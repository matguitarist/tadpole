// Profiles in the UI: the toolbar menu on the Load Order page, the window
// that manages them, and the name prompt.

import SwiftUI
import TadpoleCore

/// What the name prompt is for.
enum ProfileNamePrompt: Identifiable, Equatable {
    case new(empty: Bool)
    case rename(String)

    var id: String {
        switch self {
        case .new(let empty): empty ? "new-empty" : "new"
        case .rename(let name): "rename-" + name
        }
    }
}

/// The profile in use, with every profile to switch to.
struct ProfileMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ProfileMenuItems(model: model)
        } label: {
            Label(model.activeProfileName ?? String(localized: "Profiles"), systemImage: "person.2")
                .labelStyle(.titleAndIcon)
        }
        .help("The profile in use: switch to another load order")
    }
}

/// Shared by the toolbar menu, the menu bar icon and the Mods menu. Plain
/// buttons (a checkmark on the one in use): clicking one always switches to
/// it, even from a menu that hasn't refreshed yet.
struct ProfileMenuItems: View {
    let model: AppModel

    var body: some View {
        ForEach(model.profileStore.profiles) { profile in
            Button {
                model.switchProfile(to: profile.name)
            } label: {
                if profile.name == model.activeProfileName {
                    Label(profile.name, systemImage: "checkmark")
                } else {
                    Text(verbatim: profile.name)
                }
            }
        }
        Divider()
        Button("New Profile…") { model.profileNamePrompt = .new(empty: false) }
        Button("New Empty Profile…") { model.profileNamePrompt = .new(empty: true) }
        Button("Manage Profiles…") { model.showProfiles = true }
    }
}

/// "New Profile" / "Rename" with a name field.
struct ProfileNameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: ProfileNamePrompt
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            Text(explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $name, prompt: Text("Honour run, Modded playthrough…"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            if taken {
                Text("A profile already has that name.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isRename ? String(localized: "Rename") : String(localized: "Create"), action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || taken)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear { if case .rename(let old) = prompt { name = old } }
    }

    private var isRename: Bool { if case .rename = prompt { true } else { false } }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var taken: Bool {
        if case .rename(let old) = prompt, trimmed == old { return false }
        return model.profileStore[trimmed] != nil
    }

    private var title: String {
        switch prompt {
        case .new(empty: false): String(localized: "New Profile")
        case .new(empty: true): String(localized: "New Empty Profile")
        case .rename: String(localized: "Rename Profile")
        }
    }

    private var explanation: String {
        switch prompt {
        case .new(empty: false): String(localized: "A copy of the load order now. Changes you make next are kept in the new profile.")
        case .new(empty: true): String(localized: "Every mod is turned off (they stay installed). Turn on the ones this profile should load.")
        case .rename: String(localized: "Only the profile's name changes.")
        }
    }

    private func commit() {
        guard !trimmed.isEmpty, !taken else { return }
        switch prompt {
        case .new(let empty): model.createProfile(named: trimmed, empty: empty)
        case .rename(let old): model.renameProfile(old, to: trimmed)
        }
        dismiss()
    }
}

/// Every profile: use, rename, duplicate or delete.
struct ManageProfilesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var confirmDelete: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Profiles").font(.title3.bold())
                Spacer()
            }
            .padding()
            List(model.profileStore.profiles, selection: $selection) { profile in
                row(profile).tag(profile.name)
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Menu {
                    Button("New Profile…") { model.profileNamePrompt = .new(empty: false) }
                    Button("New Empty Profile…") { model.profileNamePrompt = .new(empty: true) }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button("Rename…") { selection.map { model.profileNamePrompt = .rename($0) } }
                    .disabled(selection == nil)
                Button("Duplicate") { selection.map(model.duplicateProfile) }
                    .disabled(selection == nil)
                Button("Delete…") { confirmDelete = selection }
                    .disabled(selection == nil || selection == model.activeProfileName)
                    .help("The profile in use can't be deleted: switch to another first")
                Spacer()
                Button("Use") { selection.map(model.switchProfile) }
                    .disabled(selection == nil || selection == model.activeProfileName)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 420)
        .onAppear { selection = model.activeProfileName }
        .sheet(item: Binding(get: { model.profileNamePrompt }, set: { model.profileNamePrompt = $0 })) { ProfileNameSheet(prompt: $0) }
        .confirmationDialog("Delete “\(confirmDelete ?? "")”?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let confirmDelete { model.deleteProfile(confirmDelete) }
                selection = model.activeProfileName
            }
        } message: {
            Text("Only the profile is deleted: its mods stay installed.")
        }
    }

    private func row(_ profile: LoadOrderProfile) -> some View {
        let installed = Set(model.mods.compactMap { $0.info?.uuid })
        let missing = profile.mods.filter { !installed.contains($0.uuid) }.count
        return HStack {
            Image(systemName: profile.name == model.activeProfileName ? "checkmark.circle.fill" : "person.2")
                .foregroundStyle(profile.name == model.activeProfileName ? Color.accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: profile.name).fontWeight(profile.name == model.activeProfileName ? .semibold : .regular)
                HStack(spacing: 6) {
                    Text(profile.mods.count == 1 ? String(localized: "1 mod") : String(localized: "\(profile.mods.count) mods"))
                    if missing > 0 {
                        Text(missing == 1 ? String(localized: "1 not installed") : String(localized: "\(missing) not installed"))
                            .foregroundStyle(.orange)
                    }
                    if profile.collectionSlug != nil { Text("From a collection") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if profile.name == model.activeProfileName {
                Text("In use").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
