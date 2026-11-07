import Foundation

/// A `UIView` (or a `UIClassSwapper` for a view with a custom class, a `UIImageView` for an image
/// view), with the keys and the key order ibtool writes (docs/formats/nib.md "UIView";
/// nib-experiments `view-*`, `image-view-*`), or the `_UILayoutGuide` ibtool adds to a storyboard
/// scene's view (`storyboard`, `sb-*`).
/// An object whose children all objects lists after it, breadth first.
protocol NibObjectChildren {
    var childObjects: [NibArchivable] { get }
}

/// What a `<datePicker>` writes after a view's keys.
struct DatePickerContent {
    let alignment: Int
    let style: Int?
    let mode: Int
    let minuteInterval: Int
    let usesCurrentDate: Bool
}

final class NibView: NibArchivable, NibObjectChildren {
    /// What a `_UILayoutGuide` writes after a view's keys.
    struct LayoutGuide {
        let identifier: NibString
        let constraintsToRemove: [NibLayoutConstraint]
    }

    struct Flags {
        var opaque = true
        var hidden = false
        var tag: Int?
        var userInteractionDisabled = false
        var clearsContextBeforeDrawing = true
        var multipleTouchEnabled = false
        var autoresizesSubviews = true
        var alpha: Float?
        var contentMode = 0
        var clipsToBounds = false
        /// Its content stretch, x, y, width and height, unless 0, 0, 1, 1 (`view-stretch*`).
        var contentStretch: [Double]?
        var doesNotTranslateAutoresizingMask = false
        var semanticContentAttribute = 0
        /// `UIViewContentHuggingPriority`, horizontal then vertical, when either is not 250, and
        /// `UIViewContentCompressionResistancePriority`, when either is not 750.
        var contentHugging: NibString?
        var compressionResistance: NibString?
        var insetsLayoutMarginsFromSafeArea = true
        var preservesSuperviewLayoutMargins = false
        var layoutMarginsFollowReadableWidth = false
        var layoutMarginsAreDirectional = false
        var shouldNotAdaptToMaterials = false
    }

    /// What a table view cell's views are (nib-experiments `cell-*`).
    enum Kind {
        case view
        case cell(CellContent)
        case cellContentView
        case cellSeparator
        /// The `textLabel` or `detailTextLabel` of a cell of a built-in style.
        case cellLabel
        case textField(TextFieldContent)
        /// `UISwitch`: enabled, whether it is on, its on and thumb tints (`sw-*`).
        case `switch`(on: Bool, onTint: NibColor?, thumbTint: NibColor?)
        case systemBackground(NibBackgroundConfiguration)
        case tableView(TableContent)
        case button(ButtonContent)
        case stack(StackContent)
        case scroll(ScrollContent)
        case collectionCell(CollectionCellContent)
        case reusableView(NibString?)
        case activity(ActivityContent)
        case segmented(SegmentedContent)
        case segment(SegmentContent)
        case progress(ProgressContent)
        case page(PageContent)
        case slider(SliderContent)
        case effect(EffectContent)
        case effectContentView
        case collection(CollectionContent)
        case textView(TextViewContent)
        /// `UIToolbar`, with its items or the nib's empty array (`toolbar-*`, `bars-tb-*`).
        case toolbar(items: NibArray, appearance: BarAppearance)
        case webView(WebViewContent)
        case map(MapContent)
        /// `UINavigationBar` among subviews: its items, a mutable array (`nav-bar-sub-*`).
        case navigationBar(items: NibArray, appearance: BarAppearance)
        /// `UIDatePicker` of date and time or a count-down timer (`date-picker-*`).
        case datePicker(DatePickerContent)
        case pickerView
        case refreshControl(enabled: Bool)
        case searchBar(SearchBarContent)

        var isCellLabel: Bool {
            if case .cellLabel = self { return true }
            return false
        }

        var isTableView: Bool {
            if case .tableView = self { return true }
            return false
        }

        /// A collection view controller's view has no layout guides of its controller's, as a table
        /// view controller's (`sb-cvc*`).
        var isCollection: Bool {
            if case .collection = self { return true }
            return false
        }

