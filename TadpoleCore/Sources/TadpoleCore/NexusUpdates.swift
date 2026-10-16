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
