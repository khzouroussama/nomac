import Foundation
import NomacCore
import NomacPlist

/// A value of an `NSKeyedArchiver` archive as DTX messages carry them (docs/formats/dtx.md
/// "Keyed archives"): Foundation's classes as Swift values, any other class as its keys.
public indirect enum Archived: Equatable, Sendable {
    case null
    case string(String)
    case integer(Int)
    case real(Double)
    case boolean(Bool)
    case data([UInt8])
    case array([Archived])
    case set([Archived])
    case dictionary([Pair])
    case uuid([UInt8])
    /// `NSURL`: its relative string, with no base.
    case url(String)
    /// `NSDate`: seconds since 2001-01-01.
    case date(Double)
    case object(Object)

    public struct Pair: Equatable, Sendable {
        public var key: Archived
        public var value: Archived

        public init(_ key: Archived, _ value: Archived) {
            self.key = key
            self.value = value
        }
    }

    /// An object of another class: its class chain, from its own class to `NSObject`, and what
    /// its `encodeWithCoder:` encodes, in order. Booleans, integers and reals are encoded inline
    /// (`encodeBool:forKey:`, `encodeInteger:forKey:`, `encodeDouble:forKey:`), everything else by
    /// reference (`encodeObject:forKey:`).
    public struct Object: Equatable, Sendable {
        public var classes: [String]
        public var fields: [Pair]

        public init(_ classes: [String], _ fields: [(String, Archived)]) {
            self.classes = classes
            self.fields = fields.map { Pair(.string($0.0), $0.1) }
        }

        public var className: String { classes.first ?? "" }

        public subscript(key: String) -> Archived? {
            fields.first { $0.key == .string(key) }?.value
        }
    }

    public static func keyed(_ entries: [(String, Archived)]) -> Archived {
        .dictionary(entries.map { Pair(.string($0.0), $0.1) })
    }

    public subscript(key: String) -> Archived? {
        switch self {
        case .dictionary(let pairs): pairs.first { $0.key == .string(key) }?.value
        case .object(let object): object[key]
        default: nil
        }
    }

    public var string: String? { if case .string(let value) = self { value } else { nil } }

    public var integer: Int? {
        switch self {
        case .integer(let value): value
        case .boolean(let value): value ? 1 : 0
        case .real(let value): Int(exactly: value)
        default: nil
        }
    }

    public var real: Double? {
        switch self {
        case .real(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }
}

/// `NSKeyedArchiver`'s and `NSKeyedUnarchiver`'s format (`$archiver`, `$version` 100000, `$top`
/// with `root`, `$objects` starting with `$null`), as libimobiledevice's, pymobiledevice3's and
/// go-ios's DTX implementations write and read it.
public enum KeyedArchive {
    public static func encode(_ value: Archived) -> [UInt8] {
        var writer = Writer()
        let root = writer.reference(value)
        let top = writer.append(.string("root"))
        let rootUID = writer.append(.uid(root))
        let topDictionary = writer.append(.dictionary(keys: [top], values: [rootUID]))
        let keys = ["$version", "$archiver", "$top", "$objects"].map { writer.append(.string($0)) }
        let version = writer.append(.integer(100_000))
        let archiver = writer.append(.string("NSKeyedArchiver"))
        let objects = writer.append(.array(writer.archiveObjects))
        let document = writer.append(.dictionary(keys: keys, values: [version, archiver, topDictionary, objects]))
        var flat = writer.flat
        flat.swapAt(0, document)
        let remap = { (index: Int) in index == 0 ? document : index == document ? 0 : index }
        flat = flat.map { object in
            switch object {
            case .array(let items): .array(items.map(remap))
            case .dictionary(let keys, let values): .dictionary(keys: keys.map(remap), values: values.map(remap))
            default: object
            }
        }
        return Array(BinaryPropertyList.data(objects: flat))
    }

    public static func decode(_ bytes: [UInt8]) throws -> Archived {
        let (objects, top) = try BinaryPropertyList.objects(from: bytes, path: "keyed archive")
        var reader = Reader(flat: objects)
        guard case .dictionary? = objects[safe: top],
              let archive = try reader.dictionary(top),
              let objectsIndex = archive["$objects"], case .array(let archiveObjects) = objects[objectsIndex],
              let topIndex = archive["$top"], let topEntries = try reader.dictionary(topIndex),
              let rootIndex = topEntries["root"], case .uid(let root) = objects[rootIndex] else {
            throw NomacError("not a keyed archive")
        }
        reader.archiveObjects = archiveObjects
        return try reader.value(uid: root, depth: 0)
    }

    /// Flat binary property list objects: the archive's `$objects` (each a reference into the
    /// flat list) and the property list objects around them.
    private struct Writer {
        var flat: [BinaryPropertyList.Object] = [.string("$null")]
        var archiveObjects: [Int] = [0]
        var classes: [[String]: Int] = [:]

        mutating func append(_ object: BinaryPropertyList.Object) -> Int {
            flat.append(object)
            return flat.count - 1
        }

        /// Appends `object` to `$objects` and returns its UID.
        private mutating func archive(_ object: BinaryPropertyList.Object) -> Int {
            archiveObjects.append(append(object))
            return archiveObjects.count - 1
        }

        private mutating func reserve() -> Int {
            archive(.string("$null"))
        }

        private mutating func fill(_ uid: Int, with object: BinaryPropertyList.Object) {
            flat[archiveObjects[uid]] = object
        }

        mutating func reference(_ value: Archived) -> Int {
            switch value {
            case .null: return 0
            case .string(let text): return archive(.string(text))
            case .integer(let number): return archive(.integer(number))
            case .real(let number): return archive(.real(number))
            case .boolean(let flag): return archive(.boolean(flag))
            case .data(let bytes): return archive(.data(bytes))
            case .array(let items): return collection(["NSArray", "NSObject"], items)
            case .set(let items): return collection(["NSSet", "NSObject"], items)
            case .dictionary(let pairs):
                let uid = reserve()
                let keys = pairs.map { reference($0.key) }
                let values = pairs.map { reference($0.value) }
                return finish(uid, ["NSDictionary", "NSObject"], [("NS.keys", .uids(keys)), ("NS.objects", .uids(values))])
            case .uuid(let bytes):
                return finish(reserve(), ["NSUUID", "NSObject"], [("NS.uuidbytes", .inline(.data(bytes)))])
            case .url(let relative):
                let uid = reserve()
                return finish(uid, ["NSURL", "NSObject"], [("NS.base", .uid(0)), ("NS.relative", .uid(reference(.string(relative))))])
            case .date(let seconds):
                return finish(reserve(), ["NSDate", "NSObject"], [("NS.time", .inline(.real(seconds)))])
            case .object(let item):
                let uid = reserve()
                var fields: [(String, Field)] = []
                for pair in item.fields {
                    let key = pair.key.string ?? ""
                    switch pair.value {
                    case .boolean(let flag): fields.append((key, .inline(.boolean(flag))))
                    case .integer(let number): fields.append((key, .inline(.integer(number))))
                    case .real(let number): fields.append((key, .inline(.real(number))))
                    default: fields.append((key, .uid(reference(pair.value))))
                    }
                }
                return finish(uid, item.classes, fields)
            }
        }

        enum Field {
            case uid(Int)
            case uids([Int])
            case inline(BinaryPropertyList.Object)
        }

        private mutating func collection(_ classes: [String], _ items: [Archived]) -> Int {
            let uid = reserve()
            let references = items.map { reference($0) }
            return finish(uid, classes, [("NS.objects", .uids(references))])
        }

        /// An object's dictionary: its number is taken before its contents', its class after.
        private mutating func finish(_ uid: Int, _ classes: [String], _ fields: [(String, Field)]) -> Int {
            let fields = fields + [("$class", .uid(classDescription(classes)))]
            var keys: [Int] = []
            var values: [Int] = []
            for (key, field) in fields {
                keys.append(append(.string(key)))
                switch field {
                case .uid(let target): values.append(append(.uid(target)))
                case .uids(let targets): values.append(append(.array(targets.map { append(.uid($0)) })))
                case .inline(let object): values.append(append(object))
                }
            }
            fill(uid, with: .dictionary(keys: keys, values: values))
            return uid
        }

        private mutating func classDescription(_ chain: [String]) -> Int {
            if let uid = classes[chain] { return uid }
            let names = chain.map { append(.string($0)) }
            let keys = [append(.string("$classname")), append(.string("$classes"))]
            let values = [append(.string(chain.first ?? "NSObject")), append(.array(names))]
            let uid = archive(.dictionary(keys: keys, values: values))
            classes[chain] = uid
            return uid
        }
    }

    private struct Reader {
        let flat: [BinaryPropertyList.Object]
        var archiveObjects: [Int] = []

        var malformed: NomacError { NomacError("malformed keyed archive") }

        func dictionary(_ index: Int) throws -> [String: Int]? {
            guard case .dictionary(let keys, let values)? = flat[safe: index] else { return nil }
            var result: [String: Int] = [:]
            for (key, value) in zip(keys, values) {
                guard case .string(let name)? = flat[safe: key] else { throw malformed }
                result[name] = value
            }
            return result
        }

        func value(uid: Int, depth: Int) throws -> Archived {
            guard depth < 256, let index = archiveObjects[safe: uid] else { throw malformed }
            switch flat[safe: index] {
            case .string("$null")? where uid == 0: return .null
            case .string(let text)?: return .string(text)
            case .integer(let number)?: return .integer(number)
            case .real(let number)?: return .real(number)
            case .float(let number)?: return .real(Double(number))
            case .boolean(let flag)?: return .boolean(flag)
            case .data(let bytes)?: return .data(bytes)
            case .date(let seconds)?: return .date(seconds)
            case .dictionary?: return try object(index, depth: depth)
            default: throw malformed
            }
        }

        func field(_ index: Int, depth: Int) throws -> Archived {
            switch flat[safe: index] {
            case .uid(let target)?: return try value(uid: target, depth: depth + 1)
            case .boolean(let flag)?: return .boolean(flag)
            case .integer(let number)?: return .integer(number)
            case .real(let number)?: return .real(number)
            case .float(let number)?: return .real(Double(number))
            case .string(let text)?: return .string(text)
            case .data(let bytes)?: return .data(bytes)
            case .array(let items)?: return .array(try items.map { try field($0, depth: depth) })
            default: throw malformed
            }
        }

        func references(_ entries: [String: Int], _ key: String, depth: Int) throws -> [Archived] {
            guard let index = entries[key] else { return [] }
            guard case .array(let items)? = flat[safe: index] else { throw malformed }
            return try items.map { try field($0, depth: depth) }
        }

        func object(_ index: Int, depth: Int) throws -> Archived {
            guard let entries = try dictionary(index), let classIndex = entries["$class"],
                  case .uid(let classUID)? = flat[safe: classIndex], let classObject = archiveObjects[safe: classUID],
                  let description = try dictionary(classObject), let chainIndex = description["$classes"],
                  case .array(let chainItems)? = flat[safe: chainIndex] else { throw malformed }
            let chain = try chainItems.map { item -> String in
                guard case .string(let name)? = flat[safe: item] else { throw malformed }
                return name
            }
            switch chain.first {
            case "NSArray", "NSMutableArray", "NSOrderedSet", "NSMutableOrderedSet":
                return .array(try references(entries, "NS.objects", depth: depth))
            case "NSSet", "NSMutableSet":
                return .set(try references(entries, "NS.objects", depth: depth))
            case "NSDictionary", "NSMutableDictionary":
                let keys = try references(entries, "NS.keys", depth: depth)
                let values = try references(entries, "NS.objects", depth: depth)
                guard keys.count == values.count else { throw malformed }
                return .dictionary(zip(keys, values).map { Archived.Pair($0, $1) })
            case "NSString", "NSMutableString":
                guard let text = entries["NS.string"].map({ try? field($0, depth: depth) }) ?? nil else { throw malformed }
                return text
            case "NSData", "NSMutableData":
                guard let data = entries["NS.data"].map({ try? field($0, depth: depth) }) ?? nil else { throw malformed }
                return data
            case "NSUUID", "__NSConcreteUUID":
                guard let index = entries["NS.uuidbytes"], case .data(let bytes) = try field(index, depth: depth) else { throw malformed }
                return .uuid(bytes)
            case "NSURL":
                guard let index = entries["NS.relative"], case .string(let relative) = try field(index, depth: depth) else { throw malformed }
                if let baseIndex = entries["NS.base"], case .url(let base) = try field(baseIndex, depth: depth) {
                    return .url(base.hasSuffix("/") || relative.hasPrefix("/") ? base + relative : base + "/" + relative)
                }
                return .url(relative)
            case "NSDate", "__NSDate":
                guard let index = entries["NS.time"], let seconds = try field(index, depth: depth).real else { throw malformed }
                return .date(seconds)
            case "NSNull":
                return .null
            default:
                let keys = entries.keys.filter { $0 != "$class" }.sorted()
                return .object(Archived.Object(chain, try keys.map { ($0, try field(entries[$0]!, depth: depth)) }))
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
