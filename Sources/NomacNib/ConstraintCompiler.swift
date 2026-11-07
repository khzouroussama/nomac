import Foundation
import NomacCore

/// What constraints need to know of a document's views: the view, its document frame, its parent's
/// id, and whether it translates its mask into constraints.
struct DocumentView {
    let view: NibView
    let frame: (x: Double, y: Double, width: Double, height: Double)
    let parent: String?
    let translates: Bool
    let hasMask: Bool
}

/// A view's `<constraints>`, compiled once every view of the document is read.
struct PendingConstraints {
    let owner: String
    let elements: [XIBElement]
}

extension DocumentCompiler {
    /// `NSLayoutAttribute` by the names documents use.
    static let layoutAttributes = ["left": 1, "right": 2, "top": 3, "bottom": 4, "leading": 5, "trailing": 6, "width": 7, "height": 8,
                                   "centerX": 9, "centerY": 10, "baseline": 11, "firstBaseline": 12]
    /// The order of a view's constraints by attribute, between views, and when the safe area takes
    /// part (nib-experiments `order-*`: total orders from all ten attributes and every pair; the
    /// baselines from `cs-pairs-*`).
    static let viewAttributeOrder = ["centerX", "centerY", "right", "left", "trailing", "leading", "width", "bottom", "top", "firstBaseline", "baseline", "height"]
    /// The same with margins (`~`), each pair's margins before its plain attributes, top margin
    /// before bottom margin (`norm-all*`, `sub-first-all`, `margin-order-*`).
    static let viewMarginOrder = ["centerX~", "centerX", "centerY~", "centerY", "right~", "left~", "right", "left", "trailing~", "leading~", "trailing",
                                  "leading", "width", "top~", "bottom~", "bottom", "top", "firstBaseline", "baseline", "height"]
    /// A first baseline sorts after a top, a baseline after that (`baseline-firstBaseline-*`,
    /// `cs-baseline-*`, `cs-pairs-*-safe`).
    static let guideAttributeOrder = ["centerX", "right", "left", "trailing", "leading", "centerY", "bottom", "top", "firstBaseline", "baseline", "width", "height"]
    static let relations = ["lessThanOrEqual": -1, "greaterThanOrEqual": 1]

    /// Every pending view's constraints, in the order ibtool writes them (docs/formats/nib.md
    /// "Constraints"): grouped by item, the view's own first, then each subview's and the safe
    /// area's by their frames' distance from the view's origin (`orderedItems`); within a group by
    /// whether the safe area comes first, whether the constraint is between subviews, the attributes,
    /// the priority and the relation (the attributes as written, the view's first in a constraint
    /// written from the view, `norm-*`; one whose second attribute alone is a center by that center:
    /// `order-cross`, `cross-attribute-*`, `norm-cross-*`, cwa's contact diary and home cells); constraints of the same items differing only in their
    /// constants in document order (`tie-constant-reversed`, `mask-*`), and identical ones as they
    /// come (`tie-identical-normalized`, nextcloud's duplicated constraints); those of one first item
    /// to different subviews follow a rule not pinned yet (`tie-second-items-*` fit the subviews'
    /// distance from the origin, the corpus does not: B-265). Items at the same distance and x are refused.
    mutating func compileConstraints() throws {
        var pending = pendingConstraints
        let moved = try installWhereIbtoolDoes(&pending)
        pendingConstraints = pending
        for pending in pendingConstraints {
            guard let owner = documentViews[pending.owner] else { continue }
            let guides = Set(safeAreaGuides.filter { $0.value == pending.owner }.keys).union(scrollGuides.filter { $0.value.owner == pending.owner }.keys)
                .union(keyboardGuides.filter { $0.value == pending.owner }.keys)
            var groups: [String: [(key: [Int], normalized: Bool, constraint: NibLayoutConstraint)]] = [:]
            for element in pending.elements {
                guard let (item, key, normalized, constraint) = try constraint(element, owner: pending.owner, guides: guides) else { continue }
                groups[item, default: []].append((key, normalized, constraint))
            }
            let items = try orderedItems(Array(groups.keys), owner: pending.owner, guides: guides)
            var sorted: [NibLayoutConstraint] = []
            for item in items {
                let group = groups[item]!.enumerated().sorted {
                    $0.element.key == $1.element.key ? $0.offset < $1.offset : $0.element.key.lexicographicallyPrecedes($1.element.key)
                }.map(\.element)
                for (first, second) in zip(group, group.dropFirst()) where first.key.dropLast() == second.key.dropLast() {
                    let (a, b) = (first.constraint, second.constraint)
                    let sameItems = a.first === b.first && a.second?.item === b.second?.item && a.multiplier == b.multiplier
                    if sameItems, a.constant == b.constant, a.relation == b.relation, a.priority == b.priority { continue }
                    let settledTie = first.key == second.key && [a, b].allSatisfy { constraint in
                        constraint.priority == 1000 && satisfiedByFrames(constraint, owner: pending.owner) && !namesDeeperView(constraint, owner: pending.owner)
                    }
                    guard settledTie || first.key != second.key || sameItems, !first.normalized, !second.normalized else {
                        throw unsupportedConstraints("constraints that differ only in their constants or relations")
                    }
                }
                sorted += group.map(\.constraint)
            }
            owner.view.constraints = sorted
        }
        pendingConstraints = []
        try listMovedConstraints(moved)
        try compileMasks()
    }

