import Testing
@testable import NomacAssets

/// The JPEGs of actool's `jpeg-lzfse` payloads as `assets-experiments heic` showed them.
@Suite struct JPEGEncoderTests {
    static func segments(_ jpeg: [UInt8]) -> [(marker: UInt8, data: [UInt8])] {
        var out: [(marker: UInt8, data: [UInt8])] = [], at = 2
        while jpeg[at + 1] != 0xDA {
            let length = Int(jpeg[at + 2]) << 8 | Int(jpeg[at + 3])
            out.append((jpeg[at + 1], Array(jpeg[at + 4..<at + 2 + length])))
            at += 2 + length
        }
        return out
    }

    /// JFIF, Exif, Photoshop, the frame, four Huffman tables, two quantization tables, a restart
    /// interval of one row of blocks; the Exif segment ends with the pixel size.
    @Test func headerHoldsTheSegmentsInActoolsOrder() {
        let segments = Self.segments(JPEGEncoder.header(width: 300, height: 200))
        #expect(segments.map(\.marker) == [0xE0, 0xE1, 0xED, 0xC0, 0xC4, 0xC4, 0xC4, 0xC4, 0xDB, 0xDB, 0xDD])
        #expect(segments.map(\.data.count) == [14, 74, 54, 15, 29, 179, 29, 179, 65, 65, 2])
        #expect(segments[3].data == [8, 0, 200, 1, 44, 3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1])
        #expect(segments[10].data == [0, 38])
        #expect(Array(segments[1].data.suffix(28)) == [0xA0, 2, 0, 4, 0, 0, 0, 1, 0, 0, 1, 0x2C, 0xA0, 3, 0, 4, 0, 0, 0, 1, 0, 0, 0, 0xC8, 0, 0, 0, 0])
    }

    /// The colors survive within the quantization's error, across partial blocks and restarts.
    @Test func decodedColorsStayClose() throws {
        let width = 21, height = 19
        let rgb = (0..<width * height).flatMap { index -> [UInt8] in
            let x = index % width, y = index / width
            return [UInt8(x * 12), UInt8(y * 13), 120]
        }
        let decoded = try JPEGDecoder.decode(JPEGEncoder.encode(rgb: rgb, width: width, height: height), path: "a.jpg")
        #expect(decoded.width == width && decoded.height == height && decoded.components == 3)
        #expect(zip(rgb, decoded.pixels).allSatisfy { abs(Int($0) - Int($1)) <= 6 })
    }
}

/// `CELM` compression 5 as actool writes it for HEIC images with alpha.
@Suite struct JPEGLZFSEPayloadTests {
    /// Two zero words, the alpha stream's length, the width, the JPEG's length, the alpha stream,
    /// the JPEG; the length after the header counts all of them.
    @Test func payloadNamesItsParts() {
        let width = 24, height = 10
        let pixels = (0..<width * height).flatMap { index -> [UInt8] in [60, 30, 10, index % width < 12 ? 255 : 128] }
        let payload = ImageSet.jpegLZFSEPayload(PNGImage(width: width, height: height, pixels: pixels))
        func word(_ at: Int) -> Int { (0..<4).reduce(0) { $0 | Int(payload[at + $1]) << (8 * $1) } }
        #expect(Array(payload[0..<4]) == Array("MLEC".utf8) && word(4) == 0 && word(8) == 5)
        #expect(word(16) == 0 && word(20) == 0 && word(28) == width)
        let alpha = word(24), jpeg = word(32)
        #expect(word(12) == 20 + alpha + jpeg && payload.count == 36 + alpha + jpeg)
        #expect(Array(payload[36 + alpha..<38 + alpha]) == [0xFF, 0xD8] && Array(payload.suffix(2)) == [0xFF, 0xD9])
    }
}
