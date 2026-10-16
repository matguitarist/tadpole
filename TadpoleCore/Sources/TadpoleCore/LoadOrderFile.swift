// Sharing load orders: BG3 Mod Manager's JSON export ({"Order": [{"UUID",
// "Name"}]}), which Tadpole also writes, and the game's modsettings.lsx.

import Foundation

public enum LoadOrderFile {
    public enum ReadError: LocalizedError, Equatable {
        case notALoadOrder

        public var errorDescription: String? {
            String(localized: "This file isn't a load order: Tadpole reads BG3 Mod Manager's .json exports, its own, and modsettings.lsx files.")
        }
    }

    /// The mods in a shared load order, in order (the game's own modules
    /// left out).
    public static func read(_ data: Data) throws -> [ProfileMod] {
        let mods: [ProfileMod]
        if let json = try? JSONSerialization.jsonObject(with: data) {
            mods = try fromJSON(json)
        } else if let settings = try? ModSettings.parse(data) {
            mods = settings.modEntries.map(ProfileMod.init)
        } else {
            throw ReadError.notALoadOrder
        }
        return mods.filter { !ModSettings.baseModuleUUIDs.contains($0.uuid) && !ModRules.gameModuleNames.contains($0.name) }
    }

    /// {"Order": [{"UUID": …, "Name": …}]}, any key case; or a bare array.
    static func fromJSON(_ json: Any) throws -> [ProfileMod] {
        func value(_ object: [String: Any], _ key: String) -> String? {
            object.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value as? String
        }
        let list: [Any]
        if let object = json as? [String: Any], let order = object.first(where: { $0.key.caseInsensitiveCompare("Order") == .orderedSame })?.value as? [Any] {
            list = order
        } else if let array = json as? [Any] {
            list = array
        } else {
            throw ReadError.notALoadOrder
        }
        let mods = list.compactMap { item -> ProfileMod? in
            guard let object = item as? [String: Any], let uuid = value(object, "UUID"), !uuid.isEmpty else { return nil }
            return ProfileMod(uuid: uuid, name: value(object, "Name") ?? uuid, folder: value(object, "Folder") ?? "")
        }
        guard !mods.isEmpty || list.isEmpty else { throw ReadError.notALoadOrder }
        return mods
    }

    /// BG3 Mod Manager's format, so either app can import it.
    public static func write(_ mods: [ProfileMod], name: String) throws -> Data {
        let order = mods.map { ["UUID": $0.uuid, "Name": $0.name, "Folder": $0.folder] }
        let object: [String: Any] = ["Name": name, "Order": order, "Exported": ISO8601DateFormatter().string(from: .now), "Source": "Tadpole"]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}
