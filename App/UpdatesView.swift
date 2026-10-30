import SwiftUI
import TadpoleCore

/// Installed mods with a newer version on Nexus, with what changed.
struct UpdatesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        content
            .navigationTitle("Updates")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.isCheckingUpdates {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { Task { await model.checkForUpdates() } } label: { Label("Check Now", systemImage: "arrow.clockwise") }
                            .help("Check Nexus for new versions of your mods")
                    }
                    Button { model.install(model.updates) } label: { Label("Update All", systemImage: "arrow.down.circle") }
                        .help("Download and install every update")
                        .disabled(model.updates.isEmpty)
                }
            }
    }

    private var subtitle: String {
        guard let date = model.lastUpdateCheck else { return "" }
        return String(localized: "Checked \(date.formatted(.relative(presentation: .named)))")
    }

    private var uncheckableNote: String {
        let count = model.uncheckableMods.count
        return count == 1
            ? String(localized: "1 mod can't be checked: it isn't linked to Nexus. Select it in Load Order and click Find on Nexus… in its details.")
            : String(localized: "\(count) mods can't be checked: they aren't linked to Nexus. Select one in Load Order and click Find on Nexus… in its details.")
    }

    @ViewBuilder
    private var content: some View {
        if model.updates.isEmpty, model.scriptExtenderUpdate == nil {
            ContentUnavailableView {
                if model.updateCheckFailed {
                    Label("Couldn't Reach Nexus", systemImage: "wifi.exclamationmark")
                } else if model.lastUpdateCheck == nil {
                    Label(model.isCheckingUpdates ? "Checking Nexus…" : "Not Checked Yet", systemImage: "arrow.clockwise")
                } else if model.mods.filter({ $0.info != nil }).count == model.uncheckableMods.count {
                    Label("No Mods to Check", systemImage: "link")
                } else if model.uncheckableMods.isEmpty {
                    Label("Everything Is Up to Date", systemImage: "checkmark.circle")
                } else {
                    Label("Linked Mods Are Up to Date", systemImage: "checkmark.circle")
                }
            } description: {
                if !model.uncheckableMods.isEmpty {
                    Text(uncheckableNote)
                }
            } actions: {
                Button("Check Now") { Task { await model.checkForUpdates() } }
                    .disabled(model.isCheckingUpdates)
            }
        } else {
            List {
                if let release = model.scriptExtenderUpdate {
                    Section("Script Extender") { ScriptExtenderUpdateRow(release: release) }
                }
                if !model.updates.isEmpty {
                Section {
                    ForEach(model.updates) { UpdateRow(update: $0) }
                    if !model.uncheckableMods.isEmpty {
                        ListNote(text: Text(uncheckableNote))
                    }
                }
                }
            }
        }
    }
}

/// A new release of the macOS Script Extender, with its notes.
private struct ScriptExtenderUpdateRow: View {
    @Environment(AppModel.self) private var model
    let release: ScriptExtenderRelease
    @State private var showNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.title)
                    .foregroundStyle(.purple)
                    .frame(width: 80, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Script Extender for macOS").font(.headline)
                    HStack(spacing: 6) {
                        Text(verbatim: model.scriptExtender?.release.version ?? "").foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: release.version).fontWeight(.medium)
                    }
                    .font(.callout)
                    HStack(spacing: 8) {
                        Text(release.publishedAt, format: .dateTime.year().month().day())
                        if !release.gameBuilds.isEmpty {
                            Text("For game build \(release.gameBuilds.joined(separator: ", "))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let task = model.scriptExtenderTask {
                    ProgressView().controlSize(.small).help(task)
                } else {
                    Button("Update") { model.installScriptExtender(release) }
                        .buttonStyle(.borderedProminent)
                }
            }
            if !release.notes.isEmpty {
                DisclosureGroup(isExpanded: $showNotes) {
                    Text(LocalizedStringKey(release.notes))  // Markdown from GitHub
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                } label: {
                    Text("What's New").font(.callout)
                }
                .padding(.leading, 90)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Link("Release Notes on GitHub", destination: release.pageURL)
        }
    }
}

private struct UpdateRow: View {
    @Environment(AppModel.self) private var model
    let update: ModUpdate
    @State private var showChanges = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                RemotePicture(url: model.nexusMods[update.modID]?.thumbnailURL, cornerRadius: 4)
                    .frame(width: 80, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(update.modName).font(.headline)
                    HStack(spacing: 6) {
                        Text(update.update.installed.version ?? update.update.installed.name)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Text(update.update.latest.version ?? update.update.latest.name).fontWeight(.medium)
                    }
                    .font(.callout)
                    HStack(spacing: 8) {
                        Text(update.update.latest.name)
                        Text(update.update.latest.uploadedAt, format: .dateTime.year().month().day())
                        if let bytes = update.update.latest.byteCount { Text(bytes, format: .byteCount(style: .file)) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if update.isGuess {
                        Label("Your version was guessed from when you installed it: check before updating.", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button("Update") { model.install([update]) }
                    .buttonStyle(.borderedProminent)
            }
            if !update.update.changes.isEmpty {
                DisclosureGroup(isExpanded: $showChanges) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(update.update.changes, id: \.self) { change in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: change.version).font(.callout.bold())
                                ForEach(Array(change.lines.enumerated()), id: \.offset) { _, line in
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(verbatim: "•").foregroundStyle(.secondary)
                                        Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .font(.callout)
                                }
                            }
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.top, 4)
                } label: {
                    Text("What's New").font(.callout)
                }
                .padding(.leading, 90)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("View on Nexus Mods") { model.openNexusBrowser(NexusClient.modPageURL(update.modID)) }
        }
    }
}
