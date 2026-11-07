import Foundation

/// What a `UIVisualEffectView` writes after a view's keys (docs/formats/nib.md "Visual effect
/// views"; nib-experiments `effect-*`): its effect, no group name and its content view, which is
/// not one of its subviews.
struct EffectContent {
    let effect: NibArchivable
    let contentView: NibView

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(effect, forKey: "UIVisualEffectViewEffect")
        encoder.encode(.null, forKey: "UIVisualEffectViewGroupName")
        try encoder.encode(contentView, forKey: "UIVisualEffectViewContentView")
    }
}

/// `UIBlurEffect`: its material, automatic and plain styles, by the style IB names
/// (`effect-style-*`).
final class NibBlurEffect: NibArchivable {
    let material: Int?
    let automatic: Int?
    let style: Int

    init(material: Int?, automatic: Int?, style: Int) {
        self.material = material
        self.automatic = automatic
        self.style = style
    }

    var className: String { "UIBlurEffect" }

    func encode(to encoder: NibEncoder) throws {
        if let material { encoder.encode(.integer(material), forKey: "UIBlurEffectMaterialStyle") }
        if let automatic { encoder.encode(.integer(automatic), forKey: "UIBlurEffectAutomaticStyle") }
        encoder.encode(.integer(style), forKey: "UIBlurEffectStyle")
    }

    static let styles: [String: (material: Int?, automatic: Int?, style: Int)] = [
        "extraLight": (nil, nil, 0), "light": (nil, nil, 1), "dark": (nil, nil, 2), "regular": (nil, 4, 1), "prominent": (nil, 5, 0),
        "systemUltraThinMaterial": (6, 4, 1), "systemThinMaterial": (7, 4, 1), "systemMaterial": (8, 4, 1), "systemThickMaterial": (9, 4, 1),
        "systemChromeMaterial": (10, 5, 0), "systemMaterialDark": (18, nil, 2), "systemMaterialLight": (13, nil, 1),
    ]
}

/// `UIVibrancyEffect` of a `<vibrancyEffect>`: its style for a blur of a material, by IB's name,
/// the secondary label's without one, then its blur's styles (`vibrancy-*`, `vibrancy-grid-*`).
final class NibVibrancyEffect: NibArchivable {
    static let styles = ["label": 0, "secondaryLabel": 1, "tertiaryLabel": 2, "quaternaryLabel": 3, "fill": 4, "secondaryFill": 5, "tertiaryFill": 6, "separator": 7]

    let vibrancy: Int?
    let blur: (material: Int?, automatic: Int?, style: Int)

    init(vibrancy: Int?, blur: (material: Int?, automatic: Int?, style: Int)) {
        self.vibrancy = vibrancy
        self.blur = blur
    }

    var className: String { "UIVibrancyEffect" }

    func encode(to encoder: NibEncoder) throws {
        if let vibrancy { encoder.encode(.integer(vibrancy), forKey: "UIVibrancyEffectVibrancyStyle") }
        if let material = blur.material { encoder.encode(.integer(material), forKey: "UIVibrancyEffectBlurMaterialStyle") }
        if let automatic = blur.automatic { encoder.encode(.integer(automatic), forKey: "UIVibrancyEffectBlurAutomaticStyle") }
        encoder.encode(.integer(blur.style), forKey: "UIVibrancyEffectBlurStyle")
    }
}

extension DocumentCompiler {
    /// A `<visualEffectView>`'s blur and content view, a `_UIVisualEffectContentView` compiled as a
    /// view of the effect view, which lists its subviews before its constraints
    /// (`effect-label-constraints`). Both write `UIShouldNotAdaptToMaterials`. A vibrancy effect's
    /// content view writes a tint of its own: white, but for the label style over a material, 96% black
    /// or, over a dark one, 96% white (`vibrancy-grid-*`).
    mutating func effectContent(_ element: XIBElement, id: String) throws -> EffectContent {
        let vibrancy = element.children(named: "vibrancyEffect").first
        let blurs = (vibrancy ?? element).children(named: "blurEffect")
        guard blurs.count == 1, element.children(named: "vibrancyEffect").count + element.children(named: "blurEffect").count == 1, let blur = blurs.first else {
            throw unsupported("a visual effect view without one blur effect")
        }
        try check(blur, attributes: ["style"], children: [])
        guard let style = NibBlurEffect.styles[blur.attributes["style"] ?? ""] else {
            throw unsupported("<blurEffect style=\"\(blur.attributes["style"] ?? "")\">")
        }
        if let vibrancy {
            try check(vibrancy, attributes: ["style"], children: ["blurEffect"])
            try value(vibrancy, "style", in: Set(NibVibrancyEffect.styles.keys))
        }
        guard let content = element.child("view", key: "contentView") else { throw unsupported("a visual effect view without a content view") }
        let contentElement = XIBElement(name: "view", attributes: content.attributes.filter { $0.key != "key" })
        contentElement.children = content.children
        let contentView = try view(contentElement, topLevel: false, parent: id)
        contentView.kind = .effectContentView
        contentView.flags.shouldNotAdaptToMaterials = true
        guard let vibrancy else {
            return EffectContent(effect: NibBlurEffect(material: style.material, automatic: style.automatic, style: style.style), contentView: contentView)
        }
        guard contentView.tintColor == nil else { throw unsupported("a tint of a vibrancy effect's content view") }
        let named = vibrancy.attributes["style"]
        let material = style.material != nil
        if named == "label", material {
            contentView.tintColor = try color(XIBElement(name: "color", attributes: ["key": "tintColor", "white": style.style == 2 ? "1" : "0", "alpha": "0.96", "colorSpace": "custom",
                                                                                     "customColorSpace": "genericGamma22GrayColorSpace"]))
        } else {
            contentView.tintColor = try color(XIBElement(name: "color", attributes: ["key": "tintColor", "cocoaTouchSystemColor": "whiteColor"]))
        }
        return EffectContent(effect: NibVibrancyEffect(vibrancy: material ? named.flatMap { NibVibrancyEffect.styles[$0] } ?? 1 : nil, blur: style), contentView: contentView)
    }
}
