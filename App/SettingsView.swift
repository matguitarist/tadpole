// Settings: General (language, theme), Game (where things are), Nexus Mods
// (API key, downloads), Script Extender (ScriptExtenderSettings).

import AppKit
import SwiftUI
import TadpoleCore

struct SettingsView: View {
    @AppStorage(Preferences.settingsTab) private var tab = "general"  // reopens on the last tab

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            GameSettings()
                .tabItem { Label("Game", systemImage: "gamecontroller") }
                .tag("game")
            NexusSettings()
                .tabItem { Label("Nexus Mods", systemImage: "globe") }
                .tag("nexus")
            ScriptExtenderSettings()
                .tabItem { Label("Script Extender", systemImage: "puzzlepiece.extension") }
                .tag("scriptExtender")
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Preferences.theme) private var theme = AppTheme.system
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true
    private let updater = AppUpdater.shared
    @State private var language = AppLanguage.current

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $language) {
                    Text("System (\(AppLanguage.systemName))").tag(AppLanguage.system)
                    ForEach(AppLanguage.available, id: \.self) { language in
                        Text(verbatim: language.name).tag(language)
                    }
                }
                .onChange(of: language) { _, new in new.apply() }
                if language != AppLanguage.atLaunch {
                    HStack {
                        Text("The new language applies after a restart.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { AppLanguage.relaunch() }
                    }
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: theme) { _, new in new.apply() }
            }
            Section {
                Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("With the menu bar icon, closing the window keeps Tadpole running so it can keep checking for mod updates. Quit from the icon's menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version") {
                    HStack {
                        Text(verbatim: "\(AppModel.appVersion) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                        if updater.isConfigured {
                            Button("Check Now") { updater.checkForUpdates() }
                                .disabled(!updater.canCheckForUpdates)
                        }
                    }
                }
                if updater.isConfigured {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.automaticallyChecks = $0 }
                    ))
                }
            } header: {
                Text("Tadpole Updates")
            } footer: {
                Text("Updates show what's new before they install. They're checked against Tadpole's own signing key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GameSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.backupBeforePlay) private var backupBeforePlay = true

    var body: some View {
        Form {
            Section("Baldur's Gate 3") {
                LabeledContent("Game") {
                    if let app = model.gameApp {
                        HStack {
                            Text(model.gameVersion.map { String(localized: "Version \($0)") } ?? app.lastPathComponent)
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app]) }
                        }
                    } else {
                        Text("Not found. Install it with Steam.").foregroundStyle(.secondary)
                    }
                }
                if model.isGameRunning {
                    Label("The game is running: Tadpole won't change the load order until you quit it.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Toggle("Back up my latest save before playing with different mods", isOn: $backupBeforePlay)
            } header: {
                Text("Saves")
            } footer: {
                Text("When you press Play and your mods changed since the last game, Tadpole first copies your latest save to Tadpole Save Backups: a save made with other mods can stop loading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                FolderRow(title: "Mods folder", url: model.paths.modsFolder)
                FolderRow(title: "Load order file", url: model.paths.modSettings)
                FolderRow(title: "Saves", url: model.paths.saves)
                FolderRow(title: "Save backups", url: model.paths.saveBackups)
            } header: {
                Text("Folders")
            } footer: {
                Text("The game decides where these are; Tadpole works with them where they are. Each change to the load order keeps the previous file as modsettings.lsx.bak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FolderRow: View {
    let title: LocalizedStringKey
    let url: URL

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(url.path(percentEncoded: false).replacingOccurrences(of: URL.homeDirectory.path(percentEncoded: false), with: "~/"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
                Button {
                    let fm = FileManager.default
                    if fm.fileExists(atPath: url.path(percentEncoded: false)) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else if url.hasDirectoryPath {
                        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(url)
                    } else {
                        NSWorkspace.shared.open(url.deletingLastPathComponent())
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
    }
}

private struct NexusSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.closeBrowserAfterDownload) private var closeBrowserAfterDownload = true
    @AppStorage(Preferences.checkModUpdates) private var checkModUpdates = true
    @AppStorage(Preferences.notifyModUpdates) private var notifyModUpdates = true
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
                    Text("Needed to download mods. Sign in to Nexus, open your account's API Keys page, and copy the “Personal API Key” at the bottom. It's kept in a file only your account can read.")
                    Link("Open the Nexus API Keys page…", destination: NexusClient.apiKeyPageURL)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Downloads") {
                if let user = model.nexusAccount.user {
                    if user.isPremium {
                        Label("Premium: mods download and install right away.", systemImage: "bolt.fill")
                    } else {
                        Text("Free accounts download through the Nexus website. Sign in once in Tadpole's Nexus browser (the sign-in is remembered), then click **Mod Manager Download** and **Slow download**: the mod installs automatically.")
                        Button("Sign In to Nexus…") {
                            model.openNexusBrowser(NexusClient.signInURL)
                            openWindow(id: BrowserWindow.id)
                        }
                    }
                }
                Toggle("Close the Nexus browser once a download starts", isOn: $closeBrowserAfterDownload)
                Text("The download and install go on in the main window's sidebar. With several mods to download, the browser stays open until the last one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Check for mod updates at launch and every 6 hours", isOn: $checkModUpdates)
                Toggle("Notify me when updates are found", isOn: $notifyModUpdates)
                    .disabled(!checkModUpdates)
            } header: {
                Text("Mod Updates")
            } footer: {
                Text("Checking uses Nexus's public information and works without an API key; installing updates needs one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