        var groupedTable: Bool {
            if case .tableView(let table) = self { return table.style != 0 }
            return false
        }
    }

    /// Nil for a layout guide, which writes no geometry.
    var frame: (x: Double, y: Double, width: Double, height: Double)?
    var autoresizingMask: Int
    var flags: Flags
    var subviews: [NibView]
    var backgroundColor: NibColor?
    var tintColor: NibColor?
    var restorationIdentifier: NibString?
    /// The layout margins, top, left or leading, bottom, right or trailing.
    var layoutMargins: [Double]?
    let customClass: (name: NibString, original: NibString)?
    var image: NibImage?
    var isImageView = false
    /// An image view's `adjustsImageSizeForAccessibilityContentSizeCategory`, after its image
    /// (`image-view-adjusts*`).
    var adjustsImageSizeForAccessibility = false
    /// An image view's preferred symbol configuration, after its image; it makes the image view
    /// write no `UIOpaque` (`image-view-symbol-preferred-*`).
    var preferredSymbolConfiguration: NibSymbolConfiguration?
    var label: LabelContent?
    var kind = Kind.view
    /// The constraints of a scene's layout guides, which come first, and the document's, in the
    /// order ibtool writes them.
    var guideConstraints: [NibLayoutConstraint] = []
    var constraints: [NibLayoutConstraint] = []
    /// Constraints a `<mask>` excludes by default: listed in all objects, not installed.
    var excludedConstraints: [NibLayoutConstraint] = []
    /// A cell's constraints between its content view's subviews, installed there.
    var movedOutConstraints: [NibLayoutConstraint] = []
    /// Subviews a `<mask key="subviews">` excludes by default: listed in all objects, not added.
    var excludedSubviews: [NibView] = []
    var layoutGuide: LayoutGuide?
    /// The safe area guide IB keeps (listed in all objects only), and the one constraints refer to.
    var safeAreaPlaceholder: NibSafeAreaGuide?
    /// A scroll view's content and frame layout guides, listed like the safe area's
    /// (`scroll-guides-constraints`).
    var layoutGuidePlaceholders: [NibArchivable] = []
    var layoutGuides: [NibViewLayoutGuide] = []

    init(frame: (x: Double, y: Double, width: Double, height: Double)?, autoresizingMask: Int, flags: Flags, subviews: [NibView],
         backgroundColor: NibColor?, customClass: (name: NibString, original: NibString)?) {
        self.frame = frame
        self.autoresizingMask = autoresizingMask
        self.flags = flags
        self.subviews = subviews
        self.backgroundColor = backgroundColor
        self.customClass = customClass
    }

    var className: String {
        if layoutGuide != nil { return "_UILayoutGuide" }
        if customClass != nil { return "UIClassSwapper" }
        switch kind {
        case .cell: return "UITableViewCell"
        case .cellContentView: return "UITableViewCellContentView"
        case .cellSeparator: return "_UITableViewCellSeparatorView"
        case .cellLabel: return "UITableViewLabel"
        case .textField: return "UITextField"
        case .switch: return "UISwitch"
        case .systemBackground: return "_UISystemBackgroundView"
        case .tableView: return "UITableView"
        case .button: return "UIButton"
        case .stack: return "UIStackView"
        case .scroll: return "UIScrollView"
        case .collectionCell: return "UICollectionViewCell"
        case .reusableView: return "UICollectionReusableView"
        case .activity: return "UIActivityIndicatorView"
        case .segmented: return "UISegmentedControl"
        case .segment: return "UISegment"
        case .progress: return "UIProgressView"
        case .page: return "UIPageControl"
        case .slider: return "UISlider"
        case .effect: return "UIVisualEffectView"
        case .effectContentView: return "_UIVisualEffectContentView"
        case .collection: return "UICollectionView"
        case .textView: return "UITextView"
        case .toolbar: return "UIToolbar"
        case .webView: return "WKWebView"
        case .map: return "MKMapView"
        case .navigationBar: return "UINavigationBar"
        case .datePicker: return "UIDatePicker"
        case .pickerView: return "UIPickerView"
        case .refreshControl: return "UIRefreshControl"
        case .searchBar: return "UISearchBar"
        case .view: return isImageView ? "UIImageView" : label != nil ? "UILabel" : "UIView"
        }
    }

