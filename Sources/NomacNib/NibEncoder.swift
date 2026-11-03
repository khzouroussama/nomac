import Foundation
import NomacCore
import NomacPlist

/// An object a nib archives. Objects are archived once, by identity.
protocol NibArchivable: AnyObject {
    /// The archived class.
    var className: String { get }
    /// The classes the runtime may use instead, entered into the class table after it.
    var fallbackClassNames: [String] { get }

    func encode(to encoder: NibEncoder) throws
}

extension NibArchivable {
    var fallbackClassNames: [String] { [] }
}

/// Archives objects as ibtool's encoder does (docs/formats/nib.md "Encoding"): depth first, each
/// object numbered and its values written when first encoded, classes when their first object is
/// numbered; the key table is built afterwards from the values written.
final class NibEncoder {
    private var objects: [NibObject] = []
    /// Identities are only unique while their objects live, so every numbered object is kept
    /// until the archive is written.
    private var numbered: [NibArchivable] = []
    private var indexes: [ObjectIdentifier: Int] = [:]
    /// Equal numbers are one object, the first encoded, whatever their types: an integer 1, a real
    /// 1 and YES are one `NSNumber` (nib-experiments `udra-bool-int-one`, `udra-label-real-17`,
    /// `udra-button-int-zero`, `button-two`).
    private var numbers: [Double: Int] = [:]
    private var classes = NibClassTable()
    private var current = 0
    /// Conditional references (`encodeConditionalObject:`), resolved once everything is encoded.
    private var conditionals: [(object: Int, value: Int, target: NibArchivable)] = []

    /// The archive of `root` and everything it refers to.
    static func archive(_ root: NibArchivable) throws -> Data {
        let encoder = NibEncoder()
        _ = try encoder.number(root)
        for (object, value, target) in encoder.conditionals {
            if let index = encoder.indexes[ObjectIdentifier(target)] {
                encoder.objects[object].values[value].value = .object(index)
            }
        }
        return NibArchive.data(objects: encoder.objects, keys: try encoder.keyTable(), classes: encoder.classes)
    }

    /// The key of collection elements.
    static let elementKey = "UINibEncoderEmptyKey"

    func encode(_ value: NibValue, forKey key: String) {
        objects[current].values.append((key, value))
    }

    func encode(_ object: NibArchivable?, forKey key: String) throws {
        let value = try object.map { NibValue.object(try number($0)) } ?? .null
        objects[current].values.append((key, value))
    }

    /// A reference that does not encode its object: it names the object's number if something else
    /// encodes it, and nil otherwise (a navigation item's bar: nib-experiments `sb-nav*`).
    func encodeConditional(_ object: NibArchivable, forKey key: String) {
        conditionals.append((current, objects[current].values.count, object))
        objects[current].values.append((key, .null))
    }

    /// The number of an object already encoded.
    func number(of object: NibArchivable) throws -> Int {
        guard let index = indexes[ObjectIdentifier(object)] else {
            throw NomacError("nomac's nib encoder: a \(object.className) is referred to before it is encoded")
        }
        return index
    }

    private func number(_ object: NibArchivable) throws -> Int {
        if let index = indexes[ObjectIdentifier(object)] { return index }
        let numeric = (object as? NibNumber)?.numericValue
        if let numeric, let index = numbers[numeric] {
            numbered.append(object)
            indexes[ObjectIdentifier(object)] = index
            return index
        }
        let index = objects.count
        numbered.append(object)
        indexes[ObjectIdentifier(object)] = index
        if let numeric { numbers[numeric] = index }
        objects.append(NibObject(classIndex: classes.index(of: object.className, fallbacks: object.fallbackClassNames), values: []))
        let parent = current
        current = index
        defer { current = parent }
        try object.encode(to: self)
        return index
    }

    /// The keys in table order: each key entered when its value is first written, depth first from
    /// the root, an object's values where it is numbered; `UINibEncoderEmptyKey` takes its bucket at
    /// its first use but counts toward what the table holds only when the archive is finished
    /// (nib-experiments `ladder-*`, every observed xib and storyboard nib).
    private func keyTable() throws -> [String] {
        var table = FoundationHashTable()
        var next = 1
        func visit(_ index: Int) throws {
            for (key, value) in objects[index].values {
                try table.insert(key, counted: key != Self.elementKey)
                if case .object(let child) = value, child == next {
                    next += 1
                    try visit(child)
                }
            }
        }
        try visit(0)
        try table.count(Self.elementKey)
        return table.keys
    }
}

