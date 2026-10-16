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

    @Test func installsPaksFrom7z() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "tadpole-\(UUID().uuidString)")
        let source = root.appending(path: "Seven")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("pak".utf8).write(to: source.appending(path: "Seven.pak"))
        let archive = root.appending(path: "Seven-1.7z")
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["--format", "7zip", "-cf", archive.path(percentEncoded: false), "-C", root.path(percentEncoded: false), "Seven"]
        try tar.run(); tar.waitUntilExit()

        let result = try ModInstaller.install([archive], into: root.appending(path: "Mods"))
        #expect(result.installed.map(\.lastPathComponent) == ["Seven.pak"])
    }
}

@Suite struct NexusTests {
    @Test func readsModManagerLinks() throws {
        let link = try #require(NXMLink(url: URL(string: "nxm://baldursgate3/mods/141/files/9876?key=abc&expires=1700000000&user_id=42")!))
        #expect(link.isForBG3 && link.modID == 141 && link.fileID == 9876)
        #expect(link.key == "abc" && link.expires == "1700000000")
        #expect(NXMLink(url: URL(string: "nxm://stardewvalley/mods/1/files/2")!)?.isForBG3 == false)
        #expect(NXMLink(url: URL(string: "nxm://baldursgate3/collections/abc")!) == nil)
    }

    @Test func readsModNumbersFromLinks() {
        #expect(NexusClient.modID(fromLinkOrNumber: "https://www.nexusmods.com/baldursgate3/mods/141?tab=files") == 141)
        #expect(NexusClient.modID(fromLinkOrNumber: " nexusmods.com/games/baldursgate3/mods/213 ") == 213)
        #expect(NexusClient.modID(fromLinkOrNumber: "#366") == 366)
        #expect(NexusClient.modID(fromLinkOrNumber: "366") == 366)
        #expect(NexusClient.modID(fromLinkOrNumber: "https://www.nexusmods.com/stardewvalley/mods/1915") == nil)
        #expect(NexusClient.modID(fromLinkOrNumber: "hair mod") == nil)
    }
}

@Suite struct SaveTests {
    /// Trimmed from a real Patch 8 save.
    static let saveInfo = """
    {
       "Active Party" : { "Characters" : [
          { "Classes" : [ { "Main" : "Wizard", "Sub" : "" } ], "Level" : 1, "Origin" : "Generic", "Race" : "Human" },
          { "Level" : 1, "Origin" : "S_TUT_Lab_TrappedDevourer", "Race" : "Aberration" },
          { "Classes" : [ { "Main" : "Cleric", "Sub" : "TrickeryDomain" } ], "Level" : 1, "Origin" : "Shadowheart", "Race" : "HighHalfElf" }
       ] },
       "Current Level" : "TUT_Avernus_C",
       "Difficulty" : [ "DifficultyMedium", "RulesetLarian" ],
       "Game Version" : "4.1.1.4251417",
       "Platform" : "Steam",
       "Save Name" : "A Nautiloid in Hell - 1h 10m"
    }
    """

    func makeSave(in saves: URL, folder: String = "Mat-32212420020__A Nautiloid in Hell - 1h 10m") throws -> URL {
        let dir = saves.appending(path: folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lsv = try PakBuilder.make([.init(path: "meta.lsf", data: Data(count: 64)),
                                       .init(path: "SaveInfo.json", data: Data(Self.saveInfo.utf8))])
        try lsv.write(to: dir.appending(path: "A Nautiloid in Hell - 1h 10m.lsv"))
        try Data().write(to: dir.appending(path: "A Nautiloid in Hell - 1h 10m.WebP"))
        return dir
    }

    @Test func readsSaveInfoFromTheLSV() throws {
        let saves = FileManager.default.temporaryDirectory.appending(path: "tadpole-\(UUID().uuidString)/Story")
        try makeSave(in: saves)
        let save = try #require(SaveGame.scan(saves).first)
        #expect(save.name == "A Nautiloid in Hell - 1h 10m")
        #expect(save.picture != nil)
        #expect(save.info?.currentLevel == "TUT_Avernus_C")
        #expect(save.info?.difficultyName == "Medium")
        #expect(save.info?.party.map(\.displayOrigin) == ["Generic", "Shadowheart"])  // the devourer has no class
        #expect(save.info?.party.first?.isPlayerMade == true)
    }

    @Test func backsUpAndRestores() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "tadpole-\(UUID().uuidString)")
        let saves = root.appending(path: "Story"), backups = root.appending(path: "Backups")
        let dir = try makeSave(in: saves)
        let save = try #require(SaveGame.scan(saves).first)
        try SaveBackups.backUp(save, into: backups)
        let backup = try #require(SaveBackups.list(backups).first)
        #expect(backup.saveName == "A Nautiloid in Hell - 1h 10m")
        #expect(SaveBackups.wouldReplace(backup, in: saves))

