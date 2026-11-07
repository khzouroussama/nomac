/// The attributes a rendition key is made of, with the numbers `KEYFORMAT` stores
/// (docs/formats/asset-catalog.md, "Key format"). Only attributes observed in actool's output
/// are listed.
public enum RenditionAttribute: UInt16, CaseIterable, Sendable {
    case element = 1
    case part = 2
    case direction = 4
    case appearance = 7
    case dimension1 = 8
    case dimension2 = 9
    case scale = 12
    case localization = 13
    case idiom = 15
    case subtype = 16
    case identifier = 17
    case displayGamut = 24
    case target = 25
    case glyphWeight = 26
    case glyphSize = 27

    /// The order attributes take in `KEYFORMAT`.
    static let keyFormatOrder: [RenditionAttribute] = [
        .appearance, .localization, .scale, .idiom, .subtype, .glyphWeight, .glyphSize, .dimension2, .dimension1, .target, .displayGamut,
        .direction, .identifier, .element, .part,
    ]

    /// Attributes every key format has, used or not.
    static let alwaysPresent: Set<RenditionAttribute> = [
        .appearance, .localization, .scale, .idiom, .subtype, .identifier, .element, .part,
    ]

    /// Attributes whose `BITMAPKEYS` entry is not a mask of the values used.
    static let unmasked: Set<RenditionAttribute> = [.appearance, .identifier, .element, .part]

    /// The bit a value sets in its attribute's `BITMAPKEYS` mask: the value itself, but bit 16 for
    /// the app icons' subtype 1792 (uncloudnotes, flappy-fly-bird), the only subtype nomac writes.
    /// A value's bit in a `BITMAPKEYS` mask: the value itself, but for subtypes a place in a
    /// table of their own (the iPhone's 1792 and the watch case sizes, 42mm's before 40mm's;
    /// `app-icons`, `watchos`, `complications` screen-widths).
    func maskBit(_ value: UInt16) -> UInt32 {
        guard self == .subtype, value != 0 else { return UInt32(value) }
        return Self.subtypeBits[value] ?? UInt32(value)
    }

    static let subtypeBits: [UInt16: UInt32] = [320: 8, 384: 9, 340: 13, 390: 14, 1792: 16, 430: 23, 484: 24, 502: 28]
}

/// The appearances a rendition can be for, as `APPEARANCEKEYS` names and numbers them.
public enum RenditionAppearance: UInt16, Sendable {
    case any = 0
    case dark = 1
    case highContrastAny = 2
    case highContrastDark = 3
    case light = 4
    case highContrastLight = 5
    /// Icon Composer icons' tinted appearance (`IconComposerIcon`).
    case tintable = 10

    /// An entry's `appearances`: none, luminosity dark or light, contrast high, or a luminosity
    /// and contrast high in either order (`colors`, `image-appearances`, `appearance-pairs`); nil
    /// for others.
    init?(entry appearances: [[String: Any]]) {
        let pairs = appearances.map { ($0["appearance"] as? String ?? "", $0["value"] as? String ?? "") }
        switch pairs.count {
        case 0: self = .any
        case 1 where pairs[0] == ("luminosity", "dark"): self = .dark
        case 1 where pairs[0] == ("luminosity", "light"): self = .light
        case 1 where pairs[0] == ("contrast", "high"): self = .highContrastAny
        case 2 where pairs.contains(where: { $0 == ("contrast", "high") }) && pairs.contains(where: { $0 == ("luminosity", "dark") }): self = .highContrastDark
        case 2 where pairs.contains(where: { $0 == ("contrast", "high") }) && pairs.contains(where: { $0 == ("luminosity", "light") }): self = .highContrastLight
        default: return nil
        }
    }

    var name: String {
        switch self {
        case .any: "UIAppearanceAny"
        case .dark: "UIAppearanceDark"
        case .highContrastAny: "UIAppearanceHighContrastAny"
        case .highContrastDark: "UIAppearanceHighContrastDark"
        case .light: "UIAppearanceLight"
        case .highContrastLight: "UIAppearanceHighContrastLight"
        case .tintable: "ISAppearanceTintable"
        }
    }
}

/// What kind of asset a rendition is, and the element and part numbers of its facet (data
/// and images share them).
public struct FacetKind: Hashable, Sendable {
    public var type: String
    public var element: UInt16
    public var part: UInt16
    /// A facet attribute after the identifier: symbol sets' target 5.
    public var target: UInt16 = 0

    public static let color = FacetKind(type: "color", element: 85, part: 217)
    public static let data = FacetKind(type: "data", element: 85, part: 181)
    public static let image = FacetKind(type: "image", element: 85, part: 181)
    /// The atlases small images are packed into, which have no facet.
    public static let packedImage = FacetKind(type: "packed image", element: 9, part: 181)
    /// App icon sets: their images are part 220, their size tables part 218 (`AppIconSet`).
    public static let appIcon = FacetKind(type: "app icon", element: 85, part: 220)
    /// Sprite atlases: their facet has no part; their atlas is part 181, their list of names
    /// part 127 (`SpriteAtlas`).
    public static let spriteAtlas = FacetKind(type: "sprite atlas", element: 9, part: 0)
    /// A stickers icon set's Messages App Store image: an image with CSI flags 0
    /// (`StickerCatalog`).
    public static let stickersIcon = FacetKind(type: "stickers icon", element: 85, part: 181)
    /// An Icon Composer icon's groups and gradients (`IconComposerIcon`); its icon stacks are
    /// part 245 renditions of its `appIcon` facet.
    public static let iconGroup = FacetKind(type: "icon group", element: 85, part: 246)
    public static let gradient = FacetKind(type: "gradient", element: 85, part: 247)
    /// Symbol sets: their glyphs are part 59, their images part 181, all with target 5 (`SymbolSet`).
    public static let symbol = FacetKind(type: "symbol", element: 85, part: 181, target: SymbolSet.target)
}
