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
    var isInstalling = false

    // Nexus (AppModel+Nexus.swift)
    var nexusAPIKey: String?
    var nexusAccount: NexusAccount = .none
    var downloads: [DownloadItem] = []
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
    var nexusSheet: NexusModRequest?
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
        let listed = Set(settings?.modEntries.map(\.uuid) ?? [])
        return mods.filter { mod in mod.info.map { !listed.contains($0.uuid) } ?? false }
    }

    /// .pak files without a meta.lsx: the game loads them all the time.
    var overrideMods: [PakMod] { mods.filter { $0.info == nil && $0.error == nil } }
    var unreadableMods: [PakMod] { mods.filter { $0.error != nil } }

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

    private func save(_ new: ModSettings) {
        guard !isGameRunning else {
            return show("Quit Baldur's Gate 3 First", String(localized: "The game rewrites its mod list when it quits, which would undo this change."))
        }
        do {
            try new.write(to: paths.modSettings)
            settings = new
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
        isInstalling = true
        let folder = paths.modsFolder
        return Task {
            defer { isInstalling = false }
            do {
                let result = try await Task.detached { try ModInstaller.install(urls, into: folder) }.value
                load()
                // New mods are turned on, at the end of the load order.
                let installed = result.installed.map(PakMod.read)
                for mod in installed where mod.info != nil { setEnabled(mod, true) }
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

    func launchGame() {
        if let url = URL(string: "steam://rungameid/\(GamePaths.steamAppID)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The game's app, wherever Steam put it.
    var gameApp: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: GamePaths.bundleIdentifier)
    }

    var gameVersion: String? {
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