    /// What all objects lists after the view, breadth first: its safe area guide, its constraints,
    /// a scene's layout guides, then its subviews (`constraint-to-safe-area`, `storyboard`). A cell
    /// lists its content view, safe area and style labels by their keys' alphabetical order
    /// (`cell-style-*`), then its content view's other subviews, the content view only its
    /// constraints (`mask-cell-group`; the corpus's tofu storyboard, two static cells). An effect
    /// view lists its content view and that view's subviews, then its constraints, the content view
    /// its own (`effect-label-sibling-*`, `effect-own-constraint*`). A table view lists its safe area
    /// (`safe-sub-table`), a collection view its layout first (`collection-safe-area*`).
    var childObjects: [NibArchivable] {
        guard layoutGuide == nil else { return [] }
        switch kind {
        case .cell(let cell):
            return [cell.contentView] + [cell.detailTextLabel].compactMap { $0 } + (safeAreaPlaceholder.map { [$0] } ?? [])
                + [cell.imageView].compactMap { $0 } + [cell.textLabel].compactMap { $0 }
                + cell.contentView.subviews.filter { view in !view.kind.isCellLabel && view !== cell.imageView && !cell.contentView.excludedSubviews.contains { $0 === view } }
                + constraints + movedOutConstraints
        case .cellContentView: return constraints + excludedSubviews
        case .cellSeparator, .systemBackground: return []
        case .tableView(let table): return (safeAreaPlaceholder.map { [$0] } ?? []) + constraints + [table.refreshControl].compactMap { $0 } + subviews
        case .collectionCell(let cell):
            let safeArea = safeAreaPlaceholder.map { [$0] } ?? []
            return cell.legacy ? safeArea + cell.contentView.subviews + cell.contentView.constraints : [cell.contentView] + safeArea
        case .segmented: return constraints
        case .effect(let effect): return [effect.contentView] + effect.contentView.subviews + constraints
        case .effectContentView: return constraints
        case .collection(let collection): return [collection.layout] + (safeAreaPlaceholder.map { [$0] } ?? []) + constraints + subviews
        case .segment: return []
        case .navigationBar(let items, _), .toolbar(let items, _): return (safeAreaPlaceholder.map { [$0] } ?? []) + constraints + items.elements
        case .view, .button, .stack, .scroll, .reusableView, .activity, .progress, .page, .slider, .cellLabel, .textField, .switch, .textView, .webView, .map, .datePicker,
             .pickerView, .searchBar, .refreshControl: break
        }
        let guides = subviews.filter { $0.layoutGuide != nil }
        return (safeAreaPlaceholder.map { [$0] } ?? []) + layoutGuidePlaceholders + constraints + guides + subviews.filter { $0.layoutGuide == nil }
    }
    var fallbackClassNames: [String] {
        if layoutGuide != nil { return ["UIView"] }
        if customClass == nil, case .cellContentView = kind { return ["UIView"] }
        return []
    }

