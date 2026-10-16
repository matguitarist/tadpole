import SwiftUI
import TadpoleCore

enum SidebarItem: Hashable {
    case loadOrder, updates, browse, collections, saves, scriptExtenderLog
}

/// The main window: sidebar and the selected page, plus the app-wide drop
/// target, sheets and alerts.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar(selection: $model.sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            Group {
                switch model.sidebarSelection ?? .loadOrder {
                case .loadOrder: LoadOrderView()
                case .updates: UpdatesView()
                case .browse: BrowseView()
                case .collections: CollectionsView()
                case .saves: SavesView()
                case .scriptExtenderLog: ScriptExtenderLogView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
        }
        .sheet(item: $model.nexusSheet) { NexusModSheet(request: $0) }
        .sheet(item: $model.collectionSheet) { CollectionSheet(request: $0) }
        .sheet(item: $model.linkSheet) { LinkNexusSheet(mod: $0) }
        .sheet(isPresented: $model.showProfiles) { ManageProfilesSheet() }
        .sheet(isPresented: $model.showSetupAssistant) { SetupAssistant() }
        // From the toolbar or menus; Manage Profiles shows its own.
        .sheet(item: Binding(get: { model.showProfiles ? nil : model.profileNamePrompt },
                             set: { model.profileNamePrompt = $0 })) { ProfileNameSheet(prompt: $0) }
        .onChange(of: model.browserRequest) { _, request in
            if request != nil { openWindow(id: BrowserWindow.id) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.install(urls)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .alert(model.message?.title ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } }),
               presenting: model.message) { _ in
            Button("OK") {}
        } message: { message in
            Text(message.body)
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Load Order", systemImage: "list.number")
                    .badge(model.enabledMods.count)
                    .tag(SidebarItem.loadOrder)
                Label("Updates", systemImage: "arrow.down.circle")
                    .badge(model.updateCount)
                    .tag(SidebarItem.updates)
            }
            Section("Get Mods") {
                Label("Browse Nexus", systemImage: "globe")
                    .tag(SidebarItem.browse)
                Label("Collections", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.collections)
            }
            Section("Game") {
                Label("Saves", systemImage: "externaldrive")
                    .tag(SidebarItem.saves)
                Label("Script Extender Log", systemImage: "doc.text.magnifyingglass")
                    .tag(SidebarItem.scriptExtenderLog)
            }
            if !model.downloads.isEmpty {
                Section {
                    ForEach(model.downloads) { DownloadRow(item: $0) }
                } header: {
                    HStack {
                        Text("Downloads")
                        Spacer()
                        if model.downloads.contains(where: \.isFinished) {
                            Button("Clear") { model.clearFinishedDownloads() }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// A picture from Nexus that fills its frame, with a placeholder.
struct RemotePicture: View {
    let url: URL?
    var cornerRadius: CGFloat = 6

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// The Nexus sort orders, worded for the user.
extension NexusSort {
    var localizedTitle: String {
        switch self {
        case .endorsements: String(localized: "Most Endorsed")
        case .downloads: String(localized: "Most Downloaded")
        case .updatedAt: String(localized: "Recently Updated")
        case .createdAt: String(localized: "Newest")
        }
    }
}

extension CollectionSort {
    var localizedTitle: String {
        switch self {
        case .endorsements: String(localized: "Most Endorsed")
        case .downloads: String(localized: "Most Downloaded")
        case .updatedAt: String(localized: "Recently Updated")
        case .createdAt: String(localized: "Newest")
        }
    }
}
