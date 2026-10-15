// Settings: the Nexus Mods API key.

import AppKit
import SwiftUI
import TadpoleCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var keyDraft = ""
    @State private var revealKey = false
    @State private var changingKey = false

    var body: some View {
        Form {
            Section {
                if model.nexusAccount.user != nil, !changingKey {
                    HStack {
                        NexusAccountStatus()
                        Spacer()
                        Button("Change Key…") { changingKey = true }
                        Button("Remove", role: .destructive) { model.removeNexusAPIKey() }
                    }
                } else {
                    keyEntry
                }
            } header: {
                Text("Nexus Mods API Key")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Needed to download mods. Sign in to Nexus, open your account's API Keys page, and copy the “Personal API Key” at the bottom. It's stored in your Keychain.")
                    Link("Open the Nexus API Keys page…", destination: NexusClient.apiKeyPageURL)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let user = model.nexusAccount.user {
                Section("Downloads") {
                    VStack(alignment: .leading, spacing: 8) {
                        if user.isPremium {
                            Label("Premium: “Mod Manager Download” installs right away.", systemImage: "bolt.fill")
                        } else {
                            Text("Free accounts download through the Nexus website. Sign in once in Tadpole's Nexus browser (the sign-in is remembered), then click **Mod Manager Download** and **Slow download**: the mod installs automatically.")
                        }
                        Button("Open Nexus Mods") {
                            model.openNexusBrowser(user.isPremium ? NexusClient.homeURL : NexusClient.signInURL)
                            openWindow(id: BrowserWindow.id)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The key field, shown until a key works (or while changing it).
    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Group {
                    if revealKey {
                        TextField("API key", text: $keyDraft, prompt: Text("Paste your personal API key"))
                    } else {
                        SecureField("API key", text: $keyDraft, prompt: Text("Paste your personal API key"))
                    }
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
                Button {
                    revealKey.toggle()
                } label: {
                    Image(systemName: revealKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(revealKey ? "Hide key" : "Show key")
                Button("Paste") {
                    keyDraft = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
            }
            HStack {
                NexusAccountStatus()
                Spacer()
                if changingKey {
                    Button("Cancel") { changingKey = false; keyDraft = "" }
                } else if model.nexusAccount != .none {
                    Button("Remove", role: .destructive) { model.removeNexusAPIKey() }
                }
                Button("Save & Verify", action: save)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let key = keyDraft
        keyDraft = ""
        changingKey = false
        Task { await model.setNexusAPIKey(key) }
    }
}

/// The Nexus account the API key belongs to.
struct NexusAccountStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.nexusAccount {
        case .none:
            Text("Not connected").foregroundStyle(.secondary)
        case .checking:
            ProgressView().controlSize(.small)
        case .signedIn(let user):
            Label(user.isPremium ? String(localized: "\(user.name) · Premium") : String(localized: "\(user.name) · Free account"),
                  systemImage: "person.crop.circle.badge.checkmark")
                .foregroundStyle(.green)
        case .invalid(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}
