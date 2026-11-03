import Foundation

/// An `NSDictionary` or `NSMutableDictionary`: `NSInlinedValue`, then each entry's key and value
/// (nib-experiments `storyboard`, `sb-controller-outlets`, `label-size-bold-*`).
final class NibDictionary: NibArchivable {
    var entries: [(key: NibArchivable, value: NibArchivable)] = []
    var mutable = false

    var className: String { mutable ? "NSMutableDictionary" : "NSDictionary" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.boolean(true), forKey: "NSInlinedValue")
        for entry in entries {
            try encoder.encode(entry.key, forKey: NibEncoder.elementKey)
            try encoder.encode(entry.value, forKey: NibEncoder.elementKey)
        }
    }
}

/// `UIRuntimeOutletConnection`: the outlet's name, its source and its destination.
final class NibOutletConnection: NibArchivable {
    let label: NibString
    let source: NibArchivable
    let destination: NibArchivable

    init(label: NibString, source: NibArchivable, destination: NibArchivable) {
        self.label = label
        self.source = source
        self.destination = destination
    }

    var className: String { "UIRuntimeOutletConnection" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(label, forKey: "UILabel")
        try encoder.encode(source, forKey: "UISource")
        try encoder.encode(destination, forKey: "UIDestination")
    }
}

/// `UIRuntimeOutletCollectionConnection`: an outlet collection's name, source and destinations
/// (`outlet-collection`).
final class NibOutletCollectionConnection: NibArchivable {
    let label: NibString
    let source: NibArchivable
    var destinations: [NibArchivable]
    /// The `collectionClass`, `NSArray` without one, and `appends="YES"`: the destinations add to the
    /// source's collection (`gesture-*`).
    var collectionClass = NibString("NSMutableArray")
    var appends = false

    init(label: NibString, source: NibArchivable, destination: NibArchivable) {
        self.label = label
        self.source = source
        self.destinations = [destination]
    }

    var className: String { "UIRuntimeOutletCollectionConnection" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(label, forKey: "UILabel")
        try encoder.encode(source, forKey: "UISource")
        try encoder.encode(NibArray(destinations, mutable: true), forKey: "UIDestination")
        try encoder.encode(collectionClass, forKey: "runtimeCollectionClassName")
        encoder.encode(.boolean(appends), forKey: "addsContentToExistingCollection")
    }
}

/// `NSLayoutConstraint`, or the `_UILayoutSupportConstraint` (fallback `NSLayoutConstraint`) of a
/// scene's layout guide, which adds a priority. An attribute is `NSLayoutAttribute`; a relation,
/// multiplier, constant, priority or identifier is written only when it is not the default, the
/// constant twice (nib-experiments `storyboard`, `constraint-*`).
final class NibLayoutConstraint: NibArchivable {
    let first: NibArchivable
    let firstAttribute: Int
    let second: (item: NibArchivable, attribute: Int)?
    var relation = 0
    var multiplier = 1.0
    var constant = 0.0
    var priority = 1000
    var archived = true
    var identifier: NibString?
    /// For margin attributes: the plain attributes `NSFirstAttribute` and `NSSecondAttribute` name,
    /// and the margins the legacy `NSConstant` adds (`margin-*`).
    var legacyAttributes: (first: Int?, second: Int?) = (nil, nil)
    var marginOffset = 0.0
    /// `symbolic="YES"`: the standard spacing, `NSSpace`, whatever constant IB wrote alongside
    /// (`constraint-symbolic`, `symbolic-constant*`).
    var symbolicConstant: NibString?
    let supportPriority: Int?

    init(_ first: NibArchivable, _ firstAttribute: Int, _ second: (item: NibArchivable, attribute: Int)? = nil, supportPriority: Int? = nil) {
        self.first = first
        self.firstAttribute = firstAttribute
        self.second = second
        self.supportPriority = supportPriority
    }

