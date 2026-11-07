/// The warnings momc prints on standard error after its notes (coredata-experiments `abstract`,
/// `no-inverse`, `ordered`, `type-transformable`, and mastodon's models).
enum ModelWarnings {
    /// The warnings of one model version, `location` being its `.xcdatamodel` path: entities in
    /// the file's order, their properties as `DataModel.sortingProperties()` orders them
    /// (coredata-experiments `sort-order`).
    /// `transformers`: whether insecure value transformers warn, which momc says only of the current
    /// version when there is one (coredata-experiments `warn-transformer-*`; wikipedia's Wikipedia).
    static func of(_ model: DataModel, location: String, transformers: Bool = true) -> [String] {
        var warnings: [String] = []
        for entity in model.entities {
            if entity.isAbstract, !model.entities.contains(where: { $0.parentName == entity.name }) {
                warnings.append("\(location):\(entity.name): warning: abstract entity \(entity.name) has no children [1]")
            }
            if entity.isAbstract, model.isUsedWithSwiftData {
                warnings.append("\(location):\(entity.name): warning: Abstract entities are not supported in SwiftData. [10]")
            }
            for property in entity.properties {
                let qualified = "\(entity.name).\(property.name)"
                let prefix = "\(location):\(qualified): warning: "
                if property.isStoredInTruth {
                    warnings.append(prefix + "\(qualified) is set to be stored using a Spotlight external record file, which is deprecated. Use Core Spotlight integration instead. [5]")
                }
                switch property {
                case .attribute(let attribute):
                    if transformers, attribute.type == .transformable, attribute.valueTransformerName == nil {
                        warnings.append(prefix + "\(qualified) is using a nil or insecure value transformer. Please switch to NSSecureUnarchiveFromDataTransformerName or a custom NSValueTransformer subclass of NSSecureUnarchiveFromDataTransformer [2]")
                    }
                case .fetched:
                    continue
                case .relationship(let relationship):
                    // The delete rule's warning comes first (`no-inverse`).
                    if relationship.deleteRule == .noAction {
                        warnings.append(prefix + "Setting the No Action Delete Rule on \(qualified) may result in relationships to deleted objects [7]")
                    }
                    let inverse = inverse(of: relationship, in: model)
                    if let inverse, inverse.inverseName != relationship.name {
                        warnings.append(prefix + "The inverse relationship for \(qualified) does not reciprocate an inverse relationship [2]")
                    } else if inverse == nil {
                        warnings.append(prefix + (relationship.isToMany
                            ? "\(qualified) does not have an inverse; this is an advanced setting (no object can be in multiple destinations for a specific relationship) [7]"
                            : "\(qualified) should have an inverse [2]"))
                    }
                    if model.isUsedWithSwiftData, relationship.isOrdered {
                        warnings.append(prefix + "Ordered relationships are unsupported in SwiftData. [10]")
                    }
                }
            }
        }
        return warnings
    }

    /// The relationship `inverseName` names on the destination or its parents.
    private static func inverse(of relationship: DataModel.Relationship, in model: DataModel) -> DataModel.Relationship? {
        guard let name = relationship.inverseName else { return nil }
        var entity = model.entities.first { $0.name == relationship.destination }
        while let current = entity {
            if let property = current.properties.first(where: { $0.name == name }) {
                if case .relationship(let inverse) = property { return inverse }
                return nil
            }
            entity = current.parentName.flatMap { parent in model.entities.first { $0.name == parent } }
        }
        return nil
    }
}
