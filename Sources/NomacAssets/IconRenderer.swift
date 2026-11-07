import Foundation
import NomacCore

/// nomac's own drawing of an Icon Composer icon at 1,024 × 1,024 pixels (ADR 0204: equivalent to
/// IconServices' pixels, not identical). The fill covers the canvas; each group's layers are drawn
/// in their rectangles, bottom first, with their paint, then given the group's translucency (more
/// of the fill showing through towards the bottom), its shadow (blurred, below and offset
/// downwards) and its opacity. The tinted appearance draws the layers in gray over a near-black
/// fill. Everything is drawn over opaque dark gray. Colors are composited in sRGB, premultiplied.
enum IconRenderer {
    static let size = 1024

    /// Premultiplied red, green, blue and alpha from 0 to 1, four floats per pixel, rows from the top.
    struct Canvas {
        var width: Int
        var height: Int
        var pixels: [Float]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            pixels = [Float](repeating: 0, count: width * height * 4)
        }

        /// Draws `source` over this canvas with its top left corner at `origin`.
        mutating func draw(_ source: Canvas, at origin: (x: Int, y: Int) = (0, 0), opacity: Float = 1) {
            let x0 = max(0, origin.x), x1 = min(width, origin.x + source.width)
            let y0 = max(0, origin.y), y1 = min(height, origin.y + source.height)
            guard x0 < x1, y0 < y1 else { return }
            let width = self.width, sourceWidth = source.width
            source.pixels.withUnsafeBufferPointer { top in
                pixels.withUnsafeMutableBufferPointer { bottom in
                    var y = y0
                    while y < y1 {
                        var x = x0
                        var t = ((y - origin.y) * sourceWidth + x - origin.x) * 4
                        var b = (y * width + x) * 4
                        while x < x1 {
                            let alpha = top[t + 3] * opacity
                            if alpha > 0 {
                                let keep = 1 - alpha
                                bottom[b] = top[t] * opacity + bottom[b] * keep
                                bottom[b + 1] = top[t + 1] * opacity + bottom[b + 1] * keep
                                bottom[b + 2] = top[t + 2] * opacity + bottom[b + 2] * keep
                                bottom[b + 3] = alpha + bottom[b + 3] * keep
                            }
                            x += 1
                            t += 4
                            b += 4
                        }
                        y += 1
                    }
                }
            }
        }

