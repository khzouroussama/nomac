import Foundation

/// A `UIColor` as ibtool archives it (docs/formats/nib.md "UIColor"; nib-experiments `gray-*`,
/// `rgb-*`, `systemColor-*`, `cocoaTouchSystemColor-*`, `named-color`).
final class NibColor: NibArchivable {
    enum Components: Equatable, Hashable {
        case gray(white: Double, alpha: Double)
        case rgb(red: Double, green: Double, blue: Double, alpha: Double)

        /// Each component rounded to `digits` significant digits, as `%.*g` writes it.
        func significant(_ digits: Int) -> Components {
            switch self {
            case .gray(let white, let alpha):
                return .gray(white: Self.round(white, digits), alpha: Self.round(alpha, digits))
            case .rgb(let red, let green, let blue, let alpha):
                return .rgb(red: Self.round(red, digits), green: Self.round(green, digits), blue: Self.round(blue, digits), alpha: Self.round(alpha, digits))
            }
        }

        /// The alpha alone rounded so, as a storyboard keeps a converted color's components
        /// (nib-experiments `sb-converted-*`).
        func significantAlpha(_ digits: Int) -> Components {
            switch self {
            case .gray(let white, let alpha): return .gray(white: white, alpha: Self.round(alpha, digits))
            case .rgb(let red, let green, let blue, let alpha): return .rgb(red: red, green: green, blue: blue, alpha: Self.round(alpha, digits))
            }
        }

        private static func round(_ value: Double, _ digits: Int) -> Double { Double(String(format: "%.\(digits)g", value))! }
    }

    enum Name: Equatable, Hashable {
        /// `UISystemColorName`.
        case system(String)
        /// `UIDynamicCatalogName`, a named color of the document's resources.
        case catalog(String)
    }

    let components: Components
    let name: (kind: Name, string: NibString)?

    init(components: Components, name: (kind: Name, string: NibString)?) {
        self.components = components
        self.name = name
    }

    var className: String { "UIColor" }
    var fallbackClassNames: [String] { ["NSColor"] }

    func encode(to encoder: NibEncoder) throws {
        switch name?.kind {
        case .system?:
            try encoder.encode(name!.string, forKey: "UISystemColorName")
        case .catalog?:
            try encoder.encode(name!.string, forKey: "UIDynamicCatalogName")
            encoder.encode(.boolean(true), forKey: "UIDynamicCatalogUseNibBundle")
        case nil:
            break
        }
        switch components {
        case .gray(let white, let alpha):
            encoder.encode(.integer(2), forKey: "UIColorComponentCount")
            Self.encode(white, "UIWhite", to: encoder)
            Self.encode(alpha, "UIAlpha", to: encoder)
            encoder.encode(.data(Self.text([white], alpha: alpha)), forKey: "NSWhite")
            encoder.encode(.integer(4), forKey: "NSColorSpace")
        case .rgb(let red, let green, let blue, let alpha):
            encoder.encode(.integer(4), forKey: "UIColorComponentCount")
            Self.encode(red, "UIRed", to: encoder)
            Self.encode(green, "UIGreen", to: encoder)
            Self.encode(blue, "UIBlue", to: encoder)
            Self.encode(alpha, "UIAlpha", to: encoder)
            encoder.encode(.data(Self.text([red, green, blue], alpha: alpha)), forKey: "NSRGB")
            encoder.encode(.integer(2), forKey: "NSColorSpace")
        }
    }

    /// A component as a float, and as a double under `<key>-Double` when the float is not it.
    private static func encode(_ value: Double, _ key: String, to encoder: NibEncoder) {
        encoder.encode(.float(Float(value)), forKey: key)
        if Double(Float(value)) != value {
            encoder.encode(.double(value), forKey: key + "-Double")
        }
    }

    /// `NSWhite` and `NSRGB`: the components with three significant digits, then the alpha
    /// unless it is 1.
    private static func text(_ values: [Double], alpha: Double) -> [UInt8] {
        let all = alpha == 1 ? values : values + [alpha]
        return Array(all.map { String(format: "%.3g", $0) }.joined(separator: " ").utf8)
    }

    /// The gray colors IB names (`gray-0-1`, `gray-1-1`, `gray-0-0`); no other gray or RGB
    /// color of a document gets a name.
    static func grayName(white: Double, alpha: Double) -> String? {
        switch (white, alpha) {
        case (0, 1): "blackColor"
        case (1, 1): "whiteColor"
        case (0, 0): "clearColor"
        default: nil
        }
    }

