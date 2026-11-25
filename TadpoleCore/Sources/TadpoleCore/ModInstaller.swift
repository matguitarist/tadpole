// Installs mods: .pak files as they are, and the .pak files inside
// archives (Nexus downloads: .zip, .7z, .rar), into the Mods folder. An existing file with
// the same name is replaced (moved to the Trash).

import ArchiveKit
import Foundation

public enum ModInstaller {
    /// Archive formats that can be unpacked (ArchiveKit): zip, and 7z and RAR
    /// through macOS's tar.
    public static let archiveExtensions: Set<String> = ["zip", "7z", "rar"]

    public struct Result: Sendable {
        public var installed: [URL] = []
        /// Archives with no .pak inside (loose files, Script Extender…).
        public var skipped: [String] = []
    }

    public static func install(_ sources: [URL], into modsFolder: URL) async throws -> Result {
        let fm = FileManager.default
        try fm.createDirectory(at: modsFolder, withIntermediateDirectories: true)
        var result = Result()
        for source in sources {
            let paks: [URL]
            var work: URL?
            let ext = source.pathExtension.lowercased()
            switch ext {
            case "pak":
                paks = [source]
            case _ where archiveExtensions.contains(ext):
                let folder = fm.temporaryDirectory.appending(path: "tadpole-install-\(UUID().uuidString)", directoryHint: .isDirectory)
                work = folder
                try await unpack(source, to: folder)
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

    /// Unpacks into `folder` (which must not exist yet). Every name is checked
    /// first, and nothing is left half-written when it fails.
    static func unpack(_ archive: URL, to folder: URL) async throws {
        do {
            if archive.pathExtension.lowercased() == "zip" {
                try await Zip.unpack(archive, into: folder)
            } else {
                try await AnyArchive.unpack(archive, into: folder)
            }
        } catch let error as ArchiveError {
            if case .unsafeEntry(let name) = error { throw ArchiveProblem.unsafeEntry(name) }
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: archive.path(percentEncoded: false)])
        }
    }
}

/// ArchiveKit's refusals, in Tadpole's own words (its other failures keep the
/// system's "couldn't be opened because it isn't in the correct format").
public enum ArchiveProblem: LocalizedError, Equatable {
    /// A name that would land outside the folder (Zip Slip): nothing was unpacked.
    case unsafeEntry(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeEntry(let name):
            String(localized: "This archive tries to write outside its folder (“\(name)”), so nothing was unpacked.")
        }
    }
}
