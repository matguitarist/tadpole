// The Help window (Help → Tadpole Help): short, task-based topics. Every
// paragraph is a String Catalog key, so it's translated like the rest of
// the app; **bold** marks the names of buttons and sections.

import SwiftUI

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, loadOrder, installing, nexus, scriptExtender, saves, troubleshooting, shortcuts

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gettingStarted: "Getting Started"
        case .loadOrder: "The Load Order"
        case .installing: "Installing Mods"
        case .nexus: "Nexus Mods & Collections"
        case .scriptExtender: "Script Extender on a Mac"
        case .saves: "Saves & Backups"
        case .troubleshooting: "Troubleshooting"
        case .shortcuts: "Keyboard Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: "flag"
        case .loadOrder: "list.number"
        case .installing: "square.and.arrow.down"
        case .nexus: "globe"
        case .scriptExtender: "puzzlepiece.extension"
        case .saves: "archivebox"
        case .troubleshooting: "wrench.and.screwdriver"
        case .shortcuts: "keyboard"
        }
    }
}

struct HelpView: View {
    static let windowID = "help"
    @State private var selection: HelpTopic? = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.icon).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let topic = selection ?? .gettingStarted
                    Label(topic.title, systemImage: topic.icon)
                        .font(.largeTitle.bold())
                        .padding(.bottom, 4)
                    content(for: topic)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .id(selection)  // start each topic at the top
        }
        .navigationTitle("Tadpole Help")
    }

    @ViewBuilder
    private func content(for topic: HelpTopic) -> some View {
        switch topic {
        case .gettingStarted:
            HelpText("Tadpole installs Baldur's Gate 3 mods and sets the order they load in. It works with the game's own files in **Documents/Larian Studios/Baldur's Gate 3**, so the game's mod list and Tadpole's are always the same.")
            HelpSection("Before the first mod") {
                HelpBullets([
                    "Run the game once and reach the main menu: that creates the folders Tadpole needs.",
                    "To download from Nexus Mods inside Tadpole, add your personal API key in **Settings → Nexus Mods** (⌘,).",
                ])
            }
            HelpSection("The pages") {
                HelpBullets([
                    "**Load Order** (⌘1): your mods, which ones load, and in what order.",
                    "**Updates** (⌘2): new versions of your mods on Nexus, with what changed.",
                    "**Browse Nexus** (⌘3): search Baldur's Gate 3 mods and install them.",
                    "**Collections** (⌘4): curated mod packs from Nexus.",
                    "**Saves** (⌘5): your saves, and backups of them.",
                    "**Script Extender Log** (⌘6): what the Script Extender did in your last game, and what went wrong.",
                ])
            }
            HelpSection("Play") {
                HelpText("**Play** in the toolbar (⌘L) starts the game through Steam. Quit the game before changing your mods: it rewrites its mod list when it quits, which would undo your changes.")
            }
            HelpSection("The bar at the bottom") {
                HelpText("The bar at the bottom of the window shows the game's version and the Script Extender's: green when all is well, yellow when it needs something (an update, applying again after a game update, or a release made for another game build), with a button to do it.")
            }
            HelpSection("The menu bar icon") {
                HelpText("The tadpole in the menu bar shows the game's version, how many mods load, and the number of mod updates. From it you can play, update your mods, and back up your saves. While it's shown, closing the window keeps Tadpole running so it can keep checking for updates: quit from its menu. Turn it off in **Settings → General**.")
            }

        case .loadOrder:
            HelpText("The game loads the mods listed in its load order file, from top to bottom, after its own modules. A mod in the Mods folder that isn't listed doesn't load.")
            HelpSection("Turning mods on and off") {
                HelpText("Tick a mod to add it to the end of the load order; untick it to take it out. It stays installed either way, under **Installed, Not Loaded**. Drag mods to change their order.")
            }
            HelpSection("Requirements") {
                HelpText("Mods can need other mods. A warning badge shows when a requirement is missing, turned off, or loads after the mod that needs it. **Order by Requirements** moves each requirement above the mods that need it, keeping the rest of your order.")
            }
            HelpSection("Profiles") {
                HelpText("A profile is a load order with a name: one per playthrough, one per collection… The menu at the top left of **Load Order** shows the profile in use; pick another to switch. Switching writes that profile's load order; the one you leave keeps yours, so switching back returns to exactly that list.")
                HelpText("Changes you make (turning mods on and off, the order) are kept in the profile in use. **New Profile…** copies the load order now; **New Empty Profile…** starts with every mod off. **Manage Profiles…** renames, duplicates and deletes them. Mods stay installed whatever the profile.")
                HelpText("**Import Load Order…** (in the profile menu) reads a list shared by a friend: a .json file from BG3 Mod Manager or Tadpole, or a modsettings.lsx file. It becomes a profile you switch to. **Export Load Order…** saves the profile in use as a .json file BG3 Mod Manager reads too.")
                HelpText("A profile can list mods you don't have (after deleting one, or from a friend's list): they stay in it, and Tadpole tells you which when you switch. When you install a collection, tick **In a new profile** to give it its own.")
            }
            HelpSection("Badges") {
                HelpBullets([
                    "**Update to …**: Nexus has a newer version. Click it to install the update.",
                    "**Script Extender**: the mod uses the Script Extender (see **Script Extender on a Mac**).",
                    "A warning sign: a requirement is missing, turned off, or loads too late.",
                ])
            }
            HelpSection("Other sections") {
                HelpBullets([
                    "**Always Loaded**: .pak files without a mod description. The game loads them whatever the load order says; move one to the Trash to stop it.",
                    "**Listed, but its .pak isn't in the Mods folder**: a mod you removed by hand. **Remove** takes it out of the load order.",
                ])
            }
            HelpText("Each change keeps the previous file as **modsettings.lsx.bak** next to it.")

        case .installing:
            HelpSection("From files you downloaded") {
                HelpText("Drop .pak files or archives (.zip, .7z, .rar) on the window, or use **Install Mods…** (⌘O). Tadpole copies every .pak it finds into the Mods folder and turns the new mods on at the end of the load order. A file with the same name is replaced; the old one goes to the Trash.")
            }
            HelpSection("What can't be installed") {
                HelpText("Tadpole installs mods packaged as .pak files, which is how most Baldur's Gate 3 mods come. Mods made of loose files that go into the game's own folders, and tools for Windows (.dll, .exe), aren't installed: the download list says so.")
            }
            HelpSection("Removing mods") {
                HelpText("Right-click a mod and choose **Move to Trash**. It leaves the load order too. You can restore it from the Trash in Finder.")
            }

        case .nexus:
            HelpSection("Browsing") {
                HelpText("**Browse Nexus** searches Baldur's Gate 3 mods. Open one to see its files, then **Install**. Mods split into several files (hair packs 1 to 4, for example) have **Install All** next to the section. **Open the Nexus Website** shows the full site in Tadpole's own browser, where your sign-in is remembered.")
            }
            HelpSection("Requirements") {
                HelpText("A mod's window and details list what its Nexus page requires: a green check when you have it, **View** to open one you don't. When you install a mod that needs mods you don't have, Tadpole lists them, with the author's notes, so you can install them along. Untick the ones the notes say are optional.")
            }
            HelpSection("Free and Premium accounts") {
                HelpText("Premium accounts download directly. Free accounts download through the Nexus website: Tadpole opens the file's page, you click **Slow download**, and Tadpole catches the download and installs it. With several mods, the next page opens by itself.")
                HelpText("Once a download starts, the browser closes and the download goes on in the sidebar's **Downloads** list. You can keep the browser open in **Settings → Nexus Mods**.")
                HelpText("Tadpole catches **Mod Manager Download** links only in its own browser, so it doesn't take them from Starseed or another mod manager in Safari or Chrome.")
            }
            HelpSection("Updates") {
                HelpText("Tadpole checks Nexus for new versions of the mods it downloaded, at launch and every 6 hours, and notifies you when it finds some. **Updates** lists them with what changed; **Update** or **Update All** installs them. The old .pak goes to the Trash and the mod keeps its place in the load order.")
                HelpText("Mods installed from files, or linked by hand, can't be checked: Tadpole doesn't know which version you have. Install them from Nexus once. Checking works without an API key; installing updates needs one.")
            }
            HelpSection("Mod details") {
                HelpText("Select an installed mod to see its picture from Nexus, whether it loads, its version, size and requirements, and a notice with **Update** when there's a newer version.")
                HelpText("Below, **Files on Nexus** lists every current file on its Nexus page, main and optional, with **Install** next to the ones you don't have, and **Install All** when several are missing.")
            }
            HelpSection("Collections") {
                HelpText("**Collections** lists curated mod packs. A collection shows which of its mods you already have; **Install** downloads the rest. Optional mods are only installed if you tick them.")
                HelpText("Tadpole knows which Nexus mod an installed mod comes from when it was downloaded through Tadpole. For mods you installed from files, select the mod and click **Find on Nexus…** in its details: once linked, it counts as installed in collections.")
            }

        case .scriptExtender:
            HelpText("Many Baldur's Gate 3 mods use Norbyte's **Script Extender**, which only exists for Windows. Without it, those mods install and load, but whatever they do through scripts doesn't happen: new spells may do nothing, menus may not appear.")
            HelpText("Tadpole marks those mods with a **Script Extender** badge. Mods that only change looks, items, hair, dice or text don't need it and work normally.")
            HelpSection("The macOS version") {
                HelpText("**bg3se-macos** is an independent rebuild of the Script Extender for Macs with Apple silicon. Install it in **Settings → Script Extender**: Tadpole downloads the latest release, checks it, and adds it to the game. Most of the Windows version works, not all of it, and it's unofficial: back up your saves before playing with Script Extender mods.")
                HelpText("Tadpole checks for new releases with your mod updates and lists them on the **Updates** page. Each release is made for a game build: if it isn't yours, Settings says so, and it may run with some features off until a release supports your build.")
                HelpText("Steam replaces the game's program when the game updates, which removes the Script Extender. Tadpole notices, and applies it again before you press **Play** (or click **Apply Again** on the Load Order page). **Remove** in Settings puts the game's original program back.")
                HelpText("If macOS stops Tadpole from changing the game, turn Tadpole on in **System Settings → Privacy & Security → App Management**.")
            }
            HelpSection("After a game") {
                HelpText("When the game quits, Tadpole reads the Script Extender's log. Each Script Extender mod's badge then shows how its scripts did: a green check when they loaded, red when they had errors, a gray dash when they didn't load (they load once a save is loaded).")
                HelpText("If the Script Extender logged errors, or the game crashed, a notification opens the log, and the menu bar icon's menu says so. Turn the notification off in **Settings → Script Extender**.")
                HelpText("When a release made for your game build comes out, Tadpole tells you: updating to it ends limited mode.")
            }
            HelpSection("The log") {
                HelpText("On a game build the release wasn't made for, an orange **Limited mode** banner at the top lists what's turned off. Mods listed by the Script Extender by mistake (it sometimes matches a mod to another mod's scripts) are noted and not counted.")
                HelpText("Each time the game runs with it, the Script Extender writes a log, like SMAPI's for Stardew Valley. **Script Extender Log** (⌘6) shows the latest one, updating while you play: which mods it loaded, and errors and warnings grouped by mod. Click a mod or part under **Problems** to see only its warnings and errors (**Show All** goes back); **Sessions** shows earlier games. Attach the log file (**Show in Finder**) when you report a problem to a mod's author.")
            }
            HelpText("Before you install a collection, Tadpole lists which of its mods need the Script Extender: the ones whose Nexus page names it as a requirement, and the ones that need such a mod. Without the Script Extender installed, tick **Skip Script Extender mods** to leave them out.")
            HelpText("Some authors don't list it. Once a mod is installed, Tadpole looks inside it for Script Extender scripts and marks it too.")

        case .saves:
            HelpText("**Saves** lists your saves, newest first, with the game's picture, your party and the difficulty.")
            HelpSection("Mods in a save") {
                HelpText("A save made with mods shows how many, in green when you have them all, orange when some are missing. Right-click → **Show Mods…** lists them, in the load order the save was made with; **Use This Save's Mods** makes a profile with exactly that load order and switches to it, so the save loads with the mods it needs.")
            }
            HelpSection("Backups") {
                HelpText("**Back Up All** (or right-click → **Back Up**) copies saves as .zip files to **Documents/Larian Studios/Tadpole Save Backups**. They're kept there until you delete them, even if you reinstall the game.")
                HelpText("**Restore** puts a backup back in the game. If that save still exists, Tadpole asks first, and the current version goes to the Trash.")
            }
            HelpText("Back up before trying new mods: a save made with a mod can need that mod to load. When you press **Play** and your mods changed since the last game, Tadpole backs up your latest save first (**Settings → Game** turns it off).")

        case .troubleshooting:
            HelpSection("A mod doesn't show up in the game") {
                HelpBullets([
                    "Check it's ticked in **Load Order**, and that the game was closed when you made the change.",
                    "Look for a warning badge: a missing or late requirement can stop a mod from loading.",
                    "Mods made for an older version of the game can stop working after a game update. Check the mod's Nexus page.",
                ])
            }
            HelpSection("The game reset my mods") {
                HelpText("The game can remove mods it can't load from its list. Open **Load Order**, tick them again, and check their requirements. The previous file is kept as **modsettings.lsx.bak** (**Settings → Game** shows where).")
            }
            HelpSection("A Script Extender mod doesn't work") {
                HelpBullets([
                    "Check the bar at the bottom of the window: the Script Extender must be installed, and applied again after a game update (**Apply Again**).",
                    "Open **Script Extender Log** (⌘6) after playing: errors are grouped by mod under **Problems**.",
                    "In **Limited mode**, the release wasn't made for your game build and some features are off. Wait for a release that supports it: Tadpole lists it on **Updates**.",
                ])
            }
            HelpSection("Tadpole can't change the game") {
                HelpText("Installing the Script Extender changes the game's program, which macOS only allows if you let it. Turn Tadpole on in **System Settings → Privacy & Security → App Management**, then try again.")
            }
            HelpSection("Downloads don't start") {
                HelpText("Check your API key in **Settings → Nexus Mods**. With a free account, sign in once in Tadpole's browser (**Settings → Nexus Mods → Sign In to Nexus…**).")
            }

        case .shortcuts:
            HelpShortcuts([
                ("⌘1 – ⌘6", "Load Order, Updates, Browse Nexus, Collections, Saves, Script Extender Log"),
                ("⇧⌘U", "Check for mod updates"),
                ("⌘O", "Install Mods…"),
                ("⌘R", "Reload"),
                ("⇧⌘O", "Open Mods Folder"),
                ("⇧⌘N", "Nexus Mods browser"),
                ("⌥⌘I", "Show or hide details"),
                ("⌘L", "Play Baldur's Gate 3"),
                ("⌘,", "Settings"),
                ("⌘?", "Tadpole Help"),
            ])
        }
    }
}

private struct HelpText: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text).fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            content
        }
    }
}

private struct HelpBullets: View {
    let items: [LocalizedStringKey]
    init(_ items: [LocalizedStringKey]) { self.items = items }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "•")
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct HelpShortcuts: View {
    let rows: [(keys: String, action: LocalizedStringKey)]
    init(_ rows: [(String, LocalizedStringKey)]) { self.rows = rows.map { (keys: $0.0, action: $0.1) } }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(verbatim: row.keys).font(.body.monospaced()).foregroundStyle(.secondary)
                    Text(row.action)
                }
            }
        }
    }
}
