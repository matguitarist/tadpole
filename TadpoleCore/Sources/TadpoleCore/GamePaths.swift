// Where BG3 keeps its mods and settings on macOS, and the game itself.

import Foundation

public struct GamePaths: Sendable {
    /// ~/Documents/Larian Studios/Baldur's Gate 3
    public var documents: URL

    /// TADPOLE_BG3_DOCUMENTS points the app at another folder (for testing
    /// without touching the real one).
    public init(home: URL = .homeDirectory) {
        if let override = ProcessInfo.processInfo.environment["TADPOLE_BG3_DOCUMENTS"], !override.isEmpty {
            documents = URL(filePath: override, directoryHint: .isDirectory)
        } else {
            documents = home.appending(path: "Documents/Larian Studios/Baldur's Gate 3", directoryHint: .isDirectory)
        }
    }

    public init(documents: URL) {
        self.documents = documents
    }

    public var modsFolder: URL { documents.appending(path: "Mods", directoryHint: .isDirectory) }
    public var modSettings: URL { documents.appending(path: "PlayerProfiles/Public/modsettings.lsx") }
    public var saves: URL { documents.appending(path: "PlayerProfiles/Public/Savegames/Story", directoryHint: .isDirectory) }
    /// Next to the game's folder, so they survive reinstalling the game.
    public var saveBackups: URL {
        documents.deletingLastPathComponent().appending(path: "Tadpole Save Backups", directoryHint: .isDirectory)
    }

    /// The folder exists once the game has been run.
    public var gameHasRun: Bool {
        FileManager.default.fileExists(atPath: modSettings.path(percentEncoded: false))
    }

    public static let steamAppID = "1086940"
    /// The Mac game's bundle id (Steam build 4.1.1, Patch 8).
    public static let bundleIdentifier = "com.larian.bg3"
}
