// BG3 saves: one folder per save in PlayerProfiles/Public/Savegames/Story,
// holding <name>.lsv (an LSPK package, like a .pak) and <name>.WebP (the
// picture). The .lsv carries SaveInfo.json (the party, the area, the
// difficulty and the game version) and meta.lsf (the mods it was made with).
//
// Backups are zips of save folders, kept next to the game's folder in
// "Larian Studios/Tadpole Save Backups".

import Foundation

public struct SaveInfo: Sendable, Hashable, Decodable {
    public struct Character: Sendable, Hashable, Decodable {
        public struct Class: Sendable, Hashable, Decodable {
            public let main: String
            public let sub: String?
            enum CodingKeys: String, CodingKey { case main = "Main", sub = "Sub" }
        }
        public let origin: String?
        public let race: String?
        public let level: Int?
        public let classes: [Class]?

        enum CodingKeys: String, CodingKey {
            case origin = "Origin", race = "Race", level = "Level", classes = "Classes"
        }

        /// Your own character ("Generic") or a custom origin ("DarkUrge").
        public var isPlayerMade: Bool { origin == "Generic" || origin == "DarkUrge" }
        /// Shadowheart, Laezel… without the game's prefixes.
        public var displayOrigin: String { origin == "Laezel" ? "Lae'zel" : (origin ?? "") }
    }

    struct Party: Sendable, Hashable, Decodable {
        let characters: [Character]
        enum CodingKeys: String, CodingKey { case characters = "Characters" }
    }

    public let saveName: String?
    public let currentLevel: String?
    public let difficulty: [String]?
    public let gameVersion: String?
    private let activeParty: Party?

    /// The party with classes (summons and companions without one left out).
    public var party: [Character] { (activeParty?.characters ?? []).filter { $0.classes?.isEmpty == false } }

    enum CodingKeys: String, CodingKey {
        case saveName = "Save Name", currentLevel = "Current Level", difficulty = "Difficulty",
             gameVersion = "Game Version", activeParty = "Active Party"
    }

    /// "DifficultyMedium" → "Medium", "HonourMode" → "Honour".
    public var difficultyName: String? {
        guard let raw = difficulty?.first else { return nil }
        return raw.replacingOccurrences(of: "Difficulty", with: "").replacingOccurrences(of: "Mode", with: "")
    }
}

public struct SaveGame: Sendable, Identifiable, Hashable {
    public let folder: URL
    public let file: URL
    public let picture: URL?
    public let date: Date
    public let size: Int64
    public let info: SaveInfo?
    /// The mods the save was made with, in their load order (the game's own
    /// modules left out). nil when meta.lsf couldn't be read.
    public var mods: [ModuleShortDesc]? = nil

    public var id: URL { folder }
    /// The save's own name (the folder is "<player>-<number>__<name>").
    public var name: String { info?.saveName ?? file.deletingPathExtension().lastPathComponent }
    public var isAutosave: Bool { name.hasPrefix("AutoSave_") }
    public var isQuicksave: Bool { name.hasPrefix("QuickSave_") }

    /// Every save, newest first.
    public static func scan(_ folder: URL) -> [SaveGame] {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return folders.compactMap(read).sorted { $0.date > $1.date }
    }

    static func read(_ folder: URL) -> SaveGame? {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        guard let lsv = files.first(where: { $0.pathExtension.lowercased() == "lsv" }) else { return nil }
        let values = try? lsv.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let picture = files.first { $0.pathExtension.lowercased() == "webp" }
        var info: SaveInfo?
        var mods: [ModuleShortDesc]?
        if let pak = try? PakArchive(url: lsv) {
            if let entry = pak.entry(matching: { $0 == "SaveInfo.json" }), let data = try? pak.data(for: entry) {
                info = try? JSONDecoder().decode(SaveInfo.self, from: data)
            }
            if let entry = pak.entry(matching: { $0 == "meta.lsf" }), let data = try? pak.data(for: entry) {
                mods = try? Self.mods(inMeta: data)
            }
        }
        return SaveGame(folder: folder, file: lsv, picture: picture, date: values?.contentModificationDate ?? .distantPast,
                        size: Int64(values?.fileSize ?? 0), info: info, mods: mods)
    }

