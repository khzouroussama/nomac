import Foundation

/// What a `UIControl` writes after a view's keys (docs/formats/nib.md "UIControl"; nib-experiments
/// `button-control-flags`, `button-halign-*`, `button-valign-*`): its state, then its content
/// alignments, the vertical one twice; center, the default, is left out.
struct ControlContent {
    var highlighted = false
    var selected = false
    var enabled = true
    var verticalAlignment = 0
    var horizontalAlignment = 0
    var pointerInteractionEnabled = false

    func encode(to encoder: NibEncoder) {
        if highlighted { encoder.encode(.boolean(true), forKey: "UIHighlighted") }
        if selected { encoder.encode(.boolean(true), forKey: "UISelected") }
        if !enabled { encoder.encode(.boolean(true), forKey: "UIDisabled") }
        if verticalAlignment != 0 {
            encoder.encode(.integer(verticalAlignment), forKey: "UIContentVerticalAlignment")
            encoder.encode(.integer(verticalAlignment), forKey: "UIContentVerticalAlignment2")
        }
        if horizontalAlignment != 0 { encoder.encode(.integer(horizontalAlignment), forKey: "UIContentHorizontalAlignment") }
        if pointerInteractionEnabled { encoder.encode(.boolean(true), forKey: "UIPointerInteractionEnabled") }
    }

    static let attributes = ["contentHorizontalAlignment", "contentVerticalAlignment", "enabled", "selected", "highlighted", "pointerInteraction"]
    /// `UIControl.ContentHorizontalAlignment` and `ContentVerticalAlignment`, by the names documents use.
    static let horizontalAlignments = ["center": 0, "left": 1, "right": 2, "fill": 3, "leading": 4, "trailing": 5]
    static let verticalAlignments = ["center": 0, "top": 1, "bottom": 2, "fill": 3]
}

/// What a `UIButton` writes after a control's keys (docs/formats/nib.md "UIButton"; nib-experiments
/// `button-*`): its states' content by state, the flags that differ from IB's, its type, its font,
/// its insets as top, left, bottom, right, and its configuration; a configured button writes neither
/// its states' content nor its font (`bc-plain-title`, `bc-no-state`).
struct ButtonContent {
    var control: ControlContent
    var states: [(state: NibNumber, content: NibButtonContent)]
    var lineBreakMode: Int?
    var reversesTitleShadowWhenHighlighted = false
    var showsTouchWhenHighlighted = false
    var adjustsImageWhenHighlighted = true
    var adjustsImageWhenDisabled = true
    var type: Int
    var adjustsImageSizeForAccessibility = false
    var font: NibFont?
    var titleShadowOffset: [Double]?
    var role: Int?
    var contentInsets: [Double]?
    var titleInsets: [Double]?
    var imageInsets: [Double]?
    var springLoaded = false
    var changesSelectionAsPrimaryAction = false
    var configuration: NibButtonConfiguration?

    func encode(to encoder: NibEncoder) throws {
        control.encode(to: encoder)
        if !states.isEmpty, configuration == nil {
            let dictionary = NibDictionary()
            dictionary.entries = states.map { (key: $0.state, value: $0.content) }
            dictionary.mutable = true
            try encoder.encode(dictionary, forKey: "UIButtonStatefulContent")
        }
        if let lineBreakMode { encoder.encode(.integer(lineBreakMode), forKey: "UILineBreakMode") }
        if reversesTitleShadowWhenHighlighted { encoder.encode(.boolean(true), forKey: "UIReversesTitleShadowWhenHighlighted") }
        if showsTouchWhenHighlighted { encoder.encode(.boolean(true), forKey: "UIShowsTouchWhenHighlighted") }
        if adjustsImageWhenHighlighted { encoder.encode(.boolean(true), forKey: "UIAdjustsImageWhenHighlighted") }
        if adjustsImageWhenDisabled { encoder.encode(.boolean(true), forKey: "UIAdjustsImageWhenDisabled") }
        if type != 0 { encoder.encode(.integer(type), forKey: "UIButtonType") }
        if adjustsImageSizeForAccessibility { encoder.encode(.boolean(true), forKey: "UIAdjustsImageSizeForAccessibilityContentSizeCategory") }
        if let font, configuration == nil { try encoder.encode(font, forKey: "UIFont") }
        if let role { encoder.encode(.integer(role), forKey: "UIButtonRole") }
        if let contentInsets { encoder.encode(.data(NibView.doubles(contentInsets)), forKey: "UIContentEdgeInsets") }
        if let titleInsets { encoder.encode(.data(NibView.doubles(titleInsets)), forKey: "UITitleEdgeInsets") }
        if let titleShadowOffset { encoder.encode(.data(NibView.doubles(titleShadowOffset)), forKey: "UITitleShadowOffset") }
        if let imageInsets { encoder.encode(.data(NibView.doubles(imageInsets)), forKey: "UIImageEdgeInsets") }
        if springLoaded { encoder.encode(.boolean(true), forKey: "UISpringLoaded") }
        if changesSelectionAsPrimaryAction { encoder.encode(.boolean(true), forKey: "UIButtonChangesSelectionAsPrimaryAction") }
        try encoder.encode(configuration, forKey: "UIButtonConfiguration")
    }

