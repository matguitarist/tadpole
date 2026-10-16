import Foundation
import Security

/// Stores the user's personal Nexus Mods API key in a file only they can
/// read (~/Library/Application Support/Tadpole/nexus-api-key, mode 600).
///
/// Why not the Keychain: an app without a paid Apple Developer ID is known to
/// the Keychain by the hash of each build, so macOS asked for the login
/// password again after every update. Keys saved by earlier versions are
/// moved out of the Keychain once.
enum NexusKeyStore {
    private static var file: URL {
        URL.applicationSupportDirectory.appending(path: "Tadpole/nexus-api-key")
    }

    static func read() -> String? {
        if let data = try? Data(contentsOf: file),
           let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        // Saved by 0.1: move it (macOS may ask one last time).
        guard let key = LegacyKeychain.read() else { return nil }
        if (try? save(key)) != nil { LegacyKeychain.delete() }
        return key
    }

    static func save(_ key: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Created private, then written: never readable by others, even briefly.
        let path = file.path(percentEncoded: false)
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        try Data(key.utf8).write(to: file)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: file)
        LegacyKeychain.delete()
    }
}

/// Where 0.1 kept the key.
private enum LegacyKeychain {
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "local.tadpole.nexus",
            kSecAttrAccount as String: "api-key",
        ]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
