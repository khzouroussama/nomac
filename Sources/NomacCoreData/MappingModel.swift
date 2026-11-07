import Foundation
import NomacCore
import NomacPlist

/// `mapc` as an iOS build runs it (`MappingModelCompile`): a `.xcmappingmodel` into the `.cdm`
/// keyed archive of its `NSMappingModel` (docs/formats/coredata.md "Mapping models"). What the
/// corpus's mapping models use is compiled; stored expressions, user info and the cases where mapc
/// fails, warns or orders by chance are refused (BACKLOG B-270).
public enum MappingCompiler {
    public static func compile(_ input: String) throws -> [UInt8] {
        let path = (input as NSString).appendingPathComponent("xcmapping.xml")
        let store = try MappingStore(contentsOf: path)
        return try KeyedArchiver.archive(try MappingModelArchive(store, path: path))
    }
}

/// The objects of a mapping model's Core Data XML store, by id.
struct MappingStore {
    struct Object {
        let type: String
        var attributes: [String: String] = [:]
        var links: [String: [String]] = [:]
    }

    let objects: [String: Object]
    let modelID: String
    let source: DataModel
    let destination: DataModel

    init(contentsOf path: String) throws {
        let root = try ModelElement.read(Data(contentsOf: URL(fileURLWithPath: path)), path: path)
        var objects: [String: Object] = [:]
        for element in root.children where element.name == "object" {
            guard let type = element["type"], let id = element["id"] else { continue }
            var object = Object(type: type)
            for child in element.children {
                guard let name = child["name"] else { continue }
                if child.name == "attribute" {
                    object.attributes[name] = child.text
                } else if child.name == "relationship" {
                    object.links[name] = (child["idrefs"] ?? "").split(separator: " ").map(String.init)
                }
            }
            objects[id] = object
        }
        self.objects = objects
        let models = objects.filter { $0.value.type == "XDDEVMAPPINGMODEL" }
        guard models.count == 1, let (modelID, model) = models.first else {
            throw NomacError("\(path) has \(models.count) mapping models; mapc's store has one", path: path)
        }
        self.modelID = modelID
        func blob(_ name: String) throws -> DataModel {
            guard let text = model.attributes[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else {
                throw NomacError("\(path) has no \(name)", path: path)
            }
            return try XDModel.dataModel(Array(data), path: path)
        }
        source = try blob("sourcemodeldata")
        destination = try blob("destinationmodeldata")
    }

    /// The members of `owner`'s to-many `link`, each linking back through `inverse` (Xcode writes
    /// both sides; mapc takes membership from the owner and fails on members without the back link).
    func members(of owner: String, _ link: String, inverse: String, path: String) throws -> [(id: String, object: Object)] {
        try (objects[owner]?.links[link] ?? []).map { id in
            guard let object = objects[id], object.links[inverse] == [owner] else {
                throw NomacError("\(path): \(id) is in \(link) without linking back; mapc fails on such stores, nomac does not reproduce it (BACKLOG B-270)", path: path)
            }
            return (id, object)
        }
    }
}

/// The source and destination models a mapping model embeds: keyed archives of Xcode's model
/// document (`XDPMModel`), read into the inputs of Core Data's version hashes.
enum XDModel {
    static func dataModel(_ bytes: [UInt8], path: String) throws -> DataModel {
        let archive = try KeyedArchiveReader(bytes)
        func entries(_ uid: Int?) -> [(key: String?, value: Int)] {
            guard let uid else { return [] }
            let keyed = archive.dictionary(uid)
            return keyed.isEmpty ? archive.array(uid).map { (nil, $0) } : keyed.map { ($0.key, $0.value) }
        }
        func stereotypes(_ uid: Int) -> [String: KeyedArchiveReader.Value] {
            var values: [String: KeyedArchiveReader.Value] = [:]
            for stereotype in entries(archive.reference(uid, "XDBucketForStereotypesstorage")) {
                for property in entries(archive.reference(stereotype.value, "XDBucketForOwnedAttributesstorage")) {
                    guard let key = property.key, case .dictionary(let fields) = archive.object(property.value) else { continue }
                    var value = fields["_default"] ?? .null
                    if case .uid(let target) = value, !archive.isObject(target) {
                        value = archive.object(target)
                    }
                    values[key] = value
                }
            }
            return values
        }
        func flag(_ value: KeyedArchiveReader.Value?) -> Bool {
            switch value {
            case .boolean(let flag)?: flag
            case .integer(let number)?: number != 0
            default: false
            }
        }
        func integer(_ value: KeyedArchiveReader.Value?) -> Int {
            if case .integer(let number)? = value { return number }
            return 0
        }
        func name(_ value: KeyedArchiveReader.Value?) -> String? {
            guard case .uid(let uid)? = value else { return nil }
            return archive.string(uid, "_name")
        }
        func unobserved(_ what: String) -> NomacError {
            NomacError("\(path): a mapping model's \(what) is not observed yet (BACKLOG B-270)", path: path)
        }
        guard let package = archive.reference(archive.root, "_xd_rootPackage") else { throw unobserved("model without a package") }
        var entities: [DataModel.Entity] = []
        for entry in entries(archive.reference(package, "XDBucketForClassesstorage")) {
            let uid = entry.value
            let values = stereotypes(uid)
            if case .uid(let constraints) = values["XDPMUniquenessConstraints"] ?? .null, !archive.array(constraints).isEmpty {
                throw unobserved("uniqueness constraints")
            }
            var properties: [DataModel.Property] = []
            for property in entries(archive.reference(uid, "XDBucketForOwnedAttributesstorage")) {
                let fields = stereotypes(property.value)
                guard let propertyName = archive.string(property.value, "_name") else { throw unobserved("property without a name") }
                if case .string = fields["XD_PPSK_versionHashModifier"] ?? .null { throw unobserved("property version hash modifier") }
                let optional = flag(fields["XD_PPSK_isOptional"]), transient = flag(fields["XD_PPSK_isTransient"])
                switch archive.className(property.value) {
                case "XDPMAttribute":
                    guard let type = DataModel.AttributeType(rawValue: integer(fields["XD_PAttK_attributeType"])) else {
                        throw unobserved("attribute type \(integer(fields["XD_PAttK_attributeType"]))")
                    }
                    properties.append(.attribute(DataModel.Attribute(
                        name: propertyName, type: type, isOptional: optional, isTransient: transient, defaultValue: nil,
                        defaultDateTimeInterval: nil, usesScalarValueType: nil, minimum: nil, maximum: nil, isIndexed: false, valueTransformerName: nil,
                        customClassName: nil, renamingIdentifier: nil,
                        allowsExternalBinaryDataStorage: flag(fields["XD_PAttK_allowsExternalBinaryDataStorage"]), userInfo: [], hasSyncable: true)))
                case "XDPMRelationship":
                    let maxCount = integer(fields["XD_PRK_maxCount"])
                    properties.append(.relationship(DataModel.Relationship(
                        name: propertyName, isOptional: optional, isTransient: transient, isToMany: maxCount != 1,
                        isOrdered: flag(fields["XD_PRK_ordered"]), minCount: integer(fields["XD_PRK_minCount"]), maxCount: maxCount,
                        deleteRule: .nullify, destination: name(fields["XD_PRK_destination"]) ?? "",
                        inverseName: name(fields["XD_PRK_inverseRelationship"]), renamingIdentifier: nil, hasSyncable: true)))
                default:
                    throw unobserved("property class \(archive.className(property.value) ?? "?")")
                }
            }
            let parents = entries(archive.reference(uid, "XDBucketForGeneralizationsstorage")).compactMap { archive.reference($0.value, "_general") }
            guard parents.count <= 1, let entityName = archive.string(uid, "_name") else { throw unobserved("entity with several parents") }
            var modifier: String?
            if case .string(let text) = values["XD_PSK_versionHashModifier"] ?? .null { modifier = text }
            entities.append(DataModel.Entity(
                name: entityName, className: nil, parentName: parents.first.flatMap { archive.string($0, "_name") },
                isAbstract: flag(values["XD_PSK_isAbstract"]), versionHashModifier: modifier, renamingIdentifier: nil, codeGeneration: nil,
                properties: properties, uniquenessConstraints: [], fetchIndexes: [], compoundIndexes: [], userInfo: [], hasSyncable: true))
        }
        return DataModel(entities: entities, fetchRequests: [], minimumToolsVersion: nil, sourceLanguage: nil)
    }
}

extension DataModel {
    func entity(_ name: String?) -> Entity? {
        entities.first { $0.name == name }
    }

