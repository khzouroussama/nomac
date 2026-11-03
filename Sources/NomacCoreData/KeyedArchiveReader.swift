import NomacCore

/// Reads an `NSKeyedArchiver` archive (a binary property list with UIDs), as mapping models embed
/// their source and destination models (docs/formats/coredata.md "Mapping models").
struct KeyedArchiveReader {
    enum Value {
        case null
        case boolean(Bool)
        case integer(Int)
        case real(Double)
        case string(String)
        case data([UInt8])
        case uid(Int)
        case array([Value])
        case dictionary([String: Value])
    }

    private let objects: [Value]

    init(_ bytes: [UInt8]) throws {
        let plist = try Self.propertyList(bytes)
        guard case .dictionary(let top) = plist, case .array(let objects)? = top["$objects"] else {
            throw NomacError("not a keyed archive")
        }
        self.objects = objects
        guard case .dictionary(let roots)? = top["$top"], case .uid(let root)? = roots["root"] else {
            throw NomacError("a keyed archive without a root object")
        }
        self.root = root
    }

    let root: Int

    /// The object a UID names; `$null` is `.null`.
    func object(_ uid: Int) -> Value {
        guard uid > 0, uid < objects.count else { return .null }
        return objects[uid]
    }

    /// The value of `key` in the archived object `uid`, through UIDs.
    func value(_ uid: Int, _ key: String) -> Value {
        guard case .dictionary(let fields) = object(uid), let value = fields[key] else { return .null }
        if case .uid(let target) = value { return object(target) }
        return value
    }

    /// The UID `key` holds in the archived object `uid`.
    func reference(_ uid: Int, _ key: String) -> Int? {
        guard case .dictionary(let fields) = object(uid), case .uid(let target)? = fields[key], target > 0 else { return nil }
        return target
    }

    /// Whether `uid` is an archived object (with a `$class`), not a string, number or data.
    func isObject(_ uid: Int) -> Bool {
        reference(uid, "$class") != nil
    }

    func className(_ uid: Int) -> String? {
        guard let classUID = reference(uid, "$class"), case .string(let name) = value(classUID, "$classname") else { return nil }
        return name
    }

    func string(_ uid: Int, _ key: String) -> String? {
        if case .string(let string) = value(uid, key) { return string }
        return nil
    }

    /// An archived `NSDictionary`: its keys' strings and its values' UIDs.
    func dictionary(_ uid: Int) -> [(key: String, value: Int)] {
        guard case .dictionary(let fields) = object(uid), case .array(let keys)? = fields["NS.keys"],
              case .array(let values)? = fields["NS.objects"] else { return [] }
        return zip(keys, values).compactMap { key, value in
            guard case .uid(let k) = key, case .string(let name) = object(k), case .uid(let v) = value else { return nil }
            return (name, v)
        }
    }

    /// An archived `NSArray`'s elements' UIDs.
    func array(_ uid: Int) -> [Int] {
        guard case .dictionary(let fields) = object(uid), case .array(let elements)? = fields["NS.objects"] else { return [] }
        return elements.compactMap { if case .uid(let element) = $0 { element } else { nil } }
    }

    private static func propertyList(_ bytes: [UInt8]) throws -> Value {
        guard bytes.count > 40, Array(bytes.prefix(8)) == Array("bplist00".utf8) else {
            throw NomacError("not a binary property list")
        }
        let trailer = bytes.suffix(32).map { $0 }
        let offsetSize = Int(trailer[6]), referenceSize = Int(trailer[7])
        let count = number(trailer[8..<16]), top = number(trailer[16..<24]), table = number(trailer[24..<32])
        guard table + count * offsetSize <= bytes.count else { throw NomacError("a truncated binary property list") }
        let offsets = (0..<count).map { number(bytes[(table + $0 * offsetSize)..<(table + ($0 + 1) * offsetSize)]) }

        func length(_ position: Int) throws -> (Int, Int) {
            let low = Int(bytes[position] & 0x0F)
            guard low == 0x0F else { return (low, position + 1) }
            let size = 1 << Int(bytes[position + 1] & 0x0F)
            return (number(bytes[(position + 2)..<(position + 2 + size)]), position + 2 + size)
        }
        func reference(_ position: Int, _ index: Int) -> Int {
            number(bytes[(position + index * referenceSize)..<(position + (index + 1) * referenceSize)])
        }
        func value(_ index: Int, depth: Int) throws -> Value {
            guard index < offsets.count, depth < 64 else { throw NomacError("a malformed binary property list") }
            let position = offsets[index]
            let marker = bytes[position]
            switch marker >> 4 {
            case 0x0: return marker == 0x09 ? .boolean(true) : marker == 0x08 ? .boolean(false) : .null
            case 0x1:
                let size = 1 << Int(marker & 0x0F)
                let raw = number(bytes[(position + 1)..<(position + 1 + size)])
                return .integer(size == 8 ? Int(bitPattern: UInt(raw)) : raw)
            case 0x2:
                let size = 1 << Int(marker & 0x0F)
                let raw = UInt64(number(bytes[(position + 1)..<(position + 1 + size)]))
                return .real(size == 4 ? Double(Float(bitPattern: UInt32(raw))) : Double(bitPattern: raw))
            case 0x4:
                let (count, start) = try length(position)
                return .data(Array(bytes[start..<(start + count)]))
            case 0x5:
                let (count, start) = try length(position)
                return .string(String(decoding: bytes[start..<(start + count)], as: UTF8.self))
            case 0x6:
                let (count, start) = try length(position)
                let units = (0..<count).map { UInt16(bytes[start + 2 * $0]) << 8 | UInt16(bytes[start + 2 * $0 + 1]) }
                return .string(String(decoding: units, as: UTF16.self))
            case 0x8:
                return .uid(number(bytes[(position + 1)..<(position + 2 + Int(marker & 0x0F))]))
            case 0xA:
                let (count, start) = try length(position)
                return .array(try (0..<count).map { try value(reference(start, $0), depth: depth + 1) })
            case 0xD:
                let (count, start) = try length(position)
                var entries: [String: Value] = [:]
                for index in 0..<count {
                    guard case .string(let key) = try value(reference(start, index), depth: depth + 1) else {
                        throw NomacError("a dictionary key that is not a string")
                    }
                    entries[key] = try value(reference(start, count + index), depth: depth + 1)
                }
                return .dictionary(entries)
            default:
                throw NomacError("binary property list objects of type \(marker >> 4) are not read")
            }
        }
        return try value(top, depth: 0)
    }

    private static func number(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { $0 << 8 | Int($1) }
    }
}
