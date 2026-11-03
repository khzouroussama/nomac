import Foundation
import NomacCore

/// Symbol sets (`.symbolset`: an SF Symbols template SVG) compiled as actool compiles them
/// (docs/formats/asset-catalog.md, "Symbol sets"; swiftfin's four and the self-written templates
/// of `assets-experiments symbols-sets`): one vector glyph rendition per glyph of the template
/// (part 59, layout 1017), the glyph re-written as an SVG of its own in points with its metrics,
/// and the regular medium glyph drawn at 15, 17 and 20 points at 1x, 2x and 3x by nomac's renderer
/// (ADR 0204). The facet and every key have target 5.
enum SymbolSet {
    static let weights = ["Ultralight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"]
    static let sizes = ["S", "M", "L"]
    static let target: UInt16 = 5
    static let capRatio = 1443.0 / 2048
    static let sizeFactor: [String: Double] = ["S": 1, "M": 1.276, "L": 1.647]
    static let marginUnit = 140.0 * 17 / 2048
    static let rasterPointSizes: [(dimension2: UInt16, points: Double)] = [(0, 15), (1, 17), (2, 20)]
    /// A glyph's sidebearing as a combination of the Ultralight-S, Regular-S and Black-S ones, by
    /// weight (`symbols-sets` interpolation cases).
    static let weightCoefficients: [String: [Double]] = [
        "Ultralight": [1, 0, 0], "Thin": [24.0 / 31, 7.0 / 31, 0], "Light": [1.0 / 3, 2.0 / 3, 0], "Regular": [0, 1, 0],
        "Medium": [0, 0.82, 0.18], "Semibold": [0, 0.682, 0.318], "Bold": [0, 0.5, 0.5],
        "Heavy": [0, 0.236021070, 0.763978958], "Black": [0, 0, 1],
    ]
    /// The Ultralight, Regular and Black glyphs of a size as combinations of the S masters.
    static let sizeColumns: [String: [[Double]]] = [
        "S": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
        "M": [[1.068014376, -0.068014376, 0], [0.182093700, 0.817906300, 0], [-0.004885181, 0.088479759, 0.916405421]],
        "L": [[1.135346599, -0.135346599, 0], [0.369791292, 0.630208708, 0], [0.015996395, 0.257733643, 0.726269962]],
    ]
    static let masters = ["Ultralight-S", "Regular-S", "Black-S"]

    struct Template {
        var version: Int
        var glyphs: [(name: String, transform: SVGImage.Transform, elements: [XMLDocumentNode])]
        var style: String
        var guides: [String: Double]
        var margins: [String: Double]
        var marginWidths: [String: Double]

        func glyph(_ name: String) -> (name: String, transform: SVGImage.Transform, elements: [XMLDocumentNode])? { glyphs.first { $0.name == name } }
    }

    struct Compiled {
        var renditions: [CARRendition]
        var sources: [ImageSet.Source]
    }

    static func unsupported(_ what: String, path: String) -> NomacError {
        NomacError("symbol sets with \(what) are not supported yet (BACKLOG B-202)", path: path)
    }

    /// watchOS glyphs are 0.94634 times iOS's in every metric (16.088 points for iOS's 17) and
    /// keep one raster, 17 points at 2x (`watchos` experiment, home-assistant's watch app).
    static let watchFactor = 0.94634

