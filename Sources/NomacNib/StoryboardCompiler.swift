import Foundation
import NomacCore
import NomacPlist

/// Compiles an iOS `.storyboard` into the files of its `.storyboardc` as
/// `ibtool --compilation-directory` does (docs/formats/nib.md "Storyboards"): an `Info.plist`, and
/// for each scene a view-controller nib and a view nib. Only the scenes the experiments observed
/// are compiled; anything else stops it with an error naming its BACKLOG item (ADR 0251).
public enum StoryboardCompiler {
    /// The files of `<name>.storyboardc`, by path inside it.
    public static func compile(_ data: Data, path: String, options: XIBCompiler.Options) throws -> [String: Data] {
        try compileReportingWarnings(data, path: path, options: options).files
    }

    /// The files of `<name>.storyboardc` and ibtool's document warnings, `<path>:<object id>: warning: <message>`
    /// lines in its order: deprecated push and modal segues (`sb-segue-push*`, `sb-segue-modal*`).
    public static func compileReportingWarnings(_ data: Data, path: String, options: XIBCompiler.Options) throws -> (files: [String: Data], warnings: [String]) {
        let deploymentTarget = try XIBCompiler.check(options, path: path)
        let document = try XIBReader.read(data, path: path)
        var compiler = DocumentCompiler(path: path, module: options.module, deploymentTarget: deploymentTarget)
        let files = try compiler.compileStoryboard(document)
        return (files, try compiler.documentWarnings())
    }

    /// `<document>` attributes of a storyboard: a xib's, another type, and the initial controller.
    static let documentAttributes: [String: Set<String>?] = {
        var attributes = XIBCompiler.documentAttributes
        attributes["type"] = ["com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB"]
        attributes["initialViewController"] = .some(nil)
        return attributes
    }()

    /// The size of scenes' views in a storyboard without a `<device>` deployed before iOS 17, whatever
    /// their frames say: 600 x 600 with trait collections, the default device's 393 x 852 without;
    /// from 17.0 they keep their frames (nib-experiments `sb-deployment-*`, from 8.0 to 16.6;
    /// `sb-flutter-launch-*`, `sb-no-traits-*`).
    static let sizeWithoutDevice: (width: Double, height: Double) = (600, 600)
    static let sizeWithoutDeviceOrTraitCollections: (width: Double, height: Double) = (393, 852)

    /// The size a storyboard gives its scenes' views on each device, in portrait, whatever their
    /// frames say; `retina3_5`, which Xcode 27.0 does not offer, gets 393 x 852 in either orientation
    /// (nib-experiments `sb-device-*`, `sb-device-retina3_5-frame`, `sb-vo-all-retina3_5-landscape`).
    static let deviceSizes: [String: (width: Double, height: Double)] = [
        "retina3_5": (393, 852), "retina4_0": (320, 568), "retina4_7": (375, 667), "retina5_5": (414, 736), "retina5_9": (375, 812),
        "retina6_0": (390, 844), "retina6_1": (414, 896), "retina6_12": (393, 852), "retina6_3": (402, 874), "retina6_5": (414, 896),
        "retina6_7": (430, 932), "retina6_9": (440, 956), "ipad9_7": (768, 1024), "ipad11_0rounded": (834, 1210),
        "ipad12_9rounded": (1024, 1366),
    ]
}

extension DocumentCompiler {
    mutating func compileStoryboard(_ document: XIBElement) throws -> [String: Data] {
        try header(document, attributes: StoryboardCompiler.documentAttributes)
        roundsInlineColors = true
        var scenes: [XIBElement] = []
        for child in document.children {
            switch child.name {
            case "device", "dependencies", "resources", "accessibilityOverrides":
                try headerElement(child)
            case "scenes":
                try check(child, attributes: [], children: ["scene"])
                scenes = child.children
            case "designables":
                try designables(child)
            case "customFonts":
                try customFonts(child)
            case "inferredMetricsTieBreakers":
                // Segues IB settles inferred metrics by; they change nothing (`sb-tie-breakers`).
                try check(child, attributes: [], children: ["segue"])
                for segue in child.children {
                    try check(segue, attributes: ["reference"], children: [])
                }
            default:
                throw unsupported("<\(child.name)> in a document")
            }
        }
        let initial = document.attributes["initialViewController"]
        if let device = document.children(named: "device").first {
            let id = device.attributes["id"] ?? "retina6_12"
            let size = StoryboardCompiler.deviceSizes[id]!
            let landscape = device.attributes["orientation"] == "landscape" && id != "retina3_5"
            sceneSize = landscape ? (size.height, size.width) : size
            deviceSizeClasses = SizeClasses.device(id, landscape: landscape)
        } else if deploymentTarget.major < 17 {
            sceneSize = document.attributes["useTraitCollections"] == "YES" ? StoryboardCompiler.sizeWithoutDevice
                : StoryboardCompiler.sizeWithoutDeviceOrTraitCollections
        }
        usesSafeAreas = document.attributes["useSafeAreas"] == "YES"
        let controllers = try scenes.map { try sceneController($0, initial: initial) }
        let segueIDs = controllers.flatMap(\.segues).map(\.id)
        guard Set(controllers.map(\.id)).count == controllers.count, Set(segueIDs).count == segueIDs.count else {
            throw unsupportedScene("two controllers or segues of one id")
        }
        let byID = Dictionary(uniqueKeysWithValues: controllers.map { ($0.id, $0) })
        let roots = Set(controllers.compactMap(\.root) + controllers.flatMap(\.children))
        let tabChildren = Set(controllers.flatMap(\.children))
        let segueDestinations = Set(controllers.flatMap { $0.segues.compactMap(\.destination) })
        for root in roots {
            // A navigation controller's root with its own identifier has its own nib too (`sb-nav-root-identifier`).
            guard let controller = byID[root], !controller.isEntryPoint || controller.identifier != nil && root != initial && !tabChildren.contains(root),
                  controller.root == nil || tabChildren.contains(root), controller.children.isEmpty,
                  !segueDestinations.contains(root) || tabChildren.contains(root) else {
                throw unsupportedScene("a navigation controller's root that is no plain view controller or that other controllers reach")
            }
        }
        guard roots.count == controllers.compactMap(\.root).count + tabChildren.count, tabChildren.count == controllers.flatMap(\.children).count else {
            throw unsupportedScene("a controller of two navigation or tab bar controllers")
        }
        // Show, presentation, push and modal segues of buttons, cells and controllers reach
        // storyboard references (`sb-ref-*`).
        for segue in controllers.flatMap(\.segues) where segue.destination.flatMap({ byID[$0]?.reference }) != nil {
            guard [.show, .presentation, .push, .modal].contains(segue.kind), segue.barItem == nil else {
                throw unsupportedScene("a storyboard reference reached by a \(segue.kind) segue or a bar button item's")
            }
        }
        var reached = Set(controllers.filter { $0.id == initial || $0.identifier != nil }.map(\.id))
        var pending = Array(reached)
        while let id = pending.popLast() {
            for destination in byID[id]!.segues.compactMap(\.destination) + [byID[id]!.root].compactMap({ $0 }) + byID[id]!.children {
                guard byID[destination] != nil else { throw unsupportedScene("a segue to \(destination), which is no scene's controller") }
                if reached.insert(destination).inserted {
                    pending.append(destination)
                }
            }
        }
        let scenesByID = Dictionary(uniqueKeysWithValues: zip(controllers.map(\.id), scenes))
        // ibtool skips the controllers nothing reaches, warning about those no controller refers to
        // (`sb-unreached-*`, `sb-segue-unreached-source`); the order of several warnings is not known.
        let unreached = Set(controllers.map(\.id)).subtracting(reached)
        let referred = Set(controllers.flatMap { $0.segues.compactMap(\.destination) + [$0.root].compactMap { $0 } + $0.children })
        let skipped = controllers.filter { unreached.contains($0.id) && !referred.contains($0.id) }
        let deprecated = controllers.contains { $0.segues.contains { [.push, .modal].contains($0.kind) } }
        guard skipped.count <= 1, skipped.isEmpty || !deprecated else {
            throw unsupportedScene("several view controllers no entry point, identifier or segue reaches (ibtool skips them with warnings)")
        }
        let unreachedWarnings = try skipped.map { ($0.id, "“\(try unreachedName(scenesByID[$0.id]!))“ is unreachable because it has no entry points, and no identifier "
                                                           + "for runtime access via -[UIStoryboard instantiateViewControllerWithIdentifier:]. [9]") }
        warnings = unreachedWarnings + controllers.flatMap(\.segues).compactMap { segue in
            [Segue.Kind.push: "Push", .modal: "Modal"][segue.kind].map { (segue.id, "\($0) segues are deprecated since iOS 8.0 [7]") }
        }
        // An embedded controller's view, or its navigation controller's root's, takes its container
        // view's size (`sb-embed*`).
        embeddedSizes = [:]
        for segue in controllers.flatMap(\.segues) where segue.kind == .embed {
            guard let destination = segue.destination, let size = segue.containerSize else { continue }
            for id in [destination] + [byID[destination]?.root].compactMap({ $0 }) {
                guard embeddedSizes[id].map({ $0 == size }) ?? true else { throw unsupportedScene("a controller embedded in container views of two sizes") }
                embeddedSizes[id] = size
            }
        }
        func templates(_ controller: SceneController) throws -> [NibSegueTemplate] {
            var templates: [NibSegueTemplate] = []
            for segue in controller.segues {
                var identifier: NibString?
                if let name = segue.identifier { identifier = string(name) }
                let destination = segue.destination.map { string(byID[$0]!.nibName) }
                let action = (segue.kind.action ?? segue.unwindAction).map { string($0) }
                let template = NibSegueTemplate(kind: segue.kind, identifier: identifier, destination: destination, action: action,
                                                arrowDirections: segue.arrowDirections)
                template.segueClass = try segue.classElement.flatMap { try customClass($0)?.name }
                templates.append(template)
            }
            return templates
        }
        // A container's child that a segue reaches has its own nib too (`sb-split-showdetail*`), as
        // a navigation controller's root with an identifier.
        let compiled = Set(controllers.map(\.id).filter { !roots.contains($0) || segueDestinations.contains($0) || byID[$0]!.identifier != nil }).subtracting(unreached)
        var files: [String: Data] = [:]
        for (scene, controller) in zip(scenes, controllers) where compiled.contains(controller.id) {
            let grandchildren = controller.children.compactMap { byID[$0]!.root }
            otherScenesControllers = Set(controllers.map(\.id)).subtracting([controller.id, controller.root].compactMap { $0 } + controller.children + grandchildren)
            if !controller.children.isEmpty {
                var children: [ContainerChild] = []
                for id in controller.children {
                    let root = try byID[id]!.root.map { (scene: scenesByID[$0]!, controller: byID[$0]!, templates: try templates(byID[$0]!)) }
                    children.append(ContainerChild(scene: scenesByID[id]!, controller: byID[id]!, templates: try templates(byID[id]!), root: root))
                }
                files.merge(try compileContainerScene(scene, controller: controller, children: children)) { $1 }
            } else if let root = controller.root {
                files.merge(try compileNavigationScene(scene, controller: controller, rootScene: scenesByID[root]!, root: byID[root]!,
                                                       templates: templates(byID[root]!))) { $1 }
            } else if controller.reference != nil {
                files.merge(try compileReferenceScene(scene, controller: controller)) { $1 }
            } else if scene.children(named: "objects").first?.children(named: "pageViewController").isEmpty == false {
                files.merge(try compilePageScene(scene, controller: controller)) { $1 }
            } else {
                files.merge(try compileScene(scene, controller: controller, templates: templates(controller))) { $1 }
            }
            try checkNoNavigationPairs()
        }
        try checkRequiredVersion()
        let nibNames = controllers.filter { compiled.contains($0.id) }.map(\.nibName)
        if controllers.contains(where: { !$0.segues.isEmpty }), nibNames.count > 3, try !Self.orderIndependent(nibNames) {
            throw NomacError("nomac does not compile segues among scenes whose nib names' Info.plist order depends on an order not known yet (BACKLOG B-266)",
                             path: path)
        }
        let references = controllers.filter { reached.contains($0.id) }.compactMap { controller in
            controller.reference.map { (controller.nibName, $0.storyboard, $0.identifier) }
        }
        files["Info.plist"] = try Self.info(nibNames: nibNames, entryPoint: initial.flatMap { byID[$0] }.map { ($0.nibName, $0.identifier != nil) },
                                            references: references)
        return files
    }

