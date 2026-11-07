import Foundation

/// What a `UITableView` writes after a view's keys (docs/formats/nib.md "Table views",
/// nib-experiments `table-*`): its scroll view's, then its style, separators, row and section
/// heights.
struct TableContent {
    /// Its table view controller's refresh control, after its bounce (`sb-tvc-refresh*`).
    var refreshControl: NibView?
    /// The `<tableView>` attributes observed, besides a view's.
    static let attributes = ["dataMode", "alwaysBounceVertical", "style", "separatorStyle", "rowHeight", "estimatedRowHeight", "sectionHeaderHeight",
                             "sectionFooterHeight", "keyboardDismissMode", "indicatorStyle", "allowsSelection", "allowsSelectionDuringEditing", "scrollEnabled",
                             "estimatedSectionHeaderHeight", "estimatedSectionFooterHeight", "showsHorizontalScrollIndicator", "showsVerticalScrollIndicator",
                             "bounces", "bouncesZoom", "canCancelContentTouches", "delaysContentTouches", "allowsMultipleSelection",
                             "allowsMultipleSelectionDuringEditing", "contentViewInsetsToSafeArea"]
    /// `UITableViewCell.SeparatorStyle` of the styles observed, written once, twice or three times
    /// (`table-separator-*`).
    static let separatorStyles = ["none": 0, "default": 1, "singleLineEtched": 2]
    /// `UITableView.Style`: plain 0, grouped 1, insetGrouped 2; `UIStyle` 1 for both grouped ones.
    let style: Int
    let separatorStyle: Int
    var alwaysBounceVertical: Bool
    var bounces = true
    var showsHorizontalScrollIndicator = true
    var delaysContentTouches = true
    var canCancelContentTouches = true
    var bouncesZoom = true
    var estimatedSectionHeaderHeight: Float = 0
    var estimatedSectionFooterHeight: Float = 0
    var allowsMultipleSelection = false
    var allowsMultipleSelectionDuringEditing = false
    var insetsContentViewsToSafeArea = true
    var separatorColor: NibColor?
    var sectionIndexBackgroundColor: NibColor?
    var separatorInset: [Double]?
    /// `scrollEnabled="NO"` (`table-scroll-disabled`).
    var scrollDisabled = false
    var keyboardDismissMode: Int?
    var indicatorStyle: Int?
    var allowsSelection: Bool
    var allowsSelectionDuringEditing: Bool
    let rowHeight: Float
    let sectionHeaderHeight: Float
    let sectionFooterHeight: Float
    let estimatedRowHeight: Float
    /// Prototype cells, each a nib of its own, by reuse identifier in alphabetical order
    /// (`sb-tvc-prototype-*`), with their segues' external objects: each placeholder of the
    /// prototype's nib, keyed by the view nib's string of that name, to the view nib's placeholder
    /// (`sb-cellseg-accessory-*`).
    var prototypes: [(reuseIdentifier: NibString, nib: Data, segues: [(NibString, NibProxy)])] = []

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.integer(1), forKey: "UIScrollViewIndicatorInsetAdjustmentBehavior")
        if let indicatorStyle { encoder.encode(.integer(indicatorStyle), forKey: "UIIndicatorStyle") }
        if !bounces { encoder.encode(.boolean(false), forKey: "UIBounceEnabled") }
        if !showsHorizontalScrollIndicator { encoder.encode(.boolean(false), forKey: "UIShowsHorizontalScrollIndicator") }
        if scrollDisabled { encoder.encode(.boolean(true), forKey: "UIScrollDisabled") }
        if !delaysContentTouches { encoder.encode(.boolean(false), forKey: "UIDelaysContentTouches") }
        if !canCancelContentTouches { encoder.encode(.boolean(false), forKey: "UICanCancelContentTouches") }
        if bouncesZoom { encoder.encode(.boolean(true), forKey: "UIBouncesZoom") }
        if alwaysBounceVertical { encoder.encode(.boolean(true), forKey: "UIAlwaysBounceVertical") }
        if let refreshControl { try encoder.encode(refreshControl, forKey: "UIRefreshControl") }
        if let keyboardDismissMode { encoder.encode(.integer(keyboardDismissMode), forKey: "UIKeyboardDismissMode") }
        encoder.encode(.integer(0), forKey: "UIScrollViewContentInsetAdjustmentBehavior")
        encoder.encode(.integer(style), forKey: "UITableViewStyle")
        encoder.encode(.integer(style == 0 ? 0 : 1), forKey: "UIStyle")
        if separatorStyle != 0 {
            encoder.encode(.integer(separatorStyle), forKey: "UISeparatorStyle")
            encoder.encode(.integer(separatorStyle), forKey: "UISeparatorStyleIOS5AndLater")
        }
        if separatorStyle != 1 { encoder.encode(.integer(separatorStyle), forKey: "UISeparatorStyleIOS9AndLater") }
        encoder.encode(.boolean(true), forKey: "UIPrefetchingEnabled")
        encoder.encode(.float(rowHeight), forKey: "UIRowHeight")
        encoder.encode(.float(sectionHeaderHeight), forKey: "UISectionHeaderHeight")
        encoder.encode(.float(sectionFooterHeight), forKey: "UISectionFooterHeight")
        encoder.encode(.float(estimatedRowHeight), forKey: "UIEstimatedRowHeight")
        encoder.encode(.float(estimatedSectionHeaderHeight), forKey: "UIEstimatedSectionHeaderHeight")
        encoder.encode(.float(estimatedSectionFooterHeight), forKey: "UIEstimatedSectionFooterHeight")
        encoder.encode(.double(0), forKey: "UIFillerRowHeight")
        encoder.encode(.double(-1), forKey: "UISectionHeaderTopPadding")
        if !allowsSelection { encoder.encode(.boolean(false), forKey: "UIAllowsSelection") }
        if allowsSelectionDuringEditing { encoder.encode(.boolean(true), forKey: "UIAllowsSelectionDuringEditing") }
        if allowsMultipleSelection { encoder.encode(.boolean(true), forKey: "UIAllowsMultipleSelection") }
        if allowsMultipleSelectionDuringEditing { encoder.encode(.boolean(true), forKey: "UIAllowsMultipleSelectionDuringEditing") }
        encoder.encode(.boolean(insetsContentViewsToSafeArea), forKey: "UIInsetsContentViewsToSafeArea")
        if let separatorColor { try encoder.encode(separatorColor, forKey: "UISeparatorColor") }
        if let sectionIndexBackgroundColor { try encoder.encode(sectionIndexBackgroundColor, forKey: "UISectionIndexBackgroundColor") }
        if let separatorInset { encoder.encode(.data(NibView.doubles(separatorInset)), forKey: "UISeparatorInset") }
        if !prototypes.isEmpty {
            let nibs = NibDictionary(), externals = NibDictionary()
            nibs.mutable = true
            externals.mutable = true
            for prototype in prototypes {
                nibs.entries.append((prototype.reuseIdentifier, NibNestedNib(prototype.nib)))
                let objects = NibDictionary()
                objects.mutable = true
                objects.entries = prototype.segues
                externals.entries.append((prototype.reuseIdentifier, objects))
            }
            try encoder.encode(nibs, forKey: "UITableViewCellPrototypeNibs")
            try encoder.encode(externals, forKey: "UITableViewCellPrototypeNibExternalObjects")
        }
        encoder.encode(.integer(0), forKey: "UISeparatorInsetReference")
    }
}