        try FileManager.default.removeItem(at: dir)
        #expect(!SaveBackups.wouldReplace(backup, in: saves))
        try SaveBackups.restore(backup, into: saves)
        #expect(SaveGame.scan(saves).first?.info?.saveName == "A Nautiloid in Hell - 1h 10m")
    }

    @Test func remembersWhereModsCameFrom() throws {
        var origins = NexusOrigins()
        origins.byPak["Hair.pak"] = .init(modID: 213, fileID: 9, version: "1.2")
        origins.byPak["Gone.pak"] = .init(modID: 5, fileID: 6)
        let url = FileManager.default.temporaryDirectory.appending(path: "tadpole-\(UUID().uuidString)/nexus.json")
        try origins.save(to: url)
        let again = NexusOrigins.load(from: url)
        #expect(again == origins)
        #expect(again.installedModIDs(installedPaks: ["Hair.pak"]) == [213])
    }
}

@Suite struct DuplicateTests {
    @Test func prefersTheHighestVersionThenTheNewestFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tadpole-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func pak(_ name: String, version: String, age: TimeInterval) throws -> PakMod {
            let meta = Samples.metaLSX.replacingOccurrences(of: "36169534507319297", with: version)
            let url = folder.appending(path: name)
            try PakBuilder.make([.init(path: "Mods/TestMod/meta.lsx", data: Data(meta.utf8))]).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-age)], ofItemAtPath: url.path(percentEncoded: false))
            return PakMod.read(url)
        }
        let old = try pak("Old.pak", version: "36028797018963968", age: 0)       // 1.0, newest file
        let new = try pak("New.pak", version: "36169534507319297", age: 1000)    // 1.1
        let newer = try pak("Newer.pak", version: "36169534507319297", age: 10)  // 1.1, newer file
        #expect(PakMod.newestFirst([old, new, newer]).map(\.file.lastPathComponent) == ["Newer.pak", "New.pak", "Old.pak"])
    }
}

@Suite struct UpdateTests {
    func file(_ id: Int, _ version: String, _ category: String, date: Int, group: Int? = 1, changes: [String] = []) -> NexusFile {
        NexusFile(fileId: id, name: "Hairpack", version: version, category: category, date: date, groupId: group, changelogText: changes)
    }

    @Test func findsTheNewestVersionInTheSameGroup() throws {
        let files = [
            file(10, "1.0", "OLD_VERSION", date: 100),
            file(11, "1.1", "ARCHIVED", date: 200, changes: ["Fixed the bun"]),
            file(12, "1.2", "MAIN", date: 300, changes: ["New pigtails", "[b]Patch 8[/b] support"]),
            file(20, "2.0", "OPTIONAL", date: 400, group: 2),  // another file
        ]
        let update = try #require(NexusUpdate.find(installedFileID: 10, in: files))
        #expect(update.latest.fileId == 12)
        #expect(update.changes.map(\.version) == ["1.2", "1.1"])
        #expect(update.changes.first?.lines == ["New pigtails", "Patch 8 support"])
    }

