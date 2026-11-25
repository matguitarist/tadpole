import FileKit
import Foundation
import Security

/// Stores the user's personal Nexus Mods API key in the login Keychain, with
/// FileKit's `Keychain` (the same service, account and label as before, so
/// a key saved by an older Tadpole still reads).
enum Keychain {
    private static let store = FileKit.Keychain(service: "local.tadpole.nexus", label: "Tadpole – Nexus Mods API key")
    private static let account = "api-key"

    static func readNexusAPIKey() -> String? {
        store.string(for: account)
    }

    static func saveNexusAPIKey(_ key: String) throws {
        do {
            try store.set(key, for: account)
        } catch let error as FileKit.Keychain.Failure {
            let status = error.status
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? String(localized: "Keychain error \(status)"),
            ])
        }
    }

    static func deleteNexusAPIKey() {
        try? store.remove(account)
    }
}
