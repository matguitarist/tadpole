// Profiles (TadpoleCore/Profiles): one is always in use and follows the
// load order; switching writes another profile's load order.

import Foundation
import TadpoleCore

extension AppModel {
    /// Test copies (TADPOLE_BG3_DOCUMENTS) keep theirs next to their folder.
    static var profilesFile: URL {
        if let override = ProcessInfo.processInfo.environment["TADPOLE_BG3_DOCUMENTS"], !override.isEmpty {
            return URL(filePath: override).deletingLastPathComponent().appending(path: "tadpole-profiles.json")
        }
        return URL.applicationSupportDirectory.appending(path: "Tadpole/profiles.json")
    }

    var activeProfileName: String? { profileStore.active }

    private func persistProfiles() {
        do {
            try profileStore.save(to: Self.profilesFile)
        } catch {
            show("Couldn't Save Profiles", error.localizedDescription)
        }
    }

    /// After loading: a profile is in use (the remembered one, else one that
    /// matches the load order, else "Default" made from it).
    func ensureActiveProfile() {
        guard let settings else { return }
        if profileStore.activeProfile != nil { return }
        if let match = ProfileRules.matching(profileStore.profiles, current: settings.modEntries) {
            profileStore.active = match
        } else {
            let name = profileStore.uniqueName(String(localized: "Default"))
            profileStore.upsert(LoadOrderProfile(name: name, mods: settings.modEntries.map(ProfileMod.init)))
            profileStore.active = name
        }
        persistProfiles()
    }

    /// Records the load order in the profile in use (after every change,
    /// and when the game rewrote it).
    func trackActiveProfile() {
        guard let settings, var profile = profileStore.activeProfile else { return }
        let installed = Set(mods.compactMap { $0.info?.uuid })
        let tracked = ProfileRules.tracked(saved: profile.mods, current: settings.modEntries, installed: installed)
        guard tracked != profile.mods else { return }
        profile.mods = tracked
        profileStore.upsert(profile)
        persistProfiles()
    }

    /// Writes another profile's load order. The current one already holds
    /// its own, so nothing is lost.
    func switchProfile(to name: String) {
        guard let profile = profileStore[name], name != profileStore.active, var settings else { return }
        guard !isGameRunning else {
            return show("Quit Baldur's Gate 3 First", String(localized: "The game rewrites its mod list when it quits, which would undo this change."))
        }
        let installed = Dictionary(mods.compactMap { mod in mod.info.map { ($0.uuid, $0) } }, uniquingKeysWith: { first, _ in first })
        let (entries, missing) = ProfileRules.loadOrder(for: profile, installed: installed)
        profileStore.active = name
        persistProfiles()
        settings.setEnabledMods(entries)
        save(settings)
        if !missing.isEmpty {
            show("Some Mods Aren't Installed",
                 String(localized: "“\(name)” lists \(missing.count) mods that aren't in the Mods folder: \(missing.map(\.name).formatted(.list(type: .and))). Install them to load them; the profile keeps them."))
        }
    }

    /// A new profile, put in use: a copy of the load order now, or an empty
    /// one (every mod turned off).
    func createProfile(named rawName: String, empty: Bool, collectionSlug: String? = nil) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, profileStore[name] == nil, var settings else { return }
        guard !empty || !isGameRunning else {
            return show("Quit Baldur's Gate 3 First", String(localized: "The game rewrites its mod list when it quits, which would undo this change."))
        }
        profileStore.upsert(LoadOrderProfile(name: name, mods: empty ? [] : settings.modEntries.map(ProfileMod.init),
                                             collectionSlug: collectionSlug))
        profileStore.active = name
        persistProfiles()
        if empty, !settings.modEntries.isEmpty {
            settings.setEnabledMods([])
            save(settings)
        }
    }

    func duplicateProfile(_ name: String) {
        guard var copy = profileStore[name] else { return }
        copy.name = profileStore.uniqueName(String(localized: "\(name) copy"))
        profileStore.upsert(copy)
        persistProfiles()
    }

    func renameProfile(_ old: String, to rawNew: String) {
        let new = rawNew.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, profileStore[new] == nil else { return }
        profileStore.rename(old, to: new)
        persistProfiles()
    }

    /// Deletes a profile that isn't in use (the mods stay installed).
    func deleteProfile(_ name: String) {
        guard name != profileStore.active else { return }
        profileStore.delete(name)
        persistProfiles()
    }

    /// Installing a collection into its own profile: a new empty one with the
    /// collection's name, then the collection's mods you already have are
    /// turned on (the downloads turn on the rest as they arrive).
    func startProfile(forCollection collection: NexusCollection, mods collectionMods: [CollectionMod]) {
        let name = profileStore.uniqueName(collection.name)
        createProfile(named: name, empty: true, collectionSlug: collection.slug)
        let wanted = Set(collectionMods.map(\.modID))
        let installed = mods.filter { mod in
            origins.byPak[mod.file.lastPathComponent].map { wanted.contains($0.modID) } ?? false
        }
        enable(installed)
    }
}
