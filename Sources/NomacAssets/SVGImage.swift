import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import NomacCore

/// The SVG files nomac reads for Icon Composer layers (ADR 0204): their size in points, which
/// actool takes from `width` and `height` (px, pt or none) or else the `viewBox`
/// (docs/formats/asset-catalog.md, "Icon Composer icons"), and the filled shapes nomac's renderer
/// draws: paths, rectangles, circles, ellipses, polygons and polylines filled with a color or a
/// linear or radial gradient, in groups with transforms and clip paths, styled by attributes,
/// `style` and simple style sheets. Other SVG features (strokes, masks, `<use>`, filters) stop
/// nomac (BACKLOG B-210).
struct SVGImage {
    var width: Double
    var height: Double
    /// The viewBox: origin and size in user units.
    var viewBox: (x: Double, y: Double, width: Double, height: Double)
    var shapes: [Shape]
    private var masks = 0

    typealias RGB = (red: Double, green: Double, blue: Double)

    struct Shape {
        /// Closed polygons in user units, after the shape's transforms.
        var polygons: [[Point]]
        var paint: Paint
        var opacity: Double
        var evenOdd: Bool
        /// Clip paths the shape is drawn inside, each polygons in user units and its rule.
        var clips: [(polygons: [[Point]], evenOdd: Bool)]
        /// Masks the shape is drawn through.
        var masks: [Mask] = []
    }

    /// A `<mask>`: its content's shapes and its region, in user units. CoreSVG masks by
    /// luminance whatever the `mask-type` (`svg-masks-strokes` mask-alpha cases).
    struct Mask {
        /// The mask's number in the image, shared by the shapes of a masked group.
        var number: Int
        var shapes: [Shape]
        var region: [[Point]]
    }

    enum Paint {
        case color(RGB)
        case gradient(Gradient)
    }

    /// A gradient in its own coordinates, `toGradient` mapping user units to them.
    struct Gradient {
        var radial: Bool
        /// x1, y1, x2, y2 for a linear gradient; cx, cy, r for a radial one.
        var geometry: [Double]
        var stops: [(offset: Double, color: RGB, opacity: Double)]
        var toGradient: Transform

        /// The color and opacity at a point in user units (spread `pad`).
        func at(_ point: Point) -> (RGB, Double) {
            let p = toGradient.apply(point)
            var t: Double
            if radial {
                t = hypot(p.x - geometry[0], p.y - geometry[1]) / max(geometry[2], 1e-9)
            } else {
                let dx = geometry[2] - geometry[0], dy = geometry[3] - geometry[1]
                let length = dx * dx + dy * dy
                t = length == 0 ? 0 : ((p.x - geometry[0]) * dx + (p.y - geometry[1]) * dy) / length
            }
            t = min(max(t, 0), 1)
            guard let first = stops.first else { return ((0, 0, 0), 0) }
            if t <= first.offset { return (first.color, first.opacity) }
            for (low, high) in zip(stops, stops.dropFirst()) where t <= high.offset {
                let f = high.offset > low.offset ? (t - low.offset) / (high.offset - low.offset) : 1
                return ((low.color.red + (high.color.red - low.color.red) * f, low.color.green + (high.color.green - low.color.green) * f,
                         low.color.blue + (high.color.blue - low.color.blue) * f), low.opacity + (high.opacity - low.opacity) * f)
            }
            return (stops.last!.color, stops.last!.opacity)
        }
    }

    struct Point {
        var x: Double
        var y: Double
    }

    struct Transform {
        var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

        func apply(_ p: Point) -> Point { Point(x: a * p.x + c * p.y + e, y: b * p.x + d * p.y + f) }

        func then(_ t: Transform) -> Transform {
            Transform(a: a * t.a + c * t.b, b: b * t.a + d * t.b, c: a * t.c + c * t.d, d: b * t.c + d * t.d,
                      e: a * t.e + c * t.f + e, f: b * t.e + d * t.f + f)
        }

        var inverted: Transform {
            let determinant = a * d - b * c
            guard determinant != 0 else { return Transform() }
            return Transform(a: d / determinant, b: -b / determinant, c: -c / determinant, d: a / determinant,
                             e: (c * f - d * e) / determinant, f: (b * e - a * f) / determinant)
        }
    }

    /// Elements with an `id`, for gradients and clip paths.
    private var definitions: [String: XMLDocumentNode] = [:]
    /// Style sheet rules: a selector (`.class`, `#id` or an element name) and its declarations.
    private var rules: [(selector: String, declarations: [String: String])] = []
    /// Untagged colors are Display P3 values (`color-space-for-untagged-svg-colors`).
    private let untaggedDisplayP3: Bool

