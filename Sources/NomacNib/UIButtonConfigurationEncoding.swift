import Foundation

/// `UIButton.Configuration` of a `<buttonConfiguration>` (docs/formats/nib.md "Button
/// configurations"; nib-experiments `bc-*`): its style and the background that goes with it, its
/// colors, image, title and padding, everything else UIKit's defaults.
final class NibButtonConfiguration: NibArchivable {
    /// `UIButton.Configuration`'s styles by the names documents use, each with its background color:
    /// clear, then the system gray fill, the system blue at 0.18 and the system blue, as unnamed
    /// colors (`bc-plain-title`, `bc-gray-title`, `bc-tinted-title`, `bc-filled-title`).
    static let styles: [String: (style: Int, background: NibColor.Components?)] = [
        "plain": (0, nil),
        "gray": (1, .rgb(red: 120.0 / 255, green: 120.0 / 255, blue: 128.0 / 255, alpha: 0.16)),
        "tinted": (2, .rgb(red: 0, green: 136.0 / 255, blue: 1, alpha: 0.18)),
        "filled": (3, .rgb(red: 0, green: 136.0 / 255, blue: 1, alpha: 1)),
    ]
    /// `NSDirectionalRectEdge` of the image placements observed (`bc-image-leading`, `bc-image-trailing`).
    static let imagePlacements = ["leading": 2, "trailing": 8]

    let style: Int
    let background: NibBackgroundConfiguration
    var baseForegroundColor: NibColor?
    var image: NibImage?
    var preferredSymbolConfiguration: NibSymbolConfiguration?
    var title: NibConfigurationTitle
    let subtitle: NibConfigurationTitle
    var imagePlacement = 2
    var imagePadding: Float = 0

    init(style: Int, background: NibBackgroundConfiguration, title: NibConfigurationTitle, subtitle: NibConfigurationTitle) {
        self.style = style
        self.background = background
        self.title = title
        self.subtitle = subtitle
    }

    var className: String { "UIButtonConfiguration" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.integer(style), forKey: "UIButtonConfigurationButtonStyle")
        try encoder.encode(background, forKey: "UIButtonConfigurationBackground")
        encoder.encode(.integer(0), forKey: "UIButtonConfigurationCornerStyle")
        encoder.encode(.integer(0), forKey: "UIButtonConfigurationButtonSize")
        encoder.encode(.integer(0), forKey: "UIButtonConfigurationMacIdiomStyle")
        encoder.encode(.null, forKey: "UIButtonConfigurationBaseBackgroundColor")
        try encoder.encode(baseForegroundColor, forKey: "UIButtonConfigurationBaseForegroundColor")
        try encoder.encode(image, forKey: "UIButtonConfigurationImage")
        try encoder.encode(preferredSymbolConfiguration, forKey: "UIButtonConfigurationPreferredSymbolConfigurationForImage")
        encoder.encode(.null, forKey: "UIButtonConfigurationSymbolContentTransition")
        encoder.encode(.boolean(false), forKey: "UIButtonConfigurationShowsActivityIndicator")
        try encoder.encode(title, forKey: "UIButtonConfigurationTitle")
        try encoder.encode(subtitle, forKey: "UIButtonConfigurationSubtitle")
        encoder.encode(.integer(imagePlacement), forKey: "UIButtonConfigurationImagePlacement")
        encoder.encode(.float(imagePadding), forKey: "UIButtonConfigurationImagePadding")
        encoder.encode(.float(1), forKey: "UIButtonConfigurationTitlePadding")
        encoder.encode(.integer(0), forKey: "UIButtonConfigurationTitleAlignment")
    }
}

