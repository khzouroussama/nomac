import Testing
@testable import NomacAssets

/// Facts about `Assets.car` found by the `identifiers`, `collisions` and `bitmap-order`
/// experiments of `.github/scripts/assets_experiments.py`.
@Suite struct CARStructureTests {
    @Test(arguments: [
        ("Red", 0x896A), ("a", 0xA2CA), ("b", 0x2F2B), ("Blue", 0x04D0), ("Zebra", 0xD7FA), ("aa", 0x9724),
        ("helloworld", 0xAFC5), ("F/Red", 0xC2EF), ("zztcqgmy", 0), ("é", 0x3652), ("日本", 0x4CE0), ("Emoji😀", 0x6610),
        ("mmmmmmmmmmmmmm", 0xBE77), ("mxolveu_sfwgs}", 0xBE77),
    ])
    func primaryIdentifiers(name: String, identifier: Int) {
        #expect(RenditionIdentifier.primary(name) == UInt16(identifier))
    }

    @Test func collisionsGoToTheLaterName() {
        #expect(RenditionIdentifier.assign(["bB", "ac"]) == ["ac": 0xAFE6, "bB": 0x6EF1])
        #expect(RenditionIdentifier.assign(["cZ", "b{"]) == ["b{": 0xF17F, "cZ": 0x6E40])
    }

    /// 104 names in 52 colliding pairs: the later names of a pair probe past identifiers taken
    /// by earlier ones.
    @Test func collisionsProbeForAFreeIdentifier() {
        var names: [String] = []
        for letter in UnicodeScalar("a").value...UnicodeScalar("z").value {
            let first = String(UnicodeScalar(letter)!), second = String(UnicodeScalar(letter - 33)!)
            names += ["a" + first, "b" + second, "xa" + first, "xb" + second]
        }
        let identifiers = RenditionIdentifier.assign(names)
        #expect(identifiers["bB"] == 0x6EF1)
        #expect(identifiers["xbS"] == 0x0E1D)
        #expect(identifiers["xbT"] == 0x0E1F)
        #expect(identifiers["xbU"] == 0x0E20)
        #expect(identifiers["xbV"] == 0x0E29)
    }

    @Test func renditionsAreCreatedMiddleFirst() {
        var order: [Int] = []
        CARWriter.midpointPreorder(8) { order.append($0) }
        #expect(order == [4, 2, 1, 0, 3, 6, 5, 7])
    }

    /// Insertion orders and the value order actool wrote, for catalogs of 3, 7 and 10 colors.
    @Test(arguments: [
        ([0x440F, 0x2FCC, 0xFF0B], [0x2FCC, 0xFF0B, 0x440F]),
        ([0xA34B, 0x54F0, 0x0B84, 0x7D47, 0xEAB1, 0xB672, 0xEB76], [0x54F0, 0x7D47, 0xEB76, 0xB672, 0x0B84, 0xEAB1, 0xA34B]),
        (
            [0x7580, 0x2B5B, 0x1AE2, 0x19C2, 0x4E19, 0x3110, 0xA4AC, 0xA140, 0x982B, 0xF192],
            [0x1AE2, 0xA140, 0xA4AC, 0x2B5B, 0x3110, 0x7580, 0x982B, 0x19C2, 0x4E19, 0xF192]
        ),
    ])
    func bitmapKeyOrder(inserted: [Int], written: [Int]) {
        var table = BitmapKeyTable()
        for identifier in inserted { table.insert(UInt16(identifier)) }
        #expect(table.slotOrder == written.map(UInt16.init))
    }

    @Test func storeLayout() {
        var store = BOMStoreWriter()
        let first = store.add([1, 2, 3])
        let second = store.add([4])
        store.addVariable("ONE", block: first)
        let bytes = store.serialized()
        #expect(Array(bytes[0..<8]) == Array("BOMStore".utf8))
        // Blocks start at 0x200 and on 16-byte boundaries; variables follow, then the index.
        #expect(Array(bytes[0x200..<0x203]) == [1, 2, 3])
        #expect(bytes[0x210] == 4)
        #expect(Array(bytes[0x220..<0x224]) == [0, 0, 0, 1])
        let indexOffset = 0x230
        #expect(Array(bytes[16..<20]) == [0, 0, 0x02, 0x30])
        #expect(Array(bytes[12..<16]) == [0, 0, 0, UInt8(second)])
        #expect(Array(bytes[indexOffset..<indexOffset + 4]) == [0, 0, 1, 0])
        #expect(bytes.count == indexOffset + 4 + 256 * 8 + 4 + 16)
    }
}
