// Updates of the app itself, through Sparkle: it reads the feed in
// Info.plist (SUFeedURL), shows the release notes embedded in it, and
// checks each update's signature against SUPublicEDKey.
//
// TADPOLE_FEED_URL replaces the feed, to try an update from a local
// server before publishing it.

import Sparkle
import SwiftUI

@MainActor
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    /// Whether this build knows where to look for updates.
    let isConfigured: Bool
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String) ?? ""
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        isConfigured = !feed.isEmpty && !key.isEmpty
        super.init()
        guard isConfigured else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        let override = ProcessInfo.processInfo.environment["TADPOLE_FEED_URL"]
        return override?.isEmpty == false ? override : nil
    }
}
