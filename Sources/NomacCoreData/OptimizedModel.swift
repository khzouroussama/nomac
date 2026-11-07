import Foundation
import NomacCore
import NomacPlist

/// The `.omo` momc writes beside the `.mom` of a `.momd`'s current version (docs/formats/coredata.md
/// "`.omo`"). Every record is momc's but the SQL entities' column-name lists, which nomac writes
/// sorted where momc follows a hash table nobody has identified: ADR 0230 shows Core Data reads
/// and migrates stores the same with any order. Models using records not decoded yet are refused
/// (BACKLOG B-256).
enum OptimizedModel {
    static let magic = Array("momv2$srsraori55717101jhus-[6910aathnnhi86786714[-;uadmiraenv143".utf8)
    static let marker: UInt32 = 0xDAED_FEEB
    /// The value class each attribute type archives (none for Transformable).
    static func valueClass(_ type: DataModel.AttributeType) -> String? {
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

    // MARK: Refusals

    /// What the observed `.omo` files cover (117 of 137 reproduced given momc's column order;
    /// the others use one of these, each refused).
    static func refuseUnobserved(_ model: DataModel, path: String) throws {
        func refuse(_ what: String) -> NomacError {
            NomacError("the .omo of a model with \(what) is not reproduced yet (BACKLOG B-256)", path: path)
        }
        for entity in model.entities {
            for property in entity.properties {
                if case .relationship(let relationship) = property, relationship.isTransient {
                    throw refuse("a transient relationship (\(entity.name).\(relationship.name))")
                }
            }
        }
    }

    // MARK: Writing

    /// An interned table: each distinct value once, entry 0 the empty value, the others in
    /// first-use order.
    struct Table<Value: Hashable> {
        var items: [Value]
        var index: [Value: Int]

        init(empty: Value) {
            items = [empty]
            index = [empty: 0]
        }

        mutating func callAsFunction(_ value: Value?) -> Int {
            guard let value else { return 0 }
            if let known = index[value] { return known }
            index[value] = items.count
            items.append(value)
            return items.count - 1
        }
    }

    struct Output {
        var bytes: [UInt8] = []
        var position: Int { bytes.count }

        mutating func u32(_ values: Int...) { values.forEach { append(UInt64(truncatingIfNeeded: $0), width: 4) } }
        mutating func u32(_ values: [Int]) { values.forEach { append(UInt64(truncatingIfNeeded: $0), width: 4) } }
        mutating func u16(_ values: [Int]) { values.forEach { append(UInt64(truncatingIfNeeded: $0), width: 2) } }
        mutating func u64(_ values: [UInt64]) {
            align(8)
            values.forEach { append($0, width: 8) }
        }
        mutating func align(_ width: Int) {
            while bytes.count % width != 0 { bytes.append(0) }
        }
        mutating func zeros(_ count: Int) { bytes += [UInt8](repeating: 0, count: count) }
        mutating func marks(_ count: Int = 2) {
            for _ in 0..<count { bytes += [0xEF, 0xBE, 0xAD, 0xDE] }
        }
        mutating func set(_ value: Int, at offset: Int) {
            for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (24 - 8 * index)) }
        }
        private mutating func append(_ value: UInt64, width: Int) {
            for index in (0..<width).reversed() { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(index)))) }
        }
    }

    /// A property of an entity, with its group: persistent attributes, transient attributes,
    /// to-one, to-many and ordered to-many relationships; and the entity that declares it.
    struct Member {
        var property: DataModel.Property
        var group: Int
        var owner: String
    }

    /// Each group's inherited properties first, the root's first, then the entity's own, each
    /// entity's by UTF-8 name (`omo-inh-chain`, `omo-inh-rel-own1`).
    static func chain(_ entity: DataModel.Entity, _ byName: [String: DataModel.Entity]) -> [DataModel.Entity] {
        var chain = [entity]
        while let parent = chain[0].parentName.flatMap({ byName[$0] }) { chain.insert(parent, at: 0) }
        return chain
    }

    static func members(_ entity: DataModel.Entity, _ byName: [String: DataModel.Entity]) -> [Member] {
        func group(_ property: DataModel.Property) -> Int {
            switch property {
            case .attribute(let attribute): attribute.isTransient ? 1 : 0
            case .relationship(let relationship): !relationship.isToMany ? 2 : relationship.isOrdered ? 4 : 3
            }
        }
        return (0..<5).flatMap { index in
            chain(entity, byName).flatMap { owner in
                owner.properties.sorted { Array($0.name.utf8).lexicographicallyPrecedes(Array($1.name.utf8)) }
                    .filter { group($0) == index }.map { Member(property: $0, group: index, owner: owner.name) }
            }
        }
    }

    static func data(_ model: DataModel, module: String?, path: String) throws -> [UInt8] {
        try refuseUnobserved(model, path: path)
        let entities = model.entities.sorted { Array($0.name.utf8).lexicographicallyPrecedes(Array($1.name.utf8)) }
        let entityIndex = Dictionary(uniqueKeysWithValues: entities.enumerated().map { ($0.element.name, $0.offset) })
        let byName = Dictionary(uniqueKeysWithValues: entities.map { ($0.name, $0) })
        // Subentities by name here, unlike the `.mom`'s dictionary (27 of 27 lists of several, the survey).
        let children = Dictionary(grouping: entities.filter { $0.parentName != nil }) { $0.parentName! }
        func root(_ entity: DataModel.Entity) -> DataModel.Entity { entity.parentName.flatMap { byName[$0] }.map(root) ?? entity }
        func hierarchy(_ entity: DataModel.Entity) -> [DataModel.Entity] { [entity] + (children[entity.name] ?? []).flatMap(hierarchy) }
        // An entity's number in SQL names: roots by name, each followed by its subentities by name,
        // depth first (68 of 68 `_Z<number>_` columns of the survey's models).
        func numbered(_ entity: DataModel.Entity) -> [String] {
            [entity.name] + (children[entity.name] ?? []).flatMap(numbered)
        }
        let numberedEntities = entities.filter { $0.parentName == nil }.flatMap(numbered)
        let entityNumber = Dictionary(uniqueKeysWithValues: numberedEntities.enumerated().map { ($0.element, $0.offset + 1) })
        // To-ones of one name in one family share a table: the second in entity number order is
        // `_Z<NAME>1`, the third `_Z<NAME>2` (coredata-experiments `sibling-keys-*`).
        var foreignKeys: [String: String] = [:]
        var taken: [String: Int] = [:]
        for name in numberedEntities {
            let entity = byName[name]!
            for case .relationship(let relationship) in entity.properties where !relationship.isToMany && !relationship.isTransient {
                let key = root(entity).name + "." + relationship.name.uppercased()
                foreignKeys[name + "." + relationship.name] = relationship.name.uppercased() + (taken[key].map(String.init) ?? "")
                taken[key, default: 0] += 1
            }
        }
        let entityHashes = try VersionHash.entities(of: model)
        var strings = Table<String>(empty: "")
        var names = Table<String>(empty: "")
        var blobs = Table<[UInt8]>(empty: [])
        // Fetch request templates in the order of a copy of a dictionary of their names, as in the
        // .mom; their names first in C, a lookup table after the entities' (`omo-fr-several`).
        let requests = try FoundationHashTable.inserting(model.fetchRequests.map(\.name)).copied().keys
            .map { name in model.fetchRequests.first { $0.name == name }! }
        for request in requests { _ = names(request.name) }
        _ = names("PF_DEFAULT_CONFIGURATION_NAME")
        _ = blobs(try KeyedArchiver.archive(item: .string(model.versionIdentifier)))

        // Lookup tables: the entities, then per entity its properties, its subentities when it has
        // some, its attributes and its relationships.
        var tables: [[String]] = [entities.map(\.name)] + (requests.isEmpty ? [] : [requests.map(\.name)])
        var firstTable: [String: Int] = [:]
        for entity in entities {
            let all = members(entity, byName).map(\.property)
            firstTable[entity.name] = tables.count
            tables.append(all.map(\.name))
            if let subentities = children[entity.name] { tables.append(subentities.map(\.name)) }
            tables.append(all.filter(\.isAttribute).map(\.name))
            tables.append(all.filter { !$0.isAttribute }.map(\.name))
        }

        struct Record {
            var property: DataModel.Property
            var hash: Int, entity: Int, name: Int, index: Int
            var valueClass = 0, transformer = 0, userInfo = 0, modifier = 0
            var defaultValue: (wide: Bool, value: UInt64)?
            /// The data table's archives of a regular expression's predicate and warning code.
            var regularExpression: (predicate: Int, warning: Int)?
            var inverse: Int?
            var renaming: Int?
            var minimum: UInt64?, maximum: UInt64?
        }
        var records: [Record] = []
        var recordIndex: [String: Int] = [:]
        var entityRecords: [(modifier: Int, name: Int, hash: Int, className: Int, uname: Int, properties: [Int], indexes: [[Int]], constraints: [[Int]], userInfo: Int)] = []
        func marked(_ entries: [(String, String)], hasSyncable: Bool) -> [(String, String)] {
            EntityDescription.markingUnsyncable(entries, hasSyncable: hasSyncable, marks: model.marksUnsyncable)
        }
        var indexCount = 0, elementCount = 0
        // Inherited members point to their declaring entity's records, which a later entity may hold.
        var inherited: [(entity: Int, position: Int, record: String)] = []
        var columnLists: [[String]] = []
        for (index, entity) in entities.enumerated() {
            let all = members(entity, byName)
            let modifier = strings(entity.versionHashModifier)
            let uname = strings(entity.renamingIdentifier ?? entity.name)
            let hash = blobs(entityHashes[entity.name]!)
            // User info is an archived dictionary after the version hash (`omo-user-info`).
            let userInfo = try userInfoBlob(marked(entity.userInfo, hasSyncable: entity.hasSyncable), &blobs)
            let name = names(entity.name)
            let className = names(try Self.className(entity, module: module))
            // Per index: its name, 0, its count of elements, then per element the property, 0,
            // ascending and 0 (`omo-fi-several`).
            let indexes = try entity.indexes(legacy: model.hasLegacyIndexes).map { index in
                [names(index.name), 0, index.elements.count] + index.elements.flatMap { [names($0.property), 0, $0.ascending ? 1 : 0, 0] }
            }
            indexCount += indexes.count
            elementCount += indexes.map { ($0.count - 3) / 4 }.reduce(0, +)
            var properties: [Int] = []
            for (position, member) in all.enumerated() {
                guard member.owner == entity.name else {
                    inherited.append((index, position, member.owner + "." + member.property.name))
                    properties.append(0)
                    continue
                }
                var record = Record(property: member.property, hash: blobs(VersionHash.property(member.property, owner: member.owner)), entity: index,
                                    name: names(member.property.name), index: position)
                record.modifier = strings(member.property.versionHashModifier)
                if let renaming = member.property.renamingIdentifier, renaming != member.property.name {
                    record.renaming = strings(renaming)
                }
                if case .relationship(let relationship) = member.property {
                    record.userInfo = try userInfoBlob(marked(relationship.userInfo, hasSyncable: relationship.hasSyncable), &blobs)
                }
                if case .attribute(let attribute) = member.property {
                    record.userInfo = try userInfoBlob(marked(attribute.userInfo, hasSyncable: attribute.hasSyncable), &blobs)
                    // A regular expression's predicate and warning code are archives of their own;
                    // bounds stay numbers (`regular-expression`).
                    if let expression = attribute.regularExpression {
                        let predicate = Predicate(left: .evaluatedObject, right: .string(expression), matching: true)
                        record.regularExpression = (blobs(try KeyedArchiver.archive(predicate)),
                                                    blobs(try KeyedArchiver.archive(item: .number(.integer(1680, bits: 64)))))
                    }
                    record.valueClass = names(attribute.customClassName ?? valueClass(attribute.type))
                    record.transformer = strings(attribute.valueTransformerName)
                    record.defaultValue = try defaultValue(attribute, strings: &strings, names: &names, path: path)
                    record.minimum = try attribute.minimum.map { try bound($0, attribute, path: path) }
                    record.maximum = try attribute.maximum.map { try bound($0, attribute, path: path) }
                }
                recordIndex[entity.name + "." + member.property.name] = records.count
                properties.append(records.count)
                records.append(record)
            }
            // Columns fill a dictionary from the root entity down, each entity's attributes, to-one
            // and to-many relationships by name; order keys come last (766 of 766 entities of the
            // survey's models, coredata_survey.py).
            var columns = ["_ent", "_pk", "_opt"]
            var orderKeys: [String] = []
            for owner in chain(entity, byName) {
                let own = owner.properties.filter { !$0.isTransient }.sorted { Array($0.name.utf8).lexicographicallyPrecedes(Array($1.name.utf8)) }
                for case .attribute(let attribute) in own { columns.append(attribute.name) }
                for case .relationship(let relationship) in own where !relationship.isToMany {
                    let key = foreignKeys[owner.name + "." + relationship.name]!
                    columns.append("_Z" + key)
                    // A destination with subentities adds the column of its entity number
                    // (`omo-inh-fk`: `_Z2_B` for entity 2; `omo-inh-fk-sub`).
                    if children[relationship.destination] != nil {
                        columns.append("_Z\(entityNumber[relationship.destination]!)_" + key)
                    }
                    columns.append(relationship.name)
                    if let inverse = byName[relationship.destination]?.properties.first(where: { $0.name == relationship.inverseName }),
                       case .relationship(let ordered) = inverse, ordered.isOrdered {
                        orderKeys.append("_Z_FOK_" + key)
                    }
                }
                for case .relationship(let relationship) in own where relationship.isToMany && !relationship.isOrdered { columns.append(relationship.name) }
                for case .relationship(let relationship) in own where relationship.isToMany && relationship.isOrdered { columns.append(relationship.name) }
            }
            // A to-many without an inverse is a hidden to-one on its destination, named after the
            // source's entity number (`omo-rel-no-inverse`, `omo-ordered`).
            for other in entities {
                for case .relationship(let relationship) in other.properties
                where relationship.destination == entity.name && relationship.isToMany && relationship.inverseName == nil {
                    let hidden = "\(entityNumber[other.name]!)\(relationship.name)"
                    columns += ["_Z" + hidden.uppercased(), hidden] + (relationship.isOrdered ? ["_Z_FOK_" + hidden.uppercased()] : [])
                }
            }
            columns += orderKeys
            // The column names are interned in the order of a copy of a dictionary filled with
            // them (docs/formats/foundation-collections.md "Immutable copies").
            for column in try FoundationHashTable.inserting(columns).copied().keys {
                _ = names(column)
            }
            columnLists.append(columns)
            // Per constraint: 0, 0, its count of properties, then each property (`omo-uq-several`).
            let constraints = entity.uniquenessConstraints.map { [0, 0, $0.count] + $0.map { names($0) } }
            entityRecords.append((modifier, name, hash, className, uname, properties, indexes, constraints, userInfo))
        }
        for member in inherited {
            entityRecords[member.entity].properties[member.position] = recordIndex[member.record]!
        }
        for index in records.indices {
            // On the destination or its parents (coredata-experiments `inverse-inherited`).
            guard case .relationship(let relationship) = records[index].property, let inverse = relationship.inverseName else { continue }
            var owner = byName[relationship.destination]
            while let current = owner, records[index].inverse == nil {
                records[index].inverse = recordIndex[current.name + "." + inverse]
                owner = current.parentName.flatMap { byName[$0] }
            }
        }

        var out = Output()
        out.bytes += magic
        let headerAt = out.position
        out.zeros(23 * 4)
        out.marks(4)
        var header: [String: Int] = [:]

        header["U"] = out.position
        out.align(4)
        out.u32(strings.items.count)
        for string in strings.items {
            out.align(4)
            let units = Array(string.utf16)
            out.u32(units.count * 2, 0)
            for unit in units { out.bytes += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
        }
        out.marks()

        header["C"] = out.position
        out.align(4)
        out.u32(names.items.count)
        for name in names.items {
            out.align(8)
            let bytes = Array(name.utf8)
            out.zeros(12)
            out.u32(bytes.count)
            out.zeros(8)
            out.bytes += bytes + [0]
        }
        out.marks()

        header["B"] = out.position
        out.align(4)
        out.u32(blobs.items.count)
        for blob in blobs.items {
            out.align(8)
            out.zeros(16)
            out.u32(blob.count, 0)
            out.bytes += blob
        }
        out.marks()

        header["K"] = out.position
        out.align(4)
        out.u32(tables.count)
        for keys in tables {
            out.align(8)
            out.zeros(40)
            let nodes = keys.isEmpty ? [] : LookupTable.nodes(keys)
            out.u32(keys.count, nodes.count + 1)
            out.zeros(8 * (nodes.count + 1))
            for node in nodes {
                out.u32(node.kind, 0)
                out.u16([node.low, node.below, node.high, node.above] + node.table + [Int](repeating: 0, count: (4 - node.table.count % 4) % 4))
            }
            out.u64(keys.map { UInt64(names($0)) })
        }
        out.marks()

        // A property's renaming identifier and an attribute's bounds share one block: whether it
        // has a renaming identifier, its U index, then the minimum and the maximum as aligned
        // 64-bit values (`omo-renaming-cases`, `omo-val-cases`, `omo-val-float`).
        func optionals(_ renaming: Int?, _ minimum: UInt64?, _ maximum: UInt64?) {
            guard renaming != nil || minimum != nil || maximum != nil else { return out.u32(0) }
            out.u32(1, renaming == nil ? 0 : 1, renaming ?? 0)
            out.u64([minimum ?? 0, maximum ?? 0])
        }
        // Spotlight and truth, which a transient property keeps here but not for its entity
        // (`property-flags-*`).
        func storageFlags(_ property: DataModel.Property) -> Int {
            (property.isIndexedBySpotlight ? 0x20 : 0) | (property.isStoredInTruth ? 0x40 : 0)
        }
        header["P"] = out.position
        out.align(4)
        let attributeCount = records.filter(\.property.isAttribute).count
        out.u32(attributeCount, 0, records.count - attributeCount, 0, 0)
        for record in records {
            let start = out.position
            switch record.property {
            case .attribute(let attribute):
                let flags = (attribute.isOptional ? 4 : 0) | (attribute.isTransient ? 2 : 0) | (attribute.allowsExternalBinaryDataStorage ? 0x800 : 0)
                    | (record.minimum != nil ? 0x400 : 0) | (record.maximum != nil ? 0x200 : 0) | storageFlags(record.property)
                    | (attribute.allowsCloudEncryption ? 0x8000 : 0)
                out.u32(0x40, 2, flags, record.modifier, record.hash, record.entity, record.name, record.regularExpression == nil ? 0 : 1)
                if let expression = record.regularExpression {
                    out.u64([0, 0])
                    out.u32(0, 1)
                    out.u64([UInt64(expression.predicate)])
                    out.u32(0, 0, 0, 0, 0, 1)
                    out.u64([1, UInt64(expression.warning)])
                }
                optionals(record.renaming, record.minimum, record.maximum)
                out.u32(record.userInfo, record.index, record.transformer, attribute.type.rawValue, record.valueClass)
                switch record.defaultValue {
                case nil: out.u32(0)
                case let (wide, value)? where wide:
                    out.u32(1)
                    out.u64([value])
                case let (_, value)?: out.u32(1, Int(value))
                }
                out.u32((attribute.allowsExternalBinaryDataStorage ? 4 : 0) | (record.minimum != nil ? 2 : 0) | (record.maximum != nil ? 1 : 0)
                    | (attribute.allowsCloudEncryption ? 0x40 : 0))
            case .relationship(let relationship):
                let flags = (relationship.isOptional ? 4 : 0) | (relationship.isTransient ? 2 : 0) | (relationship.isOrdered ? 0x100 : 0) | storageFlags(record.property)
                out.u32(0x40, 4, flags, record.modifier, record.hash, record.entity, record.name, 0)
                optionals(record.renaming, nil, nil)
                out.u32(record.userInfo, record.index, entityIndex[relationship.destination] ?? 0)
                if let inverse = record.inverse { out.u32(1, inverse) } else { out.u32(0) }
                out.u32(relationship.maxCount, relationship.minCount, relationship.deleteRule.rawValue)
            }
            out.set(out.position - start, at: start)
        }
        out.marks()

        header["E"] = out.position
        out.align(4)
        out.u32(entityRecords.count)
        for (index, (entity, record)) in zip(entities, entityRecords).enumerated() {
            let start = out.position
            let all = members(entity, byName)
            let count = all.count
            out.u32(Int(marker), 0)
            // `NSManagedObject` is interned but recorded as no class (`omo-default-class`).
            let className = (try Self.className(entity, module: module)) == "NSManagedObject" ? 0 : record.className
            out.u32(record.modifier, record.hash, className, record.name)
            // The superentity, the root, the subentities and their table (`omo-inh-*`): a flag
            // word 0x01000000 before each one present, 0 for each one absent.
            if let parent = entity.parentName { out.u32(0x0100_0000, entityIndex[parent]!) } else { out.u32(0) }
            out.u32(entityIndex[root(entity).name]!)
            if let subentities = children[entity.name] {
                out.u32(0x0100_0000, firstTable[entity.name]! + 1, subentities.count)
                out.u64(subentities.map { UInt64(entityIndex[$0.name]!) })
            } else {
                out.u32(0)
            }
            out.u32(firstTable[entity.name]!)
            if entity.parentName == nil {
                out.u64([UInt64](repeating: 0, count: count))
                out.u64(record.properties.map { UInt64($0) })
            } else {
                // A subentity's members, packed: an own property's record, or 1 then, aligned,
                // the inherited property's record and its index here (`omo-inh-<p>-<c>`, `omo-inh-off-*`).
                out.u64([UInt64](repeating: 0, count: count))
                for (position, member) in all.enumerated() {
                    if member.owner == entity.name {
                        out.u32(0, record.properties[position])
                    } else {
                        out.u32(1)
                        out.align(8)
                        out.u32([record.properties[position], position] + [Int](repeating: 0, count: 7))
                    }
                }
            }
            let sizes = (0..<5).map { group in all.filter { $0.group == group }.count }
            let (persistent, transient, toOne, toMany, ordered) = (sizes[0], sizes[1], sizes[2], sizes[3], sizes[4])
            let attributes = persistent + transient, relationships = toOne + toMany + ordered
            let ranges = [(0, count), (0, attributes), (attributes, relationships), (0, persistent), (attributes, relationships),
                          (persistent, transient), (attributes, toOne), (attributes + toOne, toMany), (attributes + toOne + toMany, ordered),
                          (attributes + toOne, toMany + ordered)] + [(Int, Int)](repeating: (count, 0), count: 5) + [(0, persistent), (persistent, 0)]
            out.u64(ranges.flatMap { [UInt64($0.0), UInt64($0.1)] })
            let external = entity.properties.contains { if case .attribute(let attribute) = $0 { attribute.allowsExternalBinaryDataStorage } else { false } }
            let attributesTable = firstTable[entity.name]! + (children[entity.name] == nil ? 1 : 2)
            let storage = all.filter { !$0.property.isTransient }.reduce(0) { $0 | storageFlags($1.property) }
            var tail = [0, count, 0, 0, 0xC | (entity.isAbstract ? 1 : 0) | (external ? 0x100 : 0) | (record.constraints.isEmpty ? 0 : 0x1800) | storage]
            tail += [Int](repeating: 0, count: 18) + [record.uname, 0, 0, 0, record.indexes.count]
            out.u32(tail)
            out.u64(record.indexes.flatMap { $0.map { UInt64($0) } })
            out.u32(0, record.constraints.count)
            out.u64(record.constraints.flatMap { $0.map { UInt64($0) } })
            // The entity and its subentities, all levels, sorted: momc's order changes from run to
            // run (ADR 0232).
            let family = hierarchy(entity).map { entityIndex[$0.name]! }.sorted()
            out.u32([record.userInfo, family.count] + [Int](repeating: 0, count: 5) + [family.count])
            out.u64(family.map { UInt64($0) })
            out.u32(index, attributesTable, attributesTable + 1)
            out.set(out.position - start, at: start + 4)
            out.u32(Int(marker))
        }
        out.marks()

        header["F"] = out.position
        out.align(4)
        out.u32(requests.count)
        // Per template, between markers: 1 and its entity's index (`omo-fr-several`).
        for request in requests {
            out.u32([0xBEEF_CAFE, 76] + [Int](repeating: 0, count: 6) + [1, entityIndex[request.entity] ?? 0] + [Int](repeating: 0, count: 8) + [326, 0xBEEF_CAFE])
        }
        out.marks()

        header["S"] = out.position
        out.align(4)
        let constrained = entities.contains { !$0.uniquenessConstraints.isEmpty }
        out.u32(7 | (constrained ? 8 : 0), entities.count, requests.count)
        if !requests.isEmpty { out.u64(requests.indices.map { UInt64($0) }) }
        out.u32(1, names("PF_DEFAULT_CONFIGURATION_NAME"), 0, 0, 0, 0, 0, entities.count)
        out.u64(entities.indices.map { UInt64($0) })
        out.u32(0, 0, 0, 0, 0, 1, 0, 1)
        out.u64([UInt64](repeating: 0, count: entities.count))
        for columns in columnLists {
            // ADR 0230: sorted, where momc writes the order of an unidentified hash table.
            let sorted = columns.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
            out.u32(0, 0, 0, 0, 0, sorted.count)
            out.u64(sorted.map { UInt64(names($0)) })
        }
        out.u32(0, 0)

        let values = [header["S"]!, header["E"]!, entities.count, header["P"]!, records.count, attributeCount, 0, records.count - attributeCount, 0, 0,
                      header["K"]!, tables.count, header["B"]!, blobs.items.count, header["U"]!, strings.items.count, header["C"]!,
                      names.items.count, header["F"]!, requests.count, requests.count, indexCount, elementCount]
        for (index, value) in values.enumerated() { out.set(value, at: headerAt + 4 * index) }
        return out.bytes
    }

    static func className(_ entity: DataModel.Entity, module: String?) throws -> String {
        let represented = entity.className ?? "NSManagedObject"
        guard represented.hasPrefix(".") else { return represented }
        guard let module else {
            throw NomacError("entity \(entity.name)'s class \(represented) is in the current module, and momc was given no --module")
        }
        return module + represented
    }

    /// An attribute's default value: a u32, or a wide u64 for Integer 64, Double and Date.
    static func defaultValue(_ attribute: DataModel.Attribute, strings: inout Table<String>, names: inout Table<String>, path: String) throws -> (wide: Bool, value: UInt64)? {
        // A date is floored to whole minutes (coredata-experiments `omo-date-defaults`: 1000 is
        // 960, -1000 is -1020, 120.9 is 120).
        if attribute.type == .date, let interval = attribute.defaultDateTimeInterval {
            return (true, (((Double(interval) ?? 0) / 60).rounded(.down) * 60).bitPattern)
        }
        guard let text = attribute.defaultValue else { return nil }
        switch attribute.type {
        case .integer16, .integer32: return (false, UInt64(UInt32(truncatingIfNeeded: integer(text))))
        case .integer64: return (true, UInt64(bitPattern: Int64(integer(text))))
        case .boolean: return (false, text == "YES" || text == "1" ? 1 : 0)
        case .double: return (true, (Double(text) ?? 0).bitPattern)
        case .float: return (false, UInt64((Float(text) ?? 0).bitPattern))
        case .string: return (false, UInt64(strings(text)))
        // A Decimal's text as `NSDecimalNumber` describes it (`decimal-defaults`).
        case .decimal: return (false, UInt64(names(try ArchivedDecimal.defaultValue(text, context: nil, location: path).description)))
        default: return nil
        }
    }

    static func userInfoBlob(_ entries: [(String, String)], _ blobs: inout Table<[UInt8]>) throws -> Int {
        entries.isEmpty ? 0 : blobs(try KeyedArchiver.archive(EntityDescription.userInfo(entries)))
    }

    /// A validation bound as 64 bits: integers and string lengths as integers, Double and Float
    /// bounds read as a Double (`omo-val-cases`, `omo-val-float`: a Float's 0.1 is Double 0.1).
    static func bound(_ text: String, _ attribute: DataModel.Attribute, path: String) throws -> UInt64 {
        switch attribute.type {
        case .integer16, .integer32, .integer64, .string: return UInt64(bitPattern: Int64(integer(text)))
        case .double: if let value = Double(text) { return value.bitPattern }
        case .float: if let value = Double(text) { return value.bitPattern }
        default: break
        }
        throw NomacError("\(path): validation \"\(text)\" of type \(attribute.type) is not observed yet (BACKLOG B-257)", path: path)
    }

    static func integer(_ text: String) -> Int {
        var digits = ""
        for (index, character) in text.trimmingCharacters(in: .whitespaces).enumerated() {
            if character.isASCII && character.isNumber || (index == 0 && (character == "+" || character == "-")) {
                digits.append(character)
            } else {
                break
            }
        }
        return Int(digits) ?? 0
    }
}

