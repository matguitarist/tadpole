// The Script Extender for macOS (github.com/tdimino/bg3se-macos), an
// independent rebuild of Norbyte's Windows-only BG3SE: its releases on
// GitHub, and installing one into the game the way its own install.sh does
// (the library next to the game's executable, the executable patched to load
// it and signed again ad hoc, the original kept as a backup).

import CryptoKit
import Foundation

public struct ScriptExtenderRelease: Codable, Hashable, Sendable {
    public let version: String       // "0.44.0"
    public let publishedAt: Date
    public let pageURL: URL
    public let notes: String
    public let zipURL: URL
    public let checksumURL: URL?

    /// Game builds the release notes name ("4.1.1.7398727"): the builds it
    /// was made and tested for.
    public var gameBuilds: [String] {
        Array(Set(notes.matches(of: #/\b\d+\.\d+\.\d+\.\d{6,}\b/#).map { String($0.output) })).sorted()
    }

    /// Whether the notes name this game build. nil: they don't name any.
    public func supports(gameBuild: String) -> Bool? {
        gameBuilds.isEmpty ? nil : gameBuilds.contains(gameBuild)
    }
}

public enum ScriptExtenderMac {
    public static let repository = "tdimino/bg3se-macos"
    public static let projectURL = URL(string: "https://github.com/\(repository)")!
    public static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
    public static let libraryName = "libbg3se.dylib"
    public static let installName = "@loader_path/libbg3se.dylib"
    /// The same name as install.sh's, so either can undo the other.
    public static let backupSuffix = ".bg3se-original"
    /// Where the Script Extender writes its log.
    /// TADPOLE_BG3SE_LOGS points at another folder (for testing).
    public static var logsFolder: URL {
        if let override = ProcessInfo.processInfo.environment["TADPOLE_BG3SE_LOGS"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "BG3SE/logs", directoryHint: .isDirectory)
    }

    public enum InstallError: LocalizedError {
        case noDownload
        case checksumMismatch
        case libraryMissing
        case gameRunning

        public var errorDescription: String? {
            switch self {
            case .noDownload: String(localized: "This release has no download for macOS.")
            case .checksumMismatch: String(localized: "The download doesn't match the release's checksum, so it wasn't installed.")
            case .libraryMissing: String(localized: "The download doesn't contain libbg3se.dylib.")
            case .gameRunning: String(localized: "Quit Baldur's Gate 3 first.")
            }
        }
    }

    // MARK: Releases

    /// The newest release on GitHub (drafts and pre-releases aren't listed
    /// as latest).
    public static func latestRelease(session: URLSession = .shared) async throws -> ScriptExtenderRelease {
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let html_url: URL
            let body: String?
            let published_at: Date
            let assets: [Asset]
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Tadpole-macOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(Release.self, from: data)
        guard let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else { throw InstallError.noDownload }
        let checksum = release.assets.first { $0.name == zip.name + ".sha256" }
        return ScriptExtenderRelease(version: version(fromTag: release.tag_name), publishedAt: release.published_at,
                                     pageURL: release.html_url, notes: release.body ?? "",
                                     zipURL: zip.browser_download_url, checksumURL: checksum?.browser_download_url)
    }

    static func version(fromTag tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Whether `version` is newer than `installed` ("0.45.0" > "0.44.1").
    public static func isNewer(_ version: String, than installed: String) -> Bool {
        version.compare(installed, options: .numeric) == .orderedDescending
    }

    /// Downloads the release, checks it against its published SHA-256, and
    /// returns its libbg3se.dylib (in a temporary folder).
    public static func download(_ release: ScriptExtenderRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let zip = try await FileDownloader.download(release.zipURL, progress: progress)
        if let checksumURL = release.checksumURL {
            let (data, _) = try await URLSession.shared.data(from: checksumURL)
            let expected = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased()
            guard let expected, try sha256(of: zip) == expected else { throw InstallError.checksumMismatch }
        }
        let folder = zip.deletingLastPathComponent().appending(path: "unpacked", directoryHint: .isDirectory)
        try ModInstaller.unpack(zip, to: folder)
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            if url.lastPathComponent == libraryName, !url.pathComponents.contains("__MACOSX") { return url }
        }
        throw InstallError.libraryMissing
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: The game

    public struct Game: Sendable {
        public let app: URL
        public init(app: URL) { self.app = app }

        var macOSFolder: URL { app.appending(path: "Contents/MacOS", directoryHint: .isDirectory) }
        public var executable: URL { macOSFolder.appending(path: "Baldur's Gate 3") }
        public var library: URL { macOSFolder.appending(path: ScriptExtenderMac.libraryName) }
        var backup: URL { macOSFolder.appending(path: "Baldur's Gate 3" + ScriptExtenderMac.backupSuffix) }

        public var build: String? {
            Bundle(url: app)?.infoDictionary?["CFBundleVersion"] as? String
        }

        public var hasLibrary: Bool { FileManager.default.fileExists(atPath: library.path(percentEncoded: false)) }

        /// The executable loads the Script Extender.
        public var isPatched: Bool {
            (try? MachOPatcher.links(executable, libraryNamed: "libbg3se")) ?? false
        }

        /// Copies the library in and patches the executable (unless it
        /// already loads it). The original executable is kept as a backup;
        /// after a game update, the stale backup is replaced.
        public func install(library source: URL) throws {
            let fm = FileManager.default
            let patched = isPatched
            if !patched, fm.fileExists(atPath: backup.path(percentEncoded: false)) {
                try fm.removeItem(at: backup)  // from before a game update
            }
            if fm.fileExists(atPath: library.path(percentEncoded: false)) { try fm.removeItem(at: library) }
            try fm.copyItem(at: source, to: library)
            guard !patched else { return }
            try replaceExecutable(keepingBackup: true) { staged in
                try MachOPatcher.addWeakLibrary(ScriptExtenderMac.installName, to: staged)
            }
        }

        /// Restores the original executable and removes the library.
        public func uninstall() throws {
            let fm = FileManager.default
            if fm.fileExists(atPath: backup.path(percentEncoded: false)), isPatched {
                try fm.removeItem(at: executable)
                try fm.moveItem(at: backup, to: executable)
            } else if isPatched {
                // No backup (installed by hand): take the command out again.
                try replaceExecutable(keepingBackup: false) { staged in
                    try MachOPatcher.removeLibrary(named: "libbg3se", from: staged)
                }
            } else if fm.fileExists(atPath: backup.path(percentEncoded: false)) {
                try fm.removeItem(at: backup)  // stale: the game was updated since
            }
            if hasLibrary { try fm.removeItem(at: library) }
            try? fm.removeItem(at: macOSFolder.appending(path: ".bg3se-patch-hash"))  // install.sh's
        }

        /// Changes a copy of the executable outside the app and signs it
        /// there, then swaps it in. Signed inside the app, codesign would
        /// seal the whole bundle (the game's data is in it: well over 100 GB).
        /// The original becomes the backup, or is deleted.
        private func replaceExecutable(keepingBackup: Bool, _ change: (URL) throws -> Void) throws {
            let fm = FileManager.default
            let temporary = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: executable, create: true)
            defer { try? fm.removeItem(at: temporary) }
            let staged = temporary.appending(path: executable.lastPathComponent)
            try fm.copyItem(at: executable, to: staged)  // a clone on APFS
            try change(staged)
            let identifier = Bundle(url: app)?.bundleIdentifier
            try Self.signAdHoc(staged, identifier: identifier)

            if keepingBackup {
                try fm.moveItem(at: executable, to: backup)
            } else {
                try fm.removeItem(at: executable)
            }
            do {
                try fm.moveItem(at: staged, to: executable)
            } catch {
                if keepingBackup { try? fm.moveItem(at: backup, to: executable) }  // put the original back
                throw error
            }
        }

        static func signAdHoc(_ file: URL, identifier: String?) throws {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/codesign")
            process.arguments = ["--force", "--sign", "-"] + (identifier.map { ["--identifier", $0] } ?? []) + [file.path(percentEncoded: false)]
            process.standardOutput = FileHandle.nullDevice
            let errors = Pipe()
            process.standardError = errors
            try process.run()
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "codesign", code: Int(process.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)])
            }
        }
    }
}
