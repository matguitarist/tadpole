// Pure rules about mods that are on: what their requirements need, and a
// load order where every requirement loads before the mods that need it.

import Foundation

public enum ModRules {
    /// Larian's own modules: mods may list them as dependencies; they're
    /// always there.
    public static let gameModuleNames: Set<String> = [
        "Gustav", "GustavDev", "GustavX", "Shared", "SharedDev", "Engine", "MainUI", "ModBrowser", "Honour", "HonourX",
    ]

    public enum Problem: Sendable, Hashable {
        case notInstalled(ModuleReference)
        case turnedOff(ModuleReference)
        case loadsAfter(ModuleReference)
    }

    /// Problems with each enabled mod's dependencies, by mod UUID.
    /// `enabled` is in load order.
    public static func problems(enabled: [ModuleInfo], installed: [ModuleInfo]) -> [String: [Problem]] {
        let position = Dictionary(enabled.enumerated().map { ($1.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let installedIDs = Set(installed.map(\.uuid))
        var result: [String: [Problem]] = [:]
        for (index, mod) in enabled.enumerated() {
            for dependency in mod.dependencies where !isGameModule(dependency) {
                if let at = position[dependency.uuid] {
                    if at > index { result[mod.uuid, default: []].append(.loadsAfter(dependency)) }
                } else if installedIDs.contains(dependency.uuid) {
                    result[mod.uuid, default: []].append(.turnedOff(dependency))
                } else {
                    result[mod.uuid, default: []].append(.notInstalled(dependency))
                }
            }
        }
        return result
    }

    static func isGameModule(_ reference: ModuleReference) -> Bool {
        ModSettings.baseModuleUUIDs.contains(reference.uuid) || gameModuleNames.contains(reference.name)
    }

    /// The same mods with each requirement moved before the mods that need
    /// it; otherwise the order is kept. Cycles keep their current order.
    public static func dependencyOrder(_ mods: [ModuleInfo]) -> [ModuleInfo] {
        let byID = Dictionary(mods.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        var placed = Set<String>()
        var visiting = Set<String>()
        var result: [ModuleInfo] = []
        func place(_ mod: ModuleInfo) {
            guard !placed.contains(mod.uuid), visiting.insert(mod.uuid).inserted else { return }
            for dependency in mod.dependencies {
                if let required = byID[dependency.uuid] { place(required) }
            }
            visiting.remove(mod.uuid)
            if placed.insert(mod.uuid).inserted { result.append(mod) }
        }
        mods.forEach(place)
        return result
    }
}