    /// A view's `<variation>`s of a `<mask key="constraints">` or `<mask key="subviews">`: by size
    /// class, or none for `default`, the constraints or subviews it includes and excludes
    /// (nib-experiments `mask-*`, `sc-mask-*`, the corpus's tofu storyboard, nextcloud's
    /// NCShareUserCell, wikipedia's PageHistoryCountsView).
    mutating func masks(_ element: XIBElement, owner: String) throws {
        for variation in element.children(named: "variation") {
            // A variation's own frame and the flags IB keeps on it change nothing (`cm-var-*`); a
            // label's font variation sits beside its mask (`cm-label-mask-font*`).
            try check(variation, attributes: ["key", "misplaced", "ambiguous", "fixedFrame"] + (element.name == "stackView" ? StackContent.variedAttributes.map(\.attribute) : []),
                      children: Set(["mask", "rect"] + (element.name == "label" ? ["fontDescription"] : [])))
            let sizeClasses = variation.attributes["key"] == "default" ? SizeClasses() : try self.sizeClasses(variation)
            for mask in variation.children(named: "mask") {
                try check(mask, attributes: ["key"], children: ["include", "exclude"])
                try value(mask, "key", in: ["constraints", "subviews"])
                // An empty mask changes nothing (`mask-empty-*`, `cvmask-old-empty`).
                if mask.children.isEmpty { continue }
                let references = try mask.children.map { child in
                    try check(child, attributes: ["reference"], children: [])
                    guard let reference = child.attributes["reference"] else { throw unsupported("an <\(child.name)> without a reference") }
                    return (included: child.name == "include", reference: reference)
                }
                let included = references.filter(\.included).map(\.reference)
                guard sizeClasses != SizeClasses() || included.isEmpty else { throw unsupported("a default mask that includes") }
                pendingMasks.append((owner, mask.attributes["key"] == "subviews", sizeClasses, included, references.filter { !$0.included }.map(\.reference)))
            }
        }
    }

