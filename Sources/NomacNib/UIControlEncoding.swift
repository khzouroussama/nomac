import Foundation

/// What a `UITextField` writes after a view's keys (docs/formats/nib.md "Controls",
/// nib-experiments `tf-*`): its alignments, font, placeholder and text, its color (the system label
/// color without one), its border, font size adjustment, clear button, IB's clear button offset
/// and its input traits.
struct TextFieldContent {
    /// `UITextField.BorderStyle` of the styles observed.
    static let borderStyles = ["none": 0, "line": 1, "roundedRect": 3]
    /// `UITextField.ViewMode` of the clear button, by the names documents use (`tf-clear-*`).
    static let clearButtonModes = ["never": 0, "whileEditing": 1, "unlessEditing": 2, "always": 3]
    /// The `<textInputTraits>`, as their `UITextInputTraits` values, in the order ibtool writes them,
    /// the content type after secure entry; a value of nil writes nothing, as the default does
    /// (`tf-trait-*`, every value of the survey's documents and UIKit's; `tf-traits-order*`).
    static let traits: [(attribute: String, key: String, values: [String: NibValue?])] = [
        ("autocapitalizationType", "UIAutocapitalizationType", ["none": nil, "words": .integer(1), "sentences": .integer(2), "allCharacters": .integer(3)]),
        ("autocorrectionType", "UIAutocorrectionType", ["default": nil, "no": .integer(1), "yes": .integer(2)]),
        ("spellCheckingType", "UISpellCheckingType", ["default": nil, "no": .integer(1), "yes": .integer(2)]),
        ("keyboardAppearance", "UIKeyboardAppearance", ["default": nil, "alert": .integer(1), "dark": .integer(1), "light": .integer(2)]),
        ("keyboardType", "UIKeyboardType", ["default": nil, "alphabet": .integer(1), "numbersAndPunctuation": .integer(2), "URL": .integer(3), "numberPad": .integer(4),
                                            "phonePad": .integer(5), "namePhonePad": .integer(6), "emailAddress": .integer(7), "decimalPad": .integer(8),
                                            "twitter": .integer(9), "webSearch": .integer(10), "asciiCapableNumberPad": nil]),
        ("returnKeyType", "UIReturnKeyType", ["default": nil, "go": .integer(1), "google": .integer(2), "join": .integer(3), "next": .integer(4), "route": .integer(5),
                                              "search": .integer(6), "send": .integer(7), "yahoo": .integer(8), "done": .integer(9), "emergencyCall": .integer(10),
                                              "continue": .integer(11)]),
        ("enablesReturnKeyAutomatically", "UIEnablesReturnKeyAutomatically", ["NO": nil, "YES": .boolean(true)]),
        ("secureTextEntry", "UISecureTextEntry", ["NO": nil, "YES": .boolean(true)]),
    ]
    static let smartTraits = [("smartInsertDeleteType", "UITextSmartInsertDeleteType"), ("smartQuotesType", "UITextSmartQuotesType"),
                              ("smartDashesType", "UITextSmartDashesType")]
    static let smartTraitValues: [String: Int?] = ["default": nil, "no": 1, "yes": 2]
    /// The content types observed, written as the document spells them (`tf-trait-textContentType-*`).
    static let contentTypes: Set = ["password", "username", "email", "name", "one-time-code", "url", "tel", "new-password", "address-level2", "address-line1",
                                    "address-line2", "address-level1", "postal-code", "cc-number", "location", "nickname", "given-name", "family-name",
                                    "honorific-prefix", "additional-name", "honorific-suffix", "organization-title", "organization", "street-address",
                                    "sublocality", "country-name", "tel-national", "tracking-number", "flight-number"]
    var enabled = true
    var contentVerticalAlignment = 0
    var contentHorizontalAlignment: Int
    var adjustsFontForContentSizeCategory: Bool
    var font: NibFont
    var placeholder: NibArchivable?
    var textAlignment: Int
    var text: NibArchivable?
    var textColor: NibColor
    var borderStyle: Int
    var minimumFontSize: Float
    var clearButtonMode = 0
    var clearsOnBeginEditing = false
    var adjustsFontSizeToFit = true
    var traits: [(key: String, value: NibValue)]
    var textContentType: NibString?
    var smartTraits: [(key: String, value: Int)] = []
    /// Secure entry also writes the inline prediction type 1 (`tf-secure`).
    var secure = false
    /// `background` and `disabledBackground` images; a background also writes the rounded rectangle's
    /// corner radius (`cm-tf-*`).
    var background: NibImage?
    var disabledBackground: NibImage?

