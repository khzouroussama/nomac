import Foundation

extension DocumentCompiler {
    /// A `<navigationBar>` among subviews, not a navigation controller's (docs/formats/nib.md
    /// "Navigation bars among subviews"; nib-experiments `nav-bar-sub-*`, `sb-nav-bar-sub`): a
    /// `UINavigationBar` writing a view's keys, with its content hugging priorities, zero directional
    /// layout margins and, unless `translucent="NO"`, no opacity; then its navigation items, the bar
    /// position 2 and its translucence (1, 2 for `translucent="NO"`). Each item has a title, done,
    /// cancel or add bar button items without actions, the nib's empty array as center item groups and
    /// the bar; other items are refused.
    mutating func navigationBar(_ element: XIBElement, view: NibView) throws {
        guard element.attributes["horizontalHuggingPriority"] == nil, element.attributes["verticalHuggingPriority"] == nil,
              element.child("edgeInsets", key: "layoutMargins") == nil, element.child("directionalEdgeInsets", key: "directionalLayoutMargins") == nil else {
            throw unsupported("content hugging priorities or layout margins of a navigation bar")
        }
        let translucent = try bool(element, "translucent", default: true)
        view.flags.contentHugging = string("{250, 250}")
        view.flags.opaque = !translucent
        view.layoutMargins = [0, 0, 0, 0]
        view.flags.layoutMarginsAreDirectional = true
        var items: [NibArchivable] = []
        for container in element.children(named: "items") {
            try check(container, attributes: [], children: ["navigationItem"])
            for itemElement in container.children {
                try check(itemElement, attributes: ["title", "id"], children: ["barButtonItem"])
                let item = NibNavigationItem()
                item.title = itemElement.attributes["title"].map { text($0, id: itemElement.attributes["id"], property: "title") }
                item.centerItemGroups = emptyArray
                item.bar = view
                if let id = itemElement.attributes["id"] { navigationBarItems[id] = item }
                for barItem in itemElement.children {
                    try check(barItem, attributes: ["key", "style", "systemItem", "id"], children: [])
                    try value(barItem, "style", in: ["plain", "done"])
                    guard let system = barItem.attributes["systemItem"].flatMap({ NibBarButtonItem.systemItems[$0] }) else {
                        throw unsupported("a navigation bar's bar button item of a system item not observed yet, or other than a system item")
                    }
                    let button = NibBarButtonItem(systemItem: system, enabled: true)
                    button.style = barItem.attributes["style"] == "done" ? 2 : 1
                    if let id = barItem.attributes["id"] { navigationBarItems[id] = button }
                    switch barItem.attributes["key"] {
                    case "leftBarButtonItem" where item.left == nil: item.left = button
                    case "rightBarButtonItem" where item.right == nil: item.right = button
                    default: throw unsupported("a navigation bar's bar button item other than one left and one right")
                    }
                }
                items.append(item)
            }
        }
        view.kind = .navigationBar(items: NibArray(items, mutable: true), translucent: translucent)
    }
}