    init(data: Data, path: String, untaggedColorsInDisplayP3: Bool = false) throws {
        let document = try XMLDocumentNode.parse(data, path: path)
        guard document.name == "svg" else { throw NomacError("the file is not an SVG image", path: path) }
        untaggedDisplayP3 = untaggedColorsInDisplayP3
        func unsupported(_ what: String) -> NomacError {
            NomacError("SVG images with \(what) are not supported yet (BACKLOG B-210)", path: path)
        }
        func length(_ name: String) throws -> Double? {
            guard var text = document.attributes[name]?.trimmingCharacters(in: .whitespaces) else { return nil }
            for unit in ["px", "pt"] where text.hasSuffix(unit) { text.removeLast(2) }
            guard let value = Double(text) else { throw unsupported("\(name) '\(document.attributes[name]!)'") }
            return value
        }
        let box = try document.attributes["viewBox"].map { text -> [Double] in
            let values = text.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            guard values.count == 4 else { throw unsupported("viewBox '\(text)'") }
            return values
        }
        guard let width = try length("width") ?? box?[2], let height = try length("height") ?? box?[3] else {
            throw unsupported("neither a size nor a viewBox")
        }
        self.width = width
        self.height = height
        viewBox = box.map { ($0[0], $0[1], $0[2], $0[3]) } ?? (0, 0, width, height)
        shapes = []
        func index(_ node: XMLDocumentNode) throws {
            if let id = node.attributes["id"] { definitions[id] = node }
            if node.name == "style" { rules += try Self.styleSheet(node.text, unsupported: unsupported) }
            try node.children.forEach(index)
        }
        try index(document)
        var rootStyle = Style()
        if let fill = document.attributes["fill"] { rootStyle.fill = fill }
        try collect(document.children, style: rootStyle, transform: Transform(), clips: [], unsupported: unsupported)
    }

    /// The inherited presentation attributes nomac reads.
    struct Style {
        var fill: String = "black"
        var fillOpacity = 1.0
        var opacity = 1.0
        var evenOdd = false
        var stroke = "none"
        var color = "black"
        var strokeOpacity = 1.0
        var strokeWidth = 1.0
        var lineCap = "butt"
        var lineJoin = "miter"
        var miterLimit = 4.0
    }

    static let ignored: Set<String> = ["title", "desc", "metadata", "defs", "linearGradient", "radialGradient", "clipPath", "mask", "stop", "sodipodi:namedview", "style"]
    static let editorPrefixes = ["inkscape:", "sodipodi:", "xmlns:"]

    /// An element's presentation attributes, then the style sheet's declarations for it, then its
    /// `style` attribute, each overriding the ones before.
    func attributes(of node: XMLDocumentNode) -> [String: String] {
        var attributes = node.attributes
        let inline = attributes.removeValue(forKey: "style")
        let classes = Set((node.attributes["class"] ?? "").split(separator: " ").map(String.init))
        for rule in rules where rule.selector == node.name || rule.selector == "#" + (node.attributes["id"] ?? "\u{0}")
            || rule.selector.hasPrefix(".") && classes.contains(String(rule.selector.dropFirst())) {
            attributes.merge(rule.declarations) { $1 }
        }
        if let inline { attributes.merge(Self.declarations(inline)) { $1 } }
        return attributes
    }