        /// Fills the canvas with a paint over the unit square.
        mutating func fill(_ sampler: Sampler) {
            let width = self.width, height = self.height
            pixels.withUnsafeMutableBufferPointer { out in
                for y in 0..<height {
                    for x in 0..<width {
                        let color = sampler.at((Float(x) + 0.5) / Float(width), (Float(y) + 0.5) / Float(height))
                        let index = (y * width + x) * 4
                        out[index] = color.0
                        out[index + 1] = color.1
                        out[index + 2] = color.2
                        out[index + 3] = color.3
                    }
                }
            }
        }
    }

    static func render(_ icon: IconComposerIcon, appearance: IconComposerIcon.Appearance) throws -> [UInt8] {
        // The rendered icon is opaque: a translucent fill shows dark gray, black when tinted
        // (`icons` F08, a fill of alpha 0.001: 31 of 255 in actool's any image).
        var canvas = Canvas(width: size, height: size)
        canvas.fill(Sampler(.color(.init(space: 2, components: [appearance == .tinted ? 0 : 0.122, 1])), automaticLift: true))
        var fill = Canvas(width: size, height: size)
        fill.fill(Sampler(appearance == .tinted ? tintedBackground : (appearance == .dark ? icon.fill.dark : icon.fill.light), automaticLift: true))
        canvas.draw(fill)
        for group in icon.groups.reversed() {
            let style = group.style[appearance]!
            guard !style.hidden else { continue }
            var layers = Canvas(width: size, height: size)
            for layer in group.layers.reversed() where !layer.style[appearance]!.hidden {
                let rect = icon.rect(layer, in: group, appearance)
                guard rect.width > 0, rect.height > 0 else { continue }
                var drawn = try draw(icon.images.first { $0.file == layer.file }!.image, width: rect.width, height: rect.height)
                if let paint = icon.layerPaint(layer, appearance) { recolor(&drawn, with: Sampler(paint, automaticLift: false)) }
                if appearance == .tinted { gray(&drawn) }
                layers.draw(drawn, at: (rect.x, rect.y), opacity: Float(layer.style[appearance]!.opacity))
            }
            applyTranslucency(&layers, Float(style.translucency))
            if style.shadowKind != 0 {
                canvas.draw(shadow(of: layers, opacity: Float(style.shadowOpacity)), opacity: Float(style.opacity))
            }
            canvas.draw(layers, opacity: Float(style.opacity))
        }
        return bgra(canvas)
    }

    /// A canvas's pixels as BGRA bytes.
    static func bgra(_ canvas: Canvas) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: canvas.width * canvas.height * 4)
        canvas.pixels.withUnsafeBufferPointer { pixels in
            bytes.withUnsafeMutableBufferPointer { out in
                var index = 0
                while index < pixels.count {
                    out[index] = byte(pixels[index + 2])
                    out[index + 1] = byte(pixels[index + 1])
                    out[index + 2] = byte(pixels[index])
                    out[index + 3] = byte(pixels[index + 3])
                    index += 4
                }
            }
        }
        return bytes
    }

    /// The tinted appearance's fill: near black, a little lighter at the top.
    static let tintedBackground = IconComposerIcon.Paint.gradient(.init(
        stops: [.init(space: 2, components: [0.047, 1]), .init(space: 2, components: [0.024, 1])], automatic: false,
        orientation: IconComposerIcon.Paint.defaultOrientation))

    static func byte(_ value: Float) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }

    typealias Color = (Float, Float, Float, Float)

    /// A paint's color at the points of the unit square. An automatic gradient goes from its color
    /// lightened with 30% white at its start to 3% at its stop (filling layers, from 15% to none).
    struct Sampler {
        let start: Color
        let end: Color
        let origin: (x: Float, y: Float)
        let direction: (x: Float, y: Float)

        init(_ paint: IconComposerIcon.Paint, automaticLift: Bool) {
            guard let gradient = paint.gradient else {
                guard case .color(let value) = paint else { preconditionFailure("a paint is a color or a gradient") }
                start = premultiplied(rgba(value))
                end = start
                origin = (0, 0)
                direction = (0, 0)
                return
            }
            let o = gradient.orientation.map { Float($0) }
            let length = (o[2] - o[0]) * (o[2] - o[0]) + (o[3] - o[1]) * (o[3] - o[1])
            origin = (o[0], o[1])
            direction = length == 0 ? (0, 0) : ((o[2] - o[0]) / length, (o[3] - o[1]) / length)
            if gradient.automatic {
                let base = rgba(gradient.stops[0])
                func lifted(_ lift: Float) -> Color {
                    premultiplied((base.0 + (1 - base.0) * lift, base.1 + (1 - base.1) * lift, base.2 + (1 - base.2) * lift, base.3))
                }
                start = lifted(automaticLift ? 0.3 : 0.15)
                end = lifted(automaticLift ? 0.03 : 0)
            } else {
                start = premultiplied(rgba(gradient.stops[0]))
                end = premultiplied(rgba(gradient.stops[gradient.stops.count - 1]))
            }
        }

        func at(_ x: Float, _ y: Float) -> Color {
            let t = min(max((x - origin.x) * direction.x + (y - origin.y) * direction.y, 0), 1)
            return (start.0 + (end.0 - start.0) * t, start.1 + (end.1 - start.1) * t, start.2 + (end.2 - start.2) * t, start.3 + (end.3 - start.3) * t)
        }
    }

    static func premultiplied(_ color: Color) -> Color {
        (color.0 * color.3, color.1 * color.3, color.2 * color.3, color.3)
    }

    /// A color's sRGB components and alpha, clamped.
    static func rgba(_ color: IconComposerIcon.IconColor) -> Color {
        let c = color.components
        let rgb: (Double, Double, Double)
        switch color.space {
        case 2, 6: rgb = (c[0], c[0], c[0])
        case 3: rgb = ColorConversion.displayP3ToSRGB((c[0], c[1], c[2]))
        default: rgb = (c[0], c[1], c[2])
        }
        let clamp = { (v: Double) in Float(min(max(v, 0), 1)) }
        return (clamp(rgb.0), clamp(rgb.1), clamp(rgb.2), clamp(c[c.count - 1]))
    }

    /// A layer image drawn at a size in pixels.
    /// A layer image drawn at a size in pixels; an SVG's content can be given a smaller size,
    /// drawn at the bottom left.
    static func draw(_ image: IconComposerIcon.LayerImage, width: Int, height: Int, content: (width: Double, height: Double)? = nil) throws -> Canvas {
        var canvas = Canvas(width: width, height: height)
        switch image {
        case .svg(let svg, _):
            let size = content ?? (Double(width), Double(height))
            let sx = size.width / svg.viewBox.width, sy = size.height / svg.viewBox.height
            let offset = Double(height) - size.height
            func pixels(_ polygons: [[SVGImage.Point]]) -> [[SVGImage.Point]] {
                polygons.map { $0.map { SVGImage.Point(x: ($0.x - svg.viewBox.x) * sx, y: ($0.y - svg.viewBox.y) * sy + offset) } }
            }
            var maskFactors: [Int: [Double]] = [:]
            func render(_ shapes: [SVGImage.Shape]) -> Canvas {
                var canvas = Canvas(width: width, height: height)
                // One coverage buffer for all shapes, cleared after each over the rows it reached.
                var coverage = [Double](repeating: 0, count: width * height), inside = coverage
                for shape in shapes {
                    let rows = Rasterizer.fill(pixels(shape.polygons), width: width, height: height, evenOdd: shape.evenOdd, into: &coverage)
                    for clip in shape.clips {
                        let reached = Rasterizer.fill(pixels(clip.polygons), width: width, height: height, evenOdd: clip.evenOdd, into: &inside)
                        for index in rows.lowerBound * width..<rows.upperBound * width { coverage[index] *= inside[index] }
                        for index in reached.lowerBound * width..<reached.upperBound * width { inside[index] = 0 }
                    }
                    // A mask lets through its content's luminance (Rec. 709 weights on the
                    // premultiplied color) inside its region.
                    for mask in shape.masks {
                        let factors = maskFactors[mask.number] ?? {
                            let content = render(mask.shapes)
                            let region = Rasterizer.fill(pixels(mask.region), width: width, height: height, evenOdd: false)
                            return region.indices.map { index in
                                let p = index * 4
                                return (0.2125 * Double(content.pixels[p]) + 0.7154 * Double(content.pixels[p + 1]) + 0.0721 * Double(content.pixels[p + 2])) * region[index]
                            }
                        }()
                        maskFactors[mask.number] = factors
                        for index in rows.lowerBound * width..<rows.upperBound * width { coverage[index] *= factors[index] }
                    }
                    canvas.pixels.withUnsafeMutableBufferPointer { out in
                        for index in rows.lowerBound * width..<rows.upperBound * width {
                            let value = coverage[index]
                            guard value > 0 else { continue }
                            coverage[index] = 0
                            let color: SVGImage.RGB, alpha: Double
                            switch shape.paint {
                            case .color(let rgb): (color, alpha) = (rgb, shape.opacity)
                            case .gradient(let gradient):
                                let point = SVGImage.Point(x: (Double(index % width) + 0.5) / sx + svg.viewBox.x, y: (Double(index / width) + 0.5 - offset) / sy + svg.viewBox.y)
                                let (rgb, opacity) = gradient.at(point)
                                (color, alpha) = (rgb, opacity * shape.opacity)
                            }
                            let v = Float(value * alpha)
                            guard v > 0 else { continue }
                            let keep = 1 - v
                            out[index * 4] = Float(color.red) * v + out[index * 4] * keep
                            out[index * 4 + 1] = Float(color.green) * v + out[index * 4 + 1] * keep
                            out[index * 4 + 2] = Float(color.blue) * v + out[index * 4 + 2] * keep
                            out[index * 4 + 3] = v + out[index * 4 + 3] * keep
                        }
                    }
                }
                return canvas
            }
            canvas = render(svg.shapes)
        case .png(let png, _):
            var source = Canvas(width: png.width, height: png.height)
            source.pixels = png.pixels.withUnsafeBufferPointer { bgra in
                var pixels = [Float](repeating: 0, count: bgra.count)
                var index = 0
                while index < bgra.count {
                    pixels[index] = Float(bgra[index + 2]) / 255
                    pixels[index + 1] = Float(bgra[index + 1]) / 255
                    pixels[index + 2] = Float(bgra[index]) / 255
                    pixels[index + 3] = Float(bgra[index + 3]) / 255
                    index += 4
                }
                return pixels
            }
            canvas = resample(source, toWidth: width, toHeight: height)
        }
        return canvas
    }

    /// Replaces a layer's colors by a paint over the layer's own rectangle, keeping its coverage.
    static func recolor(_ canvas: inout Canvas, with sampler: Sampler) {
        let width = canvas.width, height = canvas.height
        canvas.pixels.withUnsafeMutableBufferPointer { pixels in
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    let alpha = pixels[index + 3]
                    guard alpha > 0 else { continue }
                    let color = sampler.at((Float(x) + 0.5) / Float(width), (Float(y) + 0.5) / Float(height))
                    pixels[index] = color.0 * alpha
                    pixels[index + 1] = color.1 * alpha
                    pixels[index + 2] = color.2 * alpha
                    pixels[index + 3] = color.3 * alpha
                }
            }
        }
    }

    static func gray(_ canvas: inout Canvas) {
        canvas.pixels.withUnsafeMutableBufferPointer { pixels in
            var index = 0
            while index < pixels.count {
                let luminance = 0.2126 * pixels[index] + 0.7152 * pixels[index + 1] + 0.0722 * pixels[index + 2]
                pixels[index] = luminance
                pixels[index + 1] = luminance
                pixels[index + 2] = luminance
                index += 4
            }
        }
    }

    /// Glass lets the fill show through: from a fifth of the translucency at the top of the canvas
    /// to four fifths at the bottom.
    static func applyTranslucency(_ canvas: inout Canvas, _ translucency: Float) {
        guard translucency > 0 else { return }
        let width = canvas.width, height = canvas.height
        canvas.pixels.withUnsafeMutableBufferPointer { pixels in
            for y in 0..<height {
                let factor = 1 - translucency * (0.2 + 0.6 * Float(y) / Float(height))
                var index = y * width * 4
                let end = index + width * 4
                while index < end {
                    pixels[index] *= factor
                    index += 1
                }
            }
        }
    }

    /// The group's coverage in black, blurred over 16 pixels and moved 12 pixels down.
    static func shadow(of canvas: Canvas, opacity: Float) -> Canvas {
        var alpha = [Float](repeating: 0, count: canvas.width * canvas.height)
        for index in alpha.indices { alpha[index] = canvas.pixels[index * 4 + 3] }
        for _ in 0..<3 { alpha = boxBlur(alpha, width: canvas.width, height: canvas.height, radius: 8) }
        var shadow = Canvas(width: canvas.width, height: canvas.height)
        let offset = 12, width = canvas.width, strength = opacity * 0.6
        shadow.pixels.withUnsafeMutableBufferPointer { pixels in
            for index in 0..<(canvas.height - offset) * width {
                pixels[(index + offset * width) * 4 + 3] = alpha[index] * strength
            }
        }
        return shadow
    }

    static func boxBlur(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        let scale = 1 / Float(2 * radius + 1)
        var horizontal = [Float](repeating: 0, count: values.count)
        var vertical = [Float](repeating: 0, count: values.count)
        values.withUnsafeBufferPointer { values in
            horizontal.withUnsafeMutableBufferPointer { out in
                for y in 0..<height {
                    let row = y * width
                    var sum: Float = 0
                    for x in -radius...radius { sum += values[row + min(max(x, 0), width - 1)] }
                    for x in 0..<width {
                        out[row + x] = sum * scale
                        sum += values[row + min(x + radius + 1, width - 1)] - values[row + max(x - radius, 0)]
                    }
                }
            }
        }
        horizontal.withUnsafeBufferPointer { values in
            vertical.withUnsafeMutableBufferPointer { out in
                for x in 0..<width {
                    var sum: Float = 0
                    for y in -radius...radius { sum += values[min(max(y, 0), height - 1) * width + x] }
                    for y in 0..<height {
                        out[y * width + x] = sum * scale
                        sum += values[min(y + radius + 1, height - 1) * width + x] - values[max(y - radius, 0) * width + x]
                    }
                }
            }
        }
        return vertical
    }

    /// Area-weighted resampling (bilinear when enlarging) of premultiplied pixels.
    static func resample(_ source: Canvas, toWidth: Int, toHeight: Int) -> Canvas {
        if source.width == toWidth && source.height == toHeight { return source }
        func weights(_ from: Int, _ to: Int) -> [[(Int, Float)]] {
            let scale = Double(from) / Double(to)
            return (0..<to).map { target in
                if scale <= 1 {
                    let center = (Double(target) + 0.5) * scale - 0.5
                    let low = Int(center.rounded(.down)), fraction = Float(center - Double(low))
                    return [(min(max(low, 0), from - 1), 1 - fraction), (min(max(low + 1, 0), from - 1), fraction)]
                }
                let start = Double(target) * scale, end = start + scale
                var list: [(Int, Float)] = []
                var position = Int(start.rounded(.down))
                while Double(position) < end && position < from {
                    let overlap = min(end, Double(position + 1)) - max(start, Double(position))
                    if overlap > 0 { list.append((position, Float(overlap / scale))) }
                    position += 1
                }
                return list
            }
        }
        let columns = weights(source.width, toWidth), rows = weights(source.height, toHeight)
        var horizontal = Canvas(width: toWidth, height: source.height)
        source.pixels.withUnsafeBufferPointer { pixels in
            horizontal.pixels.withUnsafeMutableBufferPointer { out in
                for y in 0..<source.height {
                    for (x, list) in columns.enumerated() {
                        let target = (y * toWidth + x) * 4
                        for (column, weight) in list {
                            let index = (y * source.width + column) * 4
                            for channel in 0..<4 { out[target + channel] += pixels[index + channel] * weight }
                        }
                    }
                }
            }
        }
        var result = Canvas(width: toWidth, height: toHeight)
        horizontal.pixels.withUnsafeBufferPointer { pixels in
            result.pixels.withUnsafeMutableBufferPointer { out in
                for (y, list) in rows.enumerated() {
                    for (row, weight) in list {
                        var index = row * toWidth * 4, target = y * toWidth * 4
                        let end = target + toWidth * 4
                        while target < end {
                            out[target] += pixels[index] * weight
                            index += 1
                            target += 1
                        }
                    }
                }
            }
        }
        return result
    }

    /// A BGRA image resized for an icon PNG.
    static func downsample(_ bgra: [UInt8], from size: Int, to target: Int) -> [UInt8] {
        var source = Canvas(width: size, height: size)
        source.pixels = bgra.map { Float($0) / 255 }
        let resized = resample(source, toWidth: target, toHeight: target)
        return resized.pixels.map { byte($0) }
    }
}

