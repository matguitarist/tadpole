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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mod.name).font(.title2.bold()).textSelection(.enabled)
                    if let author = mod.info?.author, !author.isEmpty {
                        Text("by \(author)").foregroundStyle(.secondary)
                    }
                }
                if let description = mod.info?.description, !description.isEmpty {
                    Text(description).fixedSize(horizontal: false, vertical: true)
                }
                if mod.usesScriptExtender {
                    Label("Uses Norbyte's Script Extender, which is only available on Windows. Its scripted features won't work on a Mac; parts that don't need it may still work.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.purple)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        row("Version", info.version.description)
                        row("Folder", info.folder)
                        row("UUID", info.uuid)
                        row("File", mod.file.lastPathComponent)
                    }
                    .font(.callout)
                    requirements(info)
                }

                if mod.info != nil {
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
        HStack(spacing: 10) {
            RemotePicture(url: page?.thumbnailURL, cornerRadius: 4).frame(width: 72, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("On Nexus Mods").font(.caption).foregroundStyle(.secondary)
                Text(page?.name ?? String(localized: "Nexus mod \(modID)")).font(.headline).lineLimit(2)
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
                .task(id: modID) { await load(modID) }
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