    var className: String { supportPriority == nil ? "NSLayoutConstraint" : "_UILayoutSupportConstraint" }
    var fallbackClassNames: [String] { supportPriority == nil ? [] : ["NSLayoutConstraint"] }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(first, forKey: "NSFirstItem")
        encoder.encode(.integer(firstAttribute), forKey: "NSFirstAttributeV2")
        encoder.encode(.integer(legacyAttributes.first ?? firstAttribute), forKey: "NSFirstAttribute")
        if relation != 0 { encoder.encode(.integer(relation), forKey: "NSRelation") }
        if multiplier != 1 { encoder.encode(.double(multiplier), forKey: "NSMultiplier") }
        if let second {
            try encoder.encode(second.item, forKey: "NSSecondItem")
            encoder.encode(.integer(second.attribute), forKey: "NSSecondAttributeV2")
            encoder.encode(.integer(legacyAttributes.second ?? second.attribute), forKey: "NSSecondAttribute")
        }
        if constant != 0 { encoder.encode(.double(constant), forKey: "NSConstantV2") }
        if let symbolicConstant { try encoder.encode(symbolicConstant, forKey: "NSSymbolicConstant") }
        encoder.encode(.boolean(archived), forKey: "NSShouldBeArchived")
        if let priority = supportPriority ?? (priority == 1000 ? nil : priority) {
            encoder.encode(.integer(priority), forKey: "NSPriority")
        }
        if let identifier {
            try encoder.encode(identifier, forKey: "NSLayoutIdentifier")
        }
        if constant + marginOffset != 0 { encoder.encode(.double(constant + marginOffset), forKey: "NSConstant") }
    }

    static let left = 1, right = 2, top = 3, bottom = 4, leading = 5, width = 7, height = 8
}

/// A storyboard scene's view controller, naming the view nib to load: a `UIClassSwapper` with the
/// controller's class when it has a custom class or is an entry point, a `UIViewController` when
/// only segues reach it (nib-experiments `storyboard`, `sb-custom-class*`, `sb-identifier`,
/// `sb-segue-*`).
final class NibViewController: NibArchivable, NibObjectChildren {
    let externalObjects = NibDictionary()
    /// Its view nib's name; none for a controller without a view, which writes no external objects
    /// either (`sb-vc-no-view*`).
    let viewNibName: NibString?
    let storyboardIdentifier: NibString?
    let controllerClass: (name: NibString, original: NibString)
    let segueTemplates: [NibSegueTemplate]
    let swapsClass: Bool
    var navigationItem: NibNavigationItem?
    var definesPresentationContext = false
    var keptAlive: [NibArchivable] = []
    var settings = ControllerSettings()
    /// A table or collection view controller's `clearsSelectionOnViewWillAppear="NO"`, after its
    /// segue templates (`sb-cvc-keeps-selection*`, `sb-tvc-keeps-selection`).
    var keepsSelection = false

    init(viewNibName: String?, storyboardIdentifier: NibString?, className: (name: NibString, original: NibString), swapsClass: Bool = true,
         segueTemplates: [NibSegueTemplate] = []) {
        self.swapsClass = swapsClass
        self.viewNibName = viewNibName.map(NibString.init)
        self.storyboardIdentifier = storyboardIdentifier
        self.controllerClass = className
        self.segueTemplates = segueTemplates
    }

    var className: String { swapsClass ? "UIClassSwapper" : controllerClass.original.value }
    var childObjects: [NibArchivable] { (navigationItem.map { [$0] } ?? []) + segueTemplates }

    func encode(to encoder: NibEncoder) throws {
        try settings.encodeTitle(to: encoder)
        if let navigationItem {
            try encoder.encode(navigationItem, forKey: "UINavigationItem")
        }
        if let viewNibName {
            try encoder.encode(externalObjects, forKey: "UIExternalObjectsTableForViewLoading")
            try encoder.encode(viewNibName, forKey: "UINibName")
        }
        if let storyboardIdentifier {
            try encoder.encode(storyboardIdentifier, forKey: "UIStoryboardIdentifier")
        }
        try settings.encodeRestorationIdentifier(to: encoder)
        if !segueTemplates.isEmpty {
            try encoder.encode(NibArray(segueTemplates), forKey: "UIStoryboardSegueTemplates")
        }
        if keepsSelection { encoder.encode(.boolean(false), forKey: "UIClearsSelectionOnViewWillAppear") }
        if !keptAlive.isEmpty { try encoder.encode(NibArray(keptAlive), forKey: "UITopLevelObjectsToKeepAliveFromStoryboard") }
        if definesPresentationContext { encoder.encode(.boolean(true), forKey: "UIDefinesPresentationContext") }
        settings.encodePresentation(to: encoder)
        if swapsClass {
            try encoder.encode(controllerClass.name, forKey: "UIClassName")
            try encoder.encode(controllerClass.original, forKey: "UIOriginalClassName")
        }
    }
}

/// A segue's template in its source controller's nib (nib-experiments `sb-segue-*`): its identifier,
/// the nib name of its destination's controller, and for a show segue the action that performs it;
/// all objects lists templates after the controller, and each connects to it through a
/// `viewController` outlet, the last template's first.
final class NibSegueTemplate: NibArchivable {
    let kind: DocumentCompiler.Segue.Kind
    let identifier: NibString?
    let destination: NibString?
    /// A show segue's action name, an unwind segue's action.
    let action: NibString?
    let arrowDirections: Int?
    /// A custom segue's class name (`sb-segue-custom*`).
    var segueClass: NibString?

