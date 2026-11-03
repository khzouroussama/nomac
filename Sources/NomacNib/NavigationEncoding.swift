import Foundation

/// A navigation controller's nib object (docs/formats/nib.md "Navigation controllers",
/// nib-experiments `sb-nav*`): its root controller twice, as child and as view controllers, and its
/// bar; a `UIClassSwapper` when it is an entry point, a `UINavigationController` when only segues
/// reach it.
final class NibNavigationController: NibArchivable, NibObjectChildren {
    let root: NibArchivable
    let bar: NibNavigationBar
    let swapsClass: Bool
    let adjustsScrollViewInsets: Bool
    var title: NibArchivable?
    /// Its own identifier, its first key (`sb-nav-identifier`), and its toolbar (`sb-nav-toolbar`).
    var storyboardIdentifier: NibString?
    var toolbar: NibNavigationToolbar?
    /// A tab bar controller's child's tab bar item (`sb-tab-nav-*`), and the tab bar or split view
    /// controller holding it (`sb-split-nav-*`).
    var tabItem: NibTabBarItem?
    weak var container: NibContainerController?
    let controllerClass = NibString("UINavigationController")

    init(root: NibArchivable, bar: NibNavigationBar, swapsClass: Bool, adjustsScrollViewInsets: Bool) {
        self.root = root
        self.bar = bar
        self.swapsClass = swapsClass
        self.adjustsScrollViewInsets = adjustsScrollViewInsets
    }

    var className: String { swapsClass ? "UIClassSwapper" : "UINavigationController" }
    var childObjects: [NibArchivable] { [bar] + (toolbar.map { [$0] } ?? []) + (tabItem?.declared == true ? [tabItem!] : []) + [root] }