    static let attributes = ["buttonType", "lineBreakMode", "showsTouchWhenHighlighted", "adjustsImageWhenHighlighted", "adjustsImageWhenDisabled",
                             "reversesTitleShadowWhenHighlighted", "adjustsImageSizeForAccessibilityContentSizeCategory", "role", "menu",
                             "springLoaded", "changesSelectionAsPrimaryAction"]
    /// `UIButton.ButtonType` by the names documents use (roundedRect is system), and the font a
    /// button without a font description gets: system buttons 15 points, custom ones 18; the
    /// others show only their image (`button-type-*`).
    static let types = ["custom": 0, "system": 1, "roundedRect": 1, "detailDisclosure": 2, "infoLight": 3, "infoDark": 4, "contactAdd": 5]
    static let defaultFontSizes = [0: "18", 1: "15"]

    /// Whether the button is of a type that shows only its image, which writes its content
    /// hugging priorities even when they are IB's (`button-type-infoLight-hugging`).
    var imageOnly: Bool { Self.defaultFontSizes[type] == nil }
    /// `UIControl.State` by the names documents use; the states' content is ordered by state, its
    /// numbers shared by the encoder (`button-two`).
    static let states = ["normal": 0, "highlighted": 1, "disabled": 2, "selected": 4]
    static let roles = ["normal": 0, "primary": 1, "cancel": 2, "destructive": 3]
}

/// `UIButtonContent`: a state's title, images and colors (`button-state-content`).
final class NibButtonContent: NibArchivable {
    var title: NibArchivable?
    var image: NibImage?
    /// The state's preferred symbol configuration (`symbol-button-hierarchical-light`).
    var symbolConfiguration: NibSymbolConfiguration?
    var backgroundImage: NibImage?
    var titleColor: NibColor?
    var shadowColor: NibColor?

    var className: String { "UIButtonContent" }

    var isEmpty: Bool { title == nil && image == nil && symbolConfiguration == nil && backgroundImage == nil && titleColor == nil && shadowColor == nil }

    func encode(to encoder: NibEncoder) throws {
        if let title { try encoder.encode(title, forKey: "UITitle") }
        if let image { try encoder.encode(image, forKey: "UIImage") }
        if let symbolConfiguration { try encoder.encode(symbolConfiguration, forKey: "UIImageSymbolConfiguration") }
        if let backgroundImage { try encoder.encode(backgroundImage, forKey: "UIBackgroundImage") }
        if let titleColor { try encoder.encode(titleColor, forKey: "UITitleColor") }
        if let shadowColor { try encoder.encode(shadowColor, forKey: "UIShadowColor") }
    }
}

