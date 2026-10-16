// Saves: the game's save folders, and zip backups of them.

import AppKit
import TadpoleCore

extension AppModel {
    func loadSaves() {
        isLoadingSaves = true
        let paths = paths
        Task {
            let (saves, backups) = await Task.detached {
                (SaveGame.scan(paths.saves), SaveBackups.list(paths.saveBackups))
            }.value
            self.saves = saves
            self.saveBackups = backups
            isLoadingSaves = false
        }
    }

    func backUp(_ saves: [SaveGame]) {
        guard !saves.isEmpty else { return }
        let folder = paths.saveBackups
        Task {
            do {
                try await Task.detached {
                    let now = Date.now
                    for save in saves { try SaveBackups.backUp(save, into: folder, now: now) }
                }.value
            } catch {
                show("Couldn't Back Up", error.localizedDescription)
            }
            loadSaves()
        }
    }

    func restore(_ backup: SaveBackup) {
        guard !isGameRunning else {
            return show("Quit Baldur's Gate 3 First", String(localized: "Restore saves while the game isn't running, so it sees them."))
        }
        let folder = paths.saves
        Task {
            do {
                try await Task.detached { try SaveBackups.restore(backup, into: folder) }.value
            } catch {
                show("Couldn't Restore", error.localizedDescription)
            }
            loadSaves()
        }
    }

    func trash(_ saves: [SaveGame]) {
        for save in saves {
            do {
                try FileManager.default.trashItem(at: save.folder, resultingItemURL: nil)
            } catch {
                show("Couldn't Move to the Trash", error.localizedDescription)
            }
        }
        loadSaves()
    }

    func trash(_ backup: SaveBackup) {
        try? FileManager.default.trashItem(at: backup.file, resultingItemURL: nil)
        loadSaves()
    }

    func openSaveBackupsFolder() {
        try? FileManager.default.createDirectory(at: paths.saveBackups, withIntermediateDirectories: true)
        NSWorkspace.shared.open(paths.saveBackups)
    }
}
