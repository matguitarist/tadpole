// Adds (or removes) a "load this library if it's there" command in a Mach-O
// executable, the way insert_dylib does: the Script Extender for macOS is
// loaded by the game because its executable lists libbg3se.dylib. Each
// architecture of a universal binary is patched. The code signature is
// invalid afterwards; the caller re-signs (ad hoc).

import Foundation

public enum MachOPatcher {
    public enum PatchError: LocalizedError, Equatable {
        case notMachO
        case noRoom
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .notMachO: String(localized: "The game's executable isn't a Mac program Tadpole can read.")
            case .noRoom: String(localized: "There's no room in the game's executable to add the Script Extender.")
            case .unreadable: String(localized: "The game's executable couldn't be read.")
            }
        }
    }

    static let fatMagic: UInt32 = 0xCAFE_BABE
    static let fatMagic64: UInt32 = 0xCAFE_BABF
    static let machOMagic64: UInt32 = 0xFEED_FACF
    static let loadDylib: UInt32 = 0xC
    static let loadWeakDylib: UInt32 = 0x8000_0018
    static let reexportDylib: UInt32 = 0x8000_001F
    static let segment64: UInt32 = 0x19
    /// Load commands are read from the start of each slice; 64 KB is far
    /// more than any executable's header and load commands.
    static let headerWindow = 64 * 1024

    /// Whether every architecture of the file loads a library whose path
    /// contains `name` (e.g. "libbg3se").
    public static func links(_ file: URL, libraryNamed name: String) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let slices = try sliceOffsets(handle)
        for offset in slices {
            let header = try SliceHeader(handle, at: offset)
            if !header.libraries.contains(where: { $0.contains(name) }) { return false }
        }
        return !slices.isEmpty
    }

    /// Adds a weak LC_LOAD_DYLIB-style command for `installName` to every
    /// architecture that doesn't load it yet.
    public static func addWeakLibrary(_ installName: String, to file: URL) throws {
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        // Check every slice first: fail before changing anything.
        let headers = try sliceOffsets(handle).map { try SliceHeader(handle, at: $0) }
        let command = dylibCommand(installName)
        for header in headers where !header.libraries.contains(installName) {
            guard header.freeSpace >= command.count else { throw PatchError.noRoom }
        }
        for header in headers where !header.libraries.contains(installName) {
            try handle.seek(toOffset: header.offset + 32 + UInt64(header.sizeOfCommands))
            try handle.write(contentsOf: command)
            try handle.seek(toOffset: header.offset + 16)
            try handle.write(contentsOf: littleEndian(header.commandCount + 1) + littleEndian(header.sizeOfCommands + UInt32(command.count)))
        }
        try handle.synchronize()
    }

    /// Removes the commands loading a library whose path contains `name`.
    public static func removeLibrary(named name: String, from file: URL) throws {
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        for offset in try sliceOffsets(handle) {
            let header = try SliceHeader(handle, at: offset)
            var commands = Data()
            var count: UInt32 = 0
            for command in header.commands {
                if let library = command.library, library.contains(name) { continue }
                commands.append(command.data)
                count += 1
            }
            guard count != header.commandCount else { continue }
            let removed = Int(header.sizeOfCommands) - commands.count
            try handle.seek(toOffset: offset + 16)
            try handle.write(contentsOf: littleEndian(count) + littleEndian(UInt32(commands.count)))
            try handle.seek(toOffset: offset + 32)
            try handle.write(contentsOf: commands + Data(count: removed))  // zeros where the command was
        }
        try handle.synchronize()
    }

    // MARK: Reading

    private static func sliceOffsets(_ handle: FileHandle) throws -> [UInt64] {
        try handle.seek(toOffset: 0)
        guard let start = try handle.read(upToCount: 8), start.count == 8 else { throw PatchError.unreadable }
        let magicBE = start.uint32(at: 0, bigEndian: true)
        if magicBE == fatMagic || magicBE == fatMagic64 {
            let is64 = magicBE == fatMagic64
            let count = Int(start.uint32(at: 4, bigEndian: true))
            let entrySize = is64 ? 32 : 20
            guard count > 0, count < 32, let table = try handle.read(upToCount: count * entrySize), table.count == count * entrySize else {
                throw PatchError.notMachO
            }
            return (0..<count).map { index in
                let base = index * entrySize
                return is64 ? table.uint64(at: base + 8, bigEndian: true) : UInt64(table.uint32(at: base + 8, bigEndian: true))
            }
        }
        guard start.uint32(at: 0, bigEndian: false) == machOMagic64 else { throw PatchError.notMachO }
        return [0]
    }

    struct Command {
        let type: UInt32
        let data: Data
        /// The library's path, for commands that load one.
        var library: String? {
            guard [loadDylib, loadWeakDylib, reexportDylib].contains(type), data.count > 24 else { return nil }
            let nameOffset = Int(data.uint32(at: 8, bigEndian: false))
            guard nameOffset < data.count else { return nil }
            let bytes = data[data.startIndex + nameOffset..<data.endIndex].prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    struct SliceHeader {
        let offset: UInt64
        let commandCount: UInt32
        let sizeOfCommands: UInt32
        let commands: [Command]
        /// Zero bytes between the last load command and the first section's
        /// contents, where a new command can go.
        let freeSpace: Int

        var libraries: [String] { commands.compactMap(\.library) }

        init(_ handle: FileHandle, at offset: UInt64) throws {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: headerWindow), data.count >= 32,
                  data.uint32(at: 0, bigEndian: false) == machOMagic64 else { throw PatchError.notMachO }
            self.offset = offset
            commandCount = data.uint32(at: 16, bigEndian: false)
            sizeOfCommands = data.uint32(at: 20, bigEndian: false)
            let end = 32 + Int(sizeOfCommands)
            guard end <= data.count else { throw PatchError.unreadable }

            var commands: [Command] = []
            var firstSectionData = data.count
            var cursor = 32
            for _ in 0..<commandCount {
                guard cursor + 8 <= end else { throw PatchError.unreadable }
                let type = data.uint32(at: cursor, bigEndian: false)
                let size = Int(data.uint32(at: cursor + 4, bigEndian: false))
                guard size >= 8, cursor + size <= end else { throw PatchError.unreadable }
                let body = Data(data[cursor..<cursor + size])
                commands.append(Command(type: type, data: body))
                if type == segment64 {
                    let sections = Int(body.uint32(at: 64, bigEndian: false))
                    for index in 0..<sections where 72 + index * 80 + 52 <= body.count {
                        let fileOffset = Int(body.uint32(at: 72 + index * 80 + 48, bigEndian: false))
                        if fileOffset > 0 { firstSectionData = min(firstSectionData, fileOffset) }
                    }
                }
                cursor += size
            }
            self.commands = commands
            // Only zeros count as free.
            let gap = data[end..<max(end, firstSectionData)]
            freeSpace = gap.prefix { $0 == 0 }.count
        }
    }

    // MARK: Writing

    /// A weak dylib command (like insert_dylib's): the name follows the
    /// 24-byte header, padded to 8 bytes.
    static func dylibCommand(_ installName: String) -> Data {
        let name = Data(installName.utf8) + Data([0])
        let size = (24 + name.count + 7) / 8 * 8
        var command = littleEndian(loadWeakDylib) + littleEndian(UInt32(size))
        command += littleEndian(UInt32(24))  // name offset
        command += littleEndian(UInt32(2))   // timestamp
        command += littleEndian(UInt32(0))   // current version
        command += littleEndian(UInt32(0))   // compatibility version
        command += name
        command += Data(count: size - command.count)
        return command
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}

private extension Data {
    func uint32(at index: Int, bigEndian: Bool) -> UInt32 {
        let value = self[startIndex + index..<startIndex + index + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return bigEndian ? value : value.byteSwapped
    }

    func uint64(at index: Int, bigEndian: Bool) -> UInt64 {
        let value = self[startIndex + index..<startIndex + index + 8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return bigEndian ? value : value.byteSwapped
    }
}
