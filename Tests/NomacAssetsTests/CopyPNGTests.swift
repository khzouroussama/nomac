import Foundation
import NomacCore
import Testing
@testable import NomacAssets

/// Xcode's copypng as `assets-experiments copypng` observed it.
@Suite struct CopyPNGTests {
    /// A 20 × 12 gray PNG (252 bytes of rows) with a text chunk.
    static let gray: [UInt8] = {
        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
            IconPNG.bigEndian(UInt32(data.count)) + Array(type.utf8) + data + IconPNG.bigEndian(crc32(Array(type.utf8) + data))
        }
        var rows: [UInt8] = []
        for y in 0..<12 { rows += [0] + (0..<20).map { UInt8(($0 * 12 + y) % 256) } }
        let header: [UInt8] = IconPNG.bigEndian(20) + IconPNG.bigEndian(12) + [8, 0, 0, 0, 0]
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", header)
        png += chunk("tEXt", Array("Software\0me".utf8))
        png += chunk("IDAT", try! IconPNG.deflate([rows], windowBits: 15)[0])
        return png + chunk("IEND", [])
    }()

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        bytes.reduce(UInt32.max) { crc, byte in
            (0..<8).reduce(crc ^ UInt32(byte)) { value, _ in value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        } ^ UInt32.max
    }

    @Test func grayPNGsNameTheSmallestWindowHoldingTheRows() throws {
        let out = try #require(try CopyPNG.compressed(Self.gray, stripText: true, path: "/g.png"))
        let idat = try #require(out.indices.first { Array(out[$0..<$0 + 4]) == Array("IDAT".utf8) })
        #expect(Array(out[idat + 4..<idat + 6]) == [0x08, 0xD7])
        #expect(!String(decoding: out, as: UTF8.self).contains("tEXt"))
        #expect(String(decoding: try #require(try CopyPNG.compressed(Self.gray, stripText: false, path: "/g.png")), as: UTF8.self).contains("tEXt"))
    }
}
