import Foundation
import Testing
@testable import NomacVerify

@Suite struct NibSetComparisonTests {
    static func varint(_ value: Int) -> [UInt8] {
        var value = value, bytes: [UInt8] = []
        while value >= 0x80 {
            bytes.append(UInt8(value & 0x7F))
            value >>= 7
        }
        return bytes + [UInt8(value) | 0x80]
    }

    static func u32(_ value: Int) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    /// A `NIBArchive` of a root object holding a data value and an object of `container`'s class
    /// referencing `elements`, plus the objects they name.
    static func archive(_ container: String, _ elements: [Int], data: [UInt8] = []) -> Data {
        let keys = ["NS.object.0", "NS.object.1", "NS.object.2", "data", "set"]
        let classes = ["NSObject", container]
        var values: [UInt8] = varint(3) + [8] + varint(data.count) + data
        values += varint(4) + [10] + u32(1)
        for (index, element) in elements.enumerated() {
            values += varint(index) + [10] + u32(element)
        }
        let rows: [[Int]] = [[0, 0, 2], [1, 2, elements.count], [0, 0, 0], [0, 0, 0], [0, 0, 0]]
        let objects: [UInt8] = rows.joined().flatMap(Self.varint)
        let keyBytes: [UInt8] = keys.flatMap { varint($0.utf8.count) + Array($0.utf8) }
        let classBytes: [UInt8] = classes.flatMap { varint($0.utf8.count + 1) + varint(0) + Array($0.utf8) + [0] }
        let objectsAt = 50, keysAt = objectsAt + objects.count, valuesAt = keysAt + keyBytes.count, classesAt = valuesAt + values.count
        let fields: [Int] = [1, 10, rows.count, objectsAt, keys.count, keysAt, 2 + elements.count, valuesAt, classes.count, classesAt]
        let header: [UInt8] = fields.flatMap(Self.u32)
        var bytes = Array("NIBArchive".utf8) + header
        bytes += objects + keyBytes + values + classBytes
        return Data(bytes + Array("LNE".utf8) + [0])
    }

    @Test func setsCompareByTheirElements() throws {
        for set in ["NSSet", "NSMutableSet"] {
            let ibtool = Self.archive(set, [4, 2, 3]), nomac = Self.archive(set, [2, 3, 4])
            #expect(ibtool != nomac)
            #expect(NibSetComparison.sortingSets(ibtool) == nomac)
            #expect(NibSetComparison.sortingSets(Self.archive(set, [2, 2, 4])) != nomac)
        }
    }

    @Test func orderedCollectionsKeepTheirOrder() {
        for container in ["NSOrderedSet", "NSArray"] {
            #expect(NibSetComparison.sortingSets(Self.archive(container, [4, 2, 3])) != Self.archive(container, [2, 3, 4]))
        }
    }

    @Test func nestedArchivesAreSortedToo() {
        let ibtool = Self.archive("NSArray", [2], data: [UInt8](Self.archive("NSSet", [3, 2])))
        let nomac = Self.archive("NSArray", [2], data: [UInt8](Self.archive("NSSet", [2, 3])))
        #expect(NibSetComparison.sortingSets(ibtool) == nomac)
    }

    @Test func unreadableFilesAreNotEquivalent() {
        #expect(NibSetComparison.sortingSets(Self.archive("NSSet", [3, 2]).prefix(120)) == nil)
        #expect(NibSetComparison.sortingSets(Data("bplist00".utf8)) == nil)
    }
}