    /// meta.lsf's MetaData › ModuleSettings › Mods › ModuleShortDesc nodes.
    static func mods(inMeta data: Data) throws -> [ModuleShortDesc] {
        let document = try LSFDocument(data: data)
        return document.nodes.compactMap { node -> ModuleShortDesc? in
            guard node.name == "ModuleShortDesc", let parent = node.parent, document.nodes[parent].name == "Mods",
                  let uuid = node.string("UUID"), let name = node.string("Name") else { return nil }
            let entry = ModuleShortDesc(folder: node.string("Folder") ?? "", md5: node.string("MD5") ?? "", name: name,
                                        uuid: uuid, version64: node.integer("Version64") ?? 0)
            guard !ModSettings.baseModuleUUIDs.contains(entry.uuid), !ModRules.gameModuleNames.contains(entry.name) else { return nil }
            return entry
        }
    }
}

public struct SaveBackup: Sendable, Identifiable, Hashable {
    public let file: URL
    public let date: Date
    public let size: Int64

    public var id: URL { file }
    /// The save's name, without the date the backup adds.
    public var saveName: String {
        let base = file.deletingPathExtension().lastPathComponent
        let folder = base.replacing(/\ \d{4}-\d{2}-\d{2}\ \d{6}$/, with: "")
        return folder.split(separator: "__", maxSplits: 1).last.map(String.init) ?? folder
    }
}

public enum SaveBackups {
    /// Zips a save folder into `backups` as "<folder> <date>.zip".
    @discardableResult
    public static func backUp(_ save: SaveGame, into backups: URL, now: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let stamp = now.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                                           timeZone: .current, calendar: Calendar(identifier: .gregorian)))
        let zip = backups.appending(path: "\(save.folder.lastPathComponent) \(stamp).zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", save.folder.path(percentEncoded: false), zip.path(percentEncoded: false)])
        return zip
    }

    public static func list(_ backups: URL) -> [SaveBackup] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                                                                  options: .skipsHiddenFiles)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "zip" }.map { file in
            let values = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            return SaveBackup(file: file, date: values?.creationDate ?? .distantPast, size: Int64(values?.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }

    /// The save folder a backup holds (its name inside the zip).
    static func folderName(in backup: SaveBackup) -> String {
        backup.file.deletingPathExtension().lastPathComponent.replacing(/\ \d{4}-\d{2}-\d{2}\ \d{6}$/, with: "")
    }

    /// Whether restoring would replace a save that's there now.
    public static func wouldReplace(_ backup: SaveBackup, in saves: URL) -> Bool {
        FileManager.default.fileExists(atPath: saves.appending(path: folderName(in: backup)).path(percentEncoded: false))
    }

    /// Puts the save back. A save with the same folder goes to the Trash first.
    public static func restore(_ backup: SaveBackup, into saves: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "tadpole-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        try run("/usr/bin/ditto", ["-x", "-k", backup.file.path(percentEncoded: false), work.path(percentEncoded: false)])
        let folders = (try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        guard let folder = folders.first(where: { $0.hasDirectoryPath }) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: backup.file.path(percentEncoded: false)])
        }
        try fm.createDirectory(at: saves, withIntermediateDirectories: true)
        let destination = saves.appending(path: folder.lastPathComponent)
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.moveItem(at: folder, to: destination)
    }

    static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedFailureReasonErrorKey: "\(tool) failed (\(process.terminationStatus))"])
        }
    }
}

/// Which Nexus mod and file each installed .pak came from, so collections
/// and mod pages can tell what's installed. Kept by .pak file name.
public struct NexusOrigins: Sendable, Codable, Equatable {
    public struct Origin: Sendable, Codable, Hashable {
        public let modID: Int
        /// 0 when the mod was linked by hand: which file it came from isn't known.
        public let fileID: Int
        public let version: String?

        public init(modID: Int, fileID: Int, version: String? = nil) {
            self.modID = modID
            self.fileID = fileID
            self.version = version
        }
    }

    public var byPak: [String: Origin] = [:]

    public init() {}

    public static func load(from url: URL) -> NexusOrigins {
        (try? JSONDecoder().decode(NexusOrigins.self, from: Data(contentsOf: url))) ?? NexusOrigins()
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Nexus mods with at least one installed .pak, among `installedPaks`.
    public func installedModIDs(installedPaks: Set<String>) -> Set<Int> {
        Set(byPak.filter { installedPaks.contains($0.key) }.map(\.value.modID))
    }
}
