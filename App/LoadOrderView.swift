import SwiftUI
import TadpoleCore

/// The mods in the Mods folder and the order they load in.
struct LoadOrderView: View {
    @Environment(AppModel.self) private var model
    @State private var showDetails = true

    var body: some View {
        @Bindable var model = model
        content
            .navigationTitle("Load Order")
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .inspector(isPresented: $showDetails) {
                ModDetails()
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
    }

    private var subtitle: String {
        let on = model.enabledMods.count
        return model.mods.isEmpty ? "" : String(localized: "\(model.mods.count) mods · \(on) loaded")
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
                showDetails.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help("Show or hide mod details")
        }
    }
}

private struct ModList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let problems = model.problems
        List(selection: $model.selection) {
            Section {
                ForEach(Array(model.loadOrder.enumerated()), id: \.element.id) { index, row in
                    if let mod = row.mod {
                        ModRow(mod: mod, position: index + 1, isOn: true, problems: problems[row.id] ?? [])
                            .tag(mod.id)
                    } else {
                        MissingRow(entry: row.entry, position: index + 1)
                            .tag(row.id)
                    }
                }
                .onMove { model.move(fromOffsets: $0, toOffset: $1) }
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
            } footer: {
                Text("Mods load from top to bottom; drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.disabledMods.isEmpty {
                Section("Installed, Not Loaded") {
                    ForEach(model.disabledMods) { mod in
                        ModRow(mod: mod, position: nil, isOn: false, problems: []).tag(mod.id)
                    }
                }
            }
            if !model.overrideMods.isEmpty {
                Section {
                    ForEach(model.overrideMods) { mod in
                        ModRow(mod: mod, position: nil, isOn: nil, problems: []).tag(mod.id)
                    }
                } header: {
                    Text("Always Loaded")
                } footer: {
                    Text("No mod description inside: the game always loads these. Move one to the Trash to stop it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(mod.name).fontWeight(.medium)
                    if let version = mod.info?.version, version.packed != 0 {
                        Text(version.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let author = mod.info?.author, !author.isEmpty {
                    Text(author).font(.caption).foregroundStyle(.secondary)
                } else if let error = mod.error {
                    Text(error).font(.caption).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Spacer()
            if mod.usesScriptExtender {
                Badge(text: String(localized: "Script Extender"), color: .purple)
                    .help("This mod uses Norbyte's Script Extender, which isn't available on macOS. Its scripted features won't work.")
            }
            if !problems.isEmpty {
                Badge(text: problems.count == 1 ? String(localized: "1 requirement issue") : String(localized: "\(problems.count) requirement issues"), color: .orange)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([mod.file]) }
            Button("Move to Trash", role: .destructive) { model.trash(mod) }
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

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
