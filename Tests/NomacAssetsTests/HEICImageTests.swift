import Foundation
import NomacCore
import Testing
@testable import NomacAssets

/// HEIC files as `assets-experiments heic` and the corpus's HEIC files showed actool storing them.
@Suite struct HEICImageTests {
    static func tags(_ exif: [UInt8]) -> [(tag: Int, value: [UInt8])] {
        let tiff = 4 + HEICImage.be32(exif, 0)
        let t = Array(exif[tiff...]), directory = HEICImage.be32(t, 4)
        return (0..<HEICImage.be16(t, directory)).map { index in
            let at = directory + 2 + 12 * index
            return (HEICImage.be16(t, at), Array(t[at + 8..<at + 12]))
        }
    }

    /// A new Exif item: Orientation 1, TileWidth and TileLength the image's size, big-endian.
    @Test func newExifNamesTheOrientationAndTheSize() throws {
        let exif = try HEICImage.rewrittenExif(nil, width: 40, height: 30, path: "a.heic")
        #expect(exif.count == 60 && Array(exif[0..<12]) == [0, 0, 0, 6] + Array("Exif".utf8) + [0, 0, 0x4D, 0x4D])
        #expect(Self.tags(exif).map(\.tag) == [0x112, 0x142, 0x143])
        #expect(Self.tags(exif).map(\.value) == [[0, 1, 0, 0], [0, 0, 0, 40], [0, 0, 0, 30]])
    }

    /// A file's Exif keeps its tags, out-of-line values moved after the new directory.
    @Test func rewrittenExifKeepsTheFilesTags() throws {
        let rational: [UInt8] = [0, 0, 0, 72, 0, 0, 0, 1]
        var tiff: [UInt8] = Array("MM".utf8) + [0, 42, 0, 0, 0, 8, 0, 2]
        tiff += [0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 1, 0, 0]
        tiff += [0x01, 0x1A, 0, 5, 0, 0, 0, 1, 0, 0, 0, 38]
        tiff += [0, 0, 0, 0] + rational
        let exif = try HEICImage.rewrittenExif([0, 0, 0, 6] + Array("Exif".utf8) + [0, 0] + tiff, width: 400, height: 400, path: "a.heic")
        let tags = Self.tags(exif)
        #expect(tags.map(\.tag) == [0x112, 0x11A, 0x142, 0x143])
        let offset = HEICImage.be32(tags[1].value, 0), start = 4 + HEICImage.be32(exif, 0)
        #expect(offset == 8 + 2 + 12 * 4 + 4 && Array(exif[start + offset..<start + offset + 8]) == rational)
    }

    /// Opaque pixels as 1-5-5-5 RGB, little-endian, the top bit clear.
    @Test func decodedPixelsTakeFiveBitsPerChannel() {
        #expect(HEICImage.rgb555([255, 0, 0, 255, 0, 0, 255, 255, 128, 128, 128, 255]) == [0x1F, 0x00, 0x00, 0x7C, 0x10, 0x42])
    }
}
