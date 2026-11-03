import Foundation

/// What a `UICollectionView` writes after a view's keys (docs/formats/nib.md "Collection views";
/// nib-experiments `collection-*`): a scroll view's, then its layout, multiple selection and
/// prefetching.
struct CollectionContent {
    var scroll: ScrollContent
    let layout: NibCollectionLayout
    var prefetchingEnabled: Bool
    /// Prototype cells, each a nib of its own, by reuse identifier in alphabetical order
    /// (`sb-collection-two-cells`).
    var prototypes: [(reuseIdentifier: NibString, nib: Data)] = []
    /// Section header and footer views, each a nib of its own, the footer first, by
    /// `<kind>/<reuse identifier>`, with the upstream placeholder its outlets to the controller use
    /// (`sb-section-*`).
    var sectionViews: [SectionView] = []

    struct SectionView {
        let key: NibString
        let nib: Data
        let upstream: (key: NibString, placeholder: NibProxy)?
    }

    func encode(to encoder: NibEncoder) throws {
        scroll.encode(to: encoder)
        try encoder.encode(layout, forKey: "UICollectionLayout")
        encoder.encode(.boolean(true), forKey: "UIAllowsUserInitiatedMultipleSelection")
        func dictionary(_ entries: [(NibArchivable, NibArchivable)] = []) -> NibDictionary {
            let dictionary = NibDictionary()
            dictionary.mutable = true
            dictionary.entries = entries
            return dictionary
        }
        if !prototypes.isEmpty {
            try encoder.encode(dictionary(prototypes.map { ($0.reuseIdentifier, dictionary()) }), forKey: "UICollectionViewCellPrototypeNibExternalObjects")
        }
        if !sectionViews.isEmpty {
            try encoder.encode(dictionary(sectionViews.map { view in (view.key, dictionary(view.upstream.map { [($0.key, $0.placeholder)] } ?? [])) }),
                               forKey: "UICollectionViewSupplementaryViewPrototypeNibExternalObjects")
        }
        if !prototypes.isEmpty {
            try encoder.encode(dictionary(prototypes.map { ($0.reuseIdentifier, NibNestedNib($0.nib)) }), forKey: "UICollectionViewCellNibDict")
        }
        if !sectionViews.isEmpty {
            try encoder.encode(dictionary(sectionViews.map { ($0.key, NibNestedNib($0.nib)) }), forKey: "UICollectionViewSupplementaryViewNibDict")
        }
        encoder.encode(.boolean(prefetchingEnabled), forKey: "UICollectionViewPrefetchingEnabled")
    }

    static let attributes = ScrollContent.attributes + ["dataMode", "prefetchingEnabled"]
}

/// A collection view's layout: a `UICollectionViewFlowLayout` with the values that differ from its
/// defaults (spacings 10, items 50 x 50, no header, footer or inset), or a custom layout, which
/// writes its class names only (`collection-flow-*`, `collection-custom-layout`).
final class NibCollectionLayout: NibArchivable {
    struct Flow {
        var interitemSpacing: Float = 10
        var lineSpacing: Float = 10
        var itemSize = [50.0, 50]
        var headerReferenceSize = [0.0, 0]
        var footerReferenceSize = [0.0, 0]
        var sectionInset = [0.0, 0, 0, 0]
        var sectionInsetFromSafeArea = false
        var horizontal = false
    }

    let flow: Flow?
    let customClass: (name: NibString, original: NibString)?

    init(flow: Flow?, customClass: (name: NibString, original: NibString)?) {
        self.flow = flow
        self.customClass = customClass
    }

    var className: String { customClass == nil ? "UICollectionViewFlowLayout" : "UIClassSwapper" }

