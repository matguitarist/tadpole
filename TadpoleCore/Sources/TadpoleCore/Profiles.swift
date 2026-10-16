// Profiles: named load orders to switch between (one per playthrough, one
// per collection…). One is always in use; changes to the load order are
// recorded in it, so switching away and back returns to exactly that list.

import Foundation

/// A mod in a profile: enough to write it in the load order, or to name it
/// when it isn't installed.
public struct ProfileMod: Codable, Hashable, Sendable {
    public var uuid: String
    public var name: String
    public var folder: String

    public init(uuid: String, name: String, folder: String) {
        self.uuid = uuid.lowercased()
        self.name = name
        self.folder = folder
    }

    public init(_ entry: ModuleShortDesc) {
        self.init(uuid: entry.uuid, name: entry.name, folder: entry.folder)
    }
}

public struct LoadOrderProfile: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    /// In load order.
    public var mods: [ProfileMod]
    /// The Nexus collection it was made for (slug), if any.
    public var collectionSlug: String?

    public var id: String { name }

    public init(name: String, mods: [ProfileMod], collectionSlug: String? = nil) {
        self.name = name
        self.mods = mods
        self.collectionSlug = collectionSlug
    }
}

public struct ProfileStore: Codable, Equatable, Sendable {
    public var profiles: [LoadOrderProfile] = []
    /// The profile in use.
    public var active: String?

    public init(profiles: [LoadOrderProfile] = [], active: String? = nil) {
        self.profiles = profiles
        self.active = active
    }

    public subscript(name: String) -> LoadOrderProfile? {
        profiles.first { $0.name == name }
    }

    public var activeProfile: LoadOrderProfile? { active.flatMap { self[$0] } }

    public static func load(from url: URL) -> ProfileStore {
        guard let data = try? Data(contentsOf: url) else { return ProfileStore() }
        return (try? JSONDecoder().decode(ProfileStore.self, from: data)) ?? ProfileStore()
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// "Default", or "Default 2" when that's taken.
    public func uniqueName(_ base: String) -> String {
        guard self[base] != nil else { return base }
        var number = 2
        while self["\(base) \(number)"] != nil { number += 1 }
        return "\(base) \(number)"
    }

    public mutating func upsert(_ profile: LoadOrderProfile) {
        if let index = profiles.firstIndex(where: { $0.name == profile.name }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    public mutating func rename(_ old: String, to new: String) {
        guard let index = profiles.firstIndex(where: { $0.name == old }), self[new] == nil else { return }
        profiles[index].name = new
        if active == old { active = new }
    }

    public mutating func delete(_ name: String) {
        profiles.removeAll { $0.name == name }
        if active == name { active = nil }
    }
}

public enum ProfileRules {
    /// The profile after the load order changed to `current`: the load order,
    /// plus the profile's mods that aren't installed (they stay where they
    /// were, after the mod they followed).
    public static func tracked(saved: [ProfileMod], current: [ModuleShortDesc], installed: Set<String>) -> [ProfileMod] {
        var result = current.map(ProfileMod.init)
        var present = Set(result.map(\.uuid))
        for (index, mod) in saved.enumerated() where !installed.contains(mod.uuid) && !present.contains(mod.uuid) {
            // After the nearest earlier mod that's still there.
            let anchor = saved[..<index].last { present.contains($0.uuid) }
            let position = anchor.flatMap { anchor in result.firstIndex { $0.uuid == anchor.uuid } }.map { $0 + 1 } ?? 0
            result.insert(mod, at: position)
            present.insert(mod.uuid)
        }
        return result
    }

    /// The load order for a profile: its installed mods, in its order, as the
    /// installed versions; and the ones that aren't installed.
    public static func loadOrder(for profile: LoadOrderProfile, installed: [String: ModuleInfo]) -> (entries: [ModuleShortDesc], missing: [ProfileMod]) {
        var entries: [ModuleShortDesc] = []
        var missing: [ProfileMod] = []
        for mod in profile.mods {
            if let info = installed[mod.uuid] { entries.append(ModuleShortDesc(info)) } else { missing.append(mod) }
        }
        return (entries, missing)
    }

    /// The profile whose mods are exactly these, in this order.
    public static func matching(_ profiles: [LoadOrderProfile], current: [ModuleShortDesc]) -> String? {
        let uuids = current.map(\.uuid)
        return profiles.first { $0.mods.map(\.uuid) == uuids }?.name
    }
}
