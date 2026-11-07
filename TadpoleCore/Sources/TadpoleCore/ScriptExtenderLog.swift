// The Script Extender for macOS's log (~/Library/Application Support/BG3SE/
// logs, one file per game session, latest.log pointing at the newest):
// what SMAPI's log is for Stardew Valley. Lines look like
//   [2026-07-30 23:17:09.501] [INFO ] [Console] Client 0 connected
// after a header naming the version and the session.
//
// LogKit reads the lines (`parseLine`) and shows them; this type reads what
// only Tadpole needs from them: the mod lists, the game build, and how each
// mod's scripts did.

import Foundation
import LogKit

public struct ScriptExtenderLog: Sendable {
    /// One line of the log. Its source is the part of the Script Extender
    /// that wrote it (Lua, Mod, Osiris…); its code is the log's own level word.
    public typealias Entry = LogEntry

    /// Errors and warnings from one source: a mod, or else a part of the
    /// Script Extender.
    public struct ProblemGroup: Identifiable, Hashable, Sendable {
        public let source: String
        public let isMod: Bool
        public let errors: Int
        public let warnings: Int
        public let first: Entry
        public var id: String { (isMod ? "mod:" : "module:") + source }
    }

    public var version: String?
    public var session: String?
    /// The log's lines, without the header.
    public var entries: [Entry] = []
    /// From the "=== Enabled Mods ===" block.
    public var enabledMods: [String] = []
    /// Mods the Script Extender found Lua scripts in ("[SE] name"), without
    /// the ones it matched to another mod's scripts (see `misattributed`).
    public var scriptExtenderMods: [String] = []
    /// Mods the Script Extender listed with another mod's scripts: when it
    /// can't find a mod's folder by name, it falls back to the folder of a
    /// .pak it finds ("SE dir for 'DFHairPack' resolved via PAK filename:
    /// 5eSpells"), so a hair pack shows up with 5eSpells' scripts. Mod name
    /// → the mod whose scripts they really are.
    public var misattributed: [String: String] = [:]
    /// The game build when the Script Extender doesn't support it: it runs
    /// with features off ("GAME VERSION MISMATCH").
    public var unsupportedBuild: (detected: String, expected: String)?
    /// What it turned off on this build ("stats system disabled"…).
    public var disabledFeatures: [String] = []
    /// Script folders whose Lua it loaded ("Loaded from PAK:
    /// Mods/5eSpells/ScriptExtender/Lua/BootstrapServer.lua" → 5eSpells).
    public var loadedScriptFolders: Set<String> = []

    /// How a mod's scripts did in this session.
    public enum ScriptStatus: Equatable, Sendable {
        case loaded
        case errors(Int)
        case notLoaded
    }

    /// For a mod's script folders (PakMod.scriptFolders).
    public func scriptStatus(forFolders folders: [String]) -> ScriptStatus {
        let lowered = Set(folders.map { $0.lowercased() })
        let errors = entries.count { $0.level == .error && ($0.modFolder.map { lowered.contains($0.lowercased()) } ?? false) }
        if errors > 0 { return .errors(errors) }
        return loadedScriptFolders.contains { lowered.contains($0.lowercased()) } ? .loaded : .notLoaded
    }

    public init(_ text: String) {
        self.init(entries: Self.lineParser.parse(text).entries)
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self.init(String(decoding: data, as: UTF8.self))
    }

    /// Reads the facts from parsed lines. The header comes first, as one
    /// entry without a time.
    public init(entries all: [Entry]) {
        var currentBlock: String?
        var resolvedFolders: [String: String] = [:]
        entries.reserveCapacity(all.count)
        for entry in all {
            guard entry.time != nil else {
                readHeader(entry.message)
                continue
            }
            entries.append(entry)
            noteCompatibility(entry)
            let message = entry.message
            if message.hasPrefix("Loaded from PAK: "), let folder = entry.modFolder { loadedScriptFolders.insert(folder) }
            // The mod lists are logged as blocks of INFO lines.
            if message.hasPrefix("=== ") {
                currentBlock = message.contains("Enabled Mods") ? "enabled" : message.contains("SE Mods") ? "se" : nil
            } else if currentBlock == "enabled", let name = Self.listItem(message, marker: "]") {
                if !name.hasSuffix("(base game)") { enabledMods.append(name) }
            } else if currentBlock == "se", let resolved = Self.resolvedViaPak(message) {
                resolvedFolders[resolved.mod] = resolved.folder
            } else if currentBlock == "se", message.hasPrefix("  [SE] ") {
                let name = message.dropFirst(7).components(separatedBy: " (from").first ?? ""
                if !name.isEmpty, !scriptExtenderMods.contains(name) { scriptExtenderMods.append(name) }
            }
        }
        findMisattributions(resolvedFolders)
    }