/// `NSArray` and `NSMutableArray`: `NSInlinedValue`, then one `UINibEncoderEmptyKey` per element.
final class NibArray: NibArchivable {
    let mutable: Bool
    var elements: [NibArchivable]

    init(_ elements: [NibArchivable], mutable: Bool = false) {
        self.elements = elements
        self.mutable = mutable
    }

    var className: String { mutable ? "NSMutableArray" : "NSArray" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.boolean(true), forKey: "NSInlinedValue")
        for element in elements {
            try encoder.encode(element, forKey: NibEncoder.elementKey)
        }
    }
}

/// `NSString`, or `NSMutableString`: its UTF-8 bytes as `NS.bytes`.
final class NibString: NibArchivable {
    let value: String
    let mutable: Bool

    private init(value: String, mutable: Bool) {
        self.value = value
        self.mutable = mutable
    }

    convenience init(_ value: String) {
        self.init(value: value, mutable: false)
    }

    static func mutable(_ value: String) -> NibString {
        NibString(value: value, mutable: true)
    }

    var className: String { mutable ? "NSMutableString" : "NSString" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.data(Array(value.utf8)), forKey: "NS.bytes")
    }
}

/// A placeholder: `UIProxyObject` with its identifier.
final class NibProxy: NibArchivable {
    /// A button's segue's upstream placeholder is numbered once its view nib is compiled.
    var identifier: NibString

    init(identifier: String) {
        self.identifier = NibString(identifier)
    }

    /// A placeholder sharing another's identifier string (a navigation controller nib's two
    /// `UIStoryboardPlaceholder`s).
    init(sharing identifier: NibString) {
        self.identifier = identifier
    }

    var className: String { "UIProxyObject" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(identifier, forKey: "UIProxiedObjectIdentifier")
    }
}

/// The archive's root: the nib's top-level objects, all its objects, its connections, its trait
/// storage lists, its accessibility configurations, its key-value pairs (user-defined runtime
/// attributes, switches' frames), and its visible windows, empty in every nib compiled so far;
/// every empty list is one shared empty array.
final class NibRoot: NibArchivable {
    let topLevelObjects: NibArray
    let allObjects: NibArray
    let connections: [NibArchivable]
    let accessibilityConfigurations: [NibAccessibilityConfiguration]
    let traitStorageLists: [NibArchivable]
    let keyValuePairs: [NibArchivable]
    /// The nib's one empty array, which objects of the nib may share (a navigation item's
    /// `UICenterItemGroups`).
    let empty: NibArray

    init(topLevelObjects: [NibArchivable], allObjects: [NibArchivable], connections: [NibArchivable] = [],
         accessibilityConfigurations: [NibAccessibilityConfiguration] = [], traitStorageLists: [NibArchivable] = [], keyValuePairs: [NibArchivable] = [],
         empty: NibArray = NibArray([])) {
        self.topLevelObjects = NibArray(topLevelObjects)
        self.allObjects = NibArray(allObjects)
        self.connections = connections
        self.accessibilityConfigurations = accessibilityConfigurations
        self.traitStorageLists = traitStorageLists
        self.keyValuePairs = keyValuePairs
        self.empty = empty
    }

    var className: String { "NSObject" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(topLevelObjects, forKey: "UINibTopLevelObjectsKey")
        try encoder.encode(allObjects, forKey: "UINibObjectsKey")
        try encoder.encode(connections.isEmpty ? empty : NibArray(connections), forKey: "UINibConnectionsKey")
        try encoder.encode(empty, forKey: "UINibVisibleWindowsKey")
        try encoder.encode(accessibilityConfigurations.isEmpty ? empty : NibAccessibilityConfigurations(accessibilityConfigurations),
                           forKey: "UINibAccessibilityConfigurationsKey")
        try encoder.encode(traitStorageLists.isEmpty ? empty : NibArray(traitStorageLists), forKey: "UINibTraitStorageListsKey")
        try encoder.encode(keyValuePairs.isEmpty ? empty : NibArray(keyValuePairs), forKey: "UINibKeyValuePairsKey")
        encoder.encode(.integer(1), forKey: "IBUINibLNEVersionKey")
    }
}
