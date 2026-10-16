// The menu bar icon (on by default, Settings → General): the game's state,
// Play, mod updates and downloads without opening the window. While it's
// shown, closing the window keeps Tadpole running so update checks go on.

import AppKit
import SwiftUI
import TadpoleCore

/// The tadpole, with the number of mod updates next to it when there are some.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.updateCount == 0 {
            Image("MenuBarIcon")
        } else {
            Label {
                Text(verbatim: "\(model.updateCount)")
            } icon: {
                Image("MenuBarIcon")
            }
            .labelStyle(.titleAndIcon)
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Status (not clickable): "Baldur's Gate 3 4.1.1 · 12 mods loaded".
        Text(statusLine)
        Button(model.gameIsRunning ? String(localized: "Baldur's Gate 3 Is Running") : String(localized: "Play Baldur's Gate 3")) {
            model.launchGame()
        }
        .disabled(model.gameIsRunning)
        if let report = model.lastPlayReport {
            Button(report.crashFile != nil ? String(localized: "The game crashed: see the log…") : String(localized: "Script Extender errors in the last game…")) {
                show(.scriptExtenderLog)
            }
        }
        if model.scriptExtenderState == .needsReapply {
            Button("Apply the Script Extender Again") { model.reapplyScriptExtender() }
                .disabled(model.gameIsRunning || model.scriptExtenderTask != nil)
        }
        Divider()

        if model.updateCount == 0 {
            Text(model.lastUpdateCheck == nil ? String(localized: "Mod updates not checked yet") : String(localized: "All mods up to date"))
        } else {
            Button(model.updateCount == 1 ? String(localized: "1 update available…") : String(localized: "\(model.updateCount) updates available…")) {
                show(.updates)
            }
            if !model.updates.isEmpty {
                Button("Update All") { model.install(model.updates) }
            }
        }
        Button(model.isCheckingUpdates ? String(localized: "Checking…") : String(localized: "Check for Mod Updates")) {
            Task { await model.checkForUpdates() }
        }
        .disabled(model.isCheckingUpdates)
        let active = model.downloads.filter { !$0.isFinished }.count
        if active > 0 {
            Button(active == 1 ? String(localized: "Downloading 1 mod…") : String(localized: "Downloading \(active) mods…")) {
                show(.loadOrder)
            }
        }
        Divider()

        Menu(model.activeProfileName.map { String(localized: "Profile: \($0)") } ?? String(localized: "Profiles")) {
            ProfileMenuItems(model: model)
        }
        .onChange(of: model.showProfiles) { _, show in if show { showMainWindow() } }
        .onChange(of: model.profileNamePrompt) { _, prompt in if prompt != nil { showMainWindow() } }
        Divider()

        Button("Browse Nexus…") { show(.browse) }
        Button("Collections…") { show(.collections) }
        Button("Back Up All Saves") {
            show(.saves)  // where the backups appear, and any error
            model.backUpAllSaves()
        }
        Button("Open Mods Folder") { model.openModsFolder() }
        Divider()

        Button("Open Tadpole") { showMainWindow() }
        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("Quit Tadpole") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        guard model.gameApp != nil || model.paths.gameHasRun else { return String(localized: "Baldur's Gate 3 not found") }
        let game = model.gameVersion.map { String(localized: "Baldur's Gate 3 \($0)") } ?? String(localized: "Baldur's Gate 3")
        let count = model.enabledMods.count
        let mods = count == 1 ? String(localized: "1 mod loaded") : String(localized: "\(count) mods loaded")
        return "\(game) · \(mods)"
    }

    private func show(_ item: SidebarItem) {
        model.sidebarSelection = item
        showMainWindow()
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// With the menu bar icon shown, closing the window keeps the app (and its
/// update checks) running.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: Preferences.showMenuBarIcon) as? Bool ?? true)
    }

    /// Clicking the Dock icon with no window open brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        true
    }
}
