// Installs mods: .pak files as they are, and the .pak files inside .zip
// archives (Nexus downloads), into the Mods folder. An existing file with
// the same name is replaced (moved to the Trash).

import Foundation

public enum ModInstaller {
    public struct Result: Sendable {
        public var installed: [URL] = []
        /// Archives with no .pak inside (loose files, Script Extender…).
        public var skipped: [String] = []
    }

    public static func install(_ sources: [URL], into modsFolder: URL) throws -> Result {
        let fm = FileManager.default
        try fm.createDirectory(at: modsFolder, withIntermediateDirectories: true)
        var result = Result()
        for source in sources {
            let paks: [URL]
            var work: URL?
            switch source.pathExtension.lowercased() {
            case "pak":
                paks = [source]
            case "zip":
                let folder = fm.temporaryDirectory.appending(path: "tadpole-install-\(UUID().uuidString)", directoryHint: .isDirectory)
                work = folder
                try unzip(source, to: folder)
                paks = findPaks(in: folder)
            default:
                result.skipped.append(source.lastPathComponent)
                continue
            }
            defer { if let work { try? fm.removeItem(at: work) } }
            if paks.isEmpty { result.skipped.append(source.lastPathComponent) }
            for pak in paks {
                let destination = modsFolder.appending(path: pak.lastPathComponent)
                if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                    try fm.trashItem(at: destination, resultingItemURL: nil)
                }
                try fm.copyItem(at: pak, to: destination)
                result.installed.append(destination)
            }
        }
        return result
    }

    static func findPaks(in folder: URL) -> [URL] {
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        var paks: [URL] = []
        while let url = walker?.nextObject() as? URL {
            if url.pathComponents.contains("__MACOSX") { continue }
            if url.pathExtension.lowercased() == "pak" { paks.append(url) }
        }
        return paks.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// macOS's ditto unpacks zip archives.
    static func unzip(_ archive: URL, to folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path(percentEncoded: false), folder.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: archive.path(percentEncoded: false)])
        }
    }
}