    static func declarations(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for declaration in text.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if pair.count == 2 { result[pair[0]] = pair[1] }
        }
        return result
    }

    /// A style sheet of rules with simple selectors (`.class`, `#id`, an element name, several
    /// separated by commas).
    static func styleSheet(_ text: String, unsupported: (String) -> NomacError) throws -> [(selector: String, declarations: [String: String])] {
        var rules: [(selector: String, declarations: [String: String])] = []
        for block in text.replacingOccurrences(of: "/\\*.*?\\*/", with: "", options: .regularExpression).split(separator: "}") {
            let parts = block.split(separator: "{", maxSplits: 1)
            guard parts.count == 2 else {
                if !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw unsupported("the style sheet '\(block.prefix(40))'") }
                continue
            }
            let declarations = Self.declarations(String(parts[1]))
            for selector in parts[0].split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                // SF Symbols templates name classes with a colon (`multicolor-0:tintColor`).
                guard selector.wholeMatch(of: /[.#]?[A-Za-z_][\w:-]*/) != nil else { throw unsupported("the style selector '\(selector)'") }
                rules.append((selector, declarations))
            }
        }
        return rules
    }

    private mutating func collect(_ nodes: [XMLDocumentNode], style parent: Style, transform parentTransform: Transform,
                                  clips parentClips: [(polygons: [[Point]], evenOdd: Bool)], unsupported: (String) -> NomacError) throws {
        for node in nodes {
            if Self.ignored.contains(node.name) { continue }
            let attributes = self.attributes(of: node)
            var style = parent
            if let value = attributes["color"], value != "inherit", color(value) != nil { style.color = value }
            if let fill = attributes["fill"], fill != "inherit", readablePaint(fill) { style.fill = fill }
            if let value = attributes["fill-opacity"] { style.fillOpacity = Double(value) ?? 1 }
            if let value = attributes["opacity"] { style.opacity *= Double(value) ?? 1 }
            if let rule = attributes["fill-rule"] { style.evenOdd = rule == "evenodd" }
            if let stroke = attributes["stroke"], stroke != "inherit", readablePaint(stroke) { style.stroke = stroke }
            if let value = attributes["stroke-opacity"] { style.strokeOpacity = Double(value) ?? 1 }
            if let value = attributes["stroke-width"] { style.strokeWidth = Double(value.replacingOccurrences(of: "px", with: "")) ?? 1 }
            if let value = attributes["stroke-linecap"] { style.lineCap = value }
            if let value = attributes["stroke-linejoin"] { style.lineJoin = value }
            if let value = attributes["stroke-miterlimit"] { style.miterLimit = Double(value) ?? 4 }
            if let dashes = attributes["stroke-dasharray"], dashes != "none" { throw unsupported("dashed strokes") }
            let transform = try attributes["transform"].map { parentTransform.then(try Self.transform($0, unsupported: unsupported)) } ?? parentTransform
            let handled: Set<String> = ["fill", "fill-opacity", "opacity", "fill-rule", "stroke", "transform", "id", "class", "xmlns",
                                        "d", "x", "y", "width", "height", "rx", "ry", "cx", "cy", "r", "points", "stroke-width",
                                        "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "clip-rule", "version", "xmlns:xlink",
                                        "clip-path", "color-interpolation", "role", "aria-labelledby", "aria-hidden", "stroke-opacity",
                                        "stroke-dasharray", "stroke-dashoffset", "mask", "x1", "y1", "x2", "y2", "color"]
            // Editors' own attributes (`inkscape:`, `sodipodi:`) and vendor-prefixed style
            // properties (`-sfsymbols-motion-group`) change nothing drawn.
            if let other = attributes.keys.sorted().first(where: {
                !handled.contains($0) && !$0.hasPrefix("data-") && !$0.hasPrefix("-") && !Self.editorPrefixes.contains(where: $0.hasPrefix)
            }) {
                throw unsupported("the attribute '\(other)'")
            }
            var clips = parentClips
            if let reference = attributes["clip-path"], reference != "none" {
                clips.append(try clip(reference, transform: transform, unsupported: unsupported))
            }
            let first = shapes.count
            if node.name == "g" {
                try collect(node.children, style: style, transform: transform, clips: clips, unsupported: unsupported)
            } else {
                let subpaths = try Self.subpaths(node, attributes: attributes, unsupported: unsupported)
                let local = subpaths.filter { $0.points.count > 2 }.map(\.points)
                if style.fill != "none" {
                    let (fill, alpha) = try paint(style.fill, style: style, outline: local, transform: transform, unsupported: unsupported)
                    shapes.append(Shape(polygons: local.map { $0.map(transform.apply) }, paint: fill, opacity: style.opacity * style.fillOpacity * alpha,
                                        evenOdd: style.evenOdd, clips: clips))
                }
                if style.stroke != "none", style.strokeWidth > 0 {
                    let outline = SVGStroke.outline(subpaths, width: style.strokeWidth, cap: style.lineCap, join: style.lineJoin, miterLimit: style.miterLimit)
                    let (stroke, alpha) = try paint(style.stroke, style: style, outline: local, transform: transform, unsupported: unsupported)
                    shapes.append(Shape(polygons: outline.map { $0.map(transform.apply) }, paint: stroke, opacity: style.opacity * style.strokeOpacity * alpha,
                                        evenOdd: false, clips: clips))
                }
            }
            if let reference = attributes["mask"], reference != "none", shapes.count > first {
                let mask = try self.mask(reference, transform: transform, over: shapes[first...].flatMap(\.polygons), unsupported: unsupported)
                for index in first..<shapes.count { shapes[index].masks.append(mask) }
            }
        }
    }

    /// A paint and its color's alpha; `currentColor` is the inherited `color`.
    private func paint(_ text: String, style: Style, outline: [[Point]], transform: Transform, unsupported: (String) -> NomacError) throws -> (Paint, Double) {
        if text.hasPrefix("url(") { return (.gradient(try gradient(text, outline: outline, transform: transform, unsupported: unsupported)), 1) }
        guard let color = color(text.lowercased() == "currentcolor" ? style.color : text) else { throw unsupported("the paint '\(text)'") }
        return (.color(color.rgb), color.alpha)
    }

    /// A `<mask>` over shapes whose polygons (user units) give the bounding box: its region
    /// (`maskUnits`, by default the box grown by 10% on each side) and its content
    /// (`maskContentUnits`, by default in the masked element's user space).
    private mutating func mask(_ reference: String, transform: Transform, over polygons: [[Point]], unsupported: (String) -> NomacError) throws -> Mask {
        guard let id = Self.identifier(reference), let node = definitions[id], node.name == "mask" else { throw unsupported("the mask '\(reference)'") }
        let attributes = self.attributes(of: node)
        let points = polygons.flatMap { $0 }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0, minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        func value(_ name: String, _ fallback: String) throws -> Double {
            let text = attributes[name] ?? fallback
            guard let number = Double(text.hasSuffix("%") ? String(text.dropLast()) : text) else { throw unsupported("the mask \(name) '\(text)'") }
            return text.hasSuffix("%") ? number / 100 : number
        }
        let x = try value("x", "-10%"), y = try value("y", "-10%"), width = try value("width", "120%"), height = try value("height", "120%")
        let region: [Point]
        switch attributes["maskUnits"] ?? "objectBoundingBox" {
        case "objectBoundingBox":
            let bx = minX + x * (maxX - minX), by = minY + y * (maxY - minY), bw = width * (maxX - minX), bh = height * (maxY - minY)
            region = [Point(x: bx, y: by), Point(x: bx + bw, y: by), Point(x: bx + bw, y: by + bh), Point(x: bx, y: by + bh)]
        case "userSpaceOnUse":
            region = [Point(x: x, y: y), Point(x: x + width, y: y), Point(x: x + width, y: y + height), Point(x: x, y: y + height)].map(transform.apply)
        default: throw unsupported("the mask units '\(attributes["maskUnits"]!)'")
        }
        let content: Transform
        switch attributes["maskContentUnits"] ?? "userSpaceOnUse" {
        case "userSpaceOnUse": content = transform
        case "objectBoundingBox": content = Transform(a: maxX - minX, d: maxY - minY, e: minX, f: minY)
        default: throw unsupported("the mask content units '\(attributes["maskContentUnits"]!)'")
        }
        let saved = shapes
        shapes = []
        try collect(node.children, style: Style(), transform: content, clips: [], unsupported: unsupported)
        masks += 1
        let mask = Mask(number: masks, shapes: shapes, region: [region])
        shapes = saved
        return mask
    }

    /// An element's outline in its own coordinates.
    static func outline(_ node: XMLDocumentNode, attributes: [String: String], unsupported: (String) -> NomacError) throws -> [[Point]] {
        try subpaths(node, attributes: attributes, unsupported: unsupported).filter { $0.points.count > 2 }.map(\.points)
    }

    /// An element's subpaths in its own coordinates, and whether each is closed.
    static func subpaths(_ node: XMLDocumentNode, attributes: [String: String], unsupported: (String) -> NomacError) throws -> [(points: [Point], closed: Bool)] {
        let number = { (name: String) -> Double in Double(attributes[name] ?? "0") ?? 0 }
        switch node.name {
        case "path": return try SVGPath.subpaths(attributes["d"] ?? "", unsupported: unsupported)
        case "line": return [([Point(x: number("x1"), y: number("y1")), Point(x: number("x2"), y: number("y2"))], false)]
        default: return try closedOutline(node, attributes: attributes, number: number, unsupported: unsupported).map { ($0, node.name != "polyline") }
        }
    }

    private static func closedOutline(_ node: XMLDocumentNode, attributes: [String: String], number: (String) -> Double, unsupported: (String) -> NomacError) throws -> [[Point]] {
        switch node.name {
        case "rect":
            let x = number("x"), y = number("y"), w = number("width"), h = number("height")
            let rx = min(attributes["rx"].flatMap(Double.init) ?? attributes["ry"].flatMap(Double.init) ?? 0, w / 2)
            let ry = min(attributes["ry"].flatMap(Double.init) ?? rx, h / 2)
            return rx > 0 && ry > 0 ? [SVGPath.roundedRect(x: x, y: y, width: w, height: h, rx: rx, ry: ry)]
                : [[Point(x: x, y: y), Point(x: x + w, y: y), Point(x: x + w, y: y + h), Point(x: x, y: y + h)]]
        case "circle": return [SVGPath.ellipse(cx: number("cx"), cy: number("cy"), rx: number("r"), ry: number("r"))]
        case "ellipse": return [SVGPath.ellipse(cx: number("cx"), cy: number("cy"), rx: number("rx"), ry: number("ry"))]
        case "polygon", "polyline":
            let values = (attributes["points"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).compactMap { Double($0) }
            return [stride(from: 0, to: values.count - 1, by: 2).map { Point(x: values[$0], y: values[$0 + 1]) }]
        default: throw unsupported("<\(node.name)> elements")
        }
    }

    static func identifier(_ reference: String) -> String? {
        guard reference.hasPrefix("url(#"), reference.hasSuffix(")") else { return nil }
        return String(reference.dropFirst(5).dropLast())
    }

    /// A `clipPath`'s shapes in user units (`clipPathUnits` `userSpaceOnUse`).
    private func clip(_ reference: String, transform: Transform, unsupported: (String) -> NomacError) throws -> (polygons: [[Point]], evenOdd: Bool) {
        guard let id = Self.identifier(reference), let node = definitions[id], node.name == "clipPath",
              (node.attributes["clipPathUnits"] ?? "userSpaceOnUse") == "userSpaceOnUse" else {
            throw unsupported("the clip path '\(reference)'")
        }
        let base = try node.attributes["transform"].map { transform.then(try Self.transform($0, unsupported: unsupported)) } ?? transform
        var polygons: [[Point]] = []
        var evenOdd = false
        for child in node.children {
            let attributes = self.attributes(of: child)
            let own = try attributes["transform"].map { base.then(try Self.transform($0, unsupported: unsupported)) } ?? base
            polygons += try Self.outline(child, attributes: attributes, unsupported: unsupported).map { $0.map(own.apply) }
            evenOdd = attributes["clip-rule"] == "evenodd"
        }
        return (polygons, evenOdd)
    }

    /// A gradient fill: its attributes and stops, following `href`s; for `objectBoundingBox`
    /// units, the outline's box in the element's coordinates.
    private func gradient(_ reference: String, outline: [[Point]], transform: Transform, unsupported: (String) -> NomacError) throws -> Gradient {
        guard let id = Self.identifier(reference), var node = definitions[id], ["linearGradient", "radialGradient"].contains(node.name) else {
            throw unsupported("the fill '\(reference)'")
        }
        let radial = node.name == "radialGradient"
        var attributes = node.attributes
        var stops = node.children.filter { $0.name == "stop" }
        var depth = 0
        while let link = node.attributes["href"] ?? node.attributes["xlink:href"], link.hasPrefix("#"), let next = definitions[String(link.dropFirst())], depth < 8 {
            for (key, value) in next.attributes where attributes[key] == nil { attributes[key] = value }
            if stops.isEmpty { stops = next.children.filter { $0.name == "stop" } }
            node = next
            depth += 1
        }
        if attributes["spreadMethod"].map({ $0 != "pad" }) == true { throw unsupported("gradients spread by \(attributes["spreadMethod"]!)") }
        let boundingBox = (attributes["gradientUnits"] ?? "objectBoundingBox") == "objectBoundingBox"
        if !boundingBox, ["x1", "y1", "x2", "y2", "cx", "cy", "r"].contains(where: { attributes[$0]?.hasSuffix("%") == true }) {
            throw unsupported("gradients in user units given in percent")
        }
        func value(_ name: String, _ fallback: Double) -> Double {
            guard let text = attributes[name]?.trimmingCharacters(in: .whitespaces) else { return fallback }
            if text.hasSuffix("%") { return (Double(text.dropLast()) ?? fallback * 100) / 100 }
            return Double(text) ?? fallback
        }
        let geometry = radial ? [value("cx", 0.5), value("cy", 0.5), value("r", 0.5)] : [value("x1", 0), value("y1", 0), value("x2", 1), value("y2", 0)]
        var space = transform
        if boundingBox {
            let points = outline.flatMap { $0 }
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 1
            let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 1
            space = space.then(Transform(a: maxX - minX, d: maxY - minY, e: minX, f: minY))
        }
        if let text = attributes["gradientTransform"] { space = space.then(try Self.transform(text, unsupported: unsupported)) }
        let parsed = try stops.map { stop -> (offset: Double, color: RGB, opacity: Double) in
            let stopAttributes = self.attributes(of: stop)
            let offsetText = stopAttributes["offset"] ?? "0"
            let offset = offsetText.hasSuffix("%") ? (Double(offsetText.dropLast()) ?? 0) / 100 : Double(offsetText) ?? 0
            guard let color = color(stopAttributes["stop-color"] ?? "black") else { throw unsupported("the stop color '\(stopAttributes["stop-color"]!)'") }
            return (min(max(offset, 0), 1), color.rgb, (Double(stopAttributes["stop-opacity"] ?? "1") ?? 1) * color.alpha)
        }
        var ordered: [(offset: Double, color: RGB, opacity: Double)] = []
        for stop in parsed { ordered.append((max(stop.offset, ordered.last?.offset ?? 0), stop.color, stop.opacity)) }
        return Gradient(radial: radial, geometry: geometry, stops: ordered, toGradient: space.inverted)
    }

    /// A color in sRGB: `color(display-p3 r g b)`, or an untagged color, Display P3 when the icon
    /// says so.
    private func color(_ text: String) -> (rgb: RGB, alpha: Double)? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("color(display-p3"), value.hasSuffix(")") {
            let components = value.dropFirst("color(display-p3".count).dropLast().split(separator: " ").compactMap { Double($0) }
            guard components.count >= 3 else { return nil }
            let rgb = ColorConversion.displayP3ToSRGB((components[0], components[1], components[2]))
            return ((rgb.0, rgb.1, rgb.2), 1)
        }
        guard let color = SVGColor.parse(value) else { return nil }
        guard untaggedDisplayP3 else { return ((color.red, color.green, color.blue), color.alpha) }
        let rgb = ColorConversion.displayP3ToSRGB((color.red, color.green, color.blue))
        return ((rgb.0, rgb.1, rgb.2), color.alpha)
    }

    /// A paint value CoreSVG reads; any other is dropped, the inherited value staying
    /// (`svg-colors`: an unreadable fill paints black, an unreadable stroke nothing).
    private func readablePaint(_ value: String) -> Bool {
        ["none", "currentcolor"].contains(value.lowercased()) || value.hasPrefix("url(") || color(value) != nil
    }

    static func transform(_ text: String, unsupported: (String) -> NomacError) throws -> Transform {
        var result = Transform()
        let pattern = /([a-zA-Z]+)\s*\(([^)]*)\)/
        for match in text.matches(of: pattern) {
            let values = match.2.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            var t = Transform()
            switch (match.1, values.count) {
            case ("matrix", 6): t = Transform(a: values[0], b: values[1], c: values[2], d: values[3], e: values[4], f: values[5])
            case ("translate", 1): t.e = values[0]
            case ("translate", 2): t.e = values[0]; t.f = values[1]
            case ("scale", 1): t.a = values[0]; t.d = values[0]
            case ("scale", 2): t.a = values[0]; t.d = values[1]
            case ("skewX", 1): t.c = tan(values[0] * .pi / 180)
            case ("skewY", 1): t.b = tan(values[0] * .pi / 180)
            case ("rotate", 1), ("rotate", 3):
                let angle = values[0] * .pi / 180
                let rotation = Transform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle))
                if values.count == 3 {
                    t = Transform(e: values[1], f: values[2]).then(rotation).then(Transform(e: -values[1], f: -values[2]))
                } else {
                    t = rotation
                }
            default: throw unsupported("the transform '\(match.0)'")
            }
            result = result.then(t)
        }
        return result
    }

    /// The colors the shapes paint: their fills and their gradients' stops.
    var paintColors: [RGB] {
        shapes.flatMap { shape -> [RGB] in
            switch shape.paint {
            case .color(let color): [color]
            case .gradient(let gradient): gradient.stops.map(\.color)
            }
        }
    }
}

