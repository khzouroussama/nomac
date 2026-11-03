import Foundation

/// What a `UILabel` writes after a view's keys (docs/formats/nib.md "UILabel"; nib-experiments
/// `label-*`).
struct LabelContent {
    var text: NibArchivable?
    var adjustsFontForContentSizeCategory = false
    var font: NibFont
    var textColor: NibColor
    var highlightedColor: NibColor?
    /// Its shadow's color, and its offset, left out at 0, 0 (`label-shadow-*`).
    var shadowColor: NibColor?
    var shadowOffset = [0.0, -1.0]
    var numberOfLines: Int?
    var baselineAdjustment: Int?
    var adjustsFontSizeToFit = false
    var minimumFontSize: Float?
    var lineBreakMode: Int?
    var textAlignment: Int
    /// An attributed label's text, after its alignment (`al-gomap-label`).
    var attributedText: NibMutableAttributedString?
    var enabled = true
    var minimumScaleFactor: Float?
    var adjustsLetterSpacingToFit = false
    var preferredMaxLayoutWidth: Float?
    /// True when the document gives the text color.
    var disablesTextColorUpdate: Bool

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(text, forKey: "UIText")
        if adjustsFontForContentSizeCategory { encoder.encode(.boolean(true), forKey: "UIAdjustsFontForContentSizeCategory") }
        try encoder.encode(font, forKey: "UIFont")
        try encoder.encode(textColor, forKey: "UITextColor")
        if let highlightedColor { try encoder.encode(highlightedColor, forKey: "UIHighlightedColor") }
        if let shadowColor { try encoder.encode(shadowColor, forKey: "UIShadowColor") }
        if shadowOffset != [0, 0] { encoder.encode(.data(NibView.doubles(shadowOffset)), forKey: "UIShadowOffset") }
        if let numberOfLines { encoder.encode(.integer(numberOfLines), forKey: "UINumberOfLines") }
        if let baselineAdjustment { encoder.encode(.integer(baselineAdjustment), forKey: "UIBaselineAdjustment") }
        if adjustsFontSizeToFit { encoder.encode(.boolean(true), forKey: "UIAdjustsFontSizeToFit") }
        if let minimumFontSize { encoder.encode(.float(minimumFontSize), forKey: "UIMinimumFontSize") }
        if let lineBreakMode { encoder.encode(.integer(lineBreakMode), forKey: "UILineBreakMode") }
        encoder.encode(.integer(textAlignment), forKey: "UITextAlignment")
        if let attributedText { try encoder.encode(attributedText, forKey: "UIAttributedText") }
        if !enabled { encoder.encode(.boolean(false), forKey: "UIEnabled") }
        if let minimumScaleFactor { encoder.encode(.float(minimumScaleFactor), forKey: "UIMinimumScaleFactor") }
        if adjustsLetterSpacingToFit { encoder.encode(.boolean(true), forKey: "UIAdjustsLetterSpacingToFit") }
        if let preferredMaxLayoutWidth { encoder.encode(.float(preferredMaxLayoutWidth), forKey: "UIPreferredMaxLayoutWidth") }
        encoder.encode(.boolean(disablesTextColorUpdate), forKey: "UIDisableUpdateTextColorOnTraitCollectionChange")
    }

    /// `NSTextAlignment` and `NSLineBreakMode`, by the names documents use; `UIBaselineAdjustment`
    /// for those not written (alignBaselines) and absent (alignCenters).
    static let textAlignments = ["left": 0, "center": 1, "right": 2, "justified": 3, "natural": 4]
    static let lineBreakModes = ["wordWrap": 0, "characterWrap": 1, "clip": 2, "headTruncation": 3, "tailTruncation": 4, "middleTruncation": 5]
    static let baselineAdjustments = ["alignBaselines": 0, "alignCenters": 1, "none": 2]
}

