import Foundation
import NomacCore
import NomacPlist

/// Icon Composer icons (`.icon`: `icon.json` and its `Assets` folder) compiled as actool compiles
/// them (docs/formats/asset-catalog.md, "Icon Composer icons"; expo-default and the self-written
/// icons of `assets-experiments icons`): the fill's colors and gradients, each layer image, an icon
/// stack and its groups for the dark, light and tinted appearances, the icon rendered at 1,024
/// pixels for the any, dark and tinted appearances and both idioms beside their size tables, and,
/// for the icon `--app-icon` names, the icon PNGs and the partial Info.plist's keys. The rendered
/// pixels are nomac's own (`IconRenderer`, ADR 0204).
struct IconComposerIcon {
    let name: String
    let path: String
    let fill: (light: Paint, dark: Paint)
    /// `color-space-for-untagged-svg-colors` `display-p3`: SVG colors are Display P3 values.
    let untaggedSVGColorsInDisplayP3: Bool
    let groups: [Group]
    /// The layer images by file name, in the order first used.
    let images: [(file: String, image: LayerImage)]

    enum LayerImage {
        case svg(SVGImage, data: [UInt8])
        case png(PNGImage, path: String)

        var size: (width: Double, height: Double) {
            switch self {
            case .svg(let svg, _): (svg.width, svg.height)
            case .png(let png, _): (Double(png.width), Double(png.height))
            }
        }

        /// actool fills a layer whose SVG paints only white with the icon's light fill in the dark
        /// appearance: each fill color's lightness ((max + min) / 2) in Display P3 is 0.85 or more
        /// (`icons` white cases: 0.8499 is not, 0.8501 is; PNG layers never are).
        var isWhite: Bool {
            guard case .svg(let svg, _) = self, !svg.shapes.isEmpty else { return false }
            return svg.paintColors.allSatisfy { color in
                let p3 = ColorConversion.sRGBToDisplayP3(color)
                return (max(p3.0, p3.1, p3.2) + min(p3.0, p3.1, p3.2)) / 2 >= 0.85
            }
        }
    }

    struct Group {
        var name: String
        var layers: [Layer]
        var style: [Appearance: GroupStyle]
    }

    struct GroupStyle {
        var opacity: Double
        var blendMode: UInt32
        /// A group hidden in this appearance only: opacity 0 in the stack, its layers without glass.
        var hidden: Bool
        var position: Position
        /// Property 1020 of the stack: 2 for individual lighting, 0 for combined, and the blur material.
        var lighting: UInt32
        var blurMaterial: Double
        var specular: Bool
        var translucency: Double
        var shadowKind: UInt32
        var shadowOpacity: Double
    }

    struct Layer {
        var file: String
        var style: [Appearance: LayerStyle]
        /// The layer's fill in the dark, light and tinted appearances, if any.
        var fills: [Appearance: Paint]
        /// Appearances whose fill is `none`, which keeps a white layer white in the dark one
        /// (icecubes' alternate icons).
        var unfilled: Set<Appearance>
    }

    struct LayerStyle {
        var opacity: Double
        var blendMode: UInt32
        var glass: Bool
        var hidden: Bool
        var position: Position
    }

    struct Position: Equatable {
        var scale = 1.0
        var x = 0.0
        var y = 0.0
    }

    enum Appearance: CaseIterable {
        case light, dark, tinted

        var key: String {
            switch self {
            case .light: "light"
            case .dark: "dark"
            case .tinted: "tinted"
            }
        }

        var stackAppearance: RenditionAppearance {
            switch self {
            case .light: .light
            case .dark: .dark
            case .tinted: .tintable
            }
        }
    }

    struct IconColor: Hashable {
        var space: UInt32
        var components: [Double]
    }

    struct Gradient: Hashable {
        var stops: [IconColor]
        var automatic: Bool
        /// Start x and y, stop x and y, in the unit square from the top left.
        var orientation: [Double]
    }

    enum Paint: Hashable {
        case color(IconColor)
        case gradient(Gradient)
        case systemLight
        case systemDark

        static let defaultOrientation = [0.5, 0, 0.5, 1]
        static let white = Paint.color(IconColor(space: 6, components: [1, 1]))

