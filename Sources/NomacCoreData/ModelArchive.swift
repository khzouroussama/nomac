import NomacCore
import NomacPlist

/// The `.mom` of a model version: `NSKeyedArchiver`'s archive of the `NSManagedObjectModel` momc
/// builds, each class encoding what a recording `NSCoder` saw Core Data's classes encode for the
/// 174 observed `.mom` files (docs/formats/coredata.md "`.mom`").
enum ModelArchive {
    /// Written by momc as `CDMCompilerToolVersion` and `CDMCompilerXcodeVersion` (Xcode 27.0).
    static let compilerToolVersion = 25249.0
    static let compilerXcodeVersion = 270_000

    static func data(_ model: DataModel, module: String?) throws -> [UInt8] {
        try KeyedArchiver.archive(try ManagedObjectModel(model, module: module))
    }
}

/// `NSDictionary`, `NSArray`, `NSSet` and their mutable subclasses.
final class ArchivedCollection: KeyedArchivable {
    enum Kind {
        case dictionary, mutableDictionary, array, mutableArray, set
    }

    let kind: Kind
    let keys: [ArchivedItem]
    let objects: [ArchivedItem]

    init(_ kind: Kind, keys: [ArchivedItem] = [], objects: [ArchivedItem]) {
        self.kind = kind
        self.keys = keys
        self.objects = objects
    }

    var archivedClassNames: [String] {
        switch kind {
        case .dictionary: ["NSDictionary", "NSObject"]
        case .mutableDictionary: ["NSMutableDictionary", "NSDictionary", "NSObject"]
        case .array: ["NSArray", "NSObject"]
        case .mutableArray: ["NSMutableArray", "NSArray", "NSObject"]
        case .set: ["NSSet", "NSObject"]
        }
    }

    func encode(to archiver: KeyedArchiver) throws {
        if kind == .dictionary || kind == .mutableDictionary {
            try archiver.encodeArray(keys, forKey: "NS.keys")
        }
        try archiver.encodeArray(objects, forKey: "NS.objects")
    }

    /// A dictionary whose keys are in the iteration order of `order`.
    static func dictionary(_ kind: Kind, _ entries: [(String, ArchivedItem)], order: [String]) -> ArchivedCollection {
        let values = Dictionary(entries, uniquingKeysWith: { first, _ in first })
        return ArchivedCollection(kind, keys: order.map { .string($0) }, objects: order.map { values[$0]! })
    }
}

final class ArchivedDate: KeyedArchivable {
    let timeIntervalSinceReferenceDate: Double

    init(_ timeIntervalSinceReferenceDate: Double) {
        self.timeIntervalSinceReferenceDate = timeIntervalSinceReferenceDate
    }

    var archivedClassNames: [String] { ["NSDate", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        archiver.encode(timeIntervalSinceReferenceDate, forKey: "NS.time")
    }
}

final class ManagedObjectModel: KeyedArchivable {
    private var entities: ArchivedCollection!
    private var fetchRequestTemplates: ArchivedCollection?
    private let versionIdentifiers = ArchivedCollection(.set, objects: [.string("")])

