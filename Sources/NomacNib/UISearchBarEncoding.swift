import Foundation

/// What a `UISearchBar` writes after a view's keys (docs/formats/nib.md "Search bars";
/// nib-experiments `search-bar*`): its translucence, its text (an empty string), its placeholder, its
/// autocorrection, return key and secure entry flags, and the minimal style.
struct SearchBarContent {
    static let attributes = ["searchBarStyle", "placeholder", "text"]

    let text: NibString
    let placeholder: NibString?
    let autocorrection: Int?
    let minimal: Bool

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.integer(1), forKey: "UISearchBarTranslucence")
        try encoder.encode(text, forKey: "UIText")
        if let placeholder { try encoder.encode(placeholder, forKey: "UIPlaceholder") }
        if let autocorrection { encoder.encode(.integer(autocorrection), forKey: "UIAutocorrectionType") }
        encoder.encode(.boolean(false), forKey: "UIEnablesReturnKeyAutomatically")
        encoder.encode(.boolean(false), forKey: "UISecureTextEntry")
        if minimal { encoder.encode(.integer(2), forKey: "UISearchBarStyle") }
    }
}

extension DocumentCompiler {
    /// A `<searchBar>`: never opaque, its content hugging priorities always written (`search-bar`,
    /// `search-bar-opaque-hugging`), an empty text, a placeholder outside `.lproj` folders, its
    /// autocorrection among input traits (`search-bar-traits`), prominent or minimal.
    mutating func searchBar(_ element: XIBElement, view: NibView) throws {
        guard (element.attributes["text"] ?? "").isEmpty else { throw unsupported("a search bar's text") }
        guard element.attributes["placeholder"] == nil || !localizable else { throw unsupported("a search bar's placeholder in a localized document") }
        let traits = element.children(named: "textInputTraits")
        guard traits.count <= 1 else { throw unsupported("a search bar of two <textInputTraits>") }
        for trait in traits {
            try check(trait, attributes: ["key", "autocorrectionType"], children: [])
            try value(trait, "key", in: ["textInputTraits"])
        }
        view.flags.opaque = false
        if view.flags.contentHugging == nil {
            view.flags.contentHugging = string("{250, 250}")
        }
        view.kind = .searchBar(SearchBarContent(
            text: string(""), placeholder: element.attributes["placeholder"].map { string($0) },
            autocorrection: try traits.first?.attributes["autocorrectionType"].map { try mapped($0, ["no": 1, "yes": 2], "autocorrectionType") },
            minimal: try mapped(element.attributes["searchBarStyle"] ?? "prominent", ["prominent": 0, "minimal": 1], "searchBarStyle") == 1))
    }
}
