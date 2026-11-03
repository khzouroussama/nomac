import CZlib
import Foundation
import NomacCore

/// Zip archives as `ditto -c -k --norsrc <directory> <archive>` writes them, the command
/// `xcodebuild -exportArchive` makes its IPA with (docs/formats/ipa.md).
///
/// Every value below was observed in ditto's archives of self-written folders and in Xcode's IPAs;
/// the record layouts are those of PKWARE's APPNOTE.TXT. Entries are the folder's contents,
/// depth first, each folder before its contents and in APFS order (``APFSOrder``):
///
/// - a folder or an empty file: stored, "version needed" 1.0, no flags, no data;
/// - a file: deflated (raw deflate, zlib level 6, even when larger), version 2.0, flag 0x8 with
///   CRC and sizes zero in the local header and given in a data descriptor (`PK\7\8`);
/// - a symbolic link: stored, version 1.0, its target as data, CRC and sizes in the local header,
///   and no extra field.
///
/// All entries are "made by" Unix 2.1 (0x0315), with external attributes `st_mode << 16 | 0x4000`,
/// no internal attributes and names as their bytes on disk (no UTF-8 flag). Folders and files
/// carry the Info-ZIP "UX" extra field (0x5855): access and modification times and, in the
/// local header only, the owner's user and group ids. The DOS time is the modification time in
/// the local time zone, odd seconds rounded up.
public enum DittoArchive {
    /// One entry of an archive, with what it records of the file.
    struct Entry {
        enum Kind {
            case directory
            case file(path: String)
            case symbolicLink(target: String)
        }

        var name: String
        var kind: Kind
        var mode: UInt32
        var accessTime: Int
        var modificationTime: Int
        var userID: UInt32
        var groupID: UInt32
    }

    /// Writes the contents of `directory` to a new archive at `archive`.
    public static func create(from directory: String, to archive: String) throws {
        try write(try entries(of: directory), to: archive, timeZone: .current)
    }

    /// Writes `entries` to a new archive at `archive`, with DOS times in `timeZone`.
    static func write(_ entries: [Entry], to archive: String, timeZone: TimeZone) throws {
        guard FileManager.default.createFile(atPath: archive, contents: nil),
              let handle = FileHandle(forWritingAtPath: archive) else {
            throw NomacError("could not create the archive", path: archive)
        }
        defer { try? handle.close() }
        var writer = Writer(handle: handle, timeZone: timeZone)
        for entry in entries { try writer.add(entry) }
        try writer.finish()
    }

    /// The entries for the contents of `directory`, in ditto's order.
    static func entries(of directory: String) throws -> [Entry] {
        var result: [Entry] = []
        try collect(directory, prefix: "", into: &result)
        return result
    }

