import Foundation

/// What a `UITextView` writes after a view's keys (docs/formats/nib.md "Text views";
/// nib-experiments `text-view-*`): a scroll view's, its text twice (plain and attributed), its font,
/// color and alignment, what differs from IB's (editing, data detectors, selection, input traits),
/// then UIKit's highlight attributes and number pad popover.
struct TextViewContent {
    /// `UIDataDetectorTypes` bits of the types observed (`text-view-detectors*`, `text-view-all-flags`).
    static let dataDetectorTypes = ["phoneNumber": 1, "link": 2, "address": 4, "calendarEvent": 8, "shipmentTrackingNumber": 16, "flightNumber": 32, "lookupSuggestion": 64]
    /// The `<textInputTraits>` observed, as their `UITextInputTraits` values, in the order ibtool
    /// writes them (`text-view-traits-*`); `autocapitalizationType` is apart, IB's sentences being
    /// UIKit's default.
    static let traits: [(attribute: String, key: String, values: [String: Int])] = [
        ("autocorrectionType", "UIAutocorrectionType", ["no": 1, "yes": 2]),
        ("spellCheckingType", "UISpellCheckingType", ["no": 1, "yes": 2]),
        ("keyboardType", "UIKeyboardType", ["URL": 3]),
        ("keyboardAppearance", "UIKeyboardAppearance", ["alert": 1]),
        ("returnKeyType", "UIReturnKeyType", ["done": 9]),
    ]
    static let smartTraits = [("smartInsertDeleteType", "UITextSmartInsertDeleteType"), ("smartQuotesType", "UITextSmartQuotesType"),
                              ("smartDashesType", "UITextSmartDashesType")]

    var scroll: ScrollContent
    /// Written after the scroll view's keys, for a text view without text (`text-view-editing-attributes`).
    var allowsEditingTextAttributes = false
    /// Written before the font, with a text style's font (`text-view-adjusts*`).
    var adjustsFontForContentSizeCategory = false
    var text: NibArchivable?
    var attributedText: NibTextViewAttributedString?
    var font: NibFont
    var textColor: NibColor?
    var textAlignment: Int
    var editable: Bool
    var dataDetectorTypes: Int
    var selectable: Bool
    var autocapitalizationType: Int?
    var traits: [(key: String, value: Int)]
    var enablesReturnKeyAutomatically: Bool
    var textContentType: NibString?
    var smartTraits: [String]
    var highlightAttributes: NibDictionary

    func encode(to encoder: NibEncoder) throws {
        scroll.encode(to: encoder)
        if allowsEditingTextAttributes { encoder.encode(.boolean(true), forKey: "UIAllowsEditingTextAttributes") }
        if let text { try encoder.encode(text, forKey: "UIText") }
        if let attributedText { try encoder.encode(attributedText, forKey: "UIAttributedText") }
        if adjustsFontForContentSizeCategory { encoder.encode(.boolean(true), forKey: "UIAdjustsFontForContentSizeCategory") }
        try encoder.encode(font, forKey: "UIFont")
        if let textColor { try encoder.encode(textColor, forKey: "UITextColor") }
        encoder.encode(.integer(textAlignment), forKey: "UITextAlignment")
        if !editable { encoder.encode(.boolean(false), forKey: "UIEditable") }
        if dataDetectorTypes != 0 { encoder.encode(.integer(dataDetectorTypes), forKey: "UIDataDetectorTypes") }
        if !selectable { encoder.encode(.boolean(false), forKey: "UISelectable") }
        if let autocapitalizationType { encoder.encode(.integer(autocapitalizationType), forKey: "UIAutocapitalizationType") }
        for trait in traits {
            encoder.encode(.integer(trait.value), forKey: trait.key)
        }
        if enablesReturnKeyAutomatically { encoder.encode(.boolean(true), forKey: "UIEnablesReturnKeyAutomatically") }
        if let textContentType { try encoder.encode(textContentType, forKey: "UITextContentType") }
        for key in smartTraits {
            encoder.encode(.integer(1), forKey: key)
        }
        try encoder.encode(highlightAttributes, forKey: "UITextHighlightAttributes")
        encoder.encode(.boolean(true), forKey: "UITextAllowsNumberPadPopover")
    }

    static let attributes = ScrollContent.attributes + ["text", "textAlignment", "editable", "selectable", "allowsEditingTextAttributes",
                                                        "adjustsFontForContentSizeCategory"]
}

