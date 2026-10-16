import SwiftUI

@main
struct TadpoleApp: App {
    @State private var model = AppModel.shared
    /// Started with the app, so it checks for updates on its schedule.
    private let appUpdater = AppUpdater.shared

    var body: some Scene {
        Window("Tadpole", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 480)
                .task {
                    AppTheme.current.apply()
                    model.load()
                    model.startWatching()
                    model.loadNexusAccount()
                }
        }
        .commands { AppCommands(model: model) }

        Window("Tadpole Help", id: HelpView.windowID) {
            HelpView()
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 900, height: 620)
        .commandsRemoved()  // opened from the Help menu, not listed under Window

        Window("Nexus Mods", id: BrowserWindow.id) {
            BrowserView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 860)
        .commandsRemoved()  // Window → Nexus Mods (⇧⌘N) opens it

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
