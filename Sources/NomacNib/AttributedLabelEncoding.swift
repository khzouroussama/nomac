import Foundation

/// `NSMutableAttributedString` of an attributed label: a mutable copy of its text and, unless empty,
/// its fragment's attributes (docs/formats/nib.md "Attributed labels"; nib-experiments `al-*`).
final class NibMutableAttributedString: NibArchivable {
    let string: NibMutableString
    let attributes: NibDictionary?

    init(string: NibMutableString, attributes: NibDictionary?) {
        self.string = string
        self.attributes = attributes
    }

    var className: String { "NSMutableAttributedString" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(string, forKey: "NSString")
        if let attributes { try encoder.encode(attributes, forKey: "NSAttributes") }
    }
}

/// `NSMutableString`, one object per attributed text, not shared with the nib's strings (`al-system-15`).
final class NibMutableString: NibArchivable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var className: String { "NSMutableString" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.data(Array(value.utf8)), forKey: "NS.bytes")
    }
}

/// What an attributed label shows: its text, font, color and alignment, which it writes as a plain
/// label's, and the attributed text after its alignment.
struct AttributedLabelText {
    let text: String
    let font: (font: NibFont, pointSize: Double?)
    let color: NibColor?
    let alignment: Int
    let attributedText: NibMutableAttributedString
}

extension DocumentCompiler {
    /// A label's `<attributedString key="attributedText">` of at most one fragment: its `NSColor`,
    /// `NSFont` (`metaFont="system"` or a named font) and `NSParagraphStyle`, in document order,
    /// `NSOriginalFont` dropped (`al-gomap`). The paragraph style's alignment is the label's (natural
    /// without one), its line break mode the label's (`al-gomap-label`). The catalog color
    /// `textColor` is opaque black, unnamed (`al-system-15-text-color`). An empty string has the
    /// system font of 17 points with no descriptor options (`al-empty`). Texts are not localized
    /// (`al-system-15-lproj`); several fragments are refused.
    mutating func attributedLabelText(_ element: XIBElement, lineBreakMode: Int) throws -> AttributedLabelText {
        let strings = element.children(named: "attributedString").filter { $0.attributes["key"] == "attributedText" }
        guard strings.count == 1, let string = strings.first else {
            throw unsupported("an attributed label without one attributed text")
        }
        try check(string, attributes: ["key"], children: ["fragment"])
        guard string.children.count <= 1 else { throw unsupported("an attributed label of several fragments") }
        guard let fragment = string.children.first else {
            let entries: [(String, NibArchivable)] = [("NSCTFontUIUsageAttribute", self.string("CTFontRegularUsage")), ("NSFontSizeAttribute", NibNumber(17))]
            let font = NibFont(name: self.string(".SFUI-Regular"), kind: .descriptor(NibFontDescriptor(attributes: dictionary(entries), options: 0)),
                               pointSize: 17, traits: 0, systemFont: true, size: 17)
            return AttributedLabelText(text: "", font: (font, 17), color: nil, alignment: 4,
                                       attributedText: NibMutableAttributedString(string: NibMutableString(""), attributes: nil))
        }
        try check(fragment, attributes: ["content"], children: ["attributes"])
        guard let content = fragment.attributes["content"], fragment.children.count == 1, let attributes = fragment.children.first else {
            throw unsupported("an attributed label's fragment without a content and its attributes")
        }
        try check(attributes, attributes: [], children: ["color", "font", "paragraphStyle"])
        var font: (font: NibFont, pointSize: Double?)?
        var color: NibColor?
        var alignment = 4
        var entries: [(String, NibArchivable)] = []
        for attribute in attributes.children {
            switch (attribute.name, attribute.attributes["key"]) {
            case ("color", "NSColor"):
                color = try fragmentColor(attribute)
                entries.append(("NSColor", color!))
            case ("font", "NSFont"):
                font = try fragmentFont(attribute)
                entries.append(("NSFont", font!.font))
            case ("font", "NSOriginalFont"):
                try fragmentFont(attribute)
            case ("paragraphStyle", "NSParagraphStyle"):
                try check(attribute, attributes: ["key", "alignment", "lineBreakMode", "baseWritingDirection", "lineHeightMultiple", "tighteningFactorForTruncation"],
                          children: [])
                try value(attribute, "lineBreakMode", in: ["wordWrapping", "truncatingTail"])
                try value(attribute, "baseWritingDirection", in: ["natural"])
                try value(attribute, "tighteningFactorForTruncation", in: ["0.0"])
                let name = attribute.attributes["alignment"] ?? "natural"
                alignment = try mapped(name, LabelContent.textAlignments, "alignment")
                guard let appKit = NibParagraphStyle.alignments[alignment] else { throw unsupported("an attributed label aligned \(name)") }
                entries.append(("NSParagraphStyle", NibParagraphStyle(alignment: appKit, lineBreakMode: lineBreakMode,
                                                                      lineHeightMultiple: try attribute.attributes["lineHeightMultiple"].map { try number($0, "lineHeightMultiple") })))
            default:
                throw unsupported("<\(attribute.name) key=\"\(attribute.attributes["key"] ?? "")\"> in an attributed label")
            }
        }
        guard let font else { throw unsupported("an attributed label's fragment without a font") }
        return AttributedLabelText(text: content, font: font, color: color, alignment: alignment,
                                   attributedText: NibMutableAttributedString(string: NibMutableString(content), attributes: dictionary(entries)))
    }

    /// A fragment's `<font>` as the `<fontDescription>` it stands for.
    @discardableResult
    private mutating func fragmentFont(_ element: XIBElement) throws -> (font: NibFont, pointSize: Double?) {
        try check(element, attributes: ["key", "metaFont", "size", "name"], children: [])
        guard let size = element.attributes["size"] else { throw unsupported("an attributed label's font without a size") }
        let description: [String: String]
        switch (element.attributes["metaFont"], element.attributes["name"]) {
        case ("system", nil): description = ["key": "fontDescription", "type": "system", "pointSize": size]
        case (nil, let name?): description = ["key": "fontDescription", "name": name, "family": name, "pointSize": size]
        default: throw unsupported("this font of an attributed label")
        }
        let described = XIBElement(name: "label", attributes: [:])
        described.children = [XIBElement(name: "fontDescription", attributes: description)]
        return try font(described)
    }

    /// A fragment's `<color>`: as a view's, or the catalog color `textColor`.
    private mutating func fragmentColor(_ element: XIBElement) throws -> NibColor {
        guard element.attributes["colorSpace"] == "catalog" else { return try color(element) }
        try check(element, attributes: ["key", "name", "catalog", "colorSpace"], children: [])
        guard element.attributes["name"] == "textColor", element.attributes["catalog"] == "System" else {
            throw unsupported("the catalog color \(element.attributes["name"] ?? "")")
        }
        return unnamedColor(.rgb(red: 0, green: 0, blue: 0, alpha: 1))
    }
}