    /// Equal strings of a controller's templates are one object (`sb-segorder-*`).
    init(kind: DocumentCompiler.Segue.Kind, identifier: NibString?, destination: NibString?, action: NibString?, arrowDirections: Int? = nil) {
        self.kind = kind
        self.identifier = identifier
        self.destination = destination
        self.action = action
        self.arrowDirections = arrowDirections
    }

    var className: String {
        switch kind {
        case .show, .showDetail: "UIStoryboardShowSegueTemplate"
        case .presentation: "UIStoryboardPresentationSegueTemplate"
        case .popoverPresentation: "UIStoryboardPopoverPresentationSegueTemplate"
        case .unwind: "UIStoryboardUnwindSegueTemplate"
        case .embed: "UIStoryboardEmbedSegueTemplate"
        case .push: "UIStoryboardPushSegueTemplate"
        case .modal: "UIStoryboardModalSegueTemplate"
        case .custom: "UIStoryboardSegueTemplate"
        }
    }

    /// A push template's containment context and split view controller index are 0, a custom one
    /// names its class before its destination (`sb-segue-push`, `sb-segue-custom*`). An embed template performs on its view's load, its container view nil, the view nib's
    /// `containerView` outlet (`sb-embed*`). An unwind template's destination is nil and its action `UIAction`; a popover's arrow
    /// directions, passthrough views and anchors follow, the anchors nil, an anchor view being an
    /// outlet of the view nib (`sb-unwind-*`, `sb-popover-*`).
    func encode(to encoder: NibEncoder) throws {
        if let identifier { try encoder.encode(identifier, forKey: "UIIdentifier") }
        if let segueClass { try encoder.encode(segueClass, forKey: "UISegueClassName") }
        try encoder.encode(destination, forKey: "UIDestinationViewControllerIdentifier")
        if kind == .push {
            encoder.encode(.integer(0), forKey: "UIDestinationContainmentContext")
            encoder.encode(.integer(0), forKey: "UISplitViewControllerIndex")
        }
        if let action { try encoder.encode(action, forKey: kind == .unwind ? "UIAction" : "UIActionName") }
        if kind == .embed {
            encoder.encode(.boolean(true), forKey: "UIPerformOnViewLoad")
            encoder.encode(.null, forKey: "UIContainerView")
        }
        if let arrowDirections {
            encoder.encode(.integer(arrowDirections), forKey: "UIPermittedArrowDirections")
            encoder.encode(.null, forKey: "UIPassthroughViews")
            encoder.encode(.null, forKey: "UIAnchorBarButtonItem")
            encoder.encode(.null, forKey: "UIAnchorView")
        }
    }
}

/// The safe area `UILayoutGuide` IB keeps for a view, which no object refers to and only all objects
/// lists, right after the view (nib-experiments `sb-safe-area`, `safe-area`, scene-pairs `v-many`).
final class NibSafeAreaGuide: NibArchivable {
    /// An empty string, the document's (`corpus` SettingsHeaderView: a label's empty text).
    let identifier: NibString

    init(identifier: NibString) {
        self.identifier = identifier
    }

    var className: String { "UILayoutGuide" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(nil, forKey: "UILayoutGuideOwningView")
        try encoder.encode(identifier, forKey: "UILayoutGuideIdentifier")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideOwningViewIsLocked")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideShouldBeArchived")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideAllowsNegativeDimensions")
    }
}

/// A view's safe area `UILayoutGuide` when a constraint refers to it, which the view lists in
/// `UIViewLayoutGuides`: owned by the view, with system constraints that pin its top, left,
/// bottom and right to the view's, not archived and named (nib-experiments
/// `constraint-to-safe-area`, the corpus's nextcloud launch screen).
final class NibViewLayoutGuide: NibArchivable {
    unowned let owningView: NibView
    /// The guide's identifier and its system constraints' (top, left, bottom, right), strings every
    /// safe area guide of a nib shares (the corpus's pocket-casts MiniPlayerViewController).
    let identifier: NibString
    let constraintIdentifiers: [NibString]

    init(owningView: NibView, identifier: NibString, constraintIdentifiers: [NibString]) {
        self.owningView = owningView
        self.identifier = identifier
        self.constraintIdentifiers = constraintIdentifiers
    }

