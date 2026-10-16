// User preferences (UserDefaults keys), the app's language and theme, and
// the About panel.

import AppKit
import SwiftUI

enum Preferences {
    static let theme = "theme"
    static let closeBrowserAfterDownload = "closeBrowserAfterDownload"
    static let settingsTab = "settingsTab"
    static let checkModUpdates = "checkModUpdates"
    static let notifyModUpdates = "notifyModUpdates"
    static let skipScriptExtenderMods = "skipScriptExtenderMods"
    static let showMenuBarIcon = "showMenuBarIcon"  // default on
    static let reportAfterPlaying = "reportAfterPlaying"  // default on
}

/// Light, dark, or whatever macOS uses.
enum AppTheme: String, CaseIterable {
    case system, light, dark

    static var current: AppTheme {
        UserDefaults.standard.string(forKey: Preferences.theme).flatMap(AppTheme.init) ?? .system
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Applies to every window, including Settings and Help.
    @MainActor
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The app's own language, independent of macOS's. Stored as the app's
/// AppleLanguages default, which macOS reads at launch.
struct AppLanguage: Hashable {
    /// A localization code ("fr"), or nil to follow macOS.
    let code: String?

    static let system = AppLanguage(code: nil)
    private static let key = "AppleLanguages"

    /// The app's translations, sorted by their own names.
    static let available: [AppLanguage] = Set(Bundle.main.localizations)
        .subtracting(["Base"])
        .map { AppLanguage(code: $0) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    /// "Français", "English".
    var name: String {
        guard let code else { return "" }
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let stored = (domain?[key] as? [String])?.first else { return .system }
        let codes = available.compactMap(\.code)
        guard let match = Bundle.preferredLocalizations(from: codes, forPreferences: [stored]).first,
              codes.contains(match) else { return .system }
        return AppLanguage(code: match)
    }

    /// What this run of the app uses (the setting can change after launch).
    static let atLaunch = current

    /// The language macOS would pick for the app, by name.
    static var systemName: String {
        let global = UserDefaults(suiteName: UserDefaults.globalDomain)?.stringArray(forKey: key) ?? Locale.preferredLanguages
        let code = Bundle.preferredLocalizations(from: available.compactMap(\.code), forPreferences: global).first ?? "en"
        return AppLanguage(code: code).name
    }

    func apply() {
        if let code {
            UserDefaults.standard.set([code], forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }

    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// The standard About panel, with a short credit line.
@MainActor
enum AboutPanel {
    static func show() {
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString(
            string: String(localized: "Mod manager for Baldur's Gate 3 on macOS.") + "\n\n"
                + String(localized: "Mod pages, files and collections come from Nexus Mods. Not affiliated with Larian Studios or Nexus Mods."),
            attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor])
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        credits.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}

enum AppLinks {
    static let scriptExtender = URL(string: "https://github.com/Norbyte/bg3se")!
    static let nexusBG3 = URL(string: "https://www.nexusmods.com/baldursgate3")!
    static let releases = URL(string: "https://github.com/matguitarist/tadpole/releases")!
}
