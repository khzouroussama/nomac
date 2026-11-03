import Foundation

/// `UIStoryboardViewControllerPlaceholder` of a storyboard reference's `<viewControllerPlaceholder>`
/// (docs/formats/nib.md "Storyboard references"; nib-experiments `sb-ref-*`): its nib name, which
/// the `Info.plist` maps to the referenced storyboard, the tab bar or navigation controller that
/// inlines it (`sb-ref-tab`, `sb-ref-nav-root`), and the navigation item IB gives it, which only a
/// navigation controller's bar names, else only the nib's objects list.
final class NibStoryboardReference: NibArchivable, NibObjectChildren {
    let identifier: NibString
    let item: NibNavigationItem?
    weak var parent: NibArchivable?

    init(identifier: NibString, item: NibNavigationItem?) {
        self.identifier = identifier
        self.item = item
    }

    var className: String { "UIStoryboardViewControllerPlaceholder" }
    var childObjects: [NibArchivable] { [item].compactMap { $0 } }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(identifier, forKey: "UIStoryboardIdentifier")
        if let parent { try encoder.encode(parent, forKey: "UIParentViewController") }
    }
}

extension DocumentCompiler {
    /// A storyboard reference: its attributes and its navigation item, which has no attributes but
    /// its key and id (`sb-ref-show-item`, the corpus's gomap and nextcloud storyboards).
    func storyboardReference(_ element: XIBElement) throws -> (storyboard: String, identifier: String?, item: Bool) {
        try check(element, attributes: ["storyboardName", "referencedIdentifier", "id", "sceneMemberID"], children: ["navigationItem"])
        let items = element.children(named: "navigationItem")
        for item in items {
            try check(item, attributes: ["key", "id"], children: [])
            try value(item, "key", in: ["navigationItem"])
        }
        guard let storyboard = element.attributes["storyboardName"], items.count <= 1 else {
            throw unsupportedScene("a storyboard reference without a storyboard name or with two navigation items")
        }
        return (storyboard, element.attributes["referencedIdentifier"], !items.isEmpty)
    }

    /// A storyboard reference's scene: one nib of File's Owner, First Responder, the storyboard
    /// placeholder and the reference, which File's Owner's `sceneViewController` names; unlike a
    /// controller, it has no `storyboard` outlet (`sb-ref-show`, `sb-ref-push`).
    mutating func compileReferenceScene(_ scene: XIBElement, controller sceneController: SceneController) throws -> [String: Data] {
        try check(scene, attributes: ["sceneID"], children: ["objects", "point"])
        guard let objects = scene.children(named: "objects").first, let reference = sceneController.reference else {
            throw unsupportedScene("a scene without objects")
        }
        try check(objects, attributes: [], children: ["viewControllerPlaceholder", "placeholder"])
        for placeholder in objects.children(named: "placeholder") {
            try check(placeholder, attributes: ["placeholderIdentifier", "id", "sceneMemberID", "userLabel", "customClass"], children: [])
            try value(placeholder, "placeholderIdentifier", in: ["IBFirstResponder"])
        }
        let empty = NibArray([])
        let item = reference.item ? NibNavigationItem() : nil
        item?.centerItemGroups = empty
        let placeholder = NibStoryboardReference(identifier: string(sceneController.nibName), item: item)
        let owner = NibProxy(identifier: "IBFilesOwner")
        let topLevel: [NibArchivable] = [owner, NibProxy(identifier: "IBFirstResponder"), NibProxy(identifier: "UIStoryboardPlaceholder"), placeholder]
        let connections = [NibOutletConnection(label: NibString("sceneViewController"), source: owner, destination: placeholder)]
        return ["\(sceneController.nibName).nib": try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: Self.allObjects(topLevel),
                                                                                 connections: connections, empty: empty))]
    }
}
