import Foundation

/// Compares ibtool's nibs with nomac's where ibtool's own order changes from run to run: outlet
/// collections of several sources (ADR 0260; docs/formats/nib.md "Connections"). The canonical form
/// walks the archive's objects from the root, numbering each where the walk first reaches it, the
/// root's outlet collection connections sorted by label and source, their destinations by class; two nibs of one canonical form
/// decode to the same objects and connections.
enum NibConnectionComparison {
    private struct Value {
        let key: String
        let type: UInt8
        let payload: [UInt8]
        var reference: Int? {
            guard type == 10, payload.count == 4 else { return nil }
            return payload.reversed().reduce(0) { $0 << 8 | Int($1) }
        }
    }

    /// The canonical form of an `NIBArchive`, or nil when it is not one.
    static func canonical(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count >= 50, Array(bytes[0..<10]) == Array("NIBArchive".utf8) else { return nil }
        func u32(_ offset: Int) -> Int { bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | Int($1) } }
        func varint(_ offset: inout Int) -> Int? {
            var value = 0, shift = 0
            while offset < bytes.count, shift < 63 {
                let byte = bytes[offset]
                offset += 1
                value |= Int(byte & 0x7F) << shift
                shift += 7
                if byte & 0x80 != 0 { return value }
            }
            return nil
        }
        let fields = (0..<10).map { u32(10 + 4 * $0) }
        let (objectCount, objectsAt, keyCount, keysAt, valueCount, valuesAt, classCount, classesAt) =
            (fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9])
        func string(_ offset: inout Int, fallbacks: Bool) -> String? {
            guard let length = varint(&offset) else { return nil }
            if fallbacks {
                guard let count = varint(&offset) else { return nil }
                offset += 4 * count
            }
            guard offset + length <= bytes.count else { return nil }
            defer { offset += length }
            return String(decoding: bytes[offset..<offset + length].prefix { $0 != 0 }, as: UTF8.self)
        }
        var offset = keysAt
        var keys: [String] = []
        for _ in 0..<keyCount {
            guard let key = string(&offset, fallbacks: false) else { return nil }
            keys.append(key)
        }
        let sizes: [UInt8: Int] = [0: 1, 1: 2, 2: 4, 3: 8, 4: 0, 5: 0, 6: 4, 7: 8, 9: 0, 10: 4]
        var values: [Value] = []
        offset = valuesAt
        for _ in 0..<valueCount {
            guard let key = varint(&offset), key < keys.count, offset < bytes.count else { return nil }
            let type = bytes[offset]
            offset += 1
            let length: Int
            if type == 8 {
                guard let count = varint(&offset) else { return nil }
                length = count
            } else {
                guard let size = sizes[type] else { return nil }
                length = size
            }
            guard offset + length <= bytes.count else { return nil }
            values.append(Value(key: keys[key], type: type, payload: Array(bytes[offset..<offset + length])))
            offset += length
        }
        offset = classesAt
        var classes: [String] = []
        for _ in 0..<classCount {
            guard let name = string(&offset, fallbacks: true) else { return nil }
            classes.append(name)
        }
        offset = objectsAt
        var objects: [(name: String, values: [Value])] = []
        for _ in 0..<objectCount {
            guard let classIndex = varint(&offset), let first = varint(&offset), let count = varint(&offset), classIndex < classes.count,
                  first + count <= values.count else { return nil }
            objects.append((classes[classIndex], Array(values[first..<first + count])))
        }
        guard !objects.isEmpty else { return nil }
        let connections = objects[0].values.first { $0.key == "UINibConnectionsKey" }?.reference
        guard objects.indices.contains(connections ?? 0), objects.allSatisfy({ $0.values.allSatisfy { $0.reference.map(objects.indices.contains) ?? true } }) else {
            return nil
        }
        let collection = "UIRuntimeOutletCollectionConnection"
        func text(_ index: Int?) -> [UInt8] {
            index.flatMap { objects[$0].values.first { $0.key == "NS.bytes" }?.payload } ?? []
        }
        var numbering: [Int: Int] = [:]
        var lines: [(index: Int, name: String, values: [Value])] = []
        var destinations: Set<Int> = []
        func references(_ list: [Int]) -> [Value] {
            list.map { reference in Value(key: "", type: 10, payload: (0..<4).map { UInt8(truncatingIfNeeded: reference >> (8 * $0)) }) }
        }
        func walk(_ start: Int) {
            var stack = [start]
            while let index = stack.popLast() {
                guard numbering[index] == nil else { continue }
                numbering[index] = numbering.count
                var items = objects[index].values
                if index == connections {
                    let listed = items.compactMap(\.reference)
                    var run = listed.filter { objects[$0].name == collection }
                    for reference in run {
                        if let source = objects[reference].values.first(where: { $0.key == "UISource" })?.reference { walk(source) }
                    }
                    func key(_ reference: Int) -> ([UInt8], Int) {
                        let fields = objects[reference].values
                        return (text(fields.first { $0.key == "UILabel" }?.reference),
                                fields.first { $0.key == "UISource" }?.reference.flatMap { numbering[$0] } ?? -1)
                    }
                    run.sort { key($0).0 == key($1).0 ? key($0).1 < key($1).1 : key($0).0.lexicographicallyPrecedes(key($1).0) }
                    for reference in run {
                        destinations.formUnion(objects[reference].values.filter { $0.key == "UIDestination" }.compactMap(\.reference))
                    }
                    let ordered = run + listed.filter { objects[$0].name != collection }
                    items = items.filter { $0.reference == nil } + references(ordered)
                } else if destinations.contains(index) {
                    let ordered = items.compactMap(\.reference).enumerated().sorted { left, right in
                        objects[left.element].name == objects[right.element].name ? left.offset < right.offset
                            : Array(objects[left.element].name.utf8).lexicographicallyPrecedes(Array(objects[right.element].name.utf8))
                    }.map(\.element)
                    items = items.filter { $0.reference == nil } + references(ordered)
                }
                lines.append((index, objects[index].name, items))
                stack += items.compactMap(\.reference).reversed()
            }
        }
        walk(0)
        return lines.sorted { numbering[$0.index]! < numbering[$1.index]! }.map { line in
            "\(numbering[line.index]!) \(line.name) " + line.values.map { value in
                value.reference.map { "\(value.key)=#\(numbering[$0]!)" } ?? "\(value.key)=\(value.type):" + value.payload.map { String(format: "%02x", $0) }.joined()
            }.joined(separator: ", ")
        }.joined(separator: "\n")
    }
}