        /// The gradients actool's system fills stand for (`icons` fills cases).
        static let systemLightGradient = Gradient(stops: [IconColor(space: 2, components: [1, 1]), IconColor(space: 2, components: [IconComposerIcon.stored(0.925), 1])],
                                                  automatic: false, orientation: defaultOrientation)
        static let systemDarkGradient = Gradient(stops: [IconColor(space: 2, components: [IconComposerIcon.stored(0.192), 1]), IconColor(space: 2, components: [IconComposerIcon.stored(0.078), 1])],
                                                 automatic: false, orientation: defaultOrientation)

        var gradient: Gradient? {
            switch self {
            case .systemLight: Self.systemLightGradient
            case .systemDark: Self.systemDarkGradient
            case .gradient(let gradient): gradient
            case .color: nil
            }
        }
    }

    static func unsupported(_ what: String, path: String) -> NomacError {
        NomacError("Icon Composer icons with \(what) are not supported yet (BACKLOG B-210)", path: path)
    }

    init(path: String) throws {
        self.path = path
        name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let data = FileManager.default.contents(atPath: path + "/icon.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NomacError("the icon has no readable icon.json", path: path)
        }
        let fail = { (what: String) in Self.unsupported(what, path: path) }
        try Self.check(json, allowed: ["fill", "fill-specializations", "groups", "supported-platforms", "color-space-for-untagged-svg-colors"], fail)
        if let platforms = json["supported-platforms"] as? [String: Any] {
            let squares = platforms["squares"]
            guard Set(platforms.keys).isSubset(of: ["squares", "circles"]),
                  squares == nil || squares as? String == "shared" || (squares as? [String]).map({ Set($0).isSubset(of: ["iOS", "macOS"]) }) == true,
                  (platforms["circles"] as? [String]).map({ $0 == ["watchOS"] }) ?? (platforms["circles"] == nil) else {
                throw fail("supported platforms \(platforms)")
            }
        }
        let iconFills = try Self.specializations(json, "fill", fail)
        // The icon's dark fill has no default but system-dark; its tinted fill is its light one
        // (`icons` fills cases C11, C14, Q06, P21).
        fill = (light: try iconFills[.light].map { try Self.paint($0, dark: false, fail) } ?? .white,
                dark: try (json["fill"] == nil ? Self.darkSpecialization(json) : nil).map { try Self.paint($0, dark: true, fail) } ?? .systemDark)
        untaggedSVGColorsInDisplayP3 = json["color-space-for-untagged-svg-colors"] as? String == "display-p3"
        if let space = json["color-space-for-untagged-svg-colors"], !untaggedSVGColorsInDisplayP3 { throw fail("untagged SVG colors in \(space)") }
        var groups: [Group] = []
        var images: [(file: String, image: LayerImage)] = []
        var groupNames: Set<String> = []
        for group in json["groups"] as? [[String: Any]] ?? [] {
            try Self.check(group, allowed: Self.groupKeys.union(Self.groupKeys.subtracting(["layers", "name"]).map { $0 + "-specializations" }), fail)
            let groupValues = try Dictionary(uniqueKeysWithValues: Self.groupKeys.map { ($0, try Self.specializations(group, $0, fail)) })
            let groupHidden = Set(Appearance.allCases.filter { Self.bool(groupValues["hidden"]![$0]) == true })
            if groupHidden.count == Appearance.allCases.count { continue }
            var layers: [Layer] = []
            for layer in group["layers"] as? [[String: Any]] ?? [] {
                try Self.check(layer, allowed: Self.layerKeys.union(Self.layerKeys.subtracting(["name"]).map { $0 + "-specializations" }), fail)
                let values = try Dictionary(uniqueKeysWithValues: Self.layerKeys.map { ($0, try Self.specializations(layer, $0, fail)) })
                let hidden = Set(Appearance.allCases.filter { Self.bool(values["hidden"]![$0]) == true })
                if hidden.count == Appearance.allCases.count { continue }
                guard let file = values["image-name"]![.light] as? String else { throw fail("a layer without an image") }
                if !images.contains(where: { $0.file == file }) {
                    images.append((file, try Self.image(path + "/Assets/" + file, untaggedColorsInDisplayP3: untaggedSVGColorsInDisplayP3, fail)))
                }
                var paints: [Appearance: Paint] = [:]
                var unfilled: Set<Appearance> = []
                var style: [Appearance: LayerStyle] = [:]
                for appearance in Appearance.allCases {
                    let value = Self.layerFill(layer, appearance)
                    if value as? String == "none" { unfilled.insert(appearance) }
                    if let value, let paint = try Self.layerPaint(value, fail) {
                        paints[appearance] = paint
                    }
                    let blend = values["blend-mode"]![appearance] as? String ?? "normal"
                    guard let blendMode = Self.blendModes[blend] else { throw fail("the blend mode '\(blend)'") }
                    style[appearance] = LayerStyle(opacity: Self.number(values["opacity"]![appearance]) ?? 1, blendMode: blendMode,
                                                   glass: Self.bool(values["glass"]![appearance]) ?? true, hidden: hidden.contains(appearance),
                                                   position: try Self.position(values["position"]![appearance], fail))
                }
                layers.append(Layer(file: file, style: style, fills: paints, unfilled: unfilled))
            }
            var style: [Appearance: GroupStyle] = [:]
            for appearance in Appearance.allCases {
                let shadow = groupValues["shadow"]![appearance] as? [String: Any]
                let translucency = groupValues["translucency"]![appearance] as? [String: Any]
                guard shadow == nil || Set(shadow!.keys) == ["kind", "opacity"], translucency == nil || Set(translucency!.keys) == ["enabled", "value"] else {
                    throw fail("a shadow or translucency without both of its values")
                }
                let shadowKinds: [String: UInt32] = ["none": 0, "layer-color": 2, "neutral": 3]
                guard let shadowKind = shadowKinds[shadow?["kind"] as? String ?? "neutral"] else { throw fail("the shadow \(shadow!)") }
                let lighting = groupValues["lighting"]![appearance] as? String ?? "individual"
                guard ["individual", "combined"].contains(lighting) else { throw fail("the lighting '\(lighting)'") }
                let blend = groupValues["blend-mode"]![appearance] as? String ?? "normal"
                guard let blendMode = Self.blendModes[blend] else { throw fail("the blend mode '\(blend)'") }
                style[appearance] = GroupStyle(
                    opacity: Self.number(groupValues["opacity"]![appearance]) ?? 1, blendMode: blendMode, hidden: groupHidden.contains(appearance),
                    position: try Self.position(groupValues["position"]![appearance], fail),
                    lighting: lighting == "individual" ? 2 : 0, blurMaterial: Self.number(groupValues["blur-material"]![appearance]) ?? 0,
                    specular: Self.bool(groupValues["specular"]![appearance]) ?? true,
                    translucency: translucency.map { Self.bool($0["enabled"]) == true ? Self.number($0["value"]) ?? 0 : 0 } ?? 0.3,
                    shadowKind: shadowKind, shadowOpacity: shadow.flatMap { Self.number($0["opacity"]) } ?? 0.5)
            }
            // A group's facet is its name, `/` written `_`, else "Group"; names already taken get
            // " 2", " 3"... (`icons` group-name cases N01–N04, N08).
            let base = (group["name"] as? String ?? "Group").replacingOccurrences(of: "/", with: "_")
            var name = base
            var number = 2
            while groupNames.contains(name) {
                name = "\(base) \(number)"
                number += 1
            }
            groupNames.insert(name)
            groups.append(Group(name: name, layers: layers, style: style))
        }
        self.groups = groups
        self.images = images
    }