    init(_ model: DataModel, module: String?) throws {
        let context = ArchiveContext()
        var described: [String: EntityDescription] = [:]
        for entity in model.entities {
            guard described[entity.name] == nil else {
                throw NomacError("two entities are named \(entity.name)")
            }
            if let version = model.minimumToolsVersion, !entity.isSyncable || entity.properties.contains(where: {
                if case .relationship(let relationship) = $0 { !relationship.isSyncable } else { false }
            }) {
                throw NomacError("entity \(entity.name) or one of its relationships is not syncable under minimumToolsVersion Xcode \(version), which is not observed yet (BACKLOG B-257)")
            }
            described[entity.name] = try EntityDescription(entity, model: self, module: module, context: context)
        }
        for description in described.values {
            try description.link(described, legacyIndexes: model.hasLegacyIndexes, minimumToolsVersion: model.minimumToolsVersion)
        }
        // The model's dictionary of entities is copied twice from file order
        // (docs/formats/foundation-collections.md "What uses which").
        let once = try FoundationHashTable.inserting(model.entities.map(\.name)).copied().keys
        let order = try FoundationHashTable.inserting(once).copied().keys
        entities = .dictionary(.mutableDictionary, order.map { ($0, .object(described[$0]!)) }, order: order)
        if !model.fetchRequests.isEmpty {
            let requests = try model.fetchRequests.map { request -> (String, ArchivedItem) in
                guard let entity = described[request.entity] else {
                    throw NomacError("fetch request \(request.name) names the entity \(request.entity), which is not in the model")
                }
                return (request.name, .object(FetchRequest(entity: entity)))
            }
            let order = try FoundationHashTable.inserting(requests.map(\.0)).copied().keys
            fetchRequestTemplates = .dictionary(.mutableDictionary, requests, order: order)
        }
    }

    var archivedClassNames: [String] { ["NSManagedObjectModel", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(entities, forKey: "NSEntities")
        try archiver.encode(fetchRequestTemplates, forKey: "NSFetchRequestTemplates")
        try archiver.encode(versionIdentifiers, forKey: "NSVersionIdentifiers")
        archiver.encode(ModelArchive.compilerToolVersion, forKey: "CDMCompilerToolVersion")
        archiver.encodeInteger(ModelArchive.compilerXcodeVersion, forKey: "CDMCompilerXcodeVersion")
    }
}

/// Objects one model shares: the empty user info dictionary, the evaluated-object expression and
/// dates of one value.
final class ArchiveContext {
    let emptyUserInfo = ArchivedCollection(.dictionary, objects: [])
    let evaluatedObject = Expression.evaluatedObject
    var dates: [Double: ArchivedDate] = [:]

    func date(_ interval: Double) -> ArchivedDate {
        if let date = dates[interval] { return date }
        let date = ArchivedDate(interval)
        dates[interval] = date
        return date
    }
}

final class EntityDescription: KeyedArchivable {
    let source: DataModel.Entity
    private unowned let model: ManagedObjectModel
    private let className: String
    private let context: ArchiveContext
    private(set) var parent: EntityDescription?
    private var children: [EntityDescription] = []
    private var properties: ArchivedCollection!
    private var userInfo: ArchivedCollection
    private var fetchIndexes: [FetchIndexDescription] = []
    /// The property names of every fetch index of several attributes (`NSCompoundIndexes`).
    private var compoundIndexes: [[String]] = []
    private(set) var described: [String: KeyedArchivable] = [:]

    init(_ source: DataModel.Entity, model: ManagedObjectModel, module: String?, context: ArchiveContext) throws {
        self.source = source
        self.model = model
        self.context = context
        guard let represented = source.className else {
            throw NomacError("entity \(source.name) has no representedClassName; momc's output without one is not observed (BACKLOG B-257)")
        }
        if represented.hasPrefix(".") {
            guard let module else {
                throw NomacError("entity \(source.name)'s class \(represented) is in the current module, and momc was given no --module")
            }
            className = module + represented
        } else {
            className = represented
        }
        userInfo = source.userInfo.isEmpty ? context.emptyUserInfo : try Self.userInfo(source.userInfo)
    }

    static func userInfo(_ entries: [(String, String)]) throws -> ArchivedCollection {
        let order = try FoundationHashTable.inserting(entries.map(\.0)).copied().keys
        return .dictionary(.dictionary, entries.map { ($0.0, .string($0.1)) }, order: order)
    }

