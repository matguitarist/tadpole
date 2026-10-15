import SwiftUI

@main
struct TadpoleApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Tadpole", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 480)
                .task {
                    model.load()
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
        }
    }
}