    /// The masks' storages, one per view and mask key: the owner's constraints, or subviews, in their
    /// order the candidates; a record per variation, the default first, then by size class in the
    /// reverse of the attribute records' order (`sc-mask-order-all*`), each its own trait collection
    /// but the default's (the corpus's wikipedia WelcomeContainerViewController); the objects the
    /// default excludes not installed, nor in a storyboard those the device's size classes exclude.
    /// An excluded subview that constraints name is refused: ibtool warns and drops them too
    /// (`mask-subviews-root-constrained`). A record's added and removed objects are `NSSet`s, which
    /// ibtool writes in the order of their memory addresses (`sc-mask-set-probe-*`): nomac writes
    /// the candidates' order, equivalent (ADR 0252).
    private mutating func compileMasks() throws {
        var groups: [(owner: String, subviews: Bool)] = []
        for mask in pendingMasks where !groups.contains(where: { $0 == (mask.owner, mask.subviews) }) {
            groups.append((mask.owner, mask.subviews))
        }
        for group in groups {
            guard let owner = documentViews[group.owner] else { throw unsupported("a mask of a view nomac does not compile") }
            let masks = pendingMasks.filter { $0.owner == group.owner && $0.subviews == group.subviews }
            guard Set(masks.map { $0.sizeClasses.recordOrder }).count == masks.count else { throw unsupported("a mask's size class given twice") }
            if group.subviews {
                switch owner.view.kind {
                case .view, .cellContentView: break
                default: throw unsupported("a mask of the subviews of a \(owner.view.className)")
                }
            }
            let candidates: [NibArchivable] = group.subviews ? owner.view.subviews : owner.view.constraints
            // A collection view cell's mask with its constraints on the cell in the document, an old
            // cell's, stays the cell's, though its content view installs them (`cvmask-old-*`).
            let storageOwner = owner.parent.flatMap { documentViews[$0]?.view }.flatMap { cell -> NibView? in
                guard case .collectionCell(let content) = cell.kind, content.legacy, content.contentView === owner.view else { return nil }
                return cell
            } ?? owner.view
            func resolve(_ id: String) throws -> NibArchivable {
                guard group.subviews else {
                    guard let constraint = documentConstraints[id], owner.view.constraints.contains(where: { $0 === constraint }) else {
                        throw unsupported("a mask naming something other than its view's constraint")
                    }
                    return constraint
                }
                guard let view = documentViews[id]?.view, owner.view.subviews.contains(where: { $0 === view }) else {
                    throw unsupported("a mask naming something other than its view's subview")
                }
                let constrained = documentConstraints.values.contains { $0.first === view || $0.second?.item === view }
                guard !constrained, view.constraints.isEmpty else { throw unsupported("a mask excluding a constrained subview (ibtool warns)") }
                return view
            }
            let records = try masks.sorted { $0.sizeClasses.recordOrder < $1.sizeClasses.recordOrder }.map { mask in
                NibRelationshipTraitStorage.Record(sizeClasses: mask.sizeClasses, added: try mask.included.map(resolve), removed: try mask.excluded.map(resolve))
            }
            var removed = records.first { $0.sizeClasses == SizeClasses() }?.removed ?? []
            if let device = deviceSizeClasses {
                for record in records where record.sizeClasses != SizeClasses() && record.sizeClasses.applies(to: device) {
                    removed = removed.filter { object in !record.added.contains { $0 === object } } + record.removed
                }
            }
            let excluded = candidates.filter { candidate in removed.contains { $0 === candidate } }
            let storage: NibRelationshipTraitStorage
            if group.subviews {
                owner.view.excludedSubviews = excluded.compactMap { $0 as? NibView }
                storage = NibRelationshipTraitStorage(owner: storageOwner, keyPath: string("traitStorageSubviews"), candidates: candidates,
                                                      records: records.map { $0.ordered(as: candidates) }, descendants: storageOwner === owner.view ? [owner.view] : [])
                relationshipStorages.append(storage)
                continue
            }
            owner.view.excludedConstraints = excluded.compactMap { $0 as? NibLayoutConstraint }
            let items: [NibArchivable] = owner.view.constraints.flatMap { [$0.first] + ($0.second.map { [$0.item] } ?? []) }
            // A safe area among the items is its view's unarchived placeholder guide (the corpus's
            // pocket-casts ShelfActionsViewController).
            let descendants = items.filter { $0 !== owner.view || storageOwner === owner.view }
                .map { item -> NibArchivable in (item as? NibViewLayoutGuide)?.owningView.safeAreaPlaceholder ?? item }
            storage = NibRelationshipTraitStorage(owner: storageOwner, keyPath: string("traitStorageConstraints"), candidates: candidates,
                                                  records: records.map { $0.ordered(as: candidates) }, descendants: descendants)
            relationshipStorages.append(storage)
        }
        pendingMasks = []
    }