    func encode(to encoder: NibEncoder) throws {
        if let frame {
            if frame.width != 0 || frame.height != 0 {
                encoder.encode(.data(Self.doubles([0, 0, frame.width, frame.height])), forKey: "UIBounds")
            }
            encoder.encode(.data(Self.doubles([frame.x + frame.width / 2, frame.y + frame.height / 2])), forKey: "UICenter")
        }
        let added = subviews.filter { view in !excludedSubviews.contains { $0 === view } }
        if !added.isEmpty {
            try encoder.encode(NibArray(added, mutable: true), forKey: "UISubviews")
        }
        if let backgroundColor {
            try encoder.encode(backgroundColor, forKey: "UIBackgroundColor")
            if case .cell(let cell) = kind, cell.systemBackgroundView != nil {
                encoder.encode(.boolean(true), forKey: "UIDidEncodeCompatibilityBackgroundColor")
            }
        }
        encoder.encode(.boolean(true), forKey: "UIDeepDrawRect")
        if flags.opaque { encoder.encode(.boolean(true), forKey: "UIOpaque") }
        if flags.hidden { encoder.encode(.boolean(true), forKey: "UIHidden") }
        if let tag = flags.tag, tag != 0 { encoder.encode(.integer(tag), forKey: "UITag") }
        if flags.userInteractionDisabled { encoder.encode(.boolean(true), forKey: "UIUserInteractionDisabled") }
        if flags.multipleTouchEnabled { encoder.encode(.boolean(true), forKey: "UIMultipleTouchEnabled") }
        if flags.autoresizesSubviews { encoder.encode(.boolean(true), forKey: "UIAutoresizeSubviews") }
        if autoresizingMask != 0 { encoder.encode(.integer(autoresizingMask), forKey: "UIAutoresizingMask") }
        if flags.shouldNotAdaptToMaterials { encoder.encode(.boolean(true), forKey: "UIShouldNotAdaptToMaterials") }
        if !flags.clearsContextBeforeDrawing { encoder.encode(.boolean(false), forKey: "UIClearsContextBeforeDrawing") }
        if let alpha = flags.alpha { encoder.encode(.float(alpha), forKey: "UIAlpha") }
        if flags.contentMode != 0 { encoder.encode(.integer(flags.contentMode), forKey: "UIContentMode") }
        if let stretch = flags.contentStretch { encoder.encode(.data(Self.doubles(stretch)), forKey: "UIContentStretch") }
        if flags.clipsToBounds { encoder.encode(.boolean(true), forKey: "UIClipsToBounds") }
        if let tintColor {
            if case .segmented = kind {
                try encoder.encode(tintColor, forKey: "UISegmentedControlTintColor")
            } else {
                try encoder.encode(tintColor, forKey: "UITintColor")
            }
        }
        if flags.doesNotTranslateAutoresizingMask {
            encoder.encode(.boolean(true), forKey: "UIViewDoesNotTranslateAutoresizingMaskIntoConstraints")
        }
        let installed = (guideConstraints + constraints).filter { constraint in !excludedConstraints.contains { $0 === constraint } }
        if !installed.isEmpty {
            try encoder.encode(NibArray(installed, mutable: true), forKey: "UIViewAutolayoutConstraints")
        }
        if !layoutGuides.isEmpty {
            try encoder.encode(NibArray(layoutGuides, mutable: true), forKey: "UIViewLayoutGuides")
        }
        if let hugging = flags.contentHugging {
            try encoder.encode(hugging, forKey: "UIViewContentHuggingPriority")
        }
        if let resistance = flags.compressionResistance {
            try encoder.encode(resistance, forKey: "UIViewContentCompressionResistancePriority")
        }
        if let layoutMargins {
            encoder.encode(.data(Self.doubles(layoutMargins)), forKey: "UIViewLayoutMargins")
        }
        if flags.layoutMarginsFollowReadableWidth {
            encoder.encode(.boolean(true), forKey: "UIViewLayoutMarginsFollowReadableWidth")
        }
        if flags.preservesSuperviewLayoutMargins {
            encoder.encode(.boolean(true), forKey: "UIViewPreservesSuperviewMargins")
            encoder.encode(.integer(15), forKey: "UIViewPreservesSpecificSuperviewMargins")
        }
        if flags.layoutMarginsAreDirectional {
            encoder.encode(.boolean(true), forKey: "UIViewLayoutMarginsAreDirectional")
        }
        if !flags.insetsLayoutMarginsFromSafeArea {
            encoder.encode(.integer(0), forKey: "UIViewInsetsLayoutMarginsFromSafeArea")
        }
        if let restorationIdentifier { try encoder.encode(restorationIdentifier, forKey: "UIRestorationIdentifier") }
        encoder.encode(.integer(flags.semanticContentAttribute), forKey: "UIViewSemanticContentAttribute")
        encoder.encode(.null, forKey: "UIViewLargeContentStoredProperties")
        if let layoutGuide {
            try encoder.encode(layoutGuide.identifier, forKey: "_UILayoutGuideIdentifier")
            try encoder.encode(NibArray(layoutGuide.constraintsToRemove), forKey: "_UILayoutGuideConstraintsToRemove")
        }
        if let image {
            try encoder.encode(image, forKey: "UIImage")
        }
        if let preferredSymbolConfiguration { try encoder.encode(preferredSymbolConfiguration, forKey: "UIPreferredSymbolConfiguration") }
        if adjustsImageSizeForAccessibility { encoder.encode(.boolean(true), forKey: "UIAdjustsImageSizeForAccessibilityContentSizeCategory") }
        try label?.encode(to: encoder)
        switch kind {
        case .cell(let cell): try cell.encode(to: encoder)
        case .systemBackground(let configuration): try encoder.encode(configuration, forKey: "configurationAPI")
        case .tableView(let table): try table.encode(to: encoder)
        case .button(let button): try button.encode(to: encoder)
        case .stack(let stack): try stack.encode(to: encoder)
        case .scroll(let scroll): scroll.encode(to: encoder)
        case .collectionCell(let cell): try cell.encode(to: encoder)
        case .reusableView(let reuseIdentifier?): try encoder.encode(reuseIdentifier, forKey: "UIReuseIdentifier")
        case .activity(let activity): try activity.encode(to: encoder)
        case .segmented(let segmented): try segmented.encode(to: encoder)
        case .segment(let segment): try segment.encode(to: encoder)
        case .progress(let progress): try progress.encode(to: encoder)
        case .page(let page): try page.encode(to: encoder)
        case .slider(let slider): try slider.encode(to: encoder)
        case .effect(let effect): try effect.encode(to: encoder)
        case .textField(let field): try field.encode(to: encoder)
        case .switch(let on, let onTint, let thumbTint):
            encoder.encode(.boolean(true), forKey: "UISwitchEnabled")
            if on { encoder.encode(.boolean(true), forKey: "UISwitchOn") }
            if let onTint { try encoder.encode(onTint, forKey: "UISwitchOnTintColor") }
            if let thumbTint { try encoder.encode(thumbTint, forKey: "UISwitchThumbTintColor") }
        case .collection(let collection): try collection.encode(to: encoder)
        case .textView(let textView): try textView.encode(to: encoder)
        case .toolbar(let items, let appearance):
            try appearance.encodeLeading(to: encoder)
            if let tint = appearance.tint { try encoder.encode(tint, forKey: "UIBarTintColor") }
            try encoder.encode(items, forKey: "UIItems")
            try appearance.encodeTrailing(position: 1, to: encoder)
        case .webView(let webView): try webView.encode(to: encoder)
        case .map(let map): try map.encode(to: encoder)
        case .searchBar(let searchBar): try searchBar.encode(to: encoder)
        case .navigationBar(let items, let appearance):
            try appearance.encodeLeading(to: encoder)
            if let tint = appearance.tint { try encoder.encode(tint, forKey: "UIBarTintColor") }
            if !items.elements.isEmpty { try encoder.encode(items, forKey: "UIItems") }
            try appearance.encodeTrailing(position: 2, to: encoder)
        case .datePicker(let picker):
            if picker.alignment != 0 { encoder.encode(.integer(picker.alignment), forKey: "UIContentHorizontalAlignment") }
            if let style = picker.style { encoder.encode(.integer(style), forKey: "UIPickerStyle") }
            if picker.mode != 2 { encoder.encode(.integer(picker.mode), forKey: "UIDatePickerMode") }
            if picker.mode == 3 { encoder.encode(.float(60), forKey: "UICountDownDuration") }
            if picker.minuteInterval != 1 { encoder.encode(.integer(picker.minuteInterval), forKey: "UIMinuteInterval") }
            if !picker.usesCurrentDate { encoder.encode(.boolean(false), forKey: "UIDatePickerUseCurrentDateDuringDecoding") }
        case .pickerView:
            encoder.encode(.boolean(true), forKey: "UIAllowSelectingCells")
        case .refreshControl(let enabled):
            if !enabled { encoder.encode(.boolean(true), forKey: "UIDisabled") }
            encoder.encode(.integer(2), forKey: "UIRefreshControlStyle")
        default: break
        }
        if let customClass {
            try encoder.encode(customClass.name, forKey: "UIClassName")
            try encoder.encode(customClass.original, forKey: "UIOriginalClassName")
        }
    }

