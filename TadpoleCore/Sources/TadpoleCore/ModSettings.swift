// modsettings.lsx (PlayerProfiles/Public): the mods BG3 loads, in order.
// A .pak in the Mods folder that isn't listed here isn't loaded, so
// "enabled" means listed. The game's own base entries (GustavDev, GustavX)
// stay first and untouched.

import Foundation

public struct ModuleShortDesc: Sendable, Hashable {
    public var folder: String
    public var md5: String
    public var name: String
    public var publishHandle: UInt64
    public var uuid: String
    public var version64: Int64

    public init(folder: String, md5: String = "", name: String, publishHandle: UInt64 = 0, uuid: String, version64: Int64) {
        self.folder = folder
        self.md5 = md5
        self.name = name
        self.publishHandle = publishHandle
        self.uuid = uuid.lowercased()
        self.version64 = version64
    }

    public init(_ info: ModuleInfo) {
        self.init(folder: info.folder, md5: info.md5, name: info.name, publishHandle: info.publishHandle,
                  uuid: info.uuid, version64: info.version64)
    }

    init(node: LSXNode) {
        self.init(folder: node[attribute: "Folder"] ?? "", md5: node[attribute: "MD5"] ?? "",
                  name: node[attribute: "Name"] ?? "", publishHandle: node[attribute: "PublishHandle"].flatMap { UInt64($0) } ?? 0,
                  uuid: node[attribute: "UUID"] ?? "",
                  version64: (node[attribute: "Version64"] ?? node[attribute: "Version"]).flatMap { Int64($0) } ?? 0)
    }
}

public struct ModSettings: Sendable, Equatable {
    /// The game's own modules: always listed, never moved.
    public static let baseModuleUUIDs: Set<String> = [
        "28ac9ce2-2aba-8cda-b3b5-6e922f71b6b8",  // GustavDev
        "cb555efe-2d9e-131f-8195-a89329d218ea",  // GustavX (Patch 7 and later)
    ]

    public var version: [String: String]
    public var entries: [ModuleShortDesc]
    /// Files from before Patch 7 also list the order in a "ModOrder" node.
    public var hasModOrder: Bool

    public var baseEntries: [ModuleShortDesc] { entries.filter { Self.baseModuleUUIDs.contains($0.uuid) } }
    /// The enabled mods, in load order.
    public var modEntries: [ModuleShortDesc] { entries.filter { !Self.baseModuleUUIDs.contains($0.uuid) } }

    public static func read(from url: URL) throws -> ModSettings {
        try parse(Data(contentsOf: url))
    }

    public static func parse(_ data: Data) throws -> ModSettings {
        let document = try LSXDocument.parse(data)
        guard let region = document.region("ModuleSettings") else { throw LSXError.missing("ModuleSettings region") }
        let modsNode = region.descendants("Mods").first
        let entries = (modsNode?.children ?? []).filter { $0.id == "ModuleShortDesc" }.map(ModuleShortDesc.init(node:))
        return ModSettings(version: document.version, entries: entries, hasModOrder: !region.descendants("ModOrder").isEmpty)
    }

    /// Lists exactly these mods, in this order, after the base entries.
    public mutating func setEnabledMods(_ mods: [ModuleShortDesc]) {
        let base = baseEntries
        let baseIDs = Set(base.map(\.uuid))
        var seen = Set<String>()
        entries = base + mods.filter { !baseIDs.contains($0.uuid) && seen.insert($0.uuid).inserted }
    }

    /// The file's text, in the layout the game writes.
    public func lsx() -> String {
        let versionAttributes = ["major", "minor", "revision", "build"].compactMap { key in
            version[key].map { "\(key)=\"\($0.xmlEscaped)\"" }
        }.joined(separator: " ")
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            "<save>",
            "    <version \(versionAttributes)/>",
            #"    <region id="ModuleSettings">"#,
            #"        <node id="root">"#,
            "            <children>",
        ]
        if hasModOrder {
            lines.append(#"                <node id="ModOrder">"#)
            lines.append("                    <children>")
            for entry in entries {
                lines.append(#"                        <node id="Module">"#)
                lines.append(#"                            <attribute id="UUID" type="FixedString" value="\#(entry.uuid.xmlEscaped)"/>"#)
                lines.append("                        </node>")
            }
            lines.append("                    </children>")
            lines.append("                </node>")
        }
        lines.append(#"                <node id="Mods">"#)
        lines.append("                    <children>")
        for entry in entries {
            lines += [
                #"                        <node id="ModuleShortDesc">"#,
                #"                            <attribute id="Folder" type="LSString" value="\#(entry.folder.xmlEscaped)"/>"#,
                #"                            <attribute id="MD5" type="LSString" value="\#(entry.md5.xmlEscaped)"/>"#,
                #"                            <attribute id="Name" type="LSString" value="\#(entry.name.xmlEscaped)"/>"#,
                #"                            <attribute id="PublishHandle" type="uint64" value="\#(entry.publishHandle)"/>"#,
                #"                            <attribute id="UUID" type="guid" value="\#(entry.uuid.xmlEscaped)"/>"#,
                #"                            <attribute id="Version64" type="int64" value="\#(entry.version64)"/>"#,
                "                        </node>",
            ]
        }
        lines += [
            "                    </children>",
            "                </node>",
            "            </children>",
            "        </node>",
            "    </region>",
            "</save>",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the file, keeping the previous one as modsettings.lsx.bak.
    public func write(to url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path(percentEncoded: false)) {
            let backup = url.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        try Data(lsx().utf8).write(to: url, options: .atomic)
    }
}
