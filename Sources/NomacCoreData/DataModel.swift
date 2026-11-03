import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import NomacCore

/// A Core Data model version as its `contents` file describes it (`.xcdatamodel/contents`). Only
/// what momc's outputs were observed for is read; anything else is refused with the BACKLOG item
/// that covers it (docs/formats/coredata.md).
public struct DataModel: Sendable {
    public var entities: [Entity]
    public var fetchRequests: [FetchRequest]
    /// The Xcode major version of `minimumToolsVersion`, nil for `Automatic`.
    public var minimumToolsVersion: Int?
    /// `sourceLanguage`: the language of generated classes.
    public var sourceLanguage: String?

    /// Xcode 8.0 or older gives indexed attributes fetch indexes of their own name and no entity
    /// (coredata-experiments `indexed-tools-*`).
    public var hasLegacyIndexes: Bool { (minimumToolsVersion ?? .max) < 9 }

    /// Each entity's attributes by name, then its relationships by name: the order of momc's
    /// archives and warnings (coredata-experiments `relationships-order`, `sort-order`).
    func sortingProperties() throws -> DataModel {
        var model = self
        model.entities = try entities.map { entity in
            var entity = entity
            let attributes = entity.properties.filter(\.isAttribute)
            let relationships = entity.properties.filter { !$0.isAttribute }
            entity.properties = try ModelNameOrder.sorted(attributes, by: \.name) + ModelNameOrder.sorted(relationships, by: \.name)
            return entity
        }
        return model
    }

    /// The entities by name, as momc archives them; its warnings keep the file's order
    /// (coredata-experiments `relationships-order`, `sort-order`).
    func sortingEntities() throws -> DataModel {
        var model = self
        model.entities = try ModelNameOrder.sorted(entities, by: \.name)
        return model
    }

    public struct Entity: Sendable {
        public var name: String
        public var className: String?
        public var parentName: String?
        public var isAbstract: Bool
        public var versionHashModifier: String?
        public var renamingIdentifier: String?
        public var codeGeneration: CodeGeneration?
        /// Attributes and relationships in the file's order.
        public var properties: [Property]
        public var uniquenessConstraints: [[String]]
        public var fetchIndexes: [FetchIndex]
        public var compoundIndexes: [[String]]
        public var userInfo: [(String, String)]
        public var isSyncable: Bool
    }

    public enum Property: Sendable {
        case attribute(Attribute)
        case relationship(Relationship)

        public var name: String {
            switch self {
            case .attribute(let attribute): attribute.name
            case .relationship(let relationship): relationship.name
            }
        }

        public var isAttribute: Bool {
            if case .attribute = self { return true }
            return false
        }

        public var isTransient: Bool {
            switch self {
            case .attribute(let attribute): attribute.isTransient
            case .relationship(let relationship): relationship.isTransient
            }
        }

        public var renamingIdentifier: String? {
            switch self {
            case .attribute(let attribute): attribute.renamingIdentifier
            case .relationship(let relationship): relationship.renamingIdentifier
            }
        }
    }

    public struct Attribute: Sendable {
        public var name: String
        public var type: AttributeType
        public var isOptional: Bool
        public var isTransient: Bool
        public var defaultValue: String?
        public var defaultDateTimeInterval: String?
        public var usesScalarValueType: Bool?
        public var minimum: String?
        public var maximum: String?
        public var isIndexed: Bool
        public var valueTransformerName: String?
        public var customClassName: String?
        public var renamingIdentifier: String?
        public var allowsExternalBinaryDataStorage: Bool
        public var userInfo: [(String, String)]
        public var isSyncable: Bool
    }

    public struct Relationship: Sendable {
        public var name: String
        public var isOptional: Bool
        public var isTransient: Bool
        public var isToMany: Bool
        public var isOrdered: Bool
        public var minCount: Int
        public var maxCount: Int
        public var deleteRule: DeleteRule
        public var destination: String
        public var inverseName: String?
        public var renamingIdentifier: String?
        public var isSyncable: Bool
    }