    /// Geometry as ibtool writes it: the byte 7, then little-endian doubles.
    static func doubles(_ values: [Double]) -> [UInt8] {
        [7] + values.flatMap { NibArchive.littleEndian($0.bitPattern) }
    }

    /// `UIViewContentMode`, by the names IB writes: top left is `TopLeft`, capitalized, the other
    /// corners `topRight`, `bottomLeft`, `bottomRight`; ibtool takes the other spellings of the
    /// corners as scale to fill (round 108, `*-mode-*`).
    static let contentModes = ["scaleToFill": 0, "scaleAspectFit": 1, "scaleAspectFill": 2, "redraw": 3, "center": 4, "top": 5, "bottom": 6, "left": 7,
                               "right": 8, "TopLeft": 9, "topRight": 10, "bottomLeft": 11, "bottomRight": 12,
                               "topLeft": 0, "TopRight": 0, "BottomLeft": 0, "BottomRight": 0]
    /// `UISemanticContentAttribute`, by the names documents use.
    static let semanticContentAttributes = ["unspecified", "playback", "spatial", "forceLeftToRight", "forceRightToLeft"]
    /// `UIViewAutoresizing` bits, by the names documents use.
    static let autoresizingBits = ["flexibleMinX": 1, "widthSizable": 2, "flexibleMaxX": 4, "flexibleMinY": 8, "heightSizable": 16,
                                   "flexibleMaxY": 32]
    /// The mask a view without an `autoresizingMask` element gets, and one that does not
    /// translate its mask into constraints (`view-no-mask`, `view-translates-no`).
    static let defaultAutoresizingMask = 36
    /// The frame of a view without one (`view-no-rect`, `image-view-no-rect`).
    static let frameWithoutRect = (x: 0.0, y: 0.0, width: 1000.0, height: 1000.0)
}