    /// How ibtool names a controller in its warnings, as IB's outline does: its label, title, custom
    /// class in words, or kind (`sb-unreached-*`); two of the first three are not observed together.
    func unreachedName(_ scene: XIBElement) throws -> String {
        guard let controller = scene.children(named: "objects").first?.children.first(where: { $0.attributes["sceneMemberID"] == "viewController" }) else {
            throw unsupportedScene("a scene without a view controller")
        }
        let given = ["userLabel", "title", "customClass"].compactMap { controller.attributes[$0] }
        guard given.count <= 1 else { throw unsupportedScene("an unreachable view controller of a label, title or class together") }
        if let label = controller.attributes["userLabel"] ?? controller.attributes["title"] { return label }
        if let name = controller.attributes["customClass"] {
            guard zip(name, name.dropFirst()).allSatisfy({ !($0.isUppercase && $1.isUppercase) }) else {
                throw unsupportedScene("an unreachable view controller of a class with consecutive capitals")
            }
            return name.reduce(into: "") { words, character in
                if character.isUppercase, !words.isEmpty { words += " " }
                words.append(character)
            }
        }
        if controller.name == "viewControllerPlaceholder" {
            guard let identifier = controller.attributes["referencedIdentifier"] else {
                throw unsupportedScene("an unreachable storyboard reference without a referenced identifier")
            }
            return identifier
        }
        let kinds = ["viewController": "View Controller", "navigationController": "Navigation Controller", "tableViewController": "Table View Controller"]
        guard let kind = kinds[controller.name] else { throw unsupportedScene("an unreachable \(controller.name)") }
        return kind
    }

    /// The document warnings, ordered as a Foundation hash table of their objects' ids orders them
    /// (`sb-segue-push-two`, `sb-segue-modal-push`, `sb-segue-push-three`).
    func documentWarnings() throws -> [String] {
        if let deploymentWarning {
            guard warnings.isEmpty else { throw unsupportedScene("a document version ibtool warns about beside other warnings") }
            return ["\(path):global: warning: \(deploymentWarning)"]
        }
        let messages = Dictionary(warnings.map { ($0.id, $0.message) }) { first, _ in first }
        return try FoundationHashTable.inserting(warnings.map(\.id)).keys.map { "\(path):\($0): warning: \(messages[$0]!)" }
    }

    /// Whether every order of entering `names` gives the Info.plist the same order. ibtool enters
    /// them in document order without segues (`sb-scenes-*`: up to 9) and with segues among up to
    /// 3 (`sb-segue-two`, `sb-segue-chain`); with more, by an order not known yet (B-266:
    /// `sb-info-order-graph`, tofu's storyboard), so only an order-independent table is written.
    /// Up to 8 names are tried in every order.
    static func orderIndependent(_ names: [String]) throws -> Bool {
        guard names.count <= 8 else { return false }
        let expected = try FoundationHashTable.inserting(names).copied().keys
        var order = names
        func permute(_ k: Int) throws -> Bool {
            if k == order.count { return try FoundationHashTable.inserting(order).copied().keys == expected }
            for i in k..<order.count {
                order.swapAt(k, i)
                defer { order.swapAt(k, i) }
                if try !permute(k + 1) { return false }
            }
            return true
        }
        return try permute(0)
    }

    /// A value of the `.storyboardc`'s `Info.plist`: a string, the same string object as the nib
    /// names' key of that name, an integer or a dictionary.
    indirect enum InfoValue {
        case string(String)
        case nibName(String)
        case integer(Int)
        case dictionary([(String, InfoValue)])
    }

    /// The `.storyboardc`'s `Info.plist` as ibtool writes it (nib-experiments `storyboard`,
    /// `sb-identifier`, `sb-scenes-*`, `sb-segue-*`, `sb-ref-*`): each dictionary's keys in the order
    /// of a Foundation table they entered in document order, or the top level's in the order here
    /// (`sb-ref-no-entry`), copied, the key strings and then the
    /// values depth first; the controllers' nib names of a mutable dictionary (`sb-scenes-*-identified`);
    /// the entry point the nib names' key itself when the initial controller has a storyboard
    /// identifier, a string of its own otherwise; the storyboard references by nib name, each its
    /// referenced identifier and storyboard's name, entered in that order, under keys every reference
    /// shares (`sb-ref-show`, `sb-ref-tab-two`).
    static func info(nibNames: [String], entryPoint: (nibName: String, identified: Bool)?,
                     references: [(nibName: String, storyboard: String, identifier: String?)] = []) throws -> Data {
        var top: [(String, InfoValue)] = [("UIViewControllerIdentifiersToNibNames", .dictionary(nibNames.map { ($0, .string($0)) }))]
        if let entryPoint {
            top.append(("UIStoryboardDesignatedEntryPointIdentifier", entryPoint.identified ? .nibName(entryPoint.nibName) : .string(entryPoint.nibName)))
        }
        if !references.isEmpty {
            top.append(("UIViewControllerIdentifiersToExternalStoryboardReferences", .dictionary(references.map { reference in
                (reference.nibName, .dictionary((reference.identifier.map { [("UIReferencedControllerIdentifier", .string($0))] } ?? [])
                    + [("UIReferencedStoryboardName", .string(reference.storyboard))]))
            })))
        }
        top.append(("UIStoryboardVersion", .integer(1)))
        var objects: [BinaryPropertyList.Object] = []
        var nibNameKeys: [String: Int] = [:]
        var sharedKeys: [String: Int] = [:]
        func append(_ value: InfoValue, nibNames isNibNames: Bool = false) throws -> Int {
            switch value {
            case .string(let text):
                objects.append(.string(text))
                return objects.count - 1
            case .nibName(let name):
                return nibNameKeys[name]!
            case .integer(let number):
                objects.append(.integer(number))
                return objects.count - 1
            case .dictionary(let entries):
                let values = Dictionary(entries) { first, _ in first }
                let keys = try FoundationHashTable.inserting(entries.map(\.0)).copied().keys
                let index = objects.count
                objects.append(.integer(0))
                let shared = keys.allSatisfy { $0.hasPrefix("UIReferenced") }
                let keyIndices = keys.map { key in
                    if shared, let known = sharedKeys[key] { return known }
                    objects.append(.string(key))
                    if shared { sharedKeys[key] = objects.count - 1 }
                    if isNibNames { nibNameKeys[key] = objects.count - 1 }
                    return objects.count - 1
                }
                let valueIndices = try keys.map { try append(values[$0]!, nibNames: $0 == "UIViewControllerIdentifiersToNibNames") }
                objects[index] = .dictionary(keys: keyIndices, values: valueIndices)
                return index
            }
        }
        _ = try append(.dictionary(top))
        return BinaryPropertyList.data(objects: objects)
    }

    /// A scene's view controller as the storyboard's graph needs it: its id, nib name and segues.
    struct SceneController {
        let id: String
        let identifier: String?
        let nibName: String
        let segues: [Segue]
        /// The initial controller or one with a storyboard identifier, which a storyboard
        /// instantiates by name.
        let isEntryPoint: Bool
        /// A navigation controller's root controller, archived in its nib.
        let root: String?
        /// A tab bar or split view controller's children, archived in its nib, in its relationship
        /// segues' order (`sb-tab-*`, `sb-split-*`).
        var children: [String] = []
        /// Its children in the order its `UIChildViewControllers` lists them: a split view
        /// controller's master, then its detail (`sb-split-swapped`).
        var childOrder: [String] = []
        /// A storyboard reference's storyboard, referenced identifier and navigation item.
        var reference: (storyboard: String, identifier: String?, item: Bool)?
    }

