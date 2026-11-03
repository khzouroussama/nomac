import Foundation

/// Self-authored Mach-O files for tests, laid out as the public header `<mach-o/loader.h>`
/// describes: no compiler or linker output.
public enum SyntheticMachO {
    /// A thin arm64 Mach-O file: `__PAGEZERO` (executables only), a 32 KB `__TEXT` segment with
    /// one `__text` section at 0x4000 (and `__info_plist` at 0x3000 holding `infoPlist`),
    /// `__LINKEDIT` holding `linkEditSize` bytes, `LC_UUID` (unless `uuid` is false) and an
    /// `LC_BUILD_VERSION` of `platform` (iOS unless given) with `minimumOS` (18.0 unless given).
    /// `fileType` replaces `MH_EXECUTE` (2) or `MH_DYLIB` (6); `cpuSubtype` 0x8000_0002 makes it
    /// arm64e; `arm64_32` makes it a 32-bit arm64_32 file (`mach_header`, `LC_SEGMENT`, a 16 KB
    /// `__PAGEZERO`).
    public static func machO(executable: Bool = true, fileType: UInt32? = nil, cpuSubtype: UInt32 = 0, arm64_32: Bool = false, uuid: Bool = true,
                             infoPlist: [UInt8]? = nil, platform: UInt32 = 2, minimumOS: UInt32 = 18 << 16, linkEditSize: Int = 0x100,
                             seed: UInt8 = 1) -> [UInt8] {
        var commands: [UInt8] = []
        var count: UInt32 = 0
        let base: UInt64 = executable ? (arm64_32 ? 0x4000 : 0x1_0000_0000) : 0
        func segment(_ name: String, vmAddress: UInt64, vmSize: UInt64, fileOffset: UInt64, fileSize: UInt64, protection: UInt32,
                     sections: [(name: String, address: UInt64, size: UInt64, offset: UInt32, flags: UInt32)] = []) -> [UInt8] {
            arm64_32 ? segment32(name, vmAddress: vmAddress, vmSize: vmSize, fileOffset: fileOffset, fileSize: fileSize, protection: protection,
                                 sections: sections)
                : segment64(name, vmAddress: vmAddress, vmSize: vmSize, fileOffset: fileOffset, fileSize: fileSize, protection: protection,
                            sections: sections)
        }
        if executable {
            commands += segment("__PAGEZERO", vmAddress: 0, vmSize: base, fileOffset: 0, fileSize: 0, protection: 0)
            count += 1
        }
        var textSections = [(name: "__text", address: base + 0x4000, size: UInt64(0x4000), offset: UInt32(0x4000), flags: UInt32(0x8000_0400))]
        if let infoPlist {
            textSections.insert((name: "__info_plist", address: base + 0x3000, size: UInt64(infoPlist.count), offset: 0x3000, flags: 0), at: 0)
        }
        commands += segment("__TEXT", vmAddress: base, vmSize: 0x8000, fileOffset: 0, fileSize: 0x8000, protection: 5, sections: textSections)
        commands += segment("__LINKEDIT", vmAddress: base + 0x8000, vmSize: 0x4000, fileOffset: 0x8000,
                            fileSize: UInt64(linkEditSize), protection: 1)
        if uuid {
            commands += words([0x1b, 24]) + (0..<16).map { UInt8($0) &* 17 &+ seed }
            count += 1
        }
        commands += words([0x32, 24, platform, minimumOS, 27 << 16, 0])
        count += 3
        var file = arm64_32
            ? words([0xfeed_face, 0x0200_000c, 1, fileType ?? (executable ? 2 : 6), count, UInt32(commands.count), 0x0020_0085])
            : words([0xfeed_facf, 0x0100_000c, cpuSubtype, fileType ?? (executable ? 2 : 6), count, UInt32(commands.count), 0x0020_0085, 0])
        file += commands
        if let infoPlist {
            file += [UInt8](repeating: 0, count: 0x3000 - file.count) + infoPlist
        }
        file += [UInt8](repeating: 0, count: 0x4000 - file.count)
        file += (0..<0x4000).map { UInt8(truncatingIfNeeded: $0 * 7 + Int(seed)) }
        file += (0..<linkEditSize).map { UInt8(truncatingIfNeeded: $0 * 13 + Int(seed)) }
        return file
    }

    private static func segment64(_ name: String, vmAddress: UInt64, vmSize: UInt64, fileOffset: UInt64, fileSize: UInt64, protection: UInt32,
                                  sections: [(name: String, address: UInt64, size: UInt64, offset: UInt32, flags: UInt32)]) -> [UInt8] {
        var bytes = words([0x19, UInt32(72 + 80 * sections.count)]) + padded(name)
        bytes += quads([vmAddress, vmSize, fileOffset, fileSize]) + words([protection, protection, UInt32(sections.count), 0])
        for section in sections {
            bytes += padded(section.name) + padded(name) + quads([section.address, section.size])
            bytes += words([section.offset, 2, 0, 0, section.flags, 0, 0, 0])
        }
        return bytes
    }

    private static func segment32(_ name: String, vmAddress: UInt64, vmSize: UInt64, fileOffset: UInt64, fileSize: UInt64, protection: UInt32,
                                  sections: [(name: String, address: UInt64, size: UInt64, offset: UInt32, flags: UInt32)]) -> [UInt8] {
        var bytes = words([0x1, UInt32(56 + 68 * sections.count)]) + padded(name)
        bytes += words([UInt32(vmAddress), UInt32(vmSize), UInt32(fileOffset), UInt32(fileSize), protection, protection, UInt32(sections.count), 0])
        for section in sections {
            bytes += padded(section.name) + padded(name) + words([UInt32(section.address), UInt32(section.size), section.offset, 2, 0, 0, section.flags, 0, 0])
        }
        return bytes
    }

    /// A universal file of `slices`, each at the next multiple of 16 KB (`align` 14), as lipo
    /// lays them out.
    public static func universal(_ slices: [[UInt8]]) -> [UInt8] {
        func bigEndian(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * (3 - UInt32($0)))) } }
        var offsets: [Int] = []
        var end = 8 + 20 * slices.count
        for slice in slices {
            let offset = (end + 0x3fff) / 0x4000 * 0x4000
            offsets.append(offset)
            end = offset + slice.count
        }
        var file = bigEndian(0xcafe_babe) + bigEndian(UInt32(slices.count))
        for (slice, offset) in zip(slices, offsets) {
            let cpuType = UInt32(slice[4]) | UInt32(slice[5]) << 8 | UInt32(slice[6]) << 16 | UInt32(slice[7]) << 24
            let cpuSubtype = UInt32(slice[8]) | UInt32(slice[9]) << 8 | UInt32(slice[10]) << 16 | UInt32(slice[11]) << 24
            file += [cpuType, cpuSubtype, UInt32(offset), UInt32(slice.count), 14].flatMap(bigEndian)
        }
        for (slice, offset) in zip(slices, offsets) {
            file += [UInt8](repeating: 0, count: offset - file.count) + slice
        }
        return file
    }

    /// A 16-byte segment or section name.
    public static func padded(_ name: String) -> [UInt8] {
        Array(name.utf8) + [UInt8](repeating: 0, count: 16 - name.utf8.count)
    }

    /// Little-endian 32-bit words.
    public static func words(_ values: [UInt32]) -> [UInt8] {
        values.flatMap { value in (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) } }
    }

    /// Little-endian 64-bit words.
    public static func quads(_ values: [UInt64]) -> [UInt8] {
        values.flatMap { value in (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) } }
    }
}
