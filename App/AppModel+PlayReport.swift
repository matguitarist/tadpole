// After a game with the Script Extender: its latest log, read in the
// background, gives each mod's script status (load order badges), and a
// report when the game quits (errors, a crash) with a notification.

import AppKit
import TadpoleCore
@preconcurrency import UserNotifications

/// What went wrong in the last game.
struct PlayReport: Equatable {
    /// Errors by mod (or part of the Script Extender), most first.
    var errors: [(source: String, count: Int)]
    /// A crash report written during the game (the Script Extender's, or
    /// macOS's).
    var crashFile: URL?

    var hasProblems: Bool { !errors.isEmpty || crashFile != nil }

    static func == (a: PlayReport, b: PlayReport) -> Bool {
        a.crashFile == b.crashFile && a.errors.map(\.source) == b.errors.map(\.source) && a.errors.map(\.count) == b.errors.map(\.count)
    }
}

extension AppModel {
    /// The Script Extender's crash report (written when the game crashes
    /// with it).
    static var scriptExtenderCrashFile: URL {
        ScriptExtenderMac.logsFolder.deletingLastPathComponent().appending(path: "crash.log")
    }

    /// Reads the latest Script Extender log again (at launch, after a game).
    func refreshScriptLog() async {
        let file = ScriptExtenderLog.latestURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        lastScriptLog = await Task.detached(priority: .utility) { try? ScriptExtenderLog(contentsOf: file) }.value
        lastScriptLogDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// How a mod's scripts did in the last game, when the Script Extender ran
    /// it (nil: no log, or the mod has no scripts).
    func scriptStatus(of mod: PakMod) -> ScriptExtenderLog.ScriptStatus? {
        guard mod.usesScriptExtender, !mod.scriptFolders.isEmpty, let log = lastScriptLog else { return nil }
        // A mod installed after that game wasn't in it.
        if let logDate = lastScriptLogDate,
           let added = (try? mod.file.resourceValues(forKeys: [.creationDateKey]))?.creationDate, added > logDate { return nil }
        return log.scriptStatus(forFolders: mod.scriptFolders)
    }

    /// The game quit: what went wrong in it, and a notification if anything did.
    func reportAfterPlaying(startedAt: Date?) async {
        try? await Task.sleep(for: .seconds(2))  // the last log lines and crash reports
        await refreshScriptLog()
        let start = startedAt ?? .distantPast
        var errors: [(source: String, count: Int)] = []
        if let log = lastScriptLog, let date = lastScriptLogDate, date > start {
            errors = log.problemGroups.filter { $0.errors > 0 }.map { ($0.source, $0.errors) }
        }
        let report = PlayReport(errors: errors, crashFile: Self.crashFile(since: start))
        lastPlayReport = report.hasProblems ? report : nil
        guard report.hasProblems, UserDefaults.standard.object(forKey: Preferences.reportAfterPlaying) as? Bool ?? true else { return }
        UpdateNotifications.postPlayReport(report)
    }

    /// The newest crash report from during the game: the Script Extender's,
    /// or one macOS wrote for the game.
    static func crashFile(since start: Date) -> URL? {
        func modified(_ url: URL) -> Date? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        if let date = modified(scriptExtenderCrashFile), date > start { return scriptExtenderCrashFile }
        let reports = URL.libraryDirectory.appending(path: "Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("Baldur") && ($0.pathExtension == "ips" || $0.pathExtension == "crash") }
            .compactMap { file in modified(file).map { (file, $0) } }
            .filter { $0.1 > start }
            .max { $0.1 < $1.1 }?.0
    }
}

extension UpdateNotifications {
    static func postPlayReport(_ report: PlayReport) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            if report.crashFile != nil {
                content.title = String(localized: "Baldur's Gate 3 crashed")
                content.body = report.errors.isEmpty
                    ? String(localized: "A crash report was saved. Open Tadpole to see it.")
                    : String(localized: "The Script Extender also logged errors: \(report.errors.map(\.source).formatted(.list(type: .and))).")
            } else {
                let total = report.errors.reduce(0) { $0 + $1.count }
                content.title = total == 1 ? String(localized: "1 Script Extender error in your last game")
                                           : String(localized: "\(total) Script Extender errors in your last game")
                content.body = report.errors.prefix(4).map { "\($0.source) (\($0.count))" }.joined(separator: ", ")
            }
            content.userInfo = ["open": "scriptExtenderLog"]
            center.add(UNNotificationRequest(identifier: "play-report", content: content, trigger: nil))
        }
    }

    /// A Script Extender release names the game's build: limited mode can end.
    static func postScriptExtenderSupportsBuild(_ release: ScriptExtenderRelease, build: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "The Script Extender supports your game")
            content.body = String(localized: "Version \(release.version) is made for game build \(build): update it to leave limited mode.")
            content.userInfo = ["open": "updates"]
            center.add(UNNotificationRequest(identifier: "script-extender-supports-build", content: content, trigger: nil))
        }
    }
}
