import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Sprite atlases, atlas numbering and `BITMAPKEYS` splits as `assets-experiments sprites`
/// and `bitmap-order` observed them.
@Suite struct SpriteAtlasTests {
    /// `sprites` trim: a 40 × 30 image red inside (3, 5)–(35, 27) and a 20 × 20 red one.
    @Test func trimmedSpritesGiveActoolsCar() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        let info = ["author": "xcode", "version": 1] as [String: Any]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: ["info": info]), to: catalog + "/S.spriteatlas/Contents.json")
        for (name, width, height, box) in [("a", 40, 30, (3, 5, 35, 27)), ("b", 20, 20, (0, 0, 20, 20))] {
            let rows: [[UInt8]] = (0..<height).map { y in
                (0..<width).flatMap { x -> [UInt8] in box.0 <= x && x < box.2 && box.1 <= y && y < box.3 ? [200, 30, 60, 255] : [0, 0, 0, 0] }
            }
            let folder = catalog + "/S.spriteatlas/\(name).imageset"
            try FileSystem.write(Data(ImageSetTests.png(width: width, height: height, colorType: 6, rows: rows)), to: folder + "/\(name).png")
            let entry = ["filename": "\(name).png", "idiom": "universal", "scale": "1x"]
            try FileSystem.write(try JSONSerialization.data(withJSONObject: ["images": [entry], "info": info]), to: folder + "/Contents.json")
        }
        _ = try ColorCatalogTests.compile(catalog, in: temporary.path + "/out")
        #expect(ColorCatalogTests.hex(SHA256.digest(try ColorCatalogTests.car(temporary.path + "/out"))) == "52fcd0751ac392b017ec597f501cd92f06c4204818b48061a0083396a82c15cf")
    }

    /// A full leaf takes the 127th entry, keeps 64 and moves 63 to a new leaf created after
    /// that entry's value, then a new root.
    @Test func bitmapKeysSplitAsActoolInsertsThem() throws {
        var store = BOMStoreWriter()
        var tree = BOMNumberTree(in: &store, blockSize: 1024)
        let leaf = tree.root
        for key in 1...127 {
            try tree.insert(key: UInt32(key), value: store.add([0]), in: &store)
        }
        let right = leaf + 128, root = leaf + 129
        #expect(tree.root == root)
        #expect(tree.nodes[root]?.keys == [64] && tree.nodes[root]?.blocks == [leaf, right])
        #expect(tree.nodes[leaf]?.keys == Array(1...64).map(UInt32.init) && tree.nodes[leaf]?.forward == right)
        #expect(tree.nodes[right]?.keys == Array(65...127).map(UInt32.init) && tree.nodes[right]?.backward == leaf)
    }

    /// 24 images of 190 × 49 pixels make 12 atlases of two, numbered 0, 1, 10, 11, 2, ..., 9 in
    /// packing order (`sprites` atlases-12).
    @Test func atlasesAreNumberedByTheirIndicesAsStrings() throws {
        let sources = (0..<24).map { n in
            ImageSet.Source(name: "i\(n)", filename: "i\(n).png", path: "/i\(n).png",
                            image: PNGImage(width: 190, height: 49, pixels: [UInt8(n), 10, 200, 255].repeated(190 * 49)))
        }
        let identifiers = RenditionIdentifier.assign(sources.map(\.name))
        let renditions = try ImageSet.renditions(sources, identifiers: identifiers)
        let order = sources.sorted { identifiers[$0.name]! < identifiers[$1.name]! }.map(\.name)
        let numbers = ["0", "1", "10", "11", "2", "3", "4", "5", "6", "7", "8", "9"].map { Int($0)! }
        for rendition in renditions where rendition.kind == .image {
            let link = try #require(Self.linkDimension1(rendition.csi))
            #expect(numbers[link] == order.firstIndex(of: rendition.name)! / 2)
        }
    }

    /// The `dim1` of the atlas a link rendition's property 1010 names (0 when absent).
    static func linkDimension1(_ csi: [UInt8]) -> Int? {
        func u32(_ o: Int) -> Int { Int(csi[o]) | Int(csi[o + 1]) << 8 | Int(csi[o + 2]) << 16 | Int(csi[o + 3]) << 24 }
        var offset = 184
        while offset < 184 + u32(168) {
            let type = u32(offset), length = u32(offset + 4)
            if type == 1010 {
                let key = offset + 8 + 30, count = (Int(csi[offset + 8 + 26]) | Int(csi[offset + 8 + 27]) << 8) / 4
                for pair in 0..<count where Int(csi[key + 4 * pair]) | Int(csi[key + 4 * pair + 1]) << 8 == 8 {
                    return Int(csi[key + 4 * pair + 2]) | Int(csi[key + 4 * pair + 3]) << 8
                }
                return 0
            }
            offset += 8 + length
        }
        return nil
    }

    /// Mode 3 stores chunks of as many rows as fit in 2 MiB: 523 of 1,001 pixels.
    @Test func modeThreeChunksHoldUpTo2MiBOfRows() {
        let pixels = [UInt8](repeating: 7, count: 1_001 * 600 * 4)
        let blob = Deepmap2.lzCompressed(pixels, format: .bgra, width: 1_001, height: 600)
        #expect(Int(blob[10]) | Int(blob[11]) << 8 == 523)
    }
}

extension Array {
    fileprivate func repeated(_ count: Int) -> [Element] {
        Array([[Element]](repeating: self, count: count).joined())
    }
}
