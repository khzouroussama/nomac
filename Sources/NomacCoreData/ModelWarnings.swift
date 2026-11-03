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
            for property in entity.properties {
                let qualified = "\(entity.name).\(property.name)"
                let prefix = "\(location):\(qualified): warning: "
                switch property {
                case .attribute(let attribute):
                    if transformers, attribute.type == .transformable, attribute.valueTransformerName == nil {
                        warnings.append(prefix + "\(qualified) is using a nil or insecure value transformer. Please switch to NSSecureUnarchiveFromDataTransformerName or a custom NSValueTransformer subclass of NSSecureUnarchiveFromDataTransformer [2]")
                    }
                case .relationship(let relationship):
                    // The delete rule's warning comes first (`no-inverse`).
                    if relationship.deleteRule == .noAction {
                        warnings.append(prefix + "Setting the No Action Delete Rule on \(qualified) may result in relationships to deleted objects [7]")
                    }
                    if relationship.inverseName == nil {
                        warnings.append(prefix + (relationship.isToMany
                            ? "\(qualified) does not have an inverse; this is an advanced setting (no object can be in multiple destinations for a specific relationship) [7]"
                            : "\(qualified) should have an inverse [2]"))
                    }
                }
            }
        }
        return warnings
    }

    /// Warnings of several versions: each message once, from the last version that has it, in the
    /// order of those last versions (mastodon's ten versions).
    static func merged(_ warnings: [String]) -> [String] {
        var seen: Set<Substring> = []
        var kept: [String] = []
        for warning in warnings.reversed() {
            let message = warning[warning.range(of: ": warning: ")!.upperBound...]
            if seen.insert(message).inserted {
                kept.append(warning)
            }
        }
        return kept.reversed()
    }
}