    func link(_ entities: [String: EntityDescription], legacyIndexes: Bool, minimumToolsVersion: Int?) throws {
        if let parentName = source.parentName {
            guard let parent = entities[parentName] else {
                throw NomacError("entity \(source.name)'s parent \(parentName) is not in the model")
            }
            self.parent = parent
            parent.children.append(self)
        }
        var entries: [(String, ArchivedItem)] = []
        for property in source.properties {
            let description: KeyedArchivable
            switch property {
            case .attribute(let attribute):
                description = try AttributeDescription(attribute, entity: self, context: context, minimumToolsVersion: minimumToolsVersion)
            case .relationship(let relationship):
                guard let destination = entities[relationship.destination] else {
                    throw NomacError("relationship \(source.name).\(relationship.name) names the entity \(relationship.destination), which is not in the model")
                }
                description = try RelationshipDescription(relationship, entity: self, destination: destination)
            }
            described[property.name] = description
            entries.append((property.name, .object(description)))
        }
        let order = try FoundationHashTable.inserting(source.properties.map(\.name)).copied().keys
        properties = .dictionary(.mutableDictionary, entries, order: order)
        let indexes = try source.indexes(legacy: legacyIndexes)
        fetchIndexes = indexes.map { FetchIndexDescription(name: $0.name, elements: $0.elements, entity: legacyIndexes ? nil : self) }
        // Indexes of several attributes only: one with a relationship is left out (wikipedia's
        // WMFArticle and ReadingListEntry).
        let attributes = Set(source.properties.compactMap { if case .attribute(let a) = $0 { a.name } else { nil } })
        compoundIndexes = indexes.map { $0.elements.map(\.property) }.filter { $0.count > 1 && $0.allSatisfy(attributes.contains) }
    }

    func inverse(named name: String) -> KeyedArchivable? {
        described[name]
    }

    var archivedClassNames: [String] { ["NSEntityDescription", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(source.name, forKey: "NSEntityName")
        // NSManagedObject itself is archived as no class (coredata-experiments `omo-default-class`).
        try archiver.encode(className == "NSManagedObject" ? nil : className, forKey: "NSClassNameForEntity")
        if source.isAbstract {
            archiver.encode(true, forKey: "NSIsAbstract")
        }
        archiver.encodeConditional(model, forKey: "NSManagedObjectModel")
        archiver.encodeConditional(parent, forKey: "NSSuperentity")
        let order = try FoundationHashTable.inserting(children.map(\.source.name)).copied().keys
        let subentities = ArchivedCollection.dictionary(.mutableDictionary, children.map { ($0.source.name, .object($0)) }, order: order)
        try archiver.encode(subentities, forKey: "NSSubentities")
        try archiver.encode(properties, forKey: "NSProperties")
        try archiver.encode(userInfo, forKey: "NSUserInfo")
        try archiver.encode(source.versionHashModifier, forKey: "NSVersionHashModifier")
        try archiver.encode(source.renamingIdentifier ?? source.name, forKey: "NSRenamingIdentifier")
        if !source.uniquenessConstraints.isEmpty {
            let tuples = source.uniquenessConstraints.map { ArchivedItem.object(ArchivedCollection(.mutableArray, objects: $0.map { .string($0) })) }
            try archiver.encode(ArchivedCollection(.mutableArray, objects: tuples), forKey: "NSUniqueTuples")
        }
        if !fetchIndexes.isEmpty {
            try archiver.encode(ArchivedCollection(.mutableArray, objects: fetchIndexes.map { .object($0) }), forKey: "NSFetchIndexDescriptions")
            let compound = compoundIndexes.map { ArchivedItem.object(ArchivedCollection(.mutableArray, objects: $0.map { .string($0) })) }
            try archiver.encode(ArchivedCollection(.mutableArray, objects: compound), forKey: "NSCompoundIndexes")
        }
    }
}

final class AttributeDescription: KeyedArchivable {
    private let source: DataModel.Attribute
    private unowned let entity: EntityDescription
    private let valueClassName: String?
    private let defaultValue: ArchivedItem?
    private let validation: (predicates: [Predicate], warnings: [Int])?
    private let userInfo: ArchivedCollection?