/// The nodes of an `.omo` lookup table, which find a key's slot from its length, then from the
/// byte at one position (docs/formats/coredata.md "`.omo`" "K").
enum LookupTable {
    struct Node {
        var kind: Int, low: Int, below: Int, high: Int, above: Int
        var table: [Int]
    }

    static func nodes(_ keys: [String]) -> [Node] {
        let slot = Dictionary(keys.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var nodes: [Node] = []
        var queue: [[String]] = []
        var created = 0
        func reference(_ group: [String]) -> Int {
            if group.count == 1 { return slot[group[0]]! }
            created += 1
            queue.append(group)
            return (-created) & 0xFFFF
        }
        func make(_ kind: Int, _ groups: [Int: [String]]) -> Node {
            let values = groups.keys.sorted()
            let low = values.first! + 1, high = values.last! - 1
            let below = reference(groups[values.first!]!)
            let above = values.last == values.first ? below : reference(groups[values.last!]!)
            let table = low <= high ? (low...high).map { groups[$0].map(reference) ?? 0 } : []
            return Node(kind: kind, low: low, below: below, high: high, above: above, table: table)
        }
        func grouped(_ group: [String], by value: (String) -> Int) -> [Int: [String]] {
            var result: [Int: [String]] = [:]
            for key in group { result[value(key), default: []].append(key) }
            return result
        }
        nodes.append(make(1, grouped(keys) { $0.unicodeScalars.count }))
        while !queue.isEmpty {
            let group = queue.removeFirst()
            let scalars = group.map { Array($0.unicodeScalars) }
            // The first position with the most distinct characters (docs/formats/coredata.md "`.omo`" "K";
            // coredata-experiments `omo-date-defaults`: `d00` to `d12` dispatch on their last digit).
            let distinct = (0..<scalars[0].count).map { index in Set(scalars.map { $0[index] }).count }
            let position = distinct.firstIndex(of: distinct.max() ?? 0) ?? 0
            nodes.append(make((position << 13) | 9, grouped(group) { Int(Array($0.utf8)[position]) }))
        }
        return nodes
    }
}
