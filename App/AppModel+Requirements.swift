// Requirements from Nexus: what a mod's page says it needs, which of those
// are missing, and installing them along with the mod.

import Foundation
import TadpoleCore

/// Installing files of a mod that needs mods you don't have: asks which
/// requirements to install along.
struct RequirementsPrompt: Identifiable {
    let id = UUID()
    let modID: Int
    let modName: String
    let files: [BrowserQueueItem]
    let plan: RequirementPlan
}

extension AppModel {
    /// A mod's requirements, fetched once per session.
    func requirements(ofNexusMod modID: Int) async throws -> [NexusRequirement] {
        if let known = nexusRequirements[modID] { return known }
        let fetched = try await nexusClient.requirements(forMod: modID)
        nexusRequirements[modID] = fetched
        return fetched
    }

    /// Installed: downloaded or linked through Tadpole, or a mod with the
    /// same name in the Mods folder (installed from a file).
    func isInstalled(_ requirement: NexusRequirement) -> Bool {
        if let id = requirement.nexusModID, installedNexusModIDs.contains(id) { return true }
        guard let name = requirement.modName?.lowercased(), !name.isEmpty else { return false }
        return mods.contains { mod in
            let installed = mod.name.lowercased()
            return installed == name || (installed.count > 3 && name.contains(installed)) || (name.count > 3 && installed.contains(name))
        }
    }

    func requirementPlan(forNexusMod modID: Int) async -> RequirementPlan {
        await RequirementPlan.resolve(for: modID, fetch: { try await self.requirements(ofNexusMod: $0) },
                                      isInstalled: { self.isInstalled($0) })
    }

    /// Installs Nexus files, unless the mod needs mods you don't have: then
    /// returns what to ask (RequirementsSheet).
    func installCheckingRequirements(modID: Int, modName: String, files: [BrowserQueueItem]) async -> RequirementsPrompt? {
        let plan = await requirementPlan(forNexusMod: modID)
        if plan.missing.isEmpty && plan.external.isEmpty && (!plan.needsScriptExtender || scriptExtenderIsActive) {
            installFromNexus(files)
            return nil
        }
        return RequirementsPrompt(modID: modID, modName: modName, files: files, plan: plan)
    }

    /// The chosen requirements (their newest main file each), then the mod.
    func install(_ prompt: RequirementsPrompt, with chosen: [NexusRequirement]) async {
        var queue: [BrowserQueueItem] = []
        for requirement in chosen {
            guard let id = requirement.nexusModID else { continue }
            if nexusFiles[id] == nil { nexusFiles[id] = try? await nexusClient.files(forMod: id) }
            guard let file = nexusFiles[id].flatMap(NexusFile.fileToInstall) else { continue }
            queue.append(BrowserQueueItem(modID: id, fileID: file.fileId, title: requirement.modName ?? file.name))
        }
        installFromNexus(queue + prompt.files)
    }
}
