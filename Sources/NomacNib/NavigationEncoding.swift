import Foundation

/// A navigation controller's nib object (docs/formats/nib.md "Navigation controllers",
/// nib-experiments `sb-nav*`): its root controller twice, as child and as view controllers, and its
/// bar; a `UIClassSwapper` when it is an entry point, a `UINavigationController` when only segues
/// reach it.
final class NibNavigationController: NibArchivable, NibObjectChildren {
    /// Its root, none in a navigation controller without one (`sb-shape-nav-no-root`).
    let root: NibArchivable?
    let bar: NibNavigationBar
    let swapsClass: Bool
    let className_: (name: NibString, original: NibString)
    /// Its title, restoration identifier and presentation (`sb-navattr-*`).
    var settings = ControllerSettings()
    var definesPresentationContext = false
    var barHidden = false
    var toolbarShown = false
    var condensesBarsWhenKeyboardAppears = false
    /// Its own identifier (`sb-nav-identifier`), and its toolbar (`sb-nav-toolbar`).
    var storyboardIdentifier: NibString?
    var toolbar: NibNavigationToolbar?
    /// Its tab bar item, a tab bar controller's child's (`sb-tab-nav-*`) or its own (`sb-navattr-tab-item`),
    /// and the tab bar or split view controller holding it (`sb-split-nav-*`).
    var tabItem: NibTabBarItem?
    weak var container: NibContainerController?
    /// Its own segues' templates, after its children (`sb-shape-nav-show*`).
    var segueTemplates: [NibSegueTemplate] = []

    init(root: NibArchivable?, bar: NibNavigationBar, swapsClass: Bool, className: (name: NibString, original: NibString)) {
        self.root = root
        self.bar = bar
        self.swapsClass = swapsClass
        self.className_ = className
    }

    var className: String { swapsClass ? "UIClassSwapper" : "UINavigationController" }
    var childObjects: [NibArchivable] { [bar] + (toolbar.map { [$0] } ?? []) + (tabItem?.declared == true ? [tabItem!] : []) + segueTemplates + [root].compactMap { $0 } }

    func encode(to encoder: NibEncoder) throws {
        try settings.encodeTitle(to: encoder)
        if let tabItem { try encoder.encode(tabItem, forKey: "UITabBarItem") }
        if let storyboardIdentifier { try encoder.encode(storyboardIdentifier, forKey: "UIStoryboardIdentifier") }
        try settings.encodeRestorationIdentifier(to: encoder)
        if let container { try encoder.encode(container, forKey: "UIParentViewController") }
        if let root { try encoder.encode(NibArray([root], mutable: true), forKey: "UIChildViewControllers") }
        if !segueTemplates.isEmpty { try encoder.encode(NibArray(segueTemplates), forKey: "UIStoryboardSegueTemplates") }
        if definesPresentationContext { encoder.encode(.boolean(true), forKey: "UIDefinesPresentationContext") }
        settings.encodePresentation(to: encoder)
        if let root { try encoder.encode(NibArray([root], mutable: true), forKey: "UIViewControllers") }
        try encoder.encode(bar, forKey: "UINavigationBar")
        if let toolbar { try encoder.encode(toolbar, forKey: "UIToolbar") }
        if barHidden { encoder.encode(.boolean(true), forKey: "UINavigationBarHidden") }
        if toolbarShown { encoder.encode(.boolean(true), forKey: "UIToolbarShown") }
        if condensesBarsWhenKeyboardAppears { encoder.encode(.boolean(true), forKey: "UINavigationControllerCondensesBarsWhenKeyboardAppears") }
        if swapsClass {
            try encoder.encode(className_.name, forKey: "UIClassName")
            try encoder.encode(className_.original, forKey: "UIOriginalClassName")
        }
    }
}

