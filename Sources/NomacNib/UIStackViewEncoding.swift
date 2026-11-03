import Foundation

/// What a `UIStackView` writes after a view's keys (docs/formats/nib.md "UIStackView";
/// nib-experiments `stack-*`): its subviews again, all arranged, then its axis, distribution,
/// alignment, spacing and arrangement flags, always.
struct StackContent {
    var arrangedSubviews: [NibView]
    var axis: Int
    var distribution: Int
    var alignment: Int
    var spacing: Double
    var baselineRelative: Bool
    var layoutMarginsRelative: Bool

    func encode(to encoder: NibEncoder) throws {
        if !arrangedSubviews.isEmpty {
            try encoder.encode(NibArray(arrangedSubviews), forKey: "UIStackViewArrangedSubviews")
        }
        encoder.encode(.integer(axis), forKey: "UIStackViewAxis")
        encoder.encode(.integer(distribution), forKey: "UIStackViewDistribution")
        encoder.encode(.integer(alignment), forKey: "UIStackViewAlignment")
        encoder.encode(.double(spacing), forKey: "UIStackViewSpacing")
        encoder.encode(.boolean(baselineRelative), forKey: "UIStackViewBaselineRelative")
        encoder.encode(.boolean(layoutMarginsRelative), forKey: "UIStackViewLayoutMarginsRelative")
    }

    static let attributes = ["axis", "distribution", "alignment", "spacing", "spacingType", "baselineRelativeArrangement"]
    /// `UIStackView.Distribution` and `Alignment` by the names documents use; IB's `centerX` and
    /// `centerY` are fill, and `spacingType="standard"` writes nothing (`stack-alignment-centerY`,
    /// `stack-vertical-alignment-centerX`, `stack-spacing-type-standard`).
    static let distributions = ["fill": 0, "fillEqually": 1, "fillProportionally": 2, "equalSpacing": 3, "equalCentering": 4]
    /// The attributes a size-class variation varies, in the order ibtool writes their storages
    /// (`stack-vary-*`).
    static let variedAttributes: [(attribute: String, keyPath: String)] = [("axis", "axis"), ("distribution", "distribution"), ("spacing", "spacing")]
    static let alignments = ["fill": 0, "leading": 1, "top": 1, "firstBaseline": 2, "center": 3, "trailing": 4, "bottom": 4,
                             "lastBaseline": 5, "centerX": 0, "centerY": 0]
}

extension DocumentCompiler {
    /// A `<stackView>`'s content, its subviews already compiled; a stack view of arranged subviews
    /// and those of them that do not translate their masks write so, as if a constraint named
    /// them, their masks IB's default whatever the document gives (`stack`, `stack-views`,
    /// `stack-empty`, `stack-arranged-*mask`). Margins make the arrangement relative to them
    /// (`stack-edge-margins*`, `stack-directional-margins`).
    mutating func stackContent(_ element: XIBElement, id: String, subviews: [NibView]) throws -> StackContent {
        let attributes = element.attributes
        try value(element, "axis", in: ["horizontal", "vertical"])
        try value(element, "spacingType", in: ["standard"])
        let content = StackContent(arrangedSubviews: subviews, axis: attributes["axis"] == "vertical" ? 1 : 0,
                                   distribution: try mapped(attributes["distribution"] ?? "fill", StackContent.distributions, "distribution"),
                                   alignment: try mapped(attributes["alignment"] ?? "fill", StackContent.alignments, "alignment"),
                                   spacing: try number(attributes["spacing"] ?? "0", "spacing"),
                                   baselineRelative: try bool(element, "baselineRelativeArrangement", default: false),
                                   layoutMarginsRelative: element.child("edgeInsets", key: "layoutMargins") != nil
                                       || element.child("directionalEdgeInsets", key: "directionalLayoutMargins") != nil)
        if !subviews.isEmpty {
            for child in element.children(named: "subviews").flatMap(\.children) {
                guard let arranged = documentViews[child.attributes["id"] ?? ""], !arranged.translates else { continue }
                arranged.view.flags.doesNotTranslateAutoresizingMask = true
                arranged.view.autoresizingMask = NibView.defaultAutoresizingMask
            }
            try constrained(id)
        }
        return content
    }

