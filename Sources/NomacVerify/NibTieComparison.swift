import Foundation

/// Compares ibtool's nibs with nomac's where they differ in the order of a settled tie: one item's
/// required constraints by the same attributes to several views, all satisfied by the nib's frames
/// (ADR 0253). Both archives become graphs renumbered depth first from the root, each settled tie's
/// constraints in one canonical order wherever they are listed, every set's elements sorted, and
/// nested archives likewise; equal graphs are equivalent.
enum NibTieComparison {
    struct Value: Equatable {
        let key: String
        let type: UInt8
        let bytes: [UInt8]
        var reference: Int?
        var nested: [Object]?
    }

    struct Object: Equatable {
        let className: String
        var values: [Value]
    }

    /// The canonical graph, or nil when the data is not a `NIBArchive`.
    static func canonical(_ data: Data) -> [Object]? {
        guard var objects = parse([UInt8](data)) else { return nil }
        sortSettledTies(&objects)
        return renumbered(objects)
    }

    private static func parse(_ bytes: [UInt8]) -> [Object]? {
        guard bytes.count >= 50, Array(bytes[0..<10]) == Array("NIBArchive".utf8) else { return nil }
        func u32(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
        }
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
        guard let count = fields[2], let objectsAt = fields[3], let keyCount = fields[4], let keysAt = fields[5], let valueCount = fields[6],
              let valuesAt = fields[7], let classCount = fields[8], let classesAt = fields[9] else { return nil }
        func strings(_ count: Int, at start: Int, fallbacks: Bool) -> [String]? {
            var offset = start, strings: [String] = []
            for _ in 0..<count {
                guard let length = varint(&offset) else { return nil }
                if fallbacks {
                    guard let skipped = varint(&offset) else { return nil }
                    offset += 4 * skipped
                }
                guard offset + length <= bytes.count else { return nil }
                strings.append(String(decoding: bytes[offset..<offset + length].prefix { $0 != 0 }, as: UTF8.self))
                offset += length
            }
            return strings
        }
        guard let keys = strings(keyCount, at: keysAt, fallbacks: false), let classes = strings(classCount, at: classesAt, fallbacks: true) else { return nil }
        let sizes: [UInt8: Int] = [0: 1, 1: 2, 2: 4, 3: 8, 4: 0, 5: 0, 6: 4, 7: 8, 9: 0, 10: 4]
        var values: [Value] = []
        var offset = valuesAt
        for _ in 0..<valueCount {
            guard let key = varint(&offset), key < keys.count, offset < bytes.count else { return nil }
            let type = bytes[offset]
            offset += 1
            let length: Int
            if type == 8 {
                guard let size = varint(&offset) else { return nil }
                length = size
            } else {
                guard let size = sizes[type] else { return nil }
                length = size
            }
            guard offset + length <= bytes.count else { return nil }
            let payload = Array(bytes[offset..<offset + length])
            var value = Value(key: keys[key], type: type, bytes: payload)
            if type == 10 { value.reference = payload.reversed().reduce(0) { $0 << 8 | Int($1) } }
            if type == 8, payload.starts(with: Array("NIBArchive".utf8)) {
                guard let nested = canonical(Data(payload)) else { return nil }
                value.nested = nested
            }
            values.append(value)
            offset += length
        }
        var objects: [Object] = []
        offset = objectsAt
        for _ in 0..<count {
            guard let index = varint(&offset), let first = varint(&offset), let number = varint(&offset), index < classes.count,
                  first + number <= values.count else { return nil }
            objects.append(Object(className: classes[index], values: Array(values[first..<first + number])))
        }
        return objects
    }

    private static func references(_ object: Object) -> [Int] {
        object.values.filter { $0.key == "UINibEncoderEmptyKey" || $0.key.hasPrefix("NS.object.") }.compactMap(\.reference)
    }