    func encode(to encoder: NibEncoder) throws {
        if let flow {
            if flow.interitemSpacing != 10 { encoder.encode(.float(flow.interitemSpacing), forKey: "UIInteritemSpacing") }
            if flow.lineSpacing != 10 { encoder.encode(.float(flow.lineSpacing), forKey: "UILineSpacing") }
            if flow.itemSize != [50, 50] { encoder.encode(.data(NibView.doubles(flow.itemSize)), forKey: "UIItemSize") }
            if flow.headerReferenceSize != [0, 0] { encoder.encode(.data(NibView.doubles(flow.headerReferenceSize)), forKey: "UIHeaderReferenceSize") }
            if flow.footerReferenceSize != [0, 0] { encoder.encode(.data(NibView.doubles(flow.footerReferenceSize)), forKey: "UIFooterReferenceSize") }
            if flow.sectionInset != [0, 0, 0, 0] { encoder.encode(.data(NibView.doubles(flow.sectionInset)), forKey: "UISectionInset") }
            if flow.sectionInsetFromSafeArea { encoder.encode(.integer(1), forKey: "UISectionInsetReference") }
            if flow.horizontal { encoder.encode(.integer(1), forKey: "UIScrollDirection") }
        }
        if let customClass {
            try encoder.encode(customClass.name, forKey: "UIClassName")
            try encoder.encode(customClass.original, forKey: "UIOriginalClassName")
        }
    }
}

extension DocumentCompiler {
    /// A `<collectionView>`: its scroll view's content, its layout and, with `dataMode="prototypes"`, a nil
    /// delegate and its prototype cells, each compiled as a nib of its own (`sb-collection-*`); a white background is the system `systemBackgroundColor`
    /// (`collection-background-*`). `automaticEstimatedItemSize` is a runtime attribute of the layout,
    /// `estimatedItemSize` the greatest size (`collection-flow-estimated`).
    mutating func collectionContent(_ element: XIBElement) throws -> CollectionContent {
        try value(element, "dataMode", in: ["none", "prototypes"])
        let flows = element.children(named: "collectionViewFlowLayout"), customs = element.children(named: "collectionViewLayout")
        guard flows.count + customs.count == 1, let layoutElement = flows.first ?? customs.first, layoutElement.attributes["key"] == "collectionViewLayout" else {
            throw unsupported("a collection view without one layout")
        }
        let layout: NibCollectionLayout
        if layoutElement.name == "collectionViewFlowLayout" {
            try check(layoutElement, attributes: ["key", "id", "minimumLineSpacing", "minimumInteritemSpacing", "scrollDirection", "automaticEstimatedItemSize",
                                                  "sectionInsetReference", "customClass", "customModule", "customModuleProvider"],
                      children: ["size", "inset", "userDefinedRuntimeAttributes"])
            try value(layoutElement, "scrollDirection", in: ["vertical", "horizontal"])
            try value(layoutElement, "sectionInsetReference", in: ["safeArea"])
            var flow = NibCollectionLayout.Flow()
            flow.lineSpacing = Float(try number(layoutElement.attributes["minimumLineSpacing"] ?? "10", "minimumLineSpacing"))
            flow.interitemSpacing = Float(try number(layoutElement.attributes["minimumInteritemSpacing"] ?? "10", "minimumInteritemSpacing"))
            for size in layoutElement.children(named: "size") {
                try check(size, attributes: ["key", "width", "height"], children: [])
                let values = try ["width", "height"].map { try number(size.attributes[$0] ?? "0", $0) }
                switch size.attributes["key"] {
                case "itemSize": flow.itemSize = values
                case "headerReferenceSize": flow.headerReferenceSize = values
                case "footerReferenceSize": flow.footerReferenceSize = values
                default: throw unsupported("<size key=\"\(size.attributes["key"] ?? "")\"> in a collection view flow layout")
                }
            }
            for inset in layoutElement.children(named: "inset") {
                try check(inset, attributes: ["key", "minX", "minY", "maxX", "maxY"], children: [])
                try value(inset, "key", in: ["sectionInset"])
                flow.sectionInset = try ["minY", "minX", "maxY", "maxX"].map { try number(inset.attributes[$0] ?? "0", $0) }
            }
            flow.sectionInsetFromSafeArea = layoutElement.attributes["sectionInsetReference"] == "safeArea"
            flow.horizontal = layoutElement.attributes["scrollDirection"] == "horizontal"
            layout = NibCollectionLayout(flow: flow, customClass: try customClass(layoutElement, original: "UICollectionViewFlowLayout"))
            let estimated = try bool(layoutElement, "automaticEstimatedItemSize", default: false)
            guard !estimated || layoutElement.children(named: "userDefinedRuntimeAttributes").isEmpty else {
                throw unsupported("user-defined runtime attributes of a flow layout with an automatic estimated item size")
            }
            // A flow layout's own pairs are as a view's (`udra-flow-layout`).
            try runtimeAttributes(of: layoutElement, object: layout)
            if estimated {
                let greatest = "\(Double.greatestFiniteMagnitude)"
                keyValuePairs.append(NibKeyValuePair(object: layout, value: NibGeometryValue(special: 2, key: "NS.sizeval", text: string("{\(greatest), \(greatest)}")),
                                                     keyPath: string("estimatedItemSize")))
            }
        } else {
            try check(layoutElement, attributes: ["key", "id", "customClass", "customModule", "customModuleProvider"], children: [])
            guard let custom = try customClass(layoutElement, original: "UICollectionViewLayout") else {
                throw unsupported("a collection view layout without a custom class")
            }
            layout = NibCollectionLayout(flow: nil, customClass: custom)
        }
        var scroll = try scrollContent(element)
        scroll.nilDelegate = element.attributes["dataMode"] == "prototypes"
        var prototypes: [(reuseIdentifier: NibString, nib: Data)] = []
        for container in element.children(named: "cells") {
            try check(container, attributes: [], children: ["collectionViewCell"])
            for cell in container.children {
                guard let reuseIdentifier = cell.attributes["reuseIdentifier"] else { throw unsupported("a prototype cell without a reuse identifier") }
                prototypes.append((string(reuseIdentifier), try prototypeNib(cell, segues: [])))
            }
        }
        let sectionViews = try sectionViews(element)
        guard prototypes.isEmpty && sectionViews.isEmpty || scroll.nilDelegate else { throw unsupported("cells or section views of a collection view without prototypes") }
        return CollectionContent(scroll: scroll, layout: layout, prefetchingEnabled: try bool(element, "prefetchingEnabled", default: true),
                                 prototypes: prototypes.sorted { Array($0.reuseIdentifier.value.utf8).lexicographicallyPrecedes(Array($1.reuseIdentifier.value.utf8)) },
                                 sectionViews: sectionViews)
    }