    static let groupKeys: Set<String> = ["layers", "name", "hidden", "opacity", "blend-mode", "position", "shadow", "translucency", "specular", "lighting", "blur-material"]
    static let layerKeys: Set<String> = ["image-name", "name", "hidden", "opacity", "blend-mode", "glass", "fill", "position"]

    /// CoreGraphics' blend modes, as `icons` blend cases store them.
    static let blendModes: [String: UInt32] = [
        "normal": 0, "multiply": 1, "screen": 2, "overlay": 3, "darken": 4, "lighten": 5, "soft-light": 8, "hard-light": 9,
        "plus-darker": 26, "plus-lighter": 27,
    ]

    static func check(_ object: [String: Any], allowed: Set<String>, _ fail: (String) -> NomacError) throws {
        if let key = object.keys.sorted().first(where: { !allowed.contains($0) }) { throw fail("the key '\(key)'") }
    }

    static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    static func bool(_ value: Any?) -> Bool? { (value as? NSNumber)?.boolValue }

    /// A property's value in each appearance: the property itself in all of them, or else its
    /// specializations, the appearance's own or else the one without an appearance; a value
    /// neither gives is the default (`icons` specializations cases Q01–Q03, Q13, Q14, Q21, P18).
    static func specializations(_ object: [String: Any], _ key: String, _ fail: (String) -> NomacError) throws -> [Appearance: Any] {
        if let value = object[key] { return [.light: value, .dark: value, .tinted: value] }
        guard let specializations = object[key + "-specializations"] as? [[String: Any]] else { return [:] }
        var values: [String: Any] = [:]
        for specialization in specializations {
            let appearance = specialization["appearance"] as? String ?? ""
            guard ["", "light", "dark", "tinted"].contains(appearance), let value = specialization["value"] else {
                throw fail("the \(key) specialization \(specialization)")
            }
            values[appearance] = value
        }
        var result: [Appearance: Any] = [:]
        for appearance in Appearance.allCases {
            if let value = values[appearance.key] ?? values[""] { result[appearance] = value }
        }
        return result
    }

