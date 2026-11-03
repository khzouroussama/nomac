import Foundation
import NomacCore

/// Compiles an iOS `.xib` into a `.nib` as `ibtool --compile` does (docs/formats/nib.md). Every
/// element, attribute, value and option outside what the experiments observed stops it with an
/// error naming its BACKLOG item, so a nib is either Xcode's or not written (ADR 0251).
public enum XIBCompiler {
    /// The ibtool options a build passes that can change a nib.
    public struct Options: Sendable {
        /// `--module`.
        public var module: String?
        /// `--minimum-deployment-target`.
        public var minimumDeploymentTarget: String
        /// `--target-device`, once per device.
        public var targetDevices: [String]

        public init(module: String?, minimumDeploymentTarget: String, targetDevices: [String]) {
            self.module = module
            self.minimumDeploymentTarget = minimumDeploymentTarget
            self.targetDevices = targetDevices
        }
    }

    /// The deployment targets observed to give the same nibs: every iOS release from 8.0 to 26.2 and
    /// 27.0, by its last minor version (nib-experiments `deployment-*`). 7.0 writes a `~iphone.nib`
    /// bundle instead.
    static let releases = [8: 4, 9: 3, 10: 3, 11: 4, 12: 5, 13: 7, 14: 8, 15: 8, 16: 7, 17: 7, 18: 7, 26: 2, 27: 0]

    /// `--minimum-deployment-target` as `major.minor`, when it is one of `releases`.
    static func deploymentTarget(_ text: String) -> IOSVersion? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 2, let major = parts[0], let minor = parts[1], let last = releases[major], (0...last).contains(minor) else {
            return nil
        }
        return IOSVersion(major: major, minor: minor)
    }
    /// `devices-*`.
    static let targetDeviceSets: Set<Set<String>> = [["iphone"], ["ipad"], ["iphone", "ipad"]]
    /// The devices a document's `<device>` may name, all observed to give the same nibs (`device-*`);
    /// a storyboard sizes its scenes' views by them (`StoryboardCompiler.deviceSizes`).
    static let devices: Set<String> = ["retina3_5", "retina6_72", "retina4_0", "retina4_7", "retina5_5", "retina5_9", "retina6_0", "retina6_1",
                                       "retina6_12", "retina6_3", "retina6_5", "retina6_7", "retina6_9", "ipad9_7", "ipad11_0rounded",
                                       "ipad12_9rounded"]
    /// `<document>` attributes and the values observed (`tools-version-*`, `use-safe-areas`,
    /// `no-trait-collections`, `launch-screen`, `system-version-*`, `header-instantiation-direct`,
    /// `sb-instantiation-direct`); a nil value means any, observed with two or three.
    static let documentAttributes: [String: Set<String>?] = [
        "type": ["com.apple.InterfaceBuilder3.CocoaTouch.XIB"], "version": ["3.0"], "toolsVersion": nil, "systemVersion": nil,
        "targetRuntime": ["iOS.CocoaTouch"], "propertyAccessControl": ["none"], "useAutolayout": ["YES"],
        "useTraitCollections": ["YES"], "useSafeAreas": ["YES"], "launchScreen": ["YES"], "colorMatched": ["YES"],
        "customObjectInstantitationMethod": ["direct"],
    ]
    /// `<capability>` names observed in `<dependencies>` (`capabilities`).
    static let capabilities: Set<String> = ["documents saved in the Xcode 8 format", "Safe area layout guides",
                                            "System colors in document resources", "Named colors", "Constraints to layout margins",
                                            "Image references", "Aspect ratio constraints", "Stack View standard spacing",
                                            "collection view cell content view", "Constraints with non-1.0 multipliers"]

    /// The font files of a xib's or storyboard's `<customFonts>`, in document order, which ibtool writes
    /// as the partial Info.plist's `UIAppFonts` (nib-experiments `custom-fonts*`, `sb-custom-fonts`).
    public static func customFontFiles(_ data: Data, path: String) throws -> [String] {
        try XIBReader.read(data, path: path).children(named: "customFonts").flatMap(\.children).compactMap { $0.attributes["key"] }
    }

    /// The compiled nib of the document at `path`.
    public static func compile(_ data: Data, path: String, options: Options) throws -> Data {
        try compileReportingWarnings(data, path: path, options: options).nib
    }

    /// The nib and ibtool's document warnings, `<path>:global: warning: <message>` lines.
    public static func compileReportingWarnings(_ data: Data, path: String, options: Options) throws -> (nib: Data, warnings: [String]) {
        let deploymentTarget = try check(options, path: path)
        let document = try XIBReader.read(data, path: path)
        var compiler = DocumentCompiler(path: path, module: options.module, deploymentTarget: deploymentTarget)
        let nib = try compiler.compile(document)
        return (nib, compiler.deploymentWarning.map { ["\(path):global: warning: \($0)"] } ?? [])
    }

    /// Refuses the options the experiments have not observed, and returns the deployment target.
    static func check(_ options: Options, path: String) throws -> IOSVersion {
        guard let deploymentTarget = deploymentTarget(options.minimumDeploymentTarget) else {
            throw NomacError("nomac does not compile nibs for --minimum-deployment-target \(options.minimumDeploymentTarget) yet (BACKLOG B-263)", path: path)
        }
        guard targetDeviceSets.contains(Set(options.targetDevices)), Set(options.targetDevices).count == options.targetDevices.count else {
            throw NomacError("nomac does not compile nibs for --target-device \(options.targetDevices.joined(separator: ", ")) yet (BACKLOG B-263)", path: path)
        }
        return deploymentTarget
    }
}

/// An iOS version, `major.minor`.
struct IOSVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int

    static func < (lhs: IOSVersion, rhs: IOSVersion) -> Bool { (lhs.major, lhs.minor) < (rhs.major, rhs.minor) }

    var description: String { "\(major).\(minor)" }
}

/// What reads an Interface Builder document's elements into nib objects, for xibs and
/// storyboards alike.
struct DocumentCompiler {
    let path: String
    let module: String?
    let deploymentTarget: IOSVersion
    /// The iOS version the document's features need: below it ibtool writes each nib as a bundle of
    /// `objects-<version>+.nib` and a `runtime.nib` for older systems (B-263). Safe area guides need
    /// 11.0 and named colors 13.0 (nib-experiments `sb-launch-rn-at-*`, `sb-launch-expo-at-*`).
    var requiredVersion = IOSVersion(major: 8, minor: 0)
    /// Equal strings are one object across the document: class names, color names, texts, outlet
    /// names, image and font names, priorities (`same-custom-class`, `same-system-color-twice`,
    /// `strings-shared`); placeholders' identifiers are not.
    var strings: [String: NibString] = [:]
    /// Text views' attributed texts' attributes, by font, color and alignment.
    var textViewAttributes: [String: NibDictionary] = [:]
    /// Equal colors are one object, and so are equal fonts (`same-color-twice`, `label-two`).
    var colors: [String: NibColor] = [:]
    var fonts: [String: NibFont] = [:]
    /// The document's `<namedColor>` definitions.
    var namedColors: [String: XIBElement] = [:]
    /// A storyboard's: the size of its scenes' views (from its `<device>` or its deployment target;
    /// nil when they keep their frames), and whether it uses safe areas.
    var sceneSize: (width: Double, height: Double)?
    /// A storyboard's `<color key="tintColor">`, its global tint.
    var globalTint: XIBElement?
    /// Bar button items' and navigation bars' runtime attributes, for the navigation controller's nib.
    var navigationPairs: [NibKeyValuePair] = []
    /// A xib's top-level views without freeform simulated metrics.
    var simulatedViews: [NibView] = []
    var usesSafeAreas = false
    /// Whether the document has `colorMatched="YES"`; without it ibtool converts colors otherwise
    /// (nib-experiments `unmatched-*`).
    var colorMatched = true
    /// Whether the document is in an `.lproj` folder, whose texts are localizable (`label-lproj`).
    var localizable: Bool { (path as NSString).deletingLastPathComponent.hasSuffix(".lproj") }
    /// A storyboard's: its sRGB and gray colors' components keep 10 significant digits, but for named
    /// colors (nib-experiments `sb-precise-*` against `precise-*`, `sb-cw-*`; the corpus's catalog
    /// colors).
    var roundsInlineColors = false
    /// Image placeholders by image name, one object each (`image-view-two`).
    var images: [String: NibImage] = [:]
    /// The empty array of the nib being compiled, which its root and its toolbars' items share
    /// (`toolbar-empty`).
    var emptyArray = NibArray([])
    /// Button configurations' title attributes, one dictionary per font (`bc-two`).
    var titleAttributes: [String: NibDictionary] = [:]
    /// The user-defined runtime attributes of the nib being compiled.
    var keyValuePairs: [NibKeyValuePair] = []
    /// Whether the nib being compiled has a settled tie of constraints to several views (ADR 0253).
    var settledTies = false
    var accessibilityConfigurations: [NibAccessibilityConfiguration] = []
    /// The document's gesture recognizers by id, which outlets and outlet collections name.
    var gestureRecognizers: [String: NibArchivable] = [:]
    /// The document's views by id, their safe area guides' ids with their views' ids, and the
    /// constraints left to compile once every view is read.
    var documentViews: [String: DocumentView] = [:]
    var safeAreaGuides: [String: String] = [:]
    /// A scroll view's content and frame layout guides, by id, and the guides constraints name.
    var scrollGuides: [String: (owner: String, content: Bool)] = [:]
    var scrollGuideObjects: [String: NibScrollLayoutGuide] = [:]
    var pendingConstraints: [PendingConstraints] = []
    /// The document's placeholders and constraints by id, and the outlets left to compile once every
    /// object is read.
    var placeholders: [String: NibArchivable] = [:]
    var documentConstraints: [String: NibLayoutConstraint] = [:]
    var pendingOutlets: [PendingOutlets] = []
    /// The properties of the nib being compiled that vary by size class, and a storyboard's device's
    /// size classes, which pick the values objects take.
    var traitStorages: [TraitStorage] = []
    /// The `<mask>`s of the nib's views, by view id and size class, then their storages.
    var pendingMasks: [(owner: String, subviews: Bool, sizeClasses: SizeClasses, included: [String], excluded: [String])] = []
    var relationshipStorages: [NibRelationshipTraitStorage] = []
    var deviceSizeClasses: SizeClasses?
    /// The data source of a static table view of the nib being compiled.
    var staticDataSource: NibStaticDataSource?
    /// The placeholders of the segue templates cells of the scene trigger, by cell id, and the
    /// outlets of the static cells to them (`sb-cellseg-*`).
    /// The upstream placeholders of a cell's segues, by cell id, in their document order: whether
    /// the accessory triggers it, and its placeholder (`sb-cellseg-*`).
    var cellSeguePlaceholders: [String: [(accessory: Bool, placeholder: NibProxy)]] = [:]
    /// The upstream placeholders of a scene's buttons' segues, by segue id, in document order.
    var controlSeguePlaceholders: [(segue: Segue, placeholder: NibProxy)] = []
    /// ibtool's document warnings, by object id.
    var warnings: [(id: String, message: String)] = []
    /// ibtool's warning about the document's `<deployment version>`, for the whole document.
    var deploymentWarning: String?
    /// The sizes of the container views embedding controllers, by controller id (`sb-embed*`).
    var embeddedSizes: [String: (width: Double, height: Double)] = [:]
    var cellSegueOutlets: [NibOutletConnection] = []
    var upstreamIdentifier: NibString?
    /// Whether the last scene view nib numbered its controller before its gesture recognizer.
    var recognizerAfterController = false
    /// The controllers of a storyboard's other scenes, whose actions from this scene ibtool drops
    /// without a word (`sb-action-other-scene`, the corpus's tofu storyboard).
    var otherScenesControllers: Set<String> = []