    init(_ source: DataModel.Attribute, entity: EntityDescription, context: ArchiveContext, minimumToolsVersion: Int?) throws {
        self.source = source
        self.entity = entity
        let location = "attribute \(entity.source.name).\(source.name)"
        valueClassName = source.customClassName ?? Self.valueClassName(source.type)
        defaultValue = try Self.defaultValue(source, context: context, location: location)
        validation = try Self.validation(source, context: context, location: location)
        var entries = source.userInfo
        if let minimumToolsVersion, !source.isSyncable {
            // Xcode 4.1 to 9.0 mark it not syncable; 14.0 does not (`indexed-tools-*`).
            guard minimumToolsVersion <= 9 || minimumToolsVersion >= 14, entries.isEmpty else {
                throw NomacError("\(location) is not syncable under minimumToolsVersion Xcode \(minimumToolsVersion), which is not observed yet (BACKLOG B-257)")
            }
            if minimumToolsVersion <= 9 {
                entries = [("com.apple.syncservices.Syncable", "NO")]
            }
        }
        userInfo = entries.isEmpty ? nil : try EntityDescription.userInfo(entries)
        if validation != nil, userInfo != nil {
            throw NomacError("\(location) has both validation and user info, an encoding not observed yet (BACKLOG B-257)")
        }
    }

    var archivedClassNames: [String] { ["NSAttributeDescription", "NSPropertyDescription", "NSObject"] }

    /// `_P`: 0x81 always, 2 optional, 8 transient, 0x30 without validation, 0x40 without user info
    /// (every attribute of the 174 observed `.mom` files).
    private var propertyFlags: Int {
        0x81 | (source.isOptional ? 0x02 : 0) | (source.isTransient ? 0x08 : 0) | (validation == nil ? 0x30 : 0) | (userInfo == nil ? 0x40 : 0)
    }

    func encode(to archiver: KeyedArchiver) throws {
        if source.isOptional {
            archiver.encode(true, forKey: "NSIsOptional")
        }
        if source.isTransient {
            archiver.encode(true, forKey: "NSIsTransient")
        }
        try archiver.encode(source.renamingIdentifier ?? source.name, forKey: "NSRenamingIdentifier")
        try archiver.encode(source.name, forKey: "NSPropertyName")
        archiver.encodeConditional(entity, forKey: "NSEntity")
        if let validation {
            try archiver.encode(ArchivedCollection(.array, objects: validation.predicates.map { .object($0) }), forKey: "NSValidationPredicates")
            try archiver.encode(ArchivedCollection(.array, objects: validation.warnings.map { .number(.integer($0, bits: 64)) }), forKey: "NSValidationWarnings")
        }
        if let userInfo {
            try archiver.encode(userInfo, forKey: "NSUserInfo")
        }
        archiver.encodeInt32(propertyFlags, forKey: "_P")
        archiver.encodeInt32(source.type.rawValue, forKey: "NSAttributeType")
        try archiver.encode(valueClassName, forKey: "NSAttributeValueClassName")
        try archiver.encode(defaultValue, forKey: "NSDefaultValue")
        try archiver.encode(source.valueTransformerName, forKey: "NSValueTransformerName")
        archiver.encodeInt32(source.allowsExternalBinaryDataStorage ? 4 : 0, forKey: "NSFlagsKey")
    }

    private static func valueClassName(_ type: DataModel.AttributeType) -> String? {
        switch type {
        case .integer16, .integer32, .integer64, .double, .float, .boolean: "NSNumber"
        case .decimal: "NSDecimalNumber"
        case .string: "NSString"
        case .date: "NSDate"
        case .binary: "NSData"
        case .uuid: "NSUUID"
        case .uri: "NSURL"
        case .transformable, .undefined: nil
        }
    }

    private static func defaultValue(_ source: DataModel.Attribute, context: ArchiveContext, location: String) throws -> ArchivedItem? {
        if source.type == .date, let interval = source.defaultDateTimeInterval {
            guard let seconds = Double(interval) else {
                throw NomacError("\(location): defaultDateTimeInterval \(interval) is not a number")
            }
            // Floored to whole minutes, as in the .omo (coredata-experiments `omo-date-defaults`).
            return .object(context.date((seconds / 60).rounded(.down) * 60))
        }
        guard let text = source.defaultValue else { return nil }
        if let number = try number(text, type: source.type, location: location) {
            return .number(number)
        }
        if source.type == .string {
            return .string(text)
        }
        throw NomacError("\(location): default values of type \(source.type) are not observed yet (BACKLOG B-257)")
    }

