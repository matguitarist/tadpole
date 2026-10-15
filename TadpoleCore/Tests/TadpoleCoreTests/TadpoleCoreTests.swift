import Foundation
import Testing
@testable import TadpoleCore

@Suite struct PakTests {
    private func write(_ data: Data, name: String = "Mod.pak") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tadpole-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    @Test func listsAndReadsFiles() throws {
        let text = Data(String(repeating: "Larian ", count: 200).utf8)
        let url = try write(PakBuilder.make([
            .init(path: "Mods/Test/meta.lsx", data: text),
            .init(path: "Public/Test/readme.txt", data: Data("plain".utf8), lz4: false),
        ]))
        let pak = try PakArchive(url: url)
        #expect(pak.version == 18)
        #expect(pak.entries.map(\.path) == ["Mods/Test/meta.lsx", "Public/Test/readme.txt"])
        #expect(try pak.data(for: pak.entries[0]) == text)
        #expect(try pak.data(for: pak.entries[1]) == Data("plain".utf8))
    }

    @Test func rejectsOtherFiles() throws {
        let url = try write(Data("PK\u{3}\u{4} not a pak at all, a zip".utf8))
        #expect(throws: PakError.notAPak) { try PakArchive(url: url) }
    }

    @Test func readsAModFromItsPak() throws {
        let url = try write(PakBuilder.make([
            .init(path: "Mods/MoreSpellSlots/meta.lsx", data: Data(Samples.metaLSX.utf8)),
            .init(path: "Mods/MoreSpellSlots/ScriptExtender/Config.json", data: Data("{}".utf8)),
        ]), name: "MoreSpellSlots.pak")
        let mod = PakMod.read(url)
        #expect(mod.error == nil)
        #expect(mod.info?.uuid == "1a2b3c4d-0000-4000-8000-00000000aaaa")
        #expect(mod.name == "More Spell Slots")
        #expect(mod.usesScriptExtender)
    }

    @Test func pakWithoutMetaIsAnOverride() throws {
        let url = try write(PakBuilder.make([.init(path: "Public/Shared/Assets/x.dds", data: Data(count: 64))]), name: "Retexture.pak")
        let mod = PakMod.read(url)
        #expect(mod.info == nil && mod.error == nil)
        #expect(mod.name == "Retexture")
    }
}

@Suite struct MetaTests {
    @Test func readsModuleInfoAndDependencies() throws {
        let info = try ModuleInfo(meta: LSXDocument.parse(Data(Samples.metaLSX.utf8)))
        #expect(info.name == "More Spell Slots")
        #expect(info.folder == "MoreSpellSlots")
        #expect(info.author == "Someone & Co")
        #expect(info.version64 == 36169534507319297)  // ModuleInfo's own, not PublishVersion's
        #expect(info.dependencies == [ModuleReference(uuid: "e0e2a9c8-1234-4b2a-9f00-0123456789ab", name: "ImprovedUI")])
    }

    @Test func unpacksVersions() {
        let version = ModVersion(36169534507319297)
        #expect(version.description == "1.1.0.1")
        #expect(ModVersion(major: 1, minor: 1, revision: 0, build: 1).packed == 36169534507319297)
        #expect(ModVersion(36028797018963968).description == "1.0.0.0")
    }
}

@Suite struct ModSettingsTests {
    @Test func keepsBaseModulesFirstAndSetsTheOrder() throws {
        var settings = try ModSettings.parse(Data(Samples.modSettingsPatch7.utf8))
        #expect(settings.baseEntries.map(\.folder) == ["GustavX"])
        #expect(settings.modEntries.map(\.folder) == ["OldMod"])
        #expect(!settings.hasModOrder)

        let a = ModuleShortDesc(folder: "A", name: "Mod A", uuid: "AAAAAAAA-0000-4000-8000-000000000001", version64: 1)
        let b = ModuleShortDesc(folder: "B", name: "Mod B & more", uuid: "bbbbbbbb-0000-4000-8000-000000000002", version64: 2)
        settings.setEnabledMods([b, a, b])
        #expect(settings.entries.map(\.folder) == ["GustavX", "B", "A"])

        // What's written reads back the same.
        let again = try ModSettings.parse(Data(settings.lsx().utf8))
        #expect(again == settings)
        #expect(again.version["major"] == "4")
    }