/// A text view's text with its color, font and alignment as attributes (`text-view-text-color`,
/// `text-view-center`, `text-view-no-alignment`).
final class NibTextViewAttributedString: NibArchivable {
    let string: NibString
    let attributes: NibDictionary

    init(string: NibString, attributes: NibDictionary) {
        self.string = string
        self.attributes = attributes
    }

    var className: String { "NSAttributedString" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(string, forKey: "NSString")
        try encoder.encode(attributes, forKey: "NSAttributes")
    }
}

/// `NSMutableParagraphStyle` of an alignment, as `NSTextAlignment`'s AppKit values: none for left,
/// 2 for center, 4 for natural (`text-view-no-alignment`, `text-view-center`, `text-view`); an
/// attributed label's also has its label's line break mode, its line height multiple and the
/// line break strategy 65535 (`al-*`).
final class NibParagraphStyle: NibArchivable {
    static let alignments = [0: 0, 1: 2, 4: 4]

    let alignment: Int
    let lineBreakMode: Int?
    let lineHeightMultiple: Double?

    init(alignment: Int, lineBreakMode: Int? = nil, lineHeightMultiple: Double? = nil) {
        self.alignment = alignment
        self.lineBreakMode = lineBreakMode
        self.lineHeightMultiple = lineHeightMultiple
    }

    var className: String { "NSMutableParagraphStyle" }

    func encode(to encoder: NibEncoder) throws {
        if alignment != 0 { encoder.encode(.integer(alignment), forKey: "NSAlignment") }
        if let lineBreakMode { encoder.encode(.integer(lineBreakMode), forKey: "NSLineBreakMode") }
        if let lineHeightMultiple { encoder.encode(.double(lineHeightMultiple), forKey: "NSLineHeightMultiple") }
        encoder.encode(.null, forKey: "NSTabStops")
        if lineBreakMode != nil { encoder.encode(.integer(65535), forKey: "NSLineBreakStrategy") }
    }
}