    @Test func noUpdateWhenCurrentUnknownOrUngrouped() {
        let files = [file(10, "1.0", "OLD_VERSION", date: 100), file(12, "1.2", "MAIN", date: 300), file(30, "1", "MAIN", date: 50, group: nil)]
        #expect(NexusUpdate.find(installedFileID: 12, in: files) == nil)  // already the newest
        #expect(NexusUpdate.find(installedFileID: 99, in: files) == nil)  // deleted from Nexus
        #expect(NexusUpdate.find(installedFileID: 30, in: files) == nil)  // no group
        // A newer version that was archived again isn't offered.
        #expect(NexusUpdate.find(installedFileID: 10, in: [file(10, "1.0", "MAIN", date: 100), file(11, "1.1", "ARCHIVED", date: 200)]) == nil)
    }
}

@Suite struct ScriptExtenderTests {
    func nexus(_ id: Int, _ name: String) -> NexusRequirement {
        NexusRequirement(modId: String(id), modName: name, url: "https://www.nexusmods.com/baldursgate3/mods/\(id)", externalRequirement: false)
    }

    @Test func recognizesTheScriptExtenderHoweverItIsListed() {
        #expect(nexus(2172, "Baldur's Gate 3 Script Extender (BG3SE)").isScriptExtender)
        #expect(NexusRequirement(modId: "0", modName: "Script Extender", url: "https://github.com/Norbyte/bg3se/releases", externalRequirement: true).isScriptExtender)
        #expect(NexusRequirement(modId: nil, modName: "Norbyte's Script Extender", url: "", externalRequirement: true).isScriptExtender)
        #expect(!nexus(9162, "Mod Configuration Menu").isScriptExtender)
        #expect(!NexusRequirement(modId: "2172", modName: "Some page", url: "https://example.com", externalRequirement: true).isScriptExtender)
    }

    @Test func followsRequirementsThroughOtherMods() {
        let needs = ScriptExtender.needs(requirements: [
            1: [nexus(2172, "BG3SE")],              // needs it
            2: [nexus(1, "Framework")],              // through 1
            3: [nexus(2, "Subclass")],               // through 2, then 1
            4: [nexus(50, "Not in the collection")], // unknown: not flagged
            5: [],
        ])
        #expect(needs[1] == .direct)
        #expect(needs[2] == .through("Framework"))
        #expect(needs[3] == .through("Subclass"))
        #expect(needs[4] == nil)
        #expect(needs[5] == nil)
    }
}

@Suite struct MachOPatcherTests {
    /// Builds a universal program and a library with clang, adds the library
    /// to the program, re-signs it and runs it: the library's constructor
    /// must run. Then removes it again.
    @Test func addsAndRemovesALibraryTheProgramLoads() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "machopatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "int main(void) { return 0; }".write(to: folder.appending(path: "main.c"), atomically: true, encoding: .utf8)
        try #"#include <stdio.h>\n__attribute__((constructor)) static void hello(void) { puts("loaded"); }"#
            .replacingOccurrences(of: "\\n", with: "\n")
            .write(to: folder.appending(path: "lib.c"), atomically: true, encoding: .utf8)
        let program = folder.appending(path: "program")
        try run("/usr/bin/clang", ["-arch", "arm64", "-arch", "x86_64", "-Wl,-headerpad,0x400", "-o", program.path, folder.appending(path: "main.c").path])
        try run("/usr/bin/clang", ["-arch", "arm64", "-arch", "x86_64", "-dynamiclib", "-o", folder.appending(path: "libbg3se.dylib").path,
                                   folder.appending(path: "lib.c").path])

        #expect(try !MachOPatcher.links(program, libraryNamed: "libbg3se"))
        #expect(try run(program.path, []) == "")

        try MachOPatcher.addWeakLibrary("@loader_path/libbg3se.dylib", to: program)
        try MachOPatcher.addWeakLibrary("@loader_path/libbg3se.dylib", to: program)  // twice: added once
        #expect(try MachOPatcher.links(program, libraryNamed: "libbg3se"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", program.path])
        #expect(try run(program.path, []) == "loaded\n")
        // Weak: still runs without the library.
        try FileManager.default.removeItem(at: folder.appending(path: "libbg3se.dylib"))
        #expect(try run(program.path, []) == "")