    public struct FetchIndex: Sendable {
        public var name: String
        public var elements: [(property: String, ascending: Bool)]
    }

    public struct FetchRequest: Sendable {
        public var name: String
        public var entity: String
    }

    /// `NSAttributeType`, with the names the model file uses.
    public enum AttributeType: Int, Sendable {
        case undefined = 0
        case integer16 = 100
        case integer32 = 200
        case integer64 = 300
        case decimal = 400
        case double = 500
        case float = 600
        case string = 700
        case boolean = 800
        case date = 900
        case binary = 1000
        case uuid = 1100
        case uri = 1200
        case transformable = 1800

        init?(fileName: String) {
            switch fileName {
            case "Integer 16": self = .integer16
            case "Integer 32": self = .integer32
            case "Integer 64": self = .integer64
            case "Decimal": self = .decimal
            case "Double": self = .double
            case "Float": self = .float
            case "String": self = .string
            case "Boolean": self = .boolean
            case "Date": self = .date
            case "Binary": self = .binary
            case "UUID": self = .uuid
            case "URI": self = .uri
            case "Transformable": self = .transformable
            default: return nil
            }
        }
    }

    /// `codeGenerationType`: a class and its properties, or the properties only.
    public enum CodeGeneration: String, Sendable {
        case `class`
        case category
    }

    /// `NSDeleteRule`.
    public enum DeleteRule: Int, Sendable {
        case noAction = 0
        case nullify = 1
        case cascade = 2
        case deny = 3

        init?(fileName: String) {
            switch fileName {
            case "No Action": self = .noAction
            case "Nullify": self = .nullify
            case "Cascade": self = .cascade
            case "Deny": self = .deny
            default: return nil
            }
        }
    }
}

extension DataModel {
    /// Reads a version's `contents` file.
    public static func read(contentsOf path: String) throws -> DataModel {
        let root = try ModelElement.read(Data(contentsOf: URL(fileURLWithPath: path)), path: path)
        guard root.name == "model" else {
            throw NomacError("\(path) is not a Core Data model: its root element is <\(root.name)>", path: path)
        }
        return try DataModel(root, path: path)
    }

    init(_ root: ModelElement, path: String) throws {
        try root.check(Self.modelAttributes, path: path)
        if let identifier = root["userDefinedModelVersionIdentifier"], !identifier.isEmpty {
            throw ModelElement.unobserved("a userDefinedModelVersionIdentifier", path: path)
        }
        minimumToolsVersion = try Self.majorVersion(root["minimumToolsVersion"] ?? "Automatic", path: path)
        sourceLanguage = root["sourceLanguage"]
        entities = []
        fetchRequests = []
        for child in root.children {
            switch child.name {
            case "entity":
                entities.append(try Entity(child, path: path))
            case "fetchRequest":
                try child.check(["name", "entity"], path: path)
                fetchRequests.append(FetchRequest(name: try child.required("name", path: path), entity: try child.required("entity", path: path)))
            case "elements":
                continue
            default:
                throw ModelElement.unobserved("<\(child.name)>", path: path)
            }
        }
    }

    static func majorVersion(_ minimumToolsVersion: String, path: String) throws -> Int? {
        if minimumToolsVersion == "Automatic" { return nil }
        guard minimumToolsVersion.hasPrefix("Xcode "),
              let major = Int(minimumToolsVersion.dropFirst(6).split(separator: ".").first ?? "") else {
            throw ModelElement.unobserved("minimumToolsVersion \"\(minimumToolsVersion)\"", path: path)
        }
        return major
    }

    static let modelAttributes: Set<String> = [
        "type", "documentVersion", "lastSavedToolsVersion", "systemVersion", "minimumToolsVersion", "sourceLanguage",
        "userDefinedModelVersionIdentifier", "usedWithCloudKit", "iOSVersion", "macOSVersion",
    ]
}

