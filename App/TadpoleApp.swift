import SwiftUI

@main
struct TadpoleApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Tadpole", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 480)
                .task {
                    model.load()
                    model.loadNexusAccount()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Install Mods…") { model.presentInstallPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Mods") {
                Button("Reload") { model.load() }
                    .keyboardShortcut("r")
                Button("Order by Requirements") { model.sortByDependencies() }
                    .disabled(model.enabledMods.count < 2)
                Divider()
                Button("Open Mods Folder") { model.openModsFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Game") {
                Button("Play Baldur's Gate 3") { model.launchGame() }
                    .keyboardShortcut("l")
            }
            CommandGroup(before: .sidebar) {
                Button("Load Order") { model.sidebarSelection = .loadOrder }
                    .keyboardShortcut("1")
                Button("Browse Nexus") { model.sidebarSelection = .browse }
                    .keyboardShortcut("2")
                Button("Collections") { model.sidebarSelection = .collections }
                    .keyboardShortcut("3")
                Button("Saves") { model.sidebarSelection = .saves }
                    .keyboardShortcut("4")
                Divider()
            }
            CommandGroup(after: .windowArrangement) {
                OpenNexusButton()
            }
        }

        Window("Nexus Mods", id: BrowserWindow.id) {
            BrowserView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 860)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Opens the Nexus Mods browser window (menus can't read openWindow directly).
struct OpenNexusButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Nexus Mods") { openWindow(id: BrowserWindow.id) }
            .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}
