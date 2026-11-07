import Foundation

/// What a `UITableViewCell` writes after a view's keys (docs/formats/nib.md "Table view cells",
/// nib-experiments `cell-*`): its reuse identifier, style, accessories, indentation, whether its
/// background color was set, its content view and the labels of its style; its image view nil.
struct CellContent {
    /// `UITableViewCell.AccessoryType` of the accessories observed.
    static let accessoryTypes = ["disclosureIndicator": 1, "checkmark": 3, "detailButton": 4]
    /// `UITableViewCell.CellStyle` of the styles observed, and their labels (`cell-style-*`).
    static let styles = ["IBUITableViewCellStyleDefault": (0, ["textLabel"]), "IBUITableViewCellStyleValue1": (1, ["textLabel", "detailTextLabel"]),
                         "IBUITableViewCellStyleValue2": (2, ["textLabel", "detailTextLabel"]),
                         "IBUITableViewCellStyleSubtitle": (3, ["textLabel", "detailTextLabel"])]
    /// `UITableViewCell.SelectionStyle` of a cell that does not use the default style, and the system
    /// background view such a cell writes (`cell-selection-*`).
    var selectionStyle: Int?
    var systemBackgroundView: NibView?
    var reuseIdentifier: NibString?
    var showsReorderControl: Bool
    var style = 0
    var accessoryType: Int?
    var editingAccessoryType: Int?
    var indentationLevel: Int?
    var indentationWidth: Float
    /// `separatorInset`'s top, left, bottom and right (`cell-separator-inset-*`).
    var separatorInset: [Double]?
    var focusStyleCustom = false
    var backgroundColorSet: Bool
    let contentView: NibView
    var textLabel: NibView?
    var detailTextLabel: NibView?
    /// A cell's `imageView`, a subview of its content view (`cm-image-*`).
    var imageView: NibView?

    func encode(to encoder: NibEncoder) throws {
        if let reuseIdentifier { try encoder.encode(reuseIdentifier, forKey: "UIReuseIdentifier") }
        if showsReorderControl { encoder.encode(.boolean(true), forKey: "UIShowsReorderControl") }
        if style != 0 { encoder.encode(.integer(style), forKey: "UITableViewCellStyle") }
        if let indentationLevel { encoder.encode(.integer(indentationLevel), forKey: "UIIndentationLevel") }
        if let selectionStyle { encoder.encode(.integer(selectionStyle), forKey: "UISelectionStyle") }
        if let accessoryType { encoder.encode(.integer(accessoryType), forKey: "UIAccessoryType") }
        if let editingAccessoryType { encoder.encode(.integer(editingAccessoryType), forKey: "UIEditingAccessoryType") }
        encoder.encode(.float(indentationWidth), forKey: "UIIndentationWidth")
        if backgroundColorSet { encoder.encode(.boolean(true), forKey: "UITableCellBackgroundColorSet") }
        if let separatorInset { encoder.encode(.data(NibView.doubles(separatorInset)), forKey: "UISeparatorInset") }
        if focusStyleCustom { encoder.encode(.integer(1), forKey: "UIFocusStyle") }
        try encoder.encode(systemBackgroundView, forKey: "UISystemBackgroundView")
        encoder.encode(.null, forKey: "UIContentConfigurationView")
        try encoder.encode(contentView, forKey: "UIContentView")
        try encoder.encode(textLabel, forKey: "UITextLabel")
        try encoder.encode(detailTextLabel, forKey: "UIDetailTextLabel")
        try encoder.encode(imageView, forKey: "UIImageView")
    }
}

/// `UIBackgroundConfiguration` of a cell's system background view, whose height is the cell's
/// rounded up (`cell-selection-none-height-*`, cwa's exposure detection cells): nothing
/// customized, the cell's background color, a clear stroke, no insets (`cell-selection-*`); the
/// insets one string of the nib's (the corpus's tofu storyboard, whose static cells share it). A
/// button configuration's has corners of 17, a customized stroke 1 wide and the default style 0
/// (`bc-*`).
final class NibBackgroundConfiguration: NibArchivable {
    let backgroundColor: NibColor
    let strokeColor: NibColor
    let insets: NibString
    let button: Bool

