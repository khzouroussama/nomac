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
    /// by their sources' order in all objects (nib-experiments `outlet-*`, `oc-class-*`); then the
    /// controls' actions by event, those without one first, selector and source (`ev-*`, `act-*`).
    /// Outlet collections of several names of one source keep the order of their names' first
    /// connections in the document (`oc-names*`); of several sources, ibtool's order varies from
    /// run to run (`oc-mix-*`, ADR 0260). Two actions of one control without an event are refused
    /// (ibtool keeps one: `act-field-mixed-no-event`). ibtool drops a connection without an
    /// id (`cid-outlet-no-id*`, `conn-no-id-*`).
    mutating func outletConnections(allObjects: [NibArchivable], extra: [NibOutletConnection] = []) throws -> [NibArchivable] {
        let order = Dictionary(allObjects.enumerated().map { (ObjectIdentifier($0.element), $0.offset) }) { first, _ in first }
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
                    let mask = try element.attributes["eventType"].map { try mapped($0, Self.eventMasks, "eventType") }
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
            return left == right ? index($0.source) < index($1.source) : left.lexicographicallyPrecedes(right)
        }
        for (left, right) in zip(sortedEvents, sortedEvents.dropFirst())
        where left.source is NibGestureRecognizer && right.source is NibGestureRecognizer && left.selector.value == right.selector.value {
            throw unsupported("two gesture recognizers' actions of one selector")
        }
        return sortedCollections + sorted + sortedEvents
    }

    /// A connection's source's class: a custom class's original (`oc-class-custom`).
    static func originalClass(_ object: NibArchivable) -> String {
        (object as? NibView)?.customClass?.original.value ?? object.className
    }

    func property(_ element: XIBElement) throws -> String {
        guard let name = element.attributes["property"] else { throw unsupported("an outlet without a property") }
        return name
    }

    /// An outlet's or action's destination: a placeholder, a view or a constraint of the nib.
    func outletDestination(_ element: XIBElement) throws -> NibArchivable {
        guard let id = element.attributes["destination"] else { throw unsupported("an outlet without a destination") }
        if let object = placeholders[id] ?? documentViews[id]?.view ?? documentConstraints[id] ?? gestureRecognizers[id] { return object }
        throw unsupported("an outlet to an object outside its nib or of a kind nomac does not compile")
    }
}