    /// A number of the attribute's type written as the model file writes it, or nil for types
    /// that are not numbers.
    static func number(_ text: String, type: DataModel.AttributeType, location: String) throws -> ArchivedNumber? {
        let number: ArchivedNumber?
        switch type {
        // 64-bit numbers for every width: an Integer 32's default 0 is not `encodeInt32`'s 0
        // (WorldCup).
        case .integer16, .integer32, .integer64: number = .integer(integerValue(text), bits: 64)
        case .double: number = Double(text).map { .double($0) }
        case .float: number = Float(text).map { .float($0) }
        case .boolean: number = ["YES": true, "1": true, "NO": false, "0": false][text].map { .boolean($0) }
        default: return nil
        }
        guard let number else {
            throw NomacError("\(location): \"\(text)\" is not a value of type \(type)")
        }
        return number
    }

    /// `NSString.integerValue`: leading whitespace, a sign and the digits that follow; 0 without
    /// digits (`"0.0"` for an Integer 16 in EmployeeDirectory, `"YES"` for an Integer 32 in moonlight).
    private static func integerValue(_ text: String) -> Int {
        var rest = Substring(text).drop { $0 == " " || $0 == "\t" }
        let negative = rest.first == "-"
        if rest.first == "-" || rest.first == "+" { rest = rest.dropFirst() }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        let magnitude = Int(digits) ?? 0
        return negative ? -magnitude : magnitude
    }

    /// The predicates and warning codes momc derives from minValueString and maxValueString.
    private static func validation(_ source: DataModel.Attribute, context: ArchiveContext,
                                   location: String) throws -> (predicates: [Predicate], warnings: [Int])? {
        guard source.minimum != nil || source.maximum != nil else { return nil }
        let left: () -> Expression
        let codes: (tooSmall: Int, tooLarge: Int)
        let bound: (String) throws -> ArchivedNumber
        switch source.type {
        case .integer16, .integer32, .integer64, .double, .float:
            left = { context.evaluatedObject }
            codes = (1620, 1610)
            // A Float's bounds are archived as doubles read from the text (coredata-experiments
            // `omo-val-float`: 0.1 is Double 0.1).
            bound = { try number($0, type: source.type == .float ? .double : source.type, location: location)! }
        case .string:
            // Each predicate has its own key path expression around the shared `SELF` (`min-max`).
            left = { .keyPath("length", operand: context.evaluatedObject) }
            codes = (1670, 1660)
            bound = { try number($0, type: .integer64, location: location)! }
        default:
            throw NomacError("\(location): validation of type \(source.type) is not observed yet (BACKLOG B-257)")
        }
        var predicates: [Predicate] = []
        var warnings: [Int] = []
        if let minimum = source.minimum {
            predicates.append(Predicate(left: left(), right: .constant(try bound(minimum)), operator: 3))
            warnings.append(codes.tooSmall)
        }
        if let maximum = source.maximum {
            predicates.append(Predicate(left: left(), right: .constant(try bound(maximum)), operator: 1))
            warnings.append(codes.tooLarge)
        }
        return (predicates, warnings)
    }
}

final class RelationshipDescription: KeyedArchivable {
    private let source: DataModel.Relationship
    private unowned let entity: EntityDescription
    private unowned let destination: EntityDescription

    init(_ source: DataModel.Relationship, entity: EntityDescription, destination: EntityDescription) throws {
        guard !source.isTransient else {
            throw NomacError("relationship \(entity.source.name).\(source.name) is transient, which is not observed yet (BACKLOG B-257)")
        }
        self.source = source
        self.entity = entity
        self.destination = destination
    }