/// A navigation controller's root view controller, archived in the navigation controller's nib: a
/// `UIViewController` or `UITableViewController` (a `UIClassSwapper` of a custom class) with its
/// navigation item, the view nib to load (its outlets through `UpstreamPlaceholder-1`), its parent,
/// its segues' templates, the views of its scene it keeps alive, whether it defines the presentation
/// context and its class names (`sb-tvc-in-nav*`, `sb-nav-root-*`).
final class NibRootViewController: NibArchivable, NibObjectChildren {
    let item: NibNavigationItem
    let externalObjects: NibDictionary
    let viewNibName: NibString
    weak var parent: NibNavigationController?
    let segueTemplates: [NibSegueTemplate]
    let baseClass: String
    let customClass: (name: NibString, original: NibString)?
    var definesPresentationContext = false
    /// A root with its own identifier is a class swapper writing it after its nib's name
    /// (`sb-nav-root-identifier`).
    var storyboardIdentifier: NibString?
    /// Its title, its first key, and whether it keeps its selection, after its templates
    /// (`sb-nav-root-title`, `sb-nav-root-tvc-keeps-selection`, `sb-split-template*`).
    var title: NibArchivable?
    var keepsSelection = false
    /// Its presentation settings, after its templates (`sb-nav-root-modal`).
    var settings = ControllerSettings()
    var keptAlive: [NibView] = []
    /// Whether the controller declares its navigation item, which all objects then lists.
    var declaresItem = false
    /// A tab bar item of its own, before its navigation item (`sb-vcattr-root-tab-item*`).
    var tabItem: NibTabBarItem?

    init(item: NibNavigationItem, viewNibName: String, segueTemplates: [NibSegueTemplate], baseClass: String,
         customClass: (name: NibString, original: NibString)?, externalObjects: NibDictionary = NibDictionary()) {
        self.item = item
        self.externalObjects = externalObjects
        self.viewNibName = NibString(viewNibName)
        self.segueTemplates = segueTemplates
        self.baseClass = baseClass
        self.customClass = customClass
    }

    var className: String { customClass != nil ? "UIClassSwapper" : baseClass }
    var childObjects: [NibArchivable] { (declaresItem ? [item] : []) + (tabItem.map { [$0] } ?? []) + segueTemplates }

    func encode(to encoder: NibEncoder) throws {
        if let title { try encoder.encode(title, forKey: "UITitle") }
        if let tabItem { try encoder.encode(tabItem, forKey: "UITabBarItem") }
        try encoder.encode(item, forKey: "UINavigationItem")
        try encoder.encode(externalObjects, forKey: "UIExternalObjectsTableForViewLoading")
        try encoder.encode(viewNibName, forKey: "UINibName")
        if let storyboardIdentifier { try encoder.encode(storyboardIdentifier, forKey: "UIStoryboardIdentifier") }
        try encoder.encode(parent, forKey: "UIParentViewController")
        if !segueTemplates.isEmpty {
            try encoder.encode(NibArray(segueTemplates), forKey: "UIStoryboardSegueTemplates")
        }
        settings.encodePresentation(to: encoder)
        if keepsSelection { encoder.encode(.boolean(false), forKey: "UIClearsSelectionOnViewWillAppear") }
        if !keptAlive.isEmpty { try encoder.encode(NibArray(keptAlive), forKey: "UITopLevelObjectsToKeepAliveFromStoryboard") }
        if definesPresentationContext { encoder.encode(.boolean(true), forKey: "UIDefinesPresentationContext") }
        if let customClass {
            try encoder.encode(customClass.name, forKey: "UIClassName")
            try encoder.encode(customClass.original, forKey: "UIOriginalClassName")
        }
    }
}

