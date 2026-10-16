// Larian's binary resource format (.lsf, "LSOF"), as BG3 writes it in saves
// (meta.lsf: the save's mod list). Read-only, and only what Tadpole needs:
// every node with its name, parent and attributes, with strings and
// integers decoded (other attribute types are skipped). Follows LSLib's
// LSFReader for versions 6 and 7 with the V2 node and attribute layout.

import Foundation

public struct LSFDocument: Sendable {
    public enum Value: Sendable, Equatable {
        case string(String)
        case integer(Int64)
        case other
    }

    public struct Node: Sendable {
        public let name: String
        public let parent: Int?
        public var attributes: [String: Value]

        public func string(_ name: String) -> String? {
            if case .string(let value) = attributes[name] { return value }
            return nil
        }

        public func integer(_ name: String) -> Int64? {
            if case .integer(let value) = attributes[name] { return value }
            return nil
        }
    }

    public enum ReadError: LocalizedError, Equatable {
        case notLSF
        case unsupportedVersion(UInt32)
        case corrupt(String)

        public var errorDescription: String? {
            switch self {
            case .notLSF: "This isn't a Larian resource file."
            case .unsupportedVersion(let version): "This resource file's version (\(version)) isn't supported."
            case .corrupt(let detail): "This resource file is damaged (\(detail))."
            }
        }
    }

    public let nodes: [Node]

    /// Nodes with this name, in file order.
    public func nodes(named name: String) -> [Node] { nodes.filter { $0.name == name } }

    public init(data: Data) throws {
        var reader = LittleEndianReader(data)
        guard reader.bytes(4).elementsEqual(Array("LSOF".utf8)) else { throw ReadError.notLSF }
        let version = reader.uint32()
        guard (6...7).contains(version) else { throw ReadError.unsupportedVersion(version) }
        _ = reader.uint64()  // engine version

        let stringsSize = reader.uint32(), stringsOnDisk = reader.uint32()
        var keysSize: UInt32 = 0, keysOnDisk: UInt32 = 0
        if version >= 7 { keysSize = reader.uint32(); keysOnDisk = reader.uint32() }
        let nodesSize = reader.uint32(), nodesOnDisk = reader.uint32()
        let attributesSize = reader.uint32(), attributesOnDisk = reader.uint32()
        let valuesSize = reader.uint32(), valuesOnDisk = reader.uint32()
        let compression = reader.byte()
        _ = reader.byte(); _ = reader.uint16()
        let metadataFormat = reader.uint32()
        guard metadataFormat != 1 else { throw ReadError.corrupt("node keys layout") }
        let compressed = compression & 0x0F != 0
        guard !compressed || compression & 0x0F == 2 else { throw ReadError.corrupt("compression \(compression & 0x0F)") }

        // Strings are one LZ4 block; the other sections are LZ4 frames.
        func section(_ size: UInt32, _ onDisk: UInt32, frame: Bool) throws -> Data {
            let stored = Data(reader.bytes(Int(compressed && onDisk > 0 ? onDisk : size)))
            guard compressed, onDisk > 0 else { return stored }
            return frame ? try LZ4Frame.decompress(stored, size: Int(size)) : try LZ4.decompress(stored, size: Int(size))
        }
        let strings = try section(stringsSize, stringsOnDisk, frame: false)
        _ = try section(keysSize, keysOnDisk, frame: true)
        let nodeData = try section(nodesSize, nodesOnDisk, frame: true)
        let attributeData = try section(attributesSize, attributesOnDisk, frame: true)
        let values = try section(valuesSize, valuesOnDisk, frame: true)

        let names = try Self.names(strings)
        func name(_ index: UInt32) -> String {
            let bucket = Int(index >> 16), position = Int(index & 0xFFFF)
            return bucket < names.count && position < names[bucket].count ? names[bucket][position] : ""
        }

        // Nodes (V2): name u32, first attribute i32, parent i32.
        var nodes: [Node] = []
        var nodeReader = LittleEndianReader(nodeData)
        while nodeReader.remaining >= 12 {
            let nameIndex = nodeReader.uint32()
            _ = nodeReader.int32()
            let parent = nodeReader.int32()
            nodes.append(Node(name: name(nameIndex), parent: parent >= 0 ? Int(parent) : nil, attributes: [:]))
        }

        // Attributes (V2): name u32, type (6 bits) and length, node i32; their
        // values follow each other in the values section.
        var attributeReader = LittleEndianReader(attributeData)
        var valueReader = LittleEndianReader(values)
        while attributeReader.remaining >= 12 {
            let nameIndex = attributeReader.uint32()
            let typeAndLength = attributeReader.uint32()
            let node = Int(attributeReader.int32())
            let type = typeAndLength & 0x3F, length = Int(typeAndLength >> 6)
            guard valueReader.remaining >= length else { throw ReadError.corrupt("values") }
            let bytes = Data(valueReader.bytes(length))
            guard nodes.indices.contains(node) else { continue }
            nodes[node].attributes[name(nameIndex)] = Self.value(type: type, bytes: bytes)
        }
        self.nodes = nodes
    }

