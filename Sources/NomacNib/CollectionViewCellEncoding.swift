import Foundation

/// What a `UICollectionViewCell` writes after a view's keys (docs/formats/nib.md "Collection view
/// cells"; nib-experiments `cvcell-*`): its reuse identifier, no system background or content
/// configuration view, and its content view.
struct CollectionCellContent {
    var reuseIdentifier: NibString?
    let contentView: NibView
    /// A cell of the template before Xcode 12 (`<view key="contentView">`), whose content view
    /// all objects skips, listing its subviews and constraints after the cell's safe area.
    let legacy: Bool

    func encode(to encoder: NibEncoder) throws {
        if let reuseIdentifier { try encoder.encode(reuseIdentifier, forKey: "UIReuseIdentifier") }
        encoder.encode(.null, forKey: "UISystemBackgroundView")
        encoder.encode(.null, forKey: "UIContentConfigurationView")
        try encoder.encode(contentView, forKey: "UIContentView")
    }
}

extension DocumentCompiler {
    /// A `<collectionViewCell>` of a xib: the cell as a view whose one subview is its content view,
    /// pinned to it by four constraints IB generates (leading, trailing, top, bottom, named
    /// `UIIBSystemGenerated`, not listed in all objects). The content view of Xcode 12's template
    /// (`<collectionViewCellContentView>`) is compiled as a view; the older `<view
    /// key="contentView">` is a plain view whatever its attributes, the cell's constraints move to
    /// it with the cell's id standing for it, and it lists its safe area guide when the cell has a
    /// safe area and the content view has subviews (`cvcell-old*`). The content view always writes
    /// `UIViewDoesNotTranslateAutoresizingMaskIntoConstraints`, and keeps its mask
    /// (`cvcell-*content-mask-*`). Constraints of a cell of Xcode
    /// 12's template, which ibtool drops (`cvcell-label-cell-constraints`), are refused.
    /// A storyboard's prototype cell (the older template) has neither the generated constraints nor a
    /// content view that does not translate its mask (`sb-collection-cell*`).
    mutating func collectionViewCell(_ element: XIBElement, prototype: Bool = false) throws -> NibView {
        try check(element, attributes: ["id", "opaque", "clipsSubviews", "multipleTouchEnabled", "contentMode", "reuseIdentifier",
                                        "insetsLayoutMarginsFromSafeArea", "userLabel", "customClass", "customModule", "customModuleProvider"],
                  children: ["rect", "autoresizingMask", "view", "collectionViewCellContentView", "viewLayoutGuide", "size", "color", "connections",
                             "constraints", "point", "gestureRecognizers", "userDefinedRuntimeAttributes", "variation"])
        for recognizers in element.children(named: "gestureRecognizers") {
            try check(recognizers, attributes: [], children: [])
        }
        guard let id = element.attributes["id"] else { throw unsupported("a collection view cell without an id") }
        let contents = element.children.filter { ["view", "collectionViewCellContentView"].contains($0.name) }
        guard contents.count == 1, let content = contents.first, content.attributes["key"] == "contentView" else {
            throw unsupported("a collection view cell without one content view")
        }
        let legacy = content.name == "view"
        guard legacy || !prototype else { throw unsupported("a prototype collection view cell of Xcode 12's template") }
        for size in element.children(named: "size") {
            try check(size, attributes: ["key", "width", "height"], children: [])
            try value(size, "key", in: ["customSize"])
        }
        let contentID: String
        let contentElement: XIBElement
        if legacy {
            try check(content, attributes: ["key", "opaque", "clipsSubviews", "multipleTouchEnabled", "contentMode", "insetsLayoutMarginsFromSafeArea"],
                      children: ["rect", "autoresizingMask", "subviews"])
            contentID = "\(id).contentView"
            contentElement = XIBElement(name: "view", attributes: ["id": contentID])
            let moved = element.children(named: "constraints").flatMap(\.children).map { constraint in
                XIBElement(name: constraint.name, attributes: constraint.attributes.mapValues { $0 == id ? contentID : $0 })
            }
            let constraints = XIBElement(name: "constraints", attributes: [:])
            constraints.children = moved
            contentElement.children = content.children + (moved.isEmpty ? [] : [constraints]) + element.children(named: "variation")
        } else {
            guard element.children(named: "constraints").isEmpty, element.children(named: "variation").isEmpty else {
                throw unsupported("constraints or variations of a collection view cell of Xcode 12's template")
            }
            guard let identifier = content.attributes["id"] else { throw unsupported("a collection view cell content view without an id") }
            contentID = identifier
            contentElement = XIBElement(name: "view", attributes: content.attributes.filter { $0.key != "key" })
            contentElement.children = content.children
        }
        let subviews = XIBElement(name: "subviews", attributes: [:])
        subviews.children = [contentElement]
        let cellElement = XIBElement(name: "view", attributes: element.attributes.filter { $0.key != "reuseIdentifier" })
        cellElement.children = element.children.filter { !["view", "collectionViewCellContentView", "size", "constraints", "variation"].contains($0.name) } + [subviews]
        let cell = try view(cellElement, topLevel: true, originalClassName: "UICollectionViewCell")
        if legacy {
            safeAreaGuides = safeAreaGuides.filter { $0.value != id }
        }
        guard let contentView = cell.subviews.first else { throw unsupported("a collection view cell without a content view") }
        // Subviews the cell's default mask excludes do not count (`cvmask-old-subviews`).
        let excluded = element.children(named: "variation").filter { $0.attributes["key"] == "default" }.flatMap { $0.children(named: "mask") }
            .filter { $0.attributes["key"] == "subviews" }.flatMap { $0.children(named: "exclude") }.compactMap { $0.attributes["reference"] }
        let installed = contentView.subviews.filter { subview in !excluded.contains { documentViews[$0]?.view === subview } }
        if legacy, cell.safeAreaPlaceholder != nil, !installed.isEmpty {
            contentView.layoutGuides = [safeAreaLayoutGuide(of: contentView)]
        }
        // A prototype cell has them only with constraints of its own (`sb-cvmask-*`).
        if !prototype || !element.children(named: "constraints").isEmpty {
            contentView.flags.doesNotTranslateAutoresizingMask = true
            let generated = string("UIIBSystemGenerated")
            cell.guideConstraints = [5, 6, 3, 4].map { attribute in
                let constraint = NibLayoutConstraint(cell, attribute, (contentView, attribute))
                constraint.identifier = generated
                return constraint
            }
        }
        cell.kind = .collectionCell(CollectionCellContent(reuseIdentifier: element.attributes["reuseIdentifier"].map { string($0) },
                                                          contentView: contentView, legacy: legacy))
        return cell
    }

    /// A `<collectionReusableView>` of a xib: a view with its reuse identifier after a view's keys
    /// (`reusable-*`).
    mutating func collectionReusableView(_ element: XIBElement) throws -> NibView {
        let viewElement = XIBElement(name: "view", attributes: element.attributes.filter { $0.key != "reuseIdentifier" && $0.key != "key" })
        viewElement.children = element.children
        let view = try view(viewElement, topLevel: true, originalClassName: "UICollectionReusableView")
        view.kind = .reusableView(element.attributes["reuseIdentifier"].map { string($0) })
        return view
    }
}