    /// "=== BG3SE-macOS v0.44.0 ===" and "Session: 2026-10-16 08:00:00".
    private mutating func readHeader(_ text: String) {
        for line in text.split(separator: "\n") {
            if line.hasPrefix("=== "), line.hasSuffix(" ==="), version == nil {
                version = line.split(separator: " ").first { $0.hasPrefix("v") && $0.dropFirst().first?.isNumber == true }.map { String($0.dropFirst()) }
            } else if line.hasPrefix("Session: "), session == nil {
                session = String(line.dropFirst(9))
            }
        }
    }

    /// A mod resolved to a folder that another listed mod also uses (as its
    /// own name, or resolved the same way) got that mod's scripts by mistake.
    /// One mod alone resolved to a differently named folder ("Mod
    /// Configuration Menu" → MCM) is fine.
    mutating func findMisattributions(_ resolvedFolders: [String: String]) {
        for (mod, folder) in resolvedFolders {
            let owners = scriptExtenderMods.filter { $0.caseInsensitiveCompare(folder) == .orderedSame }
            let sharers = resolvedFolders.filter { $0.key != mod && $0.value.caseInsensitiveCompare(folder) == .orderedSame }
            if !owners.isEmpty || !sharers.isEmpty { misattributed[mod] = owners.first ?? folder }
        }
        scriptExtenderMods.removeAll { misattributed[$0] != nil }
    }

    /// "SE dir for 'DFHairPack' resolved via PAK filename: 5eSpells", for a
    /// mod whose name isn't the folder's.
    static func resolvedViaPak(_ message: String) -> (mod: String, folder: String)? {
        guard message.hasPrefix("SE dir for '"), let range = message.range(of: "' resolved via PAK filename: ") else { return nil }
        let mod = String(message[message.index(message.startIndex, offsetBy: 12)..<range.lowerBound])
        let folder = String(message[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return mod.caseInsensitiveCompare(folder) == .orderedSame ? nil : (mod, folder)
    }

    /// Features the Script Extender turns off on a game build it doesn't
    /// support, by what its log says (INFO lines and above).
    static let knownFeatures: [(match: String, name: String)] = [
        ("stats system disabled", "Stats (Ext.Stats)"),
        ("prototype manager features disabled", "Prototype managers"),
        ("Ext.StaticData in degraded mode", "Static data (Ext.StaticData)"),
        ("Level API disabled", "Level API (Ext.Level)"),
        ("localization disabled", "Localization (Ext.Loca)"),
        ("Functor hooks SKIPPED", "Spell and status functors"),
    ]

    private mutating func noteCompatibility(_ entry: Entry) {
        let message = entry.message
        // "[WARN] Detected: 4.1.1.7631656 | Expected: 4.1.1.7398727"
        if let range = message.range(of: "Detected: "), let expected = message.range(of: " | Expected: ") {
            unsupportedBuild = (String(message[range.upperBound..<expected.lowerBound]),
                                String(message[expected.upperBound...]).trimmingCharacters(in: .whitespaces))
        }
        guard entry.level >= .info else { return }
        for feature in Self.knownFeatures where message.localizedCaseInsensitiveContains(feature.match) {
            if !disabledFeatures.contains(feature.name) { disabledFeatures.append(feature.name) }
        }
    }

    // MARK: Lines

    /// The lines alone, for the app's own reads (Load Order, play reports).
    static let lineParser = LineLogParser(parseLine: parseLine, finish: tidy)

    /// The viewer's parser. `describe` turns what the log says into the
    /// header's facts and the insights, in the app's language; it runs off
    /// the main thread, once per read.
    public static func parser(
        describe: @escaping @Sendable (ScriptExtenderLog) -> (metadata: [LogMetadata], insights: [LogInsight])
    ) -> LineLogParser {
        LineLogParser(parseLine: parseLine) { document in
            tidy(&document)
            let described = describe(ScriptExtenderLog(entries: document.entries))
            document.metadata = described.metadata
            document.insights = described.insights
        }
    }

    /// "[2026-07-30 23:17:09.501] [INFO ] [Console] message". Nil for a line
    /// that continues the previous one (a stack trace) or is part of the
    /// header: LogKit keeps the header as the first entry, so a new session
    /// (with a new "Session:" line) isn't hidden by an earlier Clear.
    public static func parseLine(_ line: Substring) -> ParsedLine? {
        guard line.first == "[", let timeEnd = line.firstIndex(of: "]") else { return nil }
        let stamp = line[line.index(after: line.startIndex)..<timeEnd]
        var rest = line[line.index(after: timeEnd)...].drop { $0 == " " }
        guard rest.first == "[", let levelEnd = rest.firstIndex(of: "]") else { return nil }
        let code = rest[rest.index(after: rest.startIndex)..<levelEnd].trimmingCharacters(in: .whitespaces)
        let level: LogLevel
        switch code {
        case "DEBUG": level = .debug
        case "INFO": level = .info
        case "WARN": level = .warning
        case "ERROR": level = .error
        default: return nil
        }
        rest = rest[rest.index(after: levelEnd)...].drop { $0 == " " }
        var module = ""
        if rest.first == "[", let moduleEnd = rest.firstIndex(of: "]") {
            module = rest[rest.index(after: rest.startIndex)..<moduleEnd].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: moduleEnd)...]
        }
        let message = rest.hasPrefix(" ") ? String(rest.dropFirst()) : String(rest)
        let time = stamp.split(separator: " ").last.map(String.init) ?? String(stamp)
        // Some warnings and errors are written at INFO level with the real
        // level in the message: "[WARN] …", "[Level] WARN: …".
        var effective = level
        if level < .warning {
            if message.hasPrefix("[ERROR]") || message.contains("] ERROR: ") { effective = .error }
            else if message.hasPrefix("[WARN]") || message.contains("] WARN: ") {
                // Not the "[WARN] =====" lines framing a warning.
                if !message.dropFirst(6).allSatisfy({ $0 == "=" || $0 == " " }) { effective = .warning }
            }
        }
        return ParsedLine(time: time, level: effective, code: code, source: module, message: message)
    }

