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

    @ViewBuilder
    private var content: some View {
        if model.updates.isEmpty {
            ContentUnavailableView {
                Label(model.updateCheckFailed ? "Couldn't Reach Nexus" : "Everything Is Up to Date",
                      systemImage: model.updateCheckFailed ? "wifi.exclamationmark" : "checkmark.circle")
            } description: {
                VStack(spacing: 8) {
                    if model.lastUpdateCheck == nil {
                        Text(model.isCheckingUpdates ? "Checking Nexus…" : "Not checked yet.")
                    }
                    if !model.uncheckableMods.isEmpty {
                        Text("\(model.uncheckableMods.count) mods can't be checked: Tadpole only knows the version of mods downloaded through it. Install them from Nexus once to get their updates.")
                    }
                }
            } actions: {
                Button("Check Now") { Task { await model.checkForUpdates() } }
                    .disabled(model.isCheckingUpdates)
            }
        } else {
            List {
                Section {
                    ForEach(model.updates) { UpdateRow(update: $0) }
                } footer: {
                    if !model.uncheckableMods.isEmpty {
                        Text("\(model.uncheckableMods.count) mods can't be checked: Tadpole only knows the version of mods downloaded through it. Install them from Nexus once to get their updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
