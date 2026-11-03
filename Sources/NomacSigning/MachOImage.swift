import Foundation
import NomacCore

/// A thin Mach-O file, 64-bit or 32-bit (arm64_32), with the parts code signing reads and
/// changes (a universal file's slices are each one, ``MachOContainer``).
///
/// Layouts from the public header `<mach-o/loader.h>`: a little-endian `mach_header_64`
/// (32 bytes) or `mach_header` (28 bytes), then `ncmds` load commands filling `sizeofcmds`
/// bytes. `segment_command_64` (`LC_SEGMENT_64`, 0x19) holds the segment name at 8, `vmaddr`,
/// `vmsize`, `fileoff` and `filesize` at 24, 32, 40 and 48, its 80-byte sections from 72;
/// `segment_command` (`LC_SEGMENT`, 0x1) the same as 32-bit fields at 24, 28, 32 and 36, its
/// 68-byte sections from 56; `linkedit_data_command` (`LC_CODE_SIGNATURE`, 0x1d) holds
/// `dataoff` and `datasize` at 8 and 12; `uuid_command` (`LC_UUID`, 0x1b) the UUID at 8.
struct MachOImage {
    static let executeFileType: UInt32 = 2
    static let segmentCommand: UInt32 = 0x19
    static let segmentCommand32: UInt32 = 0x1
    static let uuidCommand: UInt32 = 0x1b
    static let codeSignatureCommand: UInt32 = 0x1d
    static let codeSignatureCommandSize = 16
    static let buildVersionCommand: UInt32 = 0x32

    /// The code page size codesign hashes this file with, as a power of two: 4 KB for iOS below
    /// 16.0 and watchOS below 9.0, 16 KB otherwise (observed: iOS 12.2 to 15.99 and watchOS 5.0
    /// to 8.99 give 4 KB pages, iOS 16.0 and 18.0 and watchOS 9.0 to 26.0 16 KB, arm64 and
    /// arm64_32 alike; other platforms are not observed yet).
    var pageSizeShift: UInt8 {
        guard let buildVersion else { return 14 }
        switch buildVersion.platform {
        case MachOBuildVersion.platformIOS: return buildVersion.minimumOS < 16 << 16 ? 12 : 14
        case MachOBuildVersion.platformWatchOS: return buildVersion.minimumOS < 9 << 16 ? 12 : 14
        default: return 14
        }
    }

    /// Whether codesign adds a SHA-1 code directory: for watchOS below 12.0 (observed: 11.99
    /// gets SHA-1 and SHA-256, 12.0 SHA-256 only); a universal file gets it when any slice does.
    var needsSHA1CodeDirectory: Bool {
        buildVersion.map { $0.platform == MachOBuildVersion.platformWatchOS && $0.minimumOS < 12 << 16 } ?? false
    }

    struct Segment {
        var commandOffset: Int
        var is64Bit: Bool
        var fileOffset: UInt64
        var fileSize: UInt64
        var vmSize: UInt64
    }

    var bytes: [UInt8]
    let is64Bit: Bool
    /// 32 for `mach_header_64`, 28 for `mach_header`.
    var headerSize: Int { is64Bit ? 32 : 28 }
    let fileType: UInt32
    let cpuType: UInt32
    let cpuSubtype: UInt32
    var commandCount: Int
    var commandsSize: Int
    let text: Segment
    var linkEdit: Segment
    var codeSignatureCommandOffset: Int?
    let uuid: [UInt8]?
    /// The contents of `__TEXT,__info_plist`, an Info.plist linked into the file.
    let infoPlist: [UInt8]?
    /// `LC_BUILD_VERSION`'s platform and minimum OS version (`xxxx.yy.zz` in nibbles).
    let buildVersion: (platform: UInt32, minimumOS: UInt32)?
    /// The file offset of the first section's contents: load commands must end before it.
    let firstSectionOffset: Int

