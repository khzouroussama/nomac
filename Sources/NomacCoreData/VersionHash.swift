import NomacCore

/// Core Data's version hashes (`NSPropertyDescription.versionHash`, `NSEntityDescription.versionHash`,
/// `NSManagedObjectModel.versionChecksum`), as docs/formats/coredata.md "Version hashes" states
/// them: observed through the public API on coredata-experiments `version-hashes` and checked on
/// every entity of the corpus's compiled models.
public enum VersionHash {
    /// The hashes of a model's entities, by name.
    public static func entities(of model: DataModel) throws -> [String: [UInt8]] {
        let byName = Dictionary(model.entities.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var hashes: [String: [UInt8]] = [:]
        func hash(_ entity: DataModel.Entity, visiting: Set<String>) throws -> [UInt8] {
            if let known = hashes[entity.name] { return known }
            var parentHash: [UInt8] = []
            var properties = entity.properties
            if let parentName = entity.parentName {
                guard let parent = byName[parentName], !visiting.contains(parentName) else {
                    throw NomacError("entity \(entity.name)'s parent \(parentName) is not in the model")
                }
                parentHash = try hash(parent, visiting: visiting.union([entity.name]))
                properties += inherited(parent, byName)
            }
            let persistent = properties.filter { !$0.isTransient }.sorted { Array($0.name.utf8).lexicographicallyPrecedes(Array($1.name.utf8)) }
            var preimage = cString(entity.name) + [entity.isAbstract ? 1 : 0] + parentHash
            for property in persistent {
                preimage += VersionHash.property(property)
            }
            preimage += cString(entity.versionHashModifier)
            preimage += entity.uniquenessConstraints.map { Array($0.joined(separator: ".").utf8) }
                .sorted { $0.lexicographicallyPrecedes($1) }.joined()
            let digest = SHA256.digest(preimage)
            hashes[entity.name] = digest
            return digest
        }
        for entity in model.entities {
            _ = try hash(entity, visiting: [])
        }
        return hashes
    }

    /// `versionChecksum`: SHA-256 of the entities' hashes in name order.
    public static func checksum(_ entityHashes: [String: [UInt8]]) -> [UInt8] {
        SHA256.digest(entityHashes.sorted { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }.flatMap(\.value))
    }

    static func property(_ property: DataModel.Property) -> [UInt8] {
        switch property {
        case .attribute(let attribute):
            var tail = littleEndian(UInt32(attribute.type.rawValue))
            if attribute.allowsExternalBinaryDataStorage { tail.append(1) }
            return SHA256.digest(own(attribute.name, attribute.isOptional, attribute.isTransient) + tail)
        case .relationship(let relationship):
            let tail = cString(relationship.destination) + cString(relationship.inverseName)
                + littleEndian(UInt32(relationship.maxCount)) + littleEndian(UInt32(relationship.minCount))
                + (relationship.isOrdered ? [1, 0] : [])
            return SHA256.digest(own(relationship.name, relationship.isOptional, relationship.isTransient) + tail)
        }
    }

    private static func inherited(_ entity: DataModel.Entity, _ byName: [String: DataModel.Entity]) -> [DataModel.Property] {
        entity.properties + (entity.parentName.flatMap { byName[$0] }.map { inherited($0, byName) } ?? [])
    }

    /// A property's versionHashModifier would follow the flags; nomac does not read it from models
    /// yet (docs/formats/coredata.md).
    private static func own(_ name: String, _ isOptional: Bool, _ isTransient: Bool) -> [UInt8] {
        SHA256.digest(cString(name) + [(isOptional ? 1 : 0) | (isTransient ? 2 : 0), 0])
    }

    /// The UTF-8 bytes up to the first NUL, with no terminator (`version-hashes` `name-nul`).
    private static func cString(_ string: String?) -> [UInt8] {
        Array((string ?? "").utf8.prefix { $0 != 0 })
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }
}