    init(path: String, module: String?, deploymentTarget: IOSVersion) {
        self.path = path
        self.module = module
        self.deploymentTarget = deploymentTarget
    }

    mutating func requires(_ major: Int, _ minor: Int) {
        requiredVersion = max(requiredVersion, IOSVersion(major: major, minor: minor))
    }

    /// Refuses a document whose features need a later iOS than the deployment target.
    func checkRequiredVersion() throws {
        guard deploymentTarget >= requiredVersion else {
            throw NomacError("nomac does not compile nibs that need iOS \(requiredVersion) for --minimum-deployment-target \(deploymentTarget) yet (BACKLOG B-263)",
                             path: path)
        }
    }

    mutating func compile(_ document: XIBElement) throws -> Data {
        try header(document, attributes: XIBCompiler.documentAttributes)
        var topLevel: [NibArchivable] = []
        for child in document.children {
            switch child.name {
            case "device", "dependencies", "resources", "accessibilityOverrides":
                try headerElement(child)
            case "designables":
                try designables(child)
            case "customFonts":
                try customFonts(child)
            case "objects":
                try check(child, attributes: [], children: Set(["placeholder", "view", "stackView", "tableViewCell", "collectionViewCell", "collectionReusableView"]
                                                               + NibGestureRecognizer.elements))
                for object in child.children {
                    let compiled = try topLevelObject(object)
                    topLevel.append(compiled)
                    if object.name == "view", object.children(named: "freeformSimulatedSizeMetrics").isEmpty, let view = compiled as? NibView {
                        simulatedViews.append(view)
                    }
                }
            default:
                throw unsupported("<\(child.name)> in a document")
            }
        }
        if document.attributes["useSafeAreas"] != "YES", topLevel.contains(where: { ($0 as? NibView)?.safeAreaPlaceholder != nil }) {
            throw unsupported("a safe area layout guide without useSafeAreas")
        }
        try compileConstraints()
        try resizeToDevice(simulatedViews, document: document)
        try checkRequiredVersion()
        let all = Self.allObjects(topLevel)
        return try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: all, connections: try outletConnections(allObjects: all),
                                              accessibilityConfigurations: takeAccessibilityConfigurations(),
                                              traitStorageLists: try traitStorageLists(topLevel), keyValuePairs: try takeKeyValuePairs(allObjects: all),
                                              empty: emptyArray))
    }

    /// The nib's trait storage list, for the top-level object its varied objects are under, a static
    /// cell standing for one (docs/formats/nib.md "Variations"; the corpus's tofu storyboard). Its
    /// storages are those of a walk of the views, depth first from that object, a view writing its
    /// properties' storages, its subviews mask, its constraints mask, then its constraints' (all of
    /// them, then the installed ones again), the first constraint naming a view deeper than the
    /// subviews walking it (`masks-walk-*`), then its subviews; a cell walks its content view and that view's subviews
    /// (`masks-*`, `mask-cell-group`; wikipedia's ShareViewController, PageHistoryCountsViewController,
    /// WelcomeContainerViewController). A storage walked again is a new object.
    mutating func traitStorageLists(_ topLevel: [NibArchivable]) throws -> [NibArchivable] {
        defer {
            traitStorages = []
            relationshipStorages = []
        }
        guard !traitStorages.isEmpty || !relationshipStorages.isEmpty else { return [] }
        let varied = traitStorages.map(\.object) + relationshipStorages.map(\.owner)
        func contains(_ object: NibArchivable) -> Bool {
            Self.allObjects([object]).contains { candidate in varied.contains { $0 === candidate } }
        }
        let staticCells = topLevel.compactMap { $0 as? NibStaticDataSource }.flatMap { $0.sections.flatMap(\.cells) }
        let cells = staticCells.filter(contains), containing = topLevel.filter(contains)
        guard cells.count <= 1, containing.count == 1, let top = cells.first ?? containing.first else {
            throw unsupported("size-class variations under several top-level objects")
        }
        guard let view = top as? NibView else { throw unsupported("size-class variations under a top-level object other than a view") }
        var entries: [NibTraitStorageList.Entry] = []
        var reached = Set<ObjectIdentifier>()
        func emit(_ object: NibArchivable) {
            for storage in traitStorages where storage.object === object {
                entries.append(.attribute(storage))
            }
            for storage in relationshipStorages.filter({ $0.owner === object }).sorted(by: { $0.subviews && !$1.subviews }) {
                entries.append(.relationship(reached.insert(ObjectIdentifier(storage)).inserted ? storage : storage.copy()))
            }
        }
        func walk(_ view: NibView) {
            emit(view)
            let installed = view.constraints.filter { constraint in !view.excludedConstraints.contains { $0 === constraint } }
            var naming: [ObjectIdentifier: NibLayoutConstraint] = [:]
            for constraint in view.constraints {
                for item in [constraint.first] + [constraint.second?.item].compactMap({ $0 }) where naming[ObjectIdentifier(item)] == nil {
                    naming[ObjectIdentifier(item)] = constraint
                }
            }
            for constraint in view.constraints + installed {
                emit(constraint)
                for case let item as NibView in [constraint.first] + [constraint.second?.item].compactMap({ $0 })
                where item !== view && !view.subviews.contains(where: { $0 === item }) && naming[ObjectIdentifier(item)] === constraint {
                    walk(item)
                }
            }
            switch view.kind {
            case .cell(let cell): ([cell.contentView] + cell.contentView.subviews).forEach(walk)
            default: view.subviews.forEach(walk)
            }
        }
        walk(view)
        let emitted = entries.map { entry -> ObjectIdentifier in
            switch entry {
            case .attribute(let storage): ObjectIdentifier(storage.object)
            case .relationship(let storage): ObjectIdentifier(storage.owner)
            }
        }
        guard varied.allSatisfy({ emitted.contains(ObjectIdentifier($0)) }) else {
            throw unsupported("size-class variations of objects nomac's walk of the views does not reach")
        }
        return [NibTraitStorageList(topLevelObject: top, entries: entries)]
    }

    /// The size classes of a `<variation key>`.
    func sizeClasses(_ variation: XIBElement) throws -> SizeClasses {
        guard let key = variation.attributes["key"], let sizeClasses = SizeClasses.keys.first(where: { $0.0 == key })?.1 else {
            throw unsupported("<variation key=\"\(variation.attributes["key"] ?? "")\">")
        }
        return sizeClasses
    }

    /// All objects: breadth first from the top-level objects, each view followed by its
    /// `childObjects` (`nested-subviews`, `constraint-to-safe-area`), every object once. A view
    /// listed there that a constraint names comes right after that constraint's place instead, as
    /// its child: a view deeper than the subviews moves ahead (`deep-other-great`,
    /// `deep-other-grand-top-grand2-leading`); nothing else joins the list (safe areas, a legacy
    /// collection cell's content view: nextcloud's NCPhotoCell).
    static func allObjects(_ topLevel: [NibArchivable]) -> [NibArchivable] {
        func walk(movingAhead listed: Set<ObjectIdentifier>) -> [NibArchivable] {
            var all: [NibArchivable] = []
            var queue = topLevel[...]
            var queued = Set(topLevel.map(ObjectIdentifier.init))
            while let object = queue.popFirst() {
                all.append(object)
                var children = (object as? NibObjectChildren)?.childObjects ?? []
                if let constraint = object as? NibLayoutConstraint {
                    children = ([constraint.first] + [constraint.second?.item].compactMap { $0 }).filter { listed.contains(ObjectIdentifier($0)) }
                }
                for child in children where queued.insert(ObjectIdentifier(child)).inserted {
                    queue.append(child)
                }
            }
            return all
        }
        return walk(movingAhead: Set(walk(movingAhead: []).map(ObjectIdentifier.init)))
    }

    /// Refuses a `<document>` element or attribute value the experiments have not observed, and
    /// reads its `<namedColor>` resources.
    mutating func header(_ document: XIBElement, attributes allowed: [String: Set<String>?]) throws {
        guard document.name == "document" else { throw unsupported("<\(document.name)> as a document") }
        colorMatched = document.attributes["colorMatched"] == "YES"
        for (name, value) in document.attributes {
            guard let values = allowed[name] else { throw unsupported("the \(name) attribute of <document>") }
            if let values, !values.contains(value) { throw unsupported("\(name)=\"\(value)\"") }
        }
        guard document.attributes["type"] != nil else { throw unsupported("a document without a type") }
        for resources in document.children(named: "resources") {
            try check(resources, attributes: [], children: ["systemColor", "namedColor", "image"])
            for image in resources.children(named: "image") {
                try check(image, attributes: ["name", "catalog", "width", "height"], children: [])
            }
            for named in resources.children(named: "namedColor") {
                try check(named, attributes: ["name"], children: ["color"])
                guard let name = named.attributes["name"], let color = named.children.first else { throw unsupported("a namedColor without a color") }
                namedColors[name] = color
            }
        }
    }

    /// `<designables>`, IB's record of custom views' intrinsic content sizes, which changes nothing
    /// (nib-experiments `designable*`, `sb-designable`).
    func designables(_ element: XIBElement) throws {
        try check(element, attributes: [], children: ["designable"])
        for designable in element.children {
            try check(designable, attributes: ["name"], children: ["size"])
            for size in designable.children {
                try check(size, attributes: ["key", "width", "height"], children: [])
                try value(size, "key", in: ["intrinsicContentSize"])
            }
        }
    }

    /// `<customFonts>`, the font files IB found a document's named fonts in, which change no nib; the
    /// partial Info.plist lists them (`customFontFiles`; `custom-fonts*`, `sb-custom-fonts`).
    func customFonts(_ element: XIBElement) throws {
        try check(element, attributes: ["key"], children: ["array"])
        try value(element, "key", in: ["customFonts"])
        for array in element.children {
            try check(array, attributes: ["key"], children: ["string"])
        }
    }

    /// `<device>`, `<dependencies>`, `<resources>` and IB's dynamic type preview
    /// (`<accessibilityOverrides>`), none of which changes a xib's nib (`device-*`, `no-device`,
    /// `capabilities*`, `a11y-overrides-*`, `sb-a11y-overrides`).
    mutating func headerElement(_ element: XIBElement, deviceAttributes: [String] = ["id", "orientation", "appearance", "layout"]) throws {
        switch element.name {
        case "device":
            try check(element, attributes: deviceAttributes, children: ["adaptation"])
            try value(element, "id", in: XIBCompiler.devices)
            try value(element, "orientation", in: ["portrait", "landscape"])
            try value(element, "appearance", in: ["light", "dark"])
            try value(element, "layout", in: ["fullscreen"])
            for adaptation in element.children {
                try check(adaptation, attributes: ["id"], children: [])
                try value(adaptation, "id", in: ["fullscreen"])
            }
        case "dependencies":
            try dependencies(&deploymentWarning, element)
        case "accessibilityOverrides":
            try check(element, attributes: ["isEnabled", "dynamicTypePreference"], children: [])
        case "simulatedMetricsContainer":
            // Xcode 8's default simulated metrics change no storyboard's nibs, with or without a
            // <device>, its scenes' frames matching its screen or not (`sb-metrics-*`, round 62).
            try check(element, attributes: ["key"], children: ["simulatedStatusBarMetrics", "simulatedOrientationMetrics", "simulatedScreenMetrics"])
            try value(element, "key", in: ["defaultSimulatedMetrics"])
            for metrics in element.children {
                try check(metrics, attributes: ["key", "type"], children: [])
                switch metrics.name {
                case "simulatedStatusBarMetrics":
                    try value(metrics, "key", in: ["statusBar"])
                    guard metrics.attributes["type"] == nil else { throw unsupported("simulated status bar metrics of a type") }
                case "simulatedOrientationMetrics":
                    try value(metrics, "key", in: ["orientation"])
                    guard metrics.attributes["type"] == nil else { throw unsupported("simulated orientation metrics of a type") }
                default:
                    try value(metrics, "key", in: ["destination"])
                    try value(metrics, "type", in: ["retina4_7.fullscreen", "retina4"])
                }
            }
        default:
            break
        }
    }

    /// The plug-in (any version, two observed), the capabilities observed and `<deployment>`
    /// for iOS (`plugin-version`, `capabilities`, `capability-multipliers`, `deployment-ios`). Its `version` (major x 256 +
    /// minor x 16) changes no nib from 8.0 (2048) to 27.0 (6912); below 5888 ibtool warns
    /// (`document-version-*`, `sb-document-version-*`, round 58; gomap's QuestBuilder at 5376).
    func dependencies(_ deploymentWarning: inout String?, _ element: XIBElement) throws {
        try check(element, attributes: [], children: ["plugIn", "capability", "deployment", "development"])
        for child in element.children {
            switch child.name {
            case "plugIn":
                try check(child, attributes: ["identifier", "version"], children: [])
                try value(child, "identifier", in: ["com.apple.InterfaceBuilder.IBCocoaTouchPlugin"])
            case "capability":
                try check(child, attributes: ["name", "minToolsVersion"], children: [])
                try value(child, "name", in: XIBCompiler.capabilities)
            case "development":
                // Xcode 5's development version changes nothing (`development-xcode-5100`).
                try check(child, attributes: ["version", "identifier"], children: [])
                try value(child, "identifier", in: ["xcode"])
                try value(child, "version", in: ["5100"])
            default:
                try check(child, attributes: ["identifier", "version"], children: [])
                try value(child, "identifier", in: ["iOS"])
                guard let text = child.attributes["version"] else { continue }
                guard let version = Int(text), version >= 2048 else {
                    throw NomacError("nomac does not compile documents whose <deployment version=\"\(text)\"> is before iOS 8.0 (ibtool writes nib bundles) yet (BACKLOG B-263)",
                                     path: path)
                }
                guard version <= 6912 else { throw unsupported("<deployment version=\"\(text)\">") }
                if version < 5888 {
                    deploymentWarning = "This file is set to build for a version older than the deployment target. Functionality may be limited. [9]"
                }
            }
        }
    }

    /// File's Owner and First Responder, whose classes and modules change nothing
    /// (`owner-custom-class`, `owner-module*`, `no-first-responder-class`).
    mutating func topLevelObject(_ element: XIBElement) throws -> NibArchivable {
        switch element.name {
        case "placeholder":
            switch element.attributes["placeholderIdentifier"] {
            case "IBFilesOwner":
                try check(element, attributes: ["placeholderIdentifier", "id", "userLabel", "customClass", "customModule", "customModuleProvider"],
                          children: ["connections", "userDefinedRuntimeAttributes"])
            case "IBFirstResponder":
                try check(element, attributes: ["placeholderIdentifier", "id", "customClass"], children: [])
                try value(element, "customClass", in: ["UIResponder"])
            case let other:
                throw unsupported("the placeholder \(other ?? "without an identifier")")
            }
            let proxy = NibProxy(identifier: element.attributes["placeholderIdentifier"]!)
            if let id = element.attributes["id"] {
                placeholders[id] = proxy
            }
            try connections(of: element, source: proxy)
            try runtimeAttributes(of: element, object: proxy)
            return proxy
        case "tableViewCell":
            return try tableViewCell(element)
        case "collectionViewCell":
            return try collectionViewCell(element)
        case "collectionReusableView":
            return try collectionReusableView(element)
        case let name where NibGestureRecognizer.elements.contains(name):
            return try gestureRecognizer(element)
        default:
            return try view(element, topLevel: true)
        }
    }

    /// A view or an image view, with its subviews, constraints (compiled with the document's,
    /// `compileConstraints`) and, for a top-level view, its safe area guide. A xib's container
    /// view is a view (`container-*`). A view without a
    /// frame has 1000 x 1000 (`view-no-rect`). A subview that does not translate its mask into
    /// constraints writes so only once a constraint names it (`color-key-*-3-4`, `order-*`).
    mutating func view(_ element: XIBElement, topLevel: Bool, parent: String? = nil,
                       originalClassName: String? = nil) throws -> NibView {
        let imageView = element.name == "imageView", isLabel = element.name == "label", isTable = element.name == "tableView"
        let isButton = element.name == "button", isStack = element.name == "stackView", isScroll = element.name == "scrollView"
        let isEffect = element.name == "visualEffectView", isCollection = element.name == "collectionView"
        let kindAttributes = imageView ? ["image", "catalog", "adjustsImageSizeForAccessibilityContentSizeCategory"] : isLabel ? Self.labelAttributes : isButton ? ControlContent.attributes + ButtonContent.attributes
            : isStack ? StackContent.attributes : isTable ? TableContent.attributes : isScroll ? ScrollContent.attributes
            : isCollection ? CollectionContent.attributes
            : element.name == "navigationBar" ? ["translucent"] : element.name == "searchBar" ? SearchBarContent.attributes
            : element.name == "datePicker" ? ["contentHorizontalAlignment", "contentVerticalAlignment", "datePickerMode", "minuteInterval", "useCurrentDate"]
            : Self.controlAttributes[element.name] ?? []
        try check(element, attributes: Self.viewAttributes + kindAttributes + ["customClass", "customModule", "customModuleProvider"],
                  children: Set(["rect", "autoresizingMask", "subviews", "point", "color", "constraints", "connections",
                                 "freeformSimulatedSizeMetrics", "nil", "edgeInsets", "directionalEdgeInsets", "viewLayoutGuide", "simulatedNavigationBarMetrics",
                                 "userDefinedRuntimeAttributes", "accessibility", "gestureRecognizers", "attributedString"]
                                + (isLabel ? ["fontDescription", "string", "variation", "attributedString"] : [])
                                + (imageView ? ["imageReference", "preferredSymbolConfiguration"] : [])
                                + (element.name == "toolbar" ? ["items"] : []) + (element.name == "wkWebView" ? ["wkWebViewConfiguration"] : [])
                                + (element.name == "navigationBar" ? ["items"] : []) + (isTable ? ["prototypes", "sections", "inset", "refreshControl"] : [])
                                + (isButton ? ["fontDescription", "state", "inset", "buttonConfiguration"] : []) + (element.name == "segmentedControl" ? ["segments"] : [])
                                + (isEffect ? ["view", "blurEffect"] : []) + (element.name == "textField" ? ["fontDescription", "textInputTraits", "string"] : [])
                                + (element.name == "textView" ? ["fontDescription", "textInputTraits", "string", "dataDetectorType"] : [])
                                + (element.name == "searchBar" ? ["textInputTraits"] : [])
                                + (isCollection ? ["collectionViewFlowLayout", "collectionViewLayout", "cells"] : [])
                                + (isLabel ? [] : ["variation"])))
        if !isLabel {
            try designTimeSettings(element)
        }
        var flags = NibView.Flags()
        flags.opaque = try bool(element, "opaque", default: true)
        flags.hidden = try bool(element, "hidden", default: false)
        flags.tag = try element.attributes["tag"].map { try integer($0, "tag") }
        flags.userInteractionDisabled = !(try bool(element, "userInteractionEnabled", default: true))
        flags.multipleTouchEnabled = try bool(element, "multipleTouchEnabled", default: false)
        flags.autoresizesSubviews = try bool(element, "autoresizesSubviews", default: true)
        flags.alpha = try element.attributes["alpha"].flatMap { text in
            guard let alpha = Float(text) else { throw unsupported("alpha=\"\(text)\"") }
            return alpha == 1 ? nil : alpha
        }
        flags.clipsToBounds = try bool(element, "clipsSubviews", default: false)
        flags.clearsContextBeforeDrawing = try bool(element, "clearsContextBeforeDrawing", default: true)
        if !flags.clearsContextBeforeDrawing, flags.alpha != nil {
            throw unsupported("clearsContextBeforeDrawing with an alpha")
        }
        let hugging = try ["horizontalHuggingPriority", "verticalHuggingPriority"].map { name in
            try element.attributes[name].map { try integer($0, name) } ?? 250
        }
        let infoButton = element.name == "button" && ["infoLight", "infoDark"].contains(element.attributes["buttonType"] ?? "")
        if hugging != (infoButton ? [750, 750] : Self.defaultContentHugging[element.name] ?? [250, 250]) {
            flags.contentHugging = string("{\(hugging[0]), \(hugging[1])}")
        }
        let resistance = try ["horizontalCompressionResistancePriority", "verticalCompressionResistancePriority"].map { name in
            try element.attributes[name].map { try integer($0, name) } ?? 750
        }
        if resistance != [750, 750] {
            flags.compressionResistance = string("{\(resistance[0]), \(resistance[1])}")
        }
        flags.insetsLayoutMarginsFromSafeArea = try bool(element, "insetsLayoutMarginsFromSafeArea", default: true)
        flags.preservesSuperviewLayoutMargins = try bool(element, "preservesSuperviewLayoutMargins", default: false)
        let translates = try bool(element, "translatesAutoresizingMaskIntoConstraints", default: true)
        flags.doesNotTranslateAutoresizingMask = topLevel && !translates
        flags.contentMode = try mapped(element.attributes["contentMode"] ?? "scaleToFill", NibView.contentModes, "contentMode")
        flags.semanticContentAttribute = try named(element.attributes["semanticContentAttribute"] ?? "unspecified",
                                                   in: NibView.semanticContentAttributes, "semanticContentAttribute")
        var frame = NibView.frameWithoutRect
        if let rect = element.child("rect", key: "frame") {
            try check(rect, attributes: ["key", "x", "y", "width", "height"], children: [])
            frame = (x: try number(rect.attributes["x"] ?? "0", "x"), y: try number(rect.attributes["y"] ?? "0", "y"),
                     width: try number(rect.attributes["width"] ?? "0", "width"), height: try number(rect.attributes["height"] ?? "0", "height"))
        }
        guard frame.width != 0 || frame.height != 0 || frame.x != 0 || frame.y != 0 else {
            throw unsupported("a view of no size at 0, 0")
        }
        flags.contentStretch = try contentStretch(element)
        var mask = NibView.defaultAutoresizingMask
        var hasMask = false
        for child in element.children {
            switch (child.name, child.attributes["key"]) {
            case ("rect", "frame"), ("rect", "contentStretch"), ("point", "canvasLocation"), ("subviews", nil), ("color", "backgroundColor"), ("constraints", nil),
                 ("viewLayoutGuide", "safeArea"), ("connections", nil), ("freeformSimulatedSizeMetrics", _), ("nil", _), ("simulatedNavigationBarMetrics", _),
                 ("fontDescription", "fontDescription"), ("color", "textColor"), ("color", "highlightedColor"), ("string", "text"), ("string", "placeholder"),
                 ("color", "separatorColor") where isTable, ("color", "sectionIndexBackgroundColor") where isTable,
                 ("variation", _), ("prototypes", nil), ("sections", nil), ("color", "tintColor"), ("state", _), ("inset", _), ("buttonConfiguration", "configuration"),
                 ("edgeInsets", "layoutMargins"), ("directionalEdgeInsets", "directionalLayoutMargins"), ("viewLayoutGuide", "contentLayoutGuide"),
                 ("viewLayoutGuide", "frameLayoutGuide"), ("segments", nil), ("view", "contentView"), ("blurEffect", nil), ("collectionViewFlowLayout", "collectionViewLayout"),
                 ("collectionViewLayout", "collectionViewLayout"), ("cells", nil),
                 ("userDefinedRuntimeAttributes", nil), ("accessibility", "accessibilityConfiguration"), ("textInputTraits", "textInputTraits"),
                 ("dataDetectorType", "dataDetectorTypes"), ("imageReference", "image"),
                 ("preferredSymbolConfiguration", "preferredSymbolConfiguration"), ("items", nil), ("refreshControl", "refreshControl"),
                 ("wkWebViewConfiguration", "configuration"):
                continue
            case ("color", _) where Self.controlAttributes[element.name] != nil:
                continue
            case ("gestureRecognizers", nil):
                try check(child, attributes: [], children: [])
            case ("attributedString", "attributedText") where isLabel:
                continue
            case ("attributedString", "userComments"):
                try check(child, attributes: ["key"], children: ["fragment"])
                for fragment in child.children {
                    try check(fragment, attributes: ["content"], children: [])
                }
            case ("autoresizingMask", "autoresizingMask"):
                try check(child, attributes: ["key"] + NibView.autoresizingBits.keys, children: [])
                hasMask = true
                mask = 0
                for (name, bit) in NibView.autoresizingBits {
                    if try bool(child, name, default: false) { mask |= bit }
                }
            default:
                throw unsupported("<\(child.name)\(child.attributes["key"].map { " key=\"\($0)\"" } ?? "")> in a view")
            }
        }
        if flags.doesNotTranslateAutoresizingMask {
            mask = NibView.defaultAutoresizingMask
        }
        guard let id = element.attributes["id"] else { throw unsupported("a view without an id") }
        var subviews: [NibView] = []
        for container in element.children(named: "subviews") {
            try check(container, attributes: [], children: Set(["view", "imageView", "label", "tableView", "button", "stackView", "scrollView", "visualEffectView", "collectionView",
                                                                "containerView", "toolbar", "wkWebView", "navigationBar", "datePicker", "pickerView", "searchBar"]
                                                               + Self.controlAttributes.keys))
            for child in container.children {
                subviews.append(try view(child, topLevel: false, parent: id))
            }
        }
        let background = try element.child("color", key: "backgroundColor").map { try color($0) }
        let view = NibView(frame: frame, autoresizingMask: mask, flags: flags, subviews: subviews, backgroundColor: background,
                           customClass: try customClass(element, original: originalClassName ?? Self.originalClassNames[element.name] ?? "UIView"))
        view.isImageView = imageView
        view.adjustsImageSizeForAccessibility = try imageView && bool(element, "adjustsImageSizeForAccessibilityContentSizeCategory", default: false)
        view.tintColor = try element.child("color", key: "tintColor").map { try color($0) }
        view.restorationIdentifier = element.attributes["restorationIdentifier"].map { string($0) }
        if let margins = try layoutMargins(element) {
            view.layoutMargins = margins.margins
            view.flags.layoutMarginsAreDirectional = margins.directional
        }
        view.flags.layoutMarginsFollowReadableWidth = try bool(element, "layoutMarginsFollowReadableWidth", default: false)
        try controlKind(element, view: view, frame: frame)
        if isEffect {
            view.kind = .effect(try effectContent(element, id: id))
            view.flags.shouldNotAdaptToMaterials = true
        }
        if isCollection {
            view.kind = .collection(try collectionContent(element))
        }
        if element.name == "toolbar" {
            try toolbar(element, view: view)
        }
        if element.name == "searchBar" {
            try searchBar(element, view: view)
        }
        if element.name == "datePicker" {
            try datePicker(element, view: view)
        }
        if element.name == "pickerView" {
            try pickerView(element, view: view)
        }
        if element.name == "navigationBar" {
            try navigationBar(element, view: view)
        }
        if element.name == "wkWebView" {
            view.kind = .webView(try webViewContent(element))
        }
        if element.name == "textView" {
            let textView = try textViewContent(element)
            view.kind = .textView(textView)
            view.flags.clipsToBounds = flags.clipsToBounds && textView.scroll.scrollEnabled
        }
        if isCollection || element.name == "textView", let background = view.backgroundColor, background.name != nil,
           background.components == .gray(white: 1, alpha: 1) {
            view.backgroundColor = systemColor("systemBackgroundColor", background.components)
        }
        if isScroll {
            view.kind = .scroll(try scrollContent(element))
            view.layoutGuidePlaceholders = element.children(named: "viewLayoutGuide").map { _ in NibSafeAreaGuide(identifier: string("")) }
            for guide in element.children(named: "viewLayoutGuide") {
                guard let key = guide.attributes["key"], ["contentLayoutGuide", "frameLayoutGuide"].contains(key), let guideID = guide.attributes["id"] else { continue }
                scrollGuides[guideID] = (id, key == "contentLayoutGuide")
            }
        }
        if isButton {
            let button = try buttonContent(element)
            view.kind = .button(button)
            if button.imageOnly, flags.contentHugging == nil, !infoButton {
                view.flags.contentHugging = string("{250, 250}")
            }
        }
        if isLabel {
            var label = try self.label(element)
            let variations = try element.children(named: "variation").map { variation in
                try check(variation, attributes: ["key"], children: ["fontDescription"])
                return (try sizeClasses(variation), try font(variation).font)
            }
            if !variations.isEmpty {
                traitStorages.append(TraitStorage(object: view, keyPath: string("font"), variations: variations.map { ($0.0, .object($0.1)) },
                                                  defaultValue: .object(label.font)))
                label.font = TraitStorage.value(variations, default: label.font, device: deviceSizeClasses)
            }
            view.label = label
        }
        if element.name == "textField" || element.name == "switch" {
            let colors = element.name == "switch" ? ["backgroundColor", "onTintColor", "thumbTintColor"] : ["backgroundColor", "textColor"]
            guard element.children(named: "color").allSatisfy({ colors.contains($0.attributes["key"] ?? "") }) else {
                throw unsupported("colors of a \(element.name) other than its background")
            }
        }
        if element.name == "textField" {
            view.kind = .textField(try textField(element))
        }
        if element.name == "switch" {
            guard try contentHorizontalAlignment(element) == 0 else { throw unsupported("a switch's horizontal alignment other than center") }
            view.kind = .switch(on: try bool(element, "on", default: false), onTint: try element.child("color", key: "onTintColor").map { try color($0) },
                                thumbTint: try element.child("color", key: "thumbTintColor").map { try color($0) })
            try switchFramePair(view)
        }
        if isTable {
            var table = try tableContent(element)
            table.refreshControl = try element.children(named: "refreshControl").first.map { try refreshControl($0) }
            guard table.refreshControl == nil || table.keyboardDismissMode == nil else {
                throw unsupported("a table view's refresh control beside a keyboard dismiss mode")
            }
            view.kind = .tableView(table)
            if view.backgroundColor == nil, view.kind.groupedTable {
                view.backgroundColor = try color(XIBElement(name: "color", attributes: ["systemColor": "systemGroupedBackgroundColor"]))
            } else if let background = view.backgroundColor, background.name != nil, background.components == .gray(white: 1, alpha: 1),
                      !view.kind.groupedTable {
                view.backgroundColor = systemColor("tableBackgroundColor", background.components)
            }
        }
        if let name = element.attributes["image"] {
            view.image = try image(name, catalog: element.attributes["catalog"])
        }
        if imageView {
            view.image = try symbolImage(element) ?? view.image
            view.preferredSymbolConfiguration = try preferredSymbolConfiguration(element, key: "preferredSymbolConfiguration")
            guard view.preferredSymbolConfiguration == nil || !view.adjustsImageSizeForAccessibility else {
                throw unsupported("an image view's preferred symbol configuration with accessibility sizing")
            }
            if view.preferredSymbolConfiguration != nil {
                view.flags.opaque = false
            }
        }
        for guide in element.children(named: "viewLayoutGuide") where guide.attributes["key"] == "safeArea" {
            try check(guide, attributes: ["key", "id"], children: [])
            guard let guideID = guide.attributes["id"], view.safeAreaPlaceholder == nil else { throw unsupported("a view with two safe areas") }
            view.safeAreaPlaceholder = NibSafeAreaGuide(identifier: string(""))
            requires(11, 0)
            safeAreaGuides[guideID] = id
        }
        documentViews[id] = DocumentView(view: view, frame: frame, parent: parent, translates: translates, hasMask: hasMask)
        if !isLabel {
            try masks(element, owner: id)
        }
        if isStack {
            var content = try stackContent(element, id: id, subviews: subviews)
            try stackVariations(element, view: view, content: &content)
            view.kind = .stack(content)
        }
        for container in element.children(named: "constraints") {
            try check(container, attributes: [], children: ["constraint"])
            pendingConstraints.append(PendingConstraints(owner: id, elements: container.children))
        }
        try connections(of: element, source: view)
        try runtimeAttributes(of: element, object: view)
        try accessibility(of: element, object: view)
        return view
    }

    /// The attributes every kind of view takes: a view's, priorities, and what IB keeps for itself
    /// (`fixedFrame`, `ambiguous`, `misplaced`, `userLabel`, placeholder sizes, `simulatedAppContext`:
    /// `label-fixed-frame`, `label-ambiguous`, `misplaced-*`, `label-user-label`,
    /// `label-placeholder-height`, `sb-app-context`).
    static let viewAttributes = ["id", "contentMode", "opaque", "hidden", "tag", "userInteractionEnabled", "multipleTouchEnabled",
                                 "autoresizesSubviews", "alpha", "clipsSubviews", "translatesAutoresizingMaskIntoConstraints",
                                 "semanticContentAttribute", "clearsContextBeforeDrawing", "horizontalHuggingPriority", "verticalHuggingPriority",
                                 "horizontalCompressionResistancePriority", "verticalCompressionResistancePriority",
                                 "insetsLayoutMarginsFromSafeArea", "preservesSuperviewLayoutMargins", "layoutMarginsFollowReadableWidth", "restorationIdentifier", "fixedFrame", "ambiguous", "misplaced", "userLabel", "placeholderIntrinsicWidth",
                                 "placeholderIntrinsicHeight", "simulatedAppContext"]
    /// The class a view with a custom class names as its original (`view-custom-class`,
    /// `label-custom-class*`, `image-view-custom-class-module`, `button-custom-class*`, `stack-custom-class`; text fields and
    /// switches: the corpus's pocket-casts FilterDownloadCell and wikipedia ReadingListDetailHeaderView).
    static let originalClassNames = ["label": "UILabel", "imageView": "UIImageView", "tableView": "UITableView", "button": "UIButton",
                                     "stackView": "UIStackView", "scrollView": "UIScrollView", "activityIndicatorView": "UIActivityIndicatorView",
                                     "segmentedControl": "UISegmentedControl", "progressView": "UIProgressView", "pageControl": "UIPageControl",
                                     "slider": "UISlider", "visualEffectView": "UIVisualEffectView", "textField": "UITextField", "switch": "UISwitch",
                                     "collectionView": "UICollectionView", "textView": "UITextView", "wkWebView": "WKWebView",
                                     "datePicker": "UIDatePicker", "pickerView": "UIPickerView"]
    /// The controls compiled by `controlKind`, and the attributes each takes besides a view's.
    static let controlAttributes = ["activityIndicatorView": ActivityContent.attributes, "segmentedControl": SegmentedContent.attributes,
                                    "progressView": ProgressContent.attributes, "pageControl": PageContent.attributes, "slider": SliderContent.attributes,
                                    "textField": textFieldAttributes, "switch": switchAttributes,
                                    "textView": TextViewContent.attributes]
    /// The content hugging priorities a view writes none for: 250 but for activity indicators and
    /// progress views (`activity-hugging`, `activity-no-hugging`, `progress-no-hugging`), switches
    /// (`sw-*`) and info buttons, 750 (`button-info-hugging-*`).
    static let defaultContentHugging = ["activityIndicatorView": [750, 750], "progressView": [250, 750], "switch": [750, 750]]
    static let labelAttributes = ["text", "usesAttributedText", "textAlignment", "lineBreakMode", "baselineAdjustment", "adjustsFontSizeToFit", "minimumScaleFactor",
                                  "minimumFontSize", "numberOfLines", "enabled", "highlighted", "adjustsLetterSpacingToFitWidth",
                                  "preferredMaxLayoutWidth", "adjustsFontForContentSizeCategory"]

    /// A label's content (docs/formats/nib.md "UILabel"): `textAlignment` left when absent,
    /// `baselineAdjustment` alignCenters when absent, `adjustsFontSizeToFit` unless "NO", a
    /// `nil` text color the system `labelColor` (`label-*`).
    mutating func label(_ element: XIBElement) throws -> LabelContent {
        let attributes = element.attributes
        var attributed: AttributedLabelText?
        if try bool(element, "usesAttributedText", default: false) {
            guard attributes["text"] == nil, attributes["textAlignment"] == nil, element.children(named: "string").isEmpty,
                  element.children(named: "fontDescription").isEmpty, element.child("color", key: "textColor") == nil,
                  element.child("nil", key: "textColor") == nil else {
                throw unsupported("an attributed label with a plain text, alignment, font or text color")
            }
            attributed = try attributedLabelText(element, lineBreakMode: try mapped(attributes["lineBreakMode"] ?? "tailTruncation",
                                                                                    LabelContent.lineBreakModes, "lineBreakMode"))
        }
        let font = try attributed?.font ?? self.font(element)
        let textColor: NibColor
        let documentColor: Bool
        switch (element.child("nil", key: "textColor"), element.child("color", key: "textColor")) {
        case _ where attributed != nil:
            textColor = try attributed?.color ?? color(XIBElement(name: "color", attributes: ["systemColor": "labelColor"]))
            documentColor = false
        case (_?, nil):
            textColor = try color(XIBElement(name: "color", attributes: ["systemColor": "labelColor"]))
            documentColor = false
        case (nil, nil):
            textColor = try color(XIBElement(name: "color", attributes: ["systemColor": "labelColor"]))
            documentColor = true
        case (nil, let color?):
            textColor = try self.color(color)
            documentColor = true
        default:
            throw unsupported("a label with two text colors")
        }
        let highlighted: NibColor?
        switch (element.child("nil", key: "highlightedColor"), element.child("color", key: "highlightedColor")) {
        case (_?, nil): highlighted = nil
        case (nil, nil): highlighted = try color(XIBElement(name: "color", attributes: ["cocoaTouchSystemColor": "blackColor"]))
        case (nil, let color?): highlighted = try self.color(color)
        default: throw unsupported("a label with two highlighted colors")
        }
        for child in element.children(named: "nil") where !["textColor", "highlightedColor"].contains(child.attributes["key"] ?? "") {
            throw unsupported("<nil key=\"\(child.attributes["key"] ?? "")\"> in a label")
        }
        let texts = element.children(named: "string")
        guard texts.count <= (attributes["text"] == nil ? 1 : 0) else { throw unsupported("a label with two texts") }
        for text in texts {
            try check(text, attributes: ["key"], children: [])
        }
        var content = LabelContent(font: font.font, textColor: textColor, textAlignment: 0, disablesTextColorUpdate: documentColor)
        if let text = attributes["text"] ?? texts.first?.text {
            content.text = self.text(text, id: attributes["id"], property: "text")
        }
        if let attributed {
            content.text = string(attributed.text)
            content.attributedText = attributed.attributedText
        }
        content.highlightedColor = highlighted
        content.adjustsFontForContentSizeCategory = try bool(element, "adjustsFontForContentSizeCategory", default: false)
        content.textAlignment = try attributed?.alignment ?? attributes["textAlignment"].map { try mapped($0, LabelContent.textAlignments, "textAlignment") } ?? 0
        let lineBreak = try attributes["lineBreakMode"].map { try mapped($0, LabelContent.lineBreakModes, "lineBreakMode") } ?? 4
        content.lineBreakMode = lineBreak == 4 ? nil : lineBreak
        let baseline = try attributes["baselineAdjustment"].map { try mapped($0, LabelContent.baselineAdjustments, "baselineAdjustment") } ?? 1
        content.baselineAdjustment = baseline == 0 ? nil : baseline
        content.numberOfLines = try attributes["numberOfLines"].map { try integer($0, "numberOfLines") }.flatMap { $0 == 1 ? nil : $0 }
        content.enabled = try bool(element, "enabled", default: true)
        _ = try bool(element, "highlighted", default: false)
        content.adjustsLetterSpacingToFit = try bool(element, "adjustsLetterSpacingToFitWidth", default: false)
        content.preferredMaxLayoutWidth = try attributes["preferredMaxLayoutWidth"].map { Float(try number($0, "preferredMaxLayoutWidth")) }
        content.adjustsFontSizeToFit = try bool(element, "adjustsFontSizeToFit", default: true)
        let factor = try attributes["minimumScaleFactor"].map { try number($0, "minimumScaleFactor") }
        let minimum = try attributes["minimumFontSize"].map { try number($0, "minimumFontSize") }
        if factor != nil || minimum != nil {
            let style = element.children(named: "fontDescription").first?.attributes["style"]
            guard content.adjustsFontSizeToFit, factor == nil || minimum == nil,
                  let size = font.pointSize ?? style.flatMap({ factor == nil ? nil : NibFont.textStyleSizes[$0] }) else {
                throw unsupported("this minimum font size of a label")
            }
            content.minimumFontSize = Float(minimum ?? (size * factor! * 4).rounded() / 4)
            content.minimumScaleFactor = Float(factor ?? minimum! / size)
        }
        return content
    }

    /// A label's font, one object per description, and its point size (nil for a text style).
    mutating func font(_ element: XIBElement) throws -> (font: NibFont, pointSize: Double?) {
        let descriptions = element.children(named: "fontDescription")
        guard descriptions.count == 1, let description = descriptions.first else { throw unsupported("a label without one font") }
        try check(description, attributes: ["key", "type", "pointSize", "weight", "style", "family", "name"], children: [])
        let attributes = description.attributes.filter { $0.key != "key" }
        // The system font by name is the same object as the regular system font of its size
        // (the corpus's pocket-casts UserEpisodeDetailViewController).
        let shared = attributes["name"] == ".AppleSystemUIFont" ? ["type": "system", "pointSize": attributes["pointSize"] ?? ""] : attributes
        let identity = shared.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let size = try attributes["pointSize"].map { try number($0, "pointSize") }
        if let font = fonts[identity] { return (font, size) }
        let font: NibFont
        switch (attributes["type"], attributes["style"], attributes["name"]) {
        case (let type?, nil, nil):
            guard Set(attributes.keys).isSubset(of: ["type", "pointSize", "weight"]), let size else { throw unsupported("this system font") }
            let weight = attributes["weight"] ?? "regular"
            switch (type, weight) {
            case ("boldSystem", "regular"), ("system", "bold"):
                let entries: [(String, NibArchivable)] = [("NSCTFontUIUsageAttribute", string("CTFontEmphasizedUsage")),
                                                          ("NSCTFontUIUsageOverrideAttribute", string("CTFontBoldUsage")), ("NSFontSizeAttribute", NibNumber(size))]
                font = NibFont(name: string(".SFUI-Bold"), kind: .descriptor(NibFontDescriptor(attributes: dictionary(entries, mutable: true),
                                                                                                options: NibFont.systemOptions)),
                               pointSize: size, traits: 2, systemFont: true, size: size)
            case ("italicSystem", "regular"):
                let entries: [(String, NibArchivable)] = [("NSCTFontTraitsAttribute", dictionary([("NSCTFontSymbolicTrait", NibNumber(integer: 1))])),
                                                          ("NSCTFontUIUsageAttribute", string("CTFontObliqueUsage")), ("NSFontSizeAttribute", NibNumber(size))]
                font = NibFont(name: string(".SFUI-RegularItalic"), kind: .descriptor(NibFontDescriptor(attributes: dictionary(entries),
                                                                                                         options: NibFont.systemOptions)),
                               pointSize: size, traits: 1, systemFont: true, size: size)
            case ("system", _):
                guard let system = NibFont.systemWeights[weight] else { throw unsupported("the system font weight \(weight)") }
                font = systemFont(system, size: size)
            default:
                throw unsupported("the font type \(type)")
            }
        case (nil, let style?, nil):
            guard attributes.count == 1 else { throw unsupported("the text style \(style)") }
            if let values = NibFont.textStyles[style] {
                font = NibFont(name: string(values.name), kind: .textStyle(string(style)), pointSize: 0, traits: values.traits, systemFont: true,
                               size: values.size)
            } else {
                // ibtool writes a font of no name, attributes or size for a style it does not know
                // (`label-style-subheadline`, `label-style-made-up`).
                font = NibFont(name: nil, kind: .descriptor(NibFontDescriptor(attributes: nil, options: 0)), pointSize: 0, traits: 0, systemFont: false,
                               size: 0)
            }
        case (nil, nil, let name?):
            guard Set(attributes.keys) == ["family", "name", "pointSize"], let size else { throw unsupported("the font \(name)") }
            if name == ".AppleSystemUIFont" {
                font = systemFont(NibFont.systemWeights["regular"]!, size: size)
            } else {
                guard let values = NibFont.namedFonts[name] else { throw unsupported("the font \(name)") }
                let fontName = string(name)
                let entries: [(String, NibArchivable)] = [("NSFontNameAttribute", fontName), ("NSFontSizeAttribute", NibNumber(size))]
                font = NibFont(name: fontName, kind: .descriptor(NibFontDescriptor(attributes: dictionary(entries), options: values.options)),
                               pointSize: size, traits: values.traits, systemFont: false, size: size, scales: values.options != 0)
            }
        default:
            throw unsupported("this font description")
        }
        fonts[identity] = font
        return (font, size)
    }

    private mutating func systemFont(_ values: (name: String, usage: String, traits: Int), size: Double) -> NibFont {
        let entries: [(String, NibArchivable)] = [("NSCTFontUIUsageAttribute", string(values.usage)), ("NSFontSizeAttribute", NibNumber(size))]
        return NibFont(name: string(values.name), kind: .descriptor(NibFontDescriptor(attributes: dictionary(entries), options: NibFont.systemOptions)),
                       pointSize: size, traits: values.traits, systemFont: true, size: size)
    }

    /// A font descriptor's attributes, its keys pooled strings.
    mutating func dictionary(_ entries: [(String, NibArchivable)], mutable: Bool = false) -> NibDictionary {
        let dictionary = NibDictionary()
        dictionary.entries = entries.map { (string($0.0) as NibArchivable, $0.1) }
        dictionary.mutable = mutable
        return dictionary
    }

    func mapped(_ value: String, _ table: [String: Int], _ attribute: String) throws -> Int {
        guard let number = table[value] else { throw unsupported("\(attribute)=\"\(value)\"") }
        return number
    }

    /// Simulated metrics, which change nothing (nib-experiments `view-freeform`, `view-simulated-nils`,
    /// `sb-simulated-nils`); a storyboard scene's freeform size is read by its controller.
    func designTimeSettings(_ element: XIBElement) throws {
        for child in element.children(named: "freeformSimulatedSizeMetrics") {
            try check(child, attributes: ["key"], children: [])
            try value(child, "key", in: ["simulatedDestinationMetrics"])
        }
        for child in element.children(named: "nil") {
            if element.name == "navigationController", child.attributes == ["name": "viewControllers"] { continue }
            if element.name == "textView", child.attributes == ["key": "text"] { continue }
            if element.name == "textField", child.attributes == ["key": "textColor"] { continue }
            try check(child, attributes: ["key"], children: [])
            try value(child, "key", in: ["simulatedTopBarMetrics", "simulatedBottomBarMetrics", "simulatedStatusBarMetrics"])
        }
        for child in element.children(named: "simulatedNavigationBarMetrics") {
            try check(child, attributes: ["key", "prompted", "translucent", "barStyle"], children: [])
            try value(child, "key", in: ["simulatedTopBarMetrics"])
            try value(child, "barStyle", in: ["black"])
        }
        // A controller's simulated tab bar and toolbar change nothing either (round 112, `sb-sim-*`).
        for child in element.children.filter({ ["simulatedTabBarMetrics", "simulatedToolbarMetrics"].contains($0.name) }) {
            try check(child, attributes: ["key", "translucent"], children: [])
            try value(child, "key", in: ["simulatedBottomBarMetrics"])
        }
    }

    /// The controls whose actions are observed (`act-*`, `ev-*`, `tf-action`, `sw-action`).
    static let actionHolders: Set = Set(["textField", "switch", "button", "segmentedControl", "slider", "pageControl", "datePicker", "refreshControl"]
                                        + NibGestureRecognizer.elements)

    /// Records an object's `<connections>` for `outletConnections`.
    mutating func connections(of element: XIBElement, source: NibArchivable) throws {
        for container in element.children(named: "connections") {
            let cellSegues = element.name == "tableViewCell" && cellSeguePlaceholders[element.attributes["id"] ?? ""] != nil
            let actions = Self.actionHolders.contains(element.name) || (element.name == "view" && element.attributes["customClass"] != nil)
            let controlSegues = ["button", "containerView"].contains(element.name) && !controlSeguePlaceholders.isEmpty
            try check(container, attributes: [], children: Set(["outlet", "outletCollection"] + (cellSegues || controlSegues ? ["segue"] : [])
                                                                + (actions ? ["action"] : [])))
            pendingOutlets.append(PendingOutlets(source: source, elements: container.children.filter { $0.name != "segue" }))
            for element in container.children(named: "segue") where controlSegues {
                try controlSegue(element, source: source)
            }
        }
    }

    /// A button's segue: a `perform:` action on touching up inside to its template's upstream
    /// placeholder, which a popover's `anchorView` outlet also connects (`sb-button-*`,
    /// `sb-popover-button`); a container view's embed segue: the placeholder's `containerView`
    /// outlet to it (`sb-embed*`).
    private mutating func controlSegue(_ element: XIBElement, source: NibArchivable) throws {
        guard let id = element.attributes["id"], let entry = controlSeguePlaceholders.first(where: { $0.segue.id == id }) else {
            throw unsupported("a button's segue of another scene")
        }
        placeholders[id] = entry.placeholder
        guard entry.segue.kind != .embed else {
            pendingOutlets.append(PendingOutlets(source: entry.placeholder, elements: [
                XIBElement(name: "outlet", attributes: ["property": "containerView", "destination": entry.segue.control ?? "", "id": id]),
            ]))
            return
        }
        pendingOutlets.append(PendingOutlets(source: source, elements: [
            XIBElement(name: "action", attributes: ["selector": "perform:", "destination": id, "eventType": "touchUpInside", "id": id]),
        ]))
        if let anchor = entry.segue.anchorView {
            pendingOutlets.append(PendingOutlets(source: entry.placeholder, elements: [
                XIBElement(name: "outlet", attributes: ["property": "anchorView", "destination": anchor, "id": id]),
            ]))
        }
    }

    /// A `<color>`: sRGB or generic gray gamma 2.2 components, a system color with the values IB
    /// gives it, or a named color of the document's resources. Other color spaces are converted
    /// by ibtool with color management and are not compiled yet (BACKLOG B-260).
    mutating func color(_ element: XIBElement) throws -> NibColor {
        try check(element, attributes: ["key", "white", "red", "green", "blue", "alpha", "colorSpace", "customColorSpace", "systemColor",
                                        "cocoaTouchSystemColor", "xcode11CocoaTouchSystemColor", "name"], children: [])
        let attributes = element.attributes
        var components: NibColor.Components
        var name: NibColor.Name?
        if !colorMatched {
            components = try unmatchedComponents(element)
        } else if let system = attributes["xcode11CocoaTouchSystemColor"]
                    ?? attributes["systemColor"].flatMap({ attributes["cocoaTouchSystemColor"] == nil ? nil : $0 }) {
            guard Set(attributes.keys).subtracting(["xcode11CocoaTouchSystemColor", "systemColor"]).isSubset(of: ["key", "cocoaTouchSystemColor"]),
                  attributes["xcode11CocoaTouchSystemColor"] == nil || attributes["systemColor"] == nil,
                  NibColor.xcode11SystemColors[system] == attributes["cocoaTouchSystemColor"], let values = NibColor.systemColors[system] else {
                throw unsupported("the Xcode 11 system color \(system)")
            }
            components = values
            name = .system(system)
        } else if let system = attributes["cocoaTouchSystemColor"] ?? attributes["systemColor"] {
            let names = attributes["cocoaTouchSystemColor"] != nil ? NibColor.cocoaTouchSystemColors : NibColor.observedSystemColorNames
            guard names.contains(system), let values = NibColor.systemColors[system] else {
                throw unsupported("the system color \(system)")
            }
            guard attributes.keys.allSatisfy({ ["key", "systemColor", "cocoaTouchSystemColor"].contains($0) }),
                  attributes["systemColor"].map({ $0 == system }) ?? true else {
                throw unsupported("a system color with components")
            }
            components = values
            name = .system(system)
        } else if let catalogName = attributes["name"] {
            guard let definition = namedColors[catalogName], definition.attributes["name"] == nil,
                  attributes.keys.allSatisfy({ ["key", "name"].contains($0) }) else {
                throw unsupported("the named color \(catalogName)")
            }
            components = try documentComponents(definition)
            name = .catalog(catalogName)
            requires(13, 0)
        } else {
            components = try documentComponents(element)
            let space = attributes["customColorSpace"] ?? attributes["colorSpace"] ?? ""
            if roundsInlineColors, space != "calibratedWhite" {
                components = ConvertedColor.spaces.contains(space) ? components.significantAlpha(10) : components.significant(10)
            }
            if case .gray(let white, let alpha) = components, let gray = NibColor.grayName(white: white, alpha: alpha) {
                name = .system(gray)
            }
        }
        let identity = "\(components) \(name.map { "\($0)" } ?? "")"
        if let existing = colors[identity] { return existing }
        let named = name.map { kind -> (kind: NibColor.Name, string: NibString) in
            let text: String
            switch kind {
            case .system(let value), .catalog(let value): text = value
            }
            return (kind, string(text))
        }
        let color = NibColor(components: components, name: named)
        colors[identity] = color
        return color
    }

    /// A color of a document without `colorMatched="YES"`: a `calibratedWhite` gray is written as
    /// the sRGB color of the same components, without a name (`unmatched-cw-*`, the corpus's
    /// flutter storyboards); other colors are converted by ibtool and not compiled yet.
    func unmatchedComponents(_ element: XIBElement) throws -> NibColor.Components {
        let attributes = element.attributes
        let space = attributes["colorSpace"] == "custom" ? attributes["customColorSpace"] : attributes["colorSpace"]
        guard element.children.isEmpty, Set(attributes.keys).isSubset(of: ["key", "white", "alpha", "colorSpace", "customColorSpace"]),
              space == "calibratedWhite", attributes["colorSpace"] == "custom" || attributes["customColorSpace"] == nil,
              let white = attributes["white"].flatMap(Double.init), let alpha = attributes["alpha"].flatMap(Double.init),
              [0, 0.5, 1].contains(white), [0, 1].contains(alpha) else {
            throw unsupported("this color in a document without colorMatched=\"YES\"")
        }
        return .rgb(red: white, green: white, blue: white, alpha: alpha)
    }

    func documentComponents(_ element: XIBElement) throws -> NibColor.Components {
        try check(element, attributes: ["key", "white", "red", "green", "blue", "alpha", "colorSpace", "customColorSpace"], children: [])
        let attributes = element.attributes
        func value(_ name: String) throws -> Double {
            guard let text = attributes[name] else { throw unsupported("a color without \(name)") }
            return try number(text, name)
        }
        let space = attributes["colorSpace"] == "custom" ? attributes["customColorSpace"] : attributes["colorSpace"]
        guard attributes["colorSpace"] == "custom" || (["calibratedWhite", "calibratedRGB", "deviceRGB"].contains(attributes["colorSpace"] ?? "")
                                                       && attributes["customColorSpace"] == nil) else {
            throw unsupported("colorSpace=\"\(attributes["colorSpace"] ?? "")\"")
        }
        switch space {
        case let space? where ConvertedColor.spaces.contains(space):
            let key = ConvertedColor(space, try value("red"), try value("green"), try value("blue"))
            guard let converted = NibColor.convertedColors[key] else {
                throw unsupported("the \(space) color \(attributes["red"] ?? "") \(attributes["green"] ?? "") \(attributes["blue"] ?? "")")
            }
            return .rgb(red: Double(converted.red), green: Double(converted.green), blue: Double(converted.blue), alpha: try value("alpha"))
        case "calibratedWhite":
            let white = try value("white")
            guard let converted = NibColor.calibratedWhites[white] else {
                throw unsupported("the calibratedWhite \(attributes["white"] ?? "")")
            }
            return .gray(white: converted, alpha: try value("alpha"))
        case "genericGamma22GrayColorSpace":
            return .gray(white: try value("white"), alpha: try value("alpha"))
        case "sRGB":
            return .rgb(red: try value("red"), green: try value("green"), blue: try value("blue"), alpha: try value("alpha"))
        case let other:
            throw unsupported("customColorSpace=\"\(other ?? "")\"")
        }
    }

    /// The runtime name of a view's custom class: Swift's mangled name with the module of
    /// `--module` for `customModuleProvider="target"`, whatever `customModule` says, or with
    /// `customModule` without a provider (`_TtC1T6MyView`); the class name with neither
    /// (nib-experiments `view-custom-class*`, `provider-target-*`, `module-without-provider-*`).
    mutating func customClass(_ element: XIBElement, original: String = "UIView") throws -> (name: NibString, original: NibString)? {
        guard let name = element.attributes["customClass"] else {
            if element.attributes["customModule"] != nil || element.attributes["customModuleProvider"] != nil {
                throw unsupported("customModule without customClass")
            }
            return nil
        }
        var classModule = element.attributes["customModule"]
        switch element.attributes["customModuleProvider"] {
        case nil:
            break
        case "target":
            guard let module else { throw unsupported("customModuleProvider=\"target\" without --module") }
            classModule = module
        case let other?:
            throw unsupported("customModuleProvider=\"\(other)\"")
        }
        var runtimeName = name
        if let classModule {
            guard [classModule, name].allSatisfy(Self.isPlainIdentifier) else {
                throw unsupported("the Swift name of \(classModule).\(name)")
            }
            runtimeName = "_TtC\(classModule.utf8.count)\(classModule)\(name.utf8.count)\(name)"
        }
        return (string(runtimeName), string(original))
    }

    static func isPlainIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || (first.isASCII && first.properties.isAlphabetic) else { return false }
        return name.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) }
    }

    /// A system color of a name IB gives itself, one object per name and components.
    mutating func systemColor(_ name: String, _ components: NibColor.Components) -> NibColor {
        let identity = "\(components) \(NibColor.Name.system(name))"
        if let existing = colors[identity] { return existing }
        let color = NibColor(components: components, name: (.system(name), string(name)))
        colors[identity] = color
        return color
    }

    mutating func string(_ value: String) -> NibString {
        if let existing = strings[value] { return existing }
        let string = NibString(value)
        strings[value] = string
        return string
    }

    func check(_ element: XIBElement, attributes: [String], children: Set<String>) throws {
        for name in element.attributes.keys where !attributes.contains(name) {
            throw unsupported("the \(name) attribute of <\(element.name)>")
        }
        for child in element.children where !children.contains(child.name) {
            throw unsupported("<\(child.name)> in <\(element.name)>")
        }
    }

    /// Refuses a value of `name` outside `values`; a missing attribute is accepted.
    func value(_ element: XIBElement, _ name: String, in values: Set<String>) throws {
        if let text = element.attributes[name], !values.contains(text) {
            throw unsupported("\(name)=\"\(text)\" in <\(element.name)>")
        }
    }

    /// A boolean attribute: IB's `YES` and `NO`, and the spellings Expo's templates write
    /// (`bool-*`: `true`, `yes` and `1` are `YES`; `false`, `no` and `0` are `NO`).
    func bool(_ element: XIBElement, _ name: String, default value: Bool) throws -> Bool {
        switch element.attributes[name] {
        case nil: value
        case "YES", "true", "yes", "1": true
        case "NO", "false", "no", "0": false
        case let other?: throw unsupported("\(name)=\"\(other)\"")
        }
    }

    func number(_ text: String, _ name: String) throws -> Double {
        guard let value = Double(text) else { throw unsupported("\(name)=\"\(text)\"") }
        return value
    }

    func integer(_ text: String, _ name: String) throws -> Int {
        guard let value = Int(text) else { throw unsupported("\(name)=\"\(text)\"") }
        return value
    }

    func named(_ text: String, in names: [String], _ attribute: String) throws -> Int {
        guard let index = names.firstIndex(of: text) else { throw unsupported("\(attribute)=\"\(text)\"") }
        return index
    }

    func unsupported(_ what: String) -> NomacError {
        NomacError("nomac does not compile \(what) yet (BACKLOG B-260)", path: path)
    }
}