/// `UINavigationItem`: a declared item's title (with an attributed copy), prompt, bar button items
/// and the nib's empty array as center item groups; its large-title mode; its bar, conditionally.
/// `UILeftBarButtonItem` and `UIRightBarButtonItem` are the first of its several items
/// (`bars-ni-right-*`, `bars-ni-left-two`, `bars-ni-both-two`, `bars-ni-order`).
final class NibNavigationItem: NibArchivable, NibObjectChildren {
    var title: NibArchivable?
    var prompt: NibArchivable?
    var leftItemsSupplementBackButton = false
    var leftItems: [NibBarButtonItem] = []
    var rightItems: [NibBarButtonItem] = []
    /// Its back item, after its attributed title (`sb-bar-back-title`, `bars-ni-back-*`).
    var back: NibBarButtonItem?
    var largeTitleDisplayMode = 0
    var centerItemGroups: NibArray?
    /// Its attributed title's attributes, one empty dictionary for all items of a nib (`sb-tab-nav-two`).
    var titleAttributes = NibDictionary()
    /// Its navigation controller's bar, or the navigation bar among subviews holding it (`nav-bar-sub-*`).
    weak var bar: NibArchivable?

    var left: NibBarButtonItem? { leftItems.first }
    var right: NibBarButtonItem? { rightItems.first }
    var className: String { "UINavigationItem" }
    var childObjects: [NibArchivable] { leftItems + rightItems + (back.map { [$0] } ?? []) }

    func encode(to encoder: NibEncoder) throws {
        if let title {
            try encoder.encode(title, forKey: "UITitle")
            try encoder.encode(NibAttributedString(title, attributes: titleAttributes), forKey: "UIAttributedTitle")
        }
        if let prompt { try encoder.encode(prompt, forKey: "UIPrompt") }
        if leftItemsSupplementBackButton { encoder.encode(.boolean(true), forKey: "UILeftItemsSupplementBackButton") }
        if let back { try encoder.encode(back, forKey: "UIBackBarButtonItem") }
        if let left { try encoder.encode(left, forKey: "UILeftBarButtonItem") }
        if let right { try encoder.encode(right, forKey: "UIRightBarButtonItem") }
        if !leftItems.isEmpty { try encoder.encode(NibArray(leftItems), forKey: "UILeftBarButtonItems") }
        if let centerItemGroups { try encoder.encode(centerItemGroups, forKey: "UICenterItemGroups") }
        if !rightItems.isEmpty { try encoder.encode(NibArray(rightItems), forKey: "UIRightBarButtonItems") }
        encoder.encode(.integer(largeTitleDisplayMode), forKey: "UILargeTitleDisplayMode")
        if let bar { encoder.encodeConditional(bar, forKey: "UINavigationBar") }
    }
}

/// `NSAttributedString` of a string without attributes.
final class NibAttributedString: NibArchivable {
    let string: NibArchivable
    let attributes: NibDictionary

    init(_ string: NibArchivable, attributes: NibDictionary) {
        self.string = string
        self.attributes = attributes
    }

    var className: String { "NSAttributedString" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(string, forKey: "NSString")
        try encoder.encode(attributes, forKey: "NSAttributes")
    }
}

/// `UINavigationBar`, which IB lays out itself: 0 x 54 whatever the device, centered at its
/// document frame's origin plus 27 points down (`sb-nav-bar-*`).
final class NibNavigationBar: NibArchivable {
    let center: (x: Double, y: Double)
    let hugging: NibString
    /// `multipleTouchEnabled`, `clipsSubviews` and `insetsLayoutMarginsFromSafeArea="NO"`, as a
    /// view's (`sb-nav-bar-flags`, `sb-nav-bar-insets-no`); `opaque` changes nothing.
    var multipleTouchEnabled = false
    var clipsToBounds = false
    var insetsLayoutMarginsFromSafeArea = true
    var tintColor: NibArchivable?
    var items: [NibNavigationItem] = []
    weak var delegate: NibNavigationController?
    /// `clearsContextBeforeDrawing="NO"`, after its autoresizing mask (`bars-sbn-clears`).
    var clearsContextBeforeDrawing = true
    /// A view's key (`sb-nav-bar-background`).
    var backgroundColor: NibArchivable?
    /// Its style, tint, title attributes and translucence, with `UIOpaque` when `translucent="NO"` (`bars-sbn-*`).
    var appearance = BarAppearance()
    /// A custom class's names, last (`bars-sbn-class*`).
    var customClass: (name: NibString, original: NibString)?