    /// The values IB gives system colors, whatever the document's `<systemColor>` definition says.
    static let systemColors: [String: Components] = [
        "blackColor": .gray(white: 0, alpha: 1),
        "clearColor": .gray(white: 0, alpha: 0),
        "darkTextColor": .gray(white: 0, alpha: 1),
        "labelColor": .gray(white: 0, alpha: 1),
        "lightTextColor": .gray(white: 1, alpha: 0.6),
        "secondarySystemGroupedBackgroundColor": .gray(white: 1, alpha: 1),
        "systemBackgroundColor": .gray(white: 1, alpha: 1),
        "tertiarySystemBackgroundColor": .gray(white: 1, alpha: 1),
        "whiteColor": .gray(white: 1, alpha: 1),
        "groupTableViewBackgroundColor": .rgb(red: 0.9490196078, green: 0.9490196078, blue: 0.968627451, alpha: 1),
        "linkColor": .rgb(red: 0, green: 0.4784313725, blue: 1, alpha: 1),
        "opaqueSeparatorColor": .rgb(red: 0.7764705882, green: 0.7764705882, blue: 0.7843137255, alpha: 1),
        "placeholderTextColor": .rgb(red: 0.2352941176, green: 0.2352941176, blue: 0.262745098, alpha: 0.2980392157),
        "quaternaryLabelColor": .rgb(red: 0.2352941176, green: 0.2352941176, blue: 0.262745098, alpha: 0.1764705882),
        "quaternarySystemFillColor": .rgb(red: 0.4549019608, green: 0.4549019608, blue: 0.5019607843, alpha: 0.08),
        "scrollViewTexturedBackgroundColor": .rgb(red: 0.4352941176, green: 0.4431372549, blue: 0.4745098039, alpha: 1),
        "secondaryLabelColor": .rgb(red: 0.2352941176, green: 0.2352941176, blue: 0.262745098, alpha: 0.6),
        "secondarySystemBackgroundColor": .rgb(red: 0.9490196078, green: 0.9490196078, blue: 0.968627451, alpha: 1),
        "secondarySystemFillColor": .rgb(red: 0.4705882353, green: 0.4705882353, blue: 0.5019607843, alpha: 0.16),
        "separatorColor": .rgb(red: 0.2352941176, green: 0.2352941176, blue: 0.262745098, alpha: 0.12),
        "systemBlueColor": .rgb(red: 0, green: 0.5333333333, blue: 1, alpha: 1),
        "systemBrownColor": .rgb(red: 0.6745098039, green: 0.4980392157, blue: 0.368627451, alpha: 1),
        "systemCyanColor": .rgb(red: 0, green: 0.7529411765, blue: 0.9098039216, alpha: 1),
        "systemFillColor": .rgb(red: 0.4705882353, green: 0.4705882353, blue: 0.5019607843, alpha: 0.2),
        "systemGray2Color": .rgb(red: 0.6823529412, green: 0.6823529412, blue: 0.6980392157, alpha: 1),
        "systemGray3Color": .rgb(red: 0.7803921569, green: 0.7803921569, blue: 0.8, alpha: 1),
        "systemGray4Color": .rgb(red: 0.8196078431, green: 0.8196078431, blue: 0.8392156863, alpha: 1),
        "systemGray5Color": .rgb(red: 0.8980392157, green: 0.8980392157, blue: 0.9176470588, alpha: 1),
        "systemGray6Color": .rgb(red: 0.9490196078, green: 0.9490196078, blue: 0.968627451, alpha: 1),
        "systemGrayColor": .rgb(red: 0.5568627451, green: 0.5568627451, blue: 0.5764705882, alpha: 1),
        "systemGreenColor": .rgb(red: 0.2039215686, green: 0.7803921569, blue: 0.3490196078, alpha: 1),
        "systemGroupedBackgroundColor": .rgb(red: 0.9490196078, green: 0.9490196078, blue: 0.968627451, alpha: 1),
        "systemIndigoColor": .rgb(red: 0.3803921569, green: 0.3333333333, blue: 0.9607843137, alpha: 1),
        "systemMintColor": .rgb(red: 0, green: 0.7843137255, blue: 0.7019607843, alpha: 1),
        "systemOrangeColor": .rgb(red: 1, green: 0.5529411765, blue: 0.1568627451, alpha: 1),
        "systemPinkColor": .rgb(red: 1, green: 0.1764705882, blue: 0.3333333333, alpha: 1),
        "systemPurpleColor": .rgb(red: 0.7960784314, green: 0.1882352941, blue: 0.8784313725, alpha: 1),
        "systemRedColor": .rgb(red: 1, green: 0.2196078431, blue: 0.2352941176, alpha: 1),
        "systemTealColor": .rgb(red: 0, green: 0.7647058824, blue: 0.8156862745, alpha: 1),
        "systemYellowColor": .rgb(red: 1, green: 0.8, blue: 0, alpha: 1),
        "tertiaryLabelColor": .rgb(red: 0.2352941176, green: 0.2352941176, blue: 0.262745098, alpha: 0.2980392157),
        "tertiarySystemFillColor": .rgb(red: 0.462745098, green: 0.462745098, blue: 0.5019607843, alpha: 0.12),
        "tertiarySystemGroupedBackgroundColor": .rgb(red: 0.9490196078, green: 0.9490196078, blue: 0.968627451, alpha: 1),
        "tintColor": .rgb(red: 0, green: 0.5333333333, blue: 1, alpha: 1),
        "viewFlipsideBackgroundColor": .rgb(red: 0.1215686275, green: 0.1294117647, blue: 0.1411764706, alpha: 1),
    ]


    /// `xcode11CocoaTouchSystemColor` or `systemColor` names, with the `cocoaTouchSystemColor` written
    /// beside them, observed: the first name is the color (`x11-system-background`,
    /// `color-system-and-cocoa-touch`, React Native's launch screen).
    static let xcode11SystemColors = ["systemBackgroundColor": "whiteColor"]

    /// The names observed as `systemColor` (`viewFlipsideBackgroundColor` only as
    /// `cocoaTouchSystemColor`).
    static let observedSystemColorNames = Set(systemColors.keys).subtracting(["viewFlipsideBackgroundColor"])

    /// The names `cocoaTouchSystemColor` takes (others, such as `grayColor`, make ibtool fail).
    static let cocoaTouchSystemColors: Set<String> = ["whiteColor", "darkTextColor", "groupTableViewBackgroundColor", "lightTextColor",
                                                      "clearColor", "scrollViewTexturedBackgroundColor", "viewFlipsideBackgroundColor",
                                                      "blackColor"]
}
