// A Nexus mod's files grouped like the website's Files tab (main, updates,
// optional, miscellaneous), each installed or ready to install; and the
// sheet that links an installed mod to its Nexus page.

import SwiftUI
import TadpoleCore

/// Files tab categories, worded for the user.
func nexusCategoryTitle(_ category: String) -> String {
    switch category {
    case "MAIN": String(localized: "Main Files")
    case "UPDATE": String(localized: "Updates")
    case "OPTIONAL": String(localized: "Optional Files")
    case "MISCELLANEOUS": String(localized: "Miscellaneous")
    case "OLD_VERSION": String(localized: "Old Versions")
    case "ARCHIVED": String(localized: "Archived")
    default: category.capitalized
    }
}

/// The files of one Nexus mod, by category. `compact` fits the details panel.
struct NexusFileSections: View {
    @Environment(AppModel.self) private var model
    let modID: Int
    let files: [NexusFile]
    var showOld = false
    var compact = false
    /// Called after Install (the sheet closes itself).
    var onInstall: () -> Void = {}

    var body: some View {
        let installed = Set(model.installedFiles(ofNexusMod: modID).map(\.fileID))
        let shown = files.filter { showOld || $0.isCurrent }
        // In the website's order: main files first.
        let order = Dictionary(shown.map { ($0.category, $0.categoryOrder) }, uniquingKeysWith: { first, _ in first })
        let categories = order.keys.sorted { (order[$0] ?? 99, $0) < (order[$1] ?? 99, $1) }
        ForEach(categories, id: \.self) { category in
            let inCategory = shown.filter { $0.category == category }
            // Mods split into several files (hair packs 1-4…): all at once.
            let missing = inCategory.filter { $0.isCurrent && !installed.contains($0.fileId) }
            Section {
                ForEach(inCategory) { file in
                    row(file, isInstalled: installed.contains(file.fileId))
                }
            } header: {
                HStack {
                    Text(nexusCategoryTitle(category))
                        .font(compact ? .subheadline.bold() : .headline)
                    Spacer()
                    if missing.count >= 2 {
                        Button(String(localized: "Install All (\(missing.count))")) { install(missing) }
                            .controlSize(.small)
                            .help("Install every file in this section you don't have yet")
                    }
                }
                .padding(.top, compact ? 4 : 0)
            }
        }
    }

    private func install(_ files: [NexusFile]) {
        model.installFromNexus(files.map { file in
            BrowserQueueItem(modID: modID, fileID: file.fileId, title: title(of: file))
        })
        onInstall()
    }

    private func title(of file: NexusFile) -> String {
        model.nexusMods[modID].map { "\($0.name) – \(file.name)" } ?? file.name
    }

    private func row(_ file: NexusFile, isInstalled: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name).fontWeight(.medium).lineLimit(compact ? 2 : 1)
                    if !compact, let version = file.version, !version.isEmpty {
                        Text(version).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !compact, let description = file.description, !description.isEmpty {
                    Text(description.strippingNexusMarkup).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                HStack(spacing: 8) {
                    if compact, let version = file.version, !version.isEmpty { Text(version) }
                    Text(file.uploadedAt, format: .dateTime.year().month().day())
                    if let bytes = file.byteCount { Text(bytes, format: .byteCount(style: .file)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Installed")
            } else {
                Button("Install") { install([file]) }
                .controlSize(compact ? .small : .regular)
            }
        }
        .padding(.vertical, compact ? 1 : 3)
    }
}

/// Links an installed mod to its Nexus page: suggestions from a search by
/// its name, or a pasted link or mod number.
struct LinkNexusSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mod: PakMod
    @State private var query = ""
    @State private var pasted = ""
    @State private var results: [NexusMod] = []
    @State private var isSearching = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find “\(mod.name)” on Nexus Mods").font(.title3.bold())
            Text("Linking a mod lets Tadpole show its Nexus page, its optional files and, later, its updates.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Search", text: $query, prompt: Text("Mod name"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
            Group {
                if isSearching {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    Text("No match. Try another name, or paste the mod's link below.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { result in
                        HStack(spacing: 10) {
                            RemotePicture(url: result.thumbnailURL).frame(width: 64, height: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.name).fontWeight(.medium).lineLimit(1)
                                Text([result.author, result.version].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Link") { link(result.modId) }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(height: 260)
            HStack {
                TextField("Link", text: $pasted, prompt: Text("Or paste a Nexus link or mod number"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(linkPasted)
                Button("Link", action: linkPasted)
                    .disabled(NexusClient.modID(fromLinkOrNumber: pasted) == nil)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 560)
        .task {
            query = mod.name
            await search()
        }
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await model.nexusClient.searchMods(query: query, sort: .endorsements, count: 10).items
            error = nil
        } catch {
            self.error = AppModel.describe(error)
        }
    }

    private func linkPasted() {
        if let modID = NexusClient.modID(fromLinkOrNumber: pasted) { link(modID) }
    }

    private func link(_ modID: Int) {
        model.link(mod, toNexusMod: modID)
        dismiss()
    }
}