extension DataModel.Entity {
    /// The fetch indexes momc makes of the entity: indexed attributes (`by<Name>Index`, or the
    /// attribute's name with legacy indexes), then the older compound index, then the file's
    /// fetch indexes (wikipedia's Cache: byDateIndex, then compoundIndex). Whether they mix with
    /// fetch index elements, and the names of further compound indexes, are not observed.
    func indexes(legacy: Bool) throws -> [(name: String, elements: [(property: String, ascending: Bool)])] {
        let indexed = properties.compactMap { if case .attribute(let a) = $0, a.isIndexed { a } else { nil } }
        if !fetchIndexes.isEmpty, !indexed.isEmpty || !compoundIndexes.isEmpty {
            throw NomacError("entity \(name) mixes fetch indexes with indexed attributes or compound indexes, which is not observed yet (BACKLOG B-257)")
        }
        guard compoundIndexes.count <= 1 else {
            throw NomacError("entity \(name) has several compound indexes, whose names are not observed yet (BACKLOG B-257)")
        }
        if legacy, !compoundIndexes.isEmpty {
            throw NomacError("entity \(name) has compound indexes and an old minimumToolsVersion, which is not observed yet (BACKLOG B-257)")
        }
        return indexed.map { (legacy ? $0.name : "by" + $0.name.prefix(1).uppercased() + $0.name.dropFirst() + "Index", [($0.name, true)]) }
            + compoundIndexes.map { ("compoundIndex", $0.map { ($0, true) }) }
            + fetchIndexes.map { ($0.name, $0.elements) }
    }

    init(_ element: ModelElement, path: String) throws {
        try element.check(["name", "representedClassName", "parentEntity", "isAbstract", "versionHashModifier", "elementID",
                           "codeGenerationType", "syncable"], path: path)
        name = try element.required("name", path: path)
        className = element["representedClassName"]
        parentName = element["parentEntity"]
        isAbstract = element.flag("isAbstract")
        versionHashModifier = element["versionHashModifier"]
        renamingIdentifier = element["elementID"]
        if let generation = element["codeGenerationType"] {
            guard let codeGeneration = DataModel.CodeGeneration(rawValue: generation) else {
                throw ModelElement.unobserved("codeGenerationType \"\(generation)\"", path: path)
            }
            self.codeGeneration = codeGeneration
        } else {
            codeGeneration = nil
        }
        isSyncable = element.flag("syncable")
        properties = []
        uniquenessConstraints = []
        fetchIndexes = []
        compoundIndexes = []
        userInfo = []
        for child in element.children {
            switch child.name {
            case "attribute":
                properties.append(.attribute(try DataModel.Attribute(child, path: path)))
            case "relationship":
                properties.append(.relationship(try DataModel.Relationship(child, path: path)))
            case "uniquenessConstraints":
                for constraint in child.children {
                    uniquenessConstraints.append(try constraint.values(of: "uniquenessConstraint", item: "constraint", path: path))
                }
            case "compoundIndexes":
                for index in child.children {
                    compoundIndexes.append(try index.values(of: "compoundIndex", item: "index", path: path))
                }
            case "fetchIndex":
                fetchIndexes.append(try DataModel.FetchIndex(child, path: path))
            case "userInfo":
                userInfo = try child.userInfo(path: path)
            default:
                throw ModelElement.unobserved("<\(child.name)> in an entity", path: path)
            }
        }
    }
}