/// SVG color values: `#rgb`, `#rrggbb`, `rgb(r, g, b)` and the named colors listed.
enum SVGColor {
    /// CSS's named colors (CSS Color Module Level 4, the extended color keywords).
    static let named: [String: Int] = [
        "aliceblue": 0xf0f8ff, "antiquewhite": 0xfaebd7, "aqua": 0x00ffff, "aquamarine": 0x7fffd4, "azure": 0xf0ffff, "beige": 0xf5f5dc,
        "bisque": 0xffe4c4, "black": 0x000000, "blanchedalmond": 0xffebcd, "blue": 0x0000ff, "blueviolet": 0x8a2be2, "brown": 0xa52a2a,
        "burlywood": 0xdeb887, "cadetblue": 0x5f9ea0, "chartreuse": 0x7fff00, "chocolate": 0xd2691e, "coral": 0xff7f50, "cornflowerblue": 0x6495ed,
        "cornsilk": 0xfff8dc, "crimson": 0xdc143c, "cyan": 0x00ffff, "darkblue": 0x00008b, "darkcyan": 0x008b8b, "darkgoldenrod": 0xb8860b,
        "darkgray": 0xa9a9a9, "darkgreen": 0x006400, "darkgrey": 0xa9a9a9, "darkkhaki": 0xbdb76b, "darkmagenta": 0x8b008b,
        "darkolivegreen": 0x556b2f, "darkorange": 0xff8c00, "darkorchid": 0x9932cc, "darkred": 0x8b0000, "darksalmon": 0xe9967a,
        "darkseagreen": 0x8fbc8f, "darkslateblue": 0x483d8b, "darkslategray": 0x2f4f4f, "darkslategrey": 0x2f4f4f, "darkturquoise": 0x00ced1,
        "darkviolet": 0x9400d3, "deeppink": 0xff1493, "deepskyblue": 0x00bfff, "dimgray": 0x696969, "dimgrey": 0x696969, "dodgerblue": 0x1e90ff,
        "firebrick": 0xb22222, "floralwhite": 0xfffaf0, "forestgreen": 0x228b22, "fuchsia": 0xff00ff, "gainsboro": 0xdcdcdc, "ghostwhite": 0xf8f8ff,
        "gold": 0xffd700, "goldenrod": 0xdaa520, "gray": 0x808080, "green": 0x008000, "greenyellow": 0xadff2f, "grey": 0x808080,
        "honeydew": 0xf0fff0, "hotpink": 0xff69b4, "indianred": 0xcd5c5c, "indigo": 0x4b0082, "ivory": 0xfffff0, "khaki": 0xf0e68c,
        "lavender": 0xe6e6fa, "lavenderblush": 0xfff0f5, "lawngreen": 0x7cfc00, "lemonchiffon": 0xfffacd, "lightblue": 0xadd8e6,
        "lightcoral": 0xf08080, "lightcyan": 0xe0ffff, "lightgoldenrodyellow": 0xfafad2, "lightgray": 0xd3d3d3, "lightgreen": 0x90ee90,
        "lightgrey": 0xd3d3d3, "lightpink": 0xffb6c1, "lightsalmon": 0xffa07a, "lightseagreen": 0x20b2aa, "lightskyblue": 0x87cefa,
        "lightslategray": 0x778899, "lightslategrey": 0x778899, "lightsteelblue": 0xb0c4de, "lightyellow": 0xffffe0, "lime": 0x00ff00,
        "limegreen": 0x32cd32, "linen": 0xfaf0e6, "magenta": 0xff00ff, "maroon": 0x800000, "mediumaquamarine": 0x66cdaa, "mediumblue": 0x0000cd,
        "mediumorchid": 0xba55d3, "mediumpurple": 0x9370db, "mediumseagreen": 0x3cb371, "mediumslateblue": 0x7b68ee, "mediumspringgreen": 0x00fa9a,
        "mediumturquoise": 0x48d1cc, "mediumvioletred": 0xc71585, "midnightblue": 0x191970, "mintcream": 0xf5fffa, "mistyrose": 0xffe4e1,
        "moccasin": 0xffe4b5, "navajowhite": 0xffdead, "navy": 0x000080, "oldlace": 0xfdf5e6, "olive": 0x808000, "olivedrab": 0x6b8e23,
        "orange": 0xffa500, "orangered": 0xff4500, "orchid": 0xda70d6, "palegoldenrod": 0xeee8aa, "palegreen": 0x98fb98, "paleturquoise": 0xafeeee,
        "palevioletred": 0xdb7093, "papayawhip": 0xffefd5, "peachpuff": 0xffdab9, "peru": 0xcd853f, "pink": 0xffc0cb, "plum": 0xdda0dd,
        "powderblue": 0xb0e0e6, "purple": 0x800080, "red": 0xff0000, "rosybrown": 0xbc8f8f, "royalblue": 0x4169e1, "saddlebrown": 0x8b4513,
        "salmon": 0xfa8072, "sandybrown": 0xf4a460, "seagreen": 0x2e8b57, "seashell": 0xfff5ee, "sienna": 0xa0522d, "silver": 0xc0c0c0,
        "skyblue": 0x87ceeb, "slateblue": 0x6a5acd, "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xfffafa, "springgreen": 0x00ff7f,
        "steelblue": 0x4682b4, "tan": 0xd2b48c, "teal": 0x008080, "thistle": 0xd8bfd8, "tomato": 0xff6347, "turquoise": 0x40e0d0, "violet": 0xee82ee,
        "wheat": 0xf5deb3, "white": 0xffffff, "whitesmoke": 0xf5f5f5, "yellow": 0xffff00, "yellowgreen": 0x9acd32,
    ]