    init(backgroundColor: NibColor, strokeColor: NibColor, insets: NibString, button: Bool = false) {
        self.backgroundColor = backgroundColor
        self.strokeColor = strokeColor
        self.insets = insets
        self.button = button
    }

    var className: String { "UIBackgroundConfiguration" }

    func encode(to encoder: NibEncoder) throws {
        func customized(_ name: String) { encoder.encode(.boolean(false), forKey: "hasCustomized-\(name)") }
        encoder.encode(.null, forKey: "customView"); customized("customView")
        encoder.encode(.double(button ? 17 : 0), forKey: "cornerRadius"); customized("cornerRadius")
        encoder.encode(.integer(15), forKey: "maskedCorners"); customized("maskedCorners")
        try encoder.encode(backgroundColor, forKey: "backgroundColor"); customized("backgroundColor")
        encoder.encode(.integer(0), forKey: "backgroundColorTransformerIdentifier"); customized("backgroundColorTransformerIdentifier")
        encoder.encode(.null, forKey: "visualEffect"); customized("visualEffect")
        encoder.encode(.null, forKey: "visualEffectGroupName"); customized("visualEffectGroupName")
        encoder.encode(.integer(0), forKey: "visualEffectblurClippingMode")
        encoder.encode(.null, forKey: "image"); customized("image")
        encoder.encode(.integer(0), forKey: "imageContentMode"); customized("imageContentMode")
        try encoder.encode(insets, forKey: "backgroundInsets"); customized("backgroundInsets")
        encoder.encode(.integer(0), forKey: "edgesAddingLayoutMarginsToBackgroundInsets"); customized("edgesAddingLayoutMarginsToBackgroundInsets")
        try encoder.encode(strokeColor, forKey: "strokeColor")
        encoder.encode(.boolean(button), forKey: "hasCustomized-strokeColor")
        encoder.encode(.integer(0), forKey: "strokeColorTransformerIdentifier"); customized("strokeColorTransformerIdentifier")
        encoder.encode(.double(button ? 1 : 0), forKey: "strokeWidth")
        encoder.encode(.boolean(button), forKey: "hasCustomized-strokeWidth")
        encoder.encode(.double(0), forKey: "strokeOutset"); customized("strokeOutset")
        encoder.encode(.integer(0), forKey: "strokeLocation")
        encoder.encode(.integer(button ? 0 : 1), forKey: "defaultStyle")
        encoder.encode(.integer(button ? 0 : 11), forKey: "defaultStyle_v2")
    }
}

