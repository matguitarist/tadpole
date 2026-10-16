import SwiftUI
import TadpoleCore

/// The panel at the right: the selected mod's description and requirements.
struct ModDetails: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let mod = model.mods.first(where: { $0.id == model.selection }) {
            details(mod)
        } else {
            ContentUnavailableView("No Mod Selected", systemImage: "shippingbox", description: Text("Select a mod to see what it needs."))
        }
    }

    private func details(_ mod: PakMod) -> some View {
        let modID = model.nexusOrigin(of: mod)?.modID
        let page = modID.flatMap { model.nexusMods[$0] }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let url = page?.pictureURL ?? page?.thumbnailURL {
                    ShapedPicture(url: url)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(mod.name).font(.title2.bold()).textSelection(.enabled)
                    let status = status(of: mod)
                    Label(status.text, systemImage: "circle.fill")
                        .font(.callout)
                        .foregroundStyle(status.color)
                }
                if let update = model.update(forPak: mod.file.lastPathComponent) {
                    HStack {
                        Label("Version \(update.update.latest.version ?? update.update.latest.name) available", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
                        Spacer()
                        Button("Update") { model.install([update]) }
                    }
                    .font(.callout)
                    .padding(8)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    if let info = mod.info {
                        row("Version", info.version.description)
                    }
                    if let author = mod.info?.author.nonEmpty ?? page?.author {
                        row("Author", author)
                    }
                    if let info = mod.info {
                        row("UUID", info.uuid)
                    }
                    row("File", mod.file.lastPathComponent)
                    if let size = fileSize(mod) {
                        row("Size", size.formatted(.byteCount(style: .file)))
                    }
                    if let modID {
                        GridRow {
                            Text("Nexus").foregroundStyle(.secondary)
                            Button("#\(modID)") { model.openNexusBrowser(NexusClient.modPageURL(modID)) }
                                .buttonStyle(.link)
                                .help("Show this mod's page")
                        }
                    }
                }
                .font(.callout)

                if let description = mod.info?.description.nonEmpty ?? page?.summary?.strippingNexusMarkup.nonEmpty {
                    Text(description).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if mod.usesScriptExtender {
                    if model.scriptExtenderIsActive {
                        Label("Uses the Script Extender, which is installed. Its scripted features work as far as the macOS version supports them.", systemImage: "puzzlepiece.extension.fill")
                            .foregroundStyle(.purple)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("Uses Norbyte's Script Extender, which isn't installed. Its scripted features won't work; parts that don't need it may still work. Install the macOS version in Settings → Script Extender.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.purple)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let error = mod.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if mod.info == nil, mod.error == nil {
                    Label("No mod description inside: the game always loads this file. Move it to the Trash to stop it.", systemImage: "pin.fill")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let info = mod.info {
                    requirements(info)
                    NexusSection(mod: mod)
                }

                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([mod.file]) }
                    Button("Move to Trash…", role: .destructive) { model.trash(mod) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private func status(of mod: PakMod) -> (text: String, color: Color) {
        if mod.error != nil { return (String(localized: "Can't be read"), .orange) }
        if mod.info == nil { return (String(localized: "Always loaded"), .green) }
        if model.enabledMods.contains(where: { $0.id == mod.id }) { return (String(localized: "Loaded"), .green) }
        if model.pendingEnable.contains(mod.id) { return (String(localized: "Turns on when the game quits"), .orange) }
        return (String(localized: "Installed, not loaded"), .secondary)
    }

    private func fileSize(_ mod: PakMod) -> Int64? {
        (try? mod.file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    @ViewBuilder
    private func requirements(_ info: ModuleInfo) -> some View {
        let needed = info.dependencies.filter { !ModRules.gameModuleNames.contains($0.name) && !ModSettings.baseModuleUUIDs.contains($0.uuid) }
        if !needed.isEmpty {
            let problems = model.problems[info.uuid] ?? []
            VStack(alignment: .leading, spacing: 6) {
                Text("Requires").font(.headline)
                ForEach(needed, id: \.uuid) { dependency in
                    HStack {
                        let state = state(of: dependency, in: problems)
                        Image(systemName: state.symbol).foregroundStyle(state.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dependency.name)
                            Text(state.text).font(.caption).foregroundStyle(state.color)
                        }
                    }
                }
            }
        }
    }

    private func state(of dependency: ModuleReference, in problems: [ModRules.Problem]) -> (symbol: String, color: Color, text: String) {
        if problems.contains(.notInstalled(dependency)) {
            return ("xmark.circle.fill", .red, String(localized: "Not installed"))
        } else if problems.contains(.turnedOff(dependency)) {
            return ("power.circle", .orange, String(localized: "Installed but not loaded"))
        } else if problems.contains(.loadsAfter(dependency)) {
            return ("arrow.up.circle", .orange, String(localized: "Loads after this mod: use Order by Requirements"))
        } else if model.enabledMods.contains(where: { $0.id == dependency.uuid }) {
            return ("checkmark.circle.fill", .green, String(localized: "Loaded"))
        }
        return ("circle", .secondary, String(localized: "Turn this mod on to check"))
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// The mod's Nexus page and files (optional files included), or a way to
/// link it to Nexus.
private struct NexusSection: View {
    @Environment(AppModel.self) private var model
    let mod: PakMod
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let origin = model.nexusOrigin(of: mod) {
                linked(origin.modID)
            } else {
                Text("Nexus Mods").font(.headline)
                Text("Not linked to a Nexus mod yet. Linking shows its page and optional files here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Find on Nexus…") { model.linkSheet = mod }
            }
        }
    }

    @ViewBuilder
    private func linked(_ modID: Int) -> some View {
        let page = model.nexusMods[modID]
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Files on Nexus").font(.headline)
                if let version = page?.version, !version.isEmpty {
                    Text("Latest version: \(version)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("View on Nexus Mods") { model.openNexusBrowser(NexusClient.modPageURL(modID)) }
                Button("Reload Files") { Task { await load(modID, force: true) } }
                Divider()
                Button("Link to Another Nexus Mod…") { model.linkSheet = mod }
                Button("Unlink") { model.unlink(mod) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .task(id: modID) { await load(modID) }  // the page (picture) and files, whichever is missing
        if let files = model.nexusFiles[modID] {
            if files.contains(where: \.isCurrent) {
                NexusFileSections(modID: modID, files: files, compact: true)
            } else {
                Text("No current files on Nexus.").font(.callout).foregroundStyle(.secondary)
            }
        } else if let error {
            Text(error).font(.callout).foregroundStyle(.red)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func load(_ modID: Int, force: Bool = false) async {
        do {
            try await model.loadNexusDetails(modID, force: force)
            error = nil
        } catch {
            self.error = AppModel.describe(error)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