    /// A constraint, its item (the group it sorts in) and its sort key, or nil for a placeholder,
    /// which ibtool leaves out though its views count as constrained (`constraint-placeholder`). A
    /// constraint between two subviews sorts in its first item's group as written, after that
    /// group's constraints with the view, among those to the safe area, by the safe area's attribute
    /// order (`sib-*`, `sib-safe-*`; the corpus's pocket-casts WhatsNewViewController). Constraints to
    /// views deeper than the subviews come first in their group, the deepest first, then by that key
    /// (`deep-other-*`; the corpus's cwa ExposureDetectionViewController).
    private mutating func constraint(_ element: XIBElement, owner: String, guides: Set<String>) throws
        -> (String, [Int], Bool, NibLayoutConstraint)? {
        try check(element, attributes: ["id", "firstItem", "firstAttribute", "secondItem", "secondAttribute", "relation", "constant",
                                        "multiplier", "priority", "identifier", "placeholder", "symbolic", "symbolType", "userLabel",
                                        "customClass", "customModule", "customModuleProvider"], children: ["variation"])
        let attributes = element.attributes
        let first = attributes["firstItem"] ?? owner
        let second = attributes["secondItem"]
        // ibtool drops a baseline with no second item (seen on live documents, no rule for the rest yet).
        guard second != nil || !["baseline", "firstBaseline", "lastBaseline"].contains(attributes["firstAttribute"] ?? "") else {
            throw unsupportedConstraints("a baseline constraint without a second item")
        }
        if attributes["placeholder"] != nil {
            try value(element, "placeholder", in: ["YES"])
            for id in [first, second].compactMap({ $0 }) where !guides.contains(id) {
                try constrained(id)
            }
            return nil
        }
        guard (second == nil) == (attributes["secondAttribute"] == nil) else { throw unsupportedConstraints("a constraint with half a second item") }
        for id in [first, second].compactMap({ $0 }) where id != owner && !guides.contains(id) && frame(of: id, in: owner) == nil {
            throw unsupportedConstraints("a constraint with an item that is not the view, its safe area or one of its subviews")
        }
        let firstAttribute = try layoutAttribute(attributes["firstAttribute"])
        let secondAttribute = try attributes["secondAttribute"].map { try layoutAttribute($0) }
        let subviews = [first, second].compactMap { $0 }.filter { $0 != owner && !guides.contains($0) }
        guard !(first == second && first != owner) else {
            throw unsupportedConstraints("a constraint between a subview and itself")
        }
        let sibling = Set(subviews).count == 2
        if guides.contains(first) || second.map(guides.contains) == true {
            guard subviews.count == 1 else { throw unsupportedConstraints("a constraint between the safe area and its view") }
        }
        let relation = try attributes["relation"].map { name in
            guard let relation = Self.relations[name] else { throw unsupported("relation=\"\(name)\"") }
            return relation
        } ?? 0
        let priority = try attributes["priority"].map { text in
            guard let priority = Int(text), (1...1000).contains(priority) else { throw unsupported("priority=\"\(text)\"") }
            return priority
        } ?? 1000
        let symbolic = try bool(element, "symbolic", default: false)
        if attributes["symbolType"] != nil {
            try value(element, "symbolType", in: ["layoutAnchor"])
            guard !symbolic else { throw unsupportedConstraints("a constraint both symbolic and with a symbol type") }
        }
        let anchored = attributes["symbolType"] != nil
        let written = try attributes["constant"].map { try number($0, "constant") } ?? 0
        // A symbolic constraint's constant, IB's standard spacing, is not written (`symbolic-*`), nor
        // is an anchor's (`cs-symbol-anchor*`).
        let constant = symbolic || anchored ? 0 : written
        let nibConstraint = NibLayoutConstraint(try item(first, owner: owner), firstAttribute.number,
                                                try second.map { (try item($0, owner: owner), secondAttribute!.number) })
        nibConstraint.relation = relation
        nibConstraint.multiplier = try attributes["multiplier"].map(multiplier) ?? 1
        nibConstraint.constant = constant
        nibConstraint.priority = priority
        nibConstraint.identifier = attributes["identifier"].map { string($0) }
        nibConstraint.symbolicConstant = symbolic ? string("NSSpace") : anchored ? string("NSLayoutAnchorConstraintSpace") : nil
        nibConstraint.customClass = try customClass(element, original: "NSLayoutConstraint")
        let margins = firstAttribute.plain != nil || secondAttribute?.plain != nil
        if margins {
            guard !anchored, !guides.contains(first), !(second.map(guides.contains) ?? false) else {
                throw unsupportedConstraints("a constraint to layout margins with an anchor's symbol type or the safe area")
            }
            nibConstraint.legacyAttributes = (firstAttribute.plain, secondAttribute?.plain)
            nibConstraint.marginOffset = try (secondAttribute.map { try marginOffset($0, of: second) } ?? 0) - marginOffset(firstAttribute, of: first)
        }
        let variations = try element.children(named: "variation").map { variation in
            try check(variation, attributes: ["key", "constant"], children: [])
            guard let text = variation.attributes["constant"], !symbolic, !anchored else { throw unsupported("this variation of a constraint") }
            return (try sizeClasses(variation), try number(text, "constant"))
        }
        if !variations.isEmpty {
            traitStorages.append(TraitStorage(object: nibConstraint, keyPath: string("encodedConstant"),
                                              variations: variations.map { ($0.0, .constant($0.1)) }, defaultValue: .constant(constant)))
            nibConstraint.constant = TraitStorage.value(variations, default: constant, device: deviceSizeClasses)
        }
        if let id = attributes["id"] {
            documentConstraints[id] = nibConstraint
        }
        for id in [first, second].compactMap({ $0 }) where !guides.contains(id) {
            try constrained(id)
        }
        // A view deeper than the subviews has its constraints to a guide before those to the view
        // (`deep-safe-*`; pocket-casts' FilterSettingsOverlayController), and so has a subview of a
        // cell's older content view, the cell's safe area being the guide (`cs-cvsafe-*`).
        let olderContent = documentViews[owner]?.parent.map { owner == "\($0).contentView" } ?? false
        let deepToGuide = second.map(guides.contains) == true && (olderContent || depth(of: first, in: owner) > 1)
        let guide = sibling ? 2 : guides.contains(first) || deepToGuide ? 0 : second.map(guides.contains) == true ? 2 : 1
        let order = guide == 1 ? Self.viewAttributeOrder : Self.guideAttributeOrder
        var names = (firstAttribute.name, secondAttribute?.name)
        var groupItem = first
        var relationKey = relation
        let normalized = guide == 1 && first == owner && second != nil && second != owner
        if normalized, let second, let secondName = names.1 {
            names = (secondName, names.0)
            groupItem = second
            relationKey = -relation
        }
        var ranks = (firstAttribute.plain == nil ? 1 : 0, secondAttribute.map { $0.plain == nil ? 1 : 0 } ?? 0)
        if normalized { ranks = (ranks.1, ranks.0) }
        var attributeKey = [order.firstIndex(of: names.0)! * 2 + ranks.0, names.1.map { order.firstIndex(of: $0)! * 2 + ranks.1 } ?? -1]
        if guide == 1 {
            func index(_ attribute: (name: String, number: Int, plain: Int?, offset: Double)) -> Int {
                Self.viewMarginOrder.firstIndex(of: attribute.name + (attribute.plain == nil ? "" : "~"))!
            }
            attributeKey = [index(firstAttribute), secondAttribute.map(index) ?? -1]
        }
        let other = normalized ? first : second
        let centers = ["centerX", "centerY"]
        let byCenter = guide == 1 && !centers.contains(firstAttribute.name) && centers.contains(secondAttribute?.name ?? "")
        let depth = other.map { depth(of: $0, in: owner) } ?? 0
        let key = [depth > 1 ? -depth : 0, guide, byCenter ? attributeKey[1] : attributeKey[0]] + attributeKey
            + [priority, relationKey == -1 ? 0 : relationKey == 1 ? 1 : 2]
        return (groupItem, key, normalized, nibConstraint)
    }