    init(bytes: [UInt8], path: String) throws {
        guard bytes.count >= 28, [0xfeed_facf, 0xfeed_face].contains(Self.uint32(bytes, 0)) else {
            throw NomacError("not a Mach-O file", path: path)
        }
        self.bytes = bytes
        is64Bit = Self.uint32(bytes, 0) == 0xfeed_facf
        cpuType = Self.uint32(bytes, 4)
        cpuSubtype = Self.uint32(bytes, 8)
        fileType = Self.uint32(bytes, 12)
        commandCount = Int(Self.uint32(bytes, 16))
        commandsSize = Int(Self.uint32(bytes, 20))
        var text: Segment?
        var linkEdit: Segment?
        var signature: Int?
        var uuid: [UInt8]?
        var infoPlist: [UInt8]?
        var buildVersion: (platform: UInt32, minimumOS: UInt32)?
        var firstSection = bytes.count
        var offset = is64Bit ? 32 : 28
        for _ in 0..<commandCount {
            guard offset + 8 <= bytes.count else { throw NomacError("truncated load commands", path: path) }
            let command = Self.uint32(bytes, offset)
            let size = Int(Self.uint32(bytes, offset + 4))
            guard size >= 8, offset + size <= bytes.count else { throw NomacError("malformed load command", path: path) }
            switch command {
            case Self.segmentCommand, Self.segmentCommand32:
                let wide = command == Self.segmentCommand
                func field(_ index: Int) -> UInt64 {
                    wide ? Self.uint64(bytes, offset + 24 + 8 * index) : UInt64(Self.uint32(bytes, offset + 24 + 4 * index))
                }
                let name = String(decoding: bytes[(offset + 8)..<(offset + 24)].prefix { $0 != 0 }, as: UTF8.self)
                let segment = Segment(commandOffset: offset, is64Bit: wide, fileOffset: field(2), fileSize: field(3), vmSize: field(1))
                if name == "__TEXT" { text = segment }
                if name == "__LINKEDIT" { linkEdit = segment }
                let sectionCount = Int(Self.uint32(bytes, offset + (wide ? 64 : 48)))
                for section in 0..<sectionCount {
                    // section_64 (80 bytes, `size` at 40, `offset` at 48) or section (68 bytes,
                    // `size` at 36, `offset` at 40), each with its name at 0; `offset` is zero for
                    // zero-fill sections.
                    let start = wide ? offset + 72 + section * 80 : offset + 56 + section * 68
                    let sectionOffset = Int(Self.uint32(bytes, start + (wide ? 48 : 40)))
                    if sectionOffset > 0 { firstSection = min(firstSection, sectionOffset) }
                    let sectionName = String(decoding: bytes[start..<(start + 16)].prefix { $0 != 0 }, as: UTF8.self)
                    let size = wide ? Int(Self.uint64(bytes, start + 40)) : Int(Self.uint32(bytes, start + 36))
                    if name == "__TEXT", sectionName == "__info_plist", sectionOffset + size <= bytes.count {
                        infoPlist = Array(bytes[sectionOffset..<(sectionOffset + size)])
                    }
                }
            case Self.codeSignatureCommand:
                signature = offset
            case Self.uuidCommand:
                uuid = Array(bytes[(offset + 8)..<(offset + 24)])
            case Self.buildVersionCommand:
                buildVersion = (Self.uint32(bytes, offset + 8), Self.uint32(bytes, offset + 12))
            default:
                break
            }
            offset += size
        }
        guard let text, let linkEdit else { throw NomacError("no __TEXT or __LINKEDIT segment", path: path) }
        self.text = text
        self.linkEdit = linkEdit
        self.uuid = uuid
        self.infoPlist = infoPlist
        self.buildVersion = buildVersion
        codeSignatureCommandOffset = signature
        firstSectionOffset = firstSection
    }

    /// The `dataoff` and `datasize` of `LC_CODE_SIGNATURE`, if the file has one.
    var codeSignature: (offset: Int, size: Int)? {
        codeSignatureCommandOffset.map { (Int(Self.uint32(bytes, $0 + 8)), Int(Self.uint32(bytes, $0 + 12))) }
    }