    private static func scalar(_ object: Object, _ key: String) -> Double? {
        guard let value = object.values.first(where: { $0.key == key }) else { return nil }
        let bytes = value.bytes
        func integer() -> Int64 { Int64(bitPattern: bytes.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) } << (64 - 8 * UInt64(bytes.count)))
            >> (64 - 8 * Int64(bytes.count)) }
        switch value.type {
        case 0, 1, 2, 3: return Double(integer())
        case 6: return Double(Float(bitPattern: UInt32(truncatingIfNeeded: integer())))
        case 7: return Double(bitPattern: UInt64(bitPattern: integer()))
        case 10: return value.reference.map(Double.init)
        default: return nil
        }
    }

    private static func sortSettledTies(_ objects: inout [Object]) {
        func field(_ index: Int, _ key: String) -> Value? { objects[index].values.first { $0.key == key } }
        var parents: [Int: Int] = [:]
        var frames: [Int: (x: Double, y: Double, width: Double, height: Double)] = [:]
        func doubles(_ value: Value, _ count: Int) -> [Double] {
            (0..<count).map { index in Double(bitPattern: value.bytes[(1 + 8 * index)..<(9 + 8 * index)].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }) }
        }
        for index in objects.indices {
            if let subviews = field(index, "UISubviews")?.reference {
                for child in references(objects[subviews]) { parents[child] = index }
            }
            if let center = field(index, "UICenter"), let bounds = field(index, "UIBounds"), center.bytes.count >= 17, bounds.bytes.count >= 33 {
                let (c, b) = (doubles(center, 2), doubles(bounds, 4))
                frames[index] = (c[0] - b[2] / 2, c[1] - b[3] / 2, b[2], b[3])
            }
        }
        var paths: [Int: [Int]] = [:]
        if let top = field(0, "UINibTopLevelObjectsKey")?.reference {
            var queue = references(objects[top]).enumerated().map { ($0.element, [$0.offset]) }
            while !queue.isEmpty {
                let (item, path) = queue.removeFirst()
                guard paths[item] == nil else { continue }
                paths[item] = path
                if let subviews = field(item, "UISubviews")?.reference {
                    queue += references(objects[subviews]).enumerated().map { ($0.element, path + [$0.offset]) }
                }
            }
        }
        func inOwner(_ item: Int, _ owner: Int) -> (x: Double, y: Double, width: Double, height: Double)? {
            if item == owner { return frames[owner].map { (0, 0, $0.width, $0.height) } }
            guard var frame = frames[item] else { return nil }
            var current = parents[item]
            while let ancestor = current, ancestor != owner {
                guard let outer = frames[ancestor] else { return nil }
                frame.x += outer.x
                frame.y += outer.y
                current = parents[ancestor]
            }
            return current == owner ? frame : nil
        }
        func position(_ item: Int, _ attribute: Int, _ owner: Int) -> Double? {
            let guide = objects[item].className == "UILayoutGuide" && scalar(objects[item], "UILayoutGuideOwningView") == Double(owner)
            guard let frame = guide && [1, 2, 5, 6, 7, 9].contains(attribute) ? inOwner(owner, owner) : inOwner(item, owner) else { return nil }
            switch attribute {
            case 1, 5: return frame.x
            case 2, 6: return frame.x + frame.width
            case 3: return frame.y
            case 4: return frame.y + frame.height
            case 7: return frame.width
            case 8: return frame.height
            case 9: return frame.x + frame.width / 2
            case 10: return frame.y + frame.height / 2
            default: return nil
            }
        }
        func satisfied(_ constraint: Object, _ owner: Int) -> Bool {
            guard let first = scalar(constraint, "NSFirstItem"), let firstAttribute = scalar(constraint, "NSFirstAttributeV2"),
                  let second = scalar(constraint, "NSSecondItem"), let secondAttribute = scalar(constraint, "NSSecondAttributeV2"),
                  let left = position(Int(first), Int(firstAttribute), owner), let right = position(Int(second), Int(secondAttribute), owner) else { return false }
            let difference = left - (right * (scalar(constraint, "NSMultiplier") ?? 1) + (scalar(constraint, "NSConstantV2") ?? 0))
            switch scalar(constraint, "NSRelation") ?? 0 {
            case -1: return difference <= 0.01
            case 1: return difference >= -0.01
            default: return abs(difference) <= 0.01
            }
        }
        func signature(_ index: Int) -> [Double?] {
            ["NSFirstItem", "NSFirstAttributeV2", "NSSecondAttributeV2", "NSRelation", "NSMultiplier"].map { scalar(objects[index], $0) }
        }
        var runs: [[Int]] = []
        for owner in objects.indices {
            guard let list = field(owner, "UIViewAutolayoutConstraints")?.reference else { continue }
            let listed = references(objects[list])
            var start = 0
            while start < listed.count {
                var end = start + 1
                while end < listed.count, signature(listed[end]) == signature(listed[start]) { end += 1 }
                let run = Array(listed[start..<end])
                let seconds = run.map { scalar(objects[$0], "NSSecondItem").map(Int.init) }
                if Set(seconds).count > 1, seconds.allSatisfy({ $0.map { paths[$0] != nil } ?? false }),
                   run.allSatisfy({ scalar(objects[$0], "NSPriority") == nil && satisfied(objects[$0], owner) }) {
                    runs.append(run.sorted { a, b in
                        let (pathA, pathB) = (paths[Int(scalar(objects[a], "NSSecondItem")!)]!, paths[Int(scalar(objects[b], "NSSecondItem")!)]!)
                        if pathA != pathB { return pathA.lexicographicallyPrecedes(pathB) }
                        return (scalar(objects[a], "NSConstantV2") ?? 0, scalar(objects[a], "NSSecondAttributeV2") ?? 0)
                            < (scalar(objects[b], "NSConstantV2") ?? 0, scalar(objects[b], "NSSecondAttributeV2") ?? 0)
                    })
                }
                start = end
            }
        }
        for run in runs {
            let members = Set(run)
            for index in objects.indices where ["NSArray", "NSMutableArray", "NSOrderedSet"].contains(objects[index].className) {
                let slots = objects[index].values.indices.filter { objects[index].values[$0].reference.map(members.contains) ?? false }
                guard slots.count == run.count else { continue }
                for (slot, member) in zip(slots, run) { objects[index].values[slot].reference = member }
            }
        }
    }

    private static func renumbered(_ objects: [Object]) -> [Object] {
        var order: [Int: Int] = [:]
        var stack = [0]
        while let item = stack.popLast() {
            guard order[item] == nil, item < objects.count else { continue }
            order[item] = order.count
            stack += objects[item].values.reversed().compactMap(\.reference)
        }
        return order.sorted { $0.value < $1.value }.map { item, _ in
            var object = objects[item]
            for index in object.values.indices { object.values[index].reference = object.values[index].reference.flatMap { order[$0] } }
            if ["NSSet", "NSMutableSet"].contains(object.className) {
                var elements = object.values.filter { $0.key.hasPrefix("NS.object.") }.compactMap(\.reference).sorted()
                for index in object.values.indices where object.values[index].key.hasPrefix("NS.object.") && object.values[index].reference != nil {
                    object.values[index].reference = elements.removeFirst()
                }
            }
            return Value.stripped(object)
        }
    }
}

extension NibTieComparison.Value {
    /// An object whose references and nested archives compare by their canonical forms alone.
    static func stripped(_ object: NibTieComparison.Object) -> NibTieComparison.Object {
        NibTieComparison.Object(className: object.className, values: object.values.map { value in
            var stripped = NibTieComparison.Value(key: value.key, type: value.type, bytes: value.reference != nil || value.nested != nil ? [] : value.bytes)
            stripped.reference = value.reference
            stripped.nested = value.nested
            return stripped
        })
    }
}
