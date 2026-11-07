import Foundation
import Testing
@testable import NomacVerify

@Suite struct NibConnectionComparisonTests {
    typealias Object = (name: String, values: [(key: String, reference: Int?, bytes: [UInt8])])

    /// A `NIBArchive` of `objects`, each value a reference or an `NS.bytes` data value.
    static func archive(_ objects: [Object]) -> Data {
        let keys = Array(Set(objects.flatMap { $0.values.map(\.key) })).sorted()
        let classes = Array(Set(objects.map(\.name))).sorted()
        typealias S = NibSetComparisonTests
        var values: [UInt8] = [], rows: [UInt8] = [], count = 0
        for object in objects {
            rows += S.varint(classes.firstIndex(of: object.name)!) + S.varint(count) + S.varint(object.values.count)
            for value in object.values {
                let key = S.varint(keys.firstIndex(of: value.key)!)
                values += value.reference.map { key + [10] + S.u32($0) } ?? key + [8] + S.varint(value.bytes.count) + value.bytes
                count += 1
            }
        }
        let keyBytes: [UInt8] = keys.flatMap { S.varint($0.utf8.count) + Array($0.utf8) }
        let classBytes: [UInt8] = classes.flatMap { S.varint($0.utf8.count + 1) + S.varint(0) + Array($0.utf8) + [0] }
        let objectsAt = 50, keysAt = objectsAt + rows.count, valuesAt = keysAt + keyBytes.count, classesAt = valuesAt + values.count
        let fields = [1, 10, objects.count, objectsAt, keys.count, keysAt, count, valuesAt, classes.count, classesAt]
        return Data(Array("NIBArchive".utf8) + fields.flatMap(S.u32) + rows + keyBytes + values + classBytes)
    }

    /// A root whose connections are two outlet collections of `labels` from a view, written in
    /// `order`, each with its label string and destination array numbered where it comes.
    static func connections(_ labels: [String], order: [Int]) -> Data {
        var objects: [Object] = [("NSObject", [("UINibTopLevelObjectsKey", 2, []), ("UINibConnectionsKey", 1, [])]),
                                 ("NSArray", order.map { ("UINibEncoderEmptyKey", 3 + 3 * $0, []) }), ("UIView", [])]
        objects += Array(repeating: ("NSString", []), count: 3 * labels.count)
        for (place, index) in order.enumerated() {
            let base = 3 + 3 * place
            objects[3 + 3 * index] = ("UIRuntimeOutletCollectionConnection",
                                      [("UILabel", base + 1, []), ("UISource", 2, []), ("UIDestination", base + 2, [])])
            objects[base + 1] = ("NSString", [("NS.bytes", nil, Array(labels[index].utf8))])
            objects[base + 2] = ("NSMutableArray", [("UINibEncoderEmptyKey", 2, [])])
        }
        return archive(objects)
    }

    /// A root with one collection attaching objects of `classes`, in that order.
    static func destinations(_ classes: [String]) -> Data {
        archive([("NSObject", [("UINibTopLevelObjectsKey", 2, []), ("UINibConnectionsKey", 1, [])]), ("NSArray", [("UINibEncoderEmptyKey", 3, [])]), ("UIView", []),
                 ("UIRuntimeOutletCollectionConnection", [("UILabel", 4, []), ("UISource", 2, []), ("UIDestination", 5, [])]),
                 ("NSString", [("NS.bytes", nil, Array("gestureRecognizers".utf8))]), ("NSMutableArray", [("UINibEncoderEmptyKey", 6, []), ("UINibEncoderEmptyKey", 7, [])]),
                 (classes[0], []), (classes[1], [])])
    }

    /// vlc's VideoPlayerControls, three orders in eight runs of ibtool (ADR 0260).
    @Test func ordersOfACollectionsDestinationsAreOneCanonicalForm() throws {
        let canonical = try #require(NibConnectionComparison.canonical(Self.destinations(["UITapGestureRecognizer", "UILongPressGestureRecognizer"])))
        #expect(NibConnectionComparison.canonical(Self.destinations(["UILongPressGestureRecognizer", "UITapGestureRecognizer"])) == canonical)
        #expect(NibConnectionComparison.canonical(Self.destinations(["UITapGestureRecognizer", "UISwipeGestureRecognizer"])) != canonical)
    }

    @Test func ordersOfCollectionsAreOneCanonicalForm() throws {
        let canonical = try #require(NibConnectionComparison.canonical(Self.connections(["alpha", "zeta"], order: [0, 1])))
        #expect(NibConnectionComparison.canonical(Self.connections(["alpha", "zeta"], order: [1, 0])) == canonical)
        #expect(NibConnectionComparison.canonical(Self.connections(["alpha", "beta"], order: [1, 0])) != canonical)
    }

    @Test func refusesOtherData() {
        #expect(NibConnectionComparison.canonical(Data("bplist00".utf8)) == nil)
        #expect(NibConnectionComparison.canonical(Self.connections(["a", "b"], order: [0, 1]).prefix(60)) == nil)
    }
}