/// A static table's `UITableViewDataSource`: its sections of rows, each row a cell of height -1;
/// a top-level object of the table's nib, which File's Owner refers to as `staticDataSource`
/// (`sb-tvc-static*`). All objects lists sections and cells, not rows.
final class NibStaticDataSource: NibArchivable, NibObjectChildren {
    let sections: [NibTableSection]

    init(sections: [NibTableSection]) {
        self.sections = sections
    }

    var className: String { "UITableViewDataSource" }
    var childObjects: [NibArchivable] { sections }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(NibArray(sections), forKey: "UITableSections")
    }
}

final class NibTableSection: NibArchivable, NibObjectChildren {
    let headerTitle: NibArchivable?
    let cells: [NibView]
    let rowHeights: [Float]

    init(headerTitle: NibArchivable?, cells: [NibView], rowHeights: [Float]) {
        self.headerTitle = headerTitle
        self.cells = cells
        self.rowHeights = rowHeights
    }

    var className: String { "UITableViewSection" }
    var childObjects: [NibArchivable] { cells }

    func encode(to encoder: NibEncoder) throws {
        if let headerTitle { try encoder.encode(headerTitle, forKey: "UITableSectionHeaderTitle") }
        try encoder.encode(NibArray(zip(cells, rowHeights).map(NibTableRow.init)), forKey: "UITableSectionRows")
    }
}