extension DocumentCompiler {
    /// A `<tableViewCell>` of a xib: the cell, its content view (compiled as a view of the cell) and
    /// the separator view IB adds, 8 points in from the left along the cell's bottom (`cell-*`).
    mutating func tableViewCell(_ element: XIBElement) throws -> NibView {
        try check(element, attributes: ["id", "contentMode", "selectionStyle", "indentationWidth", "indentationLevel", "reuseIdentifier", "rowHeight",
                                        "hidden", "tag", "userInteractionEnabled", "alpha", "insetsLayoutMarginsFromSafeArea", "focusStyle", "imageView",
                                        "accessoryType", "editingAccessoryType", "showsReorderControl", "style", "textLabel", "detailTextLabel", "colorLabel", "clipsSubviews", "preservesSuperviewLayoutMargins", "restorationIdentifier", "opaque", "hidesAccessoryWhenEditing",
                                        "clearsContextBeforeDrawing", "layoutMarginsFollowReadableWidth",
                                        "customClass", "customModule", "customModuleProvider", "userLabel"],
                  children: ["rect", "frame", "autoresizingMask", "tableViewCellContentView", "viewLayoutGuide", "point", "connections", "color",
                             "edgeInsets", "directionalEdgeInsets", "inset", "constraints", "userDefinedRuntimeAttributes",
                             "accessibility"])
        let selectionStyles = ["none": 0, "blue": 1, "gray": 2, "default": 3]
        guard let selectionStyle = selectionStyles[element.attributes["selectionStyle"] ?? "default"] else {
            throw unsupported("selectionStyle=\"\(element.attributes["selectionStyle"] ?? "")\"")
        }
        guard let id = element.attributes["id"], let rect = try element.child("rect", key: "frame") ?? cellFrameInset(element),
              element.children(named: "rect").allSatisfy({ ["frame", "contentStretch"].contains($0.attributes["key"] ?? "") }) else {
            throw unsupported("a table view cell without an id or a frame, or with another rectangle")
        }
        try check(rect, attributes: ["key", "x", "y", "width", "height"], children: [])
        let frame = (x: try number(rect.attributes["x"] ?? "0", "x"), y: try number(rect.attributes["y"] ?? "0", "y"),
                     width: try number(rect.attributes["width"] ?? "0", "width"), height: try number(rect.attributes["height"] ?? "0", "height"))
        var mask = 0
        for child in element.children(named: "autoresizingMask") {
            try check(child, attributes: ["key"] + NibView.autoresizingBits.keys, children: [])
            for (name, bit) in NibView.autoresizingBits where try bool(child, name, default: false) { mask |= bit }
        }
        let contents = element.children(named: "tableViewCellContentView")
        guard contents.count == 1, let content = contents.first, content.attributes["tableViewCell"] == id, content.attributes["key"] == "contentView" else {
            throw unsupported("a table view cell without one content view")
        }
        try check(content, attributes: ["key", "opaque", "clipsSubviews", "multipleTouchEnabled", "contentMode", "tableViewCell", "id", "clearsContextBeforeDrawing",
                                        "layoutMarginsFollowReadableWidth",
                                        "preservesSuperviewLayoutMargins", "insetsLayoutMarginsFromSafeArea", "ambiguous"],
                  children: ["rect", "frame", "autoresizingMask", "subviews", "constraints", "color", "variation", "edgeInsets", "directionalEdgeInsets",
                             "userDefinedRuntimeAttributes", "accessibility"])
        let contentElement = XIBElement(name: "view", attributes: content.attributes.filter { !["key", "tableViewCell"].contains($0.key) })
        contentElement.children = try content.children.map { child in
            // Xcode 8's `<frame key="frameInset">` of a width and height is the frame at 0, 0 of that
            // size (`sb-cell-frame-inset` against `sb-cell-frame-rect`; uncloudnotes' notes list).
            guard child.name == "frame" else { return child }
            try check(child, attributes: ["key", "width", "height"], children: [])
            try value(child, "key", in: ["frameInset"])
            guard content.children(named: "rect").isEmpty, let width = child.attributes["width"], let height = child.attributes["height"] else {
                throw unsupported("a cell content view's frame inset other than a width and a height")
            }
            return XIBElement(name: "rect", attributes: ["key": "frame", "x": "0.0", "y": "0.0", "width": width, "height": height])
        }
        let contentView = try view(contentElement, topLevel: false, parent: id)
        contentView.kind = .cellContentView
        var flags = NibView.Flags()
        flags.clipsToBounds = try bool(element, "clipsSubviews", default: false)
        flags.opaque = try bool(element, "opaque", default: true)
        flags.hidden = try bool(element, "hidden", default: false)
        flags.tag = try element.attributes["tag"].map { try integer($0, "tag") }
        flags.userInteractionDisabled = !(try bool(element, "userInteractionEnabled", default: true))
        flags.alpha = try element.attributes["alpha"].flatMap { text in
            guard let alpha = Float(text) else { throw unsupported("alpha=\"\(text)\"") }
            return alpha == 1 ? nil : alpha
        }
        flags.contentMode = try mapped(element.attributes["contentMode"] ?? "scaleToFill", NibView.contentModes, "contentMode")
        flags.insetsLayoutMarginsFromSafeArea = try bool(element, "insetsLayoutMarginsFromSafeArea", default: true)
        flags.clearsContextBeforeDrawing = try bool(element, "clearsContextBeforeDrawing", default: true)
        flags.layoutMarginsFollowReadableWidth = try bool(element, "layoutMarginsFollowReadableWidth", default: false)
        flags.contentStretch = try contentStretch(element)
        flags.preservesSuperviewLayoutMargins = try bool(element, "preservesSuperviewLayoutMargins", default: false)
        _ = try bool(element, "hidesAccessoryWhenEditing", default: true)
        let separatorInset = try separatorInset(element)
        let separatorX = 8 + (separatorInset?[1] ?? 0)
        var separatorFlags = NibView.Flags()
        separatorFlags.opaque = true
        let separator = NibView(frame: (separatorX, frame.height - 1, frame.width - separatorX, 1), autoresizingMask: 0, flags: separatorFlags, subviews: [],
                                backgroundColor: nil, customClass: nil)
        separator.kind = .cellSeparator
        var background = try element.child("color", key: "backgroundColor").map { try color($0) }
        let backgroundColorSet = background != nil
        var systemBackground: NibView?
        if selectionStyle != 3, background == nil {
            let plain = systemColor("tableCellPlainBackgroundColor", .gray(white: 1, alpha: 1))
            let clear = try color(XIBElement(name: "color", attributes: ["cocoaTouchSystemColor": "clearColor"]))
            var backgroundFlags = NibView.Flags()
            backgroundFlags.opaque = true
            guard frame.width.rounded(.up) == frame.width else { throw unsupported("a table view cell of a fractional width and a selection style") }
            let view = NibView(frame: (0, 0, frame.width, frame.height.rounded(.up)), autoresizingMask: 0, flags: backgroundFlags, subviews: [],
                               backgroundColor: nil, customClass: nil)
            view.kind = .systemBackground(NibBackgroundConfiguration(backgroundColor: plain, strokeColor: clear,
                                                                                insets: string("{0, 0, 0, 0}")))
            background = plain
            systemBackground = view
        }
        let cell = NibView(frame: frame, autoresizingMask: mask, flags: flags, subviews: [contentView, separator], backgroundColor: background,
                           customClass: try customClass(element, original: "UITableViewCell"))
        for child in element.children(named: "color") where !["backgroundColor", "tintColor"].contains(child.attributes["key"] ?? "") {
            throw unsupported("<color key=\"\(child.attributes["key"] ?? "")\"> in a table view cell")
        }
        cell.tintColor = try element.child("color", key: "tintColor").map { try color($0) }
        if let margins = try layoutMargins(element) {
            cell.layoutMargins = margins.margins
            cell.flags.layoutMarginsAreDirectional = margins.directional
        }
        cell.restorationIdentifier = element.attributes["restorationIdentifier"].map { string($0) }
        let accessories = try ["accessoryType", "editingAccessoryType"].map { attribute in
            try element.attributes[attribute].map { try mapped($0, CellContent.accessoryTypes, attribute) }
        }
        var cellContent = CellContent(selectionStyle: selectionStyle == 3 ? nil : selectionStyle, systemBackgroundView: systemBackground,
                                      reuseIdentifier: element.attributes["reuseIdentifier"].map { string($0) },
                                      showsReorderControl: try bool(element, "showsReorderControl", default: false),
                                      accessoryType: accessories[0], editingAccessoryType: accessories[1],
                                      indentationLevel: try element.attributes["indentationLevel"].map { try integer($0, "indentationLevel") },
                                      indentationWidth: Float(try number(element.attributes["indentationWidth"] ?? "10", "indentationWidth")),
                                      backgroundColorSet: backgroundColorSet, contentView: contentView)
        cellContent.separatorInset = separatorInset
        cellContent.focusStyleCustom = element.attributes["focusStyle"] == "custom"
        try value(element, "focusStyle", in: ["custom", "default"])
        try cellStyle(element, contentView: contentView, into: &cellContent)
        cell.kind = .cell(cellContent)
        for guide in element.children(named: "viewLayoutGuide") {
            try check(guide, attributes: ["key", "id"], children: [])
            guard let guideID = guide.attributes["id"], guide.attributes["key"] == "safeArea", cell.safeAreaPlaceholder == nil else {
                throw unsupported("a table view cell with two safe areas")
            }
            cell.safeAreaPlaceholder = NibSafeAreaGuide(identifier: string(""))
            requires(11, 0)
            safeAreaGuides[guideID] = id
        }
        documentViews[id] = DocumentView(view: cell, frame: frame, parent: nil, translates: true, hasMask: mask != 0)
        for container in element.children(named: "constraints") {
            try check(container, attributes: [], children: ["constraint"])
            pendingConstraints.append(PendingConstraints(owner: id, elements: container.children))
        }
        try connections(of: element, source: cell)
        try runtimeAttributes(of: element, object: cell)
        try accessibility(of: element, object: cell)
        for segue in cellSeguePlaceholders[id] ?? [] {
            cellSegueOutlets.append(NibOutletConnection(label: string(segue.accessory ? "accessoryActionSegueTemplate" : "selectionSegueTemplate"), source: cell,
                                                        destination: segue.placeholder))
        }
        return cell
    }