    var archivedClassNames: [String] { ["NSRelationshipDescription", "NSPropertyDescription", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        if source.isOptional {
            archiver.encode(true, forKey: "NSIsOptional")
        }
        if source.isOrdered {
            archiver.encode(true, forKey: "NSIsOrdered")
        }
        try archiver.encode(source.renamingIdentifier ?? source.name, forKey: "NSRenamingIdentifier")
        try archiver.encode(source.name, forKey: "NSPropertyName")
        archiver.encodeConditional(entity, forKey: "NSEntity")
        // `_P`: 0xF1 always, 2 optional, 0x400 ordered.
        archiver.encodeInt32(0xF1 | (source.isOptional ? 0x02 : 0) | (source.isOrdered ? 0x400 : 0), forKey: "_P")
        archiver.encodeInt32(source.maxCount, forKey: "NSMaxCount")
        archiver.encodeInt32(source.minCount, forKey: "NSMinCount")
        archiver.encodeInt32(source.deleteRule.rawValue, forKey: "NSDeleteRule")
        archiver.encodeConditional(destination, forKey: "NSDestinationEntity")
        try archiver.encode(source.destination, forKey: "_NSDestinationEntityName")
        archiver.encodeConditional(source.inverseName.flatMap { destination.inverse(named: $0) }, forKey: "NSInverseRelationship")
        try archiver.encode(source.inverseName, forKey: "_NSInverseRelationshipName")
    }
}

final class FetchIndexDescription: KeyedArchivable {
    private let name: String
    private var elements: [FetchIndexElementDescription] = []
    private weak var entity: EntityDescription?

    init(name: String, elements: [(property: String, ascending: Bool)], entity: EntityDescription?) {
        self.name = name
        self.entity = entity
        self.elements = elements.map { FetchIndexElementDescription(property: $0.property, ascending: $0.ascending, index: self) }
    }

    var archivedClassNames: [String] { ["NSFetchIndexDescription", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(name, forKey: "NSIndexName")
        try archiver.encode(ArchivedCollection(.array, objects: elements.map { .object($0) }), forKey: "NSIndexElements")
        try archiver.encode(entity, forKey: "NSEntity")
        try archiver.encode(nil as ArchivedItem?, forKey: "NSPartialIndexPredicate")
    }
}

final class FetchIndexElementDescription: KeyedArchivable {
    private let property: String
    private let ascending: Bool
    private unowned let index: FetchIndexDescription

    init(property: String, ascending: Bool, index: FetchIndexDescription) {
        self.property = property
        self.ascending = ascending
        self.index = index
    }

    var archivedClassNames: [String] { ["NSFetchIndexElementDescription", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(property, forKey: "NSPropertyName")
        archiver.encodeInteger(0, forKey: "NSFetchIndexElementType")
        try archiver.encode(index, forKey: "NSFetchIndexDescription")
        archiver.encode(ascending, forKey: "NSAscending")
    }
}

final class FetchRequest: KeyedArchivable {
    private unowned let entity: EntityDescription

    init(entity: EntityDescription) {
        self.entity = entity
    }

    var archivedClassNames: [String] { ["NSFetchRequest", "NSPersistentStoreRequest", "NSObject"] }

    /// A template without predicate, sort or limits, as the model file's `<fetchRequest name entity/>`
    /// gives it (fetch-request experiment and BubbleTeaFinder's): flags 30.
    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(nil as ArchivedItem?, forKey: "NSValuesToGroupBy")
        try archiver.encode(nil as ArchivedItem?, forKey: "NSHavingPredicate")
        archiver.encodeInt32(0, forKey: "NSFetchOffset")
        try archiver.encode(nil as ArchivedItem?, forKey: "NSValuesToFetch")
        archiver.encodeConditional(entity, forKey: "NSEntity")
        try archiver.encode(nil as ArchivedItem?, forKey: "NSPredicate")
        try archiver.encode(nil as ArchivedItem?, forKey: "NSSortDescriptors")
        archiver.encodeInt32(0, forKey: "NSFetchLimit")
        archiver.encodeInt32(0, forKey: "NSBatchSize")
        try archiver.encode(nil as ArchivedItem?, forKey: "NSRelationshipKeyPathsForPrefetching")
        archiver.encodeInteger(0, forKey: "NSResultType")
        archiver.encodeInteger(0, forKey: "NSAllocationType")
        archiver.encode(true, forKey: "NSHasFetchRequestFlags")
        archiver.encodeInteger(30, forKey: "NSFetchRequestFlags")
    }
}

/// `NSComparisonPredicate` with its `NSComparisonPredicateOperator` (modifier, options 0).
final class Predicate: KeyedArchivable {
    private let left: Expression
    private let right: Expression
    private let comparison: ComparisonOperator

