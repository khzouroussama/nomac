import Foundation
import Testing
@testable import NomacVerify

@Suite struct OptimizedModelComparisonTests {
    /// A minimal `.omo`: C strings "", "ab", "cd", one SQL entity listing `columns`, and one lookup
    /// table of "ab" and "cd" dispatching on `position`, its slots swapped when `wrong`.
    func model(columns: [Int], position: Int = 0, wrong: Bool = false) -> Data {
        var bytes = [UInt8](repeating: 0, count: 600)
        func put(_ offset: Int, _ value: Int, width: Int = 4) {
            for index in 0..<width { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * (width - 1 - index))) }
        }
        put(64, 264)
        put(64 + 3 * 4, 544)
        put(64 + 10 * 4, 400)
        put(64 + 16 * 4, 160)
        put(160, 3)
        put(212, 2)
        bytes[224...225] = [UInt8(ascii: "a"), UInt8(ascii: "b")]
        put(244, 2)
        bytes[256...257] = [UInt8(ascii: "c"), UInt8(ascii: "d")]
        put(304, 1)
        put(380, columns.count)
        for (index, column) in columns.enumerated() { put(384 + 8 * index, column, width: 8) }
        put(400, 1)
        put(448, 2)
        put(452, 3)
        put(480, 1)
        for (offset, value) in [(488, 3), (490, 0xFFFF), (492, 1), (494, 0xFFFF)] { put(offset, value, width: 2) }
        put(496, position << 13 | 9)
        let low = Int(Array("ab".utf8)[position]) + 1
        for (offset, value) in [(504, low), (506, wrong ? 1 : 0), (508, low), (510, wrong ? 0 : 1)] { put(offset, value, width: 2) }
        put(520, 1, width: 8)
        put(528, 2, width: 8)
        return Data(bytes)
    }

    @Test func columnListsCompareAsSets() throws {
        let momc = model(columns: [2, 1]), nomac = model(columns: [1, 2])
        #expect(momc != nomac)
        #expect(OptimizedModelComparison.sortingColumnLists(momc) == nomac)
        #expect(OptimizedModelComparison.sortingColumnLists(model(columns: [2, 2])) != nomac)
    }

    /// Tables that lead every key to its slot compare equal whatever position they dispatch on
    /// (ADR 0231).
    @Test func lookupTablesCompareByTheirKeys() throws {
        let momc = try #require(OptimizedModelComparison.canonical(model(columns: [2, 1], position: 1)))
        #expect(model(columns: [1, 2], position: 0) != model(columns: [1, 2], position: 1))
        #expect(OptimizedModelComparison.canonical(model(columns: [1, 2], position: 0)) == momc)
        #expect(OptimizedModelComparison.canonical(model(columns: [1, 2], position: 0, wrong: true)) == nil)
    }

    /// Two entity records: a superentity listing itself and its subentity as `family`, and the
    /// subentity listing itself.
    func entities(family: [Int]) -> Data {
        var words = [Int](repeating: 0, count: 39 + 2 * 18)
        words[16 + 1] = 160
        words[40] = 2
        func record(_ at: Int, _ family: [Int], _ index: Int) {
            words[at] = 0xDAED_FEEB
            words[at + 1] = 64
            let list = at + 13 - 2 * family.count
            words[list - 7] = family.count
            words[list - 1] = family.count
            for (slot, entity) in family.enumerated() { words[list + 2 * slot + 1] = entity }
            words[at + 13] = index
            words[at + 16] = 0xDAED_FEEB
        }
        record(41, family, 0)
        record(58, [1], 1)
        return Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * (3 - $0))) } })
    }

    @Test func familiesCompareAsSets() throws {
        #expect(entities(family: [1, 0]) != entities(family: [0, 1]))
        #expect(OptimizedModelComparison.sortingFamilies(entities(family: [1, 0])) == entities(family: [0, 1]))
        #expect(OptimizedModelComparison.sortingFamilies(entities(family: [0, 1])) == entities(family: [0, 1]))
    }

    @Test func unreadableFilesAreNotEquivalent() {
        #expect(OptimizedModelComparison.sortingColumnLists(model(columns: [2, 1]).prefix(390)) == nil)
        #expect(OptimizedModelComparison.sortingColumnLists(Data()) == nil)
        #expect(OptimizedModelComparison.canonical(model(columns: [2, 1]).prefix(500)) == nil)
    }

    @Test func propertyListsCompareByValue() throws {
        let values: NSDictionary = ["NSManagedObjectModel_VersionHashes": ["Model": ["Item": Data([1, 2])]]]
        let binary = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        let xml = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        #expect(ToolVerification.sameValues(binary, xml))
        #expect(!ToolVerification.sameValues(binary, try PropertyListSerialization.data(fromPropertyList: ["Model": 1] as NSDictionary, format: .binary, options: 0)))
    }
}
