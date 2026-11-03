import Foundation

/// Writes binary property lists (`bplist00`) byte for byte as Xcode's tools write them
/// (docs/formats/property-lists.md "Binary").
public enum BinaryPropertyList {
    /// The binary property lists Swift Build writes on a Mac (`builtin-copyStrings`): keys in
    /// Swift's string order, and the object sharing of Core Foundation's writer fed with
    /// Swift Build's interned strings (strings-experiments `copy`).
    public static func swiftBuildData(_ value: PropertyListValue) -> Data {
        var writer = Writer()
        writer.flatten(value) { $0.sorted() }
        return writer.serialized()
    }

    /// What Foundation writes for a property list it read from `swiftBuildData`'s output, as an
    /// app-store-connect export writes the app's and its extensions' Info.plist again
    /// (signing-experiments `nested`): the same objects, each dictionary's keys in the order of a
    /// Foundation dictionary created with them in Swift's order, and the top one's in the order
    /// of a copy created with them in that order, as a shallow mutable copy makes (packaging's
    /// `AppStoreExportTests`: in 23 buckets, a key that wrapped around in the first table takes
    /// its own bucket back in the copy, in the top dictionary and not in a nested one).
    public static func foundationData(rereading value: PropertyListValue) throws -> Data {
        var writer = Writer()
        var top = if case .dictionary = value { true } else { false }
        try writer.flatten(value) { keys in
            let read = try FoundationHashTable.created(with: keys.sorted()).keys
            defer { top = false }
            return top ? try FoundationHashTable.created(with: read).keys : read
        }
        return writer.serialized()
    }

    /// What Foundation writes for `value` with each dictionary's keys in the order `keyOrder`
    /// gives for them (a thinned variant's watch placeholder, NomacPackaging's `WatchPlaceholder`).
    public static func foundationData(_ value: PropertyListValue, keyOrder: ([String]) throws -> [String]) throws -> Data {
        var writer = Writer()
        try writer.flatten(value, keyOrder: keyOrder)
        return writer.serialized()
    }

    /// A binary property list of the given objects, the first one the top: for writers whose
    /// sharing follows which objects they held rather than equal values (ibtool's storyboard
    /// `Info.plist`, docs/formats/nib.md "Storyboards").
    public static func data(objects: [Object]) -> Data {
        Writer(objects: objects).serialized()
    }

    /// An object of a binary property list; containers refer to others by index.
    public enum Object: Equatable, Sendable {
        case boolean(Bool)
        case integer(Int)
        case real(Double)
        /// A 4-byte real (`22`), as Core Foundation writes a float `NSNumber`.
        case float(Float)
        /// A keyed archive's object reference (`8n`, 1, 2 or 4 bytes).
        case uid(Int)
        case date(Double)
        case data([UInt8])
        case string(String)
        case array([Int])
        case dictionary(keys: [Int], values: [Int])
    }

    private struct Writer {
        var objects: [Object] = []
        /// Strings are equal when their UTF-16 code units are, as `NSString`s are.
        var strings: [[UInt16]: Int] = [:]
        var integers: [Int: Int] = [:]
        var booleans: [Bool: Int] = [:]

        /// Appends `value` and everything it holds, depth first: a dictionary, then its keys,
        /// then its values. Equal strings and equal integers are one object; reals, dates, data
        /// and containers never are. Every boolean is appended, but all references to `true`
        /// (or `false`) name the first one (`xml-duplicates`).
        @discardableResult
        mutating func flatten(_ value: PropertyListValue, keyOrder order: ([String]) throws -> [String]) rethrows -> Int {
            switch value {
            case .string(let string):
                let units = Array(string.utf16)
                if let index = strings[units] { return index }
                strings[units] = objects.count
                return append(.string(string))
            case .integer(let integer):
                if let index = integers[integer] { return index }
                integers[integer] = objects.count
                return append(.integer(integer))
            case .boolean(let boolean):
                let index = append(.boolean(boolean))
                if let first = booleans[boolean] { return first }
                booleans[boolean] = index
                return index
            case .real(let real):
                return append(.real(real))
            case .date(let date):
                return append(.date(date))
            case .data(let bytes):
                return append(.data(bytes))
            case .array(let elements):
                let index = append(.array([]))
                var references: [Int] = []
                for element in elements {
                    references.append(try flatten(element, keyOrder: order))
                }
                objects[index] = .array(references)
                return index
            case .dictionary(let entries):
                let index = append(.dictionary(keys: [], values: []))
                let keys = try order(Array(entries.keys))
                var keyReferences: [Int] = []
                for key in keys {
                    keyReferences.append(flatten(.string(key)) { $0 })
                }
                var valueReferences: [Int] = []
                for key in keys {
                    valueReferences.append(try flatten(entries[key]!, keyOrder: order))
                }
                objects[index] = .dictionary(keys: keyReferences, values: valueReferences)
                return index
            }
        }