/// A static cell's row: its cell and height, -1 without a `rowHeight` (`cm-sb-static-row-*`).
final class NibTableRow: NibArchivable {
    let cell: NibView
    let height: Float

    init(_ cell: NibView, height: Float) {
        self.cell = cell
        self.height = height
    }

    var className: String { "UITableViewRow" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(cell, forKey: "UITableRowCell")
        encoder.encode(.float(height), forKey: "UITableRowHeight")
    }
}

/// A nested nib: `UINib` of its archive's data, the enclosing nib's bundle captured.
final class NibNestedNib: NibArchivable {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    var className: String { "UINib" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.boolean(true), forKey: "captureEnclosingNIBBundleOnDecode")
        try encoder.encode(NibData(data), forKey: "archiveData")
    }
}

/// `NSData`: its bytes as `NS.bytes`.
final class NibData: NibArchivable {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    var className: String { "NSData" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.data(Array(data)), forKey: "NS.bytes")
    }
}

extension DocumentCompiler {
    /// A `<tableView>`'s own attributes; a grouped one gets the `systemGroupedBackgroundColor`
    /// background (`table-grouped`, `table-inset-grouped`).
    mutating func tableContent(_ element: XIBElement) throws -> TableContent {
        let attributes = element.attributes
        guard let style = ["plain": 0, "grouped": 1, "insetGrouped": 2][attributes["style"] ?? "plain"] else {
            throw unsupported("style=\"\(attributes["style"] ?? "")\" in <tableView>")
        }
        try value(element, "dataMode", in: ["prototypes", "static"])
        var sections: [NibTableSection] = []
        for container in element.children(named: "sections") {
            // An empty `<sections/>` of a prototypes table, as Xcode's Master-Detail template has it,
            // changes nothing (`sb-tvc-empty-sections`).
            guard element.attributes["dataMode"] == "static" || container.children.isEmpty else {
                throw unsupported("sections of a table view without dataMode=\"static\"")
            }
            try check(container, attributes: [], children: ["tableViewSection"])
            for section in container.children {
                try check(section, attributes: ["headerTitle", "id"], children: ["cells"])
                var cells: [NibView] = []
                var rowHeights: [Float] = []
                for cellContainer in section.children {
                    try check(cellContainer, attributes: [], children: ["tableViewCell"])
                    for cell in cellContainer.children {
                        guard cell.children(named: "frame").isEmpty else { throw unsupported("<frame> in a static <tableViewCell>") }
                        rowHeights.append(Float(try number(cell.attributes["rowHeight"] ?? "-1", "rowHeight")))
                        cells.append(try tableViewCell(cell))
                    }
                }
                sections.append(NibTableSection(headerTitle: section.attributes["headerTitle"].map { text($0, id: section.attributes["id"], property: "headerTitle") },
                                                cells: cells, rowHeights: rowHeights))
            }
        }
        if !sections.isEmpty {
            staticDataSource = NibStaticDataSource(sections: sections)
        }
        var identifiers = Dictionary(cellSeguePlaceholders.values.flatMap { $0.map { ($0.placeholder.identifier.value, $0.placeholder.identifier) } }) { first, _ in first }
        if let upstreamIdentifier { identifiers[upstreamIdentifier.value] = upstreamIdentifier }
        var prototypes: [(NibString, Data, [(NibString, NibProxy)])] = []
        for container in element.children(named: "prototypes") {
            try check(container, attributes: [], children: ["tableViewCell"])
            for cell in container.children {
                // ibtool warns of a prototype cell without a reuse identifier, or an empty one, and
                // leaves it out (`cm-sb-proto-no-reuse-*`, `cm-sb-proto-empty-reuse`).
                guard let reuseIdentifier = cell.attributes["reuseIdentifier"], !reuseIdentifier.isEmpty else {
                    guard cell.children(named: "connections").isEmpty else { throw unsupported("a prototype cell without a reuse identifier (ibtool warns)") }
                    warnings.append((cell.attributes["id"] ?? "", "Prototype table cells must have reuse identifiers [9]"))
                    continue
                }
                let segues = cellSeguePlaceholders[cell.attributes["id"] ?? ""] ?? []
                let keys = try segues.indices.map { index -> NibString in
                    guard let key = identifiers["UpstreamPlaceholder-\(index + 1)"] else { throw unsupported("a prototype cell's segue placeholder of no name in its view nib") }
                    return key
                }
                prototypes.append((string(reuseIdentifier), try prototypeNib(cell, segues: segues.map(\.accessory)), zip(keys, segues.map(\.placeholder)).map { ($0, $1) }))
            }
        }
        var content = try tableAttributes(element, style: style)
        content.separatorColor = try element.child("color", key: "separatorColor").map { try color($0) }
        content.sectionIndexBackgroundColor = try element.child("color", key: "sectionIndexBackgroundColor").map { try color($0) }
        for inset in element.children(named: "inset") {
            try check(inset, attributes: ["key", "minX", "minY", "maxX", "maxY"], children: [])
            try value(inset, "key", in: ["separatorInset"])
            content.separatorInset = try ["minY", "minX", "maxY", "maxX"].map { try number(inset.attributes[$0] ?? "0", $0) }
        }
        content.scrollDisabled = !(try bool(element, "scrollEnabled", default: true))
        content.prototypes = prototypes.sorted { $0.0.value < $1.0.value }.map { ($0.0, $0.1, $0.2) }
        return content
    }

