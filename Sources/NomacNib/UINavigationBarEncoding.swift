import Foundation

extension DocumentCompiler {
    /// A `<navigationBar>` among subviews, not a navigation controller's (docs/formats/nib.md
    /// "Navigation bars among subviews"; nib-experiments `nav-bar-sub-*`, `sb-nav-bar-sub`,
    /// `bars-nb-*`): a `UINavigationBar` writing a view's keys, with its content hugging priorities,
    /// zero directional layout margins and, unless `translucent="NO"`, no opacity; then its
    /// appearance, its navigation items and the bar position 2. Each item has a title, one left and
    /// one right bar button item, the nib's empty array as center item groups and the bar; other
    /// items are refused.
    mutating func navigationBar(_ element: XIBElement, view: NibView) throws {
        guard element.attributes["horizontalHuggingPriority"] == nil, element.attributes["verticalHuggingPriority"] == nil,
              element.child("edgeInsets", key: "layoutMargins") == nil, element.child("directionalEdgeInsets", key: "directionalLayoutMargins") == nil else {
            throw unsupported("content hugging priorities or layout margins of a navigation bar")
        }
        let appearance = try barAppearance(element)
        view.flags.contentHugging = string("{250, 250}")
        view.flags.opaque = !appearance.translucent
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
                    let button = try documentBarButtonItem(barItem)
                    // `bars-nb-plain-sys`.
                    if barItem.attributes["style"] == "plain", let id = barItem.attributes["id"] {
                        warnings.append((id, "Plain Style unsupported in a Navigation Item [9]"))
                    }
                    switch barItem.attributes["key"] {
                    case "leftBarButtonItem" where item.leftItems.isEmpty: item.leftItems = [button]
                    case "rightBarButtonItem" where item.rightItems.isEmpty: item.rightItems = [button]
                    default: throw unsupported("a navigation bar's bar button item other than one left and one right")
                    }
                }
                items.append(item)
            }
        }
        view.kind = .navigationBar(items: NibArray(items, mutable: true), appearance: appearance)
    }

    /// A bar's `barStyle`, `translucent`, large titles, `<color key="barTintColor">` and
    /// `<textAttributes>` (`bars-tb-style-*`, `bars-tb-translucent-*`, `bars-nb-*`, `bars-sbn-*`).
    mutating func barAppearance(_ element: XIBElement) throws -> BarAppearance {
        var appearance = BarAppearance()
        appearance.style = try element.attributes["barStyle"].map { try mapped($0, ["black": 1, "blackOpaque": 1, "blackTranslucent": 2], "barStyle") }
        appearance.translucent = try bool(element, "translucent", default: true)
        appearance.prefersLargeTitles = try bool(element, "largeTitles", default: false)
        appearance.tint = try element.child("color", key: "barTintColor").map { try color($0) }
        appearance.largeTitleAttributes = try textAttributes(element, key: "largeTitleTextAttributes")
        appearance.titleAttributes = try textAttributes(element, key: "titleTextAttributes")
        return appearance
    }

    /// A bar's `<textAttributes>`: a dictionary of `NSColor` and `NSFont` in that order
    /// (`bars-sbn-text-*`).
    private mutating func textAttributes(_ element: XIBElement, key: String) throws -> NibDictionary? {
        guard let attributes = element.child("textAttributes", key: key) else { return nil }
        try check(attributes, attributes: ["key"], children: ["color", "fontDescription"])
        guard !attributes.children.isEmpty else { throw unsupported("<textAttributes> without attributes") }
        let dictionary = NibDictionary()
        for child in attributes.children(named: "color") {
            try value(child, "key", in: ["textColor"])
            dictionary.entries.append((key: string("NSColor"), value: try color(child)))
        }
        if !attributes.children(named: "fontDescription").isEmpty {
            dictionary.entries.append((key: string("NSFont"), value: try font(attributes).font))
        }
        return dictionary
    }
}

/// What a navigation bar or toolbar says of itself beside its items: `UIBarStyle` (black and
/// blackOpaque 1, blackTranslucent 2), large titles and their attributes before `UIIsLocked`, the
/// bar tint before `UIItems`, title attributes, the position and translucence (1, 2 for
/// `translucent="NO"`) after them (`bars-sbn-combo`, `bars-tb-bar-combo`).
struct BarAppearance {
    var style: Int?
    var prefersLargeTitles = false
    var tint: NibArchivable?
    var largeTitleAttributes: NibDictionary?
    var titleAttributes: NibDictionary?
    var translucent = true

    func encodeLeading(to encoder: NibEncoder) throws {
        if let style { encoder.encode(.integer(style), forKey: "UIBarStyle") }
        if prefersLargeTitles { encoder.encode(.boolean(true), forKey: "UIBarPrefersLargeTitles") }
        if let largeTitleAttributes { try encoder.encode(largeTitleAttributes, forKey: "UIBarLargeTitleTextAttributes") }
    }

    func encodeTrailing(position: Int, to encoder: NibEncoder) throws {
        if let titleAttributes { try encoder.encode(titleAttributes, forKey: "UITitleTextAttributes") }
        encoder.encode(.integer(position), forKey: "UIBarPosition")
        encoder.encode(.integer(translucent ? 1 : 2), forKey: "UIBarTranslucence")
    }
}
