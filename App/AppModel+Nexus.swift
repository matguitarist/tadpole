// Nexus Mods: the API key and account, and mods downloaded from Nexus.
// Premium accounts download directly. Free accounts go through the in-app
// browser: Tadpole opens each file's page, the user clicks "Slow download",
// and the nxm:// link the site hands over is caught and installed.

import AppKit
import TadpoleCore

extension AppModel {
    /// Nexus account state, from the saved API key.
    enum NexusAccount: Equatable {
        case none
        case checking
        case signedIn(NexusUser)
        case invalid(String)

        var user: NexusUser? {
            if case .signedIn(let user) = self { user } else { nil }
        }
    }

    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

    /// Test copies (TADPOLE_BG3_DOCUMENTS) keep theirs next to their game
    /// folder, not in the real one.
    static var originsFile: URL {
        if let override = ProcessInfo.processInfo.environment["TADPOLE_BG3_DOCUMENTS"], !override.isEmpty {
            return URL(filePath: override).deletingLastPathComponent().appending(path: "tadpole-nexus-origins.json")
        }
        return URL.applicationSupportDirectory.appending(path: "Tadpole/nexus-origins.json")
    }

    var nexusClient: NexusClient { NexusClient(apiKey: nexusAPIKey, appVersion: Self.appVersion) }

    // MARK: API key

    func loadNexusAccount() {
        // Test copies (TADPOLE_SKIP_KEYCHAIN=1) don't read the key.
        guard ProcessInfo.processInfo.environment["TADPOLE_SKIP_KEYCHAIN"] == nil else { return }
        nexusAccount = .checking
        Task {
            nexusAPIKey = await Task.detached { Keychain.readNexusAPIKey() }.value
            await validateNexusKey()
        }
    }

