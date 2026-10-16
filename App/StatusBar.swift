// The bar under every page (like Starseed's): the game's and the Script
// Extender's versions with a colored dot (green: fine, yellow: needs
// something, red: missing, gray: not installed), and what Tadpole is doing.

import SwiftUI
import TadpoleCore

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            GameIndicator()
            ScriptExtenderIndicator()
            if let task = model.scriptExtenderTask {
                Divider().frame(height: 14)
                HStack(spacing: 8) {
                    if let progress = model.scriptExtenderProgress {
                        ProgressView(value: progress).progressViewStyle(.linear).frame(width: 110)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(task).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            DownloadsIndicator()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Downloads in progress (with overall progress), or the latest one that
/// failed, until dismissed.
private struct DownloadsIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let active = model.downloads.filter { !$0.isFinished }
        let failed = model.downloads.filter { item in
            if case .failed = item.state { return !model.dismissedDownloadFailures.contains(item.id) }
            return false
        }
        if !active.isEmpty {
            HStack(spacing: 8) {
                ProgressView(value: overallProgress(active)).progressViewStyle(.linear).frame(width: 110)
                Text(active.count == 1 ? String(localized: "Downloading “\(active[0].title)”")
                                       : String(localized: "Downloading \(active.count) mods"))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            .help(active.map(\.title).joined(separator: "\n"))
        } else if let last = failed.last, case .failed(let reason) = last.state {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(failed.count == 1 ? String(localized: "Couldn't install “\(last.title)”")
                                       : String(localized: "\(failed.count) downloads failed"))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Button {
                    model.dismissedDownloadFailures.formUnion(failed.map(\.id))
                } label: {
                    Image(systemName: "xmark").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .help(reason)
        } else if model.isInstalling {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// Downloaded share of what's running (waiting ones count as 0).
    private func overallProgress(_ active: [DownloadItem]) -> Double {
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + ($1.state == .installing ? 1 : $1.progress) } / Double(active.count)
    }
}

private struct GameIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let version = model.gameVersion {
            VersionIndicator(color: .green,
                             text: model.gameIsRunning ? String(localized: "Baldur's Gate 3 \(version) · Running") : String(localized: "Baldur's Gate 3 \(version)"),
                             help: String(localized: "The game's version, from Steam."))
        } else {
            VersionIndicator(color: .red, text: String(localized: "Baldur's Gate 3 not found"),
                             help: String(localized: "Install the game through Steam, then run it once."))
        }
    }
}

private struct ScriptExtenderIndicator: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let installed = model.scriptExtender?.release
        let build = model.scriptExtenderGame?.build
        switch model.scriptExtenderState {
        case .notInstalled:
            VersionIndicator(color: .gray, text: String(localized: "Script Extender not installed"),
                             help: String(localized: "Script Extender mods need it for their scripted features. Install the macOS version in Settings.")) {
                Button("Install…") { showSettings() }
            }
        case .needsReapply:
            VersionIndicator(color: .yellow, text: String(localized: "Script Extender \(installed?.version ?? "") · removed by a game update"),
                             help: String(localized: "Steam replaced the game's program. Tadpole applies the Script Extender again when you press Play.")) {
                Button("Apply Again") { model.reapplyScriptExtender() }
                    .disabled(model.scriptExtenderTask != nil || model.gameIsRunning)
            }
        case .active, .installedElsewhere:
            let version = installed?.version
            let text = version.map { String(localized: "Script Extender \($0)") } ?? String(localized: "Script Extender")
            if let update = model.scriptExtenderUpdate {
                VersionIndicator(color: .yellow, text: text,
                                 help: String(localized: "Version \(update.version) is available.")) {
                    Button("Update") { model.installScriptExtender(update) }
                        .disabled(model.scriptExtenderTask != nil)
                }
            } else if let installed, let build, installed.supports(gameBuild: build) == false {
                VersionIndicator(color: .yellow, text: text + " · " + String(localized: "limited mode"),
                                 help: String(localized: "This release was made for game build \(installed.gameBuilds.joined(separator: ", ")), not \(build): some features are off until a release supports it."))
            } else {
                VersionIndicator(color: .green, text: text, help: String(localized: "The Script Extender is installed."))
            }
        }
    }

    private func showSettings() {
        UserDefaults.standard.set("scriptExtender", forKey: Preferences.settingsTab)
        openSettings()
    }
}

/// A colored dot, a name and version, and an optional button.
private struct VersionIndicator<Action: View>: View {
    let color: Color
    let text: String
    let help: String
    @ViewBuilder let action: Action

    init(color: Color, text: String, help: String, @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.color = color
        self.text = text
        self.help = help
        self.action = action()
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 2)
            Text(text)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            action
                .buttonStyle(.link)
                .font(.callout)
        }
        .help(help)
    }
}