    func encode(to encoder: NibEncoder) throws {
        if !enabled { encoder.encode(.boolean(true), forKey: "UIDisabled") }
        if contentVerticalAlignment != 0 {
            encoder.encode(.integer(contentVerticalAlignment), forKey: "UIContentVerticalAlignment")
            encoder.encode(.integer(contentVerticalAlignment), forKey: "UIContentVerticalAlignment2")
        }
        if contentHorizontalAlignment != 0 { encoder.encode(.integer(contentHorizontalAlignment), forKey: "UIContentHorizontalAlignment") }
        if adjustsFontForContentSizeCategory { encoder.encode(.boolean(true), forKey: "UIAdjustsFontForContentSizeCategory") }
        try encoder.encode(font, forKey: "UIFont")
        if let placeholder { try encoder.encode(placeholder, forKey: "UIPlaceholder") }
        encoder.encode(.integer(textAlignment), forKey: "UITextAlignment")
        if let text { try encoder.encode(text, forKey: "UIText") }
        try encoder.encode(textColor, forKey: "UITextColor")
        if let background { try encoder.encode(background, forKey: "UITextFieldBackground") }
        if let disabledBackground { try encoder.encode(disabledBackground, forKey: "UITextFieldDisabledBackground") }
        if borderStyle != 0 { encoder.encode(.integer(borderStyle), forKey: "UIBorderStyle") }
        if clearsOnBeginEditing { encoder.encode(.boolean(true), forKey: "UIClearsOnBeginEditing") }
        if adjustsFontSizeToFit { encoder.encode(.boolean(true), forKey: "UIAdjustsFontSizeToFit") }
        encoder.encode(.float(minimumFontSize), forKey: "UIMinimumFontSize")
        if clearButtonMode != 0 { encoder.encode(.integer(clearButtonMode), forKey: "UIClearButtonMode") }
        encoder.encode(.data(NibView.doubles([3, 1])), forKey: "UIClearButtonOffset")
        for trait in traits {
            encoder.encode(trait.value, forKey: trait.key)
        }
        if let textContentType { try encoder.encode(textContentType, forKey: "UITextContentType") }
        for trait in smartTraits {
            encoder.encode(.integer(trait.value), forKey: trait.key)
        }
        if secure { encoder.encode(.integer(1), forKey: "UITextInlinePredictionType") }
        encoder.encode(.boolean(true), forKey: "UIDisableTextColorUpdateOnTraitCollectionChange")
        if borderStyle == 3 || background != nil { encoder.encode(.double(0), forKey: "UIRoundedRectBackgroundCornerRadius") }
    }
}

/// `NSValue` of a rectangle, as its string.
final class NibRectValue: NibArchivable {
    let string: NibString

    init(_ string: NibString) {
        self.string = string
    }

    var className: String { "NSValue" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.integer(3), forKey: "NS.special")
        try encoder.encode(string, forKey: "NS.rectval")
    }
}

extension DocumentCompiler {
    static let textFieldAttributes = ["contentHorizontalAlignment", "contentVerticalAlignment", "text", "placeholder", "textAlignment", "background", "disabledBackground",
                                      "minimumFontSize", "borderStyle", "adjustsFontForContentSizeCategory", "clearButtonMode",
                                      "clearsOnBeginEditing", "adjustsFontSizeToFit", "enabled"]
    static let switchAttributes = ["contentHorizontalAlignment", "contentVerticalAlignment", "on"]
    /// `UIControl.Event` of the events observed, the `UIEventMask` of an action's connection
    /// (`act-field-all-events`, `act-control-*`).
    /// `UIControl.Event` bits by IB's event names (`ev-*`, `act-*`; round 105: `act-control-*`);
    /// `menuActionTriggered` writes no mask, as an action without an event (`act-control-menuActionTriggered`).
    static let eventMasks = ["touchDown": 1, "touchDownRepeat": 2, "touchDragInside": 4, "touchDragOutside": 8, "touchDragEnter": 16,
                             "touchDragExit": 32, "touchUpInside": 64, "touchUpOutside": 128, "touchCancel": 256, "valueChanged": 4096,
                             "primaryActionTriggered": 8192, "editingDidBegin": 65536, "editingChanged": 131072, "editingDidEnd": 262144,
                             "editingDidEndOnExit": 524288]

    /// A text, as an `NSLocalizableString` keyed `<id>.<property>` in a document of an `.lproj`
    /// folder (`label-lproj`, the corpus's tofu storyboard).
    mutating func text(_ value: String, id: String?, property: String) -> NibArchivable {
        localizableText(value, key: "\(id ?? "").\(property)")
    }

    /// A text field's or switch's horizontal alignment; their vertical one centered (`tf-*`, `sw-*`).
    func contentHorizontalAlignment(_ element: XIBElement) throws -> Int {
        try value(element, "contentVerticalAlignment", in: ["center"])
        return try mapped(element.attributes["contentHorizontalAlignment"] ?? "center", ControlContent.horizontalAlignments, "contentHorizontalAlignment")
    }