        try MachOPatcher.removeLibrary(named: "libbg3se", from: program)
        #expect(try !MachOPatcher.links(program, libraryNamed: "libbg3se"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", program.path])
        #expect(try run(program.path, []) == "")
    }

    /// Installs into a fake game app the way Tadpole does: the program is
    /// patched and signed outside the app, then runs and loads the library.
    @Test func installsIntoAGameAppAndRemovesItAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "segame-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appending(path: "Baldur's Gate 3.app")
        let macOS = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try "int main(void) { return 0; }".write(to: folder.appending(path: "main.c"), atomically: true, encoding: .utf8)
        try "#include <stdio.h>\n__attribute__((constructor)) static void hello(void) { puts(\"loaded\"); }"
            .write(to: folder.appending(path: "lib.c"), atomically: true, encoding: .utf8)
        let game = ScriptExtenderMac.Game(app: app)
        try run("/usr/bin/clang", ["-arch", "arm64", "-arch", "x86_64", "-Wl,-headerpad,0x400", "-o", game.executable.path, folder.appending(path: "main.c").path])
        let library = folder.appending(path: "libbg3se.dylib")
        try run("/usr/bin/clang", ["-arch", "arm64", "-dynamiclib", "-o", library.path, folder.appending(path: "lib.c").path])
        let original = try Data(contentsOf: game.executable)

        try game.install(library: library)
        #expect(game.isPatched && game.hasLibrary)
        #expect(try run(game.executable.path, []) == "loaded\n")
        try game.install(library: library)  // again (an update of the library): still patched once
        #expect(try run(game.executable.path, []) == "loaded\n")

        try game.uninstall()
        #expect(!game.isPatched && !game.hasLibrary)
        #expect(try Data(contentsOf: game.executable) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: macOS.path) == ["Baldur's Gate 3"])
    }

    @Test func rejectsFilesThatArentPrograms() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "notmacho-\(UUID().uuidString)")
        try Data("hello world, not a program".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(throws: MachOPatcher.PatchError.notMachO) { try MachOPatcher.addWeakLibrary("x", to: file) }
    }

    @discardableResult
    func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(tool) failed")
        return String(decoding: data, as: UTF8.self)
    }
}

@Suite struct ScriptExtenderMacTests {
    func release(_ notes: String) -> ScriptExtenderRelease {
        ScriptExtenderRelease(version: "0.44.0", publishedAt: .now, pageURL: ScriptExtenderMac.releasesURL, notes: notes,
                              zipURL: ScriptExtenderMac.releasesURL, checksumURL: nil)
    }

    @Test func readsTheGameBuildsFromTheNotes() {
        let notes = "## First release on Baldur's Gate 3 4.1.1.7398727\nVerified live on the current Steam build (4.1.1.7398727, arm64)."
        #expect(release(notes).gameBuilds == ["4.1.1.7398727"])
        #expect(release(notes).supports(gameBuild: "4.1.1.7398727") == true)
        #expect(release(notes).supports(gameBuild: "4.1.1.7631656") == false)
        #expect(release("Bug fixes. Version 0.44.1").supports(gameBuild: "4.1.1.7631656") == nil)
    }

    @Test func comparesVersions() {
        #expect(ScriptExtenderMac.isNewer("0.45.0", than: "0.44.0"))
        #expect(ScriptExtenderMac.isNewer("0.44.10", than: "0.44.9"))
        #expect(!ScriptExtenderMac.isNewer("0.44.0", than: "0.44.0"))
        #expect(ScriptExtenderMac.version(fromTag: "v0.44.0") == "0.44.0")
    }
}