/// `UIImageSymbolConfiguration`: a scale, a weight, a point size (`configurationType="pointSize"`), a
/// text style (`configurationType="font"`) and hierarchical colors, each when given
/// (`bc-symbol-scale*`, `bc-symbol-point-size`, `symbol-view-*`, `symbol-button-*`).
final class NibSymbolConfiguration: NibArchivable {
    /// `UIImage.SymbolScale` by the names documents use.
    static let scales = ["default": -1, "small": 1, "medium": 2, "large": 3]
    /// `UIImage.SymbolWeight` of the weights observed (`symbol-view-weight-*`, `symbol-view-scale-weight`).
    static let weights = ["ultraLight": 1, "thin": 2, "light": 3, "regular": 4, "medium": 5, "semibold": 6, "bold": 7, "heavy": 8, "black": 9]
    /// The text styles observed, with the weight they write (`symbol-view-font`, `symbol-font-style-*`).
    static let textStyleWeights = ["UICTFontTextStyleBody": 4, "UICTFontTextStyleCallout": 4, "UICTFontTextStyleCaption1": 4, "UICTFontTextStyleCaption2": 4,
                                   "UICTFontTextStyleFootnote": 4, "UICTFontTextStyleHeadline": 6, "UICTFontTextStyleSubhead": 4, "UICTFontTextStyleTitle0": 4,
                                   "UICTFontTextStyleTitle1": 4, "UICTFontTextStyleTitle2": 4, "UICTFontTextStyleTitle3": 4]

    var scale: Int?
    var weight: Int?
    var pointSize: Float?
    var textStyle: NibString?
    var hierarchicalColors: [NibColor]?

    init(scale: Int? = nil, pointSize: Float? = nil) {
        self.scale = scale
        self.pointSize = pointSize
    }

    var className: String { "UIImageSymbolConfiguration" }

    func encode(to encoder: NibEncoder) throws {
        if let scale { encoder.encode(.integer(scale), forKey: "UISymbolScale") }
        if let pointSize { encoder.encode(.float(pointSize), forKey: "UIPointSize") }
        if let weight { encoder.encode(.integer(weight), forKey: "UISymbolWeight") }
        if let textStyle { try encoder.encode(textStyle, forKey: "UITextStyle") }
        if let hierarchicalColors {
            try encoder.encode(NibArray(hierarchicalColors), forKey: "UIHierarchicalColors")
            encoder.encode(.boolean(false), forKey: "UIDerivativeHierarchicalColors")
            encoder.encode(.boolean(true), forKey: "UISpecifiedPrefersMulticolor")
            encoder.encode(.boolean(false), forKey: "UIPrefersMulticolor")
            encoder.encode(.boolean(true), forKey: "UISpecifiedPrefersMonochrome")
            encoder.encode(.boolean(false), forKey: "UIPrefersMonochrome")
        }
    }
}

/// A configuration's title or subtitle: an `NSAttributedString` of the title with its font as
/// attributes; an empty one has none (`bc-plain`, `bc-title-font`).
final class NibConfigurationTitle: NibArchivable {
    let string: NibArchivable
    let attributes: NibDictionary?

    init(string: NibArchivable, attributes: NibDictionary?) {
        self.string = string
        self.attributes = attributes
    }

    var className: String { "NSAttributedString" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(string, forKey: "NSString")
        if let attributes { try encoder.encode(attributes, forKey: "NSAttributes") }
    }
}

