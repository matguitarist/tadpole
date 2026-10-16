// The Script Extender for macOS (tdimino/bg3se-macos): installed into the
// game on request, kept up to date from its GitHub releases, and applied
// again after game updates (Steam replaces the patched executable).

import AppKit
import TadpoleCore
@preconcurrency import UserNotifications

/// What Tadpole installed: the release, and a copy of its library so it can
/// be applied again after a game update without downloading.
struct ScriptExtenderRecord: Codable, Equatable {
    var release: ScriptExtenderRelease
    /// Tadpole turned the Larian launcher off (as install.sh does), so
    /// removing the Script Extender turns it back on.
    var disabledLauncher: Bool

    /// Test copies (TADPOLE_BG3_APP) keep theirs next to the fake game.
    static var folder: URL {
        if let override = ProcessInfo.processInfo.environment["TADPOLE_BG3_APP"], !override.isEmpty {
            return URL(filePath: override).deletingLastPathComponent().appending(path: "Tadpole Script Extender", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Tadpole/Script Extender", directoryHint: .isDirectory)
    }
    static var file: URL { folder.appending(path: "installed.json") }
    static var library: URL { folder.appending(path: ScriptExtenderMac.libraryName) }

    static func load() -> ScriptExtenderRecord? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ScriptExtenderRecord.self, from: data)
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try encoder.encode(self).write(to: Self.file, options: .atomic)
    }
}

/// The Script Extender's state in the game, read from the game's files.
enum ScriptExtenderState: Equatable {
    case notInstalled
    case active
    /// Installed by Tadpole, but the game was updated since (or the library
    /// was removed): it needs to be applied again.
    case needsReapply
    /// In the game, but not installed by Tadpole (install.sh, another app).
    case installedElsewhere
}

extension AppModel {
    /// The game the Script Extender goes into. TADPOLE_BG3_APP points at
    /// another copy (for testing without touching the real game).
    var scriptExtenderGame: ScriptExtenderMac.Game? {
        if let override = ProcessInfo.processInfo.environment["TADPOLE_BG3_APP"], !override.isEmpty {
            return ScriptExtenderMac.Game(app: URL(filePath: override, directoryHint: .isDirectory))
        }
        return gameApp.map(ScriptExtenderMac.Game.init)
    }

    /// The Script Extender is in the game and loads: Script Extender mods work
    /// (as far as the macOS version supports them).
    var scriptExtenderIsActive: Bool { scriptExtenderState == .active || scriptExtenderState == .installedElsewhere }

    /// A newer release than the installed one.
    var scriptExtenderUpdate: ScriptExtenderRelease? {
        guard let installed = scriptExtender?.release, let latest = scriptExtenderLatest,
              ScriptExtenderMac.isNewer(latest.version, than: installed.version) else { return nil }
        return latest
    }

    /// Mod updates plus a Script Extender update, for badges.
    var updateCount: Int { updates.count + (scriptExtenderUpdate == nil ? 0 : 1) }

    /// Reads the game's files again (at launch, when Tadpole comes back to
    /// the front, after changes).
    func refreshScriptExtenderState() {
        guard let game = scriptExtenderGame else { return scriptExtenderState = .notInstalled }
        Task {
            let (patched, hasLibrary) = await Task.detached { (game.isPatched, game.hasLibrary) }.value
            scriptExtenderState = switch (scriptExtender != nil, patched && hasLibrary) {
            case (_, true): scriptExtender == nil ? .installedElsewhere : .active
            case (true, false): .needsReapply
            case (false, false): .notInstalled
            }
        }
    }

    /// The newest release on GitHub. Errors are kept quiet: it's checked
    /// again with the next update check.
    func checkScriptExtenderRelease(notify: Bool = false) async {
        guard let latest = try? await ScriptExtenderMac.latestRelease() else { return }
        let wasKnown = scriptExtenderUpdate?.version == latest.version
        scriptExtenderLatest = latest
        if notify, !wasKnown, let update = scriptExtenderUpdate { UpdateNotifications.postScriptExtender(update) }
    }

    /// Downloads and installs a release (the latest by default), or applies
    /// the installed one again.
    func installScriptExtender(_ release: ScriptExtenderRelease? = nil) {
        guard scriptExtenderTask == nil else { return }
        guard let game = scriptExtenderGame else {
            return show("Baldur's Gate 3 Not Found", String(localized: "Install the game through Steam first."))
        }
        guard !isGameRunning else {
            return show("Quit Baldur's Gate 3 First", String(localized: "The Script Extender is installed into the game, which can't be changed while it runs."))
        }
        scriptExtenderTask = String(localized: "Checking for the latest release…")
        scriptExtenderProgress = nil
        Task {
            defer {
                scriptExtenderTask = nil
                scriptExtenderProgress = nil
                refreshScriptExtenderState()
            }
            do {
                let release = if let release { release } else { try await ScriptExtenderMac.latestRelease() }
                scriptExtenderLatest = scriptExtenderLatest ?? release
                scriptExtenderTask = String(localized: "Downloading the Script Extender \(release.version)…")
                let downloaded = try await ScriptExtenderMac.download(release) { progress in
                    Task { @MainActor in AppModel.shared.scriptExtenderProgress = progress }
                }
                scriptExtenderProgress = nil
                scriptExtenderTask = String(localized: "Installing into the game…")
                let fm = FileManager.default
                try fm.createDirectory(at: ScriptExtenderRecord.folder, withIntermediateDirectories: true)
                if fm.fileExists(atPath: ScriptExtenderRecord.library.path(percentEncoded: false)) {
                    try fm.removeItem(at: ScriptExtenderRecord.library)
                }
                try fm.copyItem(at: downloaded, to: ScriptExtenderRecord.library)
                try? fm.removeItem(at: downloaded.deletingLastPathComponent())
                try await apply(to: game)
                let disabledLauncher = scriptExtender?.disabledLauncher ?? Self.disableLarianLauncher()
                scriptExtender = ScriptExtenderRecord(release: release, disabledLauncher: disabledLauncher)
                try scriptExtender?.save()
            } catch {
                showScriptExtenderError(error)
            }
        }
    }

