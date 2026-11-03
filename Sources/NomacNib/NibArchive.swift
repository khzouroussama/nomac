import Foundation

/// A value of a NIB archive (docs/formats/nib.md "Values").
enum NibValue: Equatable, Sendable {
    case integer(Int)
    case boolean(Bool)
    case float(Float)
    case double(Double)
    case data([UInt8])
    case null
    case object(Int)
}

/// An archived object: its class, by index into the class table, and its values in order.
struct NibObject {
    var classIndex: Int
    var values: [(key: String, value: NibValue)]
}

/// The class table: classes in the order their first object is numbered, then the fallback
/// classes no object has, by name (`NSColor`, `NSFont`, `UIView` whichever classes name them:
/// 671 nibs of nib-experiments and the corpus, `label-*`, `sb-view-custom-class`).
struct NibClassTable {
    private var used: [String] = []
    private var fallbackNames: [[String]] = []

    /// The index of `name`, appending it when it is new.
    mutating func index(of name: String, fallbacks: [String]) -> Int {
        if let index = used.firstIndex(of: name) { return index }
        used.append(name)
        fallbackNames.append(fallbacks)
        return used.count - 1
    }

    /// The names as written, each with the indexes of its fallback classes.
    var written: [(name: String, fallbacks: [Int])] {
        let names = used + Set(fallbackNames.joined()).subtracting(used).sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        let fallbacks = fallbackNames.map { $0.map { names.firstIndex(of: $0)! } }
        return names.enumerated().map { ($0.element, $0.offset < fallbacks.count ? fallbacks[$0.offset] : []) }
    }
}

/// Writes `NIBArchive` files byte for byte as ibtool writes them for iOS
/// (docs/formats/nib.md "Archive"): the header, objects, keys, values and classes, then `LNE`
/// and a zero byte.
enum NibArchive {
    static func data(objects: [NibObject], keys: [String], classes: NibClassTable) -> Data {
        let keyIndex = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element, $0.offset) })
        var objectBytes: [UInt8] = []
        var valueBytes: [UInt8] = []
        var valueCount = 0
        for object in objects {
            let firstValue = object.values.isEmpty ? 0 : valueCount
            objectBytes += varint(object.classIndex) + varint(firstValue) + varint(object.values.count)
            for (key, value) in object.values {
                valueBytes += varint(keyIndex[key]!) + encoded(value)
                valueCount += 1
            }
        }
        var keyBytes: [UInt8] = []
        for key in keys {
            keyBytes += varint(key.utf8.count) + Array(key.utf8)
        }
        var classBytes: [UInt8] = []
        let written = classes.written
        for (name, fallbacks) in written {
            classBytes += varint(name.utf8.count + 1) + varint(fallbacks.count)
            for fallback in fallbacks {
                classBytes += littleEndian(UInt32(fallback))
            }
            classBytes += Array(name.utf8) + [0]
        }
        let header = 10 + 40
        var bytes: [UInt8] = Array("NIBArchive".utf8)
        let objectsOffset = header
        let keysOffset = objectsOffset + objectBytes.count
        let valuesOffset = keysOffset + keyBytes.count
        let classesOffset = valuesOffset + valueBytes.count
        for field in [1, 10, objects.count, objectsOffset, keys.count, keysOffset, valueCount, valuesOffset, written.count, classesOffset] {
            bytes += littleEndian(UInt32(field))
        }
        return Data(bytes + objectBytes + keyBytes + valueBytes + classBytes + Array("LNE".utf8) + [0])
    }

    /// Seven bits per byte, least significant first; the last byte has its high bit set.
    static func varint(_ value: Int) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        while value >= 0x80 {
            bytes.append(UInt8(value & 0x7F))
            value >>= 7
        }
        bytes.append(UInt8(value) | 0x80)
        return bytes
    }

    /// The type byte and payload: a non-negative integer in the smallest of 1, 2, 4 and 8 bytes
    /// that holds it as a signed number, a negative one in 8 (nib-experiments `tag-*`), `false` 4,
    /// `true` 5, floats 6, doubles 7, data 8 with its length, nil 9, objects 10 with an index.
    static func encoded(_ value: NibValue) -> [UInt8] {
        switch value {
        case .integer(let integer) where integer < 0:
            return [3] + littleEndian(UInt64(bitPattern: Int64(integer)))
        case .integer(let integer):
            if integer <= Int8.max { return [0, UInt8(integer)] }
            if integer <= Int16.max { return [1] + littleEndian(UInt16(integer)) }
            if integer <= Int32.max { return [2] + littleEndian(UInt32(integer)) }
            return [3] + littleEndian(UInt64(integer))
        case .boolean(let boolean):
            return [boolean ? 5 : 4]
        case .float(let float):
            return [6] + littleEndian(float.bitPattern)
        case .double(let double):
            return [7] + littleEndian(double.bitPattern)
        case .data(let data):
            return [8] + varint(data.count) + data
        case .null:
            return [9]
        case .object(let index):
            return [10] + littleEndian(UInt32(index))
        }
    }

    static func littleEndian<Integer: FixedWidthInteger>(_ value: Integer) -> [UInt8] {
        (0..<(Integer.bitWidth / 8)).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
}