    init(center: (x: Double, y: Double), hugging: NibString) {
        self.center = center
        self.hugging = hugging
    }

    var className: String { customClass == nil ? "UINavigationBar" : "UIClassSwapper" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.data(NibView.doubles([0, 0, 0, 54])), forKey: "UIBounds")
        encoder.encode(.data(NibView.doubles([center.x, center.y])), forKey: "UICenter")
        if let backgroundColor { try encoder.encode(backgroundColor, forKey: "UIBackgroundColor") }
        encoder.encode(.boolean(true), forKey: "UIDeepDrawRect")
        if !appearance.translucent { encoder.encode(.boolean(true), forKey: "UIOpaque") }
        if multipleTouchEnabled { encoder.encode(.boolean(true), forKey: "UIMultipleTouchEnabled") }
        encoder.encode(.boolean(true), forKey: "UIAutoresizeSubviews")
        encoder.encode(.integer(2), forKey: "UIAutoresizingMask")
        if !clearsContextBeforeDrawing { encoder.encode(.boolean(false), forKey: "UIClearsContextBeforeDrawing") }
        if clipsToBounds { encoder.encode(.boolean(true), forKey: "UIClipsToBounds") }
        if let tintColor { try encoder.encode(tintColor, forKey: "UITintColor") }
        try encoder.encode(hugging, forKey: "UIViewContentHuggingPriority")
        encoder.encode(.data(NibView.doubles([0, 0, 0, 0])), forKey: "UIViewLayoutMargins")
        encoder.encode(.boolean(true), forKey: "UIViewLayoutMarginsAreDirectional")
        if !insetsLayoutMarginsFromSafeArea { encoder.encode(.integer(0), forKey: "UIViewInsetsLayoutMarginsFromSafeArea") }
        encoder.encode(.integer(0), forKey: "UIViewSemanticContentAttribute")
        encoder.encode(.null, forKey: "UIViewLargeContentStoredProperties")
        try appearance.encodeLeading(to: encoder)
        encoder.encode(.boolean(true), forKey: "UIIsLocked")
        if let tint = appearance.tint { try encoder.encode(tint, forKey: "UIBarTintColor") }
        // A navigation controller without a root has no items (`sb-shape-nav-no-root`).
        if !items.isEmpty { try encoder.encode(NibArray(items, mutable: true), forKey: "UIItems") }
        try encoder.encode(delegate, forKey: "UIDelegate")
        try appearance.encodeTrailing(position: 2, to: encoder)
        if let customClass {
            try encoder.encode(customClass.name, forKey: "UIClassName")
            try encoder.encode(customClass.original, forKey: "UIOriginalClassName")
        }
    }
}

/// `UIBarButtonItem` (`sb-bar-*`, `bars-tb-*`, `bars-ni-*`): `UIEnabled` unless disabled, a system
/// item's number, its style, the spaces' hidden shared background, its tag, title, image, width and
/// tint; a `UIClassSwapper` of a custom class.
final class NibBarButtonItem: NibArchivable {
    /// `UIBarButtonSystemItem` of the system items observed; `close` writes 0 (`sb-bar-system-*`,
    /// `bars-tb-sys-*`).
    static let systemItems = ["done": 0, "close": 0, "cancel": 1, "edit": 2, "save": 3, "add": 4, "flexibleSpace": 5, "fixedSpace": 6, "compose": 7, "reply": 8,
                              "action": 9, "organize": 10, "bookmarks": 11, "search": 12, "refresh": 13, "stop": 14, "camera": 15, "trash": 16, "play": 17,
                              "pause": 18, "rewind": 19, "fastForward": 20, "undo": 21, "redo": 22, "pageCurl": 23]
    /// The spaces write `UIHidesSharedBG` (`bars-tb-flex`, `bars-tb-fixed-width`).
    private static let spaces: Set = [5, 6]
    let systemItem: Int?
    let enabled: Bool
    /// `UIStyle`: 1 without a style, 2 for `done`; `style="plain"` writes none (`bars-tb-title-plain`,
    /// `bars-ni-plain-*`).
    var style: Int? = 1
    var tag: Int?
    /// A titled item's title, localizable as `<id>.title` (`sb-unwind-bar-item`, `sb-bar-title-lproj`).
    var title: NibArchivable?
    /// Its image, after its title and width (`sb-bar-image`, `bars-tb-image*`, `bars-tb-combo`).
    var image: NibImage?
    /// A flexible space writes no width (`bars-tb-flex-width`).
    var width: Double?
    var tintColor: NibArchivable?
    var customClass: (name: NibString, original: NibString)?

