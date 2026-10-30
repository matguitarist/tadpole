// The setup assistant: shown at first launch (and from the Help menu). It
// checks the game, connects Nexus, offers the Script Extender and sets a
// few options. Every step can be skipped.

import AppKit
import SwiftUI
import TadpoleCore

struct SetupAssistant: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable {
        case welcome, game, nexus, scriptExtender, options, done
    }

    @State private var step = Step.welcome
    @State private var apiKey = ""
    @AppStorage(Preferences.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Preferences.checkModUpdates) private var checkModUpdates = true
    @AppStorage(Preferences.backupBeforePlay) private var backupBeforePlay = true
    @AppStorage(Preferences.showModPictures) private var showModPictures = true

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .game: gameStep
                case .nexus: nexusStep
                case .scriptExtender: scriptExtenderStep
                case .options: optionsStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            Divider()
            footer
        }
        .frame(width: 620, height: 500)
        .interactiveDismissDisabled()
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to Tadpole").font(.largeTitle.bold())
            Text("Tadpole installs, orders and updates your Baldur's Gate 3 mods. Let's get things ready: it takes about a minute.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 8) {
                bullet("gamecontroller", "Check that the game is ready for mods")
                bullet("globe", "Connect your Nexus Mods account to download mods")
                bullet("puzzlepiece.extension", "Optionally, add the Script Extender many mods need")
            }
            .padding(.top, 4)
            Spacer()
            Button("Already know Tadpole? Skip setup") { finish() }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
    }

    private var gameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Baldur's Gate 3", symbol: "gamecontroller")
            if let version = model.gameVersion {
                Label("Baldur's Gate 3 \(version) is installed.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label("Baldur's Gate 3 wasn't found. Install it through Steam.", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            }
            if model.paths.gameHasRun {
                Label("Its mods folder and load order are ready.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label("Run the game once and reach the main menu: that creates the folders Tadpole works with.", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Play Baldur's Gate 3") { model.launchGame() }
                        .disabled(model.gameVersion == nil)
                    Button("Check Again") { model.load() }
                }
            }
            Text("Quit the game before changing your mods: it rewrites its mod list when it quits. Tadpole notices and reads it again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nexusStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Nexus Mods", symbol: "globe")
            Text("Browsing Nexus works without an account. To download mods in Tadpole, paste your personal API key: it's on the API Keys page of your Nexus account (free accounts too).")
                .fixedSize(horizontal: false, vertical: true)
            if let user = model.nexusAccount.user {
                Label("Connected as \(user.name)\(user.isPremium ? String(localized: " (Premium)") : "").", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Link("Open the Nexus API Keys page…", destination: NexusClient.apiKeyPageURL)
                HStack {
                    SecureField("API key", text: $apiKey, prompt: Text("Personal API key"))
                        .textFieldStyle(.roundedBorder)
                    Button("Connect") { Task { await model.setNexusAPIKey(apiKey) } }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                switch model.nexusAccount {
                case .checking: ProgressView().controlSize(.small)
                case .invalid(let message): Text(message).font(.callout).foregroundStyle(.red)
                default: EmptyView()
                }
            }
            Text("Premium accounts download directly. Free accounts click Slow download once per mod on the Nexus page Tadpole opens.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scriptExtenderStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Script Extender", symbol: "puzzlepiece.extension")
            Text("Many mods need Norbyte's Script Extender, which only exists for Windows. bg3se-macos is an independent rebuild of it for Macs with Apple silicon: Tadpole can install it, keep it up to date and apply it again after game updates.")
                .fixedSize(horizontal: false, vertical: true)
            Text("It's unofficial and not every feature works yet. You can install it later in Settings → Script Extender.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch model.scriptExtenderState {
            case .active, .installedElsewhere:
                Label("The Script Extender is installed.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            default:
                if let task = model.scriptExtenderTask {
                    HStack { ProgressView().controlSize(.small); Text(task).foregroundStyle(.secondary) }
                } else {
                    Button("Install the Script Extender") { model.installScriptExtender() }
                        .disabled(model.scriptExtenderGame == nil)
                }
            }
        }
    }

    private var optionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Options", symbol: "slider.horizontal.3")
            Toggle("Check Nexus for mod updates (at launch and every 6 hours)", isOn: $checkModUpdates)
            Toggle("Back up my latest save before playing with different mods", isOn: $backupBeforePlay)
            Toggle("Show mod pictures from Nexus", isOn: $showModPictures)
            Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
            Text("All of these are in Settings, too.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("You're Ready").font(.largeTitle.bold())
            Text("Browse Nexus or Collections to find mods, turn them on in Load Order, then press Play. Help → Tadpole Help explains the rest.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Parts

    private var footer: some View {
        HStack {
            if step != .welcome, step != .done {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
            }
            Spacer()
            Text("\(step.rawValue + 1) of \(Step.allCases.count)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if step == .done {
                Button("Start Using Tadpole") { finish() }.keyboardShortcut(.defaultAction)
            } else {
                Button(step == .welcome ? String(localized: "Get Started") : String(localized: "Continue")) {
                    step = Step(rawValue: step.rawValue + 1) ?? .done
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func title(_ text: LocalizedStringKey, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.title.bold())
    }

    private func bullet(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        // A fixed width for the symbol, so the three lines of text start together.
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 22)
            Text(text)
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Preferences.setupCompleted)
        dismiss()
    }
}
