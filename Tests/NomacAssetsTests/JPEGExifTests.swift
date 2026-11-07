import NomacCore
import Testing
@testable import NomacAssets

/// The Exif segments actool stores, as `assets-experiments jpeg-exif` observed them.
@Suite struct JPEGExifTests {
    static func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] {
        [0xFF, marker, UInt8((body.count + 2) >> 8), UInt8((body.count + 2) & 0xFF)] + body
    }

    static let frame = segment(0xC0, [8, 0, 30, 0, 40, 1, 1, 0x11, 0]) + segment(0xDA, [1, 1, 0, 0, 0x3F, 0]) + [0x12, 0x34, 0xFF, 0xD9]
    static let header = Array("MM".utf8) + [0, 42, 0, 0, 0, 8]
    static let orientation6: [UInt8] = [0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0]

    static func file(_ tiffs: [UInt8]..., xmp: String? = nil) -> [UInt8] {
        [0xFF, 0xD8] + tiffs.flatMap { segment(0xE1, Array("Exif\0\0".utf8) + $0) }
            + (xmp.map { segment(0xE1, Array("http://ns.adobe.com/xap/1.0/\0\($0)".utf8)) } ?? []) + frame
    }

    /// The TIFF actool stores for a file, nil without an Exif segment.
    static func stored(_ bytes: [UInt8]) throws -> [UInt8]? {
        let stored = try JPEGFile(bytes, path: "a.jpg").stored
        guard stored.count > 10, stored[2] == 0xFF, stored[3] == 0xE1 else { return nil }
        let length = Int(stored[4]) << 8 | Int(stored[5])
        return Array(stored[12..<(4 + length)])
    }

    @Test func littleEndianIsWrittenBigEndian() throws {
        let tiff = Array("II".utf8) + [42, 0, 8, 0, 0, 0, 1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0]
        #expect(try Self.stored(Self.file(tiff)) == Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 0])
    }

    @Test func tagsAreSortedAndOutOfLineValuesFollowInThatOrder() throws {
        let input = Self.header + [0, 4, 0x01, 0x28, 0, 3, 0, 0, 0, 1, 0, 2, 0, 0, 0x01, 0x1B, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0x3E, 0x01, 0x1A, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0x46]
            + Self.orientation6 + [0, 0, 0, 0, 0, 0, 0, 0x48, 0, 0, 0, 1, 0, 0, 0, 0x48, 0, 0, 0, 1]
        let expected = Self.header + [0, 4] + Self.orientation6 + [0x01, 0x1A, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0x3E, 0x01, 0x1B, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0x46, 0x01, 0x28, 0, 3, 0, 0, 0, 1, 0, 2, 0, 0]
            + [0, 0, 0, 0, 0, 0, 0, 0x48, 0, 0, 0, 1, 0, 0, 0, 0x48, 0, 0, 0, 1]
        #expect(try Self.stored(Self.file(input)) == expected)
    }

    @Test func tagsImageIODoesNotReadAreGone() throws {
        let kept = Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 0]
        for extra: [UInt8] in [[0x99, 0x99, 0, 3, 0, 0, 0, 1, 0, 7, 0, 0], [0x02, 0x13, 0, 3, 0, 0, 0, 1, 0, 1, 0, 0], [0x01, 0x1A, 0, 99, 0, 0, 0, 1, 1, 2, 3, 4]] {
            #expect(try Self.stored(Self.file(Self.header + [0, 2] + Self.orientation6 + extra + [0, 0, 0, 0])) == kept)
        }
    }

    @Test func orientationsOutOfRangeAreOneAndLongOnesAreGone() throws {
        for value: UInt8 in [0, 9] {
            let tiff = Self.header + [0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, value, 0, 0, 0, 0, 0, 0]
            #expect(try Self.stored(Self.file(tiff)) == Self.header + [0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0])
        }
        #expect(try Self.stored(Self.file(Self.header + [0, 1, 0x01, 0x12, 0, 4, 0, 0, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0])) == nil)
    }

    /// Software, on its own: no segment. An artist, a date and a description go the same way.
    @Test func softwareAloneLeavesNothing() throws {
        let software = Self.header + [0, 1, 0x01, 0x31, 0, 2, 0, 0, 0, 3, 0x73, 0x77, 0, 0, 0, 0, 0, 0]
        #expect(try Self.stored(Self.file(software)) == nil)
    }

    @Test func malformedSegmentsAreLeftOut() throws {
        let malformed: [[UInt8]] = [[], [0x4D], Array("XX".utf8) + [0, 42, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0], Array("MM".utf8) + [0, 43, 0, 0, 0, 8, 0, 1] + Self.orientation6 + [0, 0, 0, 0],
                                    Array("MM".utf8) + [0, 42, 0, 0, 0xFF, 0xFF], Self.header + [0xFF, 0xFF] + Self.orientation6 + [0, 0, 0, 0]]
        for tiff in malformed { #expect(try Self.stored(Self.file(tiff)) == nil) }
        #expect(try Self.stored(Self.file(Self.header + [0, 1] + Self.orientation6)) == Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 0])
    }

    @Test func onlyTheFirstExifSegmentCounts() throws {
        let three = Self.header + [0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 3, 0, 0, 0, 0, 0, 0]
        let six = Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 0]
        #expect(try Self.stored(Self.file(three, six)) == three)
        #expect(try Self.stored(Self.file(Self.header + [0, 0, 0, 0, 0, 0], three)) == nil)
    }

    /// 4400 random rationals came out so; these are the ones a plain continued fraction misses.
    @Test func rationalsAreWrittenFromTheirDouble() {
        func fraction(_ a: Int, _ b: Int, limit: Int = 0xFFFF_FFFF) -> [Int] {
            let (p, q) = JPEGMetadata.fraction(Double(a) / Double(b), limit: limit)
            return [p, q]
        }
        #expect(fraction(720000, 10000) == [72, 1])
        #expect(fraction(4643856, 1000000) == [274633, 59139])
        #expect(fraction(276135, 141755) == [44893, 23046])
        #expect(fraction(3276, 10000000) == [491, 1498779])
        #expect(fraction(1, 1000000000) == [1, 999999999])
        #expect(fraction(0xFFFF_FFFF, 3) == [0x5555_5555, 1])
        #expect(fraction(0x8000_0000, 1, limit: 0x7FFF_FFFF) == [0x7FFF_FFFF, 1])
    }

    /// A thumbnail's directory is new: compression 6, the first directory's orientation, and the
    /// offset and length; the input's own orientation of 3 and its unknown tag are gone.
    @Test func thumbnailDirectoryIsWrittenAgain() throws {
        let input = Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 26]
            + [0, 4, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 3, 0, 0, 0x99, 0x99, 0, 3, 0, 0, 0, 1, 0, 8, 0, 0, 0x02, 0x01, 0, 4, 0, 0, 0, 1, 0, 0, 0, 80, 0x02, 0x02, 0, 4, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 0, 0]
            + [0xFF, 0xD8, 0xFF, 0xD9]
        let expected = Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 26]
            + [0, 4, 0x01, 0x03, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0, 0x02, 0x01, 0, 4, 0, 0, 0, 1, 0, 0, 0, 80, 0x02, 0x02, 0, 4, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 0, 0]
            + [0xFF, 0xD8, 0xFF, 0xD9]
        #expect(try Self.stored(Self.file(input)) == expected)
    }

    @Test func aThumbnailWithoutAStartOfImageIsGone() throws {
        let input = Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 26]
            + [0, 2, 0x02, 0x01, 0, 4, 0, 0, 0, 1, 0, 0, 0, 56, 0x02, 0x02, 0, 4, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0] + [0x41, 0x42]
        #expect(try Self.stored(Self.file(input)) == Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 0])
    }

    /// A segment past what its length field holds is written with the length wrapped.
    @Test func anOverlongSegmentWrapsItsLength() throws {
        let thumbnail: [UInt8] = [0xFF, 0xD8] + [UInt8](repeating: 0, count: 65446)
        let input = Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 26]
            + [0, 2, 0x02, 0x01, 0, 4, 0, 0, 0, 1, 0, 0, 0, 56, 0x02, 0x02, 0, 4, 0, 0, 0, 1, 0, 0, 0xFF, 0xA8, 0, 0, 0, 0] + thumbnail
        let stored = try JPEGFile(Self.file(input), path: "a.jpg").stored
        #expect(Array(stored[2..<6]) == [0xFF, 0xE1, 0, 0])
    }

    /// XMP fills what the Exif segment lacks; an Exif value stays.
    @Test func xmpDatesFillMissingTags() throws {
        let exif = Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 0]
        let date = Array("2021:02:03 04:05:06\0".utf8)
        let filled = Self.header + [0, 2] + Self.orientation6 + [0x87, 0x69, 0, 4, 0, 0, 0, 1, 0, 0, 0, 38, 0, 0, 0, 0]
            + [0, 1, 0x90, 0x04, 0, 2, 0, 0, 0, 20, 0, 0, 0, 56, 0, 0, 0, 0] + date
        #expect(try Self.stored(Self.file(exif, xmp: #"<rdf:Description xmp:CreateDate="2021-02-03T04:05:06+02:00"/>"#)) == filled)
        #expect(try Self.stored(Self.file(exif, xmp: "<xmp:CreateDate>2021-02-03T04:05:06Z</xmp:CreateDate>")) == filled)
        #expect(try Self.stored(Self.file(exif, xmp: #"<rdf:Description xmp:CreateDate="2021-02-03T04:05"/>"#)) == exif)
    }

    @Test func whatImageIORewritesInAWayNotFoundYetStops() throws {
        let exif = Self.header + [0, 1] + Self.orientation6 + [0, 0, 0, 0]
        let iptc = Self.segment(0xED, Array("Photoshop 3.0\u{0}8BIM".utf8) + [0x04, 0x04, 0, 0, 0, 0, 0, 5, 0x1C, 2, 0x78, 0, 0, 0])
        #expect(throws: NomacError.self) { try JPEGFile([0xFF, 0xD8] + iptc + Self.frame, path: "a.jpg") }
        #expect(throws: NomacError.self) { try JPEGFile(Self.file(exif, xmp: #"<a tiff:Make="b"/>"#), path: "a.jpg") }
        let note = Array("Apple iOS\0\0\u{1}MM\0\0".utf8)
        let apple = Self.header + [0, 1, 0x87, 0x69, 0, 4, 0, 0, 0, 1, 0, 0, 0, 26, 0, 0, 0, 0, 0, 1, 0x92, 0x7C, 0, 7, 0, 0, 0, UInt8(note.count), 0, 0, 0, 44, 0, 0, 0, 0] + note
        #expect(throws: NomacError.self) { try JPEGFile(Self.file(apple), path: "a.jpg") }
    }

    /// An empty IPTC resource with its digest, and resources without XMP, are left out.
    @Test func photoshopSegmentsWithoutIPTCAreLeftOut() throws {
        let prefix = Array("Photoshop 3.0\u{0}8BIM".utf8)
        let empty = Self.segment(0xED, prefix + [0x04, 0x04, 0, 0, 0, 0, 0, 0])
        let resolution = Self.segment(0xED, prefix + [0x03, 0xED, 0, 0, 0, 0, 0, 2, 0, 72])
        #expect(try JPEGFile([0xFF, 0xD8] + empty + Self.frame, path: "a.jpg").stored == [0xFF, 0xD8] + Self.frame)
        #expect(try JPEGFile([0xFF, 0xD8] + resolution + Self.frame, path: "a.jpg").stored == [0xFF, 0xD8] + Self.frame)
    }
}
