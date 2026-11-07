import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Tables past one BOM leaf as the `large-tables` experiment observed them: actool's stores, whole,
/// reproduced for 53 catalogs of 510 to 24,000 names (docs/formats/asset-catalog.md, "Trees").
@Suite struct LargeTableTests {
    private static func keyTree(_ count: Int, in store: inout BOMStoreWriter, blockSize: Int = 4096) throws -> BOMKeyTree {
        var tree = BOMKeyTree(in: &store, blockSize: blockSize)
        for index in 0..<count {
            let key = Array(String(format: "k%08d", index).utf8)
            let block = store.add(key)
            try tree.insert(key: BOMBlockKey(bytes: key, block: block), value: store.add([0]), in: &store)
        }
        return tree
    }

    /// `names-511`: facets are created in key order; the 511th's value is followed by the new
    /// leaf and the new root; the kept leaf has 256 entries, the other 255.
    @Test func aFullLeafKeepsHalfAndCreatesItsSiblingThenTheRoot() throws {
        var store = BOMStoreWriter()
        let tree = try Self.keyTree(511, in: &store)
        let leaf = tree.headerBlock + 1, lastValue = leaf + 2 * 511
        let right = lastValue + 1, root = right + 1
        #expect(tree.root == root)
        #expect(tree.nodes[root]?.keys.map(\.block) == [leaf + 1 + 2 * 255])
        #expect(tree.nodes[root]?.blocks == [leaf, right])
        #expect(tree.nodes[leaf]?.keys.count == 256 && tree.nodes[leaf]?.forward == right)
        #expect(tree.nodes[right]?.keys.count == 255 && tree.nodes[right]?.backward == leaf)
    }

    /// `names-600`: facets of 9 bytes make leaves of 256 and 344 entries, 6,400 and 7,192 bytes,
    /// and a root of 4,105 whose entries are followed by its last child and a copy of its
    /// separator.
    @Test func nodesCopyFixedLengthKeys() throws {
        var store = BOMStoreWriter()
        let tree = try Self.keyTree(600, in: &store)
        tree.finish(in: &store)
        let leaf = tree.headerBlock + 1
        let right = try #require(tree.nodes[tree.root]?.blocks.last)
        #expect(store.block(leaf)?.count == 6400)
        #expect(store.block(right)?.count == 7192)
        let root = try #require(store.block(tree.root))
        #expect(root.count == 4105)
        #expect(Array(root[0..<4]) == [0, 0, 0, 1])
        #expect(Array(root[24..<33]) == Array("k00000255".utf8))
        let header = try #require(store.block(tree.headerBlock))
        #expect(Array(header[16..<21]) == [0, 0, 2, 0x58, 0])
        #expect(Array(header[21..<25]) == [0, 0, 0, 9])
    }

