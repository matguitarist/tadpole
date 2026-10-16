import SwiftUI
import TadpoleCore

/// Browse Baldur's Gate 3 collections on Nexus.
struct CollectionsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var sort = CollectionSort.endorsements
    @State private var results: [NexusCollection] = []
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var error: String?

    private struct SearchKey: Equatable {
        let query: String
        let sort: CollectionSort
    }

    var body: some View {
        content
            .navigationTitle("Collections")
            .navigationSubtitle(totalCount > 0 ? String(localized: "\(totalCount.formatted()) collections") : "")
            .searchable(text: $query, placement: .toolbar, prompt: "Search collections")
            .onSubmit(of: .search) { submittedQuery = query }
            .safeAreaInset(edge: .top, spacing: 0) {
                SortBar(selection: $sort, options: CollectionSort.allCases, title: \.localizedTitle)
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
            List {
                ForEach(results) { collection in
                    Button {
                        model.collectionSheet = CollectionRequest(collection: collection)
                    } label: {
                        CollectionRow(collection: collection)
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
            let page = try await model.nexusClient.searchCollections(query: submittedQuery, sort: sort, offset: reset ? 0 : results.count)
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

private struct CollectionRow: View {
    let collection: NexusCollection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemotePicture(url: collection.tileImageURL)
                .frame(width: 64, height: 80)
            VStack(alignment: .leading, spacing: 3) {
                Text(collection.name).font(.headline).lineLimit(1)
                if let summary = collection.summary {
                    Text(summary.strippingNexusMarkup).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                CollectionStats(collection: collection)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct CollectionStats: View {
    let collection: NexusCollection

    var body: some View {
        HStack(spacing: 12) {
            if let author = collection.author { Text(author) }
            if let count = collection.modCount { Label(String(localized: "\(count) mods"), systemImage: "shippingbox") }
            if let size = collection.totalSize { Label(size.formatted(.byteCount(style: .file)), systemImage: "internaldrive") }
            if let endorsements = collection.endorsements { Label(endorsements.formatted(.number.notation(.compactName)), systemImage: "hand.thumbsup") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// A collection's mods, which of them are installed, and installing the rest.
struct CollectionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: CollectionRequest
    @State private var revision: CollectionRevision?
    @State private var error: String?
    @State private var selectedOptional: Set<Int> = []  // file IDs
    @AppStorage(Preferences.skipScriptExtenderMods) private var skipScriptExtender = false

    private var collection: NexusCollection { revision?.collection ?? request.collection }

    var body: some View {
        VStack(spacing: 0) {
            header.padding()
            Divider()
            content
            Divider()
            footer.padding()
        }
        .frame(width: 680, height: 640)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            RemotePicture(url: collection.tileImageURL, cornerRadius: 8)
                .frame(width: 96, height: 120)
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name).font(.title2.bold()).lineLimit(2)
                if let author = collection.author { Text("by \(author)").foregroundStyle(.secondary) }
                if let summary = collection.summary {
                    Text(summary.strippingNexusMarkup).font(.callout).lineLimit(3)
                }
                CollectionStats(collection: collection)
                scriptExtenderSummary
            }
            Spacer(minLength: 0)
        }
    }

    /// Mods that need the Script Extender: listed on Nexus, or found in
    /// their installed .pak.
    private func needsScriptExtender(_ mod: CollectionMod) -> Bool {
        mod.scriptExtender != nil || model.installedScriptExtenderModIDs.contains(mod.modID)
    }

    @ViewBuilder
    private var scriptExtenderSummary: some View {
        Group {
            if let revision {
                let count = revision.mods.filter(needsScriptExtender).count
                if count > 0, model.scriptExtenderIsActive {
                    Label(count == 1
                          ? String(localized: "1 mod needs the Script Extender. It's installed, so it should work, as far as the macOS version supports it.")
                          : String(localized: "\(count) mods need the Script Extender. It's installed, so they should work, as far as the macOS version supports them."),
                          systemImage: "puzzlepiece.extension.fill")
                        .foregroundStyle(.purple)
                } else if count > 0 {
                    Label(count == 1
                          ? String(localized: "1 mod needs Norbyte's Script Extender, which only exists on Windows: on a Mac it installs, but its scripted features don't work.")
                          : String(localized: "\(count) mods need Norbyte's Script Extender, which only exists on Windows: on a Mac they install, but their scripted features don't work."),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.purple)
                } else {
                    Label("No mod here lists the Script Extender as a requirement, so this collection should work on a Mac. A few mods use it without saying so: Tadpole marks them once they're installed.",
                          systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                }
            } else if error == nil {
                Text("Checking which mods need the Script Extender…").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            ContentUnavailableView("Couldn't Load Collection", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let revision {
            let installed = model.installedNexusModIDs
            let required = revision.mods.filter { !$0.isOptional }
            let optional = revision.mods.filter(\.isOptional)
            List {
                Section("Mods (\(required.count))") {
                    ForEach(required) { modRow($0, isInstalled: installed.contains($0.modID)) }
                }
                if !optional.isEmpty {
                    Section("Optional (\(optional.count))") {
                        ForEach(optional) { modRow($0, isInstalled: installed.contains($0.modID)) }
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func modRow(_ mod: CollectionMod, isInstalled: Bool) -> some View {
        HStack(spacing: 10) {
            if mod.isOptional {
                Toggle("", isOn: Binding(
                    get: { selectedOptional.contains(mod.fileID) },
                    set: { if $0 { selectedOptional.insert(mod.fileID) } else { selectedOptional.remove(mod.fileID) } }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(isInstalled)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(mod.modName).fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(mod.fileName)
                    if let version = mod.version, !version.isEmpty { Text(version) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if needsScriptExtender(mod) {
                Badge(text: String(localized: "Script Extender"), color: .purple)
                    .help(scriptExtenderHelp(mod))
            }
            if isInstalled {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Installed")
            }
            Button {
                model.openNexusBrowser(NexusClient.modPageURL(mod.modID))
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Show this mod's page")
        }
    }

    private func scriptExtenderHelp(_ mod: CollectionMod) -> String {
        switch mod.scriptExtender {
        case .through(let name) where model.scriptExtenderIsActive:
            String(localized: "Needs “\(name)”, which needs the Script Extender. It's installed.")
        case .direct where model.scriptExtenderIsActive:
            String(localized: "Its Nexus page lists the Script Extender as a requirement. It's installed.")
        case .through(let name):
            String(localized: "Needs “\(name)”, which needs Norbyte's Script Extender (Windows only). Its scripted features won't work on a Mac.")
        case .direct:
            String(localized: "Its Nexus page lists Norbyte's Script Extender (Windows only) as a requirement. Its scripted features won't work on a Mac.")
        case nil:
            String(localized: "This mod uses Norbyte's Script Extender, which isn't available on macOS. Its scripted features won't work.")
        }
    }

    /// Mods to download: required ones and ticked optional ones that
    /// aren't installed yet, without Script Extender ones if asked.
    private var toInstall: [CollectionMod] {
        guard let revision else { return [] }
        let installed = model.installedNexusModIDs
        return revision.mods.filter { (!$0.isOptional || selectedOptional.contains($0.fileID)) && !installed.contains($0.modID) }
            .filter { !skipScriptExtender || model.scriptExtenderIsActive || $0.scriptExtender == nil }
    }

    private var footer: some View {
        HStack {
            Button("View on Nexus Mods") {
                model.openNexusBrowser(collection.pageURL)
                dismiss()
            }
            Spacer()
            if !model.scriptExtenderIsActive, revision?.mods.contains(where: { $0.scriptExtender != nil }) == true {
                Toggle("Skip Script Extender mods", isOn: $skipScriptExtender)
                    .toggleStyle(.checkbox)
                    .help("Don't download the mods that need Norbyte's Script Extender: their scripted features can't work on a Mac.")
            }
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            let missing = toInstall
            let allInstalled = revision?.mods.allSatisfy { $0.isOptional || model.installedNexusModIDs.contains($0.modID) } ?? false
            Button(!missing.isEmpty ? String(localized: "Install \(missing.count) Mods")
                   : allInstalled ? String(localized: "Everything Is Installed") : String(localized: "Nothing to Install")) {
                model.installFromNexus(missing.map { BrowserQueueItem(modID: $0.modID, fileID: $0.fileID, title: $0.modName) })
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(missing.isEmpty)
        }
    }

    private func load() async {
        do {
            revision = try await model.nexusClient.collectionRevision(slug: request.collection.slug)
        } catch {
            self.error = AppModel.describe(error)
        }
    }
}