extension DocumentCompiler {
    /// A button's `<buttonConfiguration>`: its style, title and subtitle, title font,
    /// image, by name or as an `<imageReference>` of a system symbol with a scale, the preferred
    /// symbol configuration, placement, padding and base foreground color.
    mutating func buttonConfiguration(_ element: XIBElement, id: String?) throws -> NibButtonConfiguration {
        try check(element, attributes: ["key", "style", "title", "subtitle", "image", "catalog", "imagePlacement", "imagePadding"], children: ["fontDescription", "color", "imageReference", "preferredSymbolConfiguration"])
        try value(element, "key", in: ["configuration"])
        guard let style = NibButtonConfiguration.styles[element.attributes["style"] ?? ""] else {
            throw unsupported("the button configuration style \(element.attributes["style"] ?? "none")")
        }
        let clear = try color(XIBElement(name: "color", attributes: ["cocoaTouchSystemColor": "clearColor"]))
        // Each configuration's own object (`bc-filled-two`, `bc-tinted-two`, `bc-gray-two`; the survey's KeePassium FirstSetupVC).
        let background = NibBackgroundConfiguration(backgroundColor: style.background.map { NibColor(components: $0, name: nil) } ?? clear, strokeColor: clear,
                                                    insets: string("{0, 0, 0, 0}"), button: true)
        let text = element.attributes["title"] ?? ""
        let subtitle = element.attributes["subtitle"] ?? ""
        let fonts = element.children(named: "fontDescription")
        for font in fonts { try value(font, "key", in: ["titleFontDescription"]) }
        guard fonts.isEmpty || (!text.isEmpty && subtitle.isEmpty) else { throw unsupported("a title font in a button configuration without one title") }
        var attributes: NibDictionary?
        if !text.isEmpty || !subtitle.isEmpty {
            let font = try fonts.isEmpty ? nil : self.font(element).font
            let identity = font.map { "\(ObjectIdentifier($0))" } ?? ""
            attributes = titleAttributes[identity] ?? dictionary(font.map { [("NSFont", $0 as NibArchivable)] } ?? [])
            titleAttributes[identity] = attributes
        }
        // Localizable as `<id>.configuration.title` and `.subtitle` in `Base.lproj`; an empty one has no attributes (`bc-lproj-*`).
        func title(_ value: String, _ property: String) -> NibConfigurationTitle {
            value.isEmpty ? NibConfigurationTitle(string: string(""), attributes: nil)
                : NibConfigurationTitle(string: self.text(value, id: id, property: "configuration.\(property)"), attributes: attributes)
        }
        let configuration = NibButtonConfiguration(style: style.style, background: background, title: title(text, "title"), subtitle: title(subtitle, "subtitle"))
        for color in element.children(named: "color") {
            try value(color, "key", in: ["baseForegroundColor"])
            configuration.baseForegroundColor = try self.color(color)
        }
        configuration.image = try element.attributes["image"].map { try image($0, catalog: element.attributes["catalog"]) }
        configuration.image = try symbolImage(element) ?? configuration.image
        configuration.preferredSymbolConfiguration = try preferredSymbolConfiguration(element, key: "preferredSymbolConfigurationForImage")
        configuration.imagePlacement = try mapped(element.attributes["imagePlacement"] ?? "leading", NibButtonConfiguration.imagePlacements, "imagePlacement")
        configuration.imagePadding = Float(try number(element.attributes["imagePadding"] ?? "0", "imagePadding"))
        return configuration
    }

    /// An element's `<imageReference key="image">` of a system symbol: an image placeholder of its
    /// own with its variable value and, for a scale or hierarchical colors, its symbol configuration
    /// (`bc-symbol-scale*`, `image-view-symbol-reference*`, `symbol-view-*`, `symbol-button-*`); one
    /// beside an `image` attribute is refused.
    mutating func symbolImage(_ element: XIBElement) throws -> NibImage? {
        let references = element.children(named: "imageReference")
        guard let reference = references.first else { return nil }
        try check(reference, attributes: ["key", "image", "catalog", "symbolScale", "renderingMode", "variableValue"], children: ["hierarchicalColors"])
        try value(reference, "key", in: ["image"])
        try value(reference, "catalog", in: ["system"])
        try value(reference, "renderingMode", in: ["hierarchical", "template", "original"])
        guard references.count == 1, element.attributes["image"] == nil, let name = reference.attributes["image"] else {
            throw unsupported("an image reference without a system symbol's name, or beside an image")
        }
        var configuration: NibSymbolConfiguration?
        if let scale = reference.attributes["symbolScale"] {
            configuration = NibSymbolConfiguration(scale: try mapped(scale, NibSymbolConfiguration.scales, "symbolScale"))
        }
        let palettes = reference.children(named: "hierarchicalColors")
        guard (reference.attributes["renderingMode"] == "hierarchical") == (palettes.count == 1) else {
            throw unsupported("hierarchical rendering without one set of hierarchical colors")
        }
        for palette in palettes {
            try check(palette, attributes: [], children: ["color"])
            configuration = configuration ?? NibSymbolConfiguration()
            configuration?.hierarchicalColors = try palette.children.map { try color($0) }
        }
        // Without a catalog it names an image of the app, as a plain image does, without its scale (`image-reference-asset*`, `symbol-rendering-named-*`).
        let symbol = reference.attributes["catalog"] != nil
        let image = NibImage(name: string(name), symbol: symbol, configuration: symbol ? configuration : nil)
        image.variableValue = try reference.attributes["variableValue"].map { try number($0, "variableValue") }
        // A system symbol's `template` and `original`; an image of the app writes neither (`symbol-rendering-*`).
        if image.symbol { image.renderingMode = ["original": 1, "template": 2][reference.attributes["renderingMode"] ?? ""] }
        return image
    }

