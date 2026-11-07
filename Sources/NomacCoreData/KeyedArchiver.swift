import NomacCore
import NomacPlist

/// An object `NSKeyedArchiver` archives: its class chain and what its `encode(with:)` encodes.
protocol KeyedArchivable: AnyObject {
    /// `$classes`, from the object's class to `NSObject`.
    var archivedClassNames: [String] { get }
    func encode(to archiver: KeyedArchiver) throws
}

/// What `encodeObject:forKey:` is given.
enum ArchivedItem {
    case string(String)
    /// A string that is one object only where it is the same `StringObject`, as tools that do not
    /// intern their strings hold them (mapc); a tagged one is still one object per text.
    case stringObject(StringObject)
    /// `NSData`, one object where it is the same `DataObject`.
    case data(DataObject)
    case number(ArchivedNumber)
    case object(KeyedArchivable)
}

/// An `NSNumber` (or `CFBoolean`) archived as an object.
enum ArchivedNumber: Hashable {
    case integer(Int, bits: Int)
    case float(Float)
    case double(Double)
    case boolean(Bool)
}

/// `NSKeyedArchiver` as a Mac runs it, with Core Foundation's binary property list writer
/// (docs/formats/coredata.md "Keyed archives"): objects numbered in the order they are first
/// encoded, a conditional object's number reserved at its first reference, each class's
/// description after the first object of that class has been encoded, and each object's keys in
/// the order of an immutable copy of a mutable dictionary built in encoding order, `$class` last.
/// Strings are one object per value, as momc interns them, and tagged ones are one object with
/// every equal tagged string; numbers are one object per type and value.
final class KeyedArchiver {
    enum Value {
        case uid(Int)
        case boolean(Bool)
        case int32(Int)
        case int64(Int)
        case double(Double)
        case uids([Int])
        case bytes([UInt8])
    }

    private enum Slot {
        case reserved
        case null
        case string(String)
        case stringObject(String)
        case data([UInt8])
        case number(ArchivedNumber)
        case object([(String, Value)])
        case classDescription([String])
    }

    private var slots: [Slot] = [.null]
    private var objectUIDs: [ObjectIdentifier: Int] = [:]
    private var retained: [AnyObject] = []
    private var stringUIDs: [String: Int] = [:]
    private var numberUIDs: [ArchivedNumber: Int] = [:]
    private var classUIDs: [String: Int] = [:]
    private var frames: [[(String, Value)]] = []

    /// Class names longer than a tagged pointer that are one string wherever they appear
    /// (Foundation's), the archive's strings of the same text included (wikipedia's value class
    /// name `NSDictionary`); the others are a new string at each use, `$classname` and `$classes`
    /// included, unless tagged (every class description of the 174 observed `.mom` files).
    private static let sharedClassNames: Set<String> = [
        "NSDictionary", "NSMutableDictionary", "NSMutableArray", "NSPredicate", "NSComparisonPredicate", "NSExpression",
        "NSConstantValueExpression", "NSSelfExpression", "NSFunctionExpression", "NSKeyPathExpression",
        "NSKeyPathSpecifierExpression", "NSPredicateOperator", "NSStringPredicateOperator", "NSMatchingPredicateOperator",
    ]

    func encode(_ item: ArchivedItem?, forKey key: String) throws {
        frames[frames.count - 1].append((key, .uid(try reference(item))))
    }

    func encode(_ string: String?, forKey key: String) throws {
        try encode(string.map(ArchivedItem.string), forKey: key)
    }

    func encode(_ object: KeyedArchivable?, forKey key: String) throws {
        try encode(object.map(ArchivedItem.object), forKey: key)
    }

    func encodeConditional(_ object: KeyedArchivable?, forKey key: String) {
        guard let object else {
            frames[frames.count - 1].append((key, .uid(0)))
            return
        }
        let uid = objectUIDs[ObjectIdentifier(object)] ?? reserve(object)
        frames[frames.count - 1].append((key, .uid(uid)))
    }

    func encode(_ value: Bool, forKey key: String) {
        frames[frames.count - 1].append((key, .boolean(value)))
    }

    func encodeInt32(_ value: Int, forKey key: String) {
        frames[frames.count - 1].append((key, .int32(value)))
    }

    func encodeInteger(_ value: Int, forKey key: String) {
        frames[frames.count - 1].append((key, .int64(value)))
    }

    func encode(_ value: Double, forKey key: String) {
        frames[frames.count - 1].append((key, .double(value)))
    }

    func encodeBytes(_ bytes: [UInt8], forKey key: String) {
        frames[frames.count - 1].append((key, .bytes(bytes)))
    }

    /// The `NS.keys` and `NS.objects` of collections: an array of references.
    func encodeArray(_ items: [ArchivedItem], forKey key: String) throws {
        var uids: [Int] = []
        for item in items {
            uids.append(try reference(item))
        }
        frames[frames.count - 1].append((key, .uids(uids)))
    }

    /// The archive of `root`, as `archivedDataWithRootObject:` writes it.
    static func archive(_ root: KeyedArchivable) throws -> [UInt8] {
        try archive(item: .object(root))
    }

