import Foundation
import NomacCore

/// A Mach-O file as codesign takes it: thin, or universal, a big-endian `fat_header` and
/// 20-byte `fat_arch` entries (`cputype`, `cpusubtype`, `offset`, `size`, `align`) followed
/// by thin files (the public header `<mach-o/fat.h>`).
struct MachOContainer {
    struct Slice {
        var image: MachOImage
        let alignment: UInt32
    }

    var slices: [Slice]
    let isUniversal: Bool

    /// Whether `bytes` start as a thin (`MH_MAGIC`, `MH_MAGIC_64`, little-endian) or universal
    /// Mach-O file; codesign signs anything else as generic.
    static func isMachO(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 4 else { return false }
        let little = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        return little == 0xfeed_face || little == 0xfeed_facf || bigEndian(bytes, 0) == 0xcafe_babe
    }

    init(bytes: [UInt8], path: String) throws {
        guard bytes.count >= 8, Self.bigEndian(bytes, 0) == 0xcafe_babe else {
            slices = [Slice(image: try MachOImage(bytes: bytes, path: path), alignment: 0)]
            isUniversal = false
            return
        }
        let count = Int(Self.bigEndian(bytes, 4))
        guard count > 0, 8 + 20 * count <= bytes.count else { throw NomacError("malformed universal file", path: path) }
        slices = try (0..<count).map { index in
            let entry = 8 + 20 * index
            let offset = Int(Self.bigEndian(bytes, entry + 8)), size = Int(Self.bigEndian(bytes, entry + 12))
            guard offset + size <= bytes.count else { throw NomacError("malformed universal file", path: path) }
            let image = try MachOImage(bytes: Array(bytes[offset..<(offset + size)]), path: path)
            // codesign writes ARM slices aligned to 16 KB, whatever the file had (observed: an
            // arm64 slice aligned to 2^15 by lipo comes back with 2^14).
            let alignment = [0x0100_000c, 0x0200_000c].contains(image.cpuType) ? 14 : Self.bigEndian(bytes, entry + 16)
            return Slice(image: image, alignment: alignment)
        }
        isUniversal = true
    }

    /// The slice codesign reads a universal file's identity from (on an Apple silicon Mac,
    /// observed): arm64e when there is one, else arm64 (also after an arm64_32 slice), else the
    /// first.
    var mainIndex: Int {
        slices.firstIndex { $0.image.architectureName == "arm64e" } ?? slices.firstIndex { $0.image.architectureName == "arm64" } ?? 0
    }

    /// How codesign names the file in its messages: `Mach-O thin (arm64)`, or for universal files
    /// `Mach-O universal (arm64e arm64)`, the main architecture first (observed with both
    /// orders of the slices).
    var formatDescription: String {
        guard isUniversal else { return "Mach-O thin (\(slices[0].image.architectureName))" }
        let names = [slices[mainIndex]] + slices.enumerated().filter { $0.offset != mainIndex }.map(\.element)
        return "Mach-O universal (\(names.map(\.image.architectureName).joined(separator: " ")))"
    }

    /// The file: a thin file's bytes, or the universal header with each slice at the next
    /// multiple of its alignment after the previous one (the first after the header), and
    /// zeros between them (observed: offsets 16384 and 65536 kept for slices that grew).
    var bytes: [UInt8] {
        guard isUniversal else { return slices[0].image.bytes }
        var header = Self.bigEndianBytes(0xcafe_babe) + Self.bigEndianBytes(UInt32(slices.count))
        var layout: [Int] = []
        var end = 8 + 20 * slices.count
        for slice in slices {
            let offset = MachOImage.roundUp(end, 1 << Int(slice.alignment))
            layout.append(offset)
            end = offset + slice.image.bytes.count
        }
        for (slice, offset) in zip(slices, layout) {
            header += [slice.image.cpuType, slice.image.cpuSubtype, UInt32(offset), UInt32(slice.image.bytes.count), slice.alignment]
                .flatMap(Self.bigEndianBytes)
        }
        var result = header
        for (slice, offset) in zip(slices, layout) {
            result += [UInt8](repeating: 0, count: offset - result.count) + slice.image.bytes
        }
        return result
    }

    private static func bigEndian(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 << 8 | UInt32(bytes[offset + $1]) }
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * (3 - UInt32($0)))) }
    }
}