@Suite struct ScriptExtenderLogTests {
    static let sample = """
        ========================================
        === BG3SE-macOS v0.44.0 ===
        Session: 2026-10-16 08:00:00
        Log file: /Users/me/Library/Application Support/BG3SE/logs/bg3se_2026-10-16_08-00-00.log
        Log level: DEBUG
        ========================================
        [2026-10-16 08:00:01.000] [INFO ] [Mod    ] === Enabled Mods ===
        [2026-10-16 08:00:01.001] [INFO ] [Mod    ]   [1] GustavX (base game)
        [2026-10-16 08:00:01.002] [INFO ] [Mod    ]   [2] Mod Configuration Menu
        [2026-10-16 08:00:01.003] [INFO ] [Mod    ]   [3] Tav's Hairpack
        [2026-10-16 08:00:01.004] [INFO ] [Mod    ] Total mods: 3 (2 user mods)
        [2026-10-16 08:00:01.005] [INFO ] [Mod    ] ====================
        [2026-10-16 08:00:01.006] [INFO ] [Mod    ] === Scanning for SE Mods ===
        [2026-10-16 08:00:01.007] [INFO ] [Mod    ]   [SE] MCM
        [2026-10-16 08:00:01.008] [INFO ] [Mod    ] ============================
        [2026-10-16 08:00:02.000] [DEBUG] [Console] ! identity
        [2026-10-16 08:00:03.000] [ERROR] [Lua    ] PAK compile error (Mods/MCM/ScriptExtender/Lua/BootstrapServer.lua): attempt to index nil
        stack traceback:
        \t[C]: in ?
        [2026-10-16 08:00:04.000] [WARN ] [Stats  ] Stats not available on this build
        [2026-10-16 08:00:05.000] [ERROR] [Lua    ] PAK load error (Mods/MCM/ScriptExtender/Lua/Shared.lua): oops
        """

    @Test func readsTheHeaderEntriesAndModLists() {
        let log = ScriptExtenderLog(Self.sample)
        #expect(log.version == "0.44.0")
        #expect(log.session == "2026-10-16 08:00:00")
        #expect(log.entries.count == 13)
        #expect(log.enabledMods == ["Mod Configuration Menu", "Tav's Hairpack"])
        #expect(log.scriptExtenderMods == ["MCM"])
        let error = log.entries.first { $0.level == .error }
        #expect(error?.module == "Lua")
        #expect(error?.time == "08:00:03.000")
        #expect(error?.message.hasSuffix("\tin ?") == false)
        #expect(error?.message.contains("stack traceback:") == true)  // continuation lines kept
        #expect(error?.modFolder == "MCM")
    }

    @Test func groupsProblemsByMod() {
        let groups = ScriptExtenderLog(Self.sample).problemGroups
        #expect(groups.map(\.source) == ["MCM", "Stats"])
        #expect(groups.first?.isMod == true)
        #expect(groups.first?.errors == 2)
        #expect(groups.last?.warnings == 1)
    }
}

@Suite struct ScriptExtenderLogCompatibilityTests {
    /// Lines from a real session on a game build v0.44.0 doesn't support.
    static let sample = """
        === BG3SE-macOS v0.44.0 ===
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ] === Enabled Mods ===
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ]   [1] GustavX (base game)
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ]   [2] DFHairPack
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ]   [3] AutoSnapPack
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ]   [4] 5eSpells
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ]   [5] Mod Configuration Menu
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ] === Scanning for SE Mods ===
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ] SE dir for 'DFHairPack' resolved via PAK filename: 5eSpells
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ] Found SE mod DFHairPack in PAK: /Users/me/Mods/5eSpells.pak (dir: 5eSpells)
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ]   [SE] DFHairPack
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ] SE dir for 'AutoSnapPack' resolved via PAK filename: 5eSpells
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ]   [SE] AutoSnapPack
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ]   [SE] 5eSpells
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ] SE dir for 'Mod Configuration Menu' resolved via PAK filename: MCM
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ]   [SE] Mod Configuration Menu
        [2026-10-16 11:29:48.310] [INFO ] [Mod    ] ============================
        [2026-10-16 11:29:48.323] [INFO ] [Core   ] [WARN] ============================================
        [2026-10-16 11:29:48.323] [INFO ] [Core   ] [WARN] GAME VERSION MISMATCH DETECTED
        [2026-10-16 11:29:48.323] [INFO ] [Core   ] [WARN] Detected: 4.1.1.7631656 | Expected: 4.1.1.7398727
        [2026-10-16 11:29:48.323] [INFO ] [Core   ] [WARN] ============================================
        [2026-10-16 11:29:48.327] [INFO ] [Stats  ] No verified RPGStats slot for this game version — stats system disabled (fail closed)
        [2026-10-16 11:29:48.327] [INFO ] [Core   ] [Level] WARN: level_mgr_ptr not available for this BG3 version — Level API disabled
        [2026-10-16 11:29:48.327] [INFO ] [Core   ] LOCA: No offset-table row for this game version — localization disabled
        """