    var className: String { "UILayoutGuide" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(owningView, forKey: "UILayoutGuideOwningView")
        try encoder.encode(identifier, forKey: "UILayoutGuideIdentifier")
        encoder.encode(.boolean(true), forKey: "UILayoutGuideOwningViewIsLocked")
        encoder.encode(.boolean(true), forKey: "UILayoutGuideShouldBeArchived")
        encoder.encode(.boolean(true), forKey: "UILayoutGuideAllowsNegativeDimensions")
        func system(_ first: NibArchivable, _ second: NibArchivable, _ attribute: Int, _ identifier: NibString) -> NibLayoutConstraint {
            let constraint = NibLayoutConstraint(first, attribute, (second, attribute))
            constraint.archived = false
            constraint.identifier = identifier
            return constraint
        }
        let constraints = [system(self, owningView, NibLayoutConstraint.top, constraintIdentifiers[0]),
                           system(self, owningView, NibLayoutConstraint.left, constraintIdentifiers[1]),
                           system(owningView, self, NibLayoutConstraint.bottom, constraintIdentifiers[2]),
                           system(owningView, self, NibLayoutConstraint.right, constraintIdentifiers[3])]
        try encoder.encode(NibArray(constraints), forKey: "UILayoutGuideSystemConstraints")
    }
}

/// A scroll view's `contentLayoutGuide` (`_UIScrollViewLayoutGuide`) or `frameLayoutGuide`
/// (`UILayoutGuide`), named by constraints (nib-experiments `scroll-content-guides-pinned`,
/// `scroll-guides-*`): its scroll view, its identifier, locked, not archived, and unarchived system
/// constraints of its left and top to the scroll view's, the frame guide's width and height too.
final class NibScrollLayoutGuide: NibArchivable {
    unowned let owningView: NibView
    let content: Bool
    let identifier: NibString
    let constraintIdentifiers: [NibString]

    init(owningView: NibView, content: Bool, identifier: NibString, constraintIdentifiers: [NibString]) {
        self.owningView = owningView
        self.content = content
        self.identifier = identifier
        self.constraintIdentifiers = constraintIdentifiers
    }

    var className: String { content ? "_UIScrollViewLayoutGuide" : "UILayoutGuide" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(owningView, forKey: "UILayoutGuideOwningView")
        try encoder.encode(identifier, forKey: "UILayoutGuideIdentifier")
        encoder.encode(.boolean(true), forKey: "UILayoutGuideOwningViewIsLocked")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideShouldBeArchived")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideAllowsNegativeDimensions")
        let attributes = [NibLayoutConstraint.left, NibLayoutConstraint.top, NibLayoutConstraint.width, NibLayoutConstraint.height]
        let constraints = zip(attributes, constraintIdentifiers).map { attribute, identifier in
            let constraint = NibLayoutConstraint(self, attribute, (owningView, attribute))
            constraint.archived = false
            constraint.identifier = identifier
            return constraint
        }
        try encoder.encode(NibArray(constraints), forKey: "UILayoutGuideSystemConstraints")
    }
}

extension NibView {
    /// The top and bottom layout guides ibtool adds to a scene's view, declared or not, and their
    /// constraints, which the view also lists (`storyboard`, `sb-layout-guides`): each guide is a
    /// hidden view with a width support constraint of priority 999; the top one's leading and top
    /// meet the view's and it has a height, the bottom one's leading meets the view's, it has a
    /// height, and the view's bottom meets its bottom.
    static func viewControllerLayoutGuides(for view: NibView) -> [NibView] {
        var flags = Flags()
        flags.hidden = true
        flags.doesNotTranslateAutoresizingMask = true
        func guide(_ identifier: String, _ constraints: (NibView) -> [NibLayoutConstraint]) -> NibView {
            let guide = NibView(frame: nil, autoresizingMask: 0, flags: flags, subviews: [], backgroundColor: nil, customClass: nil)
            guide.guideConstraints = [NibLayoutConstraint(guide, NibLayoutConstraint.width, supportPriority: 999)]
            guide.layoutGuide = LayoutGuide(identifier: NibString(identifier), constraintsToRemove: constraints(guide))
            return guide
        }
        let top = guide("_UIViewControllerTop") { guide in
            [NibLayoutConstraint(guide, NibLayoutConstraint.leading, (view, NibLayoutConstraint.leading)),
             NibLayoutConstraint(guide, NibLayoutConstraint.top, (view, NibLayoutConstraint.top)),
             NibLayoutConstraint(guide, NibLayoutConstraint.height)]
        }
        let bottom = guide("_UIViewControllerBottom") { guide in
            [NibLayoutConstraint(guide, NibLayoutConstraint.leading, (view, NibLayoutConstraint.leading)),
             NibLayoutConstraint(guide, NibLayoutConstraint.height),
             NibLayoutConstraint(view, NibLayoutConstraint.bottom, (guide, NibLayoutConstraint.bottom))]
        }
        return [top, bottom]
    }
}
