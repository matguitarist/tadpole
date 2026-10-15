// Nexus Mods: the API key and account, and mods downloaded from the in-app
// browser ("Mod Manager Download" links, or archives downloaded directly).

import AppKit
import TadpoleCore

extension AppModel {
    /// Nexus account state, from the API key in the Keychain.
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

    var nexusClient: NexusClient { NexusClient(apiKey: nexusAPIKey, appVersion: Self.appVersion) }

    // MARK: API key

    func loadNexusAccount() {
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

    // MARK: Downloads

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
        guard nexusAPIKey != nil else {
            return show("Nexus API Key Needed", String(localized: "Add your personal Nexus Mods API key in Settings to download mods."))
        }
        let item = DownloadItem(title: String(localized: "Nexus mod \(link.modID)"))
        downloads.insert(item, at: 0)
        let client = nexusClient
        Task {
            if let name = try? await client.modName(link.modID) { item.title = name }
        }
        Task {
            do {
                let url = try await client.downloadURL(for: link)
                item.state = .downloading
                let file = try await FileDownloader.download(url) { fraction in
                    Task { @MainActor in item.progress = fraction }
                }
                await installDownloaded(file, item: item)
            } catch {
                item.state = .failed(Self.describe(error))
            }
        }
    }

    /// An archive downloaded directly in the browser ("Manual download").
    func installBrowserDownload(_ file: URL) {
        let item = DownloadItem(title: file.lastPathComponent)
        downloads.insert(item, at: 0)
        Task { await installDownloaded(file, item: item) }
    }

    private func installDownloaded(_ file: URL, item: DownloadItem) async {
        item.state = .installing
        let outcome = await install([file]).value
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        switch outcome {
        case .installed(let names): item.state = .installed(names)
        case .nothingToInstall: item.state = .failed(String(localized: "No .pak file in this download. Mods made of loose files or for the Script Extender can't be installed by Tadpole."))
        case .failed(let message): item.state = .failed(message)
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

/// One download from Nexus, shown in the browser window.
@MainActor
@Observable
final class DownloadItem: Identifiable {
    enum State: Equatable {
        case starting, downloading, installing
        case installed([String])
        case failed(String)
    }

    let id = UUID()
    var title: String
    var state: State = .starting
    var progress = 0.0

    init(title: String) {
        self.title = title
    }

    var isFinished: Bool {
        switch state {
        case .installed, .failed: true
        default: false
        }
    }
}