    private static func collect(_ directory: String, prefix: String, into result: inout [Entry]) throws {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory)
        } catch {
            throw NomacError("could not list directory: \(error.localizedDescription)", path: directory)
        }
        for name in APFSOrder.sorted(names) {
            let path = directory + "/" + name
            var info = stat()
            guard lstat(path, &info) == 0 else { throw NomacError("could not read file information", path: path) }
            let mode = UInt32(info.st_mode)
            #if canImport(Darwin)
            let (accessTime, modificationTime) = (info.st_atimespec.tv_sec, info.st_mtimespec.tv_sec)
            #else
            let (accessTime, modificationTime) = (info.st_atim.tv_sec, info.st_mtim.tv_sec)
            #endif
            var entry = Entry(name: prefix + name, kind: .file(path: path), mode: mode, accessTime: Int(accessTime),
                              modificationTime: Int(modificationTime), userID: UInt32(info.st_uid), groupID: UInt32(info.st_gid))
            switch mode & 0o170000 {
            case 0o040000:
                entry.name += "/"
                entry.kind = .directory
                result.append(entry)
                try collect(path, prefix: entry.name, into: &result)
            case 0o120000:
                // A link's own mode on macOS (0755 under the usual umask), whatever the system.
                entry.mode = 0o120755
                entry.kind = .symbolicLink(target: try FileManager.default.destinationOfSymbolicLink(atPath: path))
                result.append(entry)
            default:
                result.append(entry)
            }
        }
    }

    private struct Writer {
        let handle: FileHandle
        let timeZone: TimeZone
        var offset = 0
        var central: [UInt8] = []
        var count = 0

        init(handle: FileHandle, timeZone: TimeZone) {
            self.handle = handle
            self.timeZone = timeZone
        }

        mutating func add(_ entry: Entry) throws {
            var data: [UInt8] = []
            var crc: UInt32 = 0
            var size = 0
            var deflated = false
            switch entry.kind {
            case .directory:
                break
            case .file(let path):
                guard let contents = FileManager.default.contents(atPath: path) else { throw NomacError("could not read file", path: path) }
                size = contents.count
                guard size <= UInt32.max else { throw Self.zip64(entry.name) }
                if size > 0 {
                    crc = Zlib.crc32(contents)
                    data = try Zlib.deflate(contents)
                    deflated = true
                }
            case .symbolicLink(let target):
                data = Array(target.utf8)
                size = data.count
                crc = Zlib.crc32(Data(data))
            }
            guard offset <= UInt32.max, data.count <= UInt32.max, count + 1 < UInt16.max else { throw Self.zip64(entry.name) }
            let isLink = if case .symbolicLink = entry.kind { true } else { false }
            let name = Array(entry.name.utf8)
            let (time, date) = DOSTime.of(entry.modificationTime, in: timeZone)
            let version: UInt16 = deflated ? 20 : 10
            let flags: UInt16 = deflated ? 0x8 : 0
            let method: UInt16 = deflated ? 8 : 0
            let times = LittleEndian.u32(UInt32(truncatingIfNeeded: entry.accessTime)) + LittleEndian.u32(UInt32(truncatingIfNeeded: entry.modificationTime))
            let localExtra = isLink ? [] : [0x55, 0x58, 12, 0] + times + LittleEndian.u16(UInt16(truncatingIfNeeded: entry.userID))
                + LittleEndian.u16(UInt16(truncatingIfNeeded: entry.groupID))
            let centralExtra = isLink ? [] : [0x55, 0x58, 8, 0] + times

            var local: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
            local += LittleEndian.u16(version) + LittleEndian.u16(flags) + LittleEndian.u16(method) + LittleEndian.u16(time) + LittleEndian.u16(date)
            local += deflated ? [UInt8](repeating: 0, count: 12) : LittleEndian.u32(crc) + LittleEndian.u32(UInt32(data.count)) + LittleEndian.u32(UInt32(size))
            local += LittleEndian.u16(UInt16(name.count)) + LittleEndian.u16(UInt16(localExtra.count)) + name + localExtra
            var record = local + data
            if deflated {
                record += [0x50, 0x4b, 0x07, 0x08] + LittleEndian.u32(crc) + LittleEndian.u32(UInt32(data.count)) + LittleEndian.u32(UInt32(size))
            }

            central += [0x50, 0x4b, 0x01, 0x02] + LittleEndian.u16(0x0315) + LittleEndian.u16(version) + LittleEndian.u16(flags)
            central += LittleEndian.u16(method) + LittleEndian.u16(time) + LittleEndian.u16(date)
            central += LittleEndian.u32(crc) + LittleEndian.u32(UInt32(data.count)) + LittleEndian.u32(UInt32(size))
            central += LittleEndian.u16(UInt16(name.count)) + LittleEndian.u16(UInt16(centralExtra.count)) + LittleEndian.u16(0)
            central += LittleEndian.u16(0) + LittleEndian.u16(0) + LittleEndian.u32(entry.mode << 16 | 0x4000) + LittleEndian.u32(UInt32(offset))
            central += name + centralExtra

            try write(record)
            count += 1
        }

        mutating func finish() throws {
            let start = offset
            guard start <= UInt32.max, central.count <= UInt32.max else { throw Self.zip64(nil) }
            try write(central)
            var end: [UInt8] = [0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0]
            end += LittleEndian.u16(UInt16(count)) + LittleEndian.u16(UInt16(count))
            end += LittleEndian.u32(UInt32(central.count)) + LittleEndian.u32(UInt32(start)) + LittleEndian.u16(0)
            try write(end)
        }

        /// Sizes, offsets or an entry count that the 32- and 16-bit fields cannot hold.
        static func zip64(_ entry: String?) -> NomacError {
            NomacError("archives that need Zip64 are not supported (BACKLOG B-306)", path: entry)
        }

        private mutating func write(_ bytes: [UInt8]) throws {
            do {
                try handle.write(contentsOf: Data(bytes))
            } catch {
                throw NomacError("could not write the archive: \(error.localizedDescription)")
            }
            offset += bytes.count
        }
    }
}

/// MS-DOS date and time fields of a modification time in a time zone, odd seconds rounded up to
/// the next even one (observed: 20:52:09 is written 20:52:10, 03:04:06 as is).
enum DOSTime {
    static func of(_ time: Int, in timeZone: TimeZone) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = Date(timeIntervalSince1970: TimeInterval(time + (time & 1)))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let dosTime = UInt16(parts.hour!) << 11 | UInt16(parts.minute!) << 5 | UInt16(parts.second! / 2)
        let dosDate = UInt16(max(parts.year! - 1980, 0)) << 9 | UInt16(parts.month!) << 5 | UInt16(parts.day!)
        return (dosTime, dosDate)
    }
}

enum LittleEndian {
    static func u16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xff), UInt8(value >> 8)] }
    static func u32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) } }
}

/// The deflate and CRC-32 of the system's zlib, which ditto uses: Xcode's IPAs match zlib 1.2.12's
/// raw deflate at level 6 (`deflateInit2(level 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY)`) for
/// every file observed, executables included.
enum Zlib {
    static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            var crc = CZlib.crc32(0, nil, 0)
            var start = 0
            while start < buffer.count {
                let length = min(buffer.count - start, Int(UInt32.max))
                crc = CZlib.crc32(crc, buffer.baseAddress!.advanced(by: start).assumingMemoryBound(to: Bytef.self), uInt(length))
                start += length
            }
            return UInt32(crc)
        }
    }

    static func deflate(_ data: Data) throws -> [UInt8] {
        var stream = z_stream()
        guard deflateInit2_(&stream, 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw NomacError("zlib could not start compressing")
        }
        defer { deflateEnd(&stream) }
        guard data.count <= UInt32.max else { throw NomacError("zlib cannot take more than 4 GiB at once") }
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(data.count))))
        // The bound can pass 4 GiB, more than `avail_out` holds: the output is given in parts.
        let status = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { out in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                var status = Z_OK
                while status == Z_OK {
                    let written = Int(stream.total_out)
                    stream.next_out = out.bindMemory(to: Bytef.self).baseAddress!.advanced(by: written)
                    stream.avail_out = uInt(min(out.count - written, Int(UInt32.max)))
                    status = CZlib.deflate(&stream, Z_FINISH)
                }
                return status
            }
        }
        guard status == Z_STREAM_END else { throw NomacError("zlib could not compress (status \(status))") }
        output.removeSubrange(Int(stream.total_out)...)
        return output
    }
}
