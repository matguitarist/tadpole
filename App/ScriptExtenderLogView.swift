// The Script Extender's log, like Starseed's SMAPI log: the session's
// version and mods, problems grouped by mod, and every line with level and
// module filters and search. Follows the file while the game runs.

import AppKit
import SwiftUI
import TadpoleCore

extension ScriptExtenderLog.Level {
    var color: Color {
        switch self {
        case .debug: .gray
        case .info: .primary
        case .warn: .orange
        case .error: .red
        }
    }

    var symbol: String {
        switch self {
        case .debug: "ladybug"
        case .info: "info.circle"
        case .warn: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .warn: "Warnings"
        case .error: "Errors"
        }
    }
}

struct ScriptExtenderLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    /// nil: the latest session (followed as new sessions start).
    @State private var chosenFile: URL?
    @State private var shownFile: URL?
    @State private var log: ScriptExtenderLog?
    @State private var loadedDate: Date?
    @State private var levels: Set<ScriptExtenderLog.Level> = [.info, .warn, .error]
    @State private var module: String?
    @State private var searchText = ""
    @State private var follow = true
    @AppStorage("hideRepeatedLogLines") private var hideRepeated = true
    /// Messages logged more than this many times are noise ("Lua context
    /// changed" comes ten times a second).
    private static let repeatLimit = 50

    var body: some View {
        Group {
            if let log {
                VStack(spacing: 0) {
                    header(log)
                    let groups = log.problemGroups
                    if !groups.isEmpty { problems(groups) }
                    Divider()
                    entries(log)
                }
            } else {
                ContentUnavailableView {
                    Label("No Script Extender Log Yet", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(model.scriptExtenderState == .notInstalled
                         ? "The Script Extender writes a log each time the game runs with it, like SMAPI's for Stardew Valley: which mods it loaded and what went wrong. Install it in Settings first."
                         : "Play once with the Script Extender: its log appears here, updating while you play.")
                } actions: {
                    if model.scriptExtenderState == .notInstalled {
                        Button("Open Script Extender Settings") {
                            UserDefaults.standard.set("scriptExtender", forKey: Preferences.settingsTab)
                            openSettings()
                        }
                    }
                }
            }
        }
        .navigationTitle("Script Extender Log")
        .navigationSubtitle(shownFile?.lastPathComponent ?? "")
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search the log"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                sessionMenu
                Button {
                    if let shownFile { NSWorkspace.shared.activateFileViewerSelecting([shownFile]) }
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show the log file in Finder")
                .disabled(shownFile == nil)
            }
        }
        // Reads the file again when it changes: every 2 seconds, cheaply
        // (its date first).
        .task(id: chosenFile) {
            loadedDate = nil
            while !Task.isCancelled {
                await reloadIfChanged()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Parts

    private func header(_ log: ScriptExtenderLog) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.version.map { "BG3SE-macOS \($0)" } ?? "BG3SE-macOS").font(.headline)
                if let session = log.session {
                    Text("Session started \(session)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            stat(log.enabledMods.count, "mods loaded", color: .secondary)
            stat(log.scriptExtenderMods.count, "Script Extender mods", color: .purple)
            stat(log.warningCount, "warnings", color: log.warningCount > 0 ? .orange : .secondary)
            stat(log.errorCount, "errors", color: log.errorCount > 0 ? .red : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func stat(_ count: Int, _ label: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(count, format: .number).font(.title3.bold()).foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// One chip per mod (or part of the Script Extender) with problems;
    /// clicking one searches for it.
    private func problems(_ groups: [ScriptExtenderLog.ProblemGroup]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Problems:").font(.callout).foregroundStyle(.secondary)
                ForEach(groups) { group in
                    Button {
                        if group.isMod {
                            searchText = "Mods/\(group.source)/"
                            module = nil
                        } else {
                            searchText = ""
                            module = group.source
                        }
                        levels.formUnion([.warn, .error])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: group.isMod ? "shippingbox" : "gearshape")
                            Text(group.source).fontWeight(.medium)
                            if group.errors > 0 { Text("\(group.errors)").foregroundStyle(.red) }
                            if group.warnings > 0 { Text("\(group.warnings)").foregroundStyle(.orange) }
                        }
                        .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .help(group.first.message)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func entries(_ log: ScriptExtenderLog) -> some View {
        let shown = filtered(log)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(ScriptExtenderLog.Level.allCases, id: \.self) { level in
                    Toggle(isOn: Binding(get: { levels.contains(level) },
                                         set: { if $0 { levels.insert(level) } else { levels.remove(level) } })) {
                        Label(level.title, systemImage: level.symbol)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
                Picker("Part", selection: $module) {
                    Text("All Parts").tag(String?.none)
                    Divider()
                    ForEach(Array(Set(log.entries.map(\.module))).filter { !$0.isEmpty }.sorted(), id: \.self) {
                        Text(verbatim: $0).tag(String?.some($0))
                    }
                }
                .fixedSize()
                .controlSize(.small)
                Spacer()
                Toggle("Hide repeated lines", isOn: $hideRepeated)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("Hide messages the log repeats more than \(Self.repeatLimit) times")
                Text("\(shown.count) lines").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Toggle("Follow", isOn: $follow)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("Scroll to new lines as the game writes them")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                List(shown) { entry in
                    EntryRow(entry: entry)
                }
                .listStyle(.plain)
                .onChange(of: shown.last?.id) { _, last in
                    if follow, let last { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onAppear {
                    if follow, let last = shown.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func filtered(_ log: ScriptExtenderLog) -> [ScriptExtenderLog.Entry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        var counts: [String: Int] = [:]
        if hideRepeated {
            for entry in log.entries where entry.level < .warn { counts[entry.message, default: 0] += 1 }
        }
        return log.entries.filter { entry in
            (counts[entry.message] ?? 0) <= Self.repeatLimit
                && levels.contains(entry.level)
                && (module == nil || entry.module == module)
                && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query))
        }
    }

    private var sessionMenu: some View {
        Menu {
            Button("Latest Session") { chosenFile = nil }
            let sessions = ScriptExtenderLog.sessionLogs()
            if !sessions.isEmpty {
                Divider()
                ForEach(sessions.prefix(20), id: \.self) { file in
                    Button(file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "bg3se_", with: "")) {
                        chosenFile = file
                    }
                }
            }
            Divider()
            Button("Open Logs Folder") {
                let folder = ScriptExtenderMac.logsFolder
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
            }
        } label: {
            Label("Sessions", systemImage: "clock.arrow.circlepath")
        }
        .help("Show the log of an earlier game session")
    }

    // MARK: Loading

    private func reloadIfChanged() async {
        // latest.log is a link to the newest session's file.
        let file = (chosenFile ?? ScriptExtenderLog.latestURL).resolvingSymlinksInPath()
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let date else {
            if chosenFile == nil { log = nil; shownFile = nil }
            return
        }
        guard file != shownFile || date != loadedDate else { return }
        let parsed = await Task.detached(priority: .utility) { try? ScriptExtenderLog(contentsOf: file) }.value
        guard !Task.isCancelled else { return }
        log = parsed
        shownFile = file
        loadedDate = date
    }
}

private struct EntryRow: View {
    let entry: ScriptExtenderLog.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: entry.time)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Image(systemName: entry.level.symbol)
                .foregroundStyle(entry.level.color)
                .frame(width: 14)
            Text(verbatim: entry.module)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(verbatim: entry.message)
                .foregroundStyle(entry.level == .debug ? .secondary : entry.level.color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.callout, design: .monospaced))
        .id(entry.id)
    }
}
