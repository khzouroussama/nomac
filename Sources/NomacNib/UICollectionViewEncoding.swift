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

    func encode(to encoder: NibEncoder) throws {
        scroll.encode(to: encoder)
        try encoder.encode(layout, forKey: "UICollectionLayout")
        encoder.encode(.boolean(true), forKey: "UIAllowsUserInitiatedMultipleSelection")
        if !prototypes.isEmpty {
            let externals = NibDictionary(), nibs = NibDictionary()
            externals.mutable = true
            nibs.mutable = true
            for prototype in prototypes {
                let objects = NibDictionary()
                objects.mutable = true
                externals.entries.append((prototype.reuseIdentifier, objects))
                nibs.entries.append((prototype.reuseIdentifier, NibNestedNib(prototype.nib)))
            }
            try encoder.encode(externals, forKey: "UICollectionViewCellPrototypeNibExternalObjects")
            try encoder.encode(nibs, forKey: "UICollectionViewCellNibDict")
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
        guard prototypes.isEmpty || scroll.nilDelegate else { throw unsupported("cells of a collection view without prototypes") }
        return CollectionContent(scroll: scroll, layout: layout, prefetchingEnabled: try bool(element, "prefetchingEnabled", default: true),
                                 prototypes: prototypes.sorted { Array($0.reuseIdentifier.value.utf8).lexicographicallyPrecedes(Array($1.reuseIdentifier.value.utf8)) })
    }
}