    /// A view's safe area guide, with the identifier strings of the nib's other guides.
    mutating func safeAreaLayoutGuide(of view: NibView) -> NibViewLayoutGuide {
        NibViewLayoutGuide(owningView: view, identifier: string("UIViewSafeAreaLayoutGuide"),
                           constraintIdentifiers: ["top", "left", "bottom", "right"].map { string("UIViewSafeAreaLayoutGuide-\($0)") })
    }

    /// The view, or the safe area guide its view lists once a constraint refers to it.
    private mutating func item(_ id: String, owner: String) throws -> NibArchivable {
        if let view = documentViews[id]?.view { return view }
        if let guide = scrollGuides[id], let scroll = documentViews[guide.owner]?.view {
            if let object = scrollGuideObjects[id] { return object }
            let name = "UIScrollView-\(guide.content ? "content" : "frame")LayoutGuide"
            let object = NibScrollLayoutGuide(owningView: scroll, content: guide.content, identifier: string(name),
                                              constraintIdentifiers: (guide.content ? ["minX", "minY"] : ["minX", "minY", "width", "height"]).map { string("\(name)-\($0)") })
            scrollGuideObjects[id] = object
            return object
        }
        if let guideOwner = keyboardGuides[id], let view = documentViews[guideOwner]?.view {
            if let object = keyboardGuideObjects[id] { return object }
            let object = NibKeyboardLayoutGuide(owningView: view, identifier: string("UIViewKeyboardLayoutGuide"))
            keyboardGuideObjects[id] = object
            return object
        }
        let view = documentViews[owner]!.view
        if view.layoutGuides.isEmpty {
            view.layoutGuides = [safeAreaLayoutGuide(of: view)]
        }
        return view.layoutGuides[0]
    }

