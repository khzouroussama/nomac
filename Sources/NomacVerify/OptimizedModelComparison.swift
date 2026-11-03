import Foundation

/// Compares momc's `.omo` with nomac's: identical but for the order of each SQL entity's
/// column-name list (ADR 0230), the byte positions its lookup tables dispatch on (ADR 0231) and
/// the order of each entity's list of itself and its subentities (ADR 0232) is equivalent
/// (docs/formats/coredata.md "`.omo`").
enum OptimizedModelComparison {
    private struct Reader {
        var bytes: [UInt8]

        func u32(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }

        func u64(_ offset: Int) -> Int? {
            guard let high = u32(offset), let low = u32(offset + 4) else { return nil }
            return high << 32 | low
        }

        func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }

        /// The C strings (header index 16).
        func names() -> [[UInt8]]? {
            guard let namesAt = u32(64 + 16 * 4) else { return nil }
            var offset = aligned(namesAt, 4)
            guard let count = u32(offset) else { return nil }
            offset += 4
            var names: [[UInt8]] = []
            for _ in 0..<count {
                offset = aligned(offset, 8)
                guard let length = u32(offset + 12), offset + 24 + length <= bytes.count else { return nil }
                names.append(Array(bytes[offset + 24..<offset + 24 + length]))
                offset += 24 + length + 1
            }
            return names
        }
    }

    private struct Node {
        var kind: Int, low: Int, below: Int, high: Int, above: Int
        var table: [Int]
    }

    private static func aligned(_ offset: Int, _ width: Int) -> Int { (offset + width - 1) / width * width }

    /// The file with its column-name lists and families sorted, its section offsets cleared and
    /// each lookup table reduced to its keys, or nil when it cannot be read or a table does not
    /// lead every key to its own slot.
    static func canonical(_ data: Data) -> Data? {
        guard let sorted = sortingColumnLists(data).flatMap(sortingFamilies) else { return nil }
        let reader = Reader(bytes: [UInt8](sorted))
        let bytes = reader.bytes
        guard let names = reader.names(), let tablesAt = reader.u32(64 + 10 * 4), let propertiesAt = reader.u32(64 + 3 * 4),
              156 <= tablesAt, tablesAt < propertiesAt, propertiesAt <= bytes.count else { return nil }
        var offset = aligned(tablesAt, 4)
        guard let count = reader.u32(offset) else { return nil }
        var header = Array(bytes[0..<156])
        for index in [0, 1, 3, 10, 12, 14, 16, 18] { header.replaceSubrange(64 + 4 * index..<68 + 4 * index, with: [0, 0, 0, 0]) }
        var canonical = header + bytes[156..<tablesAt]
        offset += 4
        for _ in 0..<count {
            offset = aligned(offset, 8) + 40
            guard let keyCount = reader.u32(offset), let nodeCount = reader.u32(offset + 4), nodeCount >= 1 else { return nil }
            offset += 8 + 8 * nodeCount
            var nodes: [Node] = []
            for _ in 0..<nodeCount - 1 {
                guard let kind = reader.u32(offset), offset + 16 <= propertiesAt else { return nil }
                let low = reader.u16(offset + 8), high = reader.u16(offset + 12)
                let size = max(high - low + 1, 0)
                guard offset + 16 + 2 * size <= propertiesAt else { return nil }
                nodes.append(Node(kind: kind, low: low, below: reader.u16(offset + 10), high: high, above: reader.u16(offset + 14),
                                  table: (0..<size).map { reader.u16(offset + 16 + 2 * $0) }))
                offset += 16 + 2 * (size + (4 - size % 4) % 4)
            }
            guard offset + 8 * keyCount <= propertiesAt else { return nil }
            var keys: [[UInt8]] = []
            for slot in 0..<keyCount {
                guard let index = reader.u64(offset + 8 * slot), index < names.count else { return nil }
                keys.append(names[index])
            }
            guard reachesEverySlot(nodes, keys: keys) else { return nil }
            canonical += [UInt8]("\(keyCount)".utf8) + [0] + bytes[offset..<offset + 8 * keyCount]
            offset += 8 * keyCount
        }
        return Data(canonical + bytes[propertiesAt...])
    }

    /// Whether looking each key up through `nodes` ends at the key's own slot: the first node
    /// dispatches on the key's length, the others on the byte their kind names, and a reference
    /// with the high bit set is a later node.
    private static func reachesEverySlot(_ nodes: [Node], keys: [[UInt8]]) -> Bool {
        guard !nodes.isEmpty else { return keys.count <= 1 }
        for (slot, key) in keys.enumerated() {
            var index = 0
            for _ in nodes.indices {
                let node = nodes[index]
                let value: Int
                if index == 0 {
                    value = String(decoding: key, as: UTF8.self).unicodeScalars.count
                } else {
                    guard node.kind >> 13 < key.count else { return false }
                    value = Int(key[node.kind >> 13])
                }
                let reference: Int
                if value == node.low - 1 {
                    reference = node.below
                } else if value == node.high + 1 {
                    reference = node.above
                } else if value >= node.low, value <= node.high {
                    reference = node.table[value - node.low]
                } else {
                    return false
                }
                if reference & 0x8000 == 0 {
                    guard reference == slot else { return false }
                    index = -1
                    break
                }
                index = 0x10000 - reference
                guard index < nodes.count else { return false }
            }
            guard index == -1 else { return false }
        }
        return true
    }

    /// The file with each entity record's list of itself and its subentities sorted: the list
    /// follows its count, written twice six words apart (and a padding word when the list is
    /// aligned after it), and ends three words before the record's end.
    static func sortingFamilies(_ data: Data) -> Data? {
        var reader = Reader(bytes: [UInt8](data))
        guard let entitiesAt = reader.u32(64 + 4) else { return nil }
        var offset = aligned(entitiesAt, 4)
        guard let count = reader.u32(offset) else { return nil }
        offset += 4
        for _ in 0..<count {
            guard let size = reader.u32(offset + 4), offset + size + 4 <= reader.bytes.count else { return nil }
            let tail = offset + size - 12
            for length in 1...max(count, 1) {
                let start = tail - 8 * length
                guard start - 32 > offset, let gap = reader.u32(start - 4) else { break }
                let label = gap != 0 ? start - 4 : start - 8
                let words = (0..<length).compactMap { reader.u64(start + 8 * $0) }
                if reader.u32(label) == length, reader.u32(label - 24) == length, words.allSatisfy({ $0 < count }), Set(words).count == length {
                    let sorted = words.sorted().flatMap { word in (0..<8).map { UInt8(truncatingIfNeeded: word >> (8 * (7 - $0))) } }
                    reader.bytes.replaceSubrange(start..<tail, with: sorted)
                    break
                }
            }
            offset += size + 4
        }
        return Data(reader.bytes)
    }

    /// The file with each column-name list sorted by name, or nil when it cannot be read.
    static func sortingColumnLists(_ data: Data) -> Data? {
        var reader = Reader(bytes: [UInt8](data))
        guard let names = reader.names(), let sqlAt = reader.u32(64) else { return nil }
        var offset = aligned(sqlAt, 4)
        guard let requests = reader.u32(offset + 8) else { return nil }
        offset += 12
        if requests > 0 { offset = aligned(offset, 8) + 8 * requests }
        guard let entities = reader.u32(offset + 28) else { return nil }
        offset = aligned(offset + 32, 8) + 8 * entities + 32
        if entities > 0 { offset = aligned(offset, 8) + 8 * entities }
        for _ in 0..<entities {
            offset += 20
            guard let columns = reader.u32(offset) else { return nil }
            offset = aligned(offset + 4, 8)
            guard offset + 8 * columns <= reader.bytes.count else { return nil }
            var words: [(name: [UInt8], word: ArraySlice<UInt8>)] = []
            for index in 0..<columns {
                guard let name = reader.u64(offset + 8 * index), name < names.count else { return nil }
                words.append((names[name], reader.bytes[offset + 8 * index..<offset + 8 * index + 8]))
            }
            let sorted = words.sorted { $0.name.lexicographicallyPrecedes($1.name) }.flatMap(\.word)
            reader.bytes.replaceSubrange(offset..<offset + 8 * columns, with: sorted)
            offset += 8 * columns
        }
        return Data(reader.bytes)
    }
}