    init(systemItem: Int?, enabled: Bool) {
        self.systemItem = systemItem
        self.enabled = enabled
    }

    var className: String { customClass == nil ? "UIBarButtonItem" : "UIClassSwapper" }

    func encode(to encoder: NibEncoder) throws {
        if enabled {
            encoder.encode(.boolean(true), forKey: "UIEnabled")
        }
        if let systemItem {
            encoder.encode(.boolean(true), forKey: "UIIsSystemItem")
            encoder.encode(.integer(systemItem), forKey: "UISystemItem")
        }
        if let style { encoder.encode(.integer(style), forKey: "UIStyle") }
        if let tag { encoder.encode(.integer(tag), forKey: "UITag") }
        if let systemItem, Self.spaces.contains(systemItem) { encoder.encode(.boolean(true), forKey: "UIHidesSharedBG") }
        if let title { try encoder.encode(title, forKey: "UITitle") }
        if let width { encoder.encode(.float(Float(width)), forKey: "UIWidth") }
        if let image { try encoder.encode(image, forKey: "UIImage") }
        if let tintColor { try encoder.encode(tintColor, forKey: "UITintColor") }
        if let customClass {
            try encoder.encode(customClass.name, forKey: "UIClassName")
            try encoder.encode(customClass.original, forKey: "UIOriginalClassName")
        }
    }
}

/// `UIRuntimeEventConnection`: an action, its selector, sender and target, and for a control's
/// action the events that send it (`ev-*`).
final class NibEventConnection: NibArchivable {
    let selector: NibString
    let source: NibArchivable
    let destination: NibArchivable
    let eventMask: Int?

    init(selector: NibString, source: NibArchivable, destination: NibArchivable, eventMask: Int? = nil) {
        self.selector = selector
        self.source = source
        self.destination = destination
        self.eventMask = eventMask
    }

    var className: String { "UIRuntimeEventConnection" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(selector, forKey: "UILabel")
        try encoder.encode(source, forKey: "UISource")
        try encoder.encode(destination, forKey: "UIDestination")
        if let eventMask { encoder.encode(.integer(eventMask), forKey: "UIEventMask") }
    }
}

/// A navigation controller's `UIToolbar`, IB's own without a frame (`sb-nav-toolbar`).
final class NibNavigationToolbar: NibArchivable {
    let hugging: NibString
    let items: NibArray

    init(hugging: NibString, items: NibArray) {
        self.hugging = hugging
        self.items = items
    }

    var className: String { "UIToolbar" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.data(NibView.doubles([0, 0, 1000, 54])), forKey: "UIBounds")
        encoder.encode(.data(NibView.doubles([500, 27])), forKey: "UICenter")
        encoder.encode(.boolean(true), forKey: "UIDeepDrawRect")
        encoder.encode(.boolean(true), forKey: "UIAutoresizeSubviews")
        encoder.encode(.integer(10), forKey: "UIAutoresizingMask")
        encoder.encode(.boolean(false), forKey: "UIClearsContextBeforeDrawing")
        try encoder.encode(hugging, forKey: "UIViewContentHuggingPriority")
        encoder.encode(.integer(0), forKey: "UIViewSemanticContentAttribute")
        encoder.encode(.null, forKey: "UIViewLargeContentStoredProperties")
        try encoder.encode(items, forKey: "UIItems")
        encoder.encode(.integer(1), forKey: "UIBarPosition")
        encoder.encode(.integer(1), forKey: "UIBarTranslucence")
    }
}
