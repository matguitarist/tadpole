// The .pak files in the Mods folder, read into mods: their meta.lsx, and
// whether they need Norbyte's Script Extender (not available on macOS).

import Foundation

public struct PakMod: Sendable, Identifiable, Hashable {
    public let file: URL
    public let info: ModuleInfo?
    /// Ships ScriptExtender files: its scripts need the Windows-only Script Extender.
    public let usesScriptExtender: Bool
    public let error: String?

    public var id: String { info?.uuid ?? file.lastPathComponent }
    public var name: String { info?.name ?? file.deletingPathExtension().lastPathComponent }

    public static func read(_ file: URL) -> PakMod {
        do {
            let pak = try PakArchive(url: file)
            let usesSE = pak.entries.contains { $0.path.localizedCaseInsensitiveContains("/ScriptExtender/") }
            // Mods/<Folder>/meta.lsx; some paks hold several, the first is the mod.
            guard let meta = pak.entry(matching: { path in
                let parts = path.split(separator: "/")
                return parts.count == 3 && parts[0] == "Mods" && parts[2].caseInsensitiveCompare("meta.lsx") == .orderedSame
            }) else {
                // Overrides without meta.lsx load without being listed.
                return PakMod(file: file, info: nil, usesScriptExtender: usesSE, error: nil)
            }
            let info = try ModuleInfo(meta: LSXDocument.parse(pak.data(for: meta)))
            return PakMod(file: file, info: info, usesScriptExtender: usesSE, error: nil)
        } catch {
            return PakMod(file: file, info: nil, usesScriptExtender: false, error: error.localizedDescription)
        }
    }

    /// Every .pak in the folder, by name.
    public static func scan(_ folder: URL) -> [PakMod] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "pak" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(read)
    }
}

extension PakMod {
    /// Copies of the same mod, best first: the highest version, then the
    /// newest file.
    public static func newestFirst(_ copies: [PakMod]) -> [PakMod] {
        func date(_ mod: PakMod) -> Date {
            (try? mod.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        return copies.sorted { ($0.info?.version64 ?? 0, date($0)) > ($1.info?.version64 ?? 0, date($1)) }
    }
}
