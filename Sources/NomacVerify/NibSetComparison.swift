import Foundation

/// Compares ibtool's nibs with nomac's: identical but for the order of the elements of an
/// `NSSet` or `NSMutableSet` is equivalent (ADR 0252; docs/formats/nib.md "Variations"). ibtool
/// writes a set's elements in the order of their memory addresses.
enum NibSetComparison {
    /// The `NIBArchive` with each set's object references in ascending order, in archives nested in
    /// its data values too, or nil when it is not one or cannot be read.
    static func sortingSets(_ data: Data) -> Data? {
        var bytes = [UInt8](data)
        guard sortSets(&bytes, archive: 0..<bytes.count) else { return nil }
        return Data(bytes)
    }

    private static let magic = Array("NIBArchive".utf8)

    private static func sortSets(_ bytes: inout [UInt8], archive: Range<Int>) -> Bool {
        let start = archive.lowerBound
        guard archive.count >= 50, Array(bytes[start..<start + 10]) == magic else { return false }
        func u32(_ offset: Int) -> Int? {
            guard offset >= start, offset + 4 <= archive.upperBound else { return nil }
            return bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
        }
        func varint(_ offset: inout Int) -> Int? {
            var value = 0, shift = 0
            while offset < archive.upperBound, shift < 63 {
                let byte = bytes[offset]
                offset += 1
                value |= Int(byte & 0x7F) << shift
                shift += 7
                if byte & 0x80 != 0 { return value }
            }
            return nil
        }
        let fields = (0..<10).map { u32(start + 10 + 4 * $0) }
        guard let objectCount = fields[2], let objectsAt = fields[3], let keyCount = fields[4], let keysAt = fields[5],
              let valueCount = fields[6], let valuesAt = fields[7], let classCount = fields[8], let classesAt = fields[9] else { return false }
        func strings(_ count: Int, at offset: Int, skippingFallbacks: Bool) -> [[UInt8]]? {
            var offset = start + offset
            var strings: [[UInt8]] = []
            for _ in 0..<count {
                guard let length = varint(&offset) else { return nil }
                if skippingFallbacks {
                    guard let fallbacks = varint(&offset) else { return nil }
                    offset += 4 * fallbacks
                }
                guard offset + length <= archive.upperBound else { return nil }
                strings.append(Array(bytes[offset..<offset + length]))
                offset += length
            }
            return strings
        }
        guard let keys = strings(keyCount, at: keysAt, skippingFallbacks: false),
              let classes = strings(classCount, at: classesAt, skippingFallbacks: true) else { return false }
        let sizes: [UInt8: Int] = [0: 1, 1: 2, 2: 4, 3: 8, 4: 0, 5: 0, 6: 4, 7: 8, 9: 0, 10: 4]
        var values: [(key: Int, type: UInt8, payload: Range<Int>)] = []
        var offset = start + valuesAt
        for _ in 0..<valueCount {
            guard let key = varint(&offset), key < keys.count, offset < archive.upperBound else { return false }
            let type = bytes[offset]
            offset += 1
            let length: Int
            if type == 8 {
                guard let count = varint(&offset) else { return false }
                length = count
            } else {
                guard let size = sizes[type] else { return false }
                length = size
            }
            guard offset + length <= archive.upperBound else { return false }
            values.append((key, type, offset..<offset + length))
            offset += length
        }
        for value in values where value.type == 8 && value.payload.count >= 10 && Array(bytes[value.payload.prefix(10)]) == magic {
            guard sortSets(&bytes, archive: value.payload) else { return false }
        }
        let setClasses = [Array("NSSet".utf8), Array("NSMutableSet".utf8)]
        offset = start + objectsAt
        for _ in 0..<objectCount {
            guard let classIndex = varint(&offset), let first = varint(&offset), let count = varint(&offset), classIndex < classes.count,
                  first + count <= values.count else { return false }
            guard setClasses.contains(Array(classes[classIndex].prefix { $0 != 0 })) else { continue }
            let elements = values[first..<first + count].filter { $0.type == 10 && keys[$0.key].starts(with: Array("NS.object.".utf8)) }
            let sorted = elements.map { Array(bytes[$0.payload]) }.sorted { $0.reversed().lexicographicallyPrecedes($1.reversed()) }
            for (element, reference) in zip(elements, sorted) {
                bytes.replaceSubrange(element.payload, with: reference)
            }
        }
        return true
    }
}
