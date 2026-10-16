// The Script Extender for macOS's log (~/Library/Application Support/BG3SE/
// logs, one file per game session, latest.log pointing at the newest):
// what SMAPI's log is for Stardew Valley. Lines look like
//   [2026-07-30 23:17:09.501] [INFO ] [Console] Client 0 connected
// after a header naming the version and the session.

import Foundation

public struct ScriptExtenderLog: Sendable {
    public enum Level: String, CaseIterable, Comparable, Sendable {
        case debug = "DEBUG", info = "INFO", warn = "WARN", error = "ERROR"

        private var rank: Int { Self.allCases.firstIndex(of: self)! }
        public static func < (a: Level, b: Level) -> Bool { a.rank < b.rank }
    }

    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: Int          // line number
        public let time: String     // "23:17:09.501"
        public let level: Level
        public let module: String   // Lua, Mod, Osiris…
        public internal(set) var message: String

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
    public var entries: [Entry] = []
    /// From the "=== Enabled Mods ===" block.
    public var enabledMods: [String] = []
    /// Mods the Script Extender found Lua scripts in ("[SE] name").
    public var scriptExtenderMods: [String] = []

    public init(_ text: String) {
        var currentBlock: String?
        var lineNumber = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine
            if let entry = Self.parse(line, number: lineNumber) {
                entries.append(entry)
                // The mod lists are logged as blocks of INFO lines.
                let message = entry.message
                if message.hasPrefix("=== ") {
                    currentBlock = message.contains("Enabled Mods") ? "enabled" : message.contains("SE Mods") ? "se" : nil
                } else if currentBlock == "enabled", let name = Self.listItem(message, marker: "]") {
                    if !name.hasSuffix("(base game)") { enabledMods.append(name) }
                } else if currentBlock == "se", message.hasPrefix("  [SE] ") {
                    let name = message.dropFirst(7).components(separatedBy: " (from").first ?? ""
                    if !name.isEmpty, !scriptExtenderMods.contains(name) { scriptExtenderMods.append(name) }
                }
            } else if line.hasPrefix("=== "), line.hasSuffix(" ==="), version == nil {
                // "=== BG3SE-macOS v0.44.0 ==="
                version = line.split(separator: " ").first { $0.hasPrefix("v") && $0.dropFirst().first?.isNumber == true }.map { String($0.dropFirst()) }
            } else if line.hasPrefix("Session: ") {
                session = String(line.dropFirst(9))
            } else if !line.isEmpty, !line.hasPrefix("===="), !entries.isEmpty, !line.hasPrefix("Log ") {
                entries[entries.count - 1].message += "\n" + line  // a message on several lines
            }
        }
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self.init(String(decoding: data, as: UTF8.self))
    }

    /// "[2026-07-30 23:17:09.501] [INFO ] [Console] message"
    static func parse(_ line: Substring, number: Int) -> Entry? {
        guard line.first == "[", let timeEnd = line.firstIndex(of: "]") else { return nil }
        let stamp = line[line.index(after: line.startIndex)..<timeEnd]
        var rest = line[line.index(after: timeEnd)...].drop { $0 == " " }
        guard rest.first == "[", let levelEnd = rest.firstIndex(of: "]") else { return nil }
        let levelText = rest[rest.index(after: rest.startIndex)..<levelEnd].trimmingCharacters(in: .whitespaces)
        guard let level = Level(rawValue: levelText) else { return nil }
        rest = rest[rest.index(after: levelEnd)...].drop { $0 == " " }
        var module = ""
        if rest.first == "[", let moduleEnd = rest.firstIndex(of: "]") {
            module = rest[rest.index(after: rest.startIndex)..<moduleEnd].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: moduleEnd)...]
        }
        let message = rest.hasPrefix(" ") ? String(rest.dropFirst()) : String(rest)
        let time = stamp.split(separator: " ").last.map(String.init) ?? String(stamp)
        return Entry(id: number, time: time, level: level, module: module, message: message)
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
    public var warningCount: Int { entries.count { $0.level == .warn } }

    /// Errors and warnings by mod (when the message names one) or by part,
    /// most errors first.
    public var problemGroups: [ProblemGroup] {
        var order: [String] = []
        var groups: [String: (isMod: Bool, errors: Int, warnings: Int, first: Entry)] = [:]
        for entry in entries where entry.level >= .warn {
            let mod = entry.modFolder
            let key = mod.map { "mod:" + $0 } ?? "module:" + entry.module
            if groups[key] == nil {
                order.append(key)
                groups[key] = (mod != nil, 0, 0, entry)
            }
            if entry.level == .error { groups[key]!.errors += 1 } else { groups[key]!.warnings += 1 }
        }
        return order.compactMap { key in
            groups[key].map { ProblemGroup(source: String(key.drop { $0 != ":" }.dropFirst()), isMod: $0.isMod,
                                           errors: $0.errors, warnings: $0.warnings, first: $0.first) }
        }
        .sorted { ($0.isMod ? 0 : 1, -$0.errors, -$0.warnings) < ($1.isMod ? 0 : 1, -$1.errors, -$1.warnings) }
    }

    // MARK: Files

    public static var latestURL: URL { ScriptExtenderMac.logsFolder.appending(path: "latest.log") }

    /// Session logs, newest first.
    public static func sessionLogs(in folder: URL = ScriptExtenderMac.logsFolder) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "log" && $0.lastPathComponent != "latest.log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }  // bg3se_YYYY-MM-DD_HH-MM-SS.log
    }
}