    /// An element's `<preferredSymbolConfiguration>` of the given key: a scale, a weight, and for
    /// `configurationType="pointSize"` a point size, for `configurationType="font"` a text style;
    /// an empty one is none (`bc-symbol-point-size`, `image-view-symbol-preferred-*`, `symbol-view-*`).
    mutating func preferredSymbolConfiguration(_ element: XIBElement, key: String) throws -> NibSymbolConfiguration? {
        let configurations = element.children(named: "preferredSymbolConfiguration")
        guard let preferred = configurations.first else { return nil }
        try check(preferred, attributes: ["key", "scale", "weight", "configurationType", "pointSize"], children: ["fontDescription"])
        try value(preferred, "key", in: [key])
        let attributes = preferred.attributes
        guard configurations.count == 1 else { throw unsupported("two preferred symbol configurations") }
        let configuration = NibSymbolConfiguration(scale: try attributes["scale"].map { try mapped($0, NibSymbolConfiguration.scales, "scale") })
        configuration.weight = try attributes["weight"].map { try mapped($0, NibSymbolConfiguration.weights, "weight") }
        switch attributes["configurationType"] {
        case nil:
            // A font without its type changes nothing (`symbol-font-no-type*`).
            guard attributes["pointSize"] == nil else { throw unsupported("a preferred symbol configuration's size without its type") }
        case "pointSize":
            guard let size = attributes["pointSize"], preferred.children.isEmpty else { throw unsupported("a point size configuration without a point size") }
            configuration.pointSize = Float(try number(size, "pointSize"))
        case "font":
            guard preferred.children.count == 1, let font = preferred.children.first else { throw unsupported("a font configuration without one font") }
            try value(font, "key", in: ["fontDescription"])
            if let style = font.attributes["style"], Set(font.attributes.keys) == ["key", "style"], let weight = NibSymbolConfiguration.textStyleWeights[style] {
                configuration.weight = configuration.weight ?? weight
                configuration.textStyle = string(style)
            } else if font.attributes["type"] == "system", attributes["weight"] == nil, let size = font.attributes["pointSize"], Set(font.attributes.keys).isSubset(of: ["key", "type", "weight", "pointSize"]) {
                // `symbol-font-system*`.
                configuration.pointSize = Float(try number(size, "pointSize"))
                configuration.weight = try mapped(font.attributes["weight"] ?? "regular", NibSymbolConfiguration.weights, "weight")
            } else {
                throw unsupported("a font configuration other than a text style's")
            }
        case let other:
            throw unsupported("configurationType=\"\(other ?? "")\"")
        }
        let empty = configuration.scale == nil && configuration.weight == nil && configuration.pointSize == nil
        return empty ? nil : configuration
    }

    /// A color of no name, one object per value.
    mutating func unnamedColor(_ components: NibColor.Components) -> NibColor {
        let identity = "\(components) "
        if let existing = colors[identity] { return existing }
        let color = NibColor(components: components, name: nil)
        colors[identity] = color
        return color
    }
}