    /// Where the signature goes: over the existing one, or after `__LINKEDIT` at the next
    /// 16-byte boundary (observed: a `__LINKEDIT` ending at 0x80b4 gets its signature at 0x80c0,
    /// zero-filled in between). The hashed code ends there.
    var signatureOffset: Int {
        codeSignature?.offset ?? Self.roundUp(Int(linkEdit.fileOffset + linkEdit.fileSize), 16)
    }

    /// Lays out a signature of `size` bytes at ``signatureOffset``: adds `LC_CODE_SIGNATURE` after
    /// the last load command when there is none, sets its `dataoff` and `datasize`, extends
    /// `__LINKEDIT` over it (its `vmsize` rounded up to 16 KB, the arm64 page size: 0x9f80 bytes
    /// observed as 0xc000) and truncates the file where the signature starts. Returns the bytes
    /// the file had in the `size` bytes from there, zeros past its end: codesign leaves them in
    /// the space its signature does not fill (observed re-signing a library signed by Apple).
    mutating func reserveSignature(size: Int) throws -> [UInt8] {
        let offset = signatureOffset
        if codeSignatureCommandOffset == nil {
            let commandOffset = headerSize + commandsSize
            guard commandOffset + Self.codeSignatureCommandSize <= firstSectionOffset else {
                throw NomacError("no room for LC_CODE_SIGNATURE in the load commands")
            }
            commandCount += 1
            commandsSize += Self.codeSignatureCommandSize
            Self.put32(&bytes, 16, UInt32(commandCount))
            Self.put32(&bytes, 20, UInt32(commandsSize))
            Self.put32(&bytes, commandOffset, Self.codeSignatureCommand)
            Self.put32(&bytes, commandOffset + 4, UInt32(Self.codeSignatureCommandSize))
            codeSignatureCommandOffset = commandOffset
        }
        let command = codeSignatureCommandOffset!
        Self.put32(&bytes, command + 8, UInt32(offset))
        Self.put32(&bytes, command + 12, UInt32(size))
        linkEdit.fileSize = UInt64(offset + size) - linkEdit.fileOffset
        linkEdit.vmSize = UInt64(Self.roundUp(Int(linkEdit.fileSize), 0x4000))
        if linkEdit.is64Bit {
            Self.put64(&bytes, linkEdit.commandOffset + 32, linkEdit.vmSize)
            Self.put64(&bytes, linkEdit.commandOffset + 48, linkEdit.fileSize)
        } else {
            Self.put32(&bytes, linkEdit.commandOffset + 28, UInt32(linkEdit.vmSize))
            Self.put32(&bytes, linkEdit.commandOffset + 36, UInt32(linkEdit.fileSize))
        }
        let previous = Array(bytes[min(offset, bytes.count)..<min(offset + size, bytes.count)])
        if bytes.count > offset {
            bytes.removeSubrange(offset...)
        } else {
            bytes += [UInt8](repeating: 0, count: offset - bytes.count)
        }
        return previous + [UInt8](repeating: 0, count: size - previous.count)
    }

    /// `architecture` as codesign names it in its messages.
    var architectureName: String {
        switch (cpuType, cpuSubtype & 0x00ff_ffff) {
        case (0x0100_000c, 2): return "arm64e"
        case (0x0100_000c, _): return "arm64"
        case (0x0200_000c, _): return "arm64_32"
        case (0x0100_0007, _): return "x86_64"
        default: return "unknown"
        }
    }

    static func roundUp(_ value: Int, _ alignment: Int) -> Int {
        (value + alignment - 1) / alignment * alignment
    }

    static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    static func uint64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        UInt64(uint32(bytes, offset)) | UInt64(uint32(bytes, offset + 4)) << 32
    }

    static func put32(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt32) {
        for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * UInt32(index))) }
    }

    static func put64(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt64) {
        put32(&bytes, offset, UInt32(truncatingIfNeeded: value))
        put32(&bytes, offset + 4, UInt32(truncatingIfNeeded: value >> 32))
    }
}
