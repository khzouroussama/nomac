import Foundation

/// `UITabBarController` or `UISplitViewController` of a storyboard's `<tabBarController>` or
/// `<splitViewController>` (docs/formats/nib.md "Tab bar and split view controllers";
/// nib-experiments `sb-tab-*`, `sb-split-*`). A tab bar controller writes its storyboard
/// identifier, its children, its tab bar, its children again as customizable and as its view
/// controllers; a split view controller its title, its storyboard identifier, its master and
/// detail and its primary edge, and all objects lists its children last first.
final class NibContainerController: NibArchivable, NibObjectChildren {
    enum Kind {
        case tabBar(NibTabBar)
        case split
    }

    let kind: Kind
    var title: NibArchivable?
    var children: [NibArchivable] = []
    let storyboardIdentifier: NibString?
    let swapsClass: Bool
    let className_: (name: NibString, original: NibString)

    init(kind: Kind, storyboardIdentifier: NibString?, swapsClass: Bool, className: (name: NibString, original: NibString)) {
        self.kind = kind
        self.storyboardIdentifier = storyboardIdentifier
        self.swapsClass = swapsClass
        self.className_ = className
    }

    var className: String {
        guard !swapsClass else { return "UIClassSwapper" }
        if case .tabBar = kind { return "UITabBarController" }
        return "UISplitViewController"
    }

    var childObjects: [NibArchivable] {
        switch kind {
        case .tabBar(let bar): [bar] + children
        case .split: children.reversed()
        }
    }

    func encode(to encoder: NibEncoder) throws {
        if let title { try encoder.encode(title, forKey: "UITitle") }
        if let storyboardIdentifier { try encoder.encode(storyboardIdentifier, forKey: "UIStoryboardIdentifier") }
        try encoder.encode(NibArray(children, mutable: true), forKey: "UIChildViewControllers")
        switch kind {
        case .tabBar(let bar):
            try encoder.encode(bar, forKey: "UITabBar")
            try encoder.encode(NibArray(children, mutable: true), forKey: "UICustomizableViewControllers")
            try encoder.encode(NibArray(children, mutable: true), forKey: "UIViewControllers")
        case .split:
            encoder.encode(.integer(0), forKey: "UISplitViewControllerPrimaryEdge")
        }
        if swapsClass {
            try encoder.encode(className_.name, forKey: "UIClassName")
            try encoder.encode(className_.original, forKey: "UIOriginalClassName")
        }
    }
}

/// A container's view controller child: its title, a tab bar controller's child's tab bar item, the
/// empty external objects all children share, its view nib's name, its parent and its segues'
/// templates (`sb-tab-plain`, `sb-tab-child-title`, `sb-split-plain`, `sb-tab-child-show`). A
/// declared item is among the nib's objects before the templates, IB's default one is not
/// (`sb-tab-items`, `sb-tab-child-show-item`).
final class NibContainerChildViewController: NibArchivable, NibObjectChildren {
    let title: NibString?
    let item: NibTabBarItem?
    let externalObjects: NibDictionary
    let viewNibName: NibString
    let segueTemplates: [NibSegueTemplate]
    let customClass: (name: NibString, original: NibString)?
    weak var parent: NibContainerController?
    /// Its presentation settings, after its templates (`sb-split-detail-modal`).
    var settings = ControllerSettings()

    init(title: NibString?, item: NibTabBarItem?, externalObjects: NibDictionary, viewNibName: NibString, segueTemplates: [NibSegueTemplate],
         customClass: (name: NibString, original: NibString)?, parent: NibContainerController) {
        self.title = title
        self.item = item
        self.externalObjects = externalObjects
        self.viewNibName = viewNibName
        self.segueTemplates = segueTemplates
        self.customClass = customClass
        self.parent = parent
    }

    var className: String { customClass != nil ? "UIClassSwapper" : "UIViewController" }
    var childObjects: [NibArchivable] { (item?.declared == true ? [item!] : []) + segueTemplates }

    func encode(to encoder: NibEncoder) throws {
        if let title { try encoder.encode(title, forKey: "UITitle") }
        if let item { try encoder.encode(item, forKey: "UITabBarItem") }
        try encoder.encode(externalObjects, forKey: "UIExternalObjectsTableForViewLoading")
        try encoder.encode(viewNibName, forKey: "UINibName")
        try encoder.encode(parent, forKey: "UIParentViewController")
        if !segueTemplates.isEmpty { try encoder.encode(NibArray(segueTemplates), forKey: "UIStoryboardSegueTemplates") }
        settings.encodePresentation(to: encoder)
        if let customClass {
            try encoder.encode(customClass.name, forKey: "UIClassName")
            try encoder.encode(customClass.original, forKey: "UIOriginalClassName")
        }
    }
}