    /// The names table: hash buckets of length-prefixed UTF-8 strings.
    static func names(_ data: Data) throws -> [[String]] {
        var reader = LittleEndianReader(data)
        let buckets = Int(reader.uint32())
        var names: [[String]] = []
        names.reserveCapacity(buckets)
        for _ in 0..<buckets {
            guard reader.remaining >= 2 else { throw ReadError.corrupt("names") }
            let count = Int(reader.uint16())
            var bucket: [String] = []
            for _ in 0..<count {
                let length = Int(reader.uint16())
                guard reader.remaining >= length else { throw ReadError.corrupt("names") }
                bucket.append(String(decoding: reader.bytes(length), as: UTF8.self))
            }
            names.append(bucket)
        }
        return names
    }

    static func value(type: UInt32, bytes: Data) -> Value {
        func integer<T: FixedWidthInteger>(_: T.Type) -> Value {
            guard bytes.count >= MemoryLayout<T>.size else { return .other }
            return .integer(Int64(truncatingIfNeeded: bytes.prefix(MemoryLayout<T>.size).reversed().reduce(T(0)) { $0 << 8 | T($1) }))
        }
        switch type {
        case 1, 27: return integer(UInt8.self)
        case 2: return integer(Int16.self)
        case 3: return integer(UInt16.self)
        case 4: return integer(Int32.self)
        case 5: return integer(UInt32.self)
        case 19: return .integer(bytes.first == 0 ? 0 : 1)
        case 24, 26, 32: return integer(Int64.self)
        // String, Path, FixedString, LSString, WString, LSWString: null-terminated.
        case 20, 21, 22, 23, 29, 30:
            return .string(String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self))
        default: return .other
        }
    }
}

/// The LZ4 frame format (magic 0x184D2204): blocks that may refer back to
/// earlier ones, so they're decoded into one buffer.
enum LZ4Frame {
    static func decompress(_ data: Data, size: Int) throws -> Data {
        var reader = LittleEndianReader(data)
        guard reader.remaining >= 7, reader.uint32() == 0x184D_2204 else { throw LSFDocument.ReadError.corrupt("LZ4 frame") }
        let flags = reader.byte()
        _ = reader.byte()  // block size
        if flags & 0x08 != 0 { _ = reader.uint64() }  // content size
        if flags & 0x01 != 0 { _ = reader.uint32() }  // dictionary
        _ = reader.byte()  // header checksum
        let blockChecksums = flags & 0x10 != 0
        var output = [UInt8]()
        output.reserveCapacity(size)
        while reader.remaining >= 4 {
            let header = reader.uint32()
            if header == 0 { break }
            let length = Int(header & 0x7FFF_FFFF)
            guard reader.remaining >= length else { throw LSFDocument.ReadError.corrupt("LZ4 block") }
            let block = Array(reader.bytes(length))
            if header & 0x8000_0000 != 0 {
                output.append(contentsOf: block)  // stored uncompressed
            } else {
                try decodeBlock(block, into: &output)
            }
            if blockChecksums { _ = reader.uint32() }
        }
        return Data(output)
    }

    /// One LZ4 block, appended to `output` (matches can reach into earlier
    /// blocks' output).
    static func decodeBlock(_ input: [UInt8], into output: inout [UInt8]) throws {
        var index = 0
        func length(_ initial: Int) throws -> Int {
            var total = initial
            guard initial == 15 else { return total }
            while true {
                guard index < input.count else { throw LSFDocument.ReadError.corrupt("LZ4 length") }
                let byte = Int(input[index]); index += 1
                total += byte
                if byte != 255 { return total }
            }
        }
        while index < input.count {
            let token = Int(input[index]); index += 1
            let literals = try length(token >> 4)
            guard index + literals <= input.count else { throw LSFDocument.ReadError.corrupt("LZ4 literals") }
            output.append(contentsOf: input[index..<index + literals])
            index += literals
            if index >= input.count { break }  // the last sequence has no match
            guard index + 2 <= input.count else { throw LSFDocument.ReadError.corrupt("LZ4 offset") }
            let offset = Int(input[index]) | Int(input[index + 1]) << 8
            index += 2
            let matchLength = try length(token & 0x0F) + 4
            guard offset > 0, offset <= output.count else { throw LSFDocument.ReadError.corrupt("LZ4 match") }
            let start = output.count - offset
            for position in 0..<matchLength { output.append(output[start + position]) }  // may overlap itself
        }
    }
}

/// Little-endian reads over bytes.
struct LittleEndianReader {
    private let data: [UInt8]
    private(set) var position = 0

    init(_ data: Data) { self.data = Array(data) }

    var remaining: Int { data.count - position }

    mutating func bytes(_ count: Int) -> ArraySlice<UInt8> {
        let end = min(data.count, position + max(0, count))
        defer { position = end }
        return data[position..<end]
    }

    mutating func byte() -> UInt8 { bytes(1).first ?? 0 }
    mutating func uint16() -> UInt16 { bytes(2).reversed().reduce(0) { $0 << 8 | UInt16($1) } }
    mutating func uint32() -> UInt32 { bytes(4).reversed().reduce(0) { $0 << 8 | UInt32($1) } }
    mutating func int32() -> Int32 { Int32(bitPattern: uint32()) }
    mutating func uint64() -> UInt64 { bytes(8).reversed().reduce(0) { $0 << 8 | UInt64($1) } }
}
