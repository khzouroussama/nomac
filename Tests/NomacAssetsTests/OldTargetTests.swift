import Foundation
import NomacCore
import NomacLZFSE
import Testing
@testable import NomacAssets

/// Deployment targets before iOS 13 as `assets-experiments old-targets` observed them on
/// self-written images; the values are actool's, its files stay outside the repository.
@Suite struct ImageVariantsTests {
    static func bgra(_ width: Int, _ height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> [UInt8] {
        var out: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                out += [b, g, r, 255]
            }
        }
        return out
    }

    static func hex(_ text: String) -> [UInt8] {
        let digits = Array(text.utf8)
        return stride(from: 0, to: digits.count, by: 2).map { UInt8(String(decoding: digits[$0...$0 + 1], as: UTF8.self), radix: 16)! }
    }

    /// Bisected over every minor version from 3.0 to 13.0.
    @Test func erasOfDeploymentTargets() throws {
        #expect(try ImageVariants(iOSTarget: "13.0").variants.map(\.value) == [0])
        #expect(try ImageVariants(iOSTarget: "12.4").variants.map(\.value) == [0, 5])
        #expect(try ImageVariants(iOSTarget: "12.0").variants[0].encoding == .palette)
        #expect(try ImageVariants(iOSTarget: "11.4").variants.map(\.value) == [0, 3, 5])
        #expect(try ImageVariants(iOSTarget: "11.4").variants[0].encoding == .plain)
        #expect(try ImageVariants(iOSTarget: "9.3").attribute == .target)
        #expect(try ImageVariants(iOSTarget: "9.2").attribute == .legacyTarget)
        #expect(try ImageVariants(iOSTarget: "9.0").packs)
        #expect(try ImageVariants(iOSTarget: "9.3").refusesDirections && !ImageVariants(iOSTarget: "10.0").refusesDirections)
        let eight = try ImageVariants(iOSTarget: "8.4")
        #expect(!eight.packs && !eight.keepsGray && eight.iconEncoding == .plainLZVN && eight.attribute == .legacyTarget)
        #expect(throws: NomacError.self) { try ImageVariants(iOSTarget: "7.1") }
        #expect(ImageVariants.writesAllIconFiles(iOSTarget: "10.3") && !ImageVariants.writesAllIconFiles(iOSTarget: "11.0"))
    }

    /// Two colors, a bit per pixel; the free low bits of each row's last word keep the low bits of
    /// the index of the pixel numbered as the word (`0x8100` on odd rows, width 9).
    @Test func paletteImagePaddingBits() throws {
        let two = Self.bgra(9, 9) { x, y in ((x + y) % 2 == 0 ? 0 : 200, 20, 30) }
        let image = try #require(PaletteImagePayload.paletteImage(two, width: 9, height: 9))
        let head = Self.hex("0df0feca010000000200ff00141effc8141e")
        #expect(Array(image.prefix(head.count)) == head)
        #expect(Array(image[head.count..<head.count + 8]) == Self.hex("005581aa005581aa"))
        #expect(image.count == 36)
    }

    /// 2 × 2 and 3 × 3 images of 4 and 9 colors, 2 and 4 bits per pixel (`sm2x2`, `sm3x3`).
    @Test func paletteImageBitWidths() throws {
        let smooth: (Int, Int) -> (UInt8, UInt8, UInt8) = { x, y in (UInt8(2 * x + y), UInt8(2 * y + x), UInt8(x + y)) }
        #expect(PaletteImagePayload.paletteImage(Self.bgra(2, 2, smooth), width: 2, height: 2)
            == Self.hex("0df0feca010000000400ff000000ff020101ff010201ff030302001001b0"))
        #expect(PaletteImagePayload.paletteImage(Self.bgra(3, 3, smooth), width: 3, height: 3)
            == Self.hex("0df0feca010000000900ff000000ff020101ff040202ff010201ff030302ff050403ff020402ff040503ff060604200151348267"))
    }

    /// 1,024 colors are a palette image, 1,046 are not (`old-targets` 32 × 32, 33 × 33).
    @Test func paletteColorLimit() {
        let colors: (Int, Int) -> (UInt8, UInt8, UInt8) = { x, y in (UInt8(x), UInt8(y), 0) }
        #expect(PaletteImagePayload.paletteImage(Self.bgra(32, 32, colors), width: 32, height: 32) != nil)
        #expect(PaletteImagePayload.paletteImage(Self.bgra(33, 33, colors), width: 33, height: 33) == nil)
    }

    /// iOS 8's plain payload: rows without padding, four no-op bytes before libcompression's LZVN
    /// (`fl33x33`: 56 bytes), run lengths when smaller below 4,096 bytes (`fl4x4`: 36 bytes,
    /// `f2`: its 16 raw bytes stay).
    @Test func plainLZVN() {
        let flat = Self.bgra(33, 33) { _, _ in (10, 20, 30) }
        let payload = PlainImagePayload.lzvn(flat, width: 33, height: 33, opaque: true)
        #expect(Array(payload.prefix(16)) == Array("MLEC".utf8) + Self.hex("020000000300000038000000"))
        #expect(Array(payload[16..<28]) == Self.hex("0e16160ee41e140aff3804f0"))
        #expect(payload.count == 16 + 56)
        let small = PlainImagePayload.lzvn(Self.bgra(4, 4) { _, _ in (10, 20, 30) }, width: 4, height: 4, opaque: true)
        #expect(Array(small[8..<16]) == Self.hex("0100000024000000"))
        let two = PlainImagePayload.lzvn(Self.bgra(2, 2) { _, _ in (200, 9, 9) }, width: 2, height: 2, opaque: true)
        #expect(Array(two[8..<16]) == Self.hex("0000000010000000"))
    }

    /// `compression_stream`'s LZVN on generated pixels: four no-op bytes and the buffer encoder's
    /// choices with the last pending match emitted (lengths and FNV-1a digests of libcompression's
    /// output; 6,095 bytes against the buffer API's 6,089).
    @Test func lzvnStream() {
        func generated(_ count: Int) -> [UInt8] {
            var x: UInt32 = 1
            return (0..<count).map { index in
                x = x &* 1_103_515_245 &+ 12_345
                return index % 4 == 3 ? 255 : UInt8(x >> 16 & 0xFF)
            }
        }
        func fnv(_ bytes: [UInt8]) -> UInt64 {
            bytes.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
        }
        for (count, length, digest) in [(6_000, 6_095, UInt64(0xDB93_4210_3720_8FA7)), (10_000, 10_223, 0xD554_DDC9_7867_C606), (40_000, 41_925, 0x9316_F39C_CAF3_E722)] {
            let stream = LZVN.encodeStream(generated(count))
            #expect(stream.count == length)
            #expect(fnv(stream) == digest)
        }
        #expect(LZVN.encode(generated(6_000), encoder: .libcompression).count == 6_089)
    }

    /// Rows, filters, planes: a tile's chunk has 7 bytes per pixel and a byte per row, padded to 8
    /// bytes (54 × 54: 20,472; 400 × 64's tile of 256 columns: 179,304 from `dmap` streams).
    @Test func dmapChunkLengths() {
        let pixels = Self.bgra(54, 54) { x, y in (UInt8(x), UInt8(y), 7) }
        #expect(Deepmap2Planes.chunk(pixels, format: .bgra, width: 54, height: 54, alignment: 8).count == 20_472)
        let tile = Self.bgra(256, 100) { x, y in (UInt8(x), UInt8(y), 7) }
        #expect(Deepmap2Planes.chunk(tile, format: .bgra, width: 256, height: 100, alignment: 8).count == 179_304)
    }

    /// Bands from 20,480 bytes of rows before padding: 71 × 72 stays one blob, 65 × 79 has
    /// ⌊79 / 3⌋ rows and one more band.
    @Test func dmapBands() throws {
        let noisy: (Int, Int) -> (UInt8, UInt8, UInt8) = { x, y in (UInt8(truncatingIfNeeded: x * x + y), UInt8(truncatingIfNeeded: y * y + x), UInt8(truncatingIfNeeded: x * y)) }
        let whole = try PaletteImagePayload.payload(Self.bgra(71, 72, noisy), format: .bgra, width: 71, height: 72, opaque: true)
        #expect(Array(whole[4..<12]) == Self.hex("020000000a000000"))
        let banded = try PaletteImagePayload.payload(Self.bgra(65, 79, noisy), format: .bgra, width: 65, height: 79, opaque: true)
        #expect(Array(banded[4..<16]) == Self.hex("030000000a00000004000000"))
    }

    /// Three 24 × 24 2x images at 11.0: per variant an atlas and three links, the link naming the
    /// atlas with (25, value) after the scale; at 9.0 too, whose keys have attribute 5.
    @Test func variantsPackAlike() throws {
        for (target, attribute) in [("11.0", RenditionAttribute.target), ("9.0", RenditionAttribute.legacyTarget)] {
            let sources = (0..<3).map { index -> ImageSet.Source in
                let pixels = Self.bgra(24, 24) { x, y in (UInt8(x * 9), UInt8(y * 9), UInt8(index * 60)) }
                return ImageSet.Source(name: "S\(index)", filename: "s.png", path: "/s.png", image: PNGImage(width: 24, height: 24, pixels: pixels), scale: 2)
            }
            let identifiers = ["S0": 31303, "S1": 24965, "S2": 60902] as [String: UInt16]
            let renditions = try ImageSet.renditions(sources, identifiers: identifiers, variants: ImageVariants(iOSTarget: target))
            #expect(renditions.count == 12)
            #expect(renditions.filter { !$0.hasFacet }.map { $0.attributes[attribute] ?? 0 } == [0, 3, 5])
            #expect(renditions.filter { $0.attributes[attribute] == 3 }.count == 4)
            let tail = Self.hex("010009000200b5000c0002001900030000000000")
            let linked = renditions.filter { $0.hasFacet && $0.attributes[attribute] == 3 }
            #expect(linked.count == 3 && linked.allSatisfy { rendition in
                rendition.csi.windows(ofCount: tail.count).contains { Array($0) == tail }
            })
        }
    }
}

private extension Array where Element == UInt8 {
    func windows(ofCount count: Int) -> [ArraySlice<UInt8>] {
        guard self.count >= count else { return [] }
        return (0...self.count - count).map { self[$0..<$0 + count] }
    }
}