/// `UITabBarItem`: a declared item's title and image; a child without one gets IB's spring-loaded
/// item, titled with its controller's title (`sb-tab-items`, `sb-tab-item-*`, `sb-tab-plain`,
/// `sb-tab-child-title`).
final class NibTabBarItem: NibArchivable {
    let declared: Bool
    var title: NibString?
    var image: NibImage?

    init(declared: Bool) {
        self.declared = declared
    }

    var className: String { "UITabBarItem" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.boolean(true), forKey: "UIEnabled")
        if let title { try encoder.encode(title, forKey: "UITitle") }
        if !declared { encoder.encode(.boolean(true), forKey: "UISpringLoaded") }
        if let image { try encoder.encode(image, forKey: "UIImage") }
    }
}

/// `UITabBar`, which IB lays out itself: 0 x 54, centered 27 points below its document frame's
/// origin, with its background color, its controller as delegate and its children's items
/// (`sb-tab-*`, `sb-tab-bar-background`).
final class NibTabBar: NibArchivable {
    let center: (x: Double, y: Double)
    let backgroundColor: NibColor?
    let hugging: NibString
    var items: [NibTabBarItem] = []
    weak var delegate: NibContainerController?

    init(center: (x: Double, y: Double), backgroundColor: NibColor?, hugging: NibString) {
        self.center = center
        self.backgroundColor = backgroundColor
        self.hugging = hugging
    }

    var className: String { "UITabBar" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.data(NibView.doubles([0, 0, 0, 54])), forKey: "UIBounds")
        encoder.encode(.data(NibView.doubles([center.x, center.y])), forKey: "UICenter")
        if let backgroundColor { try encoder.encode(backgroundColor, forKey: "UIBackgroundColor") }
        encoder.encode(.boolean(true), forKey: "UIDeepDrawRect")
        encoder.encode(.boolean(true), forKey: "UIOpaque")
        encoder.encode(.boolean(true), forKey: "UIAutoresizeSubviews")
        encoder.encode(.integer(10), forKey: "UIAutoresizingMask")
        try encoder.encode(hugging, forKey: "UIViewContentHuggingPriority")
        encoder.encode(.integer(0), forKey: "UIViewSemanticContentAttribute")
        encoder.encode(.null, forKey: "UIViewLargeContentStoredProperties")
        if let delegate { encoder.encodeConditional(delegate, forKey: "UIDelegate") }
        try encoder.encode(NibArray(items), forKey: "UIItems")
        encoder.encode(.integer(1), forKey: "UIBarTranslucence")
    }
}

/// A tab bar or split view controller's child scene, with its segues' templates, and a navigation
/// controller's root scene.
struct ContainerChild {
    let scene: XIBElement
    let controller: DocumentCompiler.SceneController
    let templates: [NibSegueTemplate]
    let root: (scene: XIBElement, controller: DocumentCompiler.SceneController, templates: [NibSegueTemplate])?
}