/// Filling polygons with antialiasing: eight sample rows per pixel, each crossing's horizontal
/// coverage exact.
enum Rasterizer {
    static let samples = 8

    static func fill(_ polygons: [[SVGImage.Point]], width: Int, height: Int, evenOdd: Bool) -> [Double] {
        var coverage = [Double](repeating: 0, count: width * height)
        fill(polygons, width: width, height: height, evenOdd: evenOdd, into: &coverage)
        return coverage
    }

    /// Writes the coverage of the rows the polygons reach, the others untouched, and returns those rows.
    @discardableResult
    static func fill(_ polygons: [[SVGImage.Point]], width: Int, height: Int, evenOdd: Bool, into coverage: inout [Double]) -> Range<Int> {
        struct Edge { var x0, y0, x1, y1: Double; var direction: Int }
        var edges: [Edge] = []
        for polygon in polygons where polygon.count > 1 {
            for index in polygon.indices {
                let a = polygon[index], b = polygon[(index + 1) % polygon.count]
                guard a.y != b.y else { continue }
                edges.append(a.y < b.y ? Edge(x0: a.x, y0: a.y, x1: b.x, y1: b.y, direction: 1) : Edge(x0: b.x, y0: b.y, x1: a.x, y1: a.y, direction: -1))
            }
        }
        guard !edges.isEmpty else { return 0..<0 }
        let minY = max(0, Int(edges.map(\.y0).min()!.rounded(.down))), maxY = min(height, Int(edges.map(\.y1).max()!.rounded(.up)))
        var row = [Double](repeating: 0, count: width + 1)
        var crossings: [(x: Double, direction: Int)] = []
        // The edges a scan line crosses, kept as it moves down: those starting above it added,
        // those ending above it dropped.
        edges.sort { $0.y0 < $1.y0 }
        var active: [Edge] = []
        var next = 0
        for y in minY..<max(minY, maxY) {
            for index in row.indices { row[index] = 0 }
            for sample in 0..<samples {
                let sy = Double(y) + (Double(sample) + 0.5) / Double(samples)
                while next < edges.count, edges[next].y0 <= sy {
                    active.append(edges[next])
                    next += 1
                }
                active.removeAll { $0.y1 <= sy }
                crossings.removeAll(keepingCapacity: true)
                for edge in active {
                    crossings.append((edge.x0 + (sy - edge.y0) / (edge.y1 - edge.y0) * (edge.x1 - edge.x0), edge.direction))
                }
                crossings.sort { $0.x < $1.x }
                var winding = 0
                for (index, crossing) in crossings.enumerated() {
                    winding += crossing.direction
                    let inside = evenOdd ? winding % 2 != 0 : winding != 0
                    guard inside, index + 1 < crossings.count else { continue }
                    span(&row, from: crossing.x, to: crossings[index + 1].x, width: width, weight: 1 / Double(samples))
                }
            }
            for x in 0..<width { coverage[y * width + x] = min(row[x], 1) }
        }
        return minY..<max(minY, maxY)
    }

