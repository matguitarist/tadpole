// Settings → Script Extender: install, update, apply again or remove the
// macOS Script Extender, with what it is and which game build it's made for.

import SwiftUI
import TadpoleCore

struct ScriptExtenderSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.reportAfterPlaying) private var reportAfterPlaying = true

    var body: some View {
        Form {
            Section {
                Text("Many mods need Norbyte's Script Extender, which only exists for Windows. **bg3se-macos** is an independent rebuild of it for Macs with Apple silicon. Tadpole can install it into the game, keep it up to date, and apply it again after game updates.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("It's unofficial: made by its own authors, not Norbyte or Larian. Most of the Windows version works, not all of it. Back up your saves before playing with Script Extender mods.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("About bg3se-macos", destination: ScriptExtenderMac.projectURL)
            }

            Section("Status") {
                LabeledContent("Script Extender") {
                    statusLabel
                }
                if let build = model.scriptExtenderGame?.build {
                    LabeledContent("Game build") { Text(verbatim: build) }
                }
                if let release = model.scriptExtender?.release ?? model.scriptExtenderLatest {
                    compatibility(release)
                }
                if let task = model.scriptExtenderTask {
                    HStack {
                        if let progress = model.scriptExtenderProgress {
                            ProgressView(value: progress).frame(width: 120)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Text(task).foregroundStyle(.secondary)
                    }
                }
                actions
            }

            Section {
                Toggle("Notify me about errors and crashes after playing", isOn: $reportAfterPlaying)
            } header: {
                Text("After Playing")
            } footer: {
                Text("When the game quits, Tadpole reads the Script Extender's log and looks for a crash report. If something went wrong, a notification opens the log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Latest Release") {
                if let latest = model.scriptExtenderLatest {
                    LabeledContent("Version") {
                        Text(verbatim: latest.version)
                    }
                    LabeledContent("Published") {
                        Text(latest.publishedAt, format: .dateTime.year().month().day())
                    }
                    if !latest.gameBuilds.isEmpty {
                        LabeledContent("Made for game build") {
                            Text(verbatim: latest.gameBuilds.joined(separator: ", "))
                        }
                    }
                    Link("Release Notes", destination: latest.pageURL)
                } else {
                    Text("Not checked yet.").foregroundStyle(.secondary)
                }
                Button("Check Now") { Task { await model.checkScriptExtenderRelease() } }
            }

            Section {
                Button("Show Script Extender Logs") {
                    let folder = ScriptExtenderMac.logsFolder
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
            } footer: {
                Text("Tadpole adds the Script Extender to the game's program and keeps the original next to it. Steam replaces the program when the game updates: Tadpole applies the Script Extender again before you press Play, or from the Load Order page. Remove puts the original back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            model.refreshScriptExtenderState()
            if model.scriptExtenderLatest == nil { await model.checkScriptExtenderRelease() }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch model.scriptExtenderState {
        case .notInstalled:
            Text("Not installed").foregroundStyle(.secondary)
        case .active:
            Label(String(localized: "Version \(model.scriptExtender?.release.version ?? "") installed"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsReapply:
            Label("Needs to be applied again after a game update", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .installedElsewhere:
            Label("Installed outside Tadpole", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    /// Whether the release notes name the game's build.
    @ViewBuilder
    private func compatibility(_ release: ScriptExtenderRelease) -> some View {
        if let build = model.scriptExtenderGame?.build, release.supports(gameBuild: build) == false {
            Label("Version \(release.version) was made for game build \(release.gameBuilds.joined(separator: ", ")), not yours. It may run in a limited mode, with some features off, until a release supports your build.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        let busy = model.scriptExtenderTask != nil
        HStack {
            switch model.scriptExtenderState {
            case .notInstalled:
                Button("Install Script Extender") { model.installScriptExtender(model.scriptExtenderLatest) }
                    .disabled(busy || model.scriptExtenderGame == nil)
            case .needsReapply:
                Button("Apply Again") { model.reapplyScriptExtender() }.disabled(busy)
            case .active, .installedElsewhere:
                if let update = model.scriptExtenderUpdate ?? (model.scriptExtenderState == .installedElsewhere ? model.scriptExtenderLatest : nil) {
                    Button(model.scriptExtenderState == .installedElsewhere
                           ? String(localized: "Install \(update.version) with Tadpole")
                           : String(localized: "Update to \(update.version)")) {
                        model.installScriptExtender(update)
                    }
                    .disabled(busy)
                }
            }
            Spacer()
            if model.scriptExtenderState != .notInstalled {
                Button("Remove…", role: .destructive) { confirmRemove = true }
                    .disabled(busy)
            }
        }
        .confirmationDialog("Remove the Script Extender?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { model.removeScriptExtender() }
        } message: {
            Text("The game's original program is put back. Script Extender mods stay installed, but their scripted features stop working.")
        }
    }

    @State private var confirmRemove = false
}