    /// A layer's fill in an appearance: its `fill`, or else its specialization for the appearance,
    /// the one without an appearance, then (for dark and tinted) the light one, `automatic`
    /// deferring to the next (`icons` V18, Q04, Q22; icecubes' tinted `automatic`).
    static func layerFill(_ layer: [String: Any], _ appearance: Appearance) -> Any? {
        if let value = layer["fill"] { return value }
        let values = Dictionary((layer["fill-specializations"] as? [[String: Any]] ?? []).compactMap { specialization in
            specialization["value"].map { (specialization["appearance"] as? String ?? "", $0) }
        }, uniquingKeysWith: { _, last in last })
        let order = appearance == .light ? ["light", ""] : [appearance.key, "", "light"]
        return order.lazy.compactMap { values[$0] }.first { $0 as? String != "automatic" }
    }

    static func darkSpecialization(_ object: [String: Any]) -> Any? {
        (object["fill-specializations"] as? [[String: Any]])?.last { $0["appearance"] as? String == "dark" }?["value"]
    }

    /// An icon fill: `automatic` and `none` are the system fill of their appearance.
    static func paint(_ value: Any, dark: Bool, _ fail: (String) -> NomacError) throws -> Paint {
        if let name = value as? String {
            switch name {
            case "automatic", "none": return dark ? .systemDark : .systemLight
            case "system-light": return .systemLight
            case "system-dark": return .systemDark
            default: throw fail("the fill '\(name)'")
            }
        }
        guard let paint = try layerPaint(value, fail) else { throw fail("the fill \(value)") }
        return paint
    }

    /// A layer fill; `automatic` and `none` leave the layer as it is.
    static func layerPaint(_ value: Any, _ fail: (String) -> NomacError) throws -> Paint? {
        if let name = value as? String {
            switch name {
            case "automatic", "none": return nil
            case "system-light": return .systemLight
            case "system-dark": return .systemDark
            default: throw fail("the fill '\(name)'")
            }
        }
        guard let object = value as? [String: Any] else { throw fail("the fill \(value)") }
        try check(object, allowed: ["solid", "linear-gradient", "automatic-gradient", "orientation"], fail)
        var orientation = Paint.defaultOrientation
        if let given = object["orientation"] as? [String: Any] {
            let start = given["start"] as? [String: Any] ?? [:], stop = given["stop"] as? [String: Any] ?? [:]
            orientation = [number(start["x"]) ?? 0.5, number(start["y"]) ?? 0, number(stop["x"]) ?? 0.5, number(stop["y"]) ?? 1]
        }
        if let solid = object["solid"] as? String { return .color(try color(solid, fail)) }
        if let stops = object["linear-gradient"] as? [String], stops.count == 2 {
            return .gradient(Gradient(stops: try stops.map { try color($0, fail) }, automatic: false, orientation: orientation))
        }
        if let base = object["automatic-gradient"] as? String {
            return .gradient(Gradient(stops: [try color(base, fail)], automatic: true, orientation: orientation))
        }
        throw fail("the fill \(object)")
    }

