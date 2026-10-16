// The app's state: the mods in BG3's Mods folder, and modsettings.lsx,
// which says which of them load and in what order.

import AppKit
import Observation
import TadpoleCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let paths = GamePaths()
    private(set) var mods: [PakMod] = []
    private(set) var settings: ModSettings?
    /// Why the mod list can't be shown (the game never ran, unreadable file…).
    private(set) var blocker: Blocker?
    var selection: String?
    var message: UserMessage?
    private var runningInstalls = 0
    var isInstalling: Bool { runningInstalls > 0 }
    /// Updated when the game starts and quits (for the banner); checks
    /// before writing use `isGameRunning`, which asks macOS.
    private(set) var gameIsRunning = false
    private(set) var gameVersion: String?
    /// Mods installed while the game ran, by UUID: turned on once it quits
    /// (it would undo the change otherwise).
    private(set) var pendingEnable: [String] = []
    /// What the files looked like at the last load, to reload only when
    /// they changed.
    private var loadedSignature = ""
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    // Nexus (AppModel+Nexus.swift)
    var nexusAPIKey: String?
    var nexusAccount: NexusAccount = .none
    var downloads: [DownloadItem] = []
    @ObservationIgnored let downloadSlots = DownloadSlots(limit: 3)
    /// A page to show in the Nexus browser window.
    var browserRequest: BrowserRequest?
    /// Free accounts: Nexus file pages to click "Slow download" on, in turn.
    var browserQueue: [BrowserQueueItem] = []
    var origins = NexusOrigins.load(from: AppModel.originsFile)
    var sidebarSelection: SidebarItem? = .loadOrder
    /// Advances when the browser's work is done (a download started), so
    /// its window can close.
    var browserDone = 0
    var showInspector = true
    // The Script Extender for macOS (AppModel+ScriptExtender).
    var scriptExtender = ScriptExtenderRecord.load()
    var scriptExtenderLatest: ScriptExtenderRelease?
    /// The latest Script Extender log, and what went wrong in the last game
    /// (AppModel+PlayReport).
    var lastScriptLog: ScriptExtenderLog?
    var lastScriptLogDate: Date?
    var lastPlayReport: PlayReport?
    private(set) var gameStartedAt: Date?
    /// Named load orders, one in use (AppModel+Profiles).
    var profileStore = ProfileStore.load(from: AppModel.profilesFile)
    var profileNamePrompt: ProfileNamePrompt?
    /// When Play last backed up the latest save (mods had changed).
    var lastAutoBackup: Date?
    var showProfiles = false
    /// Nexus mods' requirements, by mod (AppModel+Requirements).
    var nexusRequirements: [Int: [NexusRequirement]] = [:]
    var scriptExtenderState = ScriptExtenderState.notInstalled
    /// What's being done (downloading, installing…), shown in Settings.
    var scriptExtenderTask: String?
    var scriptExtenderProgress: Double?

    /// Launch work (load, watchers, update checks) has run.
    var hasStarted = false
    var nexusSheet: NexusModRequest?
    /// An installed mod to link to its Nexus page (sheet).
    var linkSheet: PakMod?
    /// Nexus pages and file lists already fetched, by mod number.
    var nexusMods: [Int: NexusMod] = [:]
    var nexusFiles: [Int: [NexusFile]] = [:]

    // Mod updates (AppModel+Updates.swift)
    var updates: [ModUpdate] = []
    var lastUpdateCheck: Date?
    var isCheckingUpdates = false
    var updateCheckFailed = false
    @ObservationIgnored var updateCheckTask: Task<Void, Never>?
    var collectionSheet: CollectionRequest?

    // Saves (AppModel+Saves.swift)
    var saves: [SaveGame] = []
    var saveBackups: [SaveBackup] = []
    var isLoadingSaves = false

    enum InstallOutcome {
        case installed([PakMod])
        case nothingToInstall
        case failed(String)
    }

    enum Blocker: Equatable {
        case gameNeverRan
        case unreadableSettings(String)
    }

    struct UserMessage: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let body: String
    }

    /// A row of the load order: an installed mod, or one that's listed but
    /// whose .pak is gone.
    struct LoadOrderEntry: Identifiable, Equatable {
        let entry: ModuleShortDesc
        let mod: PakMod?
        var id: String { entry.uuid }
    }

    // MARK: Loading

    func load() {
        loadedSignature = filesSignature()
        gameVersion = readGameVersion()
        guard paths.gameHasRun else {
            blocker = .gameNeverRan
            mods = PakMod.scan(paths.modsFolder)
            return
        }
        do {
            settings = try ModSettings.read(from: paths.modSettings)
            blocker = nil
        } catch {
            blocker = .unreadableSettings(error.localizedDescription)
        }
        mods = PakMod.scan(paths.modsFolder)
        // The game may have changed the load order (it drops mods it can't load).
        ensureActiveProfile()
        trackActiveProfile()
    }

    /// Reloads if modsettings.lsx or the Mods folder changed since the last
    /// load (the game, Finder, another app…).
    func reloadIfChanged() {
        if filesSignature() != loadedSignature { load() }
    }

    /// modsettings.lsx's date, and each .pak's name, size and date.
    private func filesSignature() -> String {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        func describe(_ url: URL) -> String {
            let values = try? url.resourceValues(forKeys: keys)
            return "\(url.lastPathComponent):\(values?.fileSize ?? -1):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        let paks = (try? fm.contentsOfDirectory(at: paths.modsFolder, includingPropertiesForKeys: Array(keys))) ?? []
        return ([describe(paths.modSettings)] + paks.map(describe).sorted()).joined(separator: "|")
    }

    /// Watches the game starting and quitting, and Tadpole coming back to
    /// the front.
    func startWatching() {
        guard observers.isEmpty else { return }
        gameIsRunning = isGameRunning
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            guard AppModel.isGame(note) else { return }
            MainActor.assumeIsolated {
                AppModel.shared.gameIsRunning = true
                AppModel.shared.gameStartedAt = .now
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            guard AppModel.isGame(note) else { return }
            MainActor.assumeIsolated { AppModel.shared.gameDidQuit() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                AppModel.shared.reloadIfChanged()
                AppModel.shared.gameVersion = AppModel.shared.readGameVersion()  // Steam may have updated the game
                AppModel.shared.refreshScriptExtenderState()
            }
        })
    }

    private nonisolated static func isGame(_ note: Notification) -> Bool {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier == GamePaths.bundleIdentifier || app?.localizedName == "Baldur's Gate 3"
    }

    /// The game has just rewritten its mod list: read it again, then turn on
    /// the mods installed while it ran.
    private func gameDidQuit() {
        gameIsRunning = false
        let started = gameStartedAt
        Task { await reportAfterPlaying(startedAt: started) }
        Task {
            try? await Task.sleep(for: .seconds(1))  // let the last writes land
            load()
            let waiting = pendingEnable
            pendingEnable = []
            let byID = modsByID
            enable(waiting.compactMap { byID[$0] })
        }
    }

    private var modsByID: [String: PakMod] {
        Dictionary(mods.compactMap { mod in mod.info.map { ($0.uuid, mod) } }, uniquingKeysWith: { first, _ in first })
    }

    /// Mods that load, in order (missing ones included, so they can be removed).
    var loadOrder: [LoadOrderEntry] {
        let byID = modsByID
        return (settings?.modEntries ?? []).map { LoadOrderEntry(entry: $0, mod: byID[$0.uuid]) }
    }

    var enabledMods: [PakMod] { loadOrder.compactMap(\.mod) }

    /// Installed mods that aren't in the load order.
    var disabledMods: [PakMod] {
        // Duplicates have their own section.
        let skipped = Set(settings?.modEntries.map(\.uuid) ?? []).union(duplicates.keys)
        return mods.filter { mod in mod.info.map { !skipped.contains($0.uuid) } ?? false }
    }

    /// .pak files without a meta.lsx: the game loads them all the time.
    var overrideMods: [PakMod] { mods.filter { $0.info == nil && $0.error == nil } }
    var unreadableMods: [PakMod] { mods.filter { $0.error != nil } }

    /// Mods installed more than once (the same UUID in several .pak files),
    /// by UUID. The game loads only one of them.
    var duplicates: [String: [PakMod]] {
        Dictionary(grouping: mods.filter { $0.info != nil }, by: { $0.info!.uuid }).filter { $0.value.count > 1 }
    }

    /// Keeps the copy with the highest version (the newest file on a tie)
    /// and moves the others to the Trash.
    func keepNewest(_ copies: [PakMod]) {
        for extra in PakMod.newestFirst(copies).dropFirst() {
            try? FileManager.default.trashItem(at: extra.file, resultingItemURL: nil)
        }
        load()
    }

    var problems: [String: [ModRules.Problem]] {
        ModRules.problems(enabled: enabledMods.compactMap(\.info), installed: mods.compactMap(\.info))
    }

    // MARK: Changing the load order

    func setEnabled(_ mod: PakMod, _ enabled: Bool) {
        guard let info = mod.info, var settings else { return }
        var entries = settings.modEntries
        if enabled {
            guard !entries.contains(where: { $0.uuid == info.uuid }) else { return }
            entries.append(ModuleShortDesc(info))
        } else {
            entries.removeAll { $0.uuid == info.uuid }
        }
        settings.setEnabledMods(entries)
        save(settings)
    }

    /// Turns on several mods at once, at the end of the load order. While
    /// the game runs, they wait until it quits.
    func enable(_ mods: [PakMod]) {
        let infos = mods.compactMap(\.info)
        guard !infos.isEmpty, var settings else { return }
        if isGameRunning {
            pendingEnable += infos.map(\.uuid).filter { !pendingEnable.contains($0) }
            return
        }
        var entries = settings.modEntries
        for info in infos {
            if let index = entries.firstIndex(where: { $0.uuid == info.uuid }) {
                entries[index] = ModuleShortDesc(info)  // an update: same place, new version
            } else {
                entries.append(ModuleShortDesc(info))
            }
        }
        guard entries != settings.modEntries else { return }
        settings.setEnabledMods(entries)
        save(settings)
    }

    func remove(_ entry: ModuleShortDesc) {
        guard var settings else { return }
        settings.setEnabledMods(settings.modEntries.filter { $0.uuid != entry.uuid })
        save(settings)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard var settings else { return }
        var entries = settings.modEntries
        entries.move(fromOffsets: source, toOffset: destination)
        settings.setEnabledMods(entries)
        save(settings)
    }

    /// Moves each mod's requirements before it, keeping the rest of the order.
    func sortByDependencies() {
        guard var settings else { return }
        let byID = modsByID
        let installed = settings.modEntries.compactMap { byID[$0.uuid]?.info }
        let sorted = ModRules.dependencyOrder(installed).map(ModuleShortDesc.init)
        let missing = settings.modEntries.filter { byID[$0.uuid] == nil }
        settings.setEnabledMods(sorted + missing)
        save(settings)
    }

    /// Writes the load order (and records it in the profile in use).
    func save(_ new: ModSettings) {
        guard !isGameRunning else {
            return show("Quit Baldur's Gate 3 First", String(localized: "The game rewrites its mod list when it quits, which would undo this change."))
        }
        do {
            try new.write(to: paths.modSettings)
            settings = new
            trackActiveProfile()
        } catch {
            show("Couldn't Save the Load Order", error.localizedDescription)
        }
    }

    // MARK: Installing and removing

    func presentInstallPanel() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose mods to install (.pak files, or .zip archives from Nexus Mods)")
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["pak", "zip", "7z", "rar"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { install(panel.urls) }
    }

    /// Installs .pak files and archives. With `quiet`, problems are only
    /// returned (downloads show them in their own row).
    @discardableResult
    func install(_ urls: [URL], quiet: Bool = false) -> Task<InstallOutcome, Never> {
        runningInstalls += 1
        let folder = paths.modsFolder
        return Task {
            defer { runningInstalls -= 1 }
            do {
                let result = try await Task.detached { try ModInstaller.install(urls, into: folder) }.value
                load()
                // New mods are turned on, at the end of the load order.
                let installed = result.installed.map(PakMod.read)
                enable(installed)
                if !result.skipped.isEmpty, !quiet {
                    show("Some Files Weren't Installed",
                         String(localized: "No .pak file was found in: \(result.skipped.formatted(.list(type: .and))). Mods made of loose files or for the Script Extender can't be installed this way."))
                }
                if let first = installed.first { selection = first.id }
                return installed.isEmpty ? .nothingToInstall : .installed(installed)
            } catch {
                if !quiet { show("Couldn't Install", error.localizedDescription) }
                return .failed(error.localizedDescription)
            }
        }
    }

    func trash(_ mod: PakMod) {
        if let info = mod.info, settings?.modEntries.contains(where: { $0.uuid == info.uuid }) == true {
            // The game would keep listing a mod whose file is gone.
            guard !isGameRunning else {
                return show("Quit Baldur's Gate 3 First", String(localized: "This mod is in the load order. Quit the game before removing it."))
            }
            setEnabled(mod, false)
        }
        do {
            try FileManager.default.trashItem(at: mod.file, resultingItemURL: nil)
        } catch {
            show("Couldn't Move to the Trash", error.localizedDescription)
        }
        load()
    }

    // MARK: Game

    var isGameRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == GamePaths.bundleIdentifier || $0.localizedName == "Baldur's Gate 3" }
    }

    /// Starts the game through Steam; after a game update, the Script
    /// Extender is applied again first.
    func launchGame() {
        Task {
            await reapplyScriptExtenderIfNeeded()
            await backUpLatestSaveIfModsChanged()
            // Test copies (TADPOLE_SKIP_LAUNCH=1) don't start the real game.
            guard ProcessInfo.processInfo.environment["TADPOLE_SKIP_LAUNCH"] == nil else { return }
            if let url = URL(string: "steam://rungameid/\(GamePaths.steamAppID)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// The game's app, wherever Steam put it.
    var gameApp: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: GamePaths.bundleIdentifier)
    }

    /// Read again by load(): the status bar shows it on every page.
    private func readGameVersion() -> String? {
        gameApp.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
    }

    func openModsFolder() {
        try? FileManager.default.createDirectory(at: paths.modsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(paths.modsFolder)
    }

    func show(_ title: String.LocalizationValue, _ body: String) {
        message = UserMessage(title: String(localized: title), body: body)
    }
}