    /// A segue from a view controller (`sb-segue-*`), a table view cell (`sb-cellseg-*`) or a button
    /// (`sb-button-*`): a show, showDetail, presentation or popover presentation segue to a scene's
    /// controller, or an unwind segue to the scene's exit (`sb-unwind-*`). A controller's own segues
    /// have identifiers; ibtool warns about those without one, which nomac does not compile.
    struct Segue {
        enum Kind: String {
            case show, showDetail, presentation, popoverPresentation, unwind, embed, push, modal, custom

            /// A show segue's action; a showDetail segue is a show segue of its own action
            /// (`sb-segue-showDetail`, `sb-cellseg-prototype-showDetail*`).
            var action: String? {
                switch self {
                case .show: "showViewController:sender:"
                case .showDetail: "showDetailViewController:sender:"
                case .presentation, .popoverPresentation, .unwind, .embed, .push, .modal, .custom: nil
                }
            }
        }
        let kind: Kind
        let identifier: String?
        /// Its destination controller; none for an unwind segue.
        let destination: String?
        let id: String
        /// The table view cell that triggers it, for a cell's segue, whether a prototype's, and
        /// whether its accessory triggers it (`trigger="accessoryAction"`: `sb-cellseg-accessory*`).
        var cell: String?
        var prototype = false
        var accessory = false
        /// The button that triggers it, or the container view an embed segue fills (`sb-embed*`).
        var control: String?
        /// An unwind segue's action.
        var unwindAction: String?
        /// A popover's permitted arrow directions (up 1, down 2, left 4, right 8) and the view it
        /// is anchored to (`sb-popover-*`).
        var arrowDirections: Int?
        var anchorView: String?
        /// An embed segue's container view's size.
        var containerSize: (width: Double, height: Double)?
        /// A custom segue's element, whose class it names (`sb-segue-custom*`).
        var classElement: XIBElement?
        /// The bar button item that triggers it, for a navigation item's segue, and anchors it
        /// when a popover (`sb-popover-bar-item`).
        var barItem: String?
    }

    /// A `<segue>` of a scene whose exit is `exit`.
    func segue(_ element: XIBElement, exit: String?) throws -> Segue {
        try check(element, attributes: ["destination", "kind", "identifier", "id", "unwindAction", "popoverAnchorView", "popoverAnchorBarButtonItem",
                                        "customClass", "customModule", "customModuleProvider", "trigger"], children: ["popoverArrowDirection"])
        try value(element, "trigger", in: ["accessoryAction"])
        guard let kind = element.attributes["kind"].flatMap(Segue.Kind.init), let destination = element.attributes["destination"],
              let id = element.attributes["id"] else {
            throw unsupportedScene("a segue other than a show, showDetail, presentation, popover or unwind segue")
        }
        var segue = Segue(kind: kind, identifier: element.attributes["identifier"], destination: kind == .unwind ? nil : destination, id: id)
        guard (kind == .unwind) == (element.attributes["unwindAction"] != nil), kind != .unwind || destination == exit else {
            throw unsupportedScene("an unwind segue without an action or to another object than its scene's exit")
        }
        segue.unwindAction = element.attributes["unwindAction"]
        let arrows = element.children(named: "popoverArrowDirection")
        let anchors = ["popoverAnchorView", "popoverAnchorBarButtonItem"].filter { element.attributes[$0] != nil }
        guard kind == .popoverPresentation ? arrows.count == 1 && anchors.count == 1 : arrows.isEmpty && anchors.isEmpty else {
            throw unsupportedScene("a popover segue without one arrow direction and one anchor")
        }
        if let arrow = arrows.first {
            try check(arrow, attributes: ["key", "up", "down", "left", "right"], children: [])
            try value(arrow, "key", in: ["popoverArrowDirection"])
            segue.arrowDirections = try [("up", 1), ("down", 2), ("left", 4), ("right", 8)].reduce(0) { bits, direction in
                try bool(arrow, direction.0, default: false) ? bits | direction.1 : bits
            }
        }
        segue.anchorView = element.attributes["popoverAnchorView"]
        guard (kind == .custom) == (element.attributes["customClass"] != nil) else {
            throw unsupportedScene("a custom segue without a class, or another segue with one")
        }
        segue.classElement = kind == .custom ? element : nil
        segue.accessory = element.attributes["trigger"] != nil
        return segue
    }

    private func sceneController(_ scene: XIBElement, initial: String?) throws -> SceneController {
        let objects = scene.children(named: "objects").first?.children ?? []
        let controllers = objects.filter { ["viewController", "navigationController", "tableViewController", "collectionViewController", "tabBarController",
                                                 "splitViewController", "pageViewController", "viewControllerPlaceholder"].contains($0.name) }
        guard controllers.count == 1, let controller = controllers.first, let id = controller.attributes["id"] else {
            throw unsupportedScene("a scene without one view controller")
        }
        if controller.name == "viewControllerPlaceholder" {
            guard id != initial else { throw unsupportedScene("a storyboard reference as the initial controller") }
            return SceneController(id: id, identifier: nil, nibName: "UIViewController-\(id)", segues: [], isEntryPoint: false, root: nil,
                                   reference: try storyboardReference(controller))
        }
        let exits = objects.filter { $0.name == "exit" }
        guard exits.count <= 1 else { throw unsupportedScene("a scene with two exits") }
        let exit = exits.first?.attributes["id"]
        var segues: [Segue] = []
        var root: String?
        var children: [(id: String, relationship: String)] = []
        let relationships = ["tabBarController": ["viewControllers"], "splitViewController": ["masterViewController", "detailViewController"]][controller.name]
        for container in controller.children(named: "connections") {
            for element in container.children(named: "segue") {
                if controller.name == "navigationController", element.attributes["kind"] == "relationship" {
                    try check(element, attributes: ["destination", "kind", "relationship", "id"], children: [])
                    guard element.attributes["relationship"] == "rootViewController", root == nil else {
                        throw unsupportedScene("a navigation controller relationship other than one root view controller")
                    }
                    root = element.attributes["destination"]
                    continue
                }
                if let relationships {
                    try check(element, attributes: ["destination", "kind", "relationship", "id"], children: [])
                    guard element.attributes["kind"] == "relationship", let relationship = element.attributes["relationship"], relationships.contains(relationship),
                          let destination = element.attributes["destination"] else {
                        throw unsupportedScene("a tab bar or split view controller's segue other than its children's relationships")
                    }
                    children.append((destination, relationship))
                    continue
                }
                let segue = try segue(element, exit: exit)
                guard segue.identifier != nil, segue.kind != .popoverPresentation, segue.kind != .embed, !segue.accessory else {
                    throw unsupportedScene("a controller's segue without an identifier, or a popover one")
                }
                segues.append(segue)
            }
        }
        if controller.name == "tableViewController" {
            let prototypes = Set(Self.descendants(of: controller, named: "prototypes").flatMap { Self.descendants(of: $0, named: "tableViewCell") }.compactMap { $0.attributes["id"] })
            for cell in Self.descendants(of: controller, named: "tableViewCell") {
                for container in cell.children(named: "connections") {
                    for element in container.children(named: "segue") {
                        var segue = try segue(element, exit: exit)
                        guard [.show, .showDetail, .presentation, .push].contains(segue.kind), let cellID = cell.attributes["id"] else {
                            throw unsupportedScene("a cell's segue other than a show, showDetail, presentation or push segue")
                        }
                        segue.cell = cellID
                        segue.prototype = prototypes.contains(cellID)
                        segues.append(segue)
                    }
                }
            }
        }
        // Buttons' segues and container views' embed segues, in document order (`sb-embed-*`).
        func controls(_ element: XIBElement) -> [XIBElement] {
            element.children.flatMap { (["button", "containerView"].contains($0.name) ? [$0] : []) + controls($0) }
        }
        for view in controller.children(named: "view") {
            for control in controls(view) {
                for container in control.children(named: "connections") {
                    for element in container.children(named: "segue") {
                        var segue = try segue(element, exit: exit)
                        guard (segue.kind == .embed) == (control.name == "containerView"),
                              segue.anchorView == nil || segue.anchorView == control.attributes["id"] else {
                            throw unsupportedScene("a container view's segue other than an embed segue, or a button's popover anchored to another view")
                        }
                        segue.control = control.attributes["id"]
                        if segue.kind == .embed {
                            guard let rect = control.child("rect", key: "frame") else { throw unsupportedScene("a container view without a frame") }
                            segue.containerSize = (try number(rect.attributes["width"] ?? "", "width"), try number(rect.attributes["height"] ?? "", "height"))
                        }
                        segues.append(segue)
                    }
                }
            }
        }
        guard !segues.contains(where: { $0.cell != nil }) || !segues.contains(where: { $0.control != nil }) else {
            throw unsupportedScene("cells' and buttons' segues in one scene")
        }
        // A navigation item's bar button items' segues follow the view's (`sb-bar-popover-and-cell`).
        for item in controller.children(named: "navigationItem").flatMap({ $0.children(named: "barButtonItem") }) {
            for element in item.children(named: "connections").flatMap({ $0.children(named: "segue") }) {
                var segue = try segue(element, exit: exit)
                guard element.attributes["popoverAnchorView"] == nil,
                      element.attributes["popoverAnchorBarButtonItem"].map({ $0 == item.attributes["id"] }) ?? true else {
                    throw unsupportedScene("a bar button item's popover segue anchored to another object")
                }
                segue.barItem = item.attributes["id"]
                segues.append(segue)
            }
        }
        let identifier = controller.attributes["storyboardIdentifier"]
        if controller.name == "navigationController" {
            guard root != nil, segues.isEmpty else {
                throw unsupportedScene("a navigation controller without one root view controller or with segues")
            }
        }
        if controller.name == "tabBarController" {
            guard !children.isEmpty else { throw unsupportedScene("a tab bar controller without children") }
        }
        if controller.name == "splitViewController" {
            guard children.map(\.relationship).sorted() == ["detailViewController", "masterViewController"] else {
                throw unsupportedScene("a split view controller without one master and one detail view controller")
            }
        }
        let base = ["navigationController": "UINavigationController", "tableViewController": "UITableViewController",
                    "collectionViewController": "UICollectionViewController", "tabBarController": "UITabBarController",
                    "splitViewController": "UISplitViewController", "pageViewController": "UIPageViewController"][controller.name] ?? "UIViewController"
        let childOrder = (relationships ?? []).flatMap { relationship in children.filter { $0.relationship == relationship } }
        return SceneController(id: id, identifier: identifier, nibName: identifier ?? "\(base)-\(id)", segues: segues,
                               isEntryPoint: id == initial || identifier != nil, root: root, children: children.map(\.id), childOrder: childOrder.map(\.id))
    }