    /// A prototype cell's nib: File's Owner, First Responder and the cell, compiled as a xib's cell
    /// with the document's shared objects.
    /// A prototype cell whose segues the controller holds refers to them through the nib's own
    /// `UpstreamPlaceholder-1`, `-2`, after First Responder, in their document order
    /// (`sb-cellseg-prototype-*`, `sb-cellseg-accessory-*`).
    mutating func prototypeNib(_ element: XIBElement, segues: [Bool], controller: String? = nil) throws -> Data {
        var nested = self
        nested.controllerNibPlaceholders = []
        nested.documentViews = [:]
        nested.safeAreaGuides = [:]
        nested.scrollGuides = [:]
        nested.scrollGuideObjects = [:]
        nested.keyboardGuides = [:]
        nested.keyboardGuideObjects = [:]
        nested.pendingConstraints = []
        nested.pendingOutlets = []
        nested.placeholders = [:]
        nested.documentConstraints = [:]
        nested.traitStorages = []
        nested.relationshipStorages = []
        nested.keyValuePairs = []
        nested.accessibilityConfigurations = []
        nested.cellSegueOutlets = []
        nested.emptyArray = NibArray([])
        let owner = NibProxy(identifier: "IBFilesOwner"), responder = NibProxy(identifier: "IBFirstResponder")
        let placeholders = segues.indices.map { NibProxy(identifier: "UpstreamPlaceholder-\($0 + 1)") }
        if let id = element.attributes["id"], !segues.isEmpty {
            nested.cellSeguePlaceholders = [id: zip(segues, placeholders).map { ($0, $1) }]
        }
        let upstream = controller.map { _ in NibProxy(identifier: "UpstreamPlaceholder-1") }
        if let controller, let upstream { nested.placeholders[controller] = upstream }
        let cell: NibArchivable = switch element.name {
        case "collectionViewCell": try nested.collectionViewCell(element, prototype: true)
        case "collectionReusableView": try nested.collectionReusableView(element)
        default: try nested.tableViewCell(element)
        }
        try nested.compileConstraints()
        let topLevel: [NibArchivable] = [owner, responder] + placeholders + (upstream.map { [$0] } ?? []) + [cell]
        let all = Self.allObjects(topLevel)
        let nib = try NibEncoder.archive(NibRoot(topLevelObjects: topLevel, allObjects: all,
                                                 connections: try nested.outletConnections(allObjects: all, extra: nested.cellSegueOutlets),
                                                 accessibilityConfigurations: nested.takeAccessibilityConfigurations(allObjects: all),
                                                 traitStorageLists: try nested.traitStorageLists(topLevel), keyValuePairs: nested.takeKeyValuePairs(allObjects: all),
                                                 empty: nested.emptyArray))
        warnings = nested.warnings
        strings = nested.strings
        colors = nested.colors
        fonts = nested.fonts
        images = nested.images
        requiredVersion = max(requiredVersion, nested.requiredVersion)
        return nib
    }