    @Test func spotsModsGivenAnotherModsScripts() {
        let log = ScriptExtenderLog(Self.sample)
        #expect(log.misattributed == ["DFHairPack": "5eSpells", "AutoSnapPack": "5eSpells"])
        #expect(log.scriptExtenderMods == ["5eSpells", "Mod Configuration Menu"])  // MCM's own folder is fine
    }

    @Test func readsTheUnsupportedBuildAndWhatsOff() {
        let log = ScriptExtenderLog(Self.sample)
        #expect(log.unsupportedBuild?.detected == "4.1.1.7631656")
        #expect(log.unsupportedBuild?.expected == "4.1.1.7398727")
        #expect(log.disabledFeatures == ["Stats (Ext.Stats)", "Level API (Ext.Level)", "Localization (Ext.Loca)"])
        // Warnings written at INFO level count, the ==== frames don't.
        #expect(log.warningCount == 3)
    }
}

@Suite struct RequirementPlanTests {
    func nexus(_ id: Int, _ name: String) -> NexusRequirement {
        NexusRequirement(modId: String(id), modName: name, url: "https://www.nexusmods.com/baldursgate3/mods/\(id)", externalRequirement: false)
    }

    @Test func findsMissingRequirementsThroughOtherMods() async {
        let graph: [Int: [NexusRequirement]] = [
            1: [nexus(2, "Subclass Framework"), nexus(3, "Installed Lib"), nexus(ScriptExtender.nexusModID, "BG3SE")],
            2: [nexus(4, "Compatibility Framework"), nexus(1, "Back to the mod")],  // a loop
            3: [nexus(5, "Not followed: 3 is installed")],
            4: [NexusRequirement(modId: nil, modName: "A tool", url: "https://example.com/tool", externalRequirement: true)],
        ]
        let plan = await RequirementPlan.resolve(for: 1, fetch: { graph[$0] ?? [] }, isInstalled: { $0.modId == "3" })
        #expect(plan.missing.map(\.modName) == ["Compatibility Framework", "Subclass Framework"])
        #expect(plan.needsScriptExtender)
        #expect(plan.external.map(\.url) == ["https://example.com/tool"])
    }

    @Test func nothingMissing() async {
        let plan = await RequirementPlan.resolve(for: 1, fetch: { _ in [] }, isInstalled: { _ in true })
        #expect(plan.isEmpty)
    }

    @Test func picksTheNewestMainFile() {
        let files = [
            NexusFile(fileId: 1, name: "Old main", version: "1", category: "MAIN", date: 100, groupId: 1),
            NexusFile(fileId: 2, name: "Main", version: "2", category: "MAIN", date: 300, groupId: 1),
            NexusFile(fileId: 3, name: "Optional", version: "3", category: "OPTIONAL", date: 400, groupId: 2),
            NexusFile(fileId: 4, name: "Archived", version: "4", category: "ARCHIVED", date: 500, groupId: 1),
        ]
        #expect(NexusFile.fileToInstall(from: files)?.fileId == 2)
        #expect(NexusFile.fileToInstall(from: [files[2]])?.fileId == 3)
        #expect(NexusFile.fileToInstall(from: [files[3]]) == nil)
    }
}

