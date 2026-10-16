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

    /// Before Play: when the load order changed since the last game started
    /// from Tadpole, the latest save is backed up first (a save made with
    /// different mods can stop loading). Settings → General turns it off.
    func backUpLatestSaveIfModsChanged() async {
        guard let settings else { return }
        let fingerprint = ProfileRules.fingerprint(settings.modEntries)
        defer {
            profileStore.lastPlayedMods = fingerprint
            try? profileStore.save(to: Self.profilesFile)
        }
        guard fingerprint != profileStore.lastPlayedMods,
              UserDefaults.standard.object(forKey: Preferences.backupBeforePlay) as? Bool ?? true else { return }
        let paths = paths
        do {
            let backup = try await Task.detached { () -> URL? in
                guard let latest = SaveGame.scan(paths.saves).first else { return nil }
                return try SaveBackups.backUp(latest, into: paths.saveBackups)
            }.value
            if backup != nil { lastAutoBackup = .now }
        } catch {
            show("Couldn't Back Up", String(localized: "Your latest save couldn't be backed up before playing: \(error.localizedDescription)"))
        }
        loadSaves()
    }

    /// Every save in the game, read fresh (the Saves page may not have
    /// been opened yet).
    func backUpAllSaves() {
        let paths = paths
        Task {
            let all = await Task.detached { SaveGame.scan(paths.saves) }.value
            backUp(all)
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
