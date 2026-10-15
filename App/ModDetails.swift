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
