import SwiftUI
import TadpoleCore

/// The mods in the Mods folder and the order they load in.
struct LoadOrderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.gameIsRunning || !model.pendingEnable.isEmpty {
                    GameRunningBanner()
                } else if model.scriptExtenderState == .needsReapply {
                    ScriptExtenderBanner()
                }
            }
            .navigationTitle("Load Order")
            .navigationSubtitle(subtitle)
            .searchable(text: $model.loadOrderFilter, placement: .toolbar, prompt: Text("Filter by name or author"))
            .toolbar { toolbar }
            .inspector(isPresented: $model.showInspector) {
                ModDetails()
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
    }

    private var subtitle: String {
        let on = model.enabledMods.count
        guard !model.mods.isEmpty else { return "" }
        let installed = model.mods.count == 1 ? String(localized: "1 mod") : String(localized: "\(model.mods.count) mods")
        let loaded = on == 1 ? String(localized: "1 loaded") : on == 0 ? String(localized: "None loaded") : String(localized: "\(on) loaded")
        return "\(installed) · \(loaded)"
    }

    @ViewBuilder
    private var content: some View {
        switch model.blocker {
        case .gameNeverRan:
            ContentUnavailableView {
                Label("Run Baldur's Gate 3 Once", systemImage: "gamecontroller")
            } description: {
                Text("Tadpole manages the mods in “Documents/Larian Studios/Baldur's Gate 3”. The game creates that folder the first time it runs: start it, reach the main menu, quit, then come back.")
            } actions: {
                Button("Play Baldur's Gate 3") { model.launchGame() }
                    .buttonStyle(.borderedProminent)
                Button("Check Again") { model.load() }
            }
        case .unreadableSettings(let detail):
            ContentUnavailableView {
                Label("Can't Read the Load Order", systemImage: "exclamationmark.triangle")
            } description: {
                Text(detail)
            } actions: {
                Button("Check Again") { model.load() }
            }
        case nil:
            if model.mods.isEmpty && model.loadOrder.isEmpty {
                ContentUnavailableView {
                    Label("No Mods Yet", systemImage: "shippingbox")
                } description: {
                    Text("Find mods on Nexus Mods, or drop .pak files and archives (.zip, .7z, .rar) on this window.")
                } actions: {
                    Button("Browse Nexus Mods") { model.sidebarSelection = .browse }
                        .buttonStyle(.borderedProminent)
                    Button("Install Mods…") { model.presentInstallPanel() }
                }
            } else {
                ModList()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ProfileMenu()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isInstalling {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    model.presentInstallPanel()
                } label: {
                    Label("Install Mods", systemImage: "square.and.arrow.down")
                }
                .help("Install .pak files or archives (or drop them on the window)")
            }
            Button {
                model.openModsFolder()
            } label: {
                Label("Open Mods Folder", systemImage: "folder")
            }
            .help("Open the Mods folder in Finder")
            Button {
                model.load()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Read the Mods folder and the load order again")
            Button {
                model.launchGame()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .help("Launch Baldur's Gate 3 through Steam")
        }
        ToolbarItem {
            Button {
                model.showInspector.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help("Show or hide mod details")
        }
    }
}

private struct ModList: View {
    @Environment(AppModel.self) private var model

    private var query: String { model.loadOrderFilter.trimmingCharacters(in: .whitespaces) }
    private var isFiltering: Bool { !query.isEmpty }

    private func matches(_ mod: PakMod) -> Bool {
        guard isFiltering else { return true }
        return mod.name.localizedCaseInsensitiveContains(query) || (mod.info?.author.localizedCaseInsensitiveContains(query) ?? false)
            || mod.file.lastPathComponent.localizedCaseInsensitiveContains(query)
    }

    private func matches(_ row: AppModel.LoadOrderEntry) -> Bool {
        if let mod = row.mod { return matches(mod) }
        return !isFiltering || row.entry.name.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        @Bindable var model = model
        let problems = model.problems
        List(selection: $model.selection) {
            let duplicates = model.duplicates
            if !duplicates.isEmpty {
                Section {
                    ForEach(duplicates.keys.sorted(), id: \.self) { uuid in
                        let copies = duplicates[uuid] ?? []
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(copies.first?.name ?? uuid).fontWeight(.medium)
                                Text(copies.map { mod in
                                    let version = mod.info.map { $0.version.description } ?? ""
                                    return "\(mod.file.lastPathComponent) (\(version))"
                                }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Keep Newest") { model.keepNewest(copies) }
                                .help("Keep the copy with the highest version and move the others to the Trash")
                        }
                        .contextMenu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(copies.map(\.file)) }
                        }
                    }
                    ListNote(text: Text("The game loads only one copy of a mod, and it may not be the newest one."))
                } header: {
                    Label("Installed Twice", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(Array(model.loadOrder.enumerated()).filter { matches($0.element) }, id: \.element.id) { index, row in
                    if let mod = row.mod {
                        ModRow(mod: mod, position: index + 1, isOn: true, problems: problems[row.id] ?? [])
                            .tag(mod.id)
                    } else {
                        MissingRow(entry: row.entry, position: index + 1)
                            .tag(row.id)
                    }
                }
                // Moving rows of a filtered list would move the wrong ones.
                .onMove(perform: isFiltering ? nil : { model.move(fromOffsets: $0, toOffset: $1) })
                ListNote(text: Text("Mods load from top to bottom; drag to reorder."))
            } header: {
                HStack {
                    Text("Load Order")
                    Spacer()
                    if model.enabledMods.count > 1 {
                        Button("Order by Requirements") { model.sortByDependencies() }
                            .buttonStyle(.link)
                            .font(.caption)
                            .help("Move each mod's requirements before it, keeping the rest of the order")
                    }
                }
            }
            if !model.disabledMods.isEmpty {
                Section("Installed, Not Loaded") {
                    ForEach(model.disabledMods.filter { matches($0) }) { mod in
                        ModRow(mod: mod, position: nil, isOn: false, problems: []).tag(mod.id)
                    }
                }
            }
            if !model.overrideMods.isEmpty {
                Section {
                    ForEach(model.overrideMods.filter { matches($0) }) { mod in
                        ModRow(mod: mod, position: nil, isOn: nil, problems: []).tag(mod.id)
                    }
                    ListNote(text: Text("No mod description inside: the game always loads these. Move one to the Trash to stop it."))
                } header: {
                    Text("Always Loaded")
                }
            }
            let subfolders = model.modsSubfolders
            if !subfolders.isEmpty {
                Section {
                    ForEach(subfolders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            Text(verbatim: folder.lastPathComponent)
                            Spacer()
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        }
                    }
                    ListNote(text: Text("Folders here can make the game reset your load order. Move their .pak files out, then the folders away."))
                } header: {
                    Label("Folders in the Mods Folder", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if !model.unreadableMods.isEmpty {
                Section("Can't Be Read") {
                    ForEach(model.unreadableMods) { mod in
                        ModRow(mod: mod, position: nil, isOn: nil, problems: []).tag(mod.id)
                    }
                }
            }
        }
    }
}

private struct ModRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.showModPictures) private var showModPictures = true
    let mod: PakMod
    let position: Int?
    /// nil: can't be turned on or off.
    let isOn: Bool?
    let problems: [ModRules.Problem]

    var body: some View {
        HStack(spacing: 10) {
            if let isOn {
                Toggle("", isOn: Binding(get: { isOn }, set: { model.setEnabled(mod, $0) }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            } else {
                Image(systemName: mod.error == nil ? "pin.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(mod.error == nil ? Color.secondary : Color.orange)
                    .frame(width: 16)
            }
            if let position {
                Text("\(position)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            }
            if showModPictures {
                ModThumbnail(url: model.nexusOrigin(of: mod).flatMap { model.nexusMods[$0.modID]?.thumbnailURL })
                    .frame(width: 48, height: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(mod.name).fontWeight(.medium)
                    .lineLimit(2)
                    .help(mod.name)
                // One line for the small print, so a narrow list keeps the name readable.
                HStack(spacing: 6) {
                    if let version = mod.info?.version, version.packed != 0 {
                        Text(version.description).fixedSize()
                    }
                    if let author = mod.info?.author, !author.isEmpty {
                        Text(author).lineLimit(1).help(author)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let error = mod.error {
                    Text(error).font(.caption).foregroundStyle(.orange).lineLimit(1)
                }
                if hasBadges {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) { badges }
                        VStack(alignment: .leading, spacing: 2) { badges }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([mod.file]) }
            Button("Move to Trash", role: .destructive) { model.trash(mod) }
        }
    }

    private var hasBadges: Bool {
        model.isFromModIO(mod) || mod.usesScriptExtender || !problems.isEmpty
            || model.update(forPak: mod.file.lastPathComponent) != nil
    }

    @ViewBuilder
    private var badges: some View {
        if model.isFromModIO(mod) {
            Badge(text: "mod.io", color: .teal)
                .help("Installed by the game's own mod manager (mod.io). Update or remove it there: the game manages its file.")
        }
        if mod.usesScriptExtender {
            ScriptExtenderBadge(mod: mod)
        }
        if let update = model.update(forPak: mod.file.lastPathComponent) {
            Button {
                model.install([update])
            } label: {
                Badge(text: String(localized: "Update to \(update.update.latest.version ?? "")"), color: .blue)
            }
            .buttonStyle(.plain)
            .help("Download and install the new version from Nexus")
        }
        if !problems.isEmpty {
            Badge(text: problems.count == 1 ? String(localized: "1 requirement issue") : String(localized: "\(problems.count) requirement issues"), color: .orange)
        }
    }
}

private struct MissingRow: View {
    @Environment(AppModel.self) private var model
    let entry: ModuleShortDesc
    let position: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.red).frame(width: 16)
            Text("\(position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name.isEmpty ? entry.uuid : entry.name).fontWeight(.medium)
                Text("Listed, but its .pak isn't in the Mods folder").font(.caption).foregroundStyle(.red)
            }
            Spacer()
            Button("Remove") { model.remove(entry) }
                .help("Take it out of the load order")
        }
        .padding(.vertical, 2)
    }
}

/// "Script Extender", with how its scripts did in the last game: loaded
/// (check), errors (red), or not loaded (gray dash).
private struct ScriptExtenderBadge: View {
    @Environment(AppModel.self) private var model
    let mod: PakMod

    var body: some View {
        let status = model.scriptExtenderIsActive ? model.scriptStatus(of: mod) : nil
        HStack(spacing: 3) {
            switch status {
            case .loaded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .errors: Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
            case .notLoaded: Image(systemName: "minus.circle").foregroundStyle(.secondary)
            case nil: EmptyView()
            }
            Badge(text: String(localized: "Script Extender"), color: .purple)
        }
        .font(.caption2)
        .help(help(status))
    }

    private func help(_ status: ScriptExtenderLog.ScriptStatus?) -> String {
        guard model.scriptExtenderIsActive else {
            return String(localized: "This mod uses Norbyte's Script Extender, which isn't installed. Its scripted features won't work: install the macOS version in Settings → Script Extender.")
        }
        switch status {
        case .loaded: return String(localized: "Its scripts loaded in your last game.")
        case .errors(let count):
            return count == 1 ? String(localized: "Its scripts had 1 error in your last game: see Script Extender Log.")
                              : String(localized: "Its scripts had \(count) errors in your last game: see Script Extender Log.")
        case .notLoaded: return String(localized: "Its scripts didn't load in your last game. They load once a save is loaded; if you did, see Script Extender Log.")
        case nil: return String(localized: "This mod uses the Script Extender, which is installed. Its scripted features work as far as the macOS version supports them.")
        }
    }
}

/// A note at the end of a list section. A section footer stays on one line
/// on macOS and cuts its text off; a row wraps.
struct ListNote: View {
    let text: Text

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .listRowSeparator(.hidden)
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// The game was updated, which removed the Script Extender from it.
private struct ScriptExtenderBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 1) {
                Text("The game was updated").font(.headline)
                Text("The update removed the Script Extender. Tadpole applies it again when you press Play, or now.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.scriptExtenderTask != nil {
                ProgressView().controlSize(.small)
            } else {
                Button("Apply Again") { model.reapplyScriptExtender() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The game is running (changes to the load order wait), or mods are
/// waiting to be turned on once it quits.
private struct GameRunningBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.gameIsRunning ? "Baldur's Gate 3 is running" : "Mods are waiting to be turned on")
                    .font(.headline)
                if model.pendingEnable.isEmpty {
                    Text("Quit the game before changing the load order: it rewrites its mod list when it quits.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("\(model.pendingEnable.count) new mods will be turned on when you quit the game.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