    func setNexusAPIKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try Keychain.saveNexusAPIKey(trimmed)
        } catch {
            show("Couldn't Save the API Key", error.localizedDescription)
            return
        }
        nexusAPIKey = trimmed
        await validateNexusKey()
    }

    func removeNexusAPIKey() {
        Keychain.deleteNexusAPIKey()
        nexusAPIKey = nil
        nexusAccount = .none
    }

    private func validateNexusKey() async {
        guard nexusAPIKey != nil else {
            nexusAccount = .none
            return
        }
        nexusAccount = .checking
        do {
            nexusAccount = .signedIn(try await nexusClient.validateKey())
        } catch {
            nexusAccount = .invalid(Self.describe(error))
        }
    }

    // MARK: What's installed

    /// Nexus mods with an installed .pak (from downloads made in Tadpole).
    var installedNexusModIDs: Set<Int> {
        origins.installedModIDs(installedPaks: Set(mods.map(\.file.lastPathComponent)))
    }

    /// Nexus mods whose installed .pak ships Script Extender scripts.
    var installedScriptExtenderModIDs: Set<Int> {
        Set(mods.filter(\.usesScriptExtender).compactMap { origins.byPak[$0.file.lastPathComponent]?.modID })
    }

    /// The installed .pak files that came from this Nexus mod.
    func installedFiles(ofNexusMod modID: Int) -> [NexusOrigins.Origin] {
        let installed = Set(mods.map(\.file.lastPathComponent))
        return origins.byPak.filter { installed.contains($0.key) && $0.value.modID == modID }.map(\.value)
    }

    // MARK: Links between installed mods and Nexus

    /// The Nexus mod an installed .pak came from (downloaded in Tadpole, or
    /// linked by hand).
    func nexusOrigin(of mod: PakMod) -> NexusOrigins.Origin? {
        origins.byPak[mod.file.lastPathComponent]
    }

    /// Links an installed mod to a Nexus mod page (which file isn't known).
    func link(_ mod: PakMod, toNexusMod modID: Int) {
        origins.byPak[mod.file.lastPathComponent] = NexusOrigins.Origin(modID: modID, fileID: 0)
        try? origins.save(to: Self.originsFile)
    }

    func unlink(_ mod: PakMod) {
        origins.byPak[mod.file.lastPathComponent] = nil
        try? origins.save(to: Self.originsFile)
    }

    /// The Nexus pages (pictures, names) of installed mods linked to Nexus,
    /// a few at a time: for the load order's pictures.
    func loadInstalledNexusPages() async {
        let ids = Array(Set(mods.compactMap { nexusOrigin(of: $0)?.modID })).filter { nexusMods[$0] == nil }.sorted()
        let client = nexusClient
        for start in stride(from: 0, to: ids.count, by: 4) {
            await withTaskGroup(of: NexusMod?.self) { group in
                for id in ids[start..<min(start + 4, ids.count)] { group.addTask { try? await client.mod(id: id) } }
                for await page in group { if let page { nexusMods[page.modId] = page } }
            }
        }
    }

    /// Fetches a Nexus mod's page, files and requirements once (forced: again).
    func loadNexusDetails(_ modID: Int, force: Bool = false) async throws {
        let client = nexusClient
        // Both before storing either: storing the files changes the view,
        // which can cancel the task that's still waiting for the page.
        let needsPage = force || nexusMods[modID] == nil
        let needsFiles = force || nexusFiles[modID] == nil
        let needsRequirements = force || nexusRequirements[modID] == nil
        async let page = needsPage ? try? client.mod(id: modID) : nil
        async let files = needsFiles ? client.files(forMod: modID) : nil
        async let requirements = needsRequirements ? try? client.requirements(forMod: modID) : nil
        let (fetchedPage, fetchedFiles, fetchedRequirements) = try await (page, files, requirements)
        if let fetchedPage { nexusMods[modID] = fetchedPage }
        if let fetchedFiles { nexusFiles[modID] = fetchedFiles }
        if let fetchedRequirements { nexusRequirements[modID] = fetchedRequirements }
    }

    // MARK: Installing from Nexus

    /// Installs Nexus files: Premium downloads them now, free accounts get
    /// each file's page in the browser, in turn.
    func installFromNexus(_ files: [BrowserQueueItem]) {
        guard !files.isEmpty else { return }
        guard nexusAPIKey != nil else {
            return show("Nexus API Key Needed", String(localized: "Add your personal Nexus Mods API key in Settings to download mods."))
        }
        if nexusAccount.user?.isPremium == true {
            for file in files { download(modID: file.modID, fileID: file.fileID, title: file.title, replacing: file.replacing) }
        } else {
            let queued = Set(browserQueue.map(\.fileID))
            browserQueue += files.filter { !queued.contains($0.fileID) }
            if let first = browserQueue.first { openNexusBrowser(first.pageURL) }
        }
    }

    func openNexusBrowser(_ url: URL = NexusClient.homeURL) {
        browserRequest = BrowserRequest(url: url)
    }

    /// A "Mod Manager Download" link caught by the in-app browser.
    func handleNXMLink(_ url: URL) {
        guard let link = NXMLink(url: url) else {
            return show("Unsupported Link", url.absoluteString)
        }
        guard link.isForBG3 else {
            return show("Not a Baldur's Gate 3 Mod", String(localized: "This link is for “\(link.gameDomain)”. Only Baldur's Gate 3 mods can be installed here."))
        }
        let queued = browserQueue.first { $0.fileID == link.fileID }
        download(modID: link.modID, fileID: link.fileID, title: queued?.title, key: link.key, expires: link.expires,
                 replacing: queued?.replacing ?? [])
        browserQueue.removeAll { $0.fileID == link.fileID }
        if let next = browserQueue.first {
            openNexusBrowser(next.pageURL)
        } else {
            browserFinished()
        }
    }

    /// The download continues in the main window: close the browser
    /// (unless that's turned off in Settings).
    func browserFinished() {
        if UserDefaults.standard.object(forKey: Preferences.closeBrowserAfterDownload) as? Bool ?? true {
            browserDone += 1
        }
    }

    func skipQueuedDownload() {
        guard !browserQueue.isEmpty else { return }
        browserQueue.removeFirst()
        if let next = browserQueue.first { openNexusBrowser(next.pageURL) }
    }

    func cancelDownloadQueue() {
        browserQueue = []
    }

    private func download(modID: Int, fileID: Int, title: String?, key: String? = nil, expires: String? = nil, replacing: [String] = []) {
        guard nexusAPIKey != nil else {
            return show("Nexus API Key Needed", String(localized: "Add your personal Nexus Mods API key in Settings to download mods."))
        }
        let item = DownloadItem(title: title ?? String(localized: "Nexus mod \(modID)"))
        downloads.insert(item, at: 0)
        let client = nexusClient
        if title == nil {
            Task { if let name = try? await client.modName(modID) { item.title = name } }
        }
        let slots = downloadSlots
        item.task = Task {
            // A few at a time: a big collection would otherwise hit Nexus's
            // rate limit.
            do {
                try await slots.acquire()
            } catch {
                item.state = .cancelled
                return
            }
            defer { slots.release() }
            do {
                item.state = .starting
                let url = try await client.downloadURL(modID: modID, fileID: fileID, key: key, expires: expires)
                try Task.checkCancellation()
                item.state = .downloading
                let file = try await FileDownloader.download(url) { fraction in
                    Task { @MainActor in item.progress = fraction }
                }
                try Task.checkCancellation()
                await installDownloaded(file, item: item, origin: NexusOrigins.Origin(modID: modID, fileID: fileID), replacing: replacing)
            } catch is CancellationError {
                item.state = .cancelled
            } catch let error as URLError where error.code == .cancelled {
                item.state = .cancelled
            } catch {
                item.state = Task.isCancelled ? .cancelled : .failed(Self.describe(error))
            }
        }
    }

    /// An archive downloaded directly in the browser ("Manual download").
    func installBrowserDownload(_ file: URL) {
        let item = DownloadItem(title: file.lastPathComponent)
        downloads.insert(item, at: 0)
        browserFinished()
        Task { await installDownloaded(file, item: item, origin: nil) }
    }

    private func installDownloaded(_ file: URL, item: DownloadItem, origin: NexusOrigins.Origin?, replacing: [String] = []) async {
        item.state = .installing
        let outcome = await install([file], quiet: true).value
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        switch outcome {
        case .installed(let mods):
            item.state = .installed(mods.map(\.name))
            if let origin {
                for mod in mods { origins.byPak[mod.file.lastPathComponent] = origin }
                try? origins.save(to: Self.originsFile)
                if !replacing.isEmpty { finishUpdate(replacing: replacing, installed: mods, fileID: origin.fileID) }
            }
        case .nothingToInstall:
            item.state = .failed(String(localized: "No .pak file in this download. Mods made of loose files or for the Script Extender can't be installed by Tadpole."))
        case .failed(let message):
            item.state = .failed(message)
        }
    }

    func clearFinishedDownloads() {
        downloads.removeAll { $0.isFinished }
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? NexusError else { return error.localizedDescription }
        switch error {
        case .noAPIKey:
            return String(localized: "Add your personal Nexus Mods API key in Settings to download mods.")
        case .keyRejected(let message):
            return message ?? String(localized: "Your Nexus Mods API key was rejected. Check it in Settings.")
        case .premiumOnly(let message):
            return message ?? String(localized: "Nexus only allows direct downloads for Premium members. Use “Mod Manager Download” on the website instead.")
        case .rateLimited:
            return String(localized: "Nexus rate limit reached. Try again in a little while.")
        case .failed(let status, let message):
            return message ?? String(localized: "Nexus request failed (HTTP \(status)).")
        case .noDownloadLink:
            return String(localized: "Nexus didn't return a download link for this file.")
        }
    }
}