        private mutating func append(_ object: Object) -> Int {
            objects.append(object)
            return objects.count - 1
        }

        /// The header, the objects, the offset table and the trailer. Offsets take the bytes
        /// the offset table's own position needs, references those the object count needs
        /// (`table-at-256`, `objects-256`).
        func serialized() -> Data {
            let referenceSize = byteCount(objects.count)
            var bytes: [UInt8] = Array("bplist00".utf8)
            var offsets: [Int] = []
            for object in objects {
                offsets.append(bytes.count)
                encode(object, referenceSize: referenceSize, into: &bytes)
            }
            let tableOffset = bytes.count
            let offsetSize = byteCount(tableOffset)
            for offset in offsets {
                bytes += bigEndian(offset, size: offsetSize)
            }
            bytes += [0, 0, 0, 0, 0, 0, UInt8(offsetSize), UInt8(referenceSize)]
            bytes += bigEndian(objects.count, size: 8) + bigEndian(0, size: 8) + bigEndian(tableOffset, size: 8)
            return Data(bytes)
        }

        private func encode(_ object: Object, referenceSize: Int, into bytes: inout [UInt8]) {
            switch object {
            case .boolean(let boolean):
                bytes.append(boolean ? 0x09 : 0x08)
            case .integer(let integer):
                bytes += integerObject(integer)
            case .real(let real):
                bytes.append(0x23)
                bytes += bigEndian(Int(bitPattern: UInt(real.bitPattern)), size: 8)
            case .float(let float):
                bytes.append(0x22)
                bytes += bigEndian(Int(float.bitPattern), size: 4)
            case .uid(let uid):
                let size = uid <= 0xFF ? 1 : uid <= 0xFFFF ? 2 : 4
                bytes.append(0x80 | UInt8(size - 1))
                bytes += bigEndian(uid, size: size)
            case .date(let date):
                bytes.append(0x33)
                bytes += bigEndian(Int(bitPattern: UInt(date.bitPattern)), size: 8)
            case .data(let data):
                bytes += marker(0x40, count: data.count) + data
            case .string(let string):
                if string.unicodeScalars.allSatisfy(\.isASCII) {
                    bytes += marker(0x50, count: string.utf8.count) + Array(string.utf8)
                } else {
                    let units = Array(string.utf16)
                    bytes += marker(0x60, count: units.count)
                    for unit in units {
                        bytes += [UInt8(unit >> 8), UInt8(unit & 0xFF)]
                    }
                }
            case .array(let references):
                bytes += marker(0xA0, count: references.count)
                for reference in references {
                    bytes += bigEndian(reference, size: referenceSize)
                }
            case .dictionary(let keys, let values):
                bytes += marker(0xD0, count: keys.count)
                for reference in keys + values {
                    bytes += bigEndian(reference, size: referenceSize)
                }
            }
        }

        /// A type marker with its count in the low nibble, or `0xF` and an integer object.
        private func marker(_ type: UInt8, count: Int) -> [UInt8] {
            count < 15 ? [type | UInt8(count)] : [type | 0x0F] + integerObject(count)
        }

        /// Integers take 1, 2, 4 or 8 bytes; negative ones always 8.
        private func integerObject(_ integer: Int) -> [UInt8] {
            let size = integer < 0 ? 8 : byteCount(integer)
            let exponent: UInt8 = size == 1 ? 0 : size == 2 ? 1 : size == 4 ? 2 : 3
            return [0x10 | exponent] + bigEndian(integer, size: size)
        }

        private func byteCount(_ value: Int) -> Int {
            value <= 0xFF ? 1 : value <= 0xFFFF ? 2 : value <= 0xFFFF_FFFF ? 4 : 8
        }

        private func bigEndian(_ value: Int, size: Int) -> [UInt8] {
            (0..<size).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        }
    }
}
