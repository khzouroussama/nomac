import Foundation

/// `UIRuntimeAccessibilityConfiguration`: an object's `<accessibility
/// key="accessibilityConfiguration">` (docs/formats/nib.md "Accessibility"; nib-experiments
/// `a11y-*`): its hint, identifier, label, traits and whether it is an element, each when given.
final class NibAccessibilityConfiguration: NibArchivable {
    let object: NibArchivable
    var hint: NibArchivable?
    var identifier: NibString?
    var label: NibArchivable?
    var traits: NibNumber?
    var isElement: NibNumber?

    init(object: NibArchivable) {
        self.object = object
    }

    var className: String { "UIRuntimeAccessibilityConfiguration" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(object, forKey: "UIAccessibileObject")
        if let hint { try encoder.encode(hint, forKey: "UIAccessibilityHint") }
        if let identifier { try encoder.encode(identifier, forKey: "UIAccessibilityIdentifier") }
        if let label { try encoder.encode(label, forKey: "UIAccessibilityLabel") }
        if let traits { try encoder.encode(traits, forKey: "UIAccessibilityTraits") }
        if let isElement { try encoder.encode(isElement, forKey: "UIIsAccessibilityElement") }
    }

    /// `UIAccessibilityTraits` bits by the names documents use (`a11y-traits-*`).
    static let traits = ["none": 0, "button": 1, "link": 2, "image": 4, "selected": 8, "staticText": 64, "summaryElement": 128,
                         "notEnabled": 256, "adjustable": 4096, "header": 65536]
}

extension DocumentCompiler {
    /// An object's accessibility configuration; in an `.lproj` folder its label and hint are
    /// localizable, keyed `<id>.accessibilityLabel` and `<id>.accessibilityHint` (`a11y-lproj`).
    mutating func accessibility(of element: XIBElement, object: NibArchivable) throws {
        for accessibility in element.children(named: "accessibility") {
            try check(accessibility, attributes: ["key", "label", "hint", "identifier"], children: ["bool", "accessibilityTraits"])
            try value(accessibility, "key", in: ["accessibilityConfiguration"])
            let configuration = NibAccessibilityConfiguration(object: object)
            let id = element.attributes["id"] ?? ""
            configuration.hint = accessibility.attributes["hint"].map { localizableText($0, key: "\(id).accessibilityHint") }
            configuration.identifier = accessibility.attributes["identifier"].map { string($0) }
            configuration.label = accessibility.attributes["label"].map { localizableText($0, key: "\(id).accessibilityLabel") }
            for child in accessibility.children {
                switch (child.name, child.attributes["key"]) {
                case ("bool", "isElement"):
                    try check(child, attributes: ["key", "value"], children: [])
                    configuration.isElement = NibNumber(integer: try bool(child, "value", default: false) ? 1 : 0)
                case ("accessibilityTraits", "traits"):
                    var bits = 0
                    for name in child.attributes.keys where name != "key" {
                        guard let bit = NibAccessibilityConfiguration.traits[name] else { throw unsupported("the accessibility trait \(name)") }
                        if try bool(child, name, default: false) { bits |= bit }
                    }
                    configuration.traits = NibNumber(integer: bits)
                default:
                    throw unsupported("<\(child.name)> in <accessibility>")
                }
            }
            accessibilityConfigurations.append(configuration)
        }
    }

    /// A text, localizable in a document of `Base.lproj` unless empty (`label-empty-lproj`,
    /// `button-empty-title-lproj`).
    mutating func localizableText(_ text: String, key: String) -> NibArchivable {
        localizable && !text.isEmpty ? NibLocalizableString(value: text, key: string(key), development: string(text)) : string(text)
    }

    /// The nib's accessibility configurations, emptied for the next nib, by the walk connections of one
    /// name go by, those of one object in the document's order (`a11y-walk-*`, `sb-a11y-walk-*`; the
    /// corpus's pocket-casts MiniPlayerViewController, 67 nibs of the corpus, holdout and survey).
    mutating func takeAccessibilityConfigurations(allObjects: [NibArchivable]) -> [NibAccessibilityConfiguration] {
        defer { accessibilityConfigurations = [] }
        let order = connectionWalk(allObjects)
        return accessibilityConfigurations.enumerated().sorted { left, right in
            let (a, b) = (order[ObjectIdentifier(left.element.object)] ?? Int.max, order[ObjectIdentifier(right.element.object)] ?? Int.max)
            return a == b ? left.offset < right.offset : a < b
        }.map(\.element)
    }
}

/// The root's accessibility configurations, an `NSArray` in `takeAccessibilityConfigurations`'s order.
final class NibAccessibilityConfigurations: NibArchivable {
    let configurations: [NibAccessibilityConfiguration]

    init(_ configurations: [NibAccessibilityConfiguration]) {
        self.configurations = configurations
    }

    var className: String { "NSArray" }

    func encode(to encoder: NibEncoder) throws {
        try NibArray(configurations).encode(to: encoder)
    }
}
