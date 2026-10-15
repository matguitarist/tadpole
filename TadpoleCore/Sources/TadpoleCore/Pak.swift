// Larian's .pak archives (LSPK), as BG3 mods ship them: a header, the
// files' data, and an LZ4-compressed file list. Only what a mod manager
// needs: list the files and read a small one (meta.lsx). Version 18 is the
// format BG3 uses since release.

import Compression
import Foundation

public struct PakEntry: Sendable, Hashable {
    public let path: String
    let offset: UInt64
    let sizeOnDisk: UInt32
    let uncompressedSize: UInt32
    let flags: UInt8
    let archivePart: UInt8

    /// Compression of this file's data: the low 4 bits of its flags.
    var compression: UInt8 { flags & 0x0F }
}

public enum PakError: LocalizedError, Equatable {
    case notAPak
    case unsupportedVersion(UInt32)
    case corrupt(String)
    case unsupportedCompression(UInt8)
    case inAnotherPart

    public var errorDescription: String? {
        switch self {
        case .notAPak: "This isn't a Larian .pak file."
        case .unsupportedVersion(let version): "This .pak uses format version \(version), which isn't supported (BG3 uses version 18)."
        case .corrupt(let detail): "This .pak seems damaged: \(detail)"
        case .unsupportedCompression(let method): "A file in this .pak uses a compression method that isn't supported (\(method))."
        case .inAnotherPart: "The file is stored in another part of a multi-part .pak."
        }
    }
}

public struct PakArchive: Sendable {
    public let url: URL
    public let version: UInt32
    public let entries: [PakEntry]

    static let signature: [UInt8] = Array("LSPK".utf8)
    static let entrySize = 272  // v18: name[256], offset u32+u16, part u8, flags u8, sizeOnDisk u32, size u32

    public init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // Signature, then the v16/v18 header: version u32, file list offset
        // u64, file list size u32, flags u8, priority u8, md5[16], parts u16.
        let header = try handle.read(upToCount: 4 + 36) ?? Data()
        guard header.count == 40, Array(header.prefix(4)) == Self.signature else { throw PakError.notAPak }
        var reader = ByteReader(header.dropFirst(4))
        let version = reader.u32()
        guard version == 18 else { throw PakError.unsupportedVersion(version) }
        let listOffset = reader.u64()
        self.version = version

        try handle.seek(toOffset: listOffset)
        guard let counts = try handle.read(upToCount: 8), counts.count == 8 else { throw PakError.corrupt("no file list") }
        var countReader = ByteReader(counts)
        let fileCount = Int(countReader.u32())
        let compressedSize = Int(countReader.u32())
        guard fileCount < 1_000_000, compressedSize > 0, compressedSize < 512 << 20 else { throw PakError.corrupt("bad file list size") }
        guard let compressed = try handle.read(upToCount: compressedSize), compressed.count == compressedSize else {
            throw PakError.corrupt("file list cut short")
        }
        let list = try LZ4.decompress(compressed, size: fileCount * Self.entrySize)

        var entries: [PakEntry] = []
        entries.reserveCapacity(fileCount)
        for index in 0..<fileCount {
            var entry = ByteReader(list[(index * Self.entrySize)..<((index + 1) * Self.entrySize)])
            let nameBytes = entry.bytes(256)
            let name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
            let offsetLow = UInt64(entry.u32())
            let offsetHigh = UInt64(entry.u16())
            let part = entry.u8()
            let flags = entry.u8()
            let sizeOnDisk = entry.u32()
            let size = entry.u32()
            entries.append(PakEntry(path: name, offset: offsetLow | offsetHigh << 32, sizeOnDisk: sizeOnDisk,
                                    uncompressedSize: size, flags: flags, archivePart: part))
        }
        self.entries = entries
    }

    /// The contents of one file in the archive.
    public func data(for entry: PakEntry) throws -> Data {
        guard entry.archivePart == 0 else { throw PakError.inAnotherPart }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: entry.offset)
        let stored = try handle.read(upToCount: Int(entry.sizeOnDisk)) ?? Data()
        guard stored.count == Int(entry.sizeOnDisk) else { throw PakError.corrupt("\(entry.path) is cut short") }
        switch entry.compression {
        case 0:
            return stored
        case 1:
            // zlib: skip the 2-byte header; Compression reads raw deflate.
            return try Inflate.decompress(stored.dropFirst(2), size: Int(entry.uncompressedSize))
        case 2:
            return try LZ4.decompress(stored, size: Int(entry.uncompressedSize))
        default:
            throw PakError.unsupportedCompression(entry.compression)
        }
    }

    /// The first file whose path matches, ignoring case.
    public func entry(matching predicate: (String) -> Bool) -> PakEntry? {
        entries.first { predicate($0.path) }
    }
}

/// Little-endian reads from a byte buffer.
struct ByteReader {
    private var bytes: [UInt8]
    private var position = 0

    init<D: Collection>(_ data: D) where D.Element == UInt8 { bytes = Array(data) }

    mutating func u8() -> UInt8 { defer { position += 1 }; return bytes[position] }
    mutating func u16() -> UInt16 { UInt16(u8()) | UInt16(u8()) << 8 }
    mutating func u32() -> UInt32 { UInt32(u16()) | UInt32(u16()) << 16 }
    mutating func u64() -> UInt64 { UInt64(u32()) | UInt64(u32()) << 32 }
    mutating func bytes(_ count: Int) -> ArraySlice<UInt8> {
        defer { position += count }
        return bytes[position..<(position + count)]
    }
}

enum LZ4 {
    /// Decodes a raw LZ4 block of known decompressed size.
    static func decompress<D: DataProtocol>(_ data: D, size: Int) throws -> Data {
        try codec(Data(data), size: size, algorithm: COMPRESSION_LZ4_RAW, encode: false)
    }

    /// Encodes a raw LZ4 block (tests build .pak files with it).
    static func compress(_ data: Data) throws -> Data {
        try codec(data, size: max(64, data.count + data.count / 255 + 64), algorithm: COMPRESSION_LZ4_RAW, encode: true)
    }
}

enum Inflate {
    static func decompress<D: DataProtocol>(_ data: D, size: Int) throws -> Data {
        try codec(Data(data), size: size, algorithm: COMPRESSION_ZLIB, encode: false)
    }
}

private func codec(_ input: Data, size: Int, algorithm: compression_algorithm, encode: Bool) throws -> Data {
    guard size > 0 else { return Data() }
    var output = Data(count: size)
    let written = output.withUnsafeMutableBytes { out in
        input.withUnsafeBytes { inBytes in
            encode
                ? compression_encode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                            inBytes.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, algorithm)
                : compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                            inBytes.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, algorithm)
        }
    }
    guard written > 0, encode || written == size else { throw PakError.corrupt("couldn't decompress") }
    output.count = written
    return output
}