    init(left: Expression, right: Expression, operator type: Int) {
        self.left = left
        self.right = right
        comparison = ComparisonOperator(type: type)
    }

    var archivedClassNames: [String] { ["NSComparisonPredicate", "NSPredicate", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(left, forKey: "NSLeftExpression")
        try archiver.encode(right, forKey: "NSRightExpression")
        try archiver.encode(comparison, forKey: "NSPredicateOperator")
    }
}

final class ComparisonOperator: KeyedArchivable {
    private let type: Int

    init(type: Int) {
        self.type = type
    }

    var archivedClassNames: [String] { ["NSComparisonPredicateOperator", "NSPredicateOperator", "NSObject"] }

    /// `NSVariant` repeats the operator type (`min-max`: 3 for >=, 1 for <=).
    func encode(to archiver: KeyedArchiver) throws {
        archiver.encodeInteger(type, forKey: "NSOperatorType")
        archiver.encodeInteger(0, forKey: "NSModifier")
        archiver.encodeInteger(type, forKey: "NSVariant")
        archiver.encodeInteger(0, forKey: "NSOptions")
    }
}

/// The `NSExpression`s of validation predicates.
final class Expression: KeyedArchivable {
    enum Kind {
        case evaluatedObject
        case constant(ArchivedNumber)
        case keyPath(String, operand: Expression)
        case keyPathSpecifier(String)
    }

    let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    /// One `SELF` expression per model, as `+[NSExpression expressionForEvaluatedObject]` gives.
    static var evaluatedObject: Expression { Expression(.evaluatedObject) }

    static func constant(_ number: ArchivedNumber) -> Expression { Expression(.constant(number)) }

    static func keyPath(_ path: String, operand: Expression) -> Expression { Expression(.keyPath(path, operand: operand)) }

    var archivedClassNames: [String] {
        switch kind {
        case .evaluatedObject: ["NSSelfExpression", "NSExpression", "NSObject"]
        case .constant: ["NSConstantValueExpression", "NSExpression", "NSObject"]
        case .keyPath: ["NSKeyPathExpression", "NSFunctionExpression", "NSExpression", "NSObject"]
        case .keyPathSpecifier: ["NSKeyPathSpecifierExpression", "NSExpression", "NSObject"]
        }
    }

    func encode(to archiver: KeyedArchiver) throws {
        switch kind {
        case .evaluatedObject:
            archiver.encodeInteger(1, forKey: "NSExpressionType")
        case .constant(let number):
            archiver.encodeInteger(0, forKey: "NSExpressionType")
            try archiver.encode(.number(number), forKey: "NSConstantValue")
        case .keyPath(let path, let operand):
            archiver.encodeInteger(3, forKey: "NSExpressionType")
            try archiver.encode("valueForKey:", forKey: "NSSelectorName")
            try archiver.encode(operand, forKey: "NSOperand")
            let specifier = Expression(.keyPathSpecifier(path))
            try archiver.encode(ArchivedCollection(.mutableArray, objects: [.object(specifier)]), forKey: "NSArguments")
        case .keyPathSpecifier(let path):
            archiver.encodeInteger(10, forKey: "NSExpressionType")
            try archiver.encode(path, forKey: "NSKeyPath")
        }
    }
}
