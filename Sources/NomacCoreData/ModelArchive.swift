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

/// `NSDecimalNumber`'s encoding of a default value, read as `NSDecimalNumber(string:)` reads text
/// (coredata-experiments `decimal-defaults`): blanks, a sign, digits, a point, digits and an exponent,
/// what follows ignored; no digits is the one `notANumber`. A value's trailing zeros go to the
/// exponent; zero keeps its fraction's length as exponent, unless negative, which gives 0.
final class ArchivedDecimal: KeyedArchivable {
    private let exponent: Int
    private let units: [UInt16]
    private let isNegative: Bool

    /// The digits without trailing zeros, what `description` writes; empty for zero.
    private let digits: String

    private init(exponent: Int, units: [UInt16], isNegative: Bool, digits: String) {
        self.exponent = exponent
        self.units = units
        self.isNegative = isNegative
        self.digits = digits
    }

    static var notANumber: ArchivedDecimal { ArchivedDecimal(exponent: 0, units: [], isNegative: true, digits: "") }

    static func defaultValue(_ text: String, context: ArchiveContext?, location: String) throws -> ArchivedDecimal {
        try parse(text, location: location) ?? context?.notANumber ?? notANumber
    }

    /// `description`: `NaN`, `0`, or the value in positional notation (the `.omo` keeps this text:
    /// coredata-experiments `decimal-defaults`).
    var description: String {
        if units.isEmpty { return isNegative ? "NaN" : "0" }
        let sign = isNegative ? "-" : ""
        if exponent >= 0 { return sign + digits + String(repeating: "0", count: exponent) }
        let places = -exponent
        if places >= digits.count { return sign + "0." + String(repeating: "0", count: places - digits.count) + digits }
        return sign + digits.dropLast(places) + "." + digits.suffix(places)
    }

    private static func parse(_ text: String, location: String) throws -> ArchivedDecimal? {
        var rest = Substring(text).drop { $0 == " " || $0 == "\t" }
        var isNegative = false
        if let sign = rest.first, sign == "-" || sign == "+" {
            isNegative = sign == "-"
            rest = rest.dropFirst()
        }
        let whole = rest.prefix { $0.isASCII && $0.isNumber }
        rest = rest.dropFirst(whole.count)
        var fraction = Substring()
        if rest.first == "." {
            rest = rest.dropFirst()
            fraction = rest.prefix { $0.isASCII && $0.isNumber }
            rest = rest.dropFirst(fraction.count)
        }
        guard !whole.isEmpty || !fraction.isEmpty else { return nil }
        var exponent = -fraction.count
        var hasExponent = false
        if let mark = rest.first, mark == "e" || mark == "E" {
            let digits = rest.dropFirst().drop { $0 == "-" || $0 == "+" }.prefix { $0.isASCII && $0.isNumber }
            guard let written = Int(digits) else {
                throw NomacError("\(location): the default value \"\(text)\" is not observed yet (BACKLOG B-257)")
            }
            hasExponent = true
            exponent += rest.dropFirst().first == "-" ? -written : written
        }
        var digits = Array((whole + fraction).drop { $0 == "0" })
        if digits.isEmpty {
            guard !hasExponent else {
                throw NomacError("\(location): the default value \"\(text)\" is not observed yet (BACKLOG B-257)")
            }
            return ArchivedDecimal(exponent: isNegative ? 0 : exponent, units: [], isNegative: false, digits: "")
        }
        while digits.last == "0" {
            digits.removeLast()
            exponent += 1
        }
        guard digits.count <= 38, (-38...38).contains(exponent) else {
            throw NomacError("\(location): the default value \"\(text)\" needs rounding, which is not observed yet (BACKLOG B-257)")
        }
        var units: [UInt16] = []
        for digit in digits {
            var carry = UInt32(digit.wholeNumberValue!)
            for index in units.indices {
                let value = UInt32(units[index]) * 10 + carry
                units[index] = UInt16(truncatingIfNeeded: value)
                carry = value >> 16
            }
            if carry > 0 { units.append(UInt16(carry)) }
        }
        return ArchivedDecimal(exponent: exponent, units: units, isNegative: isNegative, digits: String(digits))
    }