    /// A `<textField>`'s content: the system font sizes it as a label's, `minimumFontSize` is
    /// required, the text color is its `<color key="textColor">` or the system label color, a
    /// `<string key="placeholder">` is a placeholder (`tf-*`).
    mutating func textField(_ element: XIBElement) throws -> TextFieldContent {
        let attributes = element.attributes
        guard let minimum = attributes["minimumFontSize"],
              let textAlignment = attributes["textAlignment"].map({ ["natural": 4, "center": 1, "right": 2][$0] }) ?? 0 else {
            throw unsupported("a text field without minimumFontSize, or of a text alignment other than natural, center, right or none")
        }
        let traitElements = element.children(named: "textInputTraits")
        guard traitElements.count == 1, let traitElement = traitElements.first else { throw unsupported("a text field without one <textInputTraits>") }
        try check(traitElement, attributes: ["key", "textContentType"] + TextFieldContent.traits.map(\.attribute) + TextFieldContent.smartTraits.map(\.0), children: [])
        var traits: [(key: String, value: NibValue)] = []
        for trait in TextFieldContent.traits {
            guard let name = traitElement.attributes[trait.attribute] else { continue }
            guard let value = trait.values[name] else { throw unsupported("\(trait.attribute)=\"\(name)\"") }
            if let value { traits.append((trait.key, value)) }
        }
        let secure = traitElement.attributes["secureTextEntry"] == "YES"
        if secure, !traits.contains(where: { $0.key == "UIAutocorrectionType" }) {
            traits.insert(("UIAutocorrectionType", .integer(1)), at: traits.firstIndex { $0.key != "UIAutocapitalizationType" } ?? traits.count)
        }
        try value(traitElement, "textContentType", in: TextFieldContent.contentTypes)
        var smartTraits: [(key: String, value: Int)] = []
        for (attribute, key) in TextFieldContent.smartTraits {
            guard let name = traitElement.attributes[attribute] else { continue }
            guard let value = TextFieldContent.smartTraitValues[name] else { throw unsupported("\(attribute)=\"\(name)\"") }
            if let value { smartTraits.append((key, value)) }
        }
        let placeholders = element.children(named: "string")
        for string in placeholders {
            try check(string, attributes: ["key"], children: [])
            try value(string, "key", in: ["placeholder"])
        }
        guard placeholders.count + (attributes["placeholder"] == nil ? 0 : 1) <= 1 else { throw unsupported("a text field with two placeholders") }
        for empty in element.children(named: "nil") {
            try value(empty, "key", in: ["textColor"])
        }
        let textColor = try element.child("color", key: "textColor").map { try color($0) }
        warnIfFontDoesNotAdjust(element, adjusts: try bool(element, "adjustsFontForContentSizeCategory", default: false))
        var content = TextFieldContent(contentHorizontalAlignment: try mapped(attributes["contentHorizontalAlignment"] ?? "center", ControlContent.horizontalAlignments,
                                                                              "contentHorizontalAlignment"),
                                adjustsFontForContentSizeCategory: try bool(element, "adjustsFontForContentSizeCategory", default: false), font: try font(element).font,
                                placeholder: (attributes["placeholder"] ?? placeholders.first?.text).map { text($0, id: attributes["id"], property: "placeholder") },
                                textAlignment: textAlignment,
                                text: attributes["text"].map { text($0, id: attributes["id"], property: "text") },
                                textColor: try textColor ?? color(XIBElement(name: "color", attributes: ["systemColor": "labelColor"])),
                                borderStyle: try mapped(attributes["borderStyle"] ?? "none", TextFieldContent.borderStyles, "borderStyle"),
                                minimumFontSize: Float(try number(minimum, "minimumFontSize")), traits: traits)
        content.background = try attributes["background"].map { try image($0, catalog: nil) }
        content.disabledBackground = try attributes["disabledBackground"].map { try image($0, catalog: nil) }
        content.clearButtonMode = try mapped(attributes["clearButtonMode"] ?? "never", TextFieldContent.clearButtonModes, "clearButtonMode")
        content.clearsOnBeginEditing = try bool(element, "clearsOnBeginEditing", default: false)
        content.adjustsFontSizeToFit = try bool(element, "adjustsFontSizeToFit", default: true)
        content.contentVerticalAlignment = try mapped(attributes["contentVerticalAlignment"] ?? "center", ControlContent.verticalAlignments, "contentVerticalAlignment")
        content.textContentType = traitElement.attributes["textContentType"].map { string($0) }
        content.smartTraits = smartTraits
        content.enabled = try bool(element, "enabled", default: true)
        content.secure = secure
        return content
    }

    /// A switch's document frame, set again as `frame` once it is loaded: a key-value pair in all
    /// objects' order, its strings the nib's (`sw-*`, the corpus's tofu storyboard).
    mutating func switchFramePair(_ view: NibView) throws {
        guard let frame = view.frame else { return }
        let numbers = try [frame.x, frame.y, frame.width, frame.height].map { number in
            guard (number * 2).rounded() == number * 2 else { throw unsupported("a switch's frame of other than half points") }
            return number == number.rounded() ? String(Int(number)) : String(number)
        }
        keyValuePairs.append(NibKeyValuePair(object: view, value: NibRectValue(string("{{\(numbers[0]), \(numbers[1])}, {\(numbers[2]), \(numbers[3])}}")),
                                             keyPath: string("frame")))
    }
}