    /// An entity's properties, its ancestors' included.
    func allProperties(_ entity: Entity) -> [Property] {
        entity.properties + (self.entity(entity.parentName).map { allProperties($0) } ?? [])
    }

    func hasSubentities(_ name: String) -> Bool {
        entities.contains { $0.parentName == name }
    }
}

/// The `NSMappingModel` mapc archives, built as docs/formats/coredata.md "Mapping models" states.
final class MappingModelArchive: KeyedArchivable {
    private var mappings: ArchivedCollection!
    private var mappingsByName: ArchivedCollection!

    init(_ store: MappingStore, path: String) throws {
        func refuse(_ what: String) -> NomacError {
            NomacError("\(path): mapc's output for \(what) is not reproduced yet (BACKLOG B-270)", path: path)
        }
        let emptyList = ArchivedCollection(.array, objects: [])
        // One NSData per entity of each model, whichever mappings name it (v2_to_v3's two
        // mappings from Note); equal hashes of the two models stay two objects.
        let sourceHashes = try VersionHash.entities(of: store.source).mapValues(DataObject.init)
        let destinationHashes = try VersionHash.entities(of: store.destination).mapValues(DataObject.init)

        let members = try store.members(of: store.modelID, "entitymappings", inverse: "mappingmodel", path: path)
        let numbers = members.map { Int16(truncatingIfNeeded: Int($0.object.attributes["mappingnumber"] ?? "0") ?? 0) }
        guard Set(numbers).count == numbers.count else { throw refuse("entity mappings of equal mappingnumber (their order changes from run to run)") }
        let ordered = zip(numbers, members).sorted { $0.0 < $1.0 }.map(\.1)

        var entityMappings: [EntityMapping] = []
        for member in ordered {
            entityMappings.append(try EntityMapping(member.id, member.object, store: store, sourceHashes: sourceHashes,
                                                    destinationHashes: destinationHashes, refuse: refuse))
        }
        guard Set(entityMappings.map(\.name.text)).count == entityMappings.count else { throw refuse("two entity mappings of one name") }
        for mapping in entityMappings {
            try mapping.linkProperties(store: store, mappings: entityMappings, emptyList: emptyList, path: path, refuse: refuse)
        }
        mappings = entityMappings.isEmpty ? emptyList : ArchivedCollection(.array, objects: entityMappings.map { .object($0) })
        // A copy of a dictionary filled in array order (byname-12, -25 and -40).
        let byName = Dictionary(entityMappings.map { ($0.name.text, $0) }, uniquingKeysWith: { first, _ in first })
        let order = try FoundationHashTable.inserting(entityMappings.map(\.name.text)).copied().keys
        mappingsByName = ArchivedCollection(.mutableDictionary, keys: order.map { .stringObject(byName[$0]!.name) },
                                            objects: order.map { .object(byName[$0]!) })
    }