    /// A color and its alpha: a name, `transparent`, `#rgb`, `#rrggbb`, `rgb()` or `rgba()`.
    /// CoreSVG reads no other form (`#rrggbbaa` and `#rgba` are not colors, `svg-colors`).
    static func parse(_ text: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value == "transparent" { return (0, 0, 0, 0) }
        if let number = named[value] { return (Double(number >> 16) / 255, Double(number >> 8 & 0xFF) / 255, Double(number & 0xFF) / 255, 1) }
        if value.hasPrefix("#") {
            var hex = Array(value.dropFirst())
            if hex.count == 3 { hex = hex.flatMap { [$0, $0] } }
            guard hex.count == 6, let number = Int(String(hex), radix: 16) else { return nil }
            return (Double(number >> 16) / 255, Double(number >> 8 & 0xFF) / 255, Double(number & 0xFF) / 255, 1)
        }
        for (prefix, count) in [("rgb(", 3), ("rgba(", 4)] where value.hasPrefix(prefix) && value.hasSuffix(")") {
            let parts = value.dropFirst(prefix.count).dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == count else { return nil }
            let components = parts.prefix(3).compactMap { part -> Double? in
                part.hasSuffix("%") ? Double(part.dropLast()).map { $0 / 100 } : Double(part).map { $0 / 255 }
            }
            guard components.count == 3 else { return nil }
            let alpha = count == 4 ? Double(parts[3]) : 1
            return alpha.map { (components[0], components[1], components[2], min(max($0, 0), 1)) }
        }
        return nil
    }
}