    @Test func rewritesTheGamesOwnFileUnchanged() throws {
        let settings = try ModSettings.parse(Data(Samples.modSettingsPatch8.utf8))
        #expect(settings.modEntries.isEmpty)
        #expect(settings.baseEntries.map(\.name) == ["GustavX"])
        #expect(settings.lsx() == Samples.modSettingsPatch8 + "\n")
    }

    @Test func keepsTheOldModOrderListInStep() throws {
        var settings = try ModSettings.parse(Data(Samples.modSettingsPatch7.utf8))
        settings.hasModOrder = true
        let text = settings.lsx()
        #expect(text.contains(#"<node id="ModOrder">"#))
        #expect(try ModSettings.parse(Data(text.utf8)).hasModOrder)
    }

    @Test func backsUpBeforeWriting() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tadpole-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "modsettings.lsx")
        try Data(Samples.modSettingsPatch7.utf8).write(to: url)
        var settings = try ModSettings.read(from: url)
        settings.setEnabledMods([])
        try settings.write(to: url)
        #expect(try ModSettings.read(from: url).modEntries.isEmpty)
        #expect(try ModSettings.read(from: url.appendingPathExtension("bak")).modEntries.count == 1)
    }
}

@Suite struct RulesTests {
    private func mod(_ name: String, needs: [String] = []) -> ModuleInfo {
        ModuleInfo(uuid: "\(name)-uuid", name: name, folder: name,
                   dependencies: needs.map { ModuleReference(uuid: "\($0)-uuid", name: $0) })
    }

    @Test func findsMissingOffAndLateRequirements() {
        let lib = mod("Lib")
        let off = mod("Off")
        let user = mod("User", needs: ["Lib", "Off", "Gone", "GustavDev"])
        let problems = ModRules.problems(enabled: [user, lib], installed: [user, lib, off])
        #expect(Set(problems[user.uuid] ?? []) == [
            .loadsAfter(ModuleReference(uuid: "Lib-uuid", name: "Lib")),
            .turnedOff(ModuleReference(uuid: "Off-uuid", name: "Off")),
            .notInstalled(ModuleReference(uuid: "Gone-uuid", name: "Gone")),
        ])
        #expect(problems[lib.uuid] == nil)
    }

    @Test func movesRequirementsFirstAndKeepsTheRest() {
        let a = mod("A"), lib = mod("Lib"), b = mod("B", needs: ["Lib"]), c = mod("C")
        #expect(ModRules.dependencyOrder([a, b, c, lib]).map(\.name) == ["A", "Lib", "B", "C"])
        let x = mod("X", needs: ["Y"]), y = mod("Y", needs: ["X"])
        #expect(ModRules.dependencyOrder([x, y]).count == 2)  // a cycle doesn't lose mods
    }
}

@Suite struct InstallerTests {
    @Test func installsPaksFromZipsAndFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "tadpole-\(UUID().uuidString)")
        let source = root.appending(path: "download/Some Mod")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("pak".utf8).write(to: source.appending(path: "SomeMod.pak"))
        try Data("{}".utf8).write(to: source.appending(path: "info.json"))
        let zip = root.appending(path: "SomeMod-123.zip")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", source.path(percentEncoded: false), zip.path(percentEncoded: false)]
        try ditto.run(); ditto.waitUntilExit()
        let loose = root.appending(path: "Other.pak")
        try Data("other".utf8).write(to: loose)
        let readme = root.appending(path: "readme.txt")
        try Data().write(to: readme)

        let mods = root.appending(path: "Mods")
        let result = try ModInstaller.install([zip, loose, readme], into: mods)
        #expect(result.installed.map(\.lastPathComponent) == ["SomeMod.pak", "Other.pak"])
        #expect(result.skipped == ["readme.txt"])
        #expect(fm.fileExists(atPath: mods.appending(path: "SomeMod.pak").path(percentEncoded: false)))
    }
}
