// The app's menus beyond macOS's standard ones: About, File → Install Mods,
// View (pages, details), Mods, Game and Help.

import AppKit
import SwiftUI
import TadpoleCore

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Tadpole") { AboutPanel.show() }
            CheckForUpdatesButton()
        }
        // The items are views: unlike a Commands body, a view body is
        // re-evaluated when the model changes, so titles and enabled states
        // stay current.
        CommandGroup(replacing: .newItem) { FileMenuItems(model: model) }
        CommandGroup(before: .sidebar) { ViewMenuItems(model: model) }
        CommandMenu("Mods") { ModsMenuItems(model: model) }
        CommandMenu("Game") { GameMenuItems(model: model) }
        CommandGroup(after: .windowArrangement) { WindowMenuItems() }
        CommandGroup(replacing: .help) { HelpMenuItems() }
    }
}

/// Tadpole › Check for Updates… (Sparkle).
private struct CheckForUpdatesButton: View {
    private let updater = AppUpdater.shared

    var body: some View {
        if updater.isConfigured {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

/// Selects a page, reopening the main window if it was closed.
@MainActor
private func showPage(_ item: SidebarItem, model: AppModel, openWindow: OpenWindowAction) {
    model.sidebarSelection = item
    openWindow(id: "main")
}

private struct FileMenuItems: View {
    let model: AppModel

    var body: some View {
        Button("Install Mods…") { model.presentInstallPanel() }
            .keyboardShortcut("o")
    }
}

private struct ViewMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private static let pages: [(item: SidebarItem, title: LocalizedStringKey)] = [
        (.loadOrder, "Load Order"), (.updates, "Updates"), (.browse, "Browse Nexus"), (.collections, "Collections"), (.saves, "Saves"),
    ]

    var body: some View {
        ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
            Button(page.title) { showPage(page.item, model: model, openWindow: openWindow) }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
        }
        Divider()
        Button(model.showInspector ? "Hide Details" : "Show Details") {
            showPage(.loadOrder, model: model, openWindow: openWindow)
            model.showInspector.toggle()
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        Divider()
    }
}

private struct ModsMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Reload") { model.load() }
            .keyboardShortcut("r")
        Button("Order by Requirements") { model.sortByDependencies() }
            .disabled(model.enabledMods.count < 2)
        Divider()
        Button("Check for Mod Updates") {
            showPage(.updates, model: model, openWindow: openWindow)
            Task { await model.checkForUpdates() }
        }
        .keyboardShortcut("u", modifiers: [.command, .shift])
        .disabled(model.isCheckingUpdates)
        Button(model.updates.isEmpty ? String(localized: "Update All") : String(localized: "Update All (\(model.updates.count))")) {
            model.install(model.updates)
        }
        .disabled(model.updates.isEmpty)
        Divider()
        Button("Browse Nexus") { showPage(.browse, model: model, openWindow: openWindow) }
        Button("Collections") { showPage(.collections, model: model, openWindow: openWindow) }
        Divider()
        Button("Open Mods Folder") { model.openModsFolder() }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        Button("Show Load Order File") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.modSettings]) }
            .disabled(!model.paths.gameHasRun)
    }
}

private struct GameMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Play Baldur's Gate 3") { model.launchGame() }
            .keyboardShortcut("l")
        Divider()
        Button("Saves") { showPage(.saves, model: model, openWindow: openWindow) }
        Button("Back Up All Saves") {
            showPage(.saves, model: model, openWindow: openWindow)
            model.backUpAllSaves()
        }
        Button("Open Saves Folder") {
            try? FileManager.default.createDirectory(at: model.paths.saves, withIntermediateDirectories: true)
            NSWorkspace.shared.open(model.paths.saves)
        }
        Button("Open Save Backups Folder") { model.openSaveBackupsFolder() }
    }
}

private struct WindowMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Nexus Mods") { openWindow(id: BrowserWindow.id) }
            .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}

private struct HelpMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Tadpole Help") { openWindow(id: HelpView.windowID) }
            .keyboardShortcut("?", modifiers: .command)
        Divider()
        Link("Baldur's Gate 3 Mods on Nexus Mods", destination: AppLinks.nexusBG3)
        Link("About the Script Extender (Windows only)", destination: AppLinks.scriptExtender)
        Divider()
        Link("Tadpole Release Notes", destination: AppLinks.releases)
    }
}