    static func archive(item root: ArchivedItem) throws -> [UInt8] {
        let archiver = KeyedArchiver()
        let top = try archiver.reference(root)
        if archiver.slots.contains(where: { if case .reserved = $0 { true } else { false } }) {
            throw NomacError("a conditionally encoded object of the model is never encoded (BACKLOG B-257)")
        }
        let objects = try archiver.slots.map { try archiver.node($0) }
        let document = CFPropertyListWriter.Node.dictionary([
            (.constant("$version"), .integer(100_000, shared: "int32")),
            (.constant("$archiver"), .constant("NSKeyedArchiver")),
            (.constant("$top"), .dictionary([(.constant("root"), .uid(top))])),
            (.constant("$objects"), .array(objects)),
        ])
        return CFPropertyListWriter.data(document)
    }

    private func reference(_ item: ArchivedItem?) throws -> Int {
        switch item {
        case nil:
            return 0
        case .data(let object):
            if let uid = objectUIDs[ObjectIdentifier(object)] { return uid }
            retained.append(object)
            objectUIDs[ObjectIdentifier(object)] = slots.count
            slots.append(.data(object.bytes))
            return slots.count - 1
        case .stringObject(let object) where TaggedPointerString.fits(object.text):
            return try reference(.string(object.text))
        case .stringObject(let object):
            if let uid = objectUIDs[ObjectIdentifier(object)] { return uid }
            retained.append(object)
            objectUIDs[ObjectIdentifier(object)] = slots.count
            slots.append(.stringObject(object.text))
            return slots.count - 1
        case .string(let string):
            if let uid = stringUIDs[string] { return uid }
            stringUIDs[string] = slots.count
            slots.append(.string(string))
            return slots.count - 1
        case .number(let number):
            if let uid = numberUIDs[number] { return uid }
            numberUIDs[number] = slots.count
            slots.append(.number(number))
            return slots.count - 1
        case .object(let object):
            if let uid = objectUIDs[ObjectIdentifier(object)] {
                if case .reserved = slots[uid] {
                    try encodeContents(of: object, at: uid)
                }
                return uid
            }
            let uid = reserve(object)
            try encodeContents(of: object, at: uid)
            return uid
        }
    }

    private func reserve(_ object: KeyedArchivable) -> Int {
        retained.append(object)
        objectUIDs[ObjectIdentifier(object)] = slots.count
        slots.append(.reserved)
        return slots.count - 1
    }

    private func encodeContents(of object: KeyedArchivable, at uid: Int) throws {
        slots[uid] = .object([])
        frames.append([])
        try object.encode(to: self)
        var entries = frames.removeLast()
        let names = object.archivedClassNames
        let classUID: Int
        if let known = classUIDs[names[0]] {
            classUID = known
        } else {
            classUID = slots.count
            classUIDs[names[0]] = classUID
            slots.append(.classDescription(names))
        }
        entries.append(("$class", .uid(classUID)))
        slots[uid] = .object(entries)
    }

    private func node(_ slot: Slot) throws -> CFPropertyListWriter.Node {
        switch slot {
        case .reserved:
            throw NomacError("a conditionally encoded object of the model is never encoded (BACKLOG B-257)")
        case .null:
            return .constant("$null")
        case .string(let string):
            return .string(string, shared: TaggedPointerString.fits(string) ? "tagged" : "archived")
        case .stringObject(let string):
            return .string(string, shared: nil)
        case .data(let bytes):
            return .data(bytes)
        case .number(let number):
            return Self.node(number)
        case .object(let entries):
            return try dictionary(entries.map { ($0.0, Self.node($0.1)) })
        case .classDescription(let names):
            let name: (String) -> CFPropertyListWriter.Node = { name in
                if TaggedPointerString.fits(name) { return .string(name, shared: "tagged") }
                return .string(name, shared: Self.sharedClassNames.contains(name) ? "archived" : nil)
            }
            return try dictionary([("$classname", name(names[0])), ("$classes", .array(names.map(name)))])
        }
    }

    /// An object's keys: a mutable dictionary filled in encoding order, then copied (196 of 196
    /// archives of self-written classes with 1 to 49 keys, `NSKeyedArchiver` on macOS 27.0.1).
    private func dictionary(_ entries: [(String, CFPropertyListWriter.Node)]) throws -> CFPropertyListWriter.Node {
        let values = Dictionary(entries, uniquingKeysWith: { _, last in last })
        let keys = try FoundationHashTable.inserting(entries.map(\.0)).copied().keys
        return .dictionary(keys.map { (.constant($0), values[$0]!) })
    }

    private static func node(_ value: Value) -> CFPropertyListWriter.Node {
        switch value {
        case .uid(let uid): .uid(uid)
        case .boolean(let boolean): .boolean(boolean)
        case .int32(let integer): .integer(integer, shared: "int32")
        case .int64(let integer): .integer(integer, shared: "int64")
        case .double(let double): .double(double, shared: true)
        case .uids(let uids): .array(uids.map { .uid($0) })
        case .bytes(let bytes): .data(bytes)
        }
    }

    private static func node(_ number: ArchivedNumber) -> CFPropertyListWriter.Node {
        switch number {
        case .integer(let integer, let bits): .integer(integer, shared: "int\(bits)")
        case .float(let float): .float(float)
        case .double(let double): .double(double, shared: true)
        case .boolean(let boolean): .boolean(boolean)
        }
    }
}

/// A string held as one object (``ArchivedItem/stringObject(_:)``).
final class StringObject {
    let text: String

    init(_ text: String) {
        self.text = text
    }
}

/// Bytes held as one `NSData` object (``ArchivedItem/data(_:)``).
final class DataObject {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }
}