struct BrowserRequest: Equatable {
    let id = UUID()
    let url: URL
}

/// A Nexus file to download (free accounts: a page waiting in the browser).
struct BrowserQueueItem: Identifiable, Equatable {
    let modID: Int
    let fileID: Int
    let title: String
    /// For an update: the installed .pak files the new version replaces.
    var replacing: [String] = []

    var id: Int { fileID }
    var pageURL: URL { NexusClient.modManagerDownloadPageURL(modID: modID, fileID: fileID) }
}

/// A Nexus mod page shown in a sheet (from Browse, or a collection).
struct NexusModRequest: Identifiable, Equatable {
    let modID: Int
    var preview: NexusMod?
    var id: Int { modID }
}

struct CollectionRequest: Identifiable, Equatable {
    let collection: NexusCollection
    var id: String { collection.slug }
}

/// One download from Nexus.
@MainActor
@Observable
final class DownloadItem: Identifiable {
    enum State: Equatable {
        case waiting, starting, downloading, installing
        case installed([String])
        case failed(String)
        case cancelled
    }

    let id = UUID()
    var title: String
    var state: State = .waiting
    var progress = 0.0
    @ObservationIgnored var task: Task<Void, Never>?

    /// Until it starts installing (an install isn't stopped halfway).
    var canCancel: Bool {
        task != nil && [.waiting, .starting, .downloading].contains(state)
    }

    func cancel() {
        task?.cancel()
    }

    init(title: String) {
        self.title = title
    }

    var isInstalled: Bool { if case .installed = self.state { true } else { false } }

    var isFinished: Bool {
        switch state {
        case .installed, .failed, .cancelled: true
        default: false
        }
    }
}

/// Lets a few downloads run at once; the others wait their turn.
@MainActor
final class DownloadSlots {
    private let limit: Int
    private var used = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async throws {
        if used < limit {
            used += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(id) }
        }
    }

    /// Hands the slot to the next waiting download, if any.
    func release() {
        if waiters.isEmpty {
            used -= 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