    /// `mixed-520`, `mixed-1100`: names of different lengths declare 0xFFFFFFFF and copy nothing.
    @Test func nodesOfKeysOfDifferentLengthsAreOneBlockSizeLong() throws {
        var store = BOMStoreWriter()
        var tree = BOMKeyTree(in: &store, blockSize: 4096)
        for index in 0..<520 {
            let key = Array(("k" + String(repeating: "a", count: index % 3) + String(format: "%05d", index)).utf8)
            let block = store.add(key)
            try tree.insert(key: BOMBlockKey(bytes: key, block: block), value: store.add([0]), in: &store)
        }
        tree.finish(in: &store)
        #expect(tree.nodes.count == 3)
        for block in tree.nodes.keys { #expect(store.block(block)?.count == 4096) }
        #expect(Array(try #require(store.block(tree.headerBlock))[21..<25]) == [0xFF, 0xFF, 0xFF, 0xFF])
    }

    struct BitmapShape: Sendable {
        var count: Int
        var root: UInt32
        var separators: [Int]
        var branches: [Int]
        var leaves: Int
    }

    /// `seq-12000`: the shape of `BITMAPKEYS` for color sets `c00000`..., whose value order is the
    /// hash table's at 19,447 slots: a root over two branches. `root` is its block's offset from
    /// the tree's header.
    @Test(arguments: [
        BitmapShape(count: 12000, root: 10169, separators: [33930], branches: [66, 71], leaves: 139),
    ])
    func bitmapKeysBranchesSplit(observed: BitmapShape) throws {
        let count = observed.count
        let names = (0..<count).map { String(format: "c%05d", $0) }
        let identifiers = RenditionIdentifier.assign(names).values.sorted()
        var created: [(identifier: UInt16, values: [UInt16])] = []
        CARWriter.midpointPreorder(identifiers.count) { created.append((identifiers[$0], [identifiers[$0]])) }
        var store = BOMStoreWriter()
        let tree = try CARWriter.addBitmapKeys(keyFormat: [.identifier], renditions: created, to: &store)
        #expect(tree.root - tree.headerBlock == observed.root)
        let root = try #require(tree.nodes[tree.root])
        #expect(root.keys.map(Int.init) == observed.separators)
        #expect(root.blocks.map { tree.nodes[$0]!.keys.count } == observed.branches)
        #expect(tree.nodes.values.filter(\.isLeaf).count == observed.leaves)
        #expect(tree.count == count)
    }

    /// Past what `large-tables` reached nomac stops: a 4,096-byte table's branch would overflow
    /// at about 130,000 entries; here a small block size stands for it.
    @Test func aKeyTableBranchOverflowIsRefused() throws {
        var store = BOMStoreWriter()
        #expect(throws: NomacError.self) { _ = try Self.keyTree(40, in: &store, blockSize: 44) }
    }

    @Test func identifiersPastTheObservedTablesAreRefused() {
        #expect(BitmapKeyTable.mostIdentifiers == 31324)
    }

    /// assetutil's rule for trees of several leaves is not known: 900 renditions thinned to 300
    /// end in the last leaf, the others freed.
    @Test func thinningSeveralLeavesIsRefused() throws {
        var store = BOMStoreWriter()
        let tree = try Self.keyTree(511, in: &store)
        tree.finish(in: &store)
        #expect(throws: NomacError.self) {
            _ = try BOMTree(reading: store, headerBlock: tree.headerBlock, name: "RENDITIONS", path: "A.car")
        }
    }

    /// actool's growth points of the identifier table: each of these first makes it move on.
    @Test(arguments: [(672, 1087), (673, 1723), (1065, 1723), (1066, 2803), (1732, 2803), (1733, 4523), (2795, 4523), (2796, 7351)])
    func identifierTableGrowsAtActoolsCounts(count: Int, slots: Int) {
        var table = BitmapKeyTable()
        for identifier in 1...count { table.insert(UInt16(identifier)) }
        #expect(table.slots.count == slots)
        #expect(table.slotOrder.count == count)
    }
}

/// Whole stores, by digest of actool's with its appearance keys in name order (`large-tables`).
@Suite struct LargeCatalogTests {
    @Test(arguments: [
        (511, 1, "086edbc199a377e15788d096b4e72c1ac9219d744190d2811f26c8b29bcc0bc5", 266392),
        (1200, 1, "f7b3ac272875df96297edd2cd38f1e9c34fea533dd4e5c7bf04fc0c7eddee924", 600440),
        (3000, 1, "88753f41f6f2602c39008fadbab1e42798f7e00274b712d6cab59d16c1453f65", 1465032),
        (200, 3, "4e91be675e0023f2288ab8ed9e6fc63acd143bc5743b3cfe3b27d2cd2234e0e8", 243400),
    ])
    func sequentialColorSets(names: Int, appearances: Int, digest: String, bytes: Int) throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        let dark: [String: Any] = ["appearances": [["appearance": "luminosity", "value": "dark"]]]
        let light: [String: Any] = ["appearances": [["appearance": "luminosity", "value": "light"]]]
        var entries = [ColorCatalogTests.entry(ColorCatalogTests.rgb("1.000", "0.000", "0.000"))]
        if appearances == 3 {
            entries.append(ColorCatalogTests.entry(ColorCatalogTests.rgb("0.000", "1.000", "0.000"), light))
            entries.append(ColorCatalogTests.entry(ColorCatalogTests.rgb("0.000", "0.000", "1.000"), dark))
        }
        var colors: [String: [[String: Any]]] = [:]
        for index in 0..<names { colors[String(format: "c%05d", index)] = entries }
        try ColorCatalogTests.writeCatalog(catalog, colors)
        _ = try ColorCatalogTests.compile(catalog, in: temporary.path + "/out")
        let car = try ColorCatalogTests.car(temporary.path + "/out")
        #expect(car.count == bytes)
        #expect(ColorCatalogTests.hex(SHA256.digest(car)) == digest)
    }
}
