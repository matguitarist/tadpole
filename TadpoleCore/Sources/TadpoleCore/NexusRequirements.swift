// Installing a mod's requirements with it: which of the mods its Nexus page
// requires (and the ones those require) are missing, and which file of each
// to download.

import Foundation

/// What installing a mod needs, beyond the mod itself.
public struct RequirementPlan: Sendable, Equatable {
    /// Nexus mods to install first, requirements of requirements included,
    /// deepest first.
    public var missing: [NexusRequirement] = []
    /// The mod (or one it needs) requires the Script Extender.
    public var needsScriptExtender = false
    /// Required pages that aren't Nexus mods (and aren't the Script
    /// Extender): Tadpole can only link to them.
    public var external: [NexusRequirement] = []

    public init() {}

    public var isEmpty: Bool { missing.isEmpty && !needsScriptExtender && external.isEmpty }

    /// Follows requirements up to `depth` levels: `fetch` gives a mod's
    /// requirements, `isInstalled` whether one is already there (an
    /// installed one isn't followed further).
    /// Runs on the caller's actor, so the closures can read its state.
    public static func resolve(for modID: Int, depth: Int = 3,
                               isolation: isolated (any Actor)? = #isolation,
                               fetch: (Int) async throws -> [NexusRequirement],
                               isInstalled: (NexusRequirement) -> Bool) async -> RequirementPlan {
        var plan = RequirementPlan()
        var seen: Set<Int> = [modID]
        var level = [modID]
        for _ in 0..<depth where !level.isEmpty {
            var next: [Int] = []
            for id in level {
                guard let requirements = try? await fetch(id) else { continue }
                for requirement in requirements {
                    if requirement.isScriptExtender {
                        plan.needsScriptExtender = true
                    } else if let required = requirement.nexusModID {
                        guard !seen.contains(required) else { continue }
                        seen.insert(required)
                        if !isInstalled(requirement) {
                            plan.missing.append(requirement)
                            next.append(required)
                        }
                    } else if !plan.external.contains(where: { $0.url == requirement.url }) {
                        plan.external.append(requirement)
                    }
                }
            }
            level = next
        }
        // A mod's requirements before the mod: deepest last found → first.
        plan.missing.reverse()
        return plan
    }
}

extension NexusFile {
    /// The file to install for a mod that's required by another: its newest
    /// main file, or else its newest current file.
    public static func fileToInstall(from files: [NexusFile]) -> NexusFile? {
        let current = files.filter(\.isCurrent)
        return current.filter { $0.category == "MAIN" }.max { $0.date < $1.date }
            ?? current.max { $0.date < $1.date }
    }
}