    static func compile(_ asset: AssetCatalog.Asset, watch: Bool = false) throws -> Compiled {
        let pointSizes: [(dimension2: UInt16, points: Double)] = watch ? [(0, 17)] : rasterPointSizes
        let rasters = (watch ? [2] : [1, 2, 3]).flatMap { scale in pointSizes.map { (scale: scale, dimension2: $0.dimension2, points: $0.points) } }
        let factor = watch ? watchFactor : 1
        let properties = asset.contents["properties"] as? [String: Any] ?? [:]
        let symbols = asset.contents["symbols"] as? [[String: Any]] ?? []
        guard Set(asset.contents.keys).isSubset(of: ["info", "symbols", "properties"]), Set(properties.keys).isSubset(of: ["symbol-rendering-intent"]),
              symbols.count == 1, let filename = symbols[0]["filename"] as? String, Set(symbols[0].keys).isSubset(of: ["filename", "idiom"]),
              (symbols[0]["idiom"] as? String ?? "universal") == "universal" else {
            throw unsupported("other than one universal template", path: asset.path)
        }
        let path = asset.path + "/" + filename
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("could not read the symbol template", path: path) }
        let template = try parse(data, path: path)
        // Property 1019's second word: the set's rendering intent, other values 0 (experiment `symbol-sets`).
        let intent: UInt32 = ["template": 1, "multicolor": 2, "hierarchical": 3][properties["symbol-rendering-intent"] as? String ?? ""] ?? 0
        let points = try pointScale(template, path: path) * factor
        let reference = template.glyph("Regular-M") != nil ? "Regular-M" : "Regular-S"
        var renditions: [CARRendition] = []
        for glyph in template.glyphs {
            let parts = glyph.name.split(separator: "-").map(String.init)
            guard parts.count == 2, let weight = weights.firstIndex(of: parts[0]), let size = sizes.firstIndex(of: parts[1]) else {
                throw unsupported("the glyph '\(glyph.name)'", path: path)
            }
            let svg = try glyphSVG(template, glyph.name, points, path: path)
            var properties: [(type: UInt32, value: [UInt8])] = ImageSet.commonProperties
            properties.append((1018, try metrics(template, glyph.name, points, reference: reference, pointSizes: pointSizes, unitFactor: factor, path: path)))
            properties.append((1019, ImageSet.little(1) + ImageSet.little(intent) + ImageSet.little(modes(template))))
            let csi = CSI(name: filename, layout: .symbolGlyph, flags: 4, scale: 100, pixelFormat: "SVG ", properties: properties,
                          payload: ImageSet.vectorPayload(Array(svg.utf8)))
            renditions.append(CARRendition(name: asset.name, kind: .symbol, attributes: [
                .scale: 1, .glyphWeight: UInt16(weight + 1), .glyphSize: UInt16(size + 1), .target: target, .part: 59,
            ], csi: csi.bytes))
        }
        var sources: [ImageSet.Source] = []
        let box = try referenceBox(template, points, path: path)
        // The rasters are monochrome: every layer opaque in the default black, strokes left out,
        // the drawing keeping only geometry attributes.
        let glyph = try glyphSVG(template, template.glyph("Regular-M") != nil ? "Regular-M" : "Regular-S", points, path: path)
            .replacing(/<defs>.*?<\/defs>/, with: "").replacing(/\s(?!(?:d|fill-rule|clip-rule|transform|viewBox|version)=)[^\s=]+="[^"]*"/, with: "")
        let rasterSVG = try SVGImage(data: Data(glyph.utf8), path: path)
        for (scale, dimension2, size) in rasters {
            let factor = size / 17 * Double(scale)
            let width = Int((box.width * factor).rounded(.up)), height = Int((box.height * factor).rounded(.up))
            let pixels = IconRenderer.bgra(try IconRenderer.draw(.svg(rasterSVG, data: []), width: width, height: height))
            var source = ImageSet.Source(name: asset.name, filename: filename, path: path, image: PNGImage(width: width, height: height, pixels: pixels), scale: scale)
            source.kind = .symbol
            source.isOpaque = false
            source.glyph = (weight: 4, size: 2, target: target)
            source.dimension2 = dimension2
            sources.append(source)
        }
        return Compiled(renditions: renditions, sources: sources)
    }

    /// The template: its version, glyphs (`Symbols` group members with their translation), style
    /// sheet, baseline and capline guides and margin guides, positions in the template's space.
    static func parse(_ data: Data, path: String) throws -> Template {
        let root = try XMLDocumentNode.parse(data, path: path)
        var template = Template(version: 0, glyphs: [], style: "", guides: [:], margins: [:], marginWidths: [:])
        // Guides and glyphs are placed by their groups' translations (`nil` below other transforms).
        func visit(_ node: XMLDocumentNode, stroked: Bool, strokeWidth: Double, offset: (x: Double, y: Double)?) throws {
            let stroked = styleValue(node, "stroke").map { $0 != "none" } ?? stroked
            let strokeWidth = styleValue(node, "stroke-width").flatMap(Double.init) ?? strokeWidth
            var offset = offset
            if node.name == "g", let transform = node.attributes["transform"] {
                offset = translation(transform).flatMap { translation in offset.map { ($0.x + translation.x, $0.y + translation.y) } }
            }
            func placed() throws -> (x: Double, y: Double) {
                guard let offset else { throw unsupported("guides or glyphs in a transformed group", path: path) }
                return offset
            }
            // The version is a text element's own text: template 1's, in a `tspan`, reads as 0.
            if node.name == "text", let match = node.text.firstMatch(of: /Template v\.(\d+)/) { template.version = Int(match.1) ?? 0 }
            if var id = node.attributes["id"] {
                if ["left-margin", "right-margin"].contains(id) { id += "-Regular-M" }
                if let start = guideStart(node, stroke: stroked ? strokeWidth : 0) {
                    if id.hasPrefix("Baseline-") || id.hasPrefix("Capline-") { template.guides[id] = try placed().y + start.y }
                    if id.hasPrefix("left-margin-") || id.hasPrefix("right-margin-") { template.margins[id] = try placed().x + start.x }
                }
                if id.hasPrefix("left-margin-") || id.hasPrefix("right-margin-"), let width = guideWidth(node, strokeWidth: strokeWidth) {
                    template.marginWidths[id] = width
                }
            }
            if node.name == "style" { template.style += node.text }
            if node.attributes["id"] == "LayerTree" { throw unsupported("a layer tree", path: path) }
            if node.name == "g", node.attributes["id"] == "Symbols" {
                for glyph in node.children where glyph.name == "g" {
                    guard let id = glyph.attributes["id"] else { throw unsupported("a glyph without an id", path: path) }
                    let elements = glyph.children.filter { ["path", "g"].contains($0.name) }
                    for transform in ([glyph] + elements.flatMap(groups)).compactMap({ $0.attributes["transform"] }) {
                        _ = try SVGImage.transform(transform) { unsupported("the glyph transform \($0)", path: path) }
                    }
                    let offset = try placed()
                    let own = try glyph.attributes["transform"].map { try SVGImage.transform($0) { NomacError($0) } } ?? .init()
                    template.glyphs.append((id, SVGImage.Transform(e: offset.x, f: offset.y).then(own), elements))
                }
                return
            }
            try node.children.forEach { try visit($0, stroked: stroked, strokeWidth: strokeWidth, offset: offset) }
        }
        try visit(root, stroked: false, strokeWidth: 1, offset: (0, 0))
        return template
    }

    static func translation(_ transform: String) -> (x: Double, y: Double)? {
        let match = transform.firstMatch(of: /^\s*matrix\(1 0 0 1 ([^ ]+) ([^ )]+)\)\s*$/).map { ($0.1, $0.2) }
            ?? transform.firstMatch(of: /^\s*translate\(([^, ]+)[, ]+([^ )]+)\)\s*$/).map { ($0.1, $0.2) }
        guard let match, let x = Double(match.0), let y = Double(match.1) else { return nil }
        return (x, y)
    }

    /// A style property: the `style` attribute's, else the class rules', else the attribute.
    static func styleValue(_ node: XMLDocumentNode, _ name: String, rules: [(name: String, body: String)] = []) -> String? {
        func value(_ body: String) -> String? {
            body.split(separator: ";").map { $0.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) } }.last { $0.count == 2 && $0[0] == name }?[1]
        }
        let classes = (node.attributes["class"] ?? "").split(separator: " ").map(String.init)
        return value(node.attributes["style"] ?? "") ?? rules.filter { classes.contains($0.name) }.compactMap { value($0.body) }.last ?? node.attributes[name]
    }

    /// A guide's position: a `line`'s first point, or for a `path` (template 3 as other editors
    /// write it, mastodon's Phosphor symbols) its `M` with x moved to its outline's left edge, half
    /// the inherited stroke width before when stroked; y stays (experiment `symbol-sets`).
    static func guideStart(_ node: XMLDocumentNode, stroke: Double) -> (x: Double, y: Double)? {
        if node.name == "line", let x = Double(node.attributes["x1"] ?? ""), let y = Double(node.attributes["y1"] ?? "") { return (x, y) }
        guard node.name == "path", let match = (node.attributes["d"] ?? "").firstMatch(of: /^\s*M\s*([-0-9.]+)[\s,]+([-0-9.]+)/),
              let x = Double(match.1), let y = Double(match.2) else { return nil }
        return (x - stroke / 2, y)
    }

    /// A margin guide's width, the sidebearing itself before template 2: a `rect`'s width, a
    /// vertical `line`'s stroke width (experiment `symbol-sets`).
    static func guideWidth(_ node: XMLDocumentNode, strokeWidth: Double) -> Double? {
        switch node.name {
        case "rect": Double(node.attributes["width"] ?? "")
        case "line" where node.attributes["x1"] == node.attributes["x2"]: strokeWidth
        default: nil
        }
    }

    /// Points per template unit: 17 points for the medium size's cap height.
    static func pointScale(_ template: Template, path: String) throws -> Double {
        guard let baseline = template.guides["Baseline-M"], let capline = template.guides["Capline-M"] else { throw unsupported("no medium guides", path: path) }
        return 17 / ((baseline - capline) / capRatio).rounded(.toNearestOrEven)
    }

    static func styleRules(_ style: String) -> [(name: String, body: String)] {
        style.matches(of: /\.([^\s{]+)\s*\{([^}]*)\}/).map { (String($0.1), String($0.2).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// A rule's declarations as the glyph's style sheet writes them: standard properties, then
    /// vendor-prefixed ones, each sorted (corpus signal, mastodon, nextcloud).
    static func declarations(_ body: String) -> String {
        let all = body.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let sorted = all.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        return (sorted.filter { !$0.hasPrefix("-") } + sorted.filter { $0.hasPrefix("-") }).joined(separator: ";")
    }

    static func format(_ value: Double) -> String { String(format: "%g", value) }

    /// CoreSVG's re-writing of path data: the same commands, numbers as `%g`, a space only before
    /// non-negative numbers.
    static func serializePath(_ d: String) -> String {
        var out = ""
        var previousNumber = false
        for token in d.matches(of: /[MmLlHhVvCcSsQqTtZzAa]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/) {
            let text = String(token.0)
            if text.first!.isLetter && text.first != "e" && text.first != "E" {
                out += text
                previousNumber = false
            } else {
                let number = format(Double(text) ?? 0)
                out += (previousNumber && !number.hasPrefix("-") ? " " : "") + number
                previousNumber = true
            }
        }
        return out
    }

    /// A path's on-curve and control points, offset, as a CGPath's bounding box covers them; arcs
    /// as the cubic curves CoreGraphics makes of them.
    static func pathPoints(_ d: String) -> [(x: Double, y: Double)] {
        let tokens = d.matches(of: /[MmLlHhVvCcSsQqTtZzAa]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/).map { String($0.0) }
        let arguments: [Character: Int] = ["M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "Z": 0, "A": 7]
        var points: [(x: Double, y: Double)] = []
        var index = 0
        var command: Character = "M"
        var current = (x: 0.0, y: 0.0), start = current
        var lastCubic: (x: Double, y: Double)?, lastQuadratic: (x: Double, y: Double)?
        while index < tokens.count {
            if let letter = tokens[index].first, letter.isLetter {
                command = letter
                index += 1
                if command == "Z" || command == "z" {
                    current = start
                    lastCubic = nil
                    lastQuadratic = nil
                    continue
                }
            }
            let upper = Character(command.uppercased()), relative = command.isLowercase
            let count = arguments[upper] ?? 0
            guard index + count <= tokens.count else { break }
            let a = tokens[index..<(index + count)].map { Double($0) ?? 0 }
            index += count
            let base = relative ? current : (x: 0.0, y: 0.0)
            var nextCubic: (x: Double, y: Double)?, nextQuadratic: (x: Double, y: Double)?
            switch upper {
            case "H":
                current.x = a[0] + base.x
                points.append(current)
            case "V":
                current.y = a[0] + base.y
                points.append(current)
            case "A":
                let end = (a[5] + base.x, a[6] + base.y)
                points += arcPoints(from: current, rx: a[0], ry: a[1], rotation: a[2], large: a[3] != 0, sweep: a[4] != 0, to: end)
                current = end
            default:
                var xy = stride(from: 0, to: count, by: 2).map { (a[$0] + base.x, a[$0 + 1] + base.y) }
                if upper == "S" { xy.insert(lastCubic.map { (2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current, at: 0) }
                if upper == "T" { xy.insert(lastQuadratic.map { (2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current, at: 0) }
                points += xy
                if upper == "C" || upper == "S" { nextCubic = xy[xy.count - 2] }
                if upper == "Q" || upper == "T" { nextQuadratic = xy[xy.count - 2] }
                current = xy[xy.count - 1]
                if upper == "M" {
                    start = current
                    command = relative ? "l" : "L"
                }
            }
            lastCubic = nextCubic
            lastQuadratic = nextQuadratic
        }
        return points
    }

    static func arcPoints(from p0: (x: Double, y: Double), rx: Double, ry: Double, rotation: Double, large: Bool, sweep: Bool,
                          to p1: (x: Double, y: Double)) -> [(x: Double, y: Double)] {
        guard rx != 0, ry != 0 else { return [p1] }
        var rx = abs(rx), ry = abs(ry)
        let c = cos(rotation * .pi / 180), s = sin(rotation * .pi / 180)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = c * dx + s * dy, y1 = -s * dx + c * dy
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let factor = sqrt(max(0, numerator / denominator)) * (large == sweep ? -1 : 1)
        let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
        let cx = c * cx1 - s * cy1 + (p0.x + p1.x) / 2, cy = s * cx1 + c * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double { atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int((abs(delta) / (.pi / 2) - 1e-9).rounded(.up)))
        var points: [(x: Double, y: Double)] = []
        for index in 0..<segments {
            let a1 = theta + delta * Double(index) / Double(segments), a2 = theta + delta * Double(index + 1) / Double(segments)
            let k = 4.0 / 3 * tan((a2 - a1) / 4)
            let e1 = (rx * cos(a1), ry * sin(a1)), e2 = (rx * cos(a2), ry * sin(a2))
            let d1 = (-rx * sin(a1), ry * cos(a1)), d2 = (-rx * sin(a2), ry * cos(a2))
            for (ex, ey) in [(e1.0 + k * d1.0, e1.1 + k * d1.1), (e2.0 - k * d2.0, e2.1 - k * d2.1), e2] {
                points.append((c * ex - s * ey + cx, s * ex + c * ey + cy))
            }
        }
        return points
    }

    static func boundingBox(_ points: [(x: Double, y: Double)]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        (points.map(\.x).min() ?? 0, points.map(\.x).max() ?? 0, points.map(\.y).min() ?? 0, points.map(\.y).max() ?? 0)
    }

    static func glyphBox(_ template: Template, _ name: String) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let glyph = template.glyph(name)!
        return boundingBox(points(glyph.elements, rules: styleRules(template.style), transform: glyph.transform))
    }

    /// A glyph's groups, nested in paths' place (template 1's arrows).
    static func groups(_ element: XMLDocumentNode) -> [XMLDocumentNode] {
        element.name == "g" ? [element] + element.children.flatMap(groups) : []
    }

    /// The points bounding a glyph's elements; a stroked path's box grows by half the stroke width
    /// (template 1's arrows, corpus netnewswire; template 5's wireframe class, signal).
    static func points(_ elements: [XMLDocumentNode], rules: [(name: String, body: String)] = [], transform: SVGImage.Transform = .init(),
                       stroked: Bool = false, width: Double = 1) -> [(x: Double, y: Double)] {
        elements.flatMap { element -> [(x: Double, y: Double)] in
            let stroked = styleValue(element, "stroke", rules: rules).map { $0 != "none" } ?? stroked
            let width = styleValue(element, "stroke-width", rules: rules).flatMap(Double.init) ?? width
            let stroke = stroked ? width : nil
            switch element.name {
            case "path":
                let points = pathPoints(element.attributes["d"] ?? "").map { point -> (x: Double, y: Double) in
                    let placed = transform.apply(SVGImage.Point(x: point.x, y: point.y))
                    return (placed.x, placed.y)
                }
                guard let stroke else { return points }
                let box = boundingBox(points)
                let determinant: Double = transform.a * transform.d - transform.b * transform.c
                let grow: Double = stroke / 2 * abs(determinant).squareRoot()
                return [(box.minX - grow, box.minY - grow), (box.maxX + grow, box.maxY + grow)]
            case "g":
                let local = element.attributes["transform"].flatMap { try? SVGImage.transform($0) { NomacError($0) } } ?? .init()
                return points(element.children, rules: rules, transform: transform.then(local), stroked: stroked, width: width)
            default: return []
            }
        }
    }

    /// The glyph as its own SVG in points: a viewBox of its bounding box, its paths re-written in a
    /// group scaled by the template's point scale, the style sheet's rules but the preview's.
    static func glyphSVG(_ template: Template, _ name: String, _ scale: Double, path: String) throws -> String {
        guard let glyph = template.glyph(name) else { throw unsupported("no \(name) glyph", path: path) }
        let box = glyphBox(template, name)
        let rules = styleRules(template.style)
        let css = rules.filter { !$0.name.hasPrefix("SFSymbolsPreview") }
            .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg version=\"1.1\" viewBox=\"0 0 \(format((box.maxX - box.minX) * scale)) \(format((box.maxY - box.minY) * scale))\">"
        if !css.isEmpty {
            out += "<defs><style>" + css.map { ".\($0.name){\(declarations($0.body));}" }.joined() + "</style></defs>"
        }
        // The glyph's own transform folds into the group's (icecubes' Inkscape-scaled masters).
        let placed = SVGImage.Transform(a: scale, d: scale, e: -box.minX * scale, f: -box.minY * scale).then(glyph.transform)
        out += "<g id=\"s\" transform=\"matrix(\([placed.a, placed.b, placed.c, placed.d, placed.e, placed.f].map(format).joined(separator: " ")))\">"
        func serialize(_ element: XMLDocumentNode) {
            if element.name == "g" {
                out += "<g" + element.attributes.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { " \($0)=\"\(element.attributes[$0]!)\"" }.joined() + ">"
                element.children.filter { ["path", "g"].contains($0.name) }.forEach(serialize)
                out += "</g>"
                return
            }
            // Style properties become attributes, CSS's precedence (attribute, class rule, `style`),
            // vendor-prefixed ones left out and stroke widths in points (corpus signal, icecubes).
            var attributes = element.attributes.filter { $0.key != "class" }
            attributes["d"] = attributes["d"].map(serializePath)
            let classes = (element.attributes["class"] ?? "").split(separator: " ").map(String.init)
            if element.attributes["class"] != nil { attributes["class"] = classes.filter { !$0.hasPrefix("SFSymbolsPreview") }.joined(separator: " ") }
            for body in rules.filter({ classes.contains($0.name) }).map(\.body) + [element.attributes["style"] ?? ""] {
                for declaration in body.split(separator: ";") {
                    let pair = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard pair.count == 2, !pair[0].hasPrefix("-") else { continue }
                    attributes[pair[0]] = pair[0] == "stroke-width" ? Double(pair[1]).map { format($0 * scale) } ?? pair[1] : pair[1]
                }
            }
            // Namespaced attributes come last, by their local name (`sodipodi:nodetypes`, corpus icecubes).
            let names = attributes.keys.map { (key: $0, namespaced: $0.contains(":"), local: String($0.split(separator: ":").last!)) }
                .sorted { ($0.namespaced ? 1 : 0, $0.local) < ($1.namespaced ? 1 : 0, $1.local) }
            out += "<path" + names.map { " \($0.local)=\"\(attributes[$0.key]!)\"" }.joined() + "/>"
        }
        glyph.elements.forEach(serialize)
        return out + "</g></svg>\n"
    }

    static func ownSidebearings(_ template: Template, _ name: String, _ scale: Double) -> (left: Double, right: Double)? {
        guard template.glyph(name) != nil else { return nil }
        if template.version < 2 {
            guard let left = template.marginWidths["left-margin-\(name)"], let right = template.marginWidths["right-margin-\(name)"] else { return nil }
            return (left * scale, right * scale)
        }
        guard let left = template.margins["left-margin-\(name)"], let right = template.margins["right-margin-\(name)"] else { return nil }
        let box = glyphBox(template, name)
        return ((box.minX - left) * scale, (right - box.maxX) * scale)
    }

    static func coefficients(_ weight: String, _ size: String) -> [Double] {
        let e = weightCoefficients[weight]!, columns = sizeColumns[size]!
        return (0..<3).map { i in (0..<3).reduce(0) { $0 + e[$1] * columns[$1][i] } }
    }

    /// Sidebearings in points and the size factor: the glyph's own guides, else interpolated from
    /// the U/R/B-S ones, else Regular-S's or Regular-M's.
    static func sidebearings(_ template: Template, _ name: String, _ scale: Double, path: String) throws -> (left: Double, right: Double, factor: Double) {
        if let own = ownSidebearings(template, name, scale) { return (own.left, own.right, 1) }
        let masters = self.masters.map { ownSidebearings(template, $0, scale) }
        if masters.allSatisfy({ $0 != nil }) {
            let parts = name.split(separator: "-").map(String.init)
            let k = sizeFactor[parts[1]]!
            let a = coefficients(parts[0], parts[1])
            return (zip(a, masters).reduce(0) { $0 + $1.0 * $1.1!.left } * k, zip(a, masters).reduce(0) { $0 + $1.0 * $1.1!.right } * k, k)
        }
        for fixed in ["Regular-S", "Regular-M"] {
            if let own = ownSidebearings(template, fixed, scale) { return (own.left, own.right, 1) }
        }
        throw unsupported("no margin guides", path: path)
    }

    /// Property 1018: 7 for interpolatable templates (else 3), 17, then floats: the glyph's
    /// bottom below the baseline, the cap height, the template version, the left sidebearing and
    /// its unit, the right one and its unit; and for the reference glyph the raster point sizes.
    static func metrics(_ template: Template, _ name: String, _ scale: Double, reference: String, pointSizes: [(dimension2: UInt16, points: Double)] = rasterPointSizes,
                        unitFactor: Double = 1, path: String) throws -> [UInt8] {
        let size = String(name.split(separator: "-")[1])
        guard let baseline = template.guides["Baseline-\(size)"], let capline = template.guides["Capline-\(size)"] else {
            throw unsupported("no guides for the size \(size)", path: path)
        }
        let box = glyphBox(template, name)
        let side = try sidebearings(template, name, scale, path: path)
        let interpolatable = template.version >= 3 && masters.allSatisfy { template.glyph($0) != nil }
        let unit = marginUnit * side.factor * unitFactor
        var out = ImageSet.little(interpolatable ? 7 : 3) + ImageSet.little(17)
        for value in [(box.maxY - baseline) * scale, (baseline - capline) * scale, Double(template.version), side.left, unit, side.right, unit] {
            out += ImageSet.little(Float(value).bitPattern)
        }
        let table = name == reference ? pointSizes : []
        out += ImageSet.little(UInt32(table.count))
        for entry in table { out += ImageSet.little(UInt32(entry.dimension2)) + ImageSet.little(UInt32(entry.points)) }
        return out
    }

    /// Property 1019's last word: 1 for multicolor rules, 2 for hierarchical ones.
    static func modes(_ template: Template) -> UInt32 {
        let names = styleRules(template.style).map(\.name)
        return (names.contains { $0.hasPrefix("multicolor-") } ? 1 : 0) | (names.contains { $0.hasPrefix("hierarchical-") } ? 2 : 0)
    }

    /// The regular medium glyph's size in points: its own, or interpolated from the S masters
    /// (`symbols-sets` cases: 13.6894 × 6.5779 either way for git.commit).
    static func referenceBox(_ template: Template, _ scale: Double, path: String) throws -> (width: Double, height: Double) {
        if template.glyph("Regular-M") != nil {
            let box = glyphBox(template, "Regular-M")
            return ((box.maxX - box.minX) * scale, (box.maxY - box.minY) * scale)
        }
        guard masters.allSatisfy({ template.glyph($0) != nil }) else { throw unsupported("neither a Regular-M glyph nor the S masters", path: path) }
        let points = masters.map { points(template.glyph($0)!.elements, rules: styleRules(template.style)) }
        guard Set(points.map(\.count)).count == 1 else { throw unsupported("S masters of different shapes", path: path) }
        let columns = sizeColumns["M"]![1], k = sizeFactor["M"]!
        let interpolated = (0..<points[0].count).map { index in
            (x: (0..<3).reduce(0.0) { $0 + columns[$1] * points[$1][index].x } * k, y: (0..<3).reduce(0.0) { $0 + columns[$1] * points[$1][index].y } * k)
        }
        // The masters' own points are interpolated, then placed by Regular-S's transform (corpus
        // icecubes' Rocket.Fill, experiment `symbol-sets`).
        let placement = template.glyph("Regular-S")!.transform
        let box = boundingBox(interpolated.map { point -> (x: Double, y: Double) in
            let placed = placement.apply(SVGImage.Point(x: point.x, y: point.y))
            return (placed.x, placed.y)
        })
        return ((box.maxX - box.minX) * scale, (box.maxY - box.minY) * scale)
    }
}