    var archivedClassNames: [String] { ["NSMappingModel", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(mappings, forKey: "NSEntityMappings")
        try archiver.encode(mappingsByName, forKey: "NSEntityMappingsByName")
    }
}

final class EntityMapping: KeyedArchivable {
    let name: StringObject
    private let source: StringObject?
    private let destination: StringObject?
    private let sourceHash: DataObject?
    private let destinationHash: DataObject?
    private let type: Int
    private let policy: StringObject?
    private let sourceExpression: KeyedArchivable?
    private let id: String
    private let object: MappingStore.Object
    private var attributeMappings: ArchivedCollection!
    private var relationshipMappings: ArchivedCollection!

    init(_ id: String, _ object: MappingStore.Object, store: MappingStore, sourceHashes: [String: DataObject],
         destinationHashes: [String: DataObject], refuse: (String) -> NomacError) throws {
        self.id = id
        self.object = object
        let attributes = object.attributes
        for unobserved in ["userinfodata"] where attributes[unobserved] != nil {
            throw refuse("an entity mapping's \(unobserved)")
        }
        source = attributes["sourcename"].map(StringObject.init)
        destination = attributes["destinationname"].map(StringObject.init)
        if let explicit = attributes["name"] {
            name = StringObject(explicit)
        } else if let source, let destination {
            name = StringObject(source.text + "To" + destination.text)
        } else if let single = source ?? destination {
            name = single
        } else {
            throw refuse("an entity mapping without names (mapc fails)")
        }
        let sourceEntity = store.source.entity(source?.text)
        let destinationEntity = store.destination.entity(destination?.text)
        sourceHash = sourceEntity.flatMap { sourceHashes[$0.name] }
        destinationHash = destinationEntity.flatMap { destinationHashes[$0.name] }
        let policyName = attributes["migrationpolicyclassname"]
        policy = policyName.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : StringObject($0) }
        if policy != nil {
            type = 1
        } else if sourceEntity == nil {
            type = 2
        } else if destinationEntity == nil {
            type = 3
        } else if source?.text != destination?.text {
            type = 5
        } else {
            type = Self.isCopy(sourceEntity!, store.source, destinationEntity!, store.destination) ? 4 : 5
        }
        let generates = attributes["autogenerateexpression"] != "0"
        if !generates, attributes["sourceexpressiondata"] != nil { throw refuse("a stored source expression") }
        if let filter = attributes["sourcefilterpredicatestring"], filter.isEmpty { throw refuse("an empty source filter") }
        if generates, let source {
            let filter: ArchivedItem = attributes["sourcefilterpredicatestring"].map { .stringObject(StringObject($0)) } ?? .string("TRUEPREDICATE")
            sourceExpression = MappingExpression.fetch(source: source, filter: filter)
        } else {
            sourceExpression = nil
        }
    }