extension DataModel.Attribute {
    init(_ element: ModelElement, path: String) throws {
        try element.check(["name", "optional", "transient", "attributeType", "defaultValueString", "defaultDateTimeInterval",
                           "usesScalarValueType", "minValueString", "maxValueString", "indexed", "valueTransformerName",
                           "customClassName", "elementID", "allowsExternalBinaryDataStorage", "syncable"],
                          path: path)
        name = try element.required("name", path: path)
        let typeName = try element.required("attributeType", path: path)
        guard let type = DataModel.AttributeType(fileName: typeName) else {
            throw ModelElement.unobserved("attributeType \"\(typeName)\"", path: path)
        }
        self.type = type
        isOptional = element.flag("optional")
        isTransient = element.flag("transient")
        defaultValue = element["defaultValueString"]
        defaultDateTimeInterval = element["defaultDateTimeInterval"]
        usesScalarValueType = element["usesScalarValueType"].map { $0 == "YES" }
        minimum = element["minValueString"]
        maximum = element["maxValueString"]
        isIndexed = element.flag("indexed")
        valueTransformerName = element["valueTransformerName"]
        customClassName = element["customClassName"]
        renamingIdentifier = element["elementID"]
        allowsExternalBinaryDataStorage = element.flag("allowsExternalBinaryDataStorage")
        isSyncable = element.flag("syncable")
        userInfo = []
        for child in element.children {
            guard child.name == "userInfo" else {
                throw ModelElement.unobserved("<\(child.name)> in an attribute", path: path)
            }
            userInfo = try child.userInfo(path: path)
        }
    }
}

extension DataModel.Relationship {
    init(_ element: ModelElement, path: String) throws {
        try element.check(["name", "optional", "transient", "toMany", "ordered", "minCount", "maxCount", "deletionRule",
                           "destinationEntity", "inverseName", "inverseEntity", "elementID", "syncable"],
                          path: path)
        guard element.children.isEmpty else {
            throw ModelElement.unobserved("<\(element.children[0].name)> in a relationship", path: path)
        }
        name = try element.required("name", path: path)
        isOptional = element.flag("optional")
        isTransient = element.flag("transient")
        isToMany = element.flag("toMany")
        isOrdered = element.flag("ordered")
        minCount = try element.integer("minCount", path: path) ?? 0
        maxCount = try element.integer("maxCount", path: path) ?? 0
        let rule = element["deletionRule"] ?? "Nullify"
        guard let deleteRule = DataModel.DeleteRule(fileName: rule) else {
            throw ModelElement.unobserved("deletionRule \"\(rule)\"", path: path)
        }
        self.deleteRule = deleteRule
        destination = try element.required("destinationEntity", path: path)
        inverseName = element["inverseName"]
        renamingIdentifier = element["elementID"]
        isSyncable = element.flag("syncable")
    }
}

extension DataModel.FetchIndex {
    init(_ element: ModelElement, path: String) throws {
        try element.check(["name"], path: path)
        name = try element.required("name", path: path)
        elements = try element.children.map { child in
            guard child.name == "fetchIndexElement" else {
                throw ModelElement.unobserved("<\(child.name)> in a fetch index", path: path)
            }
            try child.check(["property", "type", "order"], path: path)
            guard child["type"] == "Binary" else {
                throw ModelElement.unobserved("fetch index element type \"\(child["type"] ?? "")\"", path: path)
            }
            return (try child.required("property", path: path), child["order"] != "descending")
        }
    }
}

/// An element of a model file.
final class ModelElement {
    let name: String
    let attributes: [String: String]
    var children: [ModelElement] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    subscript(_ attribute: String) -> String? { attributes[attribute] }

    func flag(_ attribute: String) -> Bool { attributes[attribute] == "YES" }

    func required(_ attribute: String, path: String) throws -> String {
        guard let value = attributes[attribute] else {
            throw NomacError("<\(name)> without \(attribute) in \(path)", path: path)
        }
        return value
    }

    func integer(_ attribute: String, path: String) throws -> Int? {
        guard let text = attributes[attribute] else { return nil }
        guard let value = Int(text) else {
            throw NomacError("\(attribute)=\"\(text)\" is not an integer in \(path)", path: path)
        }
        return value
    }

