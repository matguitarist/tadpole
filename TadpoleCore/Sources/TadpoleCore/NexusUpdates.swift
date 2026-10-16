// Updates for mods installed from Nexus. Nexus groups the versions of a file
// (groupId): the newest current file in the installed file's group, uploaded
// after it, is its update. Each newer version's own changelog says what
// changed.

import Foundation

public struct NexusUpdate: Sendable, Hashable {
    public let installed: NexusFile
    public let latest: NexusFile
    /// The versions after the installed one, newest first.
    public let changes: [Change]

    public struct Change: Sendable, Hashable {
        public let version: String
        public let lines: [String]
    }

    /// The update for the installed file, if there's a newer version of it.
    /// Unknown files (deleted from Nexus) and files without a group have none.
    public static func find(installedFileID: Int, in files: [NexusFile]) -> NexusUpdate? {
        guard let installed = files.first(where: { $0.fileId == installedFileID }),
              let group = installed.groupId else { return nil }
        let newer = files.filter { $0.groupId == group && $0.fileId != installed.fileId && $0.date > installed.date }
        guard let latest = newer.filter(\.isCurrent).max(by: { $0.date < $1.date }) else { return nil }
        let changes = newer.filter { $0.date <= latest.date }
            .sorted { $0.date > $1.date }
            .compactMap { file -> Change? in
                let lines = (file.changelogText ?? []).map(\.strippingNexusMarkup).filter { !$0.isEmpty }
                return lines.isEmpty ? nil : Change(version: file.version ?? file.name, lines: lines)
            }
        return NexusUpdate(installed: installed, latest: latest, changes: changes)
    }
}

/// For a mod linked by hand (which Nexus file it came from isn't known):
/// which of the mod's files is probably installed.
public enum InstalledFileGuess {
    public enum Result: Equatable, Sendable {
        /// A file's version is the .pak's own version: that's the one.
        case matched(NexusFile)
        /// The newest main file uploaded before the .pak was installed.
        case guessed(NexusFile)
    }

    public static func find(version: String?, installedOn date: Date?, in files: [NexusFile]) -> Result? {
        // The mod itself: main files and their older versions, not optional
        // files (which can share the version).
        let main = files.filter { ["MAIN", "UPDATE", "OLD_VERSION", "ARCHIVED"].contains($0.category) }
        if let version, let wanted = normalized(version), wanted != "1", wanted != "0" {
            let matches = main.filter { $0.version.flatMap(normalized) == wanted }
            if let match = matches.max(by: { $0.date < $1.date }) { return .matched(match) }
        }
        guard let date else { return nil }
        // Main files only (an optional file isn't the mod itself): the newest
        // one already out when the .pak arrived.
        return main.filter { $0.uploadedAt <= date && $0.groupId != nil }.max { $0.date < $1.date }.map { .guessed($0) }
    }

    /// "v2.4.3", "2.4.3.0" → "2.4.3"; nil for empty.
    static func normalized(_ version: String) -> String? {
        var text = version.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("v") { text.removeFirst() }
        var parts = text.split(separator: ".").map(String.init)
        while parts.count > 1, parts.last.flatMap(Int.init) == 0 { parts.removeLast() }
        let result = parts.joined(separator: ".")
        return result.isEmpty ? nil : result
    }
}