    static func span(_ row: inout [Double], from start: Double, to end: Double, width: Int, weight: Double) {
        let a = min(max(start, 0), Double(width)), b = min(max(end, 0), Double(width))
        guard b > a else { return }
        let first = Int(a.rounded(.down)), last = Int(b.rounded(.down))
        if first == last {
            row[first] += (b - a) * weight
            return
        }
        row[first] += (Double(first + 1) - a) * weight
        if first + 1 < last { for x in first + 1..<last { row[x] += weight } }
        if last < width { row[last] += (b - Double(last)) * weight }
    }
}

/// Conversions between sRGB and Display P3 (both with the sRGB transfer function, D65).
enum ColorConversion {
    static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func encoded(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    static func sRGBToDisplayP3(_ color: (red: Double, green: Double, blue: Double)) -> (Double, Double, Double) {
        let r = linear(color.red), g = linear(color.green), b = linear(color.blue)
        return (encoded(0.822_462 * r + 0.177_538 * g),
                encoded(0.033_194 * r + 0.966_806 * g),
                encoded(0.017_083 * r + 0.072_397 * g + 0.910_520 * b))
    }

    static func displayP3ToSRGB(_ color: (Double, Double, Double)) -> (Double, Double, Double) {
        let r = linear(color.0), g = linear(color.1), b = linear(color.2)
        return (encoded(max(0, 1.224_940 * r - 0.224_940 * g)),
                encoded(max(0, -0.042_057 * r + 1.042_057 * g)),
                encoded(max(0, -0.019_638 * r - 0.078_636 * g + 1.098_274 * b)))
    }
}