    /// `<space>:<components>`, each component kept to three decimals of its value, then single
    /// precision (`icons` colors cases: 0.47843 is stored 0.478, 0.0005 is 0.001, 0.9995 is 1,
    /// 0.1235 is 0.123; icecubes' 0.0065 is 0.006).
    static func color(_ text: String, _ fail: (String) -> NomacError) throws -> IconColor {
        let spaces: [String: (UInt32, Int)] = ["srgb": (1, 4), "gray": (2, 2), "display-p3": (3, 4), "extended-srgb": (4, 4), "extended-gray": (6, 2)]
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let (space, count) = spaces[parts[0]] else { throw fail("the color '\(text)'") }
        let components = parts[1].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard components.count == count else { throw fail("the color '\(text)'") }
        return IconColor(space: space, components: components.map(stored))
    }

    static func stored(_ value: Double) -> Double {
        Double(Float(String(format: "%.3f", value))!)
    }

    static func position(_ value: Any?, _ fail: (String) -> NomacError) throws -> Position {
        guard let object = value as? [String: Any] else { return Position() }
        let translation = object["translation-in-points"] as? [Any] ?? [0, 0]
        guard Set(object.keys).isSubset(of: ["scale", "translation-in-points"]), translation.count == 2 else { throw fail("the position \(object)") }
        return Position(scale: number(object["scale"]) ?? 1, x: number(translation[0]) ?? 0, y: number(translation[1]) ?? 0)
    }

    static func image(_ path: String, untaggedColorsInDisplayP3: Bool, _ fail: (String) -> NomacError) throws -> LayerImage {
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("the layer image does not exist", path: path) }
        switch (path as NSString).pathExtension.lowercased() {
        case "svg": return .svg(try SVGImage(data: data, path: path, untaggedColorsInDisplayP3: untaggedColorsInDisplayP3), data: [UInt8](data))
        case "png": return .png(try PNGImage(data: [UInt8](data), path: path), path: path)
        default: throw fail("layer images other than SVG and PNG")
        }
    }

    /// The layer's place on the 1,024-point canvas: its size, the image's times both scales,
    /// rounded to the nearest (ties to even), and its origin, the canvas's center moved by the
    /// group's translation and the layer's times the group's scale, less half the unrounded size,
    /// rounded down (`icons` position cases).
    func rect(_ layer: Layer, in group: Group, _ appearance: Appearance) -> (x: Int, y: Int, width: Int, height: Int) {
        let size = images.first { $0.file == layer.file }!.image.size
        let groupPosition = group.style[appearance]!.position, layerPosition = layer.style[appearance]!.position
        let scale = groupPosition.scale * layerPosition.scale
        let width = scale * size.width, height = scale * size.height
        let x = 512 + groupPosition.x + groupPosition.scale * layerPosition.x - width / 2
        let y = 512 + groupPosition.y + groupPosition.scale * layerPosition.y - height / 2
        return (Int(x.rounded(.down)), Int(y.rounded(.down)), Int(width.rounded(.toNearestOrEven)), Int(height.rounded(.toNearestOrEven)))
    }

    func groupName(_ group: Group) -> String { name + "/" + group.name }

    func imageName(_ file: String) -> String { name + "_Assets/" + (file as NSString).deletingPathExtension }

    /// The paint each layer has in an appearance: its own, or in the dark appearance the icon's
    /// light fill for a white SVG layer without one.
    func layerPaint(_ layer: Layer, _ appearance: Appearance) -> Paint? {
        if let paint = layer.fills[appearance] { return paint }
        if appearance == .dark, !layer.unfilled.contains(.dark), images.first(where: { $0.file == layer.file })!.image.isWhite { return fill.light }
        return nil
    }
}
