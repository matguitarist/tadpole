import Foundation
@testable import TadpoleCore

/// Builds .pak files in the v18 layout, the way Larian's tools write them.
enum PakBuilder {
    struct File {
        var path: String
        var data: Data
        var lz4 = true
    }

    static func make(_ files: [File]) throws -> Data {
        var body = Data()
        var list = Data()
        let headerSize = 40
        for file in files {
            // Tiny files don't compress; they're stored as they are, like Larian's tools do.
            let compressed = file.lz4 ? try? LZ4.compress(file.data) : nil
            let lz4 = compressed != nil
            let stored = compressed ?? file.data
            let offset = UInt64(headerSize + body.count)
            body.append(stored)
            var name = Data(file.path.utf8)
            name.append(Data(count: 256 - name.count))
            list.append(name)
            list.append(le(UInt32(offset & 0xFFFF_FFFF)))
            list.append(le(UInt16(offset >> 32)))
            list.append(0)  // archive part
            list.append(lz4 ? 2 : 0)  // flags: compression
            list.append(le(UInt32(stored.count)))
            list.append(le(UInt32(file.data.count)))
        }
        let compressedList = try LZ4.compress(list)
        let listOffset = UInt64(headerSize + body.count)
        var pak = Data("LSPK".utf8)
        pak.append(le(UInt32(18)))
        pak.append(le(listOffset))
        pak.append(le(UInt32(8 + compressedList.count)))
        pak.append(0)  // flags
        pak.append(0)  // priority
        pak.append(Data(count: 16))  // md5
        pak.append(le(UInt16(1)))  // parts
        precondition(pak.count == headerSize)
        pak.append(body)
        pak.append(le(UInt32(files.count)))
        pak.append(le(UInt32(compressedList.count)))
        pak.append(compressedList)
        return pak
    }

    private static func le<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}

enum Samples {
    static let metaLSX = """
    <?xml version="1.0" encoding="UTF-8"?>
    <save>
        <version major="4" minor="0" revision="9" build="331"/>
        <region id="Config">
            <node id="root">
                <children>
                    <node id="Dependencies">
                        <children>
                            <node id="ModuleShortDesc">
                                <attribute id="Folder" type="LSString" value="ImprovedUI"/>
                                <attribute id="Name" type="LSString" value="ImprovedUI"/>
                                <attribute id="UUID" type="FixedString" value="E0E2A9C8-1234-4B2A-9F00-0123456789AB"/>
                                <attribute id="Version64" type="int64" value="36028797018963968"/>
                            </node>
                        </children>
                    </node>
                    <node id="ModuleInfo">
                        <attribute id="Author" type="LSString" value="Someone &amp; Co"/>
                        <attribute id="Description" type="LSString" value="Adds more spell slots."/>
                        <attribute id="Folder" type="LSString" value="MoreSpellSlots"/>
                        <attribute id="MD5" type="LSString" value=""/>
                        <attribute id="Name" type="LSString" value="More Spell Slots"/>
                        <attribute id="PublishHandle" type="uint64" value="0"/>
                        <attribute id="UUID" type="FixedString" value="1A2B3C4D-0000-4000-8000-00000000AAAA"/>
                        <attribute id="Version64" type="int64" value="36169534507319297"/>
                        <children>
                            <node id="PublishVersion">
                                <attribute id="Version64" type="int64" value="1"/>
                            </node>
                        </children>
                    </node>
                </children>
            </node>
        </region>
    </save>
    """

    static let modSettingsPatch7 = """
    <?xml version="1.0" encoding="UTF-8"?>
    <save>
        <version major="4" minor="8" revision="0" build="10"/>
        <region id="ModuleSettings">
            <node id="root">
                <children>
                    <node id="Mods">
                        <children>
                            <node id="ModuleShortDesc">
                                <attribute id="Folder" type="LSString" value="GustavX"/>
                                <attribute id="MD5" type="LSString" value=""/>
                                <attribute id="Name" type="LSString" value="GustavX"/>
                                <attribute id="PublishHandle" type="uint64" value="0"/>
                                <attribute id="UUID" type="guid" value="cb555efe-2d9e-131f-8195-a89329d218ea"/>
                                <attribute id="Version64" type="int64" value="36028797018963968"/>
                            </node>
                            <node id="ModuleShortDesc">
                                <attribute id="Folder" type="LSString" value="OldMod"/>
                                <attribute id="MD5" type="LSString" value=""/>
                                <attribute id="Name" type="LSString" value="Old Mod"/>
                                <attribute id="PublishHandle" type="uint64" value="0"/>
                                <attribute id="UUID" type="guid" value="99999999-0000-4000-8000-000000000001"/>
                                <attribute id="Version64" type="int64" value="1"/>
                            </node>
                        </children>
                    </node>
                </children>
            </node>
        </region>
    </save>
    """
}