    /// Marks a view that takes part in a constraint: one that does not translate its mask writes so
    /// (`order-sibling`, `constraint-root-height`), with the mask its document gives, or the
    /// default one (`no-translate-mask-*`, round 64).
    mutating func constrained(_ id: String) throws {
        guard let entry = documentViews[id], !entry.translates else { return }
        entry.view.flags.doesNotTranslateAutoresizingMask = true
        if !entry.hasMask {
            entry.view.autoresizingMask = NibView.defaultAutoresizingMask
        }
    }

    /// The groups in order: the view's own constraints, then the others by how far their frames'
    /// origins lie from their superview's (the safe area at 0, 0), then by id (`order-two-*`,
    /// `sib-frames-*`, `cell-frames-*`, `view-frames-*`: every pair of frames observed, in views and
    /// cells' content views; 741 of the corpus's 758 matched views), frames partly outside the view
    /// too (`frames-outside-*`, `mask-group-*`), wholly outside or of no size (`outside-*`), a scene's
    /// layout guides at its top and bottom edges (`sb-guide-bottom-position`); at the same distance
    /// the lesser x first (`same-distance-*`). Frames as far apart above each other are refused.
    private func orderedItems(_ items: [String], owner: String, guides: Set<String>) throws -> [String] {
        let others = items.filter { $0 != owner }
        typealias Frame = (x: Double, y: Double, width: Double, height: Double)
        func frame(_ id: String) -> Frame {
            guard !guides.contains(id), let frame = self.frame(of: id, in: owner) else { return (0, 0, 0, 0) }
            return frame
        }
        let frames = Dictionary(uniqueKeysWithValues: others.map { ($0, frame($0)) })
        func distance(_ id: String) -> Double { frames[id]!.x * frames[id]!.x + frames[id]!.y * frames[id]!.y }
        func ancestors(_ id: String) -> [String] {
            var chain: [String] = []
            var current = documentViews[id]?.parent
            while let parent = current, parent != owner {
                chain.append(parent)
                current = documentViews[parent]?.parent
            }
            return chain
        }
        let containing = others.reduce(into: [String: String]()) { result, id in result[id] = ancestors(id).first { others.contains($0) } }
        // An item inside another listed item comes right after it, nearer or not
        // (`deep-negative-offset`; cwa's OnboardingInfoViewController); an unrelated item between
        // their distances makes ibtool's order depend on its sort (`deep-negative-offset-sibling`).
        // At the same distance, the frame of the lesser x first (`same-distance-*`).
        func key(_ id: String) -> (Double, Int, Double, String) {
            guard let ancestor = containing[id], distance(id) < distance(ancestor) else { return (distance(id), 0, frames[id]!.x, id) }
            let (low, high) = (distance(id), distance(ancestor))
            if others.contains(where: { $0 != id && $0 != ancestor && containing[$0] != ancestor && distance($0) >= low && distance($0) < high }) {
                return (-1, 0, 0, id)
            }
            return (high, ancestors(id).count + 1, frames[id]!.x, id)
        }
        if others.contains(where: { key($0).0 == -1 }) {
            throw unsupportedConstraints("constraints of a view nearer the origin than the subview holding it, with another between them")
        }
        let sorted = others.sorted { key($0) < key($1) }
        for (a, b) in zip(sorted, sorted.dropFirst()) where key(a).0 == key(b).0 && key(a).1 == key(b).1 && key(a).2 == key(b).2
            && frames[a]!.y != frames[b]!.y {
            throw unsupportedConstraints("constraints of subviews whose frames lie as far from their superview's origin above each other")
        }
        return (items.contains(owner) ? [owner] : []) + sorted
    }

