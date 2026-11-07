import Foundation
import NomacCore

/// An object's `<connections>`, compiled once every object of the document is read.
struct PendingOutlets {
    let source: NibArchivable
    let elements: [XIBElement]
}

extension DocumentCompiler {
    /// The connections of the pending outlets, in the order ibtool writes them (docs/formats/nib.md
    /// "Connections"): the outlet collections first, then the outlets by name, byte by byte, those
    /// of one name placeholders first, then by their sources' original classes, byte by byte, then
    /// by the walk of `connectionWalk` (nib-experiments `outlet-*`, `oc-class-*`, `outlet-same-tree-*`);
    /// then the controls' actions by event, those without one first, selector and source likewise
    /// (`ev-*`, `act-*`, `act-same-*`).
    /// Outlet collections of several names of one source keep the order of their names' first
    /// connections in the document (`oc-names*`); of several sources, ibtool's order varies from
    /// run to run (`oc-mix-*`, ADR 0260). Two actions of one control without an event are refused
    /// (ibtool keeps one: `act-field-mixed-no-event`). ibtool drops a connection without an
    /// id (`cid-outlet-no-id*`, `conn-no-id-*`).
    mutating func outletConnections(allObjects: [NibArchivable], extra: [NibOutletConnection] = []) throws -> [NibArchivable] {
        let order = connectionWalk(allObjects)
        var outlets = extra
        var collections: [NibOutletCollectionConnection] = []
        var events: [NibEventConnection] = []
        for pending in pendingOutlets {
            for element in pending.elements where element.attributes["id"] != nil {
                switch element.name {
                case "outlet":
                    try check(element, attributes: ["property", "destination", "id"], children: [])
                    outlets.append(NibOutletConnection(label: string(try property(element)), source: pending.source,
                                                       destination: try outletDestination(element)))
                case "outletCollection":
                    try check(element, attributes: ["property", "destination", "collectionClass", "appends", "id"], children: [])
                    try value(element, "collectionClass", in: ["NSMutableArray"])
                    let label = string(try property(element))
                    if let collection = collections.first(where: { $0.label === label && $0.source === pending.source }) {
                        collection.destinations.append(try outletDestination(element))
                    } else {
                        let collection = NibOutletCollectionConnection(label: label, source: pending.source, destination: try outletDestination(element))
                        collection.appends = try bool(element, "appends", default: false)
                        collection.collectionClass = string(element.attributes["collectionClass"] ?? "NSArray")
                        collections.append(collection)
                    }
                case "action":
                    try check(element, attributes: ["selector", "destination", "eventType", "id"], children: [])
                    guard let selector = element.attributes["selector"] else { throw unsupported("an action without a selector") }
                    if otherScenesControllers.contains(element.attributes["destination"] ?? "") { continue }
                    let mask = try element.attributes["eventType"].flatMap { $0 == "menuActionTriggered" ? nil : try mapped($0, Self.eventMasks, "eventType") }
                    if mask == nil, events.contains(where: { $0.source === pending.source && $0.eventMask == nil }) {
                        throw unsupported("two actions of a control without an event")
                    }
                    events.append(NibEventConnection(selector: string(selector), source: pending.source, destination: try outletDestination(element),
                                                     eventMask: mask))
                default:
                    throw unsupported("<\(element.name)> in <connections>")
                }
            }
        }
        pendingOutlets = []
        func index(_ object: NibArchivable) -> Int { order[ObjectIdentifier(object)] ?? Int.max }
        func precedes(_ left: NibArchivable, _ right: NibArchivable) -> Bool {
            let (leftProxy, rightProxy) = (left is NibProxy, right is NibProxy)
            if leftProxy != rightProxy { return leftProxy }
            let (leftClass, rightClass) = (Array(Self.originalClass(left).utf8), Array(Self.originalClass(right).utf8))
            return leftClass == rightClass ? index(left) < index(right) : leftClass.lexicographicallyPrecedes(rightClass)
        }
        // Collections of several names from several sources come out in an order ibtool changes
        // from run to run (`oc-mix-*`); nomac writes them by name, then as those of one name, which
        // `nomac verify` takes as equivalent (ADR 0260).
        let severalNames = Set(collections.map(\.label.value)).count > 1
        let oneSource = collections.allSatisfy { $0.source === collections.first?.source }
        let sortedCollections = severalNames && oneSource ? collections : collections.sorted {
            let (left, right) = (Array($0.label.value.utf8), Array($1.label.value.utf8))
            return left == right || !severalNames ? precedes($0.source, $1.source) : left.lexicographicallyPrecedes(right)
        }
        let sorted = outlets.sorted {
            let (left, right) = (Array($0.label.value.utf8), Array($1.label.value.utf8))
            return left == right ? precedes($0.source, $1.source) : left.lexicographicallyPrecedes(right)
        }
        let sortedEvents = events.sorted {
            let (left, right) = (Array($0.selector.value.utf8), Array($1.selector.value.utf8))
            if $0.eventMask != $1.eventMask { return ($0.eventMask ?? 0) < ($1.eventMask ?? 0) }
            return left == right ? precedes($0.source, $1.source) : left.lexicographicallyPrecedes(right)
        }
        return sortedCollections + sorted + sortedEvents
    }