/// `UIFont`: a system font of a weight, a text style or a named font, as UIKit encodes the font IB
/// describes (nib-experiments `label-font-*`, `label-size-*`, `label-weight-*`, `label-style-*`).
final class NibFont: NibArchivable {
    enum Kind {
        case descriptor(NibFontDescriptor)
        case textStyle(NibString)
    }

    let name: NibString?
    let kind: Kind
    let pointSize: Double
    let traits: Int
    let systemFont: Bool
    let size: Double
    /// Whether the font writes its scaling keys; named fonts of descriptor options 0 do not
    /// (`label-font-092`, `label-font-100`).
    let scales: Bool

    init(name: NibString?, kind: Kind, pointSize: Double, traits: Int, systemFont: Bool, size: Double, scales: Bool = true) {
        self.name = name
        self.kind = kind
        self.pointSize = pointSize
        self.traits = traits
        self.systemFont = systemFont
        self.size = size
        self.scales = scales
    }

    var className: String { "UIFont" }
    var fallbackClassNames: [String] { ["NSFont"] }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(name, forKey: "UIFontName")
        switch kind {
        case .descriptor(let descriptor):
            try encoder.encode(descriptor, forKey: "UIFontDescriptor")
        case .textStyle(let style):
            try encoder.encode(style, forKey: "UIIBTextStyle")
        }
        encoder.encode(.double(pointSize), forKey: "UIFontPointSize")
        if scales {
            try encoder.encode(nil, forKey: "UIFontTextStyleForScaling")
            encoder.encode(.double(0), forKey: "UIFontPointSizeForScaling")
            encoder.encode(.double(0), forKey: "UIFontMaximumPointSizeAfterScaling")
        }
        encoder.encode(.integer(traits), forKey: "UIFontTraits")
        encoder.encode(.boolean(systemFont), forKey: "UISystemFont")
        try encoder.encode(name, forKey: "NSName")
        encoder.encode(.double(size), forKey: "NSSize")
    }

    /// System fonts by `weight`: the font's name, its usage and its traits; `bold` (and
    /// `type="boldSystem"`) is the emphasized usage overridden to bold, in a mutable dictionary.
    static let systemWeights: [String: (name: String, usage: String, traits: Int)] = [
        "ultraLight": (".SFUI-Ultralight", "CTFontUltraLightUsage", 16), "thin": (".SFUI-Thin", "CTFontThinUsage", 4),
        "light": (".SFUI-Light", "CTFontLightUsage", 8), "regular": (".SFUI-Regular", "CTFontRegularUsage", 0),
        "medium": (".SFUI-Medium", "CTFontMediumUsage", 0), "semibold": (".SFUI-Semibold", "CTFontDemiUsage", 2),
        "heavy": (".SFUI-Heavy", "CTFontHeavyUsage", 2), "black": (".SFUI-Black", "CTFontBlackUsage", 2),
    ]
    /// Text styles: the font's name, traits and `NSSize`; the point size is 0.
    static let textStyles: [String: (name: String, traits: Int, size: Double)] = [
        "UICTFontTextStyleBody": (".SFUI-Regular", 0, 14), "UICTFontTextStyleHeadline": (".SFUI-Semibold", 2, 14),
        "UICTFontTextStyleSubhead": (".SFUI-Regular", 0, 12), "UICTFontTextStyleCallout": (".SFUI-Regular", 0, 13),
        "UICTFontTextStyleFootnote": (".SFUI-Regular", 0, 12), "UICTFontTextStyleCaption1": (".SFUI-Regular", 0, 11),
        "UICTFontTextStyleCaption2": (".SFUI-Regular", 0, 11), "UICTFontTextStyleTitle0": (".SFUI-Regular", 0, 31),
        "UICTFontTextStyleTitle1": (".SFUI-Regular", 0, 25), "UICTFontTextStyleTitle2": (".SFUI-Regular", 0, 19),
        "UICTFontTextStyleTitle3": (".SFUI-Regular", 0, 17),
    ]
    /// Text styles' sizes at the default content size, of which a minimum scale factor makes the
    /// minimum font size, to the nearest quarter point as for fonts of a size (nib-experiments
    /// `label-style-scale-*`, `label-system-scale-*`).
    static let textStyleSizes: [String: Double] = [
        "UICTFontTextStyleBody": 17, "UICTFontTextStyleHeadline": 17, "UICTFontTextStyleSubhead": 15, "UICTFontTextStyleCallout": 16,
        "UICTFontTextStyleFootnote": 13, "UICTFontTextStyleCaption1": 12, "UICTFontTextStyleCaption2": 11, "UICTFontTextStyleTitle0": 34,
        "UICTFontTextStyleTitle1": 28, "UICTFontTextStyleTitle2": 22, "UICTFontTextStyleTitle3": 20,
    ]
    /// The named fonts of the corpus's documents: their traits and descriptor options.
    static let namedFonts: [String: (traits: Int, options: Int)] = [
        "Futura-Medium": (0, 2_147_483_648), "Futura-CondensedMedium": (0, 2_147_483_648), "DINAlternate-Bold": (2, 2_147_483_648),
        "Courier": (0, 2_147_483_648), "Courier-Bold": (0, 0), "CourierNewPS-BoldMT": (2, 2_147_483_648),
        "HelveticaNeue": (0, 2_147_483_648), "HelveticaNeue-Bold": (2, 2_147_483_648), "HelveticaNeue-UltraLight": (0, 2_147_483_648),
        "AvenirNext-Regular": (0, 2_147_483_648), "AvenirNext-DemiBold": (2, 2_147_483_648), "Georgia": (0, 2_147_483_648),
        "ArialRoundedMTBold": (0, 2_147_483_648), "GillSans-Bold": (2, 2_147_483_648), ".SFNS-Regular": (0, 0),
        "CourierNewPSMT": (0, 2_147_483_648), "HelveticaNeue-BoldItalic": (3, 2_147_483_648),
    ]
    static let systemOptions = 2_147_517_444
}

