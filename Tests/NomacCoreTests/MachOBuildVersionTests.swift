import Foundation
import Testing
@testable import NomacCore

@Suite struct MachOBuildVersionTests {
    /// A 64-bit slice with one `LC_BUILD_VERSION`, laid out as `<mach-o/loader.h>` describes.
    static func slice(platform: UInt32, minos: UInt32, magic: UInt32 = 0xfeed_facf, extraCommand: Bool = false) -> [UInt8] {
        var commands: [UInt32] = []
        if extraCommand { commands += [0x19, 16, 0, 0] } // an unrelated 16-byte command
        commands += [0x32, 24, platform, minos, 27 << 16, 0]
        let header: [UInt32] = [magic, 0x0100_000c, 0, 6, UInt32(extraCommand ? 2 : 1), UInt32(commands.count * 4), 0] + (magic == 0xfeed_facf ? [0] : [])
        return (header + commands).flatMap(littleEndian)
    }

    static func littleEndian(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xff) } }
    static func bigEndian(_ value: UInt32) -> [UInt8] { littleEndian(value).reversed() }

    /// A universal file holding `slices` at 4096-byte offsets.
    static func universal(_ slices: [[UInt8]]) -> [UInt8] {
        var bytes = bigEndian(0xcafe_babe) + bigEndian(UInt32(slices.count))
        for (index, slice) in slices.enumerated() {
            bytes += [0x0100_000c, 0, UInt32(4096 * (index + 1)), UInt32(slice.count), 12].flatMap(bigEndian)
        }
        for (index, slice) in slices.enumerated() {
            bytes += [UInt8](repeating: 0, count: 4096 * (index + 1) - bytes.count) + slice
        }
        return bytes
    }

    @Test func readsAThinFile() {
        let entries = MachOBuildVersion.entries(in: Self.slice(platform: 2, minos: 17 << 16, extraCommand: true))
        #expect(entries == [MachOBuildVersion.Entry(platform: 2, minimumOS: "17.0")])
    }

    @Test func readsEverySliceOfAUniversalFile() {
        let file = Self.universal([
            Self.slice(platform: 1, minos: 14 << 16 | 2 << 8),
            Self.slice(platform: 6, minos: 17 << 16 | 1 << 8 | 3),
        ])
        #expect(MachOBuildVersion.entries(in: file) == [
            MachOBuildVersion.Entry(platform: 1, minimumOS: "14.2"),
            MachOBuildVersion.Entry(platform: 6, minimumOS: "17.1.3"),
        ])
    }

    @Test func reads32BitSlices() {
        #expect(MachOBuildVersion.entries(in: Self.slice(platform: 4, minos: 10 << 16, magic: 0xfeed_face)) == [
            MachOBuildVersion.Entry(platform: 4, minimumOS: "10.0"),
        ])
    }

    @Test func ignoresOtherFilesAndTruncation() {
        #expect(MachOBuildVersion.entries(in: Array("not a binary".utf8)).isEmpty)
        #expect(MachOBuildVersion.entries(in: Array(Self.slice(platform: 2, minos: 17 << 16).prefix(40))).isEmpty)
    }
}
