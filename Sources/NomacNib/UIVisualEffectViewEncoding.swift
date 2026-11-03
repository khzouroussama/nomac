import Foundation

/// What a `UIVisualEffectView` writes after a view's keys (docs/formats/nib.md "Visual effect
/// views"; nib-experiments `effect-*`): its effect, no group name and its content view, which is
/// not one of its subviews.
struct EffectContent {
    let effect: NibBlurEffect
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
        "systemChromeMaterial": (10, 5, 0), "systemMaterialDark": (18, nil, 2),
    ]
}

extension DocumentCompiler {
    /// A `<visualEffectView>`'s blur and content view, a `_UIVisualEffectContentView` compiled as a
    /// view of the effect view, which lists its subviews before its constraints
    /// (`effect-label-constraints`). Both write `UIShouldNotAdaptToMaterials`. Vibrancy effects
    /// are refused.
    mutating func effectContent(_ element: XIBElement, id: String) throws -> EffectContent {
        let blurs = element.children(named: "blurEffect")
        guard blurs.count == 1, let blur = blurs.first else { throw unsupported("a visual effect view without one blur effect") }
        try check(blur, attributes: ["style"], children: [])
        guard let style = NibBlurEffect.styles[blur.attributes["style"] ?? ""] else {
            throw unsupported("<blurEffect style=\"\(blur.attributes["style"] ?? "")\">")
        }
        guard let content = element.child("view", key: "contentView") else { throw unsupported("a visual effect view without a content view") }
        let contentElement = XIBElement(name: "view", attributes: content.attributes.filter { $0.key != "key" })
        contentElement.children = content.children
        let contentView = try view(contentElement, topLevel: false, parent: id)
        contentView.kind = .effectContentView
        contentView.flags.shouldNotAdaptToMaterials = true
        return EffectContent(effect: NibBlurEffect(material: style.material, automatic: style.automatic, style: style.style), contentView: contentView)
    }
}
