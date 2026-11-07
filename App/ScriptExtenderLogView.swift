// The Script Extender's log, like Starseed's SMAPI log: LogKit's viewer
// (levels, problems by part, search, Clear, follow live, sessions, copy and
// export) with what only Tadpole knows: the session's version and mods,
// problems grouped by mod, the game build it doesn't support, and mods
// listed with another mod's scripts.

import AppKit
import LogKitUI
import SwiftUI
import TadpoleCore

/// A color per part of the Script Extender, so lines from the same part
/// are easy to follow.
func scriptExtenderModuleColor(_ module: String) -> Color {
    switch module {
    case "Lua": .blue
    case "Mod": .green
    case "Osiris": .purple
    case "Entity": .teal
    case "Stats": .orange
    case "Core": .gray
    case "Console": .indigo
    case "Hooks": .pink
    case "Events": .mint
    case "Net": .cyan
    case "Timer": .brown
    case "Persist": .yellow
    case "Game": .red
    default: .secondary
    }
}

extension LogViewerModel {
    /// The latest session (followed as new sessions start) and the earlier
    /// ones in the Script Extender's logs folder.
    static func scriptExtender() -> LogViewerModel {
        let model = LogViewerModel(file: LogFileSource(
            files: [.init(String(localized: "Latest Session"), url: ScriptExtenderLog.latestURL)],
            folder: ScriptExtenderMac.logsFolder,
            sessionPrefix: "bg3se_",
            parser: ScriptExtenderLog.parser(describe: ScriptExtenderLogText.describe)))
        // Debug lines start hidden, as they always have.
        model.filter.levels = [.info, .warning, .error, .critical]
        model.filter.collapseRepeats = UserDefaults.standard.object(forKey: hideRepeatsKey) as? Bool ?? true
        // Show All Messages comes back here, with Debug still hidden.
        model.defaultFilter = model.filter
        return model
    }

    static let hideRepeatsKey = "hideRepeatedLogLines"
}

struct ScriptExtenderLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    /// What Tadpole reads from the session shown, computed off the main
    /// thread once per change of the log.
    @State private var facts = ScriptExtenderLog(entries: [])

    var body: some View {
        let log = model.scriptLogViewer
        LogViewer(model: log, options: options)
            .navigationTitle("Script Extender Log")
            .navigationSubtitle(log.fileURL?.resolvingSymlinksInPath().lastPathComponent ?? "")
            .task(id: documentKey) { await updateFacts() }
            .onChange(of: log.filter.collapseRepeats) { _, hide in
                UserDefaults.standard.set(hide, forKey: LogViewerModel.hideRepeatsKey)
            }
    }

    private var options: LogViewerOptions {
        let notInstalled = model.scriptExtenderState == .notInstalled
        return LogViewerOptions(
            emptyTitle: String(localized: "No Script Extender Log Yet"),
            emptyMessage: notInstalled
                ? String(localized: "The Script Extender writes a log each time the game runs with it, like SMAPI's for Stardew Valley: which mods it loaded and what went wrong. Install it in Settings first.")
                : String(localized: "Play once with the Script Extender: its log appears here, updating while you play."),
            emptyActions: notInstalled ? {
                AnyView(Button("Open Script Extender Settings") {
                    UserDefaults.standard.set("scriptExtender", forKey: Preferences.settingsTab)
                    openSettings()
                })
            } : nil,
            insightsTitle: String(localized: "What the Script Extender is telling you"),
            insightActions: { insight in AnyView(ModProblemActions(insight: insight)) },
            banner: { _ in AnyView(LimitedModeBanner(facts: facts)) },
            sourceColor: scriptExtenderModuleColor)
    }

    /// Changes when the log shown changes: another file, a new session, new lines.
    private var documentKey: String {
        let log = model.scriptLogViewer
        let entries = log.document?.entries
        return "\(log.fileURL?.path ?? "") \(entries?.first?.id ?? -1) \(entries?.count ?? -1) \(entries?.last?.id ?? -1)"
    }

    private func updateFacts() async {
        guard let entries = model.scriptLogViewer.document?.entries else {
            facts = ScriptExtenderLog(entries: [])
            return
        }
        facts = await Task.detached { ScriptExtenderLog(entries: entries) }.value
    }
}

// MARK: Header and insights

/// The header's facts and the insights, in the person's language. Runs while
/// the log is parsed, off the main thread.
enum ScriptExtenderLogText {
    nonisolated static func describe(_ log: ScriptExtenderLog) -> (metadata: [LogMetadata], insights: [LogInsight]) {
        var metadata = [LogMetadata(log.version.map { "BG3SE-macOS \($0)" } ?? "BG3SE-macOS", symbol: "puzzlepiece.extension")]
        if let session = log.session {
            metadata.append(LogMetadata(String(localized: "Session started \(session)"), symbol: "clock"))
        }
        metadata.append(LogMetadata(String(localized: "\(log.enabledMods.count) mods loaded"), symbol: "shippingbox"))
        metadata.append(LogMetadata(String(localized: "\(log.scriptExtenderMods.count) Script Extender mods"), symbol: "curlybraces"))

        // Problems by part are LogKit's own; by mod, they're Tadpole's.
        var insights = log.problemGroups.filter(\.isMod).map { group in
            LogInsight(id: group.id,
                       level: group.errors > 0 ? .error : .warning,
                       title: group.errors > 0
                           ? String(localized: "Errors in \(group.source) (\(group.errors))")
                           : String(localized: "Warnings in \(group.source) (\(group.warnings))"),
                       detail: group.first.message.split(separator: "\n").first.map(String.init) ?? "")
        }
        if !log.misattributed.isEmpty {
            let pairs = log.misattributed.sorted { $0.key < $1.key }
            insights.append(LogInsight(
                id: "misattributed", level: .info,
                title: String(localized: "Some mods were listed with another mod's scripts"),
                detail: String(localized: "The Script Extender also listed \(pairs.map(\.key).formatted(.list(type: .and))) as Script Extender mods, by mistake: it matched them to the scripts of \(Set(pairs.map(\.value)).sorted().formatted(.list(type: .and))). They don't use the Script Extender and aren't counted.")))
        }
        return (metadata, insights)
    }
}

/// Shows a mod's warnings and errors: the lines whose message names a file in its folder.
private struct ModProblemActions: View {
    @Environment(AppModel.self) private var model
    let insight: LogInsight

    var body: some View {
        if insight.id.hasPrefix("mod:") {
            let folder = String(insight.id.dropFirst(4))
            Button("Show Messages") {
                let log = model.scriptLogViewer
                log.filter.source = nil
                log.filter.levels = [.warning, .error, .critical]
                log.filter.query = "Mods/\(folder)"
            }
            .help("Show only the warnings and errors from \(folder)")
        }
    }
}

/// The game build isn't one this release supports: what's off.
private struct LimitedModeBanner: View {
    let facts: ScriptExtenderLog

    var body: some View {
        if let build = facts.unsupportedBuild {
            VStack(alignment: .leading, spacing: 4) {
                Label("Limited mode: this release was made for game build \(build.expected), and yours is \(build.detected).", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                if !facts.disabledFeatures.isEmpty {
                    Text("Turned off: \(facts.disabledFeatures.formatted(.list(type: .and))). Mods that use these won't fully work until a release supports your build.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.12))
            Divider()
        }
    }
}
