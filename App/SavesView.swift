import AppKit
import SwiftUI
import TadpoleCore

/// The game's saves, newest first, and their backups.
struct SavesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<URL> = []
    @State private var pendingTrash: [SaveGame] = []
    @State private var pendingRestore: SaveBackup?

    private var selectedSaves: [SaveGame] { model.saves.filter { selection.contains($0.id) } }

    var body: some View {
        content
            .navigationTitle("Saves")
            .navigationSubtitle(model.saves.isEmpty ? "" : String(localized: "\(model.saves.count) saves"))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.backUp(selectedSaves.isEmpty ? model.saves : selectedSaves)
                    } label: {
                        Label(selectedSaves.isEmpty ? "Back Up All" : "Back Up Selected", systemImage: "archivebox")
                    }
                    .help("Copy saves to “Larian Studios/Tadpole Save Backups” as .zip files")
                    .disabled(model.saves.isEmpty)
                    Button { model.openSaveBackupsFolder() } label: { Label("Show Backups in Finder", systemImage: "folder") }
                        .help("Open the folder with your save backups")
                    Button { model.loadSaves() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                        .help("Read the saves again")
                }
            }
            .task { model.loadSaves() }
            .confirmationDialog(pendingTrash.count == 1 ? String(localized: "Move “\(pendingTrash[0].name)” to the Trash?") : String(localized: "Move \(pendingTrash.count) saves to the Trash?"),
                                isPresented: Binding(get: { !pendingTrash.isEmpty }, set: { if !$0 { pendingTrash = [] } }),
                                titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive) {
                    model.trash(pendingTrash)
                    pendingTrash = []
                }
            } message: {
                Text("You can get it back from the Trash in Finder.")
            }
            .confirmationDialog(String(localized: "Replace “\(pendingRestore?.saveName ?? "")”?"),
                                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                                titleVisibility: .visible, presenting: pendingRestore) { backup in
                Button("Replace") { model.restore(backup) }
            } message: { _ in
                Text("This save is still in the game. Restoring puts the backed-up version in its place; the current one goes to the Trash.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.saves.isEmpty && model.saveBackups.isEmpty {
            if model.isLoadingSaves {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Saves Yet", systemImage: "externaldrive",
                                       description: Text("Saves appear here once you've played Baldur's Gate 3."))
            }
        } else {
            List(selection: $selection) {
                Section("In the Game") {
                    ForEach(model.saves) { save in
                        SaveRow(save: save)
                            .tag(save.id)
                            .contextMenu { saveMenu(save) }
                    }
                }
                if !model.saveBackups.isEmpty {
                    Section {
                        ForEach(model.saveBackups) { backup in
                            BackupRow(backup: backup) { restore(backup) }
                                .contextMenu {
                                    Button("Restore") { restore(backup) }
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([backup.file]) }
                                    Divider()
                                    Button("Move to Trash", role: .destructive) { model.trash(backup) }
                                }
                        }
                    } header: {
                        Text("Backups")
                    } footer: {
                        Text("Kept in “Documents/Larian Studios/Tadpole Save Backups”.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func saveMenu(_ save: SaveGame) -> some View {
        let targets = selection.contains(save.id) ? selectedSaves : [save]
        Button(targets.count == 1 ? String(localized: "Back Up") : String(localized: "Back Up \(targets.count) Saves")) { model.backUp(targets) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.folder)) }
        Divider()
        Button("Move to Trash…", role: .destructive) { pendingTrash = targets }
    }

    private func restore(_ backup: SaveBackup) {
        if SaveBackups.wouldReplace(backup, in: model.paths.saves) {
            pendingRestore = backup
        } else {
            model.restore(backup)
        }
    }
}

private struct SaveRow: View {
    let save: SaveGame
    @State private var picture: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let picture {
                    Image(nsImage: picture).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(save.name).font(.headline).lineLimit(1)
                    if save.isAutosave { Badge(text: String(localized: "Autosave"), color: .secondary) }
                    if save.isQuicksave { Badge(text: String(localized: "Quicksave"), color: .secondary) }
                    if let difficulty = save.info?.difficultyName { Badge(text: Self.difficultyTitle(difficulty), color: .accentColor) }
                }
                Text(save.date, format: .dateTime.weekday().day().month().year().hour().minute())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let party = save.info?.party, !party.isEmpty {
                    Text(party.map(describe).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Text(save.size, format: .byteCount(style: .file))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .help(save.info?.gameVersion.map { String(localized: "Game version \($0)") } ?? "")
        .task(id: save.picture) {
            guard let url = save.picture else { return }
            picture = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }

    /// The game's class names, in the app's language.
    static func classTitle(_ name: String) -> String {
        switch name {
        case "Barbarian": String(localized: "Barbarian")
        case "Bard": String(localized: "Bard")
        case "Cleric": String(localized: "Cleric")
        case "Druid": String(localized: "Druid")
        case "Fighter": String(localized: "Fighter")
        case "Monk": String(localized: "Monk")
        case "Paladin": String(localized: "Paladin")
        case "Ranger": String(localized: "Ranger")
        case "Rogue": String(localized: "Rogue")
        case "Sorcerer": String(localized: "Sorcerer")
        case "Warlock": String(localized: "Warlock")
        case "Wizard": String(localized: "Wizard")
        default: name  // classes added by mods
        }
    }

    /// The names the game shows for its difficulties.
    static func difficultyTitle(_ name: String) -> String {
        switch name {
        case "Easy": String(localized: "Explorer")
        case "Medium": String(localized: "Balanced")
        case "Hard": String(localized: "Tactician")
        case "Honour": String(localized: "Honour")
        default: name
        }
    }

    /// "Shadowheart · Cleric 3", or "Wizard 1" for your own character.
    private func describe(_ character: SaveInfo.Character) -> String {
        let classes = (character.classes ?? []).map { Self.classTitle($0.main) }.joined(separator: "/")
        let level = character.level.map { " \($0)" } ?? ""
        return character.isPlayerMade ? "\(classes)\(level)" : "\(character.displayOrigin) (\(classes)\(level))"
    }
}

private struct BackupRow: View {
    let backup: SaveBackup
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox").foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(backup.saveName).lineLimit(1)
                Text(backup.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(backup.size, format: .byteCount(style: .file))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Restore", action: restore)
        }
    }
}
