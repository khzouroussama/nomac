import NomacLZFSE
import Testing

/// The decoder on what the encoders write (LZVN below 4,096 bytes, LZFSE v2 blocks above, several
/// blocks and libcompression's windows), and on blocks no encoder here writes.
@Suite struct LZFSEDecoderTests {
    @Test(arguments: LZFSETests.references.indices)
    func decodesWhatTheEncodersWrite(_ index: Int) throws {
        let input = LZFSETests.references[index].input()
        #expect(try LZFSE.decode(LZFSE.encode(input)) == input, "\(LZFSETests.references[index].name)")
        #expect(try LZFSE.decode(LZFSE.encode(input, encoder: .libcompression)) == input, "\(LZFSETests.references[index].name)")
    }

    @Test(arguments: LZFSEStreamTests.references.indices)
    func decodesLibcompressionsStreams(_ index: Int) throws {
        let input = LZFSEStreamTests.references[index].input()
        #expect(try LZFSE.decode(LZFSE.encodeStream(input)) == input, "\(LZFSEStreamTests.references[index].name)")
    }

    @Test func decodesUncompressedBlocks() throws {
        let block = Array("bvx-".utf8) + [3, 0, 0, 0] + Array("abc".utf8)
        #expect(try LZFSE.decode(block + block + Array("bvx$".utf8)) == Array("abcabc".utf8))
    }

    @Test func refusesMalformedStreams() {
        let encoded = LZFSE.encode(Inputs.text(10_000, seed: 1))
        #expect(throws: LZFSE.DecodingError.self) { try LZFSE.decode(Array(encoded.dropLast(4))) }
        #expect(throws: LZFSE.DecodingError.self) { try LZFSE.decode(Array(encoded.prefix(40))) }
        #expect(throws: LZFSE.DecodingError.self) { try LZFSE.decode(Array("bvx1".utf8) + [UInt8](repeating: 0, count: 40)) }
        #expect(throws: LZFSE.DecodingError.self) { try LZFSE.decode(Array("bvxn".utf8) + [4, 0, 0, 0, 1, 0, 0, 0, 0x70]) }
    }
}
