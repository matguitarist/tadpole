// Mod updates from Nexus: for each installed .pak whose Nexus file is known,
// the newest version of that file (see NexusUpdate). Checked at launch and
// every few hours (Settings → Nexus Mods), or with Check Now. Checking uses
// the public API, so it works without an API key; updating needs one.

import AppKit
import TadpoleCore
@preconcurrency import UserNotifications

/// An update for one installed Nexus file (one or more .pak files).
struct ModUpdate: Identifiable, Equatable {
    let modID: Int
    let modName: String
    /// The installed .pak files that came from the old file.
    let paks: [String]
    let update: NexusUpdate

    var id: Int { update.latest.fileId }
}

extension AppModel {
    static let updateCheckInterval: Duration = .seconds(6 * 60 * 60)

    /// Mods that can't be checked: not linked to Nexus, or linked by hand
    /// (which file is installed isn't known).
    var uncheckableMods: [PakMod] {
        mods.filter { $0.info != nil }.filter { mod in (nexusOrigin(of: mod)?.fileID ?? 0) == 0 }
    }

    func update(forPak name: String) -> ModUpdate? {
        updates.first { $0.paks.contains(name) }
    }

    /// Checks at launch, then every few hours while the app runs.
    func startUpdateChecks() {
        guard updateCheckTask == nil else { return }
        updateCheckTask = Task {
            try? await Task.sleep(for: .seconds(3))  // after the first load
            while !Task.isCancelled {
                if UserDefaults.standard.object(forKey: Preferences.checkModUpdates) as? Bool ?? true {
                    await checkForUpdates(notify: true)
                }
                try? await Task.sleep(for: Self.updateCheckInterval)
            }
        }
    }

    func checkForUpdates(notify: Bool = false) async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        // Installed .pak files by the Nexus file they came from.
        let installed = Set(mods.map(\.file.lastPathComponent))
        var paksByFile: [NexusOrigins.Origin: [String]] = [:]
        for (pak, origin) in origins.byPak where installed.contains(pak) && origin.fileID != 0 {
            paksByFile[NexusOrigins.Origin(modID: origin.modID, fileID: origin.fileID), default: []].append(pak)
        }
        let modIDs = Set(paksByFile.keys.map(\.modID))
        let client = nexusClient

        // A few mods at a time, gently on Nexus.
        var filesByMod: [Int: [NexusFile]] = [:]
        var failures = 0
        let ids = Array(modIDs)
        for start in stride(from: 0, to: ids.count, by: 4) {
            await withTaskGroup(of: (Int, [NexusFile]?).self) { group in
                for modID in ids[start..<min(start + 4, ids.count)] {
                    group.addTask { (modID, try? await client.files(forMod: modID)) }
                }
                for await (modID, files) in group {
                    if let files { filesByMod[modID] = files } else { failures += 1 }
                }
            }
        }
        for (modID, files) in filesByMod { nexusFiles[modID] = files }

        var found: [ModUpdate] = []
        for (origin, paks) in paksByFile {
            guard let files = filesByMod[origin.modID],
                  let update = NexusUpdate.find(installedFileID: origin.fileID, in: files) else { continue }
            if nexusMods[origin.modID] == nil { nexusMods[origin.modID] = try? await client.mod(id: origin.modID) }
            let name = nexusMods[origin.modID]?.name ?? mods.first { paks.contains($0.file.lastPathComponent) }?.name ?? update.installed.name
            found.append(ModUpdate(modID: origin.modID, modName: name, paks: paks.sorted(), update: update))
        }
        found.sort { $0.modName.localizedStandardCompare($1.modName) == .orderedAscending }

        await checkScriptExtenderRelease(notify: notify)

        let previous = Set(updates.map(\.id))
        updates = found
        lastUpdateCheck = .now
        updateCheckFailed = failures > 0 && filesByMod.isEmpty && !modIDs.isEmpty
        let new = found.filter { !previous.contains($0.id) }
        if notify, !new.isEmpty { UpdateNotifications.post(new) }
    }

    /// Downloads the new version; the old .pak goes to the Trash once the new
    /// one is installed, and the mod keeps its place in the load order.
    func install(_ updates: [ModUpdate]) {
        installFromNexus(updates.map { update in
            BrowserQueueItem(modID: update.modID, fileID: update.update.latest.fileId,
                             title: "\(update.modName) \(update.update.latest.version ?? "")".trimmingCharacters(in: .whitespaces),
                             replacing: update.paks)
        })
    }

    /// After an update is installed: the old .pak files it replaces go to the
    /// Trash (unless the new one has the same name), and the update leaves
    /// the list.
    func finishUpdate(replacing old: [String], installed: [PakMod], fileID: Int) {
        let newNames = Set(installed.map(\.file.lastPathComponent))
        for name in old where !newNames.contains(name) {
            try? FileManager.default.trashItem(at: paths.modsFolder.appending(path: name), resultingItemURL: nil)
            origins.byPak[name] = nil
        }
        try? origins.save(to: Self.originsFile)
        updates.removeAll { $0.id == fileID }
        load()
    }
}

/// "3 mod updates available" in Notification Center; clicking it opens
/// the Updates page.
@MainActor
enum UpdateNotifications {
    static func post(_ updates: [ModUpdate]) {
        guard UserDefaults.standard.object(forKey: Preferences.notifyModUpdates) as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = updates.count == 1
                ? String(localized: "An update for \(updates[0].modName)")
                : String(localized: "\(updates.count) mod updates available")
            content.body = updates.map(\.modName).formatted(.list(type: .and))
            center.add(UNNotificationRequest(identifier: "mod-updates", content: content, trigger: nil))
        }
    }
}

/// Opens the Updates page when a notification is clicked.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    /// Opens what the notification is about: the log after a game, else
    /// Updates.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let target = response.notification.request.content.userInfo["open"] as? String
        await MainActor.run {
            AppModel.shared.sidebarSelection = target == "scriptExtenderLog" ? .scriptExtenderLog : .updates
            NSApp.activate()
        }
    }
}