    func encode(to encoder: NibEncoder) throws {
        if let storyboardIdentifier { try encoder.encode(storyboardIdentifier, forKey: "UIStoryboardIdentifier") }
        if let tabItem { try encoder.encode(tabItem, forKey: "UITabBarItem") }
        if let container { try encoder.encode(container, forKey: "UIParentViewController") }
        if let title { try encoder.encode(title, forKey: "UITitle") }
        try encoder.encode(NibArray([root], mutable: true), forKey: "UIChildViewControllers")
        if !adjustsScrollViewInsets {
            encoder.encode(.integer(0), forKey: "UIKeyAutomaticallyAdjustsScrollViewInsets")
        }
        try encoder.encode(NibArray([root], mutable: true), forKey: "UIViewControllers")
        try encoder.encode(bar, forKey: "UINavigationBar")
        if let toolbar { try encoder.encode(toolbar, forKey: "UIToolbar") }
        if swapsClass {
            try encoder.encode(controllerClass, forKey: "UIClassName")
            try encoder.encode(controllerClass, forKey: "UIOriginalClassName")
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
    var childObjects: [NibArchivable] { (declaresItem ? [item] : []) + segueTemplates }

    func encode(to encoder: NibEncoder) throws {
        if let title { try encoder.encode(title, forKey: "UITitle") }
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

/// `UINavigationItem`: a declared item's title (with an attributed copy), bar button items and
/// the nib's empty array as center item groups; its large-title mode; its bar, conditionally.
final class NibNavigationItem: NibArchivable, NibObjectChildren {
    var title: NibArchivable?
    var left: NibBarButtonItem?
    var right: NibBarButtonItem?
    /// Its back item, after its attributed title (`sb-bar-back-title`).
    var back: NibBarButtonItem?
    var largeTitleDisplayMode = 0
    var centerItemGroups: NibArray?
    /// Its attributed title's attributes, one empty dictionary for all items of a nib (`sb-tab-nav-two`).
    var titleAttributes = NibDictionary()
    /// Its navigation controller's bar, or the navigation bar among subviews holding it (`nav-bar-sub-*`).
    weak var bar: NibArchivable?

    var className: String { "UINavigationItem" }
    var childObjects: [NibArchivable] { [left, right, back].compactMap { $0 } }

    func encode(to encoder: NibEncoder) throws {
        if let title {
            try encoder.encode(title, forKey: "UITitle")
            try encoder.encode(NibAttributedString(title, attributes: titleAttributes), forKey: "UIAttributedTitle")
        }
        if let back { try encoder.encode(back, forKey: "UIBackBarButtonItem") }
        if let left { try encoder.encode(left, forKey: "UILeftBarButtonItem") }
        if let right { try encoder.encode(right, forKey: "UIRightBarButtonItem") }
        if let left { try encoder.encode(NibArray([left]), forKey: "UILeftBarButtonItems") }
        if let centerItemGroups { try encoder.encode(centerItemGroups, forKey: "UICenterItemGroups") }
        if let right { try encoder.encode(NibArray([right]), forKey: "UIRightBarButtonItems") }
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
    let prefersLargeTitles: Bool
    let hugging: NibString
    /// `multipleTouchEnabled`, `clipsSubviews` and `insetsLayoutMarginsFromSafeArea="NO"`, as a
    /// view's (`sb-nav-bar-flags`, `sb-nav-bar-insets-no`); `opaque` changes nothing.
    var multipleTouchEnabled = false
    var clipsToBounds = false
    var insetsLayoutMarginsFromSafeArea = true
    var items: [NibNavigationItem] = []
    weak var delegate: NibNavigationController?

    init(center: (x: Double, y: Double), prefersLargeTitles: Bool, hugging: NibString) {
        self.center = center
        self.prefersLargeTitles = prefersLargeTitles
        self.hugging = hugging
    }

    var className: String { "UINavigationBar" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.data(NibView.doubles([0, 0, 0, 54])), forKey: "UIBounds")
        encoder.encode(.data(NibView.doubles([center.x, center.y])), forKey: "UICenter")
        encoder.encode(.boolean(true), forKey: "UIDeepDrawRect")
        if multipleTouchEnabled { encoder.encode(.boolean(true), forKey: "UIMultipleTouchEnabled") }
        encoder.encode(.boolean(true), forKey: "UIAutoresizeSubviews")
        encoder.encode(.integer(2), forKey: "UIAutoresizingMask")
        if clipsToBounds { encoder.encode(.boolean(true), forKey: "UIClipsToBounds") }
        try encoder.encode(hugging, forKey: "UIViewContentHuggingPriority")
        encoder.encode(.data(NibView.doubles([0, 0, 0, 0])), forKey: "UIViewLayoutMargins")
        encoder.encode(.boolean(true), forKey: "UIViewLayoutMarginsAreDirectional")
        if !insetsLayoutMarginsFromSafeArea { encoder.encode(.integer(0), forKey: "UIViewInsetsLayoutMarginsFromSafeArea") }
        encoder.encode(.integer(0), forKey: "UIViewSemanticContentAttribute")
        encoder.encode(.null, forKey: "UIViewLargeContentStoredProperties")
        if prefersLargeTitles {
            encoder.encode(.boolean(true), forKey: "UIBarPrefersLargeTitles")
        }
        encoder.encode(.boolean(true), forKey: "UIIsLocked")
        try encoder.encode(NibArray(items, mutable: true), forKey: "UIItems")
        try encoder.encode(delegate, forKey: "UIDelegate")
        encoder.encode(.integer(2), forKey: "UIBarPosition")
        encoder.encode(.integer(1), forKey: "UIBarTranslucence")
    }
}

/// `UIBarButtonItem` of a system item (`sb-bar-*`): `UIEnabled` unless disabled, the system item's
/// number, style 1.
final class NibBarButtonItem: NibArchivable {
    /// `UIBarButtonSystemItem` of the system items observed.
    /// (`sb-bar-system-*`).
    static let systemItems = ["done": 0, "cancel": 1, "edit": 2, "save": 3, "add": 4, "compose": 7, "reply": 8, "action": 9, "organize": 10,
                              "bookmarks": 11, "search": 12, "refresh": 13, "stop": 14, "camera": 15, "trash": 16, "play": 17]
    let systemItem: Int?
    let enabled: Bool
    /// `UIBarButtonItem.Style`: plain 1, done 2 (`nav-bar-sub-done`).
    var style = 1
    /// A titled item's title, localizable as `<id>.title` (`sb-unwind-bar-item`, `sb-bar-title-lproj`).
    var title: NibArchivable?
    /// A titled item's image, after its title (`sb-bar-image`).
    var image: NibImage?

    init(systemItem: Int?, enabled: Bool) {
        self.systemItem = systemItem
        self.enabled = enabled
    }

    var className: String { "UIBarButtonItem" }

    func encode(to encoder: NibEncoder) throws {
        if enabled {
            encoder.encode(.boolean(true), forKey: "UIEnabled")
        }
        if let systemItem {
            encoder.encode(.boolean(true), forKey: "UIIsSystemItem")
            encoder.encode(.integer(systemItem), forKey: "UISystemItem")
        }
        encoder.encode(.integer(style), forKey: "UIStyle")
        if let title { try encoder.encode(title, forKey: "UITitle") }
        if let image { try encoder.encode(image, forKey: "UIImage") }
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