@Suite struct ScriptStatusTests {
    @Test func findsAModsScriptFolders() {
        let paths = ["Mods/5eSpells/meta.lsx", "Mods/5eSpells/ScriptExtender/Config.json", "Mods/5eSpells/ScriptExtender/Lua/BootstrapServer.lua",
                     "Public/5eSpells/Stats/Spells.txt", "Mods/Other/scriptextender/Lua/x.lua"]
        #expect(PakMod.scriptFolders(in: paths) == ["5eSpells", "Other"])
    }

    @Test func readsEachModsScriptsFromTheLog() {
        let log = ScriptExtenderLog("""
            [2026-10-16 08:00:00.592] [INFO ] [Lua    ] Loaded from PAK: Mods/MCM/ScriptExtender/Lua/BootstrapServer.lua
            [2026-10-16 08:00:00.629] [INFO ] [Lua    ] Loaded from PAK: Mods/5eSpells/ScriptExtender/Lua/BootstrapServer.lua
            [2026-10-16 08:01:52.036] [ERROR] [Lua    ] PAK compile error (Mods/MCM/ScriptExtender/Lua/Shared/Settings.lua): oops
            """)
        #expect(log.scriptStatus(forFolders: ["5eSpells"]) == .loaded)
        #expect(log.scriptStatus(forFolders: ["mcm"]) == .errors(1))
        #expect(log.scriptStatus(forFolders: ["CommunityLibrary"]) == .notLoaded)
    }
}

@Suite struct ProfileTests {
    func entry(_ id: String) -> ModuleShortDesc { ModuleShortDesc(folder: id, name: id, uuid: id, version64: 1) }
    func mod(_ id: String) -> ProfileMod { ProfileMod(uuid: id, name: id, folder: id) }

    @Test func keepsModsThatArentInstalledWhereTheyWere() {
        // The profile had a, b, x (not installed), c; the user moved c first.
        let saved = [mod("a"), mod("b"), mod("x"), mod("c")]
        let tracked = ProfileRules.tracked(saved: saved, current: [entry("c"), entry("a"), entry("b")], installed: ["a", "b", "c"])
        #expect(tracked.map(\.uuid) == ["c", "a", "b", "x"])
        // Turning b off drops it: it's installed, so the load order decides.
        let without = ProfileRules.tracked(saved: saved, current: [entry("a"), entry("c")], installed: ["a", "b", "c"])
        #expect(without.map(\.uuid) == ["a", "x", "c"])
        // A missing mod listed first stays first.
        #expect(ProfileRules.tracked(saved: [mod("x"), mod("a")], current: [entry("a")], installed: ["a"]).map(\.uuid) == ["x", "a"])
    }

    @Test func buildsTheLoadOrderFromInstalledMods() {
        let profile = LoadOrderProfile(name: "Run 2", mods: [mod("a"), mod("x"), mod("b")])
        let installed = ["a": ModuleInfo(uuid: "a", name: "A", folder: "A"), "b": ModuleInfo(uuid: "b", name: "B", folder: "B")]
        let (entries, missing) = ProfileRules.loadOrder(for: profile, installed: installed)
        #expect(entries.map(\.uuid) == ["a", "b"])
        #expect(missing.map(\.uuid) == ["x"])
    }

    @Test func namesRenamesAndRoundTrips() throws {
        var store = ProfileStore(profiles: [LoadOrderProfile(name: "Default", mods: [mod("a")])], active: "Default")
        #expect(store.uniqueName("Default") == "Default 2")
        #expect(store.uniqueName("Honour run") == "Honour run")
        store.rename("Default", to: "Main")
        #expect(store.active == "Main")
        #expect(ProfileRules.matching(store.profiles, current: [entry("a")]) == "Main")
        let file = FileManager.default.temporaryDirectory.appending(path: "profiles-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try store.save(to: file)
        #expect(ProfileStore.load(from: file) == store)
        store.delete("Main")
        #expect(store.active == nil && store.profiles.isEmpty)
    }
}