extension DocumentCompiler {
    /// A tab bar or split view controller's scene with its children's, view controllers or
    /// navigation controllers with their roots: one nib of the container and its children, each
    /// view controller's view nib apart. Its top-level objects are a storyboard placeholder per
    /// inlined controller, depth first in the relationships' order and reversed, File's Owner, First
    /// Responder, its own placeholder and the container. Each controller's `storyboard` outlet goes
    /// to its placeholder: the container's and navigation controllers' first, then the view
    /// controllers', each depth first (`sb-tab-order`, `sb-tab-nav-two`, `sb-tab-plain-then-nav`,
    /// `sb-split-swapped`, `sb-split-nav-both`); after `sceneViewController`, the view controllers'
    /// segue templates' `viewController` outlets in the same order (`sb-tab-two-show`); navigation
    /// roots' popover anchors before `sceneViewController`, their bar button items' events last, as
    /// in a navigation controller's nib (`sb-split-bar-*`). Views beside children are refused.
    mutating func compileContainerScene(_ scene: XIBElement, controller sceneController: SceneController, children: [ContainerChild]) throws -> [String: Data] {
        let isTabBar = scene.children(named: "objects").first?.children(named: "tabBarController").isEmpty == false
        let (container, _) = try sceneObjects(scene, controller: isTabBar ? "tabBarController" : "splitViewController")
        try check(container, attributes: ["id", "sceneMemberID", "customClass", "customModule", "customModuleProvider", "storyboardIdentifier"] + (isTabBar ? [] : ["title"]),
                  children: Set(["connections", "toolbarItems"] + (isTabBar ? ["tabBar"] : [])))
        for items in container.children(named: "toolbarItems") {
            try check(items, attributes: [], children: [])
        }
        let original = isTabBar ? "UITabBarController" : "UISplitViewController"
        let customClass = try customClass(container, original: original)
        let kind: NibContainerController.Kind = isTabBar ? .tabBar(try tabBar(container)) : .split
        let containerController = NibContainerController(kind: kind, storyboardIdentifier: sceneController.identifier.map { string($0) },
                                                         swapsClass: customClass != nil || sceneController.isEntryPoint,
                                                         className: customClass ?? (string(original), string(original)))
        containerController.title = container.attributes["title"].map { text($0, id: container.attributes["id"], property: "title") }
        let sharedExternals = NibDictionary()
        let empty = NibArray([])
        let titleAttributes = NibDictionary()
        let templateLabel = NibString("viewController")
        var files: [String: Data] = [:]
        var containers: [NibArchivable] = [containerController]
        var viewControllers: [NibArchivable] = []
        var templateOutlets: [NibArchivable] = []
        var anchors: [NibArchivable] = []
        var events: [NibArchivable] = []
        var inlined: [NibArchivable] = []
        var childrenByID: [String: NibArchivable] = [:]
        for child in children {
            guard child.controller.children.isEmpty else { throw unsupportedScene("a tab bar or split view controller's child with children of its own") }
            if let reference = child.controller.reference {
                // A storyboard reference among a tab bar controller's children has a placeholder of
                // its own but no `storyboard` outlet, and the tab bar a default item for it, which
                // the reference does not name (`sb-ref-tab`, `sb-ref-tab-two`).
                guard isTabBar, case .tabBar(let bar) = kind else { throw unsupportedScene("a storyboard reference in a split view controller") }
                bar.items.append(NibTabBarItem(declared: false))
                let item = reference.item ? NibNavigationItem() : nil
                item?.centerItemGroups = empty
                let placeholder = NibStoryboardReference(identifier: string(child.controller.nibName), item: item)
                placeholder.parent = containerController
                childrenByID[child.controller.id] = placeholder
                inlined.append(placeholder)
                continue
            }
            let (controller, objects) = try sceneObjects(child.scene, controller: child.root == nil ? "viewController" : "navigationController")
            let item = isTabBar ? try tabBarItem(controller) : nil
            if let item, case .tabBar(let bar) = kind { bar.items.append(item) }
            if let root = child.root, root.controller.reference != nil {
                guard isTabBar else { throw unsupportedScene("a storyboard reference in a split view controller") }
                let navigation = try referenceNavigation(controller, swapsClass: false, root: root.controller, empty: empty, inContainer: true)
                navigation.tabItem = item
                navigation.container = containerController
                childrenByID[child.controller.id] = navigation
                containers.append(navigation)
                inlined += [navigation, navigation.root]
            } else if let root = child.root {
                let navigation = try inlinedNavigation(controller, swapsClass: false, rootScene: root.scene, root: root.controller, templates: root.templates,
                                                       empty: empty, sharedExternals: sharedExternals)
                guard navigation.extras.isEmpty else { throw unsupportedScene("views beside a tab bar or split view controller's navigation child's root") }
                anchors += navigation.anchors
                events += navigation.actions
                files["\(navigation.view.nibName).nib"] = navigation.view.nib
                navigation.root.item.titleAttributes = titleAttributes
                navigation.navigation.tabItem = item
                navigation.navigation.container = containerController
                childrenByID[child.controller.id] = navigation.navigation
                containers.append(navigation.navigation)
                viewControllers.append(navigation.root)
                templateOutlets += Self.templateOutlets(root.templates, controller: navigation.root, label: templateLabel)
                inlined += [navigation.navigation, navigation.root]
            } else {
                guard child.controller.segues.allSatisfy({ $0.cell == nil && $0.control == nil }) else {
                    throw unsupportedScene("cells' or buttons' segues of a tab bar or split view controller's child")
                }
                try check(controller, attributes: ["id", "sceneMemberID", "customClass", "customModule", "customModuleProvider", "userLabel"]
                          + ControllerSettings.attributes.filter { isTabBar || $0 != "title" },
                          children: ["layoutGuides", "view", "tabBarItem", "connections", "extendedEdge"])
                let title = controller.attributes["title"]
                guard title == nil || (item?.declared == false && !localizable) else {
                    throw unsupportedScene("a tab bar controller's child's title with its own tab bar item or in a localized document")
                }
                item?.title = title.map { string($0) } ?? item?.title
                let view = try childView(controller, objects: objects, into: &files)
                let viewController = NibContainerChildViewController(title: title.map { string($0) }, item: item,
                                                                     externalObjects: view.usesUpstream ? NibDictionary() : sharedExternals,
                                                                     viewNibName: string(view.nibName),
                                                                     segueTemplates: child.templates,
                                                                     customClass: try self.customClass(controller, original: "UIViewController"),
                                                                     parent: containerController)
                viewController.settings = try presentationSettings(controller)
                if view.usesUpstream {
                    viewController.externalObjects.entries = externalObjects(viewController, [])
                }
                childrenByID[child.controller.id] = viewController
                viewControllers.append(viewController)
                templateOutlets += Self.templateOutlets(child.templates, controller: viewController, label: templateLabel)
                inlined.append(viewController)
            }
        }
        containerController.children = sceneController.childOrder.map { childrenByID[$0]! }
        if case .tabBar(let bar) = kind { bar.delegate = containerController }
        let placeholder = NibProxy(identifier: "UIStoryboardPlaceholder")
        let placeholders = inlined.map { _ in NibProxy(sharing: placeholder.identifier) }
        let placeholderOf = Dictionary(uniqueKeysWithValues: zip(inlined.map(ObjectIdentifier.init), placeholders))
        let owner = NibProxy(identifier: "IBFilesOwner")
        let topLevel: [NibArchivable] = placeholders.reversed() + [owner, NibProxy(identifier: "IBFirstResponder"), placeholder, containerController]
        let storyboard = NibString("storyboard")
        let connections: [NibArchivable] = (containers + viewControllers).map {
            NibOutletConnection(label: storyboard, source: $0, destination: placeholderOf[ObjectIdentifier($0)] ?? placeholder)
        } + anchors + [NibOutletConnection(label: NibString("sceneViewController"), source: owner, destination: containerController)] + templateOutlets + events
        files["\(sceneController.nibName).nib"] = try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: Self.allObjects(topLevel),
                                                                                 connections: connections, empty: empty))
        return files
    }

    /// A tab bar controller's `<tabBar>`, which IB lays out itself.
    private mutating func tabBar(_ controller: XIBElement) throws -> NibTabBar {
        let bars = controller.children(named: "tabBar")
        guard bars.count == 1, let barElement = bars.first, let rect = barElement.child("rect", key: "frame") else {
            throw unsupportedScene("a tab bar controller without one tab bar of a frame")
        }
        try check(barElement, attributes: ["key", "contentMode", "id"], children: ["rect", "autoresizingMask", "color"])
        try value(barElement, "contentMode", in: ["scaleToFill"])
        for mask in barElement.children(named: "autoresizingMask") {
            try check(mask, attributes: ["key"], children: [])
        }
        for color in barElement.children(named: "color") {
            try value(color, "key", in: ["backgroundColor"])
        }
        return NibTabBar(center: (try number(rect.attributes["x"] ?? "0", "x"), try number(rect.attributes["y"] ?? "0", "y") + 27),
                         backgroundColor: try barElement.child("color", key: "backgroundColor").map { try color($0) }, hugging: string("{250, 250}"))
    }

    /// A tab bar controller's child's `<tabBarItem>`, its title and image.
    private mutating func tabBarItem(_ controller: XIBElement) throws -> NibTabBarItem {
        let item = NibTabBarItem(declared: controller.child("tabBarItem", key: "tabBarItem") != nil)
        for element in controller.children(named: "tabBarItem") {
            try check(element, attributes: ["key", "title", "image", "catalog", "id"], children: [])
            try value(element, "key", in: ["tabBarItem"])
            guard element.attributes["title"] == nil || !localizable else { throw unsupported("a tab bar item's title in a localized document") }
            item.title = element.attributes["title"].map { string($0) }
            item.image = try element.attributes["image"].map { try image($0, catalog: element.attributes["catalog"]) }
        }
        return item
    }

    /// A container's view controller's view nib, added to `files`; whether it refers to its
    /// controller, which then has its own external objects (`sb-tab-child-outlet`,
    /// `sb-split-detail-outlet`).
    private mutating func childView(_ controller: XIBElement, objects: XIBElement, into files: inout [String: Data]) throws
        -> (nibName: String, usesUpstream: Bool) {
        guard objects.children(named: "view").isEmpty else { throw unsupportedScene("views beside a tab bar or split view controller's child") }
        let view = try controllerView(controller, objects: objects, owner: NibProxy(identifier: "IBFilesOwner"))
        files["\(view.nibName).nib"] = view.nib
        return (view.nibName, view.usesUpstream)
    }
}
