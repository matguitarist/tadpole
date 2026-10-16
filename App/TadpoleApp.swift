import SwiftUI
import UserNotifications

@main
struct TadpoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true
    /// Started with the app, so it checks for updates on its schedule.
    private let appUpdater = AppUpdater.shared

    var body: some Scene {
        Window("Tadpole", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 480)
                .task {
                    // Once: the window can be closed and reopened while
                    // the menu bar icon keeps the app running.
                    guard !model.hasStarted else { return model.load() }
                    model.hasStarted = true
                    AppTheme.current.apply()
                    model.load()
                    model.startWatching()
                    model.refreshScriptExtenderState()
                    Task { await model.refreshScriptLog() }
                    model.loadNexusAccount()
                    UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
                    model.startUpdateChecks()
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

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarContent()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