    /// A view's `<edgeInsets key="layoutMargins">` or `<directionalEdgeInsets
    /// key="directionalLayoutMargins">`, top, left or leading, bottom, right or trailing, written
    /// even when zero; a stack view without either writes zeros (`view-margins-*`, `stack`).
    func layoutMargins(_ element: XIBElement) throws -> (margins: [Double], directional: Bool)? {
        if let edges = element.child("edgeInsets", key: "layoutMargins") {
            try check(edges, attributes: ["key", "top", "left", "bottom", "right"], children: [])
            return (try ["top", "left", "bottom", "right"].map { try number(edges.attributes[$0] ?? "0", $0) }, false)
        }
        if let edges = element.child("directionalEdgeInsets", key: "directionalLayoutMargins") {
            try check(edges, attributes: ["key", "top", "leading", "bottom", "trailing"], children: [])
            return (try ["top", "leading", "bottom", "trailing"].map { try number(edges.attributes[$0] ?? "0", $0) }, true)
        }
        return element.name == "stackView" ? ([0, 0, 0, 0], false) : nil
    }
}

extension DocumentCompiler {
    /// A stack view's size-class variations of its axis, distribution and spacing: a trait storage
    /// each, in that order, of `NSNumber`s (integers, the spacing a double unless absent from the
    /// stack view, then the integer 0), the stack view itself taking the device's values
    /// (`stack-vary-*`; wikipedia's WelcomeContainerViewController, InsertMediaImageInfoView).
    mutating func stackVariations(_ element: XIBElement, view: NibView, content: inout StackContent) throws {
        let variations = element.children(named: "variation").filter { variation in
            StackContent.variedAttributes.contains { variation.attributes[$0.attribute] != nil }
        }
        guard !variations.isEmpty else { return }
        for variation in variations where variation.attributes["key"] == "default" {
            throw unsupported("a stack view's default variation of \(StackContent.variedAttributes.filter { variation.attributes[$0.attribute] != nil }.map(\.attribute))")
        }
        for (attribute, keyPath) in StackContent.variedAttributes {
            let varied = try variations.compactMap { variation -> (SizeClasses, Double)? in
                guard let value = variation.attributes[attribute] else { return nil }
                switch attribute {
                case "axis": return (try sizeClasses(variation), Double(try mapped(value, ["horizontal": 0, "vertical": 1], "axis")))
                case "distribution": return (try sizeClasses(variation), Double(try mapped(value, StackContent.distributions, "distribution")))
                default: return (try sizeClasses(variation), try number(value, "spacing"))
                }
            }
            guard !varied.isEmpty else { continue }
            let integer = attribute != "spacing"
            let number = { (value: Double) -> NibNumber in integer ? NibNumber(integer: Int(value)) : NibNumber(value) }
            let defaultValue: Double
            switch attribute {
            case "axis": defaultValue = Double(content.axis)
            case "distribution": defaultValue = Double(content.distribution)
            default: defaultValue = content.spacing
            }
            let defaultNumber = attribute == "spacing" && element.attributes["spacing"] == nil ? NibNumber(integer: 0) : number(defaultValue)
            traitStorages.append(TraitStorage(object: view, keyPath: string(keyPath), variations: varied.map { ($0.0, .object(number($0.1))) },
                                              defaultValue: .object(defaultNumber)))
            let value = TraitStorage.value(varied, default: defaultValue, device: deviceSizeClasses)
            switch attribute {
            case "axis": content.axis = Int(value)
            case "distribution": content.distribution = Int(value)
            default: content.spacing = value
            }
        }
    }
}