    /// Xcode 8's `<frame key="frameInset">` of a top, a width and a height is the frame at that top
    /// (`cm-sb-proto-frame-inset`).
    private func cellFrameInset(_ element: XIBElement) throws -> XIBElement? {
        guard let inset = element.children(named: "frame").first else { return nil }
        try check(inset, attributes: ["key", "minY", "width", "height"], children: [])
        try value(inset, "key", in: ["frameInset"])
        guard let width = inset.attributes["width"], let height = inset.attributes["height"] else { return nil }
        return XIBElement(name: "rect", attributes: ["key": "frame", "x": "0.0", "y": inset.attributes["minY"] ?? "0.0", "width": width, "height": height])
    }

    /// A cell's `<inset key="separatorInset">` as top, left, bottom, right; IB's separator view then
    /// starts 8 points past its left inset (`cell-separator-inset-*`).
    private func separatorInset(_ element: XIBElement) throws -> [Double]? {
        guard let inset = element.child("inset", key: "separatorInset") else { return nil }
        try check(inset, attributes: ["key", "minX", "minY", "maxX", "maxY"], children: [])
        return try ["minY", "minX", "maxY", "maxX"].map { try number(inset.attributes[$0] ?? "0", $0) }
    }

    /// A cell of a built-in style: its style's labels, subviews of its content view of the class
    /// `UITableViewLabel` (`cell-style-*`).
    private func cellStyle(_ element: XIBElement, contentView: NibView, into content: inout CellContent) throws {
        if let imageView = element.attributes["imageView"] {
            guard let view = documentViews[imageView]?.view, contentView.subviews.contains(where: { $0 === view }), view.isImageView else {
                throw unsupported("a table view cell's imageView that is not an image view of its content view")
            }
            content.imageView = view
        }
        let labels = ["textLabel", "detailTextLabel"].filter { element.attributes[$0] != nil }
        guard let name = element.attributes["style"] else {
            guard labels.isEmpty else { throw unsupported("a table view cell's labels without a style") }
            return
        }
        guard let (style, styleLabels) = CellContent.styles[name] else { throw unsupported("style=\"\(name)\" in <tableViewCell>") }
        guard labels == styleLabels else { throw unsupported("a table view cell of the style \(name) without its labels") }
        let views = try labels.map { attribute in
            guard let view = documentViews[element.attributes[attribute]!]?.view, contentView.subviews.contains(where: { $0 === view }),
                  view.label != nil, view.customClass == nil else {
                throw unsupported("a table view cell's \(attribute) that is not a label of its content view")
            }
            view.kind = .cellLabel
            return view
        }
        content.style = style
        content.textLabel = views[0]
        content.detailTextLabel = views.count > 1 ? views[1] : nil
    }
}
