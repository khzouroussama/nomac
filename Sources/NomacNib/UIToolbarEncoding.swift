import Foundation

extension DocumentCompiler {
    /// A `<toolbar>` among subviews: a `UIToolbar` writing a view's keys, its content hugging
    /// priorities whatever they are, then its style and bar tint, `UIItems` (the nib's empty array
    /// without items), `UIBarPosition` 1 and its translucence (docs/formats/nib.md "Toolbars";
    /// nib-experiments `toolbar-*`, `sb-toolbar`, `bars-tb-*`).
    mutating func toolbar(_ element: XIBElement, view: NibView) throws {
        var items: [NibArchivable] = []
        for container in element.children(named: "items") {
            try check(container, attributes: [], children: ["barButtonItem"])
            for itemElement in container.children {
                items.append(try documentBarButtonItem(itemElement))
            }
        }
        guard element.attributes["horizontalHuggingPriority"] == nil, element.attributes["verticalHuggingPriority"] == nil else {
            throw unsupported("content hugging priorities of a toolbar")
        }
        view.flags.contentHugging = string("{250, 250}")
        view.kind = .toolbar(items: items.isEmpty ? emptyArray : NibArray(items), appearance: try barAppearance(element))
    }

    /// A toolbar's or navigation bar's item among a view's subviews: outlets name it by its id and
    /// its connections are the document's.
    mutating func documentBarButtonItem(_ element: XIBElement) throws -> NibBarButtonItem {
        guard element.children(named: "userDefinedRuntimeAttributes").isEmpty else {
            throw unsupported("<userDefinedRuntimeAttributes> in a bar button item among subviews")
        }
        let item = try barButtonItem(element)
        guard item.customClass == nil || element.children(named: "connections").isEmpty else {
            throw unsupported("connections of a bar button item of a custom class")
        }
        if let id = element.attributes["id"] { navigationBarItems[id] = item }
        try connections(of: element, source: item)
        return item
    }

    /// A `<barButtonItem>` without its connections: a system item, a title or image or none of
    /// them, its style, tag, width, tint and class (`bars-tb-*`, `bars-ni-item-*`). `userLabel`
    /// changes nothing (`bars-tb-label`, `bars-ni-item-label`).
    mutating func barButtonItem(_ element: XIBElement) throws -> NibBarButtonItem {
        try check(element, attributes: ["key", "style", "systemItem", "title", "enabled", "image", "catalog", "id", "tag", "width", "userLabel",
                                        "customClass", "customModule", "customModuleProvider"],
                  children: ["connections", "userDefinedRuntimeAttributes", "color"])
        let system = try element.attributes["systemItem"].map { name in
            guard let system = NibBarButtonItem.systemItems[name] else { throw unsupported("a bar button item of a system item not observed") }
            return system
        }
        guard system == nil || element.attributes["title"] == nil && element.attributes["image"] == nil else {
            throw unsupported("a system bar button item with a title or an image")
        }
        let item = NibBarButtonItem(systemItem: system, enabled: try bool(element, "enabled", default: true))
        item.title = element.attributes["title"].map { text($0, id: element.attributes["id"], property: "title") }
        try value(element, "style", in: ["plain", "done"])
        item.style = element.attributes["style"] == "plain" ? nil : element.attributes["style"] == "done" ? 2 : 1
        item.tag = try element.attributes["tag"].map { try integer($0, "tag") }
        item.image = try element.attributes["image"].map { try image($0, catalog: element.attributes["catalog"]) }
        item.width = try element.attributes["width"].flatMap { system == 5 ? nil : try number($0, "width") }
        for child in element.children(named: "color") {
            try value(child, "key", in: ["tintColor"])
            item.tintColor = try color(child)
        }
        item.customClass = try customClass(element, original: "UIBarButtonItem")
        return item
    }

    /// The empty array of the nib just compiled, the next nib getting its own.
    mutating func takeEmptyArray() -> NibArray {
        defer { emptyArray = NibArray([]) }
        return emptyArray
    }
}