    /// The order of a nib's objects among connections of one name and class: its views first, from
    /// its top-level views in order, then the others in all objects. A xib walks them depth first
    /// (`act-same-tree-*`, `outlet-same-tree-*`, `act-same-top-nested`). A storyboard takes a view's
    /// subviews in order and then goes on from the last taken, as a stack, one top-level view after
    /// another, a static cell being one, whose views take their subviews last first
    /// (`sb-act-same-*`, `sb-outlet-same-tree-*`, `sb-static-same-*`; the corpus's uncloudnotes DogDoodies, wikipedia
    /// WMFTwoFactorPasswordViewController and DescriptionEditViewController, tofu's AccountCreation).
    func connectionWalk(_ allObjects: [NibArchivable]) -> [ObjectIdentifier: Int] {
        func children(_ view: NibView) -> [NibView] {
            switch view.kind {
            case .effect(let effect): [effect.contentView] + view.subviews
            case .collectionCell(let cell): [cell.contentView] + view.subviews
            default: view.subviews
            }
        }
        let views = allObjects.compactMap { $0 as? NibView }
        let nested = Set(views.flatMap(children).map(ObjectIdentifier.init))
        let top = views.filter { !nested.contains(ObjectIdentifier($0)) }
        var walk: [NibView] = []
        if isStoryboard {
            for root in top {
                var reversed = false
                if case .cell = root.kind { reversed = true }
                walk.append(root)
                var stack = [root]
                while let view = stack.popLast() {
                    let subviews = reversed ? children(view).reversed() : children(view)
                    walk += subviews
                    stack += subviews
                }
            }
        } else {
            func visit(_ view: NibView) {
                walk.append(view)
                children(view).forEach(visit)
            }
            top.forEach(visit)
        }
        var order: [ObjectIdentifier: Int] = [:]
        for object in walk as [NibArchivable] + allObjects where order[ObjectIdentifier(object)] == nil {
            order[ObjectIdentifier(object)] = order.count
        }
        return order
    }

    /// A connection's source's class: a custom class's original (`oc-class-custom`).
    static func originalClass(_ object: NibArchivable) -> String {
        (object as? NibView)?.customClass?.original.value ?? object.className
    }

    func property(_ element: XIBElement) throws -> String {
        guard let name = element.attributes["property"] else { throw unsupported("an outlet without a property") }
        return name
    }

    /// An outlet's or action's destination: a placeholder, a view, a constraint, a gesture recognizer,
    /// a navigation bar's item or bar button item of the nib (`outlet-nav-bar-*`), or the placeholder
    /// of an object of its controller's nib (`sb-outlet-*-from-view*`). The refusal names the
    /// destination's element.
    func outletDestination(_ element: XIBElement) throws -> NibArchivable {
        guard let id = element.attributes["destination"] else { throw unsupported("an outlet without a destination") }
        if let object = placeholders[id] ?? documentViews[id]?.view ?? documentConstraints[id] ?? gestureRecognizers[id] ?? navigationBarItems[id]
            ?? controllerNibPlaceholders.first(where: { $0.id == id })?.placeholder { return object }
        let name = document.flatMap { Self.element(id: id, in: $0) }.map { "<\($0.name)>" } ?? "an object not in the document"
        throw unsupported("an outlet to \(name) (\(id)) outside its nib or of a kind nomac does not compile")
    }

    private static func element(id: String, in root: XIBElement) -> XIBElement? {
        root.attributes["id"] == id ? root : root.children.lazy.compactMap { element(id: id, in: $0) }.first
    }
}