/// SVG path data flattened to polygons: lines as they are, curves and arcs in segments short
/// enough at the sizes Icon Composer layers are drawn.
enum SVGPath {
    typealias Point = SVGImage.Point
    static let segments = 32

    /// The subpaths of path data, flattened, with whether each is closed.
    static func subpaths(_ data: String, unsupported: (String) -> NomacError) throws -> [(points: [Point], closed: Bool)] {
        var tokens = Tokenizer(Array(data.utf8))
        var subpaths: [(points: [Point], closed: Bool)] = []
        var current: [Point] = []
        var point = Point(x: 0, y: 0), start = point
        var lastControl: Point?
        var lastCommand: UInt8 = 0
        var command: UInt8 = 0
        func finish(closed: Bool = false) {
            if current.count > 1 { subpaths.append((current, closed)) }
            current = []
        }
        while let next = tokens.command(previous: command) {
            command = next
            let relative = command >= 97
            let base = relative ? point : Point(x: 0, y: 0)
            func p(_ x: Double, _ y: Double) -> Point { Point(x: base.x + x, y: base.y + y) }
            switch command | 0x20 {
            case UInt8(ascii: "m"):
                finish()
                let (x, y) = (try tokens.number(), try tokens.number())
                point = p(x, y)
                start = point
                current = [point]
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "l"):
                point = p(try tokens.number(), try tokens.number())
                current.append(point)
            case UInt8(ascii: "h"):
                point = Point(x: (relative ? point.x : 0) + (try tokens.number()), y: point.y)
                current.append(point)
            case UInt8(ascii: "v"):
                point = Point(x: point.x, y: (relative ? point.y : 0) + (try tokens.number()))
                current.append(point)
            case UInt8(ascii: "c"), UInt8(ascii: "s"):
                let first: Point
                if command | 0x20 == UInt8(ascii: "c") {
                    first = p(try tokens.number(), try tokens.number())
                } else if let control = lastControl, [UInt8(ascii: "c"), UInt8(ascii: "s")].contains(lastCommand | 0x20) {
                    first = Point(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
                } else {
                    first = point
                }
                let second = p(try tokens.number(), try tokens.number())
                let end = p(try tokens.number(), try tokens.number())
                current += cubic(point, first, second, end)
                lastControl = second
                point = end
            case UInt8(ascii: "q"), UInt8(ascii: "t"):
                let control: Point
                if command | 0x20 == UInt8(ascii: "q") {
                    control = p(try tokens.number(), try tokens.number())
                } else if let last = lastControl, [UInt8(ascii: "q"), UInt8(ascii: "t")].contains(lastCommand | 0x20) {
                    control = Point(x: 2 * point.x - last.x, y: 2 * point.y - last.y)
                } else {
                    control = point
                }
                let end = p(try tokens.number(), try tokens.number())
                let first = Point(x: point.x + 2 * (control.x - point.x) / 3, y: point.y + 2 * (control.y - point.y) / 3)
                let second = Point(x: end.x + 2 * (control.x - end.x) / 3, y: end.y + 2 * (control.y - end.y) / 3)
                current += cubic(point, first, second, end)
                lastControl = control
                point = end
            case UInt8(ascii: "a"):
                let rx = abs(try tokens.number()), ry = abs(try tokens.number()), rotation = try tokens.number()
                let large = try tokens.flag(), sweep = try tokens.flag()
                let end = p(try tokens.number(), try tokens.number())
                current += arc(from: point, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                point = end
            case UInt8(ascii: "z"):
                point = start
                finish(closed: true)
                current = [point]
            default:
                throw unsupported("the path command '\(Character(UnicodeScalar(command)))'")
            }
            if ![UInt8(ascii: "c"), UInt8(ascii: "s"), UInt8(ascii: "q"), UInt8(ascii: "t")].contains(command | 0x20) { lastControl = nil }
            lastCommand = command
        }
        guard tokens.atEnd else { throw unsupported("path data '\(data.prefix(40))'") }
        finish()
        return subpaths
    }

    static func cubic(_ p0: Point, _ p1: Point, _ p2: Point, _ p3: Point) -> [Point] {
        (1...segments).map { step in
            let t = Double(step) / Double(segments), u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return Point(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }
    }

    /// An elliptical arc by the endpoint parameterization of the SVG specification (appendix B.2.4).
    static func arc(from p0: Point, to p1: Point, rx: Double, ry: Double, rotation: Double, large: Bool, sweep: Bool) -> [Point] {
        guard rx > 0, ry > 0, p0.x != p1.x || p0.y != p1.y else { return [p1] }
        let phi = rotation * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        var rx = rx, ry = ry
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = sqrt(max(0, numerator / denominator))
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2, cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double { atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi } else if sweep && delta < 0 { delta += 2 * .pi }
        let count = max(4, Int((abs(delta) / (.pi / 2)).rounded(.up)) * segments / 4)
        return (1...count).map { step in
            let theta = theta1 + delta * Double(step) / Double(count)
            let x = rx * cos(theta), y = ry * sin(theta)
            return Point(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }
    }

    static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> [Point] {
        let count = 4 * segments
        return (0..<count).map { step in
            let theta = 2 * .pi * Double(step) / Double(count)
            return Point(x: cx + rx * cos(theta), y: cy + ry * sin(theta))
        }
    }

    static func roundedRect(x: Double, y: Double, width: Double, height: Double, rx: Double, ry: Double) -> [Point] {
        var points: [Point] = []
        let corners = [(x + width - rx, y + ry, -Double.pi / 2), (x + width - rx, y + height - ry, 0.0),
                       (x + rx, y + height - ry, Double.pi / 2), (x + rx, y + ry, Double.pi)]
        for (cx, cy, start) in corners {
            for step in 0...segments {
                let theta = start + Double.pi / 2 * Double(step) / Double(segments)
                points.append(Point(x: cx + rx * cos(theta), y: cy + ry * sin(theta)))
            }
        }
        return points
    }

    /// Path data's commands and numbers.
    struct Tokenizer {
        let bytes: [UInt8]
        var index = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipSeparators() {
            while index < bytes.count, [UInt8(ascii: " "), UInt8(ascii: ","), 9, 10, 13].contains(bytes[index]) { index += 1 }
        }

        var atEnd: Bool {
            mutating get { skipSeparators(); return index == bytes.count }
        }

        /// The next command letter, or the previous command repeated when numbers follow.
        mutating func command(previous: UInt8) -> UInt8? {
            skipSeparators()
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            if (byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "z") && byte | 0x20 != UInt8(ascii: "e") {
                index += 1
                return byte
            }
            return previous == 0 || previous | 0x20 == UInt8(ascii: "z") ? nil : previous
        }

        mutating func number() throws -> Double {
            skipSeparators()
            let start = index
            if index < bytes.count, [UInt8(ascii: "-"), UInt8(ascii: "+")].contains(bytes[index]) { index += 1 }
            var seenDot = false, seenExponent = false
            while index < bytes.count {
                let byte = bytes[index]
                if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
                    index += 1
                } else if byte == UInt8(ascii: ".") && !seenDot && !seenExponent {
                    seenDot = true
                    index += 1
                } else if (byte | 0x20) == UInt8(ascii: "e") && !seenExponent {
                    seenExponent = true
                    index += 1
                    if index < bytes.count, [UInt8(ascii: "-"), UInt8(ascii: "+")].contains(bytes[index]) { index += 1 }
                } else {
                    break
                }
            }
            guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                throw NomacError("malformed SVG path data near '\(String(decoding: bytes[start..<min(bytes.count, start + 20)], as: UTF8.self))'")
            }
            return value
        }

        mutating func flag() throws -> Bool {
            skipSeparators()
            guard index < bytes.count, [UInt8(ascii: "0"), UInt8(ascii: "1")].contains(bytes[index]) else {
                throw NomacError("malformed SVG arc flag")
            }
            index += 1
            return bytes[index - 1] == UInt8(ascii: "1")
        }
    }
}

/// An XML element tree read with `XMLParser`.
final class XMLDocumentNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLDocumentNode] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    static func parse(_ data: Data, path: String) throws -> XMLDocumentNode {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw NomacError("the file is not well-formed XML", path: path) }
        return root
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var root: XMLDocumentNode?
        var stack: [XMLDocumentNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let node = XMLDocumentNode(name: elementName, attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
        }
    }
}