    /// Refuses attributes no observation covers.
    func check(_ known: Set<String>, path: String) throws {
        if let unknown = attributes.keys.sorted().first(where: { !known.contains($0) }) {
            throw Self.unobserved("\(unknown) on <\(name)>", path: path)
        }
    }

    /// The `value`s of `<group><item value="..."/>...</group>`.
    func values(of group: String, item: String, path: String) throws -> [String] {
        guard name == group else { throw Self.unobserved("<\(name)>", path: path) }
        return try children.map { child in
            guard child.name == item else { throw Self.unobserved("<\(child.name)> in <\(group)>", path: path) }
            try child.check(["value"], path: path)
            return try child.required("value", path: path)
        }
    }

    /// The entries of `<userInfo><entry key="..." value="..."/>...</userInfo>`, in the file's order.
    func userInfo(path: String) throws -> [(String, String)] {
        try children.map { entry in
            guard entry.name == "entry" else { throw Self.unobserved("<\(entry.name)> in user info", path: path) }
            try entry.check(["key", "value"], path: path)
            return (try entry.required("key", path: path), try entry.required("value", path: path))
        }
    }

    static func unobserved(_ what: String, path: String) -> NomacError {
        NomacError("\(path): nomac does not compile \(what) in Core Data models yet; momc's output for it is not observed (BACKLOG B-257)", path: path)
    }

    static func read(_ data: Data, path: String) throws -> ModelElement {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw NomacError("\(path) is not a well-formed model file", path: path)
        }
        return root
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var root: ModelElement?
        var stack: [ModelElement] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let element = ModelElement(name: elementName, attributes: attributes)
            if let parent = stack.last {
                parent.children.append(element)
            } else {
                root = element
            }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }
    }
}

/// The order of names in momc, that of `localizedStandardCompare(_:)` for the letters, digits and
/// underscores of model names (coredata-experiments `sort-order`): underscores, then numbers by
/// value, then letters ignoring case; names equal so far put lowercase letters first, from the left.
enum ModelNameOrder {
    static func sorted<T>(_ elements: [T], by name: (T) -> String) throws -> [T] {
        let keyed = try elements.map { (key: try key(name($0)), name: name($0), element: $0) }
        let sorted = keyed.sorted { lhs, rhs in
            if lhs.key != rhs.key { return lhs.key.lexicographicallyPrecedes(rhs.key) }
            // Lowercase letters have the greater code: the first case difference decides.
            return zip(lhs.name.utf8, rhs.name.utf8).first { $0 != $1 }.map { $0 > $1 } ?? false
        }
        for (lhs, rhs) in zip(sorted, sorted.dropFirst()) where lhs.key == rhs.key && lhs.name.count != rhs.name.count {
            throw NomacError("the names \(lhs.name) and \(rhs.name) differ only by leading zeros, whose order in momc is not observed yet (BACKLOG B-257)")
        }
        return sorted.map(\.element)
    }

    private enum Token: Comparable {
        case underscore
        case number(digits: Int, value: String)
        case letter(UInt8)
    }

    private static func key(_ name: String) throws -> [Token] {
        var tokens: [Token] = []
        var digits = ""
        for byte in name.utf8 {
            if (0x30...0x39).contains(byte) {
                digits.append(Character(Unicode.Scalar(byte)))
                continue
            }
            if !digits.isEmpty {
                tokens.append(number(digits))
                digits = ""
            }
            switch byte {
            case 0x5F: tokens.append(.underscore)
            case 0x41...0x5A: tokens.append(.letter(byte + 0x20))
            case 0x61...0x7A: tokens.append(.letter(byte))
            default:
                throw NomacError("the name \(name) has characters whose order in momc is not observed yet (BACKLOG B-257)")
            }
        }
        if !digits.isEmpty { tokens.append(number(digits)) }
        return tokens
    }

    private static func number(_ digits: String) -> Token {
        let value = String(digits.drop { $0 == "0" })
        return .number(digits: value.count, value: value)
    }
}
