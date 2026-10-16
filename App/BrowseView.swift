import SwiftUI
import TadpoleCore

/// Search Baldur's Gate 3 mods on Nexus; a mod opens in a sheet with its files.
struct BrowseView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var sort = NexusSort.endorsements
    @State private var results: [NexusMod] = []
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var error: String?

    private struct SearchKey: Equatable {
        let query: String
        let sort: NexusSort
    }

    var body: some View {
        content
            .navigationTitle("Browse Nexus")
            .navigationSubtitle(totalCount > 0 ? String(localized: "\(totalCount.formatted()) mods") : "")
            .searchable(text: $query, placement: .toolbar, prompt: "Search mods")
            .onSubmit(of: .search) { submittedQuery = query }
            .toolbar {
                ToolbarItem {
                    Button { model.openNexusBrowser() } label: { Label("Open the Nexus Website", systemImage: "safari") }
                        .help("Open Nexus Mods in Tadpole's browser")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SortBar(selection: $sort, options: NexusSort.allCases, title: \.localizedTitle)
            }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { submittedQuery = query }
            }
            .task(id: SearchKey(query: submittedQuery, sort: sort)) {
                await load(reset: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let error, results.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Reach Nexus", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await load(reset: true) } }
            }
        } else if results.isEmpty && !isLoading {
            ContentUnavailableView.search(text: submittedQuery)
        } else {
            let installed = model.installedNexusModIDs
            List {
                ForEach(results) { mod in
                    Button {
                        model.nexusSheet = NexusModRequest(modID: mod.modId, preview: mod)
                    } label: {
                        NexusModRow(mod: mod, isInstalled: installed.contains(mod.modId))
                    }
                    .buttonStyle(.plain)
                }
                if isLoading || results.count < totalCount {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Load More") { Task { await load(reset: false) } }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func load(reset: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await model.nexusClient.searchMods(query: submittedQuery, sort: sort, offset: reset ? 0 : results.count)
            results = reset ? page.items : results + page.items
            totalCount = page.totalCount
            error = nil
        } catch is CancellationError {
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            self.error = AppModel.describe(error)
        }
    }
}

private struct NexusModRow: View {
    let mod: NexusMod
    let isInstalled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemotePicture(url: mod.thumbnailURL)
                .frame(width: 96, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mod.name).font(.headline).lineLimit(1)
                    if isInstalled { Badge(text: String(localized: "Installed"), color: .green) }
                }
                if let summary = mod.summary {
                    Text(summary.strippingNexusMarkup).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 12) {
                    if let author = mod.author { Text(author) }
                    if let endorsements = mod.endorsements { Label(endorsements.formatted(.number.notation(.compactName)), systemImage: "hand.thumbsup") }
                    if let downloads = mod.downloads { Label(downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// A segmented sort picker on a bar under the toolbar.
struct SortBar<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: KeyPath<Option, String>

    var body: some View {
        Picker("Sort", selection: $selection) {
            ForEach(options, id: \.self) { Text($0[keyPath: title]) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// A Nexus mod: its picture and description, and its files to install.
struct NexusModSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: NexusModRequest
    @State private var mod: NexusMod?
    @State private var showOldFiles = false
    @State private var error: String?
    @State private var requirementsPrompt: RequirementsPrompt?

    var body: some View {
        VStack(spacing: 0) {
            header.padding()
            Divider()
            fileList
            Divider()
            HStack {
                if let mod = mod ?? request.preview {
                    Button("View on Nexus Mods") {
                        model.openNexusBrowser(mod.pageURL)
                        dismiss()
                    }
                }
                Toggle("Show old files", isOn: $showOldFiles).toggleStyle(.checkbox)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 640, height: 600)
        .task { await load() }
    }

    private var header: some View {
        let shown = mod ?? request.preview
        return HStack(alignment: .top, spacing: 14) {
            RemotePicture(url: shown?.pictureURL ?? shown?.thumbnailURL, cornerRadius: 8)
                .frame(width: 200, height: 120)
            VStack(alignment: .leading, spacing: 4) {
                Text(shown?.name ?? String(localized: "Nexus mod \(request.modID)")).font(.title2.bold()).lineLimit(2)
                if let author = shown?.author { Text("by \(author)").foregroundStyle(.secondary) }
                if let summary = shown?.summary {
                    Text(summary.strippingNexusMarkup).font(.callout).lineLimit(4)
                }
                EndorseTrackButtons(modID: request.modID, version: shown?.version)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var fileList: some View {
        if let error {
            ContentUnavailableView("Couldn't Load Files", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let files = model.nexusFiles[request.modID] {
            List {
                NexusRequirementsList(modID: request.modID)
                    .padding(.vertical, 4)
                NexusFileSections(modID: request.modID, files: files, showOld: showOldFiles, onInstall: { dismiss() },
                                  onNeedsRequirements: { requirementsPrompt = $0 })
            }
            .sheet(item: $requirementsPrompt) { prompt in
                RequirementsSheet(prompt: prompt) { installed in if installed { dismiss() } }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        do {
            try await model.loadNexusDetails(request.modID)
            mod = model.nexusMods[request.modID]
            if model.nexusFiles[request.modID]?.contains(where: \.isCurrent) == false { showOldFiles = true }
        } catch {
            self.error = AppModel.describe(error)
        }
    }

}