    /// An element's descendants of a name, depth first in document order.
    static func descendants(of element: XIBElement, named name: String) -> [XIBElement] {
        element.children.flatMap { ($0.name == name ? [$0] : []) + descendants(of: $0, named: name) }
    }

    /// A scene: its view controller, with its segues' templates, and its First Responder.
    private mutating func compileScene(_ scene: XIBElement, controller sceneController: SceneController, templates: [NibSegueTemplate]) throws -> [String: Data] {
        let objectNames = Set(scene.children(named: "objects").first?.children.map(\.name) ?? [])
        let kind = ["tableViewController", "collectionViewController"].first { objectNames.contains($0) } ?? "viewController"
        let (controller, objects) = try sceneObjects(scene, controller: kind, recognizers: kind == "viewController")
        if kind == "viewController", controller.children(named: "view").isEmpty {
            return try compileViewlessScene(controller, objects: objects, controller: sceneController)
        }
        try check(controller, attributes: ["id", "customClass", "customModule", "customModuleProvider", "storyboardIdentifier", "sceneMemberID",
                                           "definesPresentationContext", "userLabel"] + ControllerSettings.attributes + (kind == "viewController" ? [] : ["clearsSelectionOnViewWillAppear"]),
                  children: ["layoutGuides", "view", "tableView", "collectionView", "connections", "freeformSimulatedSizeMetrics", "size", "nil", "navigationItem",
                             "simulatedNavigationBarMetrics", "toolbarItems", "extendedEdge", "value"])
        try emptyToolbarItems(controller)
        let baseClass = ["tableViewController": "UITableViewController", "collectionViewController": "UICollectionViewController"][kind] ?? "UIViewController"
        let nibName = sceneController.nibName
        let empty = NibArray([])
        let item = NibNavigationItem()
        let (declared, _, barActions) = try navigationItem(controller, into: item, empty: empty)
        guard !sceneController.segues.contains(where: { $0.barItem != nil && $0.kind == .popoverPresentation }) else {
            throw unsupportedScene("a bar button item's popover segue outside a navigation controller")
        }
        let owner = NibProxy(identifier: "IBFilesOwner")
        let cellTemplates = cellSegueTemplates(sceneController, templates)
        let extraElements = objects.children(named: "view")
        let recognizer = try sceneRecognizer(objects, view: controller.child("view", key: "view") ?? controller, controller: controller)
        guard recognizer == nil || extraElements.isEmpty && cellTemplates.isEmpty else {
            throw unsupportedScene("gesture recognizers beside views or cells' segues in a scene")
        }
        let controlTemplates = zip(sceneController.segues, templates).filter { $0.0.control != nil }
        let view = try controllerView(controller, objects: objects, owner: owner, excluded: Set(extraElements.compactMap { $0.attributes["id"] }),
                                      recognizer: recognizer, controlSegues: controlTemplates.map(\.0))
        let extras = try extraViews(extraElements)
        guard cellTemplates.isEmpty || view.usesUpstream else { throw unsupportedScene("cells' segues of a table view without outlets to its controller") }
        let customClass = try customClass(controller, original: baseClass)
        let className = customClass ?? (string(baseClass), string(baseClass))
        let placeholder = NibProxy(identifier: "UIStoryboardPlaceholder")
        let viewController = NibViewController(viewNibName: view.nibName, storyboardIdentifier: sceneController.identifier.map { string($0) }, className: className,
                                               swapsClass: customClass != nil || sceneController.isEntryPoint, segueTemplates: templates)
        viewController.navigationItem = declared ? item : nil
        viewController.definesPresentationContext = try bool(controller, "definesPresentationContext", default: false)
        viewController.keptAlive = extras.map(\.view) + (recognizer.map { [$0.recognizer] } ?? [])
        viewController.settings = try controllerSettings(controller, storyboardIdentifier: viewController.storyboardIdentifier)
        viewController.keepsSelection = !(try bool(controller, "clearsSelectionOnViewWillAppear", default: true))
        guard !viewController.keepsSelection || viewController.keptAlive.isEmpty && !viewController.definesPresentationContext && !viewController.settings.presents else {
            throw unsupportedScene("a controller keeping its selection with objects kept alive, a presentation context or presentation styles")
        }
        if let recognizer {
            viewController.externalObjects.entries = recognizer.externalObjects(controller: view.usesUpstream ? viewController : nil)
        } else if view.usesUpstream || !controlTemplates.isEmpty {
            viewController.externalObjects.entries = externalObjects(view.usesUpstream ? viewController : nil, cellTemplates, controlTemplates: controlTemplates)
        }
        let extraTopLevel: [NibArchivable] = extras.reversed().map(\.view) + (recognizer.map { [$0.recognizer] } ?? [])
        let topLevel: [NibArchivable] = [owner, view.responder, placeholder]
            + (kind == "viewController" ? extraTopLevel + [viewController] : [viewController] + extraTopLevel)
        let outlets = [NibOutletConnection(label: NibString("storyboard"), source: viewController, destination: placeholder)]
            + (try controllerOutlets(controller, source: viewController, destinations: Dictionary(uniqueKeysWithValues: extras.map { ($0.id, $0.view) })))
            + [NibOutletConnection(label: NibString("sceneViewController"), source: owner, destination: viewController)]
            + Self.templateOutlets(templates, controller: viewController, label: NibString("viewController"))
        let connections: [NibArchivable] = outlets
            + (recognizer?.events(to: viewController) ?? [])
            + Self.barItemEvents(barActions, sceneController, templates, controller: viewController)
        // The runtime attributes of the views beside the controller are its nib's (wikipedia's Saved storyboard).
        let allObjects = Self.allObjects(topLevel)
        let controllerNib = try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: allObjects, connections: connections,
                                                           keyValuePairs: try takeKeyValuePairs(allObjects: allObjects), empty: empty))
        return ["\(nibName).nib": controllerNib, "\(view.nibName).nib": view.nib]
    }

    /// A scene of a view controller without a view, which loads its own: one nib of File's Owner,
    /// First Responder, the storyboard placeholder and the controller, no view nib (`sb-vc-no-view*`;
    /// nextcloud's action extension). Its segues and navigation item are not observed.
    private mutating func compileViewlessScene(_ controller: XIBElement, objects: XIBElement, controller sceneController: SceneController) throws -> [String: Data] {
        try check(controller, attributes: ["id", "customClass", "customModule", "customModuleProvider", "storyboardIdentifier", "sceneMemberID", "userLabel"]
                  + ControllerSettings.attributes, children: ["freeformSimulatedSizeMetrics", "size", "nil", "extendedEdge", "value"])
        guard sceneController.segues.isEmpty, objects.children(named: "view").isEmpty else {
            throw unsupportedScene("segues or views beside a view controller without a view")
        }
        for size in controller.children(named: "size") {
            try check(size, attributes: ["key", "width", "height"], children: [])
            try value(size, "key", in: ["freeformSize"])
        }
        let customClass = try customClass(controller, original: "UIViewController")
        let viewController = NibViewController(viewNibName: nil, storyboardIdentifier: sceneController.identifier.map { string($0) },
                                               className: customClass ?? (string("UIViewController"), string("UIViewController")),
                                               swapsClass: customClass != nil || sceneController.isEntryPoint)
        viewController.settings = try controllerSettings(controller, storyboardIdentifier: viewController.storyboardIdentifier)
        let owner = NibProxy(identifier: "IBFilesOwner")
        let placeholder = NibProxy(identifier: "UIStoryboardPlaceholder")
        let topLevel: [NibArchivable] = [owner, NibProxy(identifier: "IBFirstResponder"), placeholder, viewController]
        let connections: [NibArchivable] = [NibOutletConnection(label: NibString("storyboard"), source: viewController, destination: placeholder),
                                            NibOutletConnection(label: NibString("sceneViewController"), source: owner, destination: viewController)]
        return ["\(sceneController.nibName).nib": try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: Self.allObjects(topLevel),
                                                                                 connections: connections))]
    }

    /// A scene's controller of the given element name and its objects, its placeholders checked.
    func sceneObjects(_ scene: XIBElement, controller name: String, recognizers: Bool = false) throws -> (XIBElement, XIBElement) {
        try check(scene, attributes: ["sceneID"], children: ["objects", "point"])
        guard let objects = scene.children(named: "objects").first else { throw unsupportedScene("a scene without objects") }
        try check(objects, attributes: [], children: Set([name, "placeholder", "view", "exit"] + (recognizers ? NibGestureRecognizer.elements : [])))
        for exit in objects.children(named: "exit") {
            try check(exit, attributes: ["id", "userLabel", "sceneMemberID"], children: [])
            try value(exit, "sceneMemberID", in: ["exit"])
            try value(exit, "userLabel", in: ["Exit"])
        }
        let controllers = objects.children(named: name)
        guard controllers.count == 1, let controller = controllers.first else { throw unsupportedScene("a scene without one view controller") }
        for placeholder in objects.children(named: "placeholder") {
            try check(placeholder, attributes: ["placeholderIdentifier", "id", "sceneMemberID", "userLabel", "customClass"], children: [])
            try value(placeholder, "placeholderIdentifier", in: ["IBFirstResponder"])
            try value(placeholder, "customClass", in: ["UIResponder"])
            try value(placeholder, "sceneMemberID", in: ["firstResponder"])
            try value(placeholder, "userLabel", in: ["First Responder"])
        }
        try designTimeSettings(controller)
        try value(controller, "sceneMemberID", in: ["viewController"])
        return (controller, objects)
    }

    /// A view controller's view nib, its outlets to its scene's views compiled into it (all but
    /// those to `excluded` objects of the controller's nib, and segues).
    mutating func controllerView(_ controller: XIBElement, objects: XIBElement, owner: NibProxy, excluded: Set<String> = [],
                                         recognizer: SceneRecognizer? = nil, controlSegues: [Segue] = [])
        throws -> (nibName: String, nib: Data, usesUpstream: Bool, responder: NibProxy) {
        guard let id = controller.attributes["id"] else { throw unsupportedScene("a view controller without an id") }
        for guides in controller.children(named: "layoutGuides") {
            try check(guides, attributes: [], children: ["viewControllerLayoutGuide"])
            guard guides.children.map({ $0.attributes["type"] }) == ["top", "bottom"] else {
                throw unsupportedScene("layout guides other than one top and one bottom")
            }
            for guide in guides.children {
                try check(guide, attributes: ["type", "id"], children: [])
            }
        }
        let views = controller.children.filter { $0.name == (["tableViewController": "tableView", "collectionViewController": "collectionView"][controller.name] ?? "view") }
        guard views.count == 1, let viewElement = views.first, viewElement.attributes["key"] == "view", let viewID = viewElement.attributes["id"] else {
            throw unsupportedScene("a view controller without one view")
        }
        let viewNibName = "\(id)-view-\(viewID)"
        let responder = NibProxy(identifier: "IBFirstResponder")
        let upstream = NibProxy(identifier: "UpstreamPlaceholder-\(recognizer == nil ? 1 : 2)")
        upstreamIdentifier = upstream.identifier
        placeholders = [id: upstream]
        if let recognizer {
            placeholders[recognizer.id] = recognizer.placeholder
        }
        guard recognizer == nil || controlSegues.isEmpty else { throw unsupportedScene("buttons' segues beside a gesture recognizer") }
        controlSeguePlaceholders = controlSegues.map { ($0, NibProxy(identifier: "")) }
        for placeholder in objects.children(named: "placeholder") {
            if let placeholderID = placeholder.attributes["id"] {
                placeholders[placeholderID] = responder
            }
        }
        let outlets = XIBElement(name: controller.name, attributes: controller.attributes)
        outlets.children = controller.children.map { child in
            guard child.name == "connections" else { return child }
            let container = XIBElement(name: child.name, attributes: child.attributes)
            container.children = child.children.filter { $0.name != "segue" && !excluded.contains($0.attributes["destination"] ?? "") }
            return container
        }
        try connections(of: outlets, source: upstream)
        let (viewNib, usesUpstream) = try sceneViewNib(viewElement, layoutGuideIDs: controller.children(named: "layoutGuides").flatMap(\.children).compactMap { $0.attributes["id"] },
                                                       size: try embeddedSize(controller) ?? sceneSize, owner: owner, responder: responder,
                                                       upstream: upstream, recognizer: recognizer?.placeholder)
        return (viewNibName, viewNib, usesUpstream, responder)
    }

    /// The templates of the segues cells of the scene trigger, in their placeholders' order: from
    /// `UpstreamPlaceholder-2`, static cells last first, prototype cells first first, a cell's
    /// segues in document order whatever triggers them (`sb-cellseg-*`, `sb-cellseg-nav-root`,
    /// `sb-cellseg-accessory-*`, `sb-cellseg-prototypes-reversed-ids`, `sb-cellseg-static-two-both`).
    private mutating func cellSegueTemplates(_ sceneController: SceneController, _ templates: [NibSegueTemplate]) -> [(Segue, NibSegueTemplate)] {
        let cellTemplates = zip(sceneController.segues, templates).filter { $0.0.cell != nil }
        var cells: [String] = []
        for (segue, _) in cellTemplates where !cells.contains(segue.cell!) {
            cells.append(segue.cell!)
        }
        if !(cellTemplates.first?.0.prototype ?? true) {
            cells.reverse()
        }
        let ordered = cells.flatMap { cell in cellTemplates.filter { $0.0.cell == cell } }
        cellSeguePlaceholders = [:]
        for (number, (segue, _)) in ordered.enumerated() {
            cellSeguePlaceholders[segue.cell!, default: []].append((segue.accessory, NibProxy(identifier: "UpstreamPlaceholder-\(number + 2)")))
        }
        return ordered
    }

    /// The external objects a controller's view nib loads with: the controller, then the cells'
    /// segue templates by placeholder number; or the controller when the view refers to it, then
    /// the buttons' segue templates (`sb-button-*`).
    /// Their keys are the nib's strings, which a container's children share (the corpus's
    /// uncloudnotes CampgroundManager storyboards).
    mutating func externalObjects(_ controller: NibArchivable?, _ cellTemplates: [(Segue, NibSegueTemplate)],
                                  controlTemplates: [(Segue, NibSegueTemplate)] = []) -> [(NibArchivable, NibArchivable)] {
        let first: [(NibArchivable, NibArchivable)] = controller.map { [(string("UpstreamPlaceholder-1"), $0)] } ?? []
        return first + cellTemplates.enumerated().map { (string("UpstreamPlaceholder-\($0.offset + 2)"), $0.element.1) }
            + controlTemplates.enumerated().map { (string("UpstreamPlaceholder-\($0.offset + first.count + 1)"), $0.element.1) }
    }

    /// The templates' `viewController` outlets: by template class, byte by byte, those of one class
    /// last first (`sb-segorder-*`, `sb-button-two`, `sb-bar-popover-and-cell`; the corpus's
    /// uncloudnotes CreateNoteWithImages, a button's show and a bar button item's unwind segue).
    static func templateOutlets(_ templates: [NibSegueTemplate], controller: NibArchivable,
                                label: NibString) -> [NibOutletConnection] {
        templates.reversed().enumerated().sorted { left, right in
            let (a, b) = (Array(left.element.className.utf8), Array(right.element.className.utf8))
            return a == b ? left.offset < right.offset : a.lexicographicallyPrecedes(b)
        }.map { NibOutletConnection(label: label, source: $0.element, destination: controller) }
    }

    /// A scene's views beside its controller (`sb-extra-view*`, the corpus's tofu storyboard): top-level
    /// objects of the controller's nib in reverse document order, which the controller keeps alive in
    /// document order; their constraints compiled, their own connections and variations refused.
    private mutating func extraViews(_ elements: [XIBElement]) throws -> [(id: String, view: NibView)] {
        let views = try elements.map { element in
            guard let id = element.attributes["id"] else { throw unsupportedScene("a view without an id") }
            return (id, try view(element, topLevel: true))
        }
        try compileConstraints()
        guard pendingOutlets.isEmpty, traitStorages.isEmpty else {
            throw unsupportedScene("connections or variations in a view beside a scene's controller")
        }
        return views
    }

    /// A controller's outlets to objects of its own nib, by name (`sb-extra-view-two`, `sb-bar-*`);
    /// one without an id is dropped (`sb-conn-no-id`).
    private func controllerOutlets(_ controller: XIBElement, source: NibArchivable, destinations: [String: NibArchivable]) throws -> [NibOutletConnection] {
        var outlets: [NibOutletConnection] = []
        for container in controller.children(named: "connections") {
            for outlet in container.children(named: "outlet") {
                guard outlet.attributes["id"] != nil, let destination = destinations[outlet.attributes["destination"] ?? ""] else { continue }
                try check(outlet, attributes: ["property", "destination", "id"], children: [])
                outlets.append(NibOutletConnection(label: NibString(try property(outlet)), source: source, destination: destination))
            }
        }
        return outlets.sorted { Array($0.label.value.utf8).lexicographicallyPrecedes(Array($1.label.value.utf8)) }
    }

    /// A controller's `<navigationItem>`, if it declares one, read into `item`: its title, the nib's
    /// empty array as center item groups, its large-title mode, its left and right system or titled
    /// bar button items by id, and their actions, which must target the controller, and segues, by
    /// segue id (`sb-nav-item-*`, `sb-bar-*`).
    mutating func navigationItem(_ controller: XIBElement, into item: NibNavigationItem, empty: NibArray) throws
        -> (declared: Bool, barItems: [String: NibBarButtonItem], actions: [(selector: String, item: NibBarButtonItem, segue: String?)]) {
        let itemElements = controller.children(named: "navigationItem")
        guard let itemElement = itemElements.first else { return (false, [:], []) }
        try check(itemElement, attributes: ["key", "title", "largeTitleDisplayMode", "id"], children: ["barButtonItem"])
        guard itemElements.count == 1 else { throw unsupportedScene("a view controller of two navigation items") }
        item.title = itemElement.attributes["title"].map { text($0, id: itemElement.attributes["id"], property: "title") }
        item.centerItemGroups = empty
        let mode = itemElement.attributes["largeTitleDisplayMode"] ?? "automatic"
        guard let largeTitleDisplayMode = ["automatic": 0, "never": 2][mode] else { throw unsupported("largeTitleDisplayMode=\"\(mode)\"") }
        item.largeTitleDisplayMode = largeTitleDisplayMode
        var barItems: [String: NibBarButtonItem] = [:]
        var actions: [(selector: String, item: NibBarButtonItem, segue: String?)] = []
        for element in itemElement.children {
            try check(element, attributes: ["key", "systemItem", "title", "enabled", "style", "image", "catalog", "id"],
                      children: ["connections", "userDefinedRuntimeAttributes"])
            let system = try element.attributes["systemItem"].map { name in
                guard let system = NibBarButtonItem.systemItems[name] else { throw unsupportedScene("a bar button item of a system item not observed yet") }
                return system
            }
            guard let id = element.attributes["id"], (system == nil) != (element.attributes["title"] == nil) else {
                throw unsupportedScene("a bar button item without one system item or title")
            }
            let barItem = NibBarButtonItem(systemItem: system, enabled: try bool(element, "enabled", default: true))
            barItem.title = element.attributes["title"].map { text($0, id: id, property: "title") }
            barItem.style = try mapped(element.attributes["style"] ?? "plain", ["plain": 1, "done": 2], "style")
            barItem.image = try element.attributes["image"].map { name in
                guard barItem.title != nil else { throw unsupportedScene("an image bar button item without a title") }
                return try image(name, catalog: element.attributes["catalog"])
            }
            switch element.attributes["key"] {
            case "leftBarButtonItem" where item.left == nil: item.left = barItem
            case "rightBarButtonItem" where item.right == nil: item.right = barItem
            case "backBarButtonItem" where item.back == nil && system == nil && element.children.isEmpty: item.back = barItem
            default: throw unsupportedScene("a bar button item other than one left and one right")
            }
            barItems[id] = barItem
            try navigationRuntimeAttributes(of: element, object: barItem)
            for container in element.children(named: "connections") {
                try check(container, attributes: [], children: ["action", "segue"])
                for action in container.children {
                    if action.name == "segue" {
                        actions.append(("perform:", barItem, action.attributes["id"]))
                        continue
                    }
                    try check(action, attributes: ["selector", "destination", "id"], children: [])
                    guard let selector = action.attributes["selector"], action.attributes["destination"] == controller.attributes["id"] else {
                        throw unsupportedScene("an action of a bar button item to another object than its controller")
                    }
                    actions.append((selector, barItem, nil))
                }
            }
        }
        guard item.back == nil || item.left == nil && item.right == nil else {
            throw unsupportedScene("a back bar button item beside a left or right one")
        }
        return (true, barItems, actions)
    }

    /// A navigation controller with its root, as its own nib and a container's nib archive them: the
    /// navigation controller, its bar, the root controller with its navigation item, bar button
    /// items, segue templates and the views of its scene it keeps alive, and the root's view nib.
    struct InlinedNavigation {
        let navigation: NibNavigationController
        let root: NibRootViewController
        let rootElement: XIBElement
        let view: (nibName: String, nib: Data, usesUpstream: Bool, responder: NibProxy)
        let extras: [(id: String, view: NibView)]
        let barItems: [String: NibArchivable]
        /// The bar button items' actions and segues' `perform:` events, by selector, byte by byte
        /// (`sb-bar-segue-then-action`, `sb-bar-segue-then-zzz`).
        let actions: [NibEventConnection]
        /// Its popover templates' `anchorBarButtonItem` outlets (`sb-popover-bar-item`).
        let anchors: [NibOutletConnection]
    }

    /// A navigation controller's element and its root's scene inlined; in a container, without a
    /// title or scroll view insets of its own, and the root's empty external objects the container's.
    mutating func inlinedNavigation(_ navigation: XIBElement, swapsClass: Bool, rootScene: XIBElement, root rootController: SceneController,
                                    templates: [NibSegueTemplate], empty: NibArray, sharedExternals: NibDictionary?) throws -> InlinedNavigation {
        try checkNavigation(navigation, inContainer: sharedExternals != nil)
        let bar = try navigationBar(navigation)
        let rootKind = rootScene.children(named: "objects").first?.children(named: "tableViewController").isEmpty == false ? "tableViewController" : "viewController"
        let (controller, objects) = try sceneObjects(rootScene, controller: rootKind)
        try check(controller, attributes: ["id", "sceneMemberID", "customClass", "customModule", "customModuleProvider", "definesPresentationContext",
                                           "storyboardIdentifier", "clearsSelectionOnViewWillAppear", "userLabel"] + ControllerSettings.attributes,
                  children: ["layoutGuides", "view", "tableView", "connections", "navigationItem", "nil", "simulatedNavigationBarMetrics", "toolbarItems", "extendedEdge", "value"])
        try emptyToolbarItems(controller)
        let rootClass = rootKind == "tableViewController" ? "UITableViewController" : "UIViewController"
        let item = NibNavigationItem()
        let (declared, barItems, actions) = try navigationItem(controller, into: item, empty: empty)
        let cellTemplates = cellSegueTemplates(rootController, templates)
        let controlTemplates = zip(rootController.segues, templates).filter { $0.0.control != nil }
        let extraElements = objects.children(named: "view")
        let view = try controllerView(controller, objects: objects, owner: NibProxy(identifier: "IBFilesOwner"),
                                      excluded: Set(barItems.keys).union(extraElements.compactMap { $0.attributes["id"] }), controlSegues: controlTemplates.map(\.0))
        guard cellTemplates.isEmpty || view.usesUpstream else { throw unsupportedScene("cells' segues of a table view without outlets to its controller") }
        let extras = try extraViews(extraElements)
        let rootCustomClass = try customClass(controller, original: rootClass)
        let rootViewController = NibRootViewController(item: item, viewNibName: view.nibName, segueTemplates: templates, baseClass: rootClass,
                                                       customClass: rootCustomClass ?? (rootController.identifier == nil ? nil : (string(rootClass), string(rootClass))),
                                                       externalObjects: view.usesUpstream || !controlTemplates.isEmpty ? NibDictionary() : sharedExternals ?? NibDictionary())
        rootViewController.definesPresentationContext = try bool(controller, "definesPresentationContext", default: false)
        rootViewController.storyboardIdentifier = rootController.identifier.map { string($0) }
        rootViewController.title = controller.attributes["title"].map { text($0, id: controller.attributes["id"], property: "title") }
        // A root's title is also its undeclared navigation item's (`sb-vc-title-nav`).
        if !declared, let title = rootViewController.title {
            guard !localizable else { throw unsupportedScene("a navigation controller's root's title without a navigation item in a localized document") }
            item.title = title
        }
        rootViewController.keepsSelection = !(try bool(controller, "clearsSelectionOnViewWillAppear", default: true))
        rootViewController.keptAlive = extras.map(\.view)
        rootViewController.declaresItem = declared
        rootViewController.settings = try presentationSettings(controller)
        guard !rootViewController.keepsSelection || extras.isEmpty && !rootViewController.definesPresentationContext && rootController.identifier == nil
                && !rootViewController.settings.presents else {
            throw unsupportedScene("a navigation controller's root keeping its selection with objects kept alive, a presentation context or an identifier")
        }
        if view.usesUpstream || !controlTemplates.isEmpty {
            rootViewController.externalObjects.entries = externalObjects(view.usesUpstream ? rootViewController : nil, cellTemplates, controlTemplates: controlTemplates)
        }
        let navigationController = try self.navigationController(navigation, root: rootViewController, bar: bar, swapsClass: swapsClass, empty: empty)
        rootViewController.parent = navigationController
        item.bar = bar
        bar.items = [item]
        let anchorLabel = NibString("anchorBarButtonItem")
        let anchors = zip(rootController.segues, templates).compactMap { segue, template in
            segue.kind == .popoverPresentation ? segue.barItem.flatMap { barItems[$0] }.map { NibOutletConnection(label: anchorLabel, source: template, destination: $0) } : nil
        }
        return InlinedNavigation(navigation: navigationController, root: rootViewController, rootElement: controller, view: view, extras: extras,
                                 barItems: barItems, actions: Self.barItemEvents(actions, rootController, templates, controller: rootViewController),
                                 anchors: anchors)
    }

    /// A navigation controller's own attributes and children; in a container, without a title or
    /// scroll view insets of its own.
    func checkNavigation(_ navigation: XIBElement, inContainer: Bool) throws {
        try check(navigation, attributes: ["id", "sceneMemberID", "userLabel"] + (inContainer ? [] : ["automaticallyAdjustsScrollViewInsets", "title", "storyboardIdentifier"]),
                  children: Set(["navigationBar", "connections", "toolbarItems", "nil"] + (inContainer ? ["tabBarItem"] : ["toolbar"])))
        for child in navigation.children {
            switch child.name {
            case "toolbarItems": try check(child, attributes: [], children: [])
            case "nil": try value(child, "name", in: ["viewControllers"])
            default: continue
            }
        }
    }

    /// A navigation controller of a root and a bar, with its title, identifier and toolbar.
    mutating func navigationController(_ navigation: XIBElement, root: NibArchivable, bar: NibNavigationBar, swapsClass: Bool,
                                       empty: NibArray) throws -> NibNavigationController {
        let controller = NibNavigationController(root: root, bar: bar, swapsClass: swapsClass,
                                                 adjustsScrollViewInsets: try bool(navigation, "automaticallyAdjustsScrollViewInsets", default: true))
        controller.title = navigation.attributes["title"].map { text($0, id: navigation.attributes["id"], property: "title") }
        controller.storyboardIdentifier = navigation.attributes["storyboardIdentifier"].map { string($0) }
        controller.toolbar = try navigationToolbar(navigation, empty: empty)
        bar.delegate = controller
        return controller
    }

    /// A navigation controller whose root is a storyboard reference: the reference's navigation
    /// item is the bar's, and the reference has no `storyboard` outlet (`sb-ref-nav-root`,
    /// `sb-ref-tab-nav-root`); a reference without a navigation item is not observed.
    mutating func referenceNavigation(_ navigation: XIBElement, swapsClass: Bool, root: SceneController, empty: NibArray,
                                      inContainer: Bool) throws -> NibNavigationController {
        try checkNavigation(navigation, inContainer: inContainer)
        let bar = try navigationBar(navigation)
        guard root.reference?.item == true else { throw unsupportedScene("a navigation controller's root storyboard reference without a navigation item") }
        let item = NibNavigationItem()
        item.centerItemGroups = empty
        item.bar = bar
        bar.items = [item]
        let reference = NibStoryboardReference(identifier: string(root.nibName), item: item)
        let controller = try navigationController(navigation, root: reference, bar: bar, swapsClass: swapsClass, empty: empty)
        reference.parent = controller
        return controller
    }

    /// A navigation controller's scene with its root controller's (docs/formats/nib.md "Navigation
    /// controllers"): one nib of the navigation controller, its bar, the root controller and its
    /// navigation item, bar button items and segue templates, and the root's view nib.
    private mutating func compileNavigationScene(_ scene: XIBElement, controller sceneController: SceneController, rootScene: XIBElement,
                                                 root rootController: SceneController, templates: [NibSegueTemplate]) throws -> [String: Data] {
        let (navigation, _) = try sceneObjects(scene, controller: "navigationController")
        let empty = NibArray([])
        if rootController.reference != nil {
            let controller = try referenceNavigation(navigation, swapsClass: sceneController.isEntryPoint, root: rootController, empty: empty, inContainer: false)
            let owner = NibProxy(identifier: "IBFilesOwner")
            let placeholder = NibProxy(identifier: "UIStoryboardPlaceholder")
            let navigationPlaceholder = NibProxy(sharing: placeholder.identifier)
            let topLevel: [NibArchivable] = [placeholder, owner, NibProxy(identifier: "IBFirstResponder"), navigationPlaceholder, controller]
            let connections = [NibOutletConnection(label: NibString("storyboard"), source: controller, destination: navigationPlaceholder),
                               NibOutletConnection(label: NibString("sceneViewController"), source: owner, destination: controller)]
            let all = Self.allObjects(topLevel)
            keyValuePairs = navigationPairs
            navigationPairs = []
            return ["\(sceneController.nibName).nib": try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: all, connections: connections,
                                                                                     keyValuePairs: try takeKeyValuePairs(allObjects: all), empty: empty))]
        }
        let inlined = try inlinedNavigation(navigation, swapsClass: sceneController.isEntryPoint, rootScene: rootScene, root: rootController,
                                            templates: templates, empty: empty, sharedExternals: nil)
        let owner = NibProxy(identifier: "IBFilesOwner")
        let placeholder = NibProxy(identifier: "UIStoryboardPlaceholder")
        let navigationPlaceholder = NibProxy(sharing: placeholder.identifier)
        let topLevel: [NibArchivable] = [placeholder, owner, inlined.view.responder, navigationPlaceholder, inlined.navigation] + inlined.extras.reversed().map(\.view)
        let storyboard = NibString("storyboard")
        var connections: [NibArchivable] = [NibOutletConnection(label: storyboard, source: inlined.navigation, destination: navigationPlaceholder),
                                            NibOutletConnection(label: storyboard, source: inlined.root, destination: placeholder)]
        var destinations: [String: NibArchivable] = inlined.barItems
        for extra in inlined.extras {
            destinations[extra.id] = extra.view
        }
        let outlets = try controllerOutlets(inlined.rootElement, source: inlined.root, destinations: destinations)
        guard outlets.isEmpty || inlined.anchors.isEmpty else { throw unsupportedScene("a root's outlets beside a bar button item's popover segue") }
        connections += outlets + inlined.anchors
        connections.append(NibOutletConnection(label: NibString("sceneViewController"), source: owner, destination: inlined.navigation))
        connections += Self.templateOutlets(templates, controller: inlined.root, label: NibString("viewController"))
        connections += inlined.actions
        let all = Self.allObjects(topLevel)
        keyValuePairs = navigationPairs
        navigationPairs = []
        let nib = try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: all, connections: connections,
                                                 keyValuePairs: try takeKeyValuePairs(allObjects: all), empty: empty))
        return ["\(sceneController.nibName).nib": nib, "\(inlined.view.nibName).nib": inlined.view.nib]
    }

    /// The presentation settings of an archived child controller, written after its segue templates
    /// as a scene's controller's (`sb-nav-root-modal`, `sb-split-detail-modal`, `sb-tab-nav-root-modal`);
    /// its title is its own, a restoration identifier is not observed there.
    mutating func presentationSettings(_ controller: XIBElement) throws -> ControllerSettings {
        var settings = try controllerSettings(controller, storyboardIdentifier: nil)
        guard settings.restorationIdentifier == nil else { throw unsupportedScene("a restoration identifier of a navigation or container's child") }
        settings.title = nil
        return settings
    }

    /// A controller's `<toolbarItems/>`, which changes nothing when empty (`sb-vc-toolbar-items`,
    /// `sb-nav-root-toolbar-items`).
    private func emptyToolbarItems(_ controller: XIBElement) throws {
        for items in controller.children(named: "toolbarItems") {
            try check(items, attributes: [], children: [])
        }
    }

    /// Bar button items' actions to their controller and their segues' `perform:` events to their
    /// templates, by selector, byte by byte (`sb-bar-segue-then-action`, `sb-bar-segue-then-zzz`,
    /// `sb-standalone-bar-items`).
    static func barItemEvents(_ actions: [(selector: String, item: NibBarButtonItem, segue: String?)], _ sceneController: SceneController,
                              _ templates: [NibSegueTemplate], controller: NibArchivable) -> [NibEventConnection] {
        let templateOf = Dictionary(uniqueKeysWithValues: zip(sceneController.segues.map(\.id), templates))
        let events = actions.map { action in
            NibEventConnection(selector: NibString(action.selector), source: action.item, destination: action.segue.flatMap { templateOf[$0] } ?? controller)
        }
        return events.enumerated().sorted { left, right in
            let (a, b) = (Array(left.element.selector.value.utf8), Array(right.element.selector.value.utf8))
            return a == b ? left.offset < right.offset : a.lexicographicallyPrecedes(b)
        }.map(\.element)
    }

    /// A navigation controller's `<toolbar>`, IB's own, without a frame: 1000 x 54, centered at
    /// 500, 27, with the nib's empty array as items (`sb-nav-toolbar`; react-native-image-crop-picker's
    /// QBImagePicker storyboard).
    private mutating func navigationToolbar(_ navigation: XIBElement, empty: NibArray) throws -> NibNavigationToolbar? {
        let toolbars = navigation.children(named: "toolbar")
        guard let element = toolbars.first else { return nil }
        try check(element, attributes: ["key", "opaque", "clearsContextBeforeDrawing", "contentMode", "id"], children: ["autoresizingMask"])
        guard toolbars.count == 1, element.attributes["key"] == "toolbar", element.attributes["opaque"] == "NO",
              element.attributes["clearsContextBeforeDrawing"] == "NO", element.attributes["contentMode"] == "scaleToFill" else {
            throw unsupportedScene("a navigation controller's toolbar other than IB's")
        }
        for mask in element.children(named: "autoresizingMask") {
            try check(mask, attributes: ["key"], children: [])
        }
        return NibNavigationToolbar(hugging: string("{250, 250}"), items: empty)
    }

    /// A navigation controller's `<navigationBar>`, which IB lays out itself: centered 27 points
    /// below its document frame's origin.
    mutating func navigationBar(_ navigation: XIBElement) throws -> NibNavigationBar {
        let bars = navigation.children(named: "navigationBar")
        guard bars.count == 1, let barElement = bars.first, let rect = barElement.child("rect", key: "frame") else {
            throw unsupportedScene("a navigation controller without one navigation bar of a frame")
        }
        try check(barElement, attributes: ["key", "contentMode", "largeTitles", "id", "insetsLayoutMarginsFromSafeArea", "opaque", "clipsSubviews",
                                           "multipleTouchEnabled"], children: ["rect", "autoresizingMask", "userDefinedRuntimeAttributes"])
        try value(barElement, "contentMode", in: ["scaleToFill"])
        try check(rect, attributes: ["key", "x", "y", "width", "height"], children: [])
        for mask in barElement.children(named: "autoresizingMask") {
            try check(mask, attributes: ["key"], children: [])
        }
        let bar = NibNavigationBar(center: (try number(rect.attributes["x"] ?? "0", "x"), try number(rect.attributes["y"] ?? "0", "y") + 27),
                                   prefersLargeTitles: try bool(barElement, "largeTitles", default: false), hugging: string("{250, 250}"))
        bar.multipleTouchEnabled = try bool(barElement, "multipleTouchEnabled", default: false)
        bar.clipsToBounds = try bool(barElement, "clipsSubviews", default: false)
        bar.insetsLayoutMarginsFromSafeArea = try bool(barElement, "insetsLayoutMarginsFromSafeArea", default: true)
        _ = try bool(barElement, "opaque", default: true)
        try navigationRuntimeAttributes(of: barElement, object: bar)
        return bar
    }

    /// A scene's view nib: File's Owner, First Responder and the view, sized for the device, with
    /// the safe area guide of a document that uses safe areas, and the top and bottom layout guides
    /// ibtool adds as the view's last subviews, their constraints as its first, when the document
    /// does not use safe areas or the controller declares them. Constraints may name them as they
    /// name sibling subviews, the guides at the view's top and bottom edges, of no height
    /// (`sb-guide-*`; uncloudnotes' UnCloudNotes); all objects lists them as
    /// `DocumentCompiler.allObjects` does (`sb-subview`, `sb-safe-area`, `sb-image-view*`,
    /// `sb-safe-area-layout-guides`), and the owner's `view` outlet connects it. The controller's
    /// outlets come from `upstream`, a top-level placeholder after First Responder the controller
    /// nib names (`sb-controller-outlets`); whether the nib uses it.
    private mutating func sceneViewNib(_ element: XIBElement, layoutGuideIDs: [String], size: (width: Double, height: Double)?,
                                       owner: NibProxy, responder: NibProxy, upstream: NibProxy, recognizer: NibProxy? = nil) throws -> (Data, Bool) {
        guard element.attributes["translatesAutoresizingMaskIntoConstraints"] == nil else {
            throw unsupportedScene("translatesAutoresizingMaskIntoConstraints on a scene's view")
        }
        let viewElement = XIBElement(name: element.name, attributes: element.attributes.filter { $0.key != "key" })
        viewElement.children = element.children
        let view = try self.view(viewElement, topLevel: true)
        // A table or collection view controller's view may lack the guide in a document using safe
        // areas (`sb-tvc-safe-areas-*`, `sb-cvc-safe-areas-no-guide`).
        let tableOrCollection = view.kind.isTableView || view.kind.isCollection
        guard (view.safeAreaPlaceholder != nil) == usesSafeAreas || usesSafeAreas && tableOrCollection else {
            throw unsupportedScene(usesSafeAreas ? "useSafeAreas without one safe area layout guide" : "a safe area layout guide without useSafeAreas")
        }
        guard let frame = view.frame, frame.x == 0, frame.y == 0 else {
            throw unsupportedScene("a scene's view whose frame does not start at 0, 0")
        }
        var layoutGuides: [NibView] = []
        if !view.kind.isTableView, !view.kind.isCollection, !usesSafeAreas || !layoutGuideIDs.isEmpty {
            layoutGuides = NibView.viewControllerLayoutGuides(for: view)
            if let viewID = element.attributes["id"] {
                for (id, (guide, y)) in zip(layoutGuideIDs, zip(layoutGuides, [0, frame.height])) {
                    documentViews[id] = DocumentView(view: guide, frame: (0, y, frame.width, 0), parent: viewID, translates: true, hasMask: false)
                }
            }
        }
        try compileConstraints()
        if let size {
            try resize(view, to: size)
        }
        if !layoutGuides.isEmpty {
            view.subviews += layoutGuides
            view.guideConstraints = layoutGuides.flatMap { $0.layoutGuide!.constraintsToRemove }
        }
        let viewOutlet = NibOutletConnection(label: string("view"), source: owner, destination: view)
        let dataSource = staticDataSource.map { [$0 as NibArchivable] } ?? []
        staticDataSource = nil
        let segueOutlets = cellSegueOutlets
        let cellPlaceholders: [NibProxy] = cellSeguePlaceholders.values.flatMap { $0.map(\.placeholder) }
        let seguePlaceholders = cellPlaceholders.sorted { left, right in
            let (a, b) = (left.identifier.value, right.identifier.value)
            return a.utf8.count != b.utf8.count ? a.utf8.count < b.utf8.count : a < b
        }
        cellSegueOutlets = []
        cellSeguePlaceholders = [:]
        var connections = try outletConnections(allObjects: Self.allObjects([owner, responder, upstream, view] + dataSource), extra: [viewOutlet] + segueOutlets)
        if let source = dataSource.first {
            connections.insert(NibOutletConnection(label: string("staticDataSource"), source: owner, destination: source), at: 0)
        }
        let segueSlots = connections.indices.filter { index in segueOutlets.contains { $0 === connections[index] } }
        // By label, then by placeholder (`sb-cellseg-static-two-both`).
        for (slot, outlet) in zip(segueSlots, segueOutlets.sorted { left, right in
            guard left.label.value == right.label.value else { return Array(left.label.value.utf8).lexicographicallyPrecedes(Array(right.label.value.utf8)) }
            return seguePlaceholders.firstIndex { $0 === left.destination }! < seguePlaceholders.firstIndex { $0 === right.destination }!
        }) {
            connections[slot] = outlet
        }
        let usesUpstream = connections.contains { connection in
            [(connection as? NibOutletConnection)?.source, (connection as? NibOutletConnection)?.destination,
             (connection as? NibOutletCollectionConnection)?.source, (connection as? NibEventConnection)?.destination].contains { $0 === upstream }
        }
        // Buttons' segues' placeholders follow the controller's, when the view refers to it, in
        // document order (`sb-button-two*`, `sb-button-outlet`).
        let controlPlaceholders = controlSeguePlaceholders.map(\.placeholder)
        for (offset, placeholder) in controlPlaceholders.enumerated() {
            placeholder.identifier = NibString("UpstreamPlaceholder-\(offset + (usesUpstream ? 2 : 1))")
        }
        controlSeguePlaceholders = []
        let upstreams: [NibArchivable] = (usesUpstream ? [upstream] + seguePlaceholders : []) + controlPlaceholders
        let topLevel: [NibArchivable] = [owner, responder] + (recognizer.map { [$0] } ?? []) + upstreams + [view] + dataSource
        let allObjects = Self.allObjects(topLevel)
        return (try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: allObjects, connections: connections,
                                               accessibilityConfigurations: takeAccessibilityConfigurations(),
                                               traitStorageLists: try traitStorageLists(topLevel), keyValuePairs: try takeKeyValuePairs(allObjects: allObjects),
                                               empty: takeEmptyArray())),
                usesUpstream)
    }

    /// The size a controller's scene view takes: its freeform size, else its container view's when
    /// embedded (`sb-embed*`, `sb-embed-freeform`).
    private func embeddedSize(_ controller: XIBElement) throws -> (width: Double, height: Double)? {
        try freeformSize(controller) ?? controller.attributes["id"].flatMap { embeddedSizes[$0] }
    }

    /// A controller's freeform size, which its scene's view keeps whatever the device or the
    /// deployment target (nib-experiments `sb-freeform`, `sb-freeform-no-device`), when the view's
    /// frame has that size.
    private func freeformSize(_ controller: XIBElement) throws -> (width: Double, height: Double)? {
        let sizes = controller.children(named: "size")
        let metrics = !controller.children(named: "freeformSimulatedSizeMetrics").isEmpty
        guard !sizes.isEmpty else {
            guard !metrics else { throw unsupportedScene("freeform metrics without one freeform size") }
            return nil
        }
        guard sizes.count == 1, let size = sizes.first, size.attributes["key"] == "freeformSize" else {
            throw unsupportedScene("a controller's size other than one freeform size")
        }
        try check(size, attributes: ["key", "width", "height"], children: [])
        let width = try number(size.attributes["width"] ?? "", "width"), height = try number(size.attributes["height"] ?? "", "height")
        // A freeform size without freeform metrics sizes the view whatever its frame
        // (`sb-freeform-size-only*`; wikipedia's SavedProgressViewController).
        guard metrics else { return (width, height) }
        let frame = controller.children(named: "view").first?.child("rect", key: "frame")
        guard try frame.map({ (try number($0.attributes["width"] ?? "", "width"), try number($0.attributes["height"] ?? "", "height")) == (width, height) }) == true else {
            throw unsupportedScene("a freeform size other than its view's frame")
        }
        return (width, height)
    }

    /// The scene's view at `size`, its subviews resized by their autoresizing masks: each axis's
    /// change given to its one flexible part, whatever its length, or shared between two in
    /// proportion to their lengths (`sb-device-subview`, `-fixed`, `-both`,
    /// `sb-flutter-launch-*`). Results that are not whole points are rounded by a rule not
    /// observed yet (`sb-device-subview-fraction`), and refused, and so are subviews of a subview
    /// whose size changes.
    func resize(_ view: NibView, to size: (width: Double, height: Double), keepingOrigin: Bool = false) throws {
        guard let frame = view.frame, (frame.width, frame.height) != size else { return }
        view.frame = (keepingOrigin ? frame.x : 0, keepingOrigin ? frame.y : 0, size.width, size.height)
        for subview in view.subviews {
            guard let old = subview.frame else { continue }
            let mask = subview.autoresizingMask
            let horizontal = try share(size.width - frame.width, [(old.x, mask & 1 != 0), (old.width, mask & 2 != 0),
                                                                  (frame.width - old.x - old.width, mask & 4 != 0)])
            let vertical = try share(size.height - frame.height, [(old.y, mask & 8 != 0), (old.height, mask & 16 != 0),
                                                                  (frame.height - old.y - old.height, mask & 32 != 0)])
            guard (horizontal.1 == 0 && vertical.1 == 0) || subview.subviews.isEmpty else {
                throw unsupportedScene("autoresizing the subviews of a resized subview")
            }
            subview.frame = (old.x + horizontal.0, old.y + vertical.0, old.width + horizontal.1, old.height + vertical.1)
        }
    }

    /// The changes of an axis's margin and size: `delta` given to the flexible part, or shared
    /// between two in proportion to their lengths.
    private func share(_ delta: Double, _ parts: [(length: Double, flexible: Bool)]) throws -> (Double, Double) {
        guard delta != 0 else { return (0, 0) }
        let flexible = parts.filter(\.flexible)
        let total = flexible.map(\.length).reduce(0, +)
        guard flexible.count == 1 || (flexible.count == 2 && total > 0) else {
            throw unsupportedScene("autoresizing a subview with \(flexible.count) flexible parts in one direction")
        }
        let changes = parts.map { $0.flexible ? flexible.count == 1 ? delta : delta * $0.length / total : 0 }
        guard changes.allSatisfy({ $0 == $0.rounded() }) else {
            throw unsupportedScene("autoresizing a subview to fractions of a point")
        }
        return (changes[0], changes[1])
    }

    func unsupportedScene(_ what: String) -> NomacError {
        NomacError("nomac does not compile \(what) yet (BACKLOG B-261)", path: path)
    }
}

extension DocumentCompiler {
    /// The user-defined runtime attributes of a bar button item or navigation bar, which ibtool
    /// writes in the navigation controller's nib, not the root's view nib (`sb-udra-bar-item*`,
    /// `sb-udra-nav-bar`).
    mutating func navigationRuntimeAttributes(of element: XIBElement, object: NibArchivable) throws {
        let pending = keyValuePairs
        keyValuePairs = []
        try runtimeAttributes(of: element, object: object)
        navigationPairs += keyValuePairs
        keyValuePairs = pending
    }

    /// Refuses bar button items' and navigation bars' runtime attributes outside a navigation
    /// controller's nib, where they are not observed.
    func checkNoNavigationPairs() throws {
        guard navigationPairs.isEmpty else {
            throw unsupportedScene("user-defined runtime attributes of bar button items or navigation bars outside a navigation controller")
        }
    }
}