/// `UIFontDescriptor`: its attributes, a dictionary or nil, and its options.
final class NibFontDescriptor: NibArchivable {
    let attributes: NibDictionary?
    let options: Int

    init(attributes: NibDictionary?, options: Int) {
        self.attributes = attributes
        self.options = options
    }

    var className: String { "UIFontDescriptor" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(attributes, forKey: "UIFontDescriptorAttributes")
        encoder.encode(.integer(options), forKey: "UIFontDescriptorOptions")
    }
}

/// `NSNumber`: a double (`NS.dblval`) or an integer (`NS.intval`).
final class NibNumber: NibArchivable {
    let value: NibValue
    /// The value numbers compare by.
    let numericValue: Double

    init(_ value: Double) {
        self.value = .double(value)
        numericValue = value
    }

    init(integer: Int) {
        value = .integer(integer)
        numericValue = Double(integer)
    }

    var className: String { "NSNumber" }

    func encode(to encoder: NibEncoder) throws {
        if case .integer = value {
            encoder.encode(value, forKey: "NS.intval")
        } else {
            encoder.encode(value, forKey: "NS.dblval")
        }
    }
}

/// `NSLocalizableString`: a text of a document in an `.lproj` folder, its bytes, its key
/// (`<id>.<property>`) and the text again (nib-experiments `label-lproj`; the corpus's
/// flappy-fly-bird launch screen).
final class NibLocalizableString: NibArchivable {
    let value: String
    let key: NibString
    let development: NibString

    init(value: String, key: NibString, development: NibString) {
        self.value = value
        self.key = key
        self.development = development
    }

    var className: String { "NSLocalizableString" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.data(Array(value.utf8)), forKey: "NS.bytes")
        try encoder.encode(key, forKey: "NSKey")
        try encoder.encode(development, forKey: "NSDev")
    }
}
