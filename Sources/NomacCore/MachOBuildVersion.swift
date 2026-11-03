import Foundation

/// The `LC_BUILD_VERSION` load commands of a Mach-O file, the platform and minimum OS version
/// each architecture slice was built for (`vtool -show-build`).
///
/// Formats from the public headers `<mach-o/fat.h>` and `<mach-o/loader.h>`: a universal file
/// starts with a big-endian `fat_header` (magic `0xcafebabe`, or `0xcafebabf` with 64-bit
/// offsets) followed by one `fat_arch` per slice; a slice starts with a little-endian
/// `mach_header` (`0xfeedface`) or `mach_header_64` (`0xfeedfacf`) followed by its load
/// commands. `build_version_command` is `cmd, cmdsize, platform, minos, sdk, ntools`, with
/// versions encoded as `xxxx.yy.zz` in nibbles.
public enum MachOBuildVersion {
    /// One `LC_BUILD_VERSION` command.
    public struct Entry: Equatable, Sendable {
        /// The platform number (`PLATFORM_MACOS` = 1, `PLATFORM_IOS` = 2, ...).
        public var platform: UInt32
        /// The minimum OS version as `major.minor` or `major.minor.patch` (patch only when
        /// not zero), as `vtool` prints it.
        public var minimumOS: String

        public init(platform: UInt32, minimumOS: String) {
            self.platform = platform
            self.minimumOS = minimumOS
        }
    }

    public static let platformMacOS: UInt32 = 1
    public static let platformIOS: UInt32 = 2
    public static let platformTvOS: UInt32 = 3
    public static let platformWatchOS: UInt32 = 4
    public static let platformMacCatalyst: UInt32 = 6
    public static let platformVisionOS: UInt32 = 11

    /// The entries of the file at `path`, in slice order; empty if it is not a Mach-O file.
    public static func entries(atPath path: String) throws -> [Entry] {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw NomacError("cannot read \(path)")
        }
        return entries(in: [UInt8](data))
    }

    /// The entries of a Mach-O file's bytes, in slice order.
    public static func entries(in bytes: [UInt8]) -> [Entry] {
        let reader = Reader(bytes: bytes)
        guard let magic = reader.uint32(at: 0, bigEndian: true) else { return [] }
        switch magic {
        case 0xcafe_babe, 0xcafe_babf:
            let wide = magic == 0xcafe_babf
            guard let count = reader.uint32(at: 4, bigEndian: true) else { return [] }
            var result: [Entry] = []
            let stride = wide ? 32 : 20
            for slice in 0..<Int(count) {
                let base = 8 + slice * stride
                let offset = wide ? reader.uint64(at: base + 8, bigEndian: true).map(Int.init) : reader.uint32(at: base + 8, bigEndian: true).map(Int.init)
                guard let offset else { break }
                result += sliceEntries(reader, at: offset)
            }
            return result
        default:
            return sliceEntries(reader, at: 0)
        }
    }

    private static let loadCommandBuildVersion: UInt32 = 0x32

    private static func sliceEntries(_ reader: Reader, at offset: Int) -> [Entry] {
        guard let magic = reader.uint32(at: offset, bigEndian: false) else { return [] }
        let headerSize: Int
        switch magic {
        case 0xfeed_facf: headerSize = 32
        case 0xfeed_face: headerSize = 28
        default: return []
        }
        guard let count = reader.uint32(at: offset + 16, bigEndian: false) else { return [] }
        var result: [Entry] = []
        var command = offset + headerSize
        for _ in 0..<Int(count) {
            guard let kind = reader.uint32(at: command, bigEndian: false),
                  let size = reader.uint32(at: command + 4, bigEndian: false), size >= 8 else { break }
            if kind == loadCommandBuildVersion,
               let platform = reader.uint32(at: command + 8, bigEndian: false),
               let minimum = reader.uint32(at: command + 12, bigEndian: false) {
                result.append(Entry(platform: platform, minimumOS: version(minimum)))
            }
            command += Int(size)
        }
        return result
    }

    /// `xxxx.yy.zz` as `vtool` prints it.
    static func version(_ encoded: UInt32) -> String {
        let major = encoded >> 16, minor = (encoded >> 8) & 0xff, patch = encoded & 0xff
        return patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    private struct Reader {
        let bytes: [UInt8]

        func uint32(at offset: Int, bigEndian: Bool) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            let value = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
            return bigEndian ? value.byteSwapped : value
        }

        func uint64(at offset: Int, bigEndian: Bool) -> UInt64? {
            guard offset >= 0, offset + 8 <= bytes.count else { return nil }
            let value = (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
            return bigEndian ? value.byteSwapped : value
        }
    }
}