    /// The header is shown only on demand (as trace), and header lines
    /// repeated later in a file ("====", "Log file: …") aren't part of the
    /// message before them.
    static func tidy(_ document: inout LogDocument) {
        for index in document.entries.indices {
            if document.entries[index].time == nil {
                document.entries[index].level = .trace
                continue
            }
            let message = document.entries[index].message
            guard message.contains("\n") else { continue }
            let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
            let kept = [lines[0]] + lines.dropFirst().filter { !isHeaderLine($0) }
            if kept.count != lines.count { document.entries[index].message = kept.joined(separator: "\n") }
        }
    }

    static func isHeaderLine(_ line: Substring) -> Bool {
        line.hasPrefix("====") || line.hasPrefix("Log ") || line.hasPrefix("Session: ")
            || (line.hasPrefix("=== ") && line.hasSuffix(" ==="))
    }

    /// "  [3] Tav's Hairpack" → "Tav's Hairpack"
    static func listItem(_ message: String, marker: Character) -> String? {
        let trimmed = message.drop { $0 == " " }
        guard trimmed.first == "[", let end = trimmed.firstIndex(of: marker), trimmed[trimmed.index(after: trimmed.startIndex)..<end].allSatisfy(\.isNumber)
        else { return nil }
        let name = trimmed[trimmed.index(after: end)...].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    public var errorCount: Int { entries.count { $0.level == .error } }
    public var warningCount: Int { entries.count { $0.level == .warning } }

    /// Errors and warnings by mod (when the message names one) or by part,
    /// most errors first.
    public var problemGroups: [ProblemGroup] {
        var order: [String] = []
        var groups: [String: (isMod: Bool, errors: Int, warnings: Int, first: Entry)] = [:]
        for entry in entries where entry.level >= .warning {
            let mod = entry.modFolder
            let key = mod.map { "mod:" + $0 } ?? "module:" + entry.source
            if groups[key] == nil {
                order.append(key)
                groups[key] = (mod != nil, 0, 0, entry)
            }
            if entry.level >= .error { groups[key]!.errors += 1 } else { groups[key]!.warnings += 1 }
        }
        return order.compactMap { key in
            groups[key].map { ProblemGroup(source: String(key.drop { $0 != ":" }.dropFirst()), isMod: $0.isMod,
                                           errors: $0.errors, warnings: $0.warnings, first: $0.first) }
        }
        .sorted { ($0.isMod ? 0 : 1, -$0.errors, -$0.warnings) < ($1.isMod ? 0 : 1, -$1.errors, -$1.warnings) }
    }

    // MARK: Files

    public static var latestURL: URL { ScriptExtenderMac.logsFolder.appending(path: "latest.log") }
}

extension LogEntry {
    /// The mod a problem comes from, when its message names a file in
    /// one ("…/Mods/MCM/ScriptExtender/Lua/…" or "Mods/MCM/…").
    public var modFolder: String? {
        guard let range = message.range(of: "Mods/") else { return nil }
        let rest = message[range.upperBound...]
        var folder = String(rest.prefix { $0 != "/" && $0 != ")" && $0 != ":" && $0 != " " })
        if folder.lowercased().hasSuffix(".pak") { folder.removeLast(4) }
        return folder.isEmpty ? nil : folder
    }
}