    /// Moves a constraint to the view ibtool installs it on, its items' nearest common ancestor when
    /// that is a descendant of the view that lists it, where it sorts as one of that view's own
    /// (`moved-*`; pocket-casts' FilterNameCell, VideoViewController); a constraint of one item
    /// stays where it is listed (`symbolic-width`). A safe area guide stands for its view. Returns,
    /// by element, the views that listed the moved constraints that do not name their new view.
    private mutating func installWhereIbtoolDoes(_ pending: inout [PendingConstraints]) throws -> [(element: XIBElement, listing: String, target: String)] {
        func ancestors(_ id: String) -> [String] {
            var chain = [safeAreaGuides[id] ?? scrollGuides[id]?.owner ?? keyboardGuides[id] ?? id]
            while let parent = documentViews[chain.last!]?.parent { chain.append(parent) }
            return chain
        }
        var moved: [(element: XIBElement, listing: String, target: String)] = []
        var kept: [PendingConstraints] = []
        for group in pending {
            var elements: [XIBElement] = []
            for element in group.elements {
                let items = [element.attributes["firstItem"] ?? group.owner] + [element.attributes["secondItem"]].compactMap { $0 }
                let chains = items.map(ancestors)
                guard element.name == "constraint", items.count == 2, chains.allSatisfy({ $0.contains(group.owner) }),
                      let common = chains[0].first(where: { id in chains.allSatisfy { $0.contains(id) } }), common != group.owner else {
                    elements.append(element)
                    continue
                }
                moved.append((element, group.owner, common))
            }
            kept.append(PendingConstraints(owner: group.owner, elements: elements))
        }
        for (element, _, target) in moved {
            if let index = kept.firstIndex(where: { $0.owner == target }) {
                kept[index] = PendingConstraints(owner: target, elements: kept[index].elements + [element])
            } else {
                kept.append(PendingConstraints(owner: target, elements: [element]))
            }
        }
        pending = kept
        return moved.filter { entry in !([entry.element.attributes["firstItem"], entry.element.attributes["secondItem"]].contains(entry.target)) }
    }

    /// A moved constraint between two subviews of its new view stays, in all objects, with the cell
    /// that listed it, after the cell's own, in its new view's order (`moved-cell-labels`,
    /// `moved-cell-mixed`); from another view it is refused, not observed yet.
    private mutating func listMovedConstraints(_ moved: [(element: XIBElement, listing: String, target: String)]) throws {
        for (element, listing, target) in moved {
            guard let cell = documentViews[listing]?.view, case .cell = cell.kind else {
                throw unsupportedConstraints("a constraint between a subview's subviews listed by another view than a cell")
            }
            guard let id = element.attributes["id"], let constraint = documentConstraints[id], let view = documentViews[target]?.view else { continue }
            cell.movedOutConstraints.append(constraint)
            cell.movedOutConstraints.sort { a, b in view.constraints.firstIndex { $0 === a }! < view.constraints.firstIndex { $0 === b }! }
        }
    }

    /// Whether a constraint names a view deeper than `owner`'s subviews, which all objects lists in
    /// that constraint's place, so in a tie's order (`deep-other-*`).
    func namesDeeperView(_ constraint: NibLayoutConstraint, owner: String) -> Bool {
        let ids = Dictionary(documentViews.map { (ObjectIdentifier($0.value.view), $0.key) }) { first, _ in first }
        return ([constraint.first] + [constraint.second?.item].compactMap { $0 }).contains { item in
            ids[ObjectIdentifier(item)].map { depth(of: $0, in: owner) > 1 } ?? false
        }
    }

    /// Whether the document's frames satisfy a constraint, its items in `owner`'s coordinates: ties
    /// of such required constraints are written in document order, ibtool's own order being
    /// equivalent (ADR 0253). A safe area's edges are known across only: its insets above and
    /// below depend on the device; margins are not checked.
    func satisfiedByFrames(_ constraint: NibLayoutConstraint, owner: String) -> Bool {
        guard let ownerView = documentViews[owner] else { return false }
        let ids = Dictionary(documentViews.map { (ObjectIdentifier($0.value.view), $0.key) }) { first, _ in first }
        func value(_ item: NibArchivable, _ attribute: Int) -> Double? {
            let frame: (x: Double, y: Double, width: Double, height: Double)
            if item === ownerView.view {
                frame = (0, 0, ownerView.frame.width, ownerView.frame.height)
            } else if let guide = item as? NibViewLayoutGuide, guide.owningView === ownerView.view, [1, 2, 5, 6, 7, 9].contains(attribute) {
                frame = (0, 0, ownerView.frame.width, ownerView.frame.height)
            } else if let id = ids[ObjectIdentifier(item)], let inOwner = self.frame(of: id, in: owner) {
                frame = inOwner
            } else {
                return nil
            }
            switch attribute {
            case 1, 5: return frame.x
            case 2, 6: return frame.x + frame.width
            case 3: return frame.y
            case 4: return frame.y + frame.height
            case 7: return frame.width
            case 8: return frame.height
            case 9: return frame.x + frame.width / 2
            case 10: return frame.y + frame.height / 2
            default: return nil
            }
        }
        guard let first = value(constraint.first, constraint.firstAttribute) else { return false }
        let second = constraint.second.map { value($0.item, $0.attribute).map { $0 * constraint.multiplier } } ?? 0
        guard let second else { return false }
        let difference = first - (second + constraint.constant)
        switch constraint.relation {
        case -1: return difference <= 0.01
        case 1: return difference >= -0.01
        default: return abs(difference) <= 0.01
        }
    }