extension DocumentCompiler {
    /// A `<textView>`'s content: the system font of 17 points without a description
    /// (`text-view-no-font`), left alignment without one (`text-view-no-alignment`), its input
    /// traits as an empty `<textInputTraits>` without them (`text-view-no-traits`). In a document of
    /// an `.lproj` folder the plain text is localizable and the attributed one is not
    /// (`text-view-lproj`). A text of more than 512 characters is two `NSMutableString`s, the plain
    /// one and the attributed one's, in the element or the attribute; labels' are not
    /// (`text-view-length-*`, `label-length-*`; wikipedia's LibrariesUsed storyboard). In an `.lproj`
    /// folder the plain one is localizable as any (`text-view-length-*-lproj`).
    mutating func textViewContent(_ element: XIBElement) throws -> TextViewContent {
        let attributes = element.attributes
        for child in element.children(named: "color") where !["backgroundColor", "textColor", "tintColor"].contains(child.attributes["key"] ?? "") {
            throw unsupported("<color key=\"\(child.attributes["key"] ?? "")\"> in a text view")
        }
        let texts = element.children(named: "string")
        let nils = element.children(named: "nil")
        guard texts.count + nils.count <= (attributes["text"] == nil ? 1 : 0) else { throw unsupported("a text view with two texts") }
        for empty in nils {
            try value(empty, "key", in: ["text"])
        }
        for text in texts {
            try check(text, attributes: ["key"], children: [])
            try value(text, "key", in: ["text"])
        }
        var fontElement = element
        if element.children(named: "fontDescription").isEmpty {
            fontElement = XIBElement(name: "textView", attributes: [:])
            fontElement.children = [XIBElement(name: "fontDescription", attributes: ["type": "system", "pointSize": "17"])]
        }
        let font = try self.font(fontElement).font
        let textColor = try element.child("color", key: "textColor").map { try color($0) }
        let textAlignment = try attributes["textAlignment"].map { try mapped($0, LabelContent.textAlignments, "textAlignment") } ?? 0
        var text: NibArchivable?, attributedText: NibTextViewAttributedString?
        if let value = attributes["text"] ?? texts.first?.text {
            guard let paragraphAlignment = NibParagraphStyle.alignments[textAlignment] else {
                throw unsupported("a text view's text aligned \(attributes["textAlignment"] ?? "")")
            }
            let counts = [value.utf8.count, value.utf16.count, value.unicodeScalars.count]
            guard counts.allSatisfy({ $0 > 512 }) || counts.allSatisfy({ $0 <= 512 }) else {
                throw unsupported("a text view's text of about 512 characters in another script than ASCII")
            }
            let long = counts[0] > 512
            text = long && !localizable ? NibString.mutable(value) : self.text(value, id: attributes["id"], property: "text")
            // Text views of one font, color and alignment share their attributes and paragraph style
            // (`text-view-two-*`).
            let key = "\(ObjectIdentifier(font))-\(textColor.map { "\(ObjectIdentifier($0))" } ?? "")-\(paragraphAlignment)"
            let attributes = try textViewAttributes[key] ?? {
                let entries: [(String, NibArchivable)] = (textColor.map { [("NSColor", $0 as NibArchivable)] } ?? [])
                    + [("NSFont", font), ("NSParagraphStyle", NibParagraphStyle(alignment: paragraphAlignment))]
                return dictionary(entries)
            }()
            textViewAttributes[key] = attributes
            attributedText = NibTextViewAttributedString(string: long ? NibString.mutable(value) : string(value), attributes: attributes)
        }
        var dataDetectorTypes = 0
        for detectors in element.children(named: "dataDetectorType") {
            try check(detectors, attributes: ["key"] + TextViewContent.dataDetectorTypes.keys, children: [])
            try value(detectors, "key", in: ["dataDetectorTypes"])
            for (name, bit) in TextViewContent.dataDetectorTypes where try bool(detectors, name, default: false) {
                dataDetectorTypes |= bit
            }
        }
        // `mx-detect-*`.
        if dataDetectorTypes != 0, try bool(element, "editable", default: true), let id = element.attributes["id"] {
            warnings.append((id, "Data Detection and Editable (These attributes are mutually exclusive) [9]"))
        }
        let traitElements = element.children(named: "textInputTraits")
        guard traitElements.count <= 1 else { throw unsupported("a text view with two <textInputTraits>") }
        let traitElement = traitElements.first ?? XIBElement(name: "textInputTraits", attributes: [:])
        try check(traitElement, attributes: ["key", "autocapitalizationType", "enablesReturnKeyAutomatically", "textContentType"]
                  + TextViewContent.traits.map(\.attribute) + TextViewContent.smartTraits.map(\.0), children: [])
        let traitAttributes = traitElement.attributes
        try value(traitElement, "textContentType", in: ["url"])
        for (attribute, _) in TextViewContent.smartTraits {
            try value(traitElement, attribute, in: ["no"])
        }
        let autocapitalizationType: Int?
        switch traitAttributes["autocapitalizationType"] {
        case nil: autocapitalizationType = 0
        case "sentences": autocapitalizationType = nil
        case let other?: autocapitalizationType = try mapped(other, ["words": 1], "autocapitalizationType")
        }
        let allowsEditingTextAttributes = try bool(element, "allowsEditingTextAttributes", default: false)
        guard !allowsEditingTextAttributes || text == nil else { throw unsupported("a text view with a text and editable text attributes") }
        var content = TextViewContent(
            scroll: try scrollContent(element), text: text, attributedText: attributedText, font: font, textColor: textColor, textAlignment: textAlignment,
            editable: try bool(element, "editable", default: true), dataDetectorTypes: dataDetectorTypes, selectable: try bool(element, "selectable", default: true),
            autocapitalizationType: autocapitalizationType,
            traits: try TextViewContent.traits.compactMap { trait in
                try traitAttributes[trait.attribute].map { (trait.key, try mapped($0, trait.values, trait.attribute)) }
            },
            enablesReturnKeyAutomatically: try bool(traitElement, "enablesReturnKeyAutomatically", default: false),
            textContentType: traitAttributes["textContentType"].map { string($0) },
            smartTraits: TextViewContent.smartTraits.filter { traitAttributes[$0.0] != nil }.map(\.1),
            highlightAttributes: dictionary([("NSColor", try tint(of: element) ?? systemColor("systemBlueColor", NibColor.systemColors["systemBlueColor"]!)),
                                             ("NSTextHighlightOutlineColor", systemColor("secondarySystemFillColor", NibColor.systemColors["secondarySystemFillColor"]!))]))
        content.allowsEditingTextAttributes = allowsEditingTextAttributes
        content.adjustsFontForContentSizeCategory = try bool(element, "adjustsFontForContentSizeCategory", default: false)
        warnIfFontDoesNotAdjust(element, adjusts: content.adjustsFontForContentSizeCategory)
        return content
    }
}