    /// Copy (4) rather than Transform (5): the source entity's persistent properties all have a
    /// counterpart of the same kind and inputs in the destination entity.
    private static func isCopy(_ source: DataModel.Entity, _ sourceModel: DataModel, _ destination: DataModel.Entity, _ destinationModel: DataModel) -> Bool {
        guard source.isAbstract == destination.isAbstract,
              source.versionHashModifier == nil || source.versionHashModifier == destination.versionHashModifier,
              source.parentName == nil || source.parentName == destination.parentName else { return false }
        let targets = Dictionary(destinationModel.allProperties(destination).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return sourceModel.allProperties(source).filter { !$0.isTransient }.allSatisfy { property in
            switch (property, targets[property.name]) {
            case (.attribute(let a), .attribute(let b)?):
                a.isOptional == b.isOptional && !b.isTransient && a.type == b.type
                    && a.allowsExternalBinaryDataStorage == b.allowsExternalBinaryDataStorage
            case (.relationship(let a), .relationship(let b)?):
                a.isOptional == b.isOptional && !b.isTransient && a.destination == b.destination
                    && (a.inverseName == nil || a.inverseName == b.inverseName)
            default:
                false
            }
        }
    }

    func linkProperties(store: MappingStore, mappings: [EntityMapping], emptyList: ArchivedCollection, path: String,
                        refuse: (String) -> NomacError) throws {
        let sourceEntity = store.source.entity(source?.text)
        let destinationEntity = store.destination.entity(destination?.text)
        let sourceProperties = sourceEntity.map { store.source.allProperties($0) } ?? []
        let destinationProperties = destinationEntity.map { store.destination.allProperties($0) } ?? []
        func members(_ link: String) throws -> [MappingStore.Object] {
            let objects = try store.members(of: id, link, inverse: "entitymapping", path: path).map(\.object)
            for object in objects {
                for unobserved in ["valueexpressiondata", "userinfodata"] where object.attributes[unobserved] != nil {
                    throw refuse("a property mapping's \(unobserved)")
                }
                guard let name = object.attributes["name"], destinationProperties.contains(where: { $0.name == name }) else {
                    throw refuse("a property mapping the destination entity has no property for (mapc fails)")
                }
            }
            let names = objects.map { $0.attributes["name"]! }
            guard Set(names.map { $0.lowercased() }).count == names.count else {
                throw refuse("property mappings whose names differ only by case (their order changes from run to run)")
            }
            return objects.sorted { Self.precedes($0.attributes["name"]!, $1.attributes["name"]!) }
        }
        let attributes = try members("attributemappings").map { mapping -> KeyedArchivable in
            let name = mapping.attributes["name"]!
            let isAttribute = sourceProperties.contains { if case .attribute(let a) = $0 { a.name == name } else { false } }
            return PropertyMapping(name: name, value: type != 2 && isAttribute ? MappingExpression.keyPath("source", name) : nil)
        }
        let relationships = try members("relationshipmappings").map { mapping -> KeyedArchivable in
            let name = mapping.attributes["name"]!
            guard type != 2 else { return PropertyMapping(name: name, value: nil) }
            if mapping.attributes["autogenerateexpression"] == "0" { throw refuse("a relationship mapping that does not generate its expression") }
            return PropertyMapping(name: name, value: try relationshipValue(name, mapping, sourceEntity, store, mappings, refuse))
        }
        attributeMappings = attributes.isEmpty ? emptyList : ArchivedCollection(.array, objects: attributes.map { .object($0) })
        relationshipMappings = relationships.isEmpty ? emptyList : ArchivedCollection(.array, objects: relationships.map { .object($0) })
    }

    /// A relationship mapping's generated value: `FUNCTION($manager, "<selector>", "<name>", <key path>)`.
    private func relationshipValue(_ name: String, _ mapping: MappingStore.Object, _ sourceEntity: DataModel.Entity?, _ store: MappingStore,
                                   _ mappings: [EntityMapping], _ refuse: (String) -> NomacError) throws -> MappingExpression? {
        let mappingName = mapping.attributes["sourcemappingname"]
        if let mappingName, !mappings.contains(where: { $0.name.text == mappingName }) {
            throw refuse("a relationship mapping naming a missing entity mapping (mapc fails)")
        }
        let sourceRelationship = sourceEntity.flatMap { entity in
            store.source.allProperties(entity).lazy.compactMap { if case .relationship(let r) = $0, r.name == name { r } else { nil } }.first
        }
        guard let keyPath = mapping.attributes["sourcekeypath"] ?? (sourceRelationship != nil ? "$source." + name : nil) else {
            if mappingName != nil { throw refuse("a relationship mapping without a key path (mapc fails)") }
            return nil
        }
        guard keyPath.hasPrefix("$source"), keyPath == "$source" || keyPath.hasPrefix("$source.") else {
            throw refuse("the key path \(keyPath)")
        }
        let components = keyPath == "$source" ? [] : keyPath.dropFirst("$source.".count).split(separator: ".").map(String.init)
        var entity = sourceEntity
        var last: DataModel.Relationship?
        for component in components {
            switch entity.flatMap({ e in store.source.allProperties(e).first { $0.name == component } }) {
            case .relationship(let relationship)?:
                last = relationship
                entity = store.source.entity(relationship.destination)
            case .attribute?:
                throw refuse("a key path ending on an attribute (mapc crashes)")
            case .fetched?:
                throw refuse("a key path through a fetched property")
            case nil:
                last = nil
                entity = nil
            }
        }
        if components.isEmpty || entity == nil { last = nil }
        let destinationChildren = store.destination.entity(destination?.text).flatMap { entity in
            store.destination.allProperties(entity).lazy.compactMap { if case .relationship(let r) = $0, r.name == name { r } else { nil } }.first
        }.map { store.destination.hasSubentities($0.destination) } ?? false
        let operand = Self.keyPathExpression(components)
        if let last, store.source.hasSubentities(last.destination) || destinationChildren {
            return .relationshipFunction("destinationInstancesForSourceRelationshipNamed:sourceInstances:", name: last.name, operand)
        }
        if destinationChildren { throw refuse("children found only on the destination side of a key path that does not resolve") }
        let target: String
        if let mappingName {
            target = mappingName
        } else {
            let candidates = mappings.filter { $0.destination?.text == sourceRelationship?.destination && sourceRelationship != nil }
            guard candidates.count == 1 else { throw refuse("a relationship mapping with \(candidates.count) candidate entity mappings") }
            target = candidates[0].name.text
        }
        return .relationshipFunction("destinationInstancesForEntityMappingNamed:sourceInstances:", name: target, operand)
    }

    private static func keyPathExpression(_ components: [String]) -> MappingExpression {
        components.isEmpty ? .variable("source") : .keyPath("source", components.joined(separator: "."))
    }

    /// `compare(_:options: [.caseInsensitive, .numeric])` on names that differ beyond case.
    static func precedes(_ a: String, _ b: String) -> Bool {
        var left = Array(a.lowercased().unicodeScalars)[...], right = Array(b.lowercased().unicodeScalars)[...]
        while let l = left.first, let r = right.first {
            if l.properties.numericType == .decimal, r.properties.numericType == .decimal {
                let ld = left.prefix { $0.properties.numericType == .decimal }, rd = right.prefix { $0.properties.numericType == .decimal }
                let lv = Int(String(String.UnicodeScalarView(ld))) ?? 0, rv = Int(String(String.UnicodeScalarView(rd))) ?? 0
                if lv != rv { return lv < rv }
                left = left.dropFirst(ld.count)
                right = right.dropFirst(rd.count)
                continue
            }
            if l != r { return l.value < r.value }
            left = left.dropFirst()
            right = right.dropFirst()
        }
        return left.isEmpty && !right.isEmpty
    }

    var archivedClassNames: [String] { ["NSEntityMapping", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(.stringObject(name), forKey: "NSMappingName")
        archiver.encodeInt32(type, forKey: "NSMappingType")
        try archiver.encode(source.map(ArchivedItem.stringObject), forKey: "NSSourceEntityName")
        try archiver.encode(sourceHash.map(ArchivedItem.data), forKey: "NSSourceEntityVersionHash")
        try archiver.encode(destination.map(ArchivedItem.stringObject), forKey: "NSDestinationEntityName")
        try archiver.encode(destinationHash.map(ArchivedItem.data), forKey: "NSDestinationEntityVersionHash")
        try archiver.encode(sourceExpression, forKey: "NSSourceExpression")
        try archiver.encode(nil as ArchivedItem?, forKey: "NSUserInfo")
        try archiver.encode(policy.map(ArchivedItem.stringObject), forKey: "NSEntityMigrationPolicyClassName")
        try archiver.encode(attributeMappings, forKey: "NSAttributeMappings")
        try archiver.encode(relationshipMappings, forKey: "NSRelationshipMappings")
    }
}

final class PropertyMapping: KeyedArchivable {
    private let name: String
    private let value: MappingExpression?

    init(name: String, value: MappingExpression?) {
        self.name = name
        self.value = value
    }

    var archivedClassNames: [String] { ["NSPropertyMapping", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(.stringObject(StringObject(name)), forKey: "NSDestinationPropertyName")
        try archiver.encode(value, forKey: "NSValueExpression")
        try archiver.encode(nil as ArchivedItem?, forKey: "NSUserInfo")
        try archiver.encode(nil as ArchivedItem?, forKey: "NSPropertyTransforms")
    }
}

/// The expressions mapc generates, as `NSExpression(format:)` parses them (strings that are not
/// tagged are new objects, selectors one object per text) or, for the source fetch, as built with
/// the API (docs/formats/coredata.md "Mapping models").
final class MappingExpression: KeyedArchivable {
    enum Kind {
        case variable(String)
        case keyPath(variable: String, path: String)
        case specifier(String)
        case constant(ArchivedItem)
        case function(selector: String, operand: MappingExpression, arguments: ArchivedCollection)
        case fetch(request: MappingExpression, context: MappingExpression)
    }

    let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    /// `$name`.
    static func variable(_ name: String) -> MappingExpression { MappingExpression(.variable(name)) }

    /// `$variable.path`.
    static func keyPath(_ variable: String, _ path: String) -> MappingExpression { MappingExpression(.keyPath(variable: variable, path: path)) }

    /// `FUNCTION($manager, "selector" , "name", keyPath)`.
    static func relationshipFunction(_ selector: String, name: String, _ keyPath: MappingExpression) -> MappingExpression {
        let constant = MappingExpression(.constant(.stringObject(StringObject(name))))
        return MappingExpression(.function(selector: selector, operand: .variable("manager"),
                                           arguments: ArchivedCollection(.mutableArray, objects: [.object(constant), .object(keyPath)])))
    }

    /// `FETCH(FUNCTION($manager, "fetchRequestForSourceEntityNamed:predicateString:" , source, filter), $manager.sourceContext, NO)`,
    /// whose first constant is the entity mapping's own source name.
    static func fetch(source: StringObject, filter: ArchivedItem) -> MappingExpression {
        let arguments = ArchivedCollection(.array, objects: [.object(MappingExpression(.constant(.stringObject(source)))),
                                                             .object(MappingExpression(.constant(filter)))])
        let request = MappingExpression(.function(selector: "fetchRequestForSourceEntityNamed:predicateString:", operand: .variable("manager"),
                                                  arguments: arguments))
        return MappingExpression(.fetch(request: request, context: .keyPath("manager", "sourceContext")))
    }

    var archivedClassNames: [String] {
        switch kind {
        case .variable: ["NSVariableExpression", "NSExpression", "NSObject"]
        case .keyPath: ["NSKeyPathExpression", "NSFunctionExpression", "NSExpression", "NSObject"]
        case .specifier: ["NSKeyPathSpecifierExpression", "NSExpression", "NSObject"]
        case .constant: ["NSConstantValueExpression", "NSExpression", "NSObject"]
        case .function: ["NSFunctionExpression", "NSExpression", "NSObject"]
        case .fetch: ["NSFetchRequestExpression", "NSExpression", "NSObject"]
        }
    }

    func encode(to archiver: KeyedArchiver) throws {
        switch kind {
        case .variable(let name):
            archiver.encodeInteger(2, forKey: "NSExpressionType")
            try archiver.encode(.stringObject(StringObject(name)), forKey: "NSVariable")
        case .keyPath(let variable, let path):
            archiver.encodeInteger(4, forKey: "NSExpressionType")
            try archiver.encode("valueForKeyPath:", forKey: "NSSelectorName")
            try archiver.encode(MappingExpression.variable(variable), forKey: "NSOperand")
            let specifier = MappingExpression(.specifier(path))
            try archiver.encode(ArchivedCollection(.mutableArray, objects: [.object(specifier)]), forKey: "NSArguments")
        case .specifier(let path):
            archiver.encodeInteger(10, forKey: "NSExpressionType")
            try archiver.encode(.stringObject(StringObject(path)), forKey: "NSKeyPath")
        case .constant(let value):
            archiver.encodeInteger(0, forKey: "NSExpressionType")
            try archiver.encode(value, forKey: "NSConstantValue")
        case .function(let selector, let operand, let arguments):
            archiver.encodeInteger(4, forKey: "NSExpressionType")
            try archiver.encode(selector, forKey: "NSSelectorName")
            try archiver.encode(operand, forKey: "NSOperand")
            try archiver.encode(arguments, forKey: "NSArguments")
        case .fetch(let request, let context):
            archiver.encodeInteger(50, forKey: "NSExpressionType")
            try archiver.encode(request, forKey: "NSFRExpression")
            try archiver.encode(context, forKey: "NSMOCExpression")
            archiver.encode(false, forKey: "NSCountOnlyFlag")
        }
    }
}
