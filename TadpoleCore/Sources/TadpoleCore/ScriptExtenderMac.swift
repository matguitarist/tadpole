// The Script Extender for macOS (github.com/tdimino/bg3se-macos), an
// independent rebuild of Norbyte's Windows-only BG3SE: its releases on
// GitHub, and installing one into the game the way its own install.sh does
// (the library next to the game's executable, the executable patched to load
// it and signed again ad hoc, the original kept as a backup).

import DownloadKit
import Foundation
import ProcessKit

public struct ScriptExtenderRelease: Codable, Hashable, Sendable {
    public let version: String       // "0.44.0"
    public let publishedAt: Date
    public let pageURL: URL
    public let notes: String
    public let zipURL: URL
    public let checksumURL: URL?
    /// The zip's SHA-256 when GitHub publishes its digest (releases cached
    /// before Tadpole read it have none, and use `checksumURL`).
    public var sha256: String? = nil

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
    public static let owner = "tdimino", repositoryName = "bg3se-macos"
    public static let repository = "\(owner)/\(repositoryName)"
    /// Sent with every request to GitHub.
    static let userAgent = "Tadpole-macOS"
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
    public static func latestRelease() async throws -> ScriptExtenderRelease {
        let release: GitHubRelease
        do {
            release = try await GitHubRelease.latest(owner: owner, repo: repositoryName, options: DownloadOptions(userAgent: userAgent))
        } catch is DownloadError {
            throw URLError(.badServerResponse)
        }
        return try self.release(from: release)
    }

    /// Tadpole's pick from a GitHub release: its zip, and the zip's
    /// "<name>.sha256" file or digest.
    static func release(from release: GitHubRelease) throws -> ScriptExtenderRelease {
        guard let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else { throw InstallError.noDownload }
        let checksum = release.asset(named: zip.name + ".sha256")
        return ScriptExtenderRelease(version: release.version, publishedAt: release.published ?? .now,
                                     pageURL: release.page ?? releasesURL, notes: release.notes,
                                     zipURL: zip.url, checksumURL: checksum?.url, sha256: zip.sha256)
    }

    /// Whether `version` is newer than `installed` ("0.45.0" > "0.44.1").
    public static func isNewer(_ version: String, than installed: String) -> Bool {
        ReleaseVersion.isNewer(version, than: installed)
    }

    /// Downloads the release, checks it against its published SHA-256, and
    /// returns its libbg3se.dylib (in a temporary folder).
    public static func download(_ release: ScriptExtenderRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        var expected = release.sha256
        if expected == nil, let checksumURL = release.checksumURL {
            let text = String(decoding: try await Download.data(from: checksumURL, options: DownloadOptions(userAgent: userAgent)), as: UTF8.self)
            expected = SHA256Hex.find(for: release.zipURL.lastPathComponent, in: text)
                ?? text.split(whereSeparator: \.isWhitespace).first.flatMap { SHA256Hex.normalized(String($0)) }
            guard expected != nil else { throw InstallError.checksumMismatch }
        }
        let zip: URL
        do {
            zip = try await FileDownloader.download(release.zipURL, userAgent: userAgent, sha256: expected, progress: progress)
        } catch is DownloadError {
            throw InstallError.checksumMismatch  // the only DownloadError FileDownloader passes on
        }
        let folder = zip.deletingLastPathComponent().appending(path: "unpacked", directoryHint: .isDirectory)
        try await ModInstaller.unpack(zip, to: folder)
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            if url.lastPathComponent == libraryName, !url.pathComponents.contains("__MACOSX") { return url }
        }
        throw InstallError.libraryMissing
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
            let arguments = ["--force", "--sign", "-"] + (identifier.map { ["--identifier", $0] } ?? []) + [file.path(percentEncoded: false)]
            let output = try Shell.runSync("/usr/bin/codesign", arguments, options: Shell.Options(stdout: .discard))
            guard output.succeeded else {
                throw NSError(domain: "codesign", code: Int(output.status),
                              userInfo: [NSLocalizedDescriptionKey: output.errorText.trimmingCharacters(in: .whitespacesAndNewlines)])
            }
        }
    }
}