    var archivedClassNames: [String] { ["NSDecimalNumberPlaceholder", "NSDecimalNumber", "NSNumber", "NSValue", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        archiver.encodeInt32(exponent, forKey: "NS.exponent")
        archiver.encodeInt32(units.count, forKey: "NS.length")
        archiver.encode(isNegative, forKey: "NS.negative")
        archiver.encode(!units.isEmpty, forKey: "NS.compact")
        archiver.encodeInt32(1, forKey: "NS.mantissa.bo")
        let padded = units + [UInt16](repeating: 0, count: 8 - units.count)
        archiver.encodeBytes(padded.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }, forKey: "NS.mantissa")
    }
}

final class ManagedObjectModel: KeyedArchivable {
    private var entities: ArchivedCollection!
    private var fetchRequestTemplates: ArchivedCollection?
    private let versionIdentifiers: ArchivedCollection

    init(_ model: DataModel, module: String?) throws {
        versionIdentifiers = ArchivedCollection(.set, objects: [.string(model.versionIdentifier)])
        let context = ArchiveContext()
        var described: [String: EntityDescription] = [:]
        for entity in model.entities {
            guard described[entity.name] == nil else {
                throw NomacError("two entities are named \(entity.name)")
            }
            described[entity.name] = try EntityDescription(entity, model: self, module: module, marksUnsyncable: model.marksUnsyncable, context: context)
        }
        for entity in model.entities {
            try described[entity.name]!.link(described, legacyIndexes: model.hasLegacyIndexes, marksUnsyncable: model.marksUnsyncable)
        }
        for (parent, names) in try model.subentityNames() {
            described[parent]?.subentities = names.map { described[$0]! }
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
    let notANumber = ArchivedDecimal.notANumber
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
    /// A class of the current module is a string built for each entity (the survey's Bitwarden has
    /// two entities of one class).
    private let classNameObject: StringObject?
    private let context: ArchiveContext
    private(set) var parent: EntityDescription?
    fileprivate var subentities: [EntityDescription] = []
    private var properties: ArchivedCollection!
    private var userInfo: ArchivedCollection
    private var fetchIndexes: [FetchIndexDescription] = []
    /// The property names of every fetch index of several attributes (`NSCompoundIndexes`).
    private var compoundIndexes: [[String]] = []
    private(set) var described: [String: KeyedArchivable] = [:]

    init(_ source: DataModel.Entity, model: ManagedObjectModel, module: String?, marksUnsyncable: Bool, context: ArchiveContext) throws {
        self.source = source
        self.model = model
        self.context = context
        // No class is NSManagedObject (coredata-experiments `no-class`).
        let represented = source.className ?? "NSManagedObject"
        if represented.hasPrefix(".") {
            guard let module else {
                throw NomacError("entity \(source.name)'s class \(represented) is in the current module, and momc was given no --module")
            }
            className = module + represented
            classNameObject = StringObject(className)
        } else {
            className = represented
            classNameObject = nil
        }
        let entries = Self.markingUnsyncable(source.userInfo, hasSyncable: source.hasSyncable, marks: marksUnsyncable)
        userInfo = entries.isEmpty ? context.emptyUserInfo : try Self.userInfo(entries)
    }

    /// The file's entries, then `com.apple.syncservices.Syncable` for what an old `minimumToolsVersion`
    /// marks not syncable (coredata-experiments `syncable-*`).
    static func markingUnsyncable(_ entries: [(String, String)], hasSyncable: Bool, marks: Bool) -> [(String, String)] {
        marks && !hasSyncable ? entries + [("com.apple.syncservices.Syncable", "NO")] : entries
    }

    static func userInfo(_ entries: [(String, String)]) throws -> ArchivedCollection {
        let order = try FoundationHashTable.inserting(entries.map(\.0)).copied().keys
        return .dictionary(.dictionary, entries.map { ($0.0, .string($0.1)) }, order: order)
    }

    func link(_ entities: [String: EntityDescription], legacyIndexes: Bool, marksUnsyncable: Bool) throws {
        if let parentName = source.parentName {
            guard let parent = entities[parentName] else {
                throw NomacError("entity \(source.name)'s parent \(parentName) is not in the model")
            }
            self.parent = parent
        }
        var entries: [(String, ArchivedItem)] = []
        for property in source.properties {
            let description: KeyedArchivable
            switch property {
            case .attribute(let attribute):
                description = try AttributeDescription(attribute, entity: self, context: context, marksUnsyncable: marksUnsyncable)
            case .relationship(let relationship):
                guard let destination = entities[relationship.destination] else {
                    throw NomacError("relationship \(source.name).\(relationship.name) names the entity \(relationship.destination), which is not in the model")
                }
                description = try RelationshipDescription(relationship, entity: self, destination: destination, marksUnsyncable: marksUnsyncable)
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

    /// A property of the entity or its parents (coredata-experiments `inverse-inherited`).
    func inverse(named name: String) -> KeyedArchivable? {
        described[name] ?? parent?.inverse(named: name)
    }

    var archivedClassNames: [String] { ["NSEntityDescription", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        try archiver.encode(source.name, forKey: "NSEntityName")
        // NSManagedObject itself is archived as no class (coredata-experiments `omo-default-class`).
        try archiver.encode(className == "NSManagedObject" ? nil : classNameObject.map(ArchivedItem.stringObject) ?? .string(className), forKey: "NSClassNameForEntity")
        if source.isAbstract {
            archiver.encode(true, forKey: "NSIsAbstract")
        }
        archiver.encodeConditional(model, forKey: "NSManagedObjectModel")
        archiver.encodeConditional(parent, forKey: "NSSuperentity")
        let names = subentities.map(\.source.name)
        try archiver.encode(ArchivedCollection.dictionary(.mutableDictionary, subentities.map { ($0.source.name, .object($0)) }, order: names), forKey: "NSSubentities")
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
    private let valueClassName: ArchivedItem?
    private let defaultValue: ArchivedItem?
    private let validation: (predicates: [Predicate], warnings: [Int])?
    private let userInfo: ArchivedCollection?
    // A transient property keeps neither (coredata-experiments `property-flags-transient`).
    private var isIndexedBySpotlight: Bool { source.isIndexedBySpotlight && !source.isTransient }
    private var isStoredInTruth: Bool { source.isStoredInTruth && !source.isTransient }

    init(_ source: DataModel.Attribute, entity: EntityDescription, context: ArchiveContext, marksUnsyncable: Bool) throws {
        self.source = source
        self.entity = entity
        let location = "attribute \(entity.source.name).\(source.name)"
        // NSDecimalNumber is too long for a tagged pointer, and momc makes a new string for each
        // attribute (coredata-experiments `decimal-several`).
        valueClassName = source.customClassName.map { .string($0) }
            ?? (source.type == .decimal ? .stringObject(StringObject("NSDecimalNumber")) : OptimizedModel.valueClass(source.type).map { .string($0) })
        defaultValue = try Self.defaultValue(source, context: context, location: location)
        validation = try Self.validation(source, context: context, location: location)
        let entries = EntityDescription.markingUnsyncable(source.userInfo, hasSyncable: source.hasSyncable, marks: marksUnsyncable)
        userInfo = entries.isEmpty ? nil : try EntityDescription.userInfo(entries)
    }

    var archivedClassNames: [String] { ["NSAttributeDescription", "NSPropertyDescription", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        if source.isOptional {
            archiver.encode(true, forKey: "NSIsOptional")
        }
        if source.isTransient {
            archiver.encode(true, forKey: "NSIsTransient")
        }
        if isIndexedBySpotlight {
            archiver.encode(true, forKey: "NSIndexedBySpotlight")
        }
        if isStoredInTruth {
            archiver.encode(true, forKey: "NSIsStoredInTruth")
        }
        if source.allowsCloudEncryption {
            archiver.encode(true, forKey: "NSAllowsCloudEncryption")
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
        if let modifier = source.versionHashModifier {
            try archiver.encode(modifier, forKey: "NSVersionHashModifier")
        }
        archiver.encodeInt32(PropertyFlags.value(isOptional: source.isOptional, isTransient: source.isTransient, isIndexedBySpotlight: isIndexedBySpotlight,
                                                 isStoredInTruth: isStoredInTruth, isOrdered: false, allowsCloudEncryption: source.allowsCloudEncryption,
                                                 hasValidation: validation != nil, hasUserInfo: userInfo != nil,
                                                 hasVersionHashModifier: source.versionHashModifier != nil), forKey: "_P")
        archiver.encodeInt32(source.type.rawValue, forKey: "NSAttributeType")
        try archiver.encode(valueClassName, forKey: "NSAttributeValueClassName")
        try archiver.encode(defaultValue, forKey: "NSDefaultValue")
        try archiver.encode(source.valueTransformerName, forKey: "NSValueTransformerName")
        archiver.encodeInt32(source.allowsExternalBinaryDataStorage ? 4 : 0, forKey: "NSFlagsKey")
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
        switch source.type {
        case .string:
            return .string(text)
        case .decimal:
            return .object(try ArchivedDecimal.defaultValue(text, context: context, location: location))
        // momc drops them (coredata-experiments `default-ignored`).
        case .binary, .uuid, .uri, .transformable:
            return nil
        default:
            throw NomacError("\(location): default values of type \(source.type) are not observed yet (BACKLOG B-257)")
        }
    }

    /// A number of the attribute's type written as the model file writes it, or nil for types
    /// that are not numbers.
    static func number(_ text: String, type: DataModel.AttributeType, location: String) throws -> ArchivedNumber? {
        let number: ArchivedNumber?
        switch type {
        // 64-bit numbers for every width: an Integer 32's default 0 is not `encodeInt32`'s 0
        // (WorldCup).
        case .integer16, .integer32, .integer64: number = .integer(ModelElement.integerValue(text), bits: 64)
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

    /// The predicates and warning codes momc derives from minValueString and maxValueString.
    private static func validation(_ source: DataModel.Attribute, context: ArchiveContext,
                                   location: String) throws -> (predicates: [Predicate], warnings: [Int])? {
        guard source.minimum != nil || source.maximum != nil || source.regularExpression != nil else { return nil }
        let left: () -> Expression
        let codes: (tooSmall: Int, tooLarge: Int)
        let bound: (String) throws -> ArchivedNumber
        if source.regularExpression != nil, source.type != .string {
            throw NomacError("\(location): a regular expression on type \(source.type) is not observed yet (BACKLOG B-257)")
        }
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
        if let expression = source.regularExpression {
            predicates.append(Predicate(left: context.evaluatedObject, right: .string(expression), matching: true))
            warnings.append(1680)
        }
        return (predicates, warnings)
    }
}

final class RelationshipDescription: KeyedArchivable {
    private let source: DataModel.Relationship
    private unowned let entity: EntityDescription
    private unowned let destination: EntityDescription
    private let userInfo: ArchivedCollection?
    private var isIndexedBySpotlight: Bool { source.isIndexedBySpotlight && !source.isTransient }
    private var isStoredInTruth: Bool { source.isStoredInTruth && !source.isTransient }

    init(_ source: DataModel.Relationship, entity: EntityDescription, destination: EntityDescription, marksUnsyncable: Bool) throws {
        self.source = source
        self.entity = entity
        self.destination = destination
        let entries = EntityDescription.markingUnsyncable(source.userInfo, hasSyncable: source.hasSyncable, marks: marksUnsyncable)
        userInfo = entries.isEmpty ? nil : try EntityDescription.userInfo(entries)
    }

    var archivedClassNames: [String] { ["NSRelationshipDescription", "NSPropertyDescription", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        if source.isOptional {
            archiver.encode(true, forKey: "NSIsOptional")
        }
        if source.isTransient {
            archiver.encode(true, forKey: "NSIsTransient")
        }
        if isIndexedBySpotlight {
            archiver.encode(true, forKey: "NSIndexedBySpotlight")
        }
        if isStoredInTruth {
            archiver.encode(true, forKey: "NSIsStoredInTruth")
        }
        if source.isOrdered {
            archiver.encode(true, forKey: "NSIsOrdered")
        }
        try archiver.encode(source.renamingIdentifier ?? source.name, forKey: "NSRenamingIdentifier")
        try archiver.encode(source.name, forKey: "NSPropertyName")
        archiver.encodeConditional(entity, forKey: "NSEntity")
        if let userInfo {
            try archiver.encode(userInfo, forKey: "NSUserInfo")
        }
        if let modifier = source.versionHashModifier {
            try archiver.encode(modifier, forKey: "NSVersionHashModifier")
        }
        archiver.encodeInt32(PropertyFlags.value(isOptional: source.isOptional, isTransient: source.isTransient, isIndexedBySpotlight: isIndexedBySpotlight,
                                                 isStoredInTruth: isStoredInTruth, isOrdered: source.isOrdered, allowsCloudEncryption: false,
                                                 hasValidation: false, hasUserInfo: userInfo != nil,
                                                 hasVersionHashModifier: source.versionHashModifier != nil), forKey: "_P")
        archiver.encodeInt32(source.maxCount, forKey: "NSMaxCount")
        archiver.encodeInt32(source.minCount, forKey: "NSMinCount")
        archiver.encodeInt32(source.deleteRule.rawValue, forKey: "NSDeleteRule")
        archiver.encodeConditional(destination, forKey: "NSDestinationEntity")
        try archiver.encode(source.destination, forKey: "_NSDestinationEntityName")
        archiver.encodeConditional(source.inverseName.flatMap { destination.inverse(named: $0) }, forKey: "NSInverseRelationship")
        try archiver.encode(source.inverseName, forKey: "_NSInverseRelationshipName")
    }
}

/// `_P`, an attribute's or a relationship's flags: 1 always, 2 optional, 8 transient, 0x100 indexed
/// by Spotlight, 0x200 stored in truth, 0x400 ordered, 0x800 cloud encryption; 0x30 without
/// validation, 0x40 without user info, 0x80 without a version hash modifier
/// (coredata-experiments `property-flags-*`).
enum PropertyFlags {
    static func value(isOptional: Bool, isTransient: Bool, isIndexedBySpotlight: Bool, isStoredInTruth: Bool, isOrdered: Bool,
                      allowsCloudEncryption: Bool, hasValidation: Bool, hasUserInfo: Bool, hasVersionHashModifier: Bool) -> Int {
        var flags = 0x01
        if isOptional { flags |= 0x02 }
        if isTransient { flags |= 0x08 }
        if !hasValidation { flags |= 0x30 }
        if !hasUserInfo { flags |= 0x40 }
        if !hasVersionHashModifier { flags |= 0x80 }
        if isIndexedBySpotlight { flags |= 0x100 }
        if isStoredInTruth { flags |= 0x200 }
        if isOrdered { flags |= 0x400 }
        if allowsCloudEncryption { flags |= 0x800 }
        return flags
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
    private let comparison: KeyedArchivable

    init(left: Expression, right: Expression, operator type: Int) {
        self.left = left
        self.right = right
        comparison = ComparisonOperator(type: type)
    }

    /// A regular expression's `MATCHES` (coredata-experiments `regular-expression`).
    init(left: Expression, right: Expression, matching: Bool) {
        self.left = left
        self.right = right
        comparison = MatchingOperator()
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

final class MatchingOperator: KeyedArchivable {
    var archivedClassNames: [String] { ["NSMatchingPredicateOperator", "NSStringPredicateOperator", "NSPredicateOperator", "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        archiver.encodeInteger(6, forKey: "NSOperatorType")
        archiver.encodeInteger(0, forKey: "NSModifier")
        archiver.encodeInteger(0, forKey: "NSFlags")
    }
}

/// The `NSExpression`s of validation predicates.
final class Expression: KeyedArchivable {
    enum Kind {
        case evaluatedObject
        case constant(ArchivedNumber)
        case stringConstant(String)
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

    static func string(_ text: String) -> Expression { Expression(.stringConstant(text)) }

    static func keyPath(_ path: String, operand: Expression) -> Expression { Expression(.keyPath(path, operand: operand)) }

    var archivedClassNames: [String] {
        switch kind {
        case .evaluatedObject: ["NSSelfExpression", "NSExpression", "NSObject"]
        case .constant, .stringConstant: ["NSConstantValueExpression", "NSExpression", "NSObject"]
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
        case .stringConstant(let text):
            archiver.encodeInteger(0, forKey: "NSExpressionType")
            try archiver.encode(text, forKey: "NSConstantValue")
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