    /// After a game update: the same release, from Tadpole's copy.
    func reapplyScriptExtender() {
        guard scriptExtenderTask == nil, let game = scriptExtenderGame else { return }
        guard !isGameRunning else {
            return show("Quit Baldur's Gate 3 First", String(localized: "The Script Extender is installed into the game, which can't be changed while it runs."))
        }
        guard FileManager.default.fileExists(atPath: ScriptExtenderRecord.library.path(percentEncoded: false)) else {
            return installScriptExtender(scriptExtender?.release)  // the copy is gone: download it again
        }
        scriptExtenderTask = String(localized: "Installing into the game…")
        Task {
            defer {
                scriptExtenderTask = nil
                refreshScriptExtenderState()
            }
            do {
                try await apply(to: game)
            } catch {
                showScriptExtenderError(error)
            }
        }
    }

    private func apply(to game: ScriptExtenderMac.Game) async throws {
        let library = ScriptExtenderRecord.library
        try await Task.detached { try game.install(library: library) }.value
    }

    func removeScriptExtender() {
        guard scriptExtenderTask == nil else { return }
        guard !isGameRunning else {
            return show("Quit Baldur's Gate 3 First", String(localized: "The Script Extender is installed into the game, which can't be changed while it runs."))
        }
        scriptExtenderTask = String(localized: "Removing the Script Extender…")
        let game = scriptExtenderGame
        Task {
            defer {
                scriptExtenderTask = nil
                refreshScriptExtenderState()
            }
            do {
                if let game { try await Task.detached { try game.uninstall() }.value }
                if scriptExtender?.disabledLauncher == true { Self.restoreLarianLauncher() }
                try? FileManager.default.removeItem(at: ScriptExtenderRecord.folder)
                scriptExtender = nil
            } catch {
                showScriptExtenderError(error)
            }
        }
    }

    /// Before Play: after a game update, the Script Extender is applied
    /// again first (the game must not be running, which it isn't yet).
    func reapplyScriptExtenderIfNeeded() async {
        guard scriptExtenderState == .needsReapply, let game = scriptExtenderGame, !isGameRunning,
              FileManager.default.fileExists(atPath: ScriptExtenderRecord.library.path(percentEncoded: false)) else { return }
        do {
            try await apply(to: game)
        } catch {
            showScriptExtenderError(error)
        }
        refreshScriptExtenderState()
    }

    private func showScriptExtenderError(_ error: Error) {
        let nsError = error as NSError
        let denied = (nsError.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(nsError.code))
            || (nsError.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(nsError.code))
            || (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map { $0.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains($0.code) } == true
        if denied {
            show("Tadpole Can't Change the Game", String(localized: "macOS stops apps from changing other apps unless you allow it. Turn on Tadpole in System Settings → Privacy & Security → App Management, then try again."))
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
        } else {
            show("Script Extender Not Installed", AppModel.describe(error))
        }
    }

    // MARK: The Larian launcher

    /// install.sh turns the launcher off so the game starts directly; Tadpole
    /// does the same. Returns whether it changed the setting.
    private static func disableLarianLauncher() -> Bool {
        // Test copies (TADPOLE_BG3_APP) leave the real game's settings alone.
        guard ProcessInfo.processInfo.environment["TADPOLE_BG3_APP"] == nil else { return false }
        let domain = GamePaths.bundleIdentifier as CFString
        if (CFPreferencesCopyAppValue("NoLauncher" as CFString, domain) as? Bool) == true { return false }
        CFPreferencesSetAppValue("NoLauncher" as CFString, true as CFBoolean, domain)
        CFPreferencesAppSynchronize(domain)
        return true
    }

    private static func restoreLarianLauncher() {
        let domain = GamePaths.bundleIdentifier as CFString
        CFPreferencesSetAppValue("NoLauncher" as CFString, nil, domain)
        CFPreferencesAppSynchronize(domain)
    }
}

extension UpdateNotifications {
    static func postScriptExtender(_ release: ScriptExtenderRelease) {
        guard UserDefaults.standard.object(forKey: Preferences.notifyModUpdates) as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Script Extender \(release.version) is available")
            content.body = String(localized: "Update it from the Updates page.")
            center.add(UNNotificationRequest(identifier: "script-extender-update", content: content, trigger: nil))
        }
    }
}
