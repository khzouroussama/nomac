import Foundation

extension DocumentCompiler {
    /// A `<toolbar>` among subviews without items: a `UIToolbar` writing a view's keys, its content
    /// hugging priorities whatever they are, then `UIItems`, the nib's empty array, `UIBarPosition` 1
    /// and `UIBarTranslucence` 1 (docs/formats/nib.md "Toolbars"; nib-experiments `toolbar-*`,
    /// `sb-toolbar`). Items are refused.
    mutating func toolbar(_ element: XIBElement, view: NibView) throws {
        for items in element.children(named: "items") {
            try check(items, attributes: [], children: [])
        }
        guard element.attributes["horizontalHuggingPriority"] == nil, element.attributes["verticalHuggingPriority"] == nil else {
            throw unsupported("content hugging priorities of a toolbar")
        }
        view.flags.contentHugging = string("{250, 250}")
        view.kind = .toolbar(items: emptyArray)
    }

    /// The empty array of the nib just compiled, the next nib getting its own.
    mutating func takeEmptyArray() -> NibArray {
        defer { emptyArray = NibArray([]) }
        return emptyArray
    }
}