    func tableAttributes(_ element: XIBElement, style: Int) throws -> TableContent {
        let attributes = element.attributes
        func height(_ name: String, _ fallback: String? = nil) throws -> Float {
            guard let text = attributes[name] ?? fallback else { throw unsupported("a table view without \(name)") }
            return Float(try number(text, name))
        }
        var content = TableContent(style: style, separatorStyle: try mapped(attributes["separatorStyle"] ?? "default", TableContent.separatorStyles, "separatorStyle"),
                            alwaysBounceVertical: try bool(element, "alwaysBounceVertical", default: false),
                            keyboardDismissMode: try attributes["keyboardDismissMode"].map { try mapped($0, ["onDrag": 1, "interactive": 2], "keyboardDismissMode") },
                            indicatorStyle: try attributes["indicatorStyle"].map { try mapped($0, ["white": 2], "indicatorStyle") },
                            allowsSelection: try bool(element, "allowsSelection", default: true),
                            allowsSelectionDuringEditing: try bool(element, "allowsSelectionDuringEditing", default: false),
                            rowHeight: try height("rowHeight"), sectionHeaderHeight: try height("sectionHeaderHeight"),
                            sectionFooterHeight: try height("sectionFooterHeight"), estimatedRowHeight: try height("estimatedRowHeight", "0"))
        content.bounces = try bool(element, "bounces", default: true)
        content.showsHorizontalScrollIndicator = try bool(element, "showsHorizontalScrollIndicator", default: true)
        content.delaysContentTouches = try bool(element, "delaysContentTouches", default: true)
        content.canCancelContentTouches = try bool(element, "canCancelContentTouches", default: true)
        content.bouncesZoom = try bool(element, "bouncesZoom", default: true)
        content.estimatedSectionHeaderHeight = try height("estimatedSectionHeaderHeight", "0")
        content.estimatedSectionFooterHeight = try height("estimatedSectionFooterHeight", "0")
        content.allowsMultipleSelection = try bool(element, "allowsMultipleSelection", default: false)
        content.allowsMultipleSelectionDuringEditing = try bool(element, "allowsMultipleSelectionDuringEditing", default: false)
        content.insetsContentViewsToSafeArea = try bool(element, "contentViewInsetsToSafeArea", default: true)
        return content
    }
}

extension DocumentCompiler {
    /// A table view controller's `<refreshControl>`: a view of IB's frame, 1000 x 1000 at the
    /// origin whatever the document says, writing `UIDisabled` when disabled and its style 2, and
    /// its actions (`sb-tvc-refresh*`).
    mutating func refreshControl(_ element: XIBElement) throws -> NibView {
        try check(element, attributes: ["key", "opaque", "multipleTouchEnabled", "contentMode", "insetsLayoutMarginsFromSafeArea", "enabled",
                                        "contentHorizontalAlignment", "contentVerticalAlignment", "id"], children: ["rect", "autoresizingMask", "connections"])
        try value(element, "contentHorizontalAlignment", in: ["center"])
        try value(element, "contentVerticalAlignment", in: ["center"])
        if let rect = element.child("rect", key: "frame") {
            guard rect.attributes == ["key": "frame", "x": "0.0", "y": "0.0", "width": "1000", "height": "1000"] else {
                throw unsupported("a refresh control of another frame than IB's")
            }
        }
        let viewElement = XIBElement(name: "view", attributes: element.attributes.filter {
            !["key", "enabled", "contentHorizontalAlignment", "contentVerticalAlignment"].contains($0.key)
        })
        viewElement.children = [XIBElement(name: "rect", attributes: ["key": "frame", "x": "0", "y": "0", "width": "1000", "height": "1000"])]
            + element.children(named: "autoresizingMask")
        let view = try self.view(viewElement, topLevel: false)
        view.kind = NibView.Kind.refreshControl(enabled: try bool(element, "enabled", default: true))
        try connections(of: element, source: view)
        return view
    }
}