    /// How many levels below `owner` a view is: 1 for a subview, 0 for `owner` or another item.
    func depth(of id: String, in owner: String) -> Int {
        var depth = 0
        var current: String? = id
        while let view = current, view != owner {
            guard let parent = documentViews[view]?.parent else { return 0 }
            depth += 1
            current = parent
        }
        return current == owner ? depth : 0
    }

    /// The frame of a view of `owner`'s subtree in `owner`'s coordinates: a subview's own, a deeper
    /// view's moved by its ancestors' origins, through plain views, cells' content views and stack
    /// views (deeper views' groups sort by it: `deep-*`, `deep-through-stack`); nil for other views.
    func frame(of id: String, in owner: String) -> (x: Double, y: Double, width: Double, height: Double)? {
        guard let view = documentViews[id] else { return nil }
        var frame = view.frame
        var ancestor = view.parent
        while let ancestorID = ancestor, ancestorID != owner {
            guard let superview = documentViews[ancestorID] else { return nil }
            switch superview.view.kind {
            case .view, .cellContentView, .stack, .scroll: break
            default: return nil
            }
            frame.x += superview.frame.x
            frame.y += superview.frame.y
            ancestor = superview.parent
        }
        return ancestor == owner ? frame : nil
    }

    /// An attribute: its name for sorting (a margin's plain attribute), its number, the plain
    /// attribute's for a margin, and the margin's offset from its plain attribute: IB's 8 points
    /// in every container (`margin-*`: a xib's root view and subviews, cells' content views, scenes'
    /// views on every device), 0 for the centers within margins.
    /// The legacy constant a margin attribute adds: the margin of its item on that side, 8 points
    /// for a view without layout margins of its own (`margin-*`; the corpus's cwa
    /// ExposureSubmissionTestResultHeaderView, margins of 0, 16 and 24).
    private func marginOffset(_ attribute: (name: String, number: Int, plain: Int?, offset: Double), of id: String?) throws -> Double {
        guard attribute.plain != nil, let margins = id.flatMap({ documentViews[$0]?.view.layoutMargins }) else { return attribute.offset }
        let sides = ["left": margins[1], "leading": margins[1], "top": margins[0], "right": -margins[3], "trailing": -margins[3], "bottom": -margins[2]]
        guard let offset = sides[attribute.name] else { throw unsupportedConstraints("a constraint to the center within the layout margins of a view with margins") }
        return offset
    }

    private func layoutAttribute(_ name: String?) throws -> (name: String, number: Int, plain: Int?, offset: Double) {
        guard let name else { throw unsupported("the layout attribute none") }
        if let number = Self.layoutAttributes[name] { return (name, number, nil, 0) }
        guard let (plain, number, offset) = Self.marginAttributes[name] else { throw unsupported("the layout attribute \(name)") }
        return (plain, number, Self.layoutAttributes[plain]!, offset)
    }

    static let marginAttributes: [String: (plain: String, number: Int, offset: Double)] = [
        "leftMargin": ("left", 13, 8), "rightMargin": ("right", 14, -8), "topMargin": ("top", 15, 8), "bottomMargin": ("bottom", 16, -8),
        "leadingMargin": ("leading", 17, 8), "trailingMargin": ("trailing", 18, -8), "centerXWithinMargins": ("centerX", 19, 0),
        "centerYWithinMargins": ("centerY", 20, 0),
    ]

    /// `multiplier`: a number, or a ratio written `a:b` or `a/b`, rounded to a float
    /// (`constraint-multiplier-*`: 1/3, 1:3 and 0.33333333333333331 give 0.3333333432674408).
    private func multiplier(_ text: String) throws -> Double {
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "/" })
        let value = parts.count == 2 ? try number(String(parts[0]), "multiplier") / number(String(parts[1]), "multiplier")
            : try number(text, "multiplier")
        return Double(Float(value))
    }

    func unsupportedConstraints(_ what: String) -> NomacError {
        NomacError("nomac does not compile \(what) yet (BACKLOG B-265)", path: path)
    }
}
