import CZlib
import Foundation
import NomacCore

/// The entries of a zip archive as `ditto -c -k` writes an IPA (stored and deflated entries, no
/// zip64), in the order of its central directory, for `nomac verify`'s comparison of exports and
/// the bundle identifier of an IPA `nomac install` stops first.
public struct ZipArchive {
    public struct Entry: Equatable {
        public var name: String
        /// The Unix mode in the upper half of the external attributes: type and permissions.
        public var mode: UInt32
        public var contents: [UInt8]
        var isDirectory: Bool { mode & 0o170000 == 0o040000 || name.hasSuffix("/") }
        var isSymbolicLink: Bool { mode & 0o170000 == 0o120000 }
    }

    public var entries: [Entry]

    public init(path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("cannot read the zip archive", path: path) }
        let bytes = [UInt8](data)
        func u16(_ at: Int) throws -> Int {
            guard at >= 0, at + 2 <= bytes.count else { throw NomacError("truncated zip archive", path: path) }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8
        }
        func u32(_ at: Int) throws -> Int { let low = try u16(at), high = try u16(at + 2); return low | high << 16 }
        guard bytes.count >= 22, let end = (0...(bytes.count - 22)).reversed().first(where: { bytes[$0..<($0 + 4)].elementsEqual([0x50, 0x4b, 0x05, 0x06]) }) else {
            throw NomacError("not a zip archive", path: path)
        }
        var central = try u32(end + 16)
        entries = []
        for _ in 0..<(try u16(end + 10)) {
            guard try u32(central) == 0x0201_4b50 else { throw NomacError("malformed central directory", path: path) }
            let method = try u16(central + 10)
            let compressedSize = try u32(central + 20), size = try u32(central + 24)
            let nameLength = try u16(central + 28), extraLength = try u16(central + 30), commentLength = try u16(central + 32)
            let mode = UInt32(try u32(central + 38) >> 16)
            let local = try u32(central + 42)
            guard central + 46 + nameLength <= bytes.count else { throw NomacError("truncated zip archive", path: path) }
            let name = String(decoding: bytes[(central + 46)..<(central + 46 + nameLength)], as: UTF8.self)
            let localName = try u16(local + 26), localExtra = try u16(local + 28)
            let start = local + 30 + localName + localExtra
            guard start + compressedSize <= bytes.count else { throw NomacError("truncated entry \(name)", path: path) }
            let stored = Array(bytes[start..<(start + compressedSize)])
            let contents: [UInt8]
            switch method {
            case 0: contents = stored
            case 8: contents = try Self.inflate(stored, size: size, name: name, path: path)
            default: throw NomacError("entry \(name) uses compression method \(method)", path: path)
            }
            entries.append(Entry(name: name, mode: mode, contents: contents))
            central += 46 + nameLength + extraLength + commentLength
        }
    }

    /// Raw deflate data, as zip entries hold it.
    static func inflate(_ input: [UInt8], size: Int, name: String, path: String) throws -> [UInt8] {
        guard size > 0 else { return [] }
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw NomacError("could not start inflating \(name)", path: path)
        }
        defer { inflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: size)
        var input = input
        let status = input.withUnsafeMutableBufferPointer { source in
            output.withUnsafeMutableBufferPointer { target in
                stream.next_in = source.baseAddress
                stream.avail_in = UInt32(source.count)
                stream.next_out = target.baseAddress
                stream.avail_out = UInt32(target.count)
                return CZlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, Int(stream.total_out) == size else { throw NomacError("malformed deflate data in \(name)", path: path) }
        return output
    }

    /// Writes the entries under `directory`: folders, files with their permissions, symbolic links.
    func extract(to directory: String) throws {
        let manager = FileManager.default
        for entry in entries {
            let path = directory + "/" + entry.name
            if entry.isDirectory {
                try FileSystem.createDirectory(path)
            } else if entry.isSymbolicLink {
                try FileSystem.createDirectory((path as NSString).deletingLastPathComponent)
                try manager.createSymbolicLink(atPath: path, withDestinationPath: String(decoding: entry.contents, as: UTF8.self))
            } else {
                try FileSystem.write(Data(entry.contents), to: path)
                try manager.setAttributes([.posixPermissions: Int(entry.mode & 0o7777)], ofItemAtPath: path)
            }
        }
    }
}