    /// A collection view's section header and footer views, footer first. Without a reuse identifier
    /// ibtool warns and drops the view; with one, a nib of its own whose outlets to the controller go
    /// through its own `UpstreamPlaceholder-1` (`sb-section-*`). ibtool fails on two views of one
    /// reuse identifier (`sb-section-footer-same-reuse`).
    private mutating func sectionViews(_ element: XIBElement) throws -> [CollectionContent.SectionView] {
        let kinds = [("sectionFooterView", "UICollectionElementKindSectionFooter"), ("sectionHeaderView", "UICollectionElementKindSectionHeader")]
        let elements = kinds.compactMap { key, kind in element.child("collectionReusableView", key: key).map { ($0, kind) } }
        guard element.children(named: "collectionReusableView").count == elements.count else {
            throw unsupported("a collection view's <collectionReusableView> other than one header and one footer")
        }
        let reuseIdentifiers = elements.compactMap { $0.0.attributes["reuseIdentifier"] }
        guard Set(reuseIdentifiers).count == reuseIdentifiers.count else { throw unsupported("section views of one reuse identifier (ibtool fails)") }
        let controller = placeholders.first { ($0.value as? NibProxy)?.identifier === upstreamIdentifier }
        var views: [CollectionContent.SectionView] = []
        for (view, kind) in elements {
            guard let reuseIdentifier = view.attributes["reuseIdentifier"] else {
                warnings.append((view.attributes["id"] ?? "", "Prototype collection view section header or footer views must have reuse identifiers [9]"))
                continue
            }
            let connections = Self.descendants(of: view, named: "outlet") + Self.descendants(of: view, named: "action")
            let reached = controller.flatMap { controller in connections.contains { $0.attributes["destination"] == controller.key } ? controller : nil }
            let nib = try prototypeNib(view, segues: [], controller: reached?.key)
            var upstream: (key: NibString, placeholder: NibProxy)?
            if let upstreamIdentifier, let placeholder = reached?.value as? NibProxy {
                upstream = (upstreamIdentifier, placeholder)
                prototypesReachController = true
            }
            views.append(CollectionContent.SectionView(key: string("\(kind)/\(reuseIdentifier)"), nib: nib, upstream: upstream))
        }
        return views
    }
}