extension DocumentCompiler {
    /// A `<button>`'s control and button content (`button-*`). The image-only types drop their
    /// states' content and their font (`button-type-*-untitled`, `button-type-infoLight-*`); their
    /// titles, which ibtool drops with a warning, are refused.
    mutating func buttonContent(_ element: XIBElement) throws -> ButtonContent {
        let type = try mapped(element.attributes["buttonType"] ?? "custom", ButtonContent.types, "buttonType")
        var states: [(state: Int, content: NibButtonContent)] = []
        for state in element.children(named: "state") {
            try check(state, attributes: ["key", "title", "image", "catalog", "backgroundImage"], children: ["color", "imageReference", "preferredSymbolConfiguration"])
            let content = NibButtonContent()
            if let title = state.attributes["title"] {
                content.title = localizableText(title, key: "\(element.attributes["id"] ?? "").\(state.attributes["key"] ?? "")Title")
            }
            content.image = try symbolImage(state) ?? state.attributes["image"].map { try image($0, catalog: state.attributes["catalog"]) }
            content.symbolConfiguration = try preferredSymbolConfiguration(state, key: "preferredSymbolConfiguration")
            guard content.symbolConfiguration == nil || (content.title == nil && content.backgroundImage == nil && state.children(named: "color").isEmpty) else {
                throw unsupported("a button state's symbol configuration beside a title, a background image or colors")
            }
            content.backgroundImage = try state.attributes["backgroundImage"].map { try image($0, catalog: nil) }
            for color in state.children(named: "color") {
                switch color.attributes["key"] {
                case "titleColor": content.titleColor = try self.color(color)
                case "titleShadowColor": content.shadowColor = try self.color(color)
                default: throw unsupported("<color key=\"\(color.attributes["key"] ?? "")\"> in a button's state")
                }
            }
            let titled = ButtonContent.defaultFontSizes[type] != nil
            if !titled, content.title != nil { throw unsupported("a title on a button of type \(type) (ibtool drops it with a warning)") }
            guard titled, !content.isEmpty else { continue }
            states.append((try mapped(state.attributes["key"] ?? "", ButtonContent.states, "state key"), content))
        }
        var insets: [String: [Double]] = [:]
        for inset in element.children(named: "inset") {
            try check(inset, attributes: ["key", "minX", "minY", "maxX", "maxY"], children: [])
            let values = try ["minY", "minX", "maxY", "maxX"].map { try number(inset.attributes[$0] ?? "0", $0) }
            if values.contains(where: { $0 != 0 }) { insets[inset.attributes["key"] ?? ""] = values }
        }
        guard Set(insets.keys).isSubset(of: ["contentEdgeInsets", "titleEdgeInsets", "imageEdgeInsets"]) else {
            throw unsupported("<inset key=\"\(insets.keys.sorted().joined(separator: ", "))\"> in a button")
        }
        try value(element, "menu", in: ["NO"])
        var font: NibFont?
        if let size = ButtonContent.defaultFontSizes[type] {
            var described = element
            if element.children(named: "fontDescription").isEmpty {
                described = XIBElement(name: "button", attributes: [:])
                described.children = [XIBElement(name: "fontDescription", attributes: ["key": "fontDescription", "type": "system", "pointSize": size])]
            }
            font = try self.font(described).font
        }
        let attributes = element.attributes
        var control = ControlContent()
        control.highlighted = try bool(element, "highlighted", default: false)
        control.selected = try bool(element, "selected", default: false)
        control.enabled = try bool(element, "enabled", default: true)
        control.horizontalAlignment = try mapped(attributes["contentHorizontalAlignment"] ?? "center", ControlContent.horizontalAlignments,
                                                 "contentHorizontalAlignment")
        control.verticalAlignment = try mapped(attributes["contentVerticalAlignment"] ?? "center", ControlContent.verticalAlignments,
                                               "contentVerticalAlignment")
        control.pointerInteractionEnabled = try bool(element, "pointerInteraction", default: false)
        let sorted = states.sorted { $0.state < $1.state }.map { (state: NibNumber(integer: $0.state), content: $0.content) }
        var button = ButtonContent(control: control, states: sorted, type: type, font: font)
        // A title shadow of no offset writes none (`button-title-shadow-offset-*`).
        for size in element.children(named: "size") {
            try check(size, attributes: ["key", "width", "height"], children: [])
            let offset = [try number(size.attributes["width"] ?? "0", "width"), try number(size.attributes["height"] ?? "0", "height")]
            if offset != [0, 0] { button.titleShadowOffset = offset }
        }
        button.lineBreakMode = try attributes["lineBreakMode"].flatMap { mode in
            mode == "middleTruncation" ? nil : try mapped(mode, LabelContent.lineBreakModes, "lineBreakMode")
        }
        button.reversesTitleShadowWhenHighlighted = try bool(element, "reversesTitleShadowWhenHighlighted", default: false)
        button.showsTouchWhenHighlighted = try bool(element, "showsTouchWhenHighlighted", default: false)
        button.adjustsImageWhenHighlighted = try bool(element, "adjustsImageWhenHighlighted", default: true)
        button.adjustsImageWhenDisabled = try bool(element, "adjustsImageWhenDisabled", default: true)
        button.adjustsImageSizeForAccessibility = try bool(element, "adjustsImageSizeForAccessibilityContentSizeCategory", default: false)
        button.role = try attributes["role"].flatMap { role in role == "normal" ? nil : try mapped(role, ButtonContent.roles, "role") }
        button.contentInsets = insets["contentEdgeInsets"]
        button.titleInsets = insets["titleEdgeInsets"]
        button.imageInsets = insets["imageEdgeInsets"]
        button.springLoaded = try bool(element, "springLoaded", default: false)
        button.changesSelectionAsPrimaryAction = try bool(element, "changesSelectionAsPrimaryAction", default: false)
        let configurations = element.children(named: "buttonConfiguration")
        guard configurations.count <= 1 else { throw unsupported("a button with two configurations") }
        button.configuration = try configurations.first.map { try buttonConfiguration($0, id: element.attributes["id"]) }
        return button
    }

    /// An image placeholder by name, one object per image; a system image (an SF Symbol) of no size
    /// (`button-image-symbol`).
    mutating func image(_ name: String, catalog: String?) throws -> NibImage {
        guard catalog == nil || catalog == "system" else { throw unsupported("the image catalog \(catalog ?? "")") }
        let identity = catalog.map { "\($0):\(name)" } ?? name
        if let image = images[identity] { return image }
        let image = NibImage(name: string(name), symbol: catalog != nil)
        images[identity] = image
        return image
    }
}
