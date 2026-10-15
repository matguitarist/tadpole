// A mod's identity, from the meta.lsx inside its .pak
// (Mods/<Folder>/meta.lsx): the UUID the game loads it by, its name,
// folder and version, and the mods it depends on.

import Foundation

public struct ModuleReference: Sendable, Hashable {
    public let uuid: String
    public let name: String

    /// UUIDs compare case-insensitively: kept lowercased.
    public init(uuid: String, name: String) {
        self.uuid = uuid.lowercased()
        self.name = name
    }
}

public struct ModuleInfo: Sendable, Hashable {
    public var uuid: String
    public var name: String
    public var folder: String
    public var author: String
    public var description: String
    public var version64: Int64
    public var md5: String
    public var publishHandle: UInt64
    public var dependencies: [ModuleReference]

    public var version: ModVersion { ModVersion(version64) }

    /// From the meta.lsx document.
    public init(meta: LSXDocument) throws {
        guard let root = meta.region("Config"), let info = root.descendants("ModuleInfo").first else {
            throw LSXError.missing("ModuleInfo")
        }
        guard let uuid = info[attribute: "UUID"], !uuid.isEmpty else { throw LSXError.missing("UUID") }
        self.uuid = uuid.lowercased()
        name = info[attribute: "Name"] ?? ""
        folder = info[attribute: "Folder"] ?? ""
        author = info[attribute: "Author"] ?? ""
        description = info[attribute: "Description"] ?? ""
        // Older mods have "Version" (int32) instead of "Version64".
        version64 = (info[attribute: "Version64"] ?? info[attribute: "Version"]).flatMap { Int64($0) } ?? 0
        md5 = info[attribute: "MD5"] ?? ""
        publishHandle = info[attribute: "PublishHandle"].flatMap { UInt64($0) } ?? 0
        dependencies = root.descendants("Dependencies").flatMap { $0.descendants("ModuleShortDesc") }.compactMap { node in
            guard let uuid = node[attribute: "UUID"], !uuid.isEmpty else { return nil }
            return ModuleReference(uuid: uuid, name: node[attribute: "Name"] ?? node[attribute: "Folder"] ?? uuid)
        }
    }

    public init(uuid: String, name: String, folder: String, author: String = "", description: String = "",
                version64: Int64 = 0, md5: String = "", publishHandle: UInt64 = 0, dependencies: [ModuleReference] = []) {
        self.uuid = uuid.lowercased()
        self.name = name
        self.folder = folder
        self.author = author
        self.description = description
        self.version64 = version64
        self.md5 = md5
        self.publishHandle = publishHandle
        self.dependencies = dependencies
    }
}

/// Larian's packed version: major.minor.revision.build in one 64-bit number.
public struct ModVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int, minor: Int, revision: Int, build: Int

    public init(_ packed: Int64) {
        let value = UInt64(bitPattern: packed)
        major = Int(value >> 55)
        minor = Int((value >> 47) & 0xFF)
        revision = Int((value >> 31) & 0xFFFF)
        build = Int(value & 0x7FFF_FFFF)
    }

    public init(major: Int, minor: Int, revision: Int, build: Int) {
        self.major = major
        self.minor = minor
        self.revision = revision
        self.build = build
    }

    public var packed: Int64 {
        Int64(bitPattern: UInt64(major) << 55 | UInt64(minor) << 47 | UInt64(revision) << 31 | UInt64(build))
    }

    public var description: String { "\(major).\(minor).\(revision).\(build)" }

    public static func < (a: ModVersion, b: ModVersion) -> Bool {
        (a.major, a.minor, a.revision, a.build) < (b.major, b.minor, b.revision, b.build)
    }
}
