// A Nexus mod's requirements: the list in the mod window and the details
// panel, and the window that asks which missing ones to install along.

import SwiftUI
import TadpoleCore

/// What a mod's Nexus page requires, each installed or not.
struct NexusRequirementsList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let modID: Int
    var compact = false

    /// Loaded with the mod's page and files (loadNexusDetails).
    var body: some View {
        if let requirements = model.nexusRequirements[modID], !requirements.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                Text("Requires on Nexus")
                    .font(compact ? .subheadline.bold() : .headline)
                ForEach(requirements, id: \.self) { row($0) }
            }
        }
    }

    private func row(_ requirement: NexusRequirement) -> some View {
        HStack(alignment: .top, spacing: 8) {
            icon(requirement)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(requirement.modName ?? requirement.url ?? "")
                    .lineLimit(2)
                if let notes = requirement.notes?.strippingNexusMarkup, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(compact ? 2 : 3)
                }
            }
            Spacer(minLength: 4)
            action(requirement)
                .controlSize(.small)
        }
        .font(compact ? .callout : .body)
    }

    @ViewBuilder
    private func icon(_ requirement: NexusRequirement) -> some View {
        if requirement.isScriptExtender {
            Image(systemName: model.scriptExtenderIsActive ? "checkmark.circle.fill" : "puzzlepiece.extension")
                .foregroundStyle(model.scriptExtenderIsActive ? .green : .purple)
        } else if requirement.nexusModID == nil {
            Image(systemName: "link").foregroundStyle(.secondary)
        } else if model.isInstalled(requirement) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "xmark.circle").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func action(_ requirement: NexusRequirement) -> some View {
        if requirement.isScriptExtender {
            if !model.scriptExtenderIsActive {
                Button("Install…") {
                    UserDefaults.standard.set("scriptExtender", forKey: Preferences.settingsTab)
                    openSettings()
                }
            }
        } else if let id = requirement.nexusModID {
            if !model.isInstalled(requirement) {
                Button("View") { model.nexusSheet = NexusModRequest(modID: id) }
                    .help("Open this mod to install it")
            }
        } else if let url = requirement.url.flatMap(URL.init(string:)) {
            Link("Open", destination: url)
        }
    }
}

/// "“5e Spells” needs other mods": the missing ones, ticked, with the
/// author's notes (some are only needed for part of the mod).
struct RequirementsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    let prompt: RequirementsPrompt
    /// Called with whether anything was installed.
    var onDone: (Bool) -> Void = { _ in }
    @State private var chosen: Set<Int> = []
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("“\(prompt.modName)” needs other mods").font(.title3.bold())
            if !prompt.plan.missing.isEmpty {
                Text("Its Nexus page lists these, and you don't have them. Read the notes: some are only needed for part of the mod.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(prompt.plan.missing, id: \.self) { requirement in
                            let id = requirement.nexusModID ?? 0
                            Toggle(isOn: Binding(get: { chosen.contains(id) },
                                                 set: { if $0 { chosen.insert(id) } else { chosen.remove(id) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(requirement.modName ?? "Mod \(id)").fontWeight(.medium)
                                    if let notes = requirement.notes?.strippingNexusMarkup, !notes.isEmpty {
                                        Text(notes).font(.callout).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }
            if prompt.plan.needsScriptExtender, !model.scriptExtenderIsActive {
                Label {
                    HStack {
                        Text("It also needs the Script Extender, which isn't installed.")
                        Button("Install…") {
                            UserDefaults.standard.set("scriptExtender", forKey: Preferences.settingsTab)
                            openSettings()
                        }
                        .buttonStyle(.link)
                    }
                } icon: {
                    Image(systemName: "puzzlepiece.extension").foregroundStyle(.purple)
                }
            }
            ForEach(prompt.plan.external, id: \.self) { requirement in
                Label {
                    HStack {
                        Text("Also needs “\(requirement.modName ?? "")”, from another site.")
                        if let url = requirement.url.flatMap(URL.init(string:)) { Link("Open", destination: url) }
                    }
                } icon: {
                    Image(systemName: "link").foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                    onDone(false)
                }
                .keyboardShortcut(.cancelAction)
                Button(chosen.isEmpty ? String(localized: "Install Only This Mod")
                       : chosen.count == 1 ? String(localized: "Install with 1 Requirement")
                       : String(localized: "Install with \(chosen.count) Requirements")) {
                    isWorking = true
                    let selected = prompt.plan.missing.filter { chosen.contains($0.nexusModID ?? 0) }
                    Task {
                        await model.install(prompt, with: selected)
                        dismiss()
                        onDone(true)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            }
        }
        .padding()
        .frame(width: 520)
        .onAppear { chosen = Set(prompt.plan.missing.compactMap(\.nexusModID)) }
    }
}

/// Endorse and Track buttons for a Nexus mod (with an API key).
struct EndorseTrackButtons: View {
    @Environment(AppModel.self) private var model
    let modID: Int
    var version: String? = nil

    var body: some View {
        if model.nexusAccount.user != nil {
            let endorsed = model.endorsements[modID] == .endorsed
            let tracked = model.trackedMods.contains(modID)
            HStack(spacing: 6) {
                Button {
                    model.setEndorsed(!endorsed, modID: modID, version: version)
                } label: {
                    Label(endorsed ? "Endorsed" : "Endorse", systemImage: endorsed ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .tint(endorsed ? .green : nil)
                .help(endorsed ? "You endorsed this mod. Click to withdraw it." : "Thank the author by endorsing this mod on Nexus")
                Button {
                    model.setTracked(!tracked, modID: modID)
                } label: {
                    Label(tracked ? "Tracking" : "Track", systemImage: tracked ? "bell.fill" : "bell")
                }
                .help(tracked ? "Nexus notifies you about this mod. Click to stop." : "Get Nexus notifications when this mod is updated")
            }
            .controlSize(.small)
            .task { await model.loadNexusAccountLists() }
        }
    }
}
