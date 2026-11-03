import Foundation

/// `UIPageViewController` of a storyboard's `<pageViewController>` (docs/formats/nib.md "Page view
/// controllers"; nib-experiments `sb-page-*`): its identifier, its view's resizing, its transition
/// style, orientation, spine location and page spacing, its class names when an entry point or of
/// a custom class.
final class NibPageViewController: NibArchivable {
    static let transitionStyles = ["pageCurl": 0, "scroll": 1]
    static let orientations = ["horizontal": 0, "vertical": 1]
    static let spineLocations = ["none": 0, "min": 1]

    let storyboardIdentifier: NibString?
    let transitionStyle: Int
    let navigationOrientation: Int
    let spineLocation: Int
    let pageSpacing: Int
    let className_: (name: NibString, original: NibString)?

    init(storyboardIdentifier: NibString?, transitionStyle: Int, navigationOrientation: Int, spineLocation: Int, pageSpacing: Int,
         className: (name: NibString, original: NibString)?) {
        self.storyboardIdentifier = storyboardIdentifier
        self.transitionStyle = transitionStyle
        self.navigationOrientation = navigationOrientation
        self.spineLocation = spineLocation
        self.pageSpacing = pageSpacing
        self.className_ = className
    }

    var className: String { className_ == nil ? "UIPageViewController" : "UIClassSwapper" }

    func encode(to encoder: NibEncoder) throws {
        if let storyboardIdentifier { try encoder.encode(storyboardIdentifier, forKey: "UIStoryboardIdentifier") }
        encoder.encode(.boolean(false), forKey: "UIAutoresizesArchivedViewToFullSize")
        encoder.encode(.integer(transitionStyle), forKey: "UITransitionStyle")
        encoder.encode(.integer(navigationOrientation), forKey: "UINavigationOrientation")
        encoder.encode(.integer(spineLocation), forKey: "UISpineLocation")
        encoder.encode(.integer(pageSpacing), forKey: "UIPageSpacing")
        if let className_ {
            try encoder.encode(className_.name, forKey: "UIClassName")
            try encoder.encode(className_.original, forKey: "UIOriginalClassName")
        }
    }
}

extension DocumentCompiler {
    /// A page view controller's scene: one nib of File's Owner, First Responder, the storyboard
    /// placeholder and the controller, connected by `storyboard` and `sceneViewController`; no view
    /// nib. IB's `autoresizesArchivedViewToFullSize="NO"` is required; a page spacing must be whole
    /// (`sb-page-spacing`); mid and max spine locations, and segues, are not observed.
    mutating func compilePageScene(_ scene: XIBElement, controller sceneController: SceneController) throws -> [String: Data] {
        let (controller, _) = try sceneObjects(scene, controller: "pageViewController")
        try check(controller, attributes: ["id", "sceneMemberID", "storyboardIdentifier", "customClass", "customModule", "customModuleProvider", "userLabel",
                                           "autoresizesArchivedViewToFullSize", "transitionStyle", "navigationOrientation", "spineLocation", "pageSpacing"],
                  children: [])
        guard controller.attributes["autoresizesArchivedViewToFullSize"] == "NO", sceneController.segues.isEmpty else {
            throw unsupportedScene("a page view controller resizing its archived view or with segues")
        }
        let spacing = try number(controller.attributes["pageSpacing"] ?? "0", "pageSpacing")
        guard spacing == spacing.rounded() else { throw unsupportedScene("a page view controller's fractional page spacing") }
        let customClass = try customClass(controller, original: "UIPageViewController")
        let pageController = NibPageViewController(
            storyboardIdentifier: sceneController.identifier.map { string($0) },
            transitionStyle: try mapped(controller.attributes["transitionStyle"] ?? "pageCurl", NibPageViewController.transitionStyles, "transitionStyle"),
            navigationOrientation: try mapped(controller.attributes["navigationOrientation"] ?? "horizontal", NibPageViewController.orientations,
                                              "navigationOrientation"),
            spineLocation: try mapped(controller.attributes["spineLocation"] ?? "min", NibPageViewController.spineLocations, "spineLocation"),
            pageSpacing: Int(spacing),
            className: customClass ?? (sceneController.isEntryPoint ? (string("UIPageViewController"), string("UIPageViewController")) : nil))
        let owner = NibProxy(identifier: "IBFilesOwner")
        let placeholder = NibProxy(identifier: "UIStoryboardPlaceholder")
        let topLevel: [NibArchivable] = [owner, NibProxy(identifier: "IBFirstResponder"), placeholder, pageController]
        let connections: [NibArchivable] = [NibOutletConnection(label: NibString("storyboard"), source: pageController, destination: placeholder),
                                            NibOutletConnection(label: NibString("sceneViewController"), source: owner, destination: pageController)]
        return ["\(sceneController.nibName).nib": try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: Self.allObjects(topLevel),
                                                                                 connections: connections))]
    }
}