extension DocumentCompiler {
    /// A view's `<rect key="contentStretch">`: its four values as the document writes them, after
    /// the content mode, left out when 0, 0, 1, 1 (`view-stretch*`, `image-view-stretch`,
    /// `label-stretch`, `button-stretch`).
    func contentStretch(_ element: XIBElement) throws -> [Double]? {
        guard let rect = element.child("rect", key: "contentStretch") else { return nil }
        try check(rect, attributes: ["key", "x", "y", "width", "height"], children: [])
        let values = try ["x", "y", "width", "height"].map { try number(rect.attributes[$0] ?? "0", $0) }
        return values == [0, 0, 1, 1] ? nil : values
    }
}

extension DocumentCompiler {
    /// For a deployment target under 17.0, ibtool gives a xib's top-level views without freeform
    /// simulated metrics the document device's size, in its orientation, or 600 x 600 without a
    /// device, keeping their origin and autoresizing their subviews; from 17.0 on they keep their
    /// frames (`tl-*`, nib-experiments round 99: 15.0 and 16.0 resize, 17.0 and 27.0 do not;
    /// cells and labels keep theirs).
    mutating func resizeToDevice(_ views: [NibView], document: XIBElement) throws {
        guard deploymentTarget.major < 17, !views.isEmpty else { return }
        let size: (width: Double, height: Double)
        if let device = document.children(named: "device").first {
            guard let id = device.attributes["id"], !["retina3_5", "retina6_72"].contains(id), let portrait = StoryboardCompiler.deviceSizes[id] else {
                throw unsupported("top-level views without freeform metrics on the device \(device.attributes["id"] ?? "") for iOS before 17")
            }
            size = device.attributes["orientation"] == "landscape" ? (portrait.height, portrait.width) : portrait
        } else {
            guard document.attributes["useTraitCollections"] == "YES" else {
                throw unsupported("top-level views without freeform metrics, a device or trait collections for iOS before 17")
            }
            size = StoryboardCompiler.sizeWithoutDevice
        }
        for view in views {
            try resize(view, to: size, keepingOrigin: true)
        }
    }
}