/// `UIImageNibPlaceholder`: an image view's image, by its name only; the size its `<image>`
/// resource gives changes nothing (nib-experiments `image-view-size-*`, the corpus's 275
/// placeholders), and image views showing one image share it (`image-view-two`).
final class NibImage: NibArchivable {
    let name: NibString
    /// A system image, an SF Symbol: no size, and its name again (`button-image-symbol`).
    let symbol: Bool
    /// A symbol's configuration and variable value from an `<imageReference>` (`bc-symbol-scale*`,
    /// `symbol-view-variable-*`).
    let configuration: NibSymbolConfiguration?
    var variableValue: Double?
    var renderingMode: Int?

    init(name: NibString, symbol: Bool = false, configuration: NibSymbolConfiguration? = nil) {
        self.name = name
        self.symbol = symbol
        self.configuration = configuration
    }

    var className: String { "UIImageNibPlaceholder" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.float(symbol ? 0 : 1), forKey: "UIImageWidth")
        encoder.encode(.float(symbol ? 0 : 1), forKey: "UIImageHeight")
        try encoder.encode(name, forKey: "UIResourceName")
        try encoder.encode(symbol ? name : nil, forKey: "UISystemSymbolResourceName")
        if let renderingMode { encoder.encode(.integer(renderingMode), forKey: "UIRenderingMode") }
        if let variableValue { encoder.encode(.double(variableValue), forKey: "UIImageVariableValue") }
        try encoder.encode(configuration, forKey: "UISymbolImageConfiguration")
        try encoder.encode(nil, forKey: "UIResourceCatalogName")
    }
}
