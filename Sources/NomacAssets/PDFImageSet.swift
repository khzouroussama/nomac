import Foundation
import NomacCore

extension ImageSet {
    /// A PDF file's images: rasters at the platform's scales (1x, 2x and 3x; 2x only on watchOS,
    /// as for SVGs: pocket-casts' watch catalog) of the page's size in points, each side
    /// rounded to the nearest pixel, halves up (12.5 × 7.25 points give 13 × 7, 25 × 15 and
    /// 38 × 22 pixels), their slice the whole image, the page stretched over it by nomac's
    /// renderer (ADR 0204); and the page as Quartz writes it again for the vector rendition
    /// (`QuartzPDF`; `pdf_experiments.py` structure: size-fraction).
    static func pdfImages(_ asset: AssetCatalog.Asset, filename: String, renderingIntent: String?, preservesVector: Bool, scales: [Int]) throws -> [Source] {
        let path = asset.path + "/" + filename
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("could not read the image", path: path) }
        let page = try PDFPage(file: PDFFile(data: [UInt8](data), path: path))
        func isCMYK(_ color: PDFPage.Color) -> Bool { color.space == nil && color.pattern == nil }
        if page.drawings.contains(where: { $0.fill && isCMYK($0.color) || $0.stroke && isCMYK($0.strokeColor) }) {
            throw NomacError("PDF images with CMYK colors are not supported yet (BACKLOG B-215)", path: path)
        }
        let vector = QuartzPDF.rewrite(page)
        let colors = try PDFRaster.Colors(page)
        let size = (width: page.box.maxX - page.box.minX, height: page.box.maxY - page.box.minY)
        return scales.map { scale in
            let width = Int((size.width * Double(scale)).rounded(.toNearestOrAwayFromZero))
            let height = Int((size.height * Double(scale)).rounded(.toNearestOrAwayFromZero))
            var image = PNGImage(width: width, height: height, pixels: IconRenderer.bgra(PDFRaster.draw(page, width: width, height: height, colors: colors, extended: false)))
            if colors.wide {
                image.widePixels = PDFRaster.draw(page, width: width, height: height, colors: colors, extended: true).pixels.flatMap { value -> [UInt8] in
                    let half = PNGImage.half(value)
                    return [UInt8(half & 0xFF), UInt8(half >> 8)]
                }
            }
            var source = Source(name: asset.name, filename: filename, path: path, image: image, scale: scale)
            source.slice = (0, 0, width, height)
            source.renderingIntent = renderingIntent
            source.rasterized = true
            source.isOpaque = false
            source.preservesVector = preservesVector
            if scale == scales[0] { source.vectorData = vector }
            return source
        }
    }
}

/// nomac's drawing of a PDF page (ADR 0204): each fill's path flattened into polygons and
/// filled with eight-row antialiasing, each stroke outlined as SVG strokes are (dashes drawn
/// solid), cut by the clips, its color times its opacity drawn over what is below, a group
/// drawn with an opacity drawn alone first, an image by the sample under each pixel's center,
/// the page stretched over the image.
enum PDFRaster {
    /// The drawings' colors in sRGB, clamped, and in extended sRGB; an ICCBased color converted
    /// from its profile, as actool converts a PNG's (B-213). The images also get a rendition in
    /// extended sRGB when a color lies outside sRGB by the PNGs' limits (`icc` p3 cases: Display
    /// P3 red adds the display gamut 1 renditions).
    struct Colors {
        var fills: [(sRGB: [Double], extended: [Double])] = []
        var strokes: [(sRGB: [Double], extended: [Double])] = []
        /// Each image's pixels by its key, rows from the top: colors in sRGB and extended sRGB,
        /// and alpha from its soft mask or stencil.
        var images: [Int: (sRGB: [Double], extended: [Double], alpha: [Double])] = [:]
        /// Each shading's colors by key at 1,024 even steps of its domain.
        var shadings: [Int: (sRGB: [[Double]], extended: [[Double]])] = [:]
        /// The drawings' colors of each luminosity mask, by serial.
        var masks: [Int: (fills: [(sRGB: [Double], extended: [Double])], strokes: [(sRGB: [Double], extended: [Double])])] = [:]
        var wide = false

        init(_ page: PDFPage) throws {
            var profiles: [[UInt8]: ICCProfile] = [:]
            func convert(_ color: PDFPage.Color) throws -> (sRGB: [Double], extended: [Double]) {
                if color.pattern != nil { return ([0, 0, 0], [0, 0, 0]) }
                let components = color.components.map { min(max($0, 0), 1) }
                guard case .icc(let data, let count)? = color.space else {
                    let rgb = components.count == 1 ? [components[0], components[0], components[0]] : components
                    return (rgb, rgb)
                }
                let profile = try profiles[data] ?? ICCProfile(data)
                profiles[data] = profile
                let bytes = components.map { UInt8(($0 * 255).rounded()) }
                if count == 1 || profile.isGray {
                    let gray = Double(profile.convertGray(bytes[0])) / 255
                    return ([gray, gray, gray], [gray, gray, gray])
                }
                let converted = profile.convert(bytes[0], bytes[1], bytes[2])
                wide = wide || converted.under > 0.0015 || converted.over > 0.0078
                let unclamped = profile.extended(bytes[0], bytes[1], bytes[2])
                return ([converted.red, converted.green, converted.blue].map { Double($0) / 255 }, [unclamped.red, unclamped.green, unclamped.blue])
            }
            for drawing in page.drawings {
                fills.append(try convert(drawing.color))
                strokes.append(try convert(drawing.strokeColor))
            }
            func table(_ shading: PDFPage.Shading) throws {
                guard shadings[shading.key] == nil else { return }
                var sRGB: [[Double]] = [], extended: [[Double]] = []
                for step in 0..<1024 {
                    let t = shading.domain[0] + Double(step) / 1023 * (shading.domain[1] - shading.domain[0])
                    let color = try convert(PDFPage.Color(space: shading.space, components: shading.function.evaluate(t)))
                    sRGB.append(color.sRGB)
                    extended.append(color.extended)
                }
                shadings[shading.key] = (sRGB, extended)
            }
            func tables(_ items: [PDFPage.Item]) throws {
                for item in items {
                    switch item {
                    case .shading(let fill): try table(fill.shading)
                    case .group(let group): try tables(group.items)
                    case .drawing, .text:
                        guard let drawing = item.drawing else { continue }
                        if let pattern = drawing.color.pattern { try table(pattern.shading) }
                        if let pattern = drawing.strokeColor.pattern { try table(pattern.shading) }
                    case .image: break
                    }
                }
            }
            try tables(page.items)
            /// The luminosity masks the items use, their content's colors and shadings.
            func luminosityMasks(_ items: [PDFPage.Item]) throws {
                for item in items {
                    var mask: PDFPage.SoftMask?
                    switch item {
                    case .drawing, .text: mask = item.drawing?.softMask
                    case .group(let group):
                        mask = group.softMask
                        try luminosityMasks(group.items)
                    case .image(let image): mask = image.softMask
                    case .shading(let fill): mask = fill.softMask
                    }
                    guard let mask, mask.luminosity != nil, masks[mask.serial] == nil else { continue }
                    let drawings = PDFPage.drawings(mask.items)
                    masks[mask.serial] = (try drawings.map { try convert($0.color) }, try drawings.map { try convert($0.strokeColor) })
                    try tables(mask.items)
                    try luminosityMasks(mask.items)
                }
            }
            try luminosityMasks(page.items)
            for image in PDFPage.images(page.items) where images[image.key] == nil {
                let samples = image.samples
                let values = Self.values(samples)
                var cache: [[Double]: (sRGB: [Double], extended: [Double])] = [:]
                var sRGB: [Double] = [], extended: [Double] = [], alpha: [Double] = []
                let stencil = try samples.space == nil ? convert(image.color) : nil
                let mask = image.mask.map(Self.values)
                for pixel in 0..<(samples.width * samples.height) {
                    let count = samples.space?.components ?? 1
                    let components = Array(values[(pixel * count)..<(pixel * count + count)])
                    var opacity = mask.map { maskValues in
                        // The mask's pixel nearest this one's center (`images` rgb-smask: same size).
                        let x = (pixel % samples.width) * image.mask!.width / samples.width
                        let y = (pixel / samples.width) * image.mask!.height / samples.height
                        return maskValues[y * image.mask!.width + x]
                    } ?? 1
                    let color: (sRGB: [Double], extended: [Double])
                    if let stencil {
                        color = stencil
                        opacity *= components[0] < 0.5 ? 1 : 0
                    } else if let known = cache[components] {
                        color = known
                    } else {
                        color = try convert(PDFPage.Color(space: samples.space, components: components))
                        cache[components] = color
                    }
                    sRGB += color.sRGB
                    extended += color.extended
                    alpha.append(opacity)
                }
                images[image.key] = (sRGB, extended, alpha)
            }
        }

        /// Samples as components from 0 to 1, `/Decode` applied, pixel by pixel from the top row.
        static func values(_ samples: PDFPage.Samples) -> [Double] {
            let count = samples.space?.components ?? 1
            let bits = samples.bitsPerComponent
            let row = (samples.width * count * bits + 7) / 8
            let maximum = Double((1 << bits) - 1)
            var values: [Double] = []
            values.reserveCapacity(samples.width * samples.height * count)
            for y in 0..<samples.height {
                for index in 0..<(samples.width * count) {
                    let raw: Int
                    switch bits {
                    case 8: raw = Int(samples.data[y * row + index])
                    case 16: raw = Int(samples.data[y * row + index * 2]) << 8 | Int(samples.data[y * row + index * 2 + 1])
                    default:
                        let bit = index * bits
                        raw = Int(samples.data[y * row + bit / 8] >> (8 - bits - bit % 8)) & ((1 << bits) - 1)
                    }
                    let fraction = Double(raw) / maximum
                    if let decode = samples.decode {
                        let channel = index % count
                        values.append(decode[2 * channel] + fraction * (decode[2 * channel + 1] - decode[2 * channel]))
                    } else {
                        values.append(fraction)
                    }
                }
            }
            return values
        }
    }

    static func draw(_ page: PDFPage, width: Int, height: Int, colors: Colors, extended: Bool) -> IconRenderer.Canvas {
        let scaleX = Double(width) / (page.box.maxX - page.box.minX), scaleY = Double(height) / (page.box.maxY - page.box.minY)
        var canvas = IconRenderer.Canvas(width: width, height: height)
        var masks: [Int: [Double]] = [:]
        var softMasks: [Int: [Double]] = [:]
        var index = 0
        var fills = colors.fills, strokes = colors.strokes
        func pixel(_ point: PDFPage.Point) -> SVGImage.Point {
            SVGImage.Point(x: (point.x - page.box.minX) * scaleX, y: Double(height) - (point.y - page.box.minY) * scaleY)
        }
        /// A soft mask's value per pixel: its content's alpha drawn alone, colors aside, within its
        /// box; for a luminosity mask its content's luminance over the backdrop (PDF 1.7 § 11.5.3),
        /// the backdrop's outside the box; then the transfer function.
        func alpha(_ softMask: PDFPage.SoftMask) -> [Double] {
            if let known = softMasks[softMask.serial] { return known }
            var layer = IconRenderer.Canvas(width: width, height: height)
            let box = PDFPage.Path(rectangle: softMask.box).applying(softMask.matrix)
            let inside = Rasterizer.fill(subpaths(box).map { $0.points.map(pixel) }, width: width, height: height, evenOdd: false)
            var result: [Double]
            if let luminosity = softMask.luminosity, let palette = colors.masks[softMask.serial] {
                let saved = (index, fills, strokes)
                (index, fills, strokes) = (0, palette.fills, palette.strokes)
                draw(PDFPage.transformed(softMask.items, by: softMask.matrix), on: &layer)
                (index, fills, strokes) = saved
                let backdrop = luminosity.backdrop.count == 1 ? [Double](repeating: luminosity.backdrop[0], count: 3) : luminosity.backdrop
                let weights = [0.3, 0.59, 0.11]
                let outside = zip(backdrop, weights).map { $0 * $1 }.reduce(0, +)
                result = (0..<(width * height)).map { pixel in
                    let keep = 1 - Double(layer.pixels[pixel * 4 + 3])
                    let value = (0..<3).map { (Double(layer.pixels[pixel * 4 + $0]) + backdrop[$0] * keep) * weights[$0] }.reduce(0, +)
                    return value * inside[pixel] + outside * (1 - inside[pixel])
                }
            } else {
                draw(PDFPage.transformed(softMask.items, by: softMask.matrix), on: &layer, colorless: true)
                result = (0..<(width * height)).map { Double(layer.pixels[$0 * 4 + 3]) * inside[$0] }
            }
            if let transfer = softMask.transfer {
                result = result.map { min(max(transfer.evaluate(min(max($0, 0), 1)).first ?? $0, 0), 1) }
            }
            softMasks[softMask.serial] = result
            return result
        }
        /// The color a shading gives at a pixel, through `matrix` to its space.
        func shade(_ shading: PDFPage.Shading, inverse: PDFPage.Matrix, pixel index: Int) -> [Double]? {
            let point = inverse.apply(page.box.minX + (Double(index % width) + 0.5) / scaleX, page.box.minY + (Double(height) - Double(index / width) - 0.5) / scaleY)
            guard let t = shading.parameter(at: point), let table = colors.shadings[shading.key] else { return nil }
            let step = Int(((t - shading.domain[0]) / max(shading.domain[1] - shading.domain[0], 1e-12) * 1023).rounded())
            return (extended ? table.extended : table.sRGB)[min(max(step, 0), 1023)]
        }
        func paint(_ coverage: [Double], clips: [PDFPage.Clip], softMask: PDFPage.SoftMask?, rgb: [Double], alpha opacity: Double,
                   on canvas: inout IconRenderer.Canvas, pattern: PDFPage.Pattern? = nil) {
            var coverage = coverage
            if let softMask {
                let mask = alpha(softMask)
                for index in coverage.indices { coverage[index] *= mask[index] }
            }
            for clip in clips {
                let mask = masks[clip.serial] ?? Rasterizer.fill(subpaths(clip.path).map { $0.points.map(pixel) }, width: width, height: height, evenOdd: clip.evenOdd)
                masks[clip.serial] = mask
                for index in coverage.indices { coverage[index] *= mask[index] }
            }
            let inverse = pattern?.matrix.inverted
            for index in coverage.indices where coverage[index] > 0 {
                var color = rgb
                if let pattern {
                    guard let inverse, let shaded = shade(pattern.shading, inverse: inverse, pixel: index) else { continue }
                    color = shaded
                }
                let alpha = Float(min(max(coverage[index] * opacity, 0), 1))
                let keep = 1 - alpha
                let base = index * 4
                for channel in 0..<3 {
                    canvas.pixels[base + channel] = Float(color[channel]) * alpha + canvas.pixels[base + channel] * keep
                }
                canvas.pixels[base + 3] = alpha + canvas.pixels[base + 3] * keep
            }
        }
        func draw(_ items: [PDFPage.Item], on canvas: inout IconRenderer.Canvas, colorless: Bool = false) {
            for item in items {
                switch item {
                case .group(let group) where group.alpha == 1 && group.softMask == nil && group.clips.isEmpty:
                    draw(group.items, on: &canvas, colorless: colorless)
                case .group(let group):
                    // A group drawn with an opacity, a soft mask or within clips (its content has
                    // only their bounding boxes): its items drawn alone, then laid over what is
                    // below through them.
                    var layer = IconRenderer.Canvas(width: width, height: height)
                    draw(group.items, on: &layer, colorless: colorless)
                    var coverage = group.softMask.map(alpha) ?? [Double](repeating: 1, count: width * height)
                    for clip in group.clips {
                        let mask = masks[clip.serial] ?? Rasterizer.fill(subpaths(clip.path).map { $0.points.map(pixel) }, width: width, height: height, evenOdd: clip.evenOdd)
                        masks[clip.serial] = mask
                        for index in coverage.indices { coverage[index] *= mask[index] }
                    }
                    for base in stride(from: 0, to: layer.pixels.count, by: 4) where layer.pixels[base + 3] > 0 {
                        let opacity = Float(group.alpha * coverage[base / 4])
                        let keep = 1 - layer.pixels[base + 3] * opacity
                        for channel in 0..<4 { canvas.pixels[base + channel] = layer.pixels[base + channel] * opacity + canvas.pixels[base + channel] * keep }
                    }
                case .shading(let fill):
                    guard let inverse = fill.matrix.inverted else { continue }
                    var coverage = [Double](repeating: 1, count: width * height)
                    if colorless {
                        paint(coverage, clips: fill.clips, softMask: fill.softMask, rgb: [0, 0, 0], alpha: fill.alpha, on: &canvas)
                        continue
                    }
                    for index in coverage.indices where shade(fill.shading, inverse: inverse, pixel: index) == nil { coverage[index] = 0 }
                    paint(coverage, clips: fill.clips, softMask: fill.softMask, rgb: [0, 0, 0], alpha: fill.alpha, on: &canvas,
                          pattern: PDFPage.Pattern(key: fill.shading.key, shading: fill.shading, matrix: fill.matrix))
                case .image(let image):
                    guard let pixels = colors.images[image.key], let inverse = image.matrix.inverted else { continue }
                    let corners = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].map { pixel(image.matrix.apply($0.0, $0.1)) }
                    var coverage = Rasterizer.fill([corners], width: width, height: height, evenOdd: false)
                    for clip in image.clips {
                        let mask = masks[clip.serial] ?? Rasterizer.fill(subpaths(clip.path).map { $0.points.map(pixel) }, width: width, height: height, evenOdd: clip.evenOdd)
                        masks[clip.serial] = mask
                        for index in coverage.indices { coverage[index] *= mask[index] }
                    }
                    if let softMask = image.softMask {
                        let mask = alpha(softMask)
                        for index in coverage.indices { coverage[index] *= mask[index] }
                    }
                    let samples = image.samples
                    for index in coverage.indices where coverage[index] > 0 {
                        // The sample under the pixel's center.
                        let point = inverse.apply(page.box.minX + (Double(index % width) + 0.5) / scaleX,
                                                  page.box.minY + (Double(height) - Double(index / width) - 0.5) / scaleY)
                        let column = min(max(Int(point.x * Double(samples.width)), 0), samples.width - 1)
                        let row = min(max(Int((1 - point.y) * Double(samples.height)), 0), samples.height - 1)
                        let sample = row * samples.width + column
                        let rgb = extended ? pixels.extended : pixels.sRGB
                        let alpha = Float(min(max(coverage[index] * pixels.alpha[sample] * image.alpha, 0), 1))
                        let keep = 1 - alpha
                        for channel in 0..<3 { canvas.pixels[index * 4 + channel] = Float(rgb[sample * 3 + channel]) * alpha + canvas.pixels[index * 4 + channel] * keep }
                        canvas.pixels[index * 4 + 3] = alpha + canvas.pixels[index * 4 + 3] * keep
                    }
                case .drawing, .text:
                    guard let drawing = item.drawing else { continue }
                    defer { if !colorless { index += 1 } }
                    let fill = colorless ? [0, 0, 0] : extended ? fills[index].extended : fills[index].sRGB
                    let stroke = colorless ? [0, 0, 0] : extended ? strokes[index].extended : strokes[index].sRGB
                    if drawing.fill {
                        let coverage = Rasterizer.fill(subpaths(drawing.pagePath).map { $0.points.map(pixel) }, width: width, height: height, evenOdd: drawing.evenOdd)
                        paint(coverage, clips: drawing.clips, softMask: drawing.softMask, rgb: fill, alpha: drawing.settings.alpha, on: &canvas,
                              pattern: colorless ? nil : drawing.color.pattern)
                    }
                    if drawing.stroke {
                        let line = drawing.line
                        let matrix = drawing.matrix ?? PDFPage.Matrix()
                        // A zero width is the thinnest line the device draws: one pixel (`strokes` zero-width).
                        let pixelWidth = 1 / (max(scaleX, scaleY) * max(abs(matrix.a * matrix.d - matrix.b * matrix.c).squareRoot(), 1e-9))
                        let outline = SVGStroke.outline(subpaths(drawing.path).map { (points: $0.points.map { SVGImage.Point(x: $0.x, y: $0.y) }, closed: $0.closed) },
                                                        width: line.width > 0 ? line.width : pixelWidth, cap: ["butt", "round", "square"][min(max(line.cap, 0), 2)],
                                                        join: ["miter", "round", "bevel"][min(max(line.join, 0), 2)], miterLimit: line.miterLimit)
                        let polygons = outline.map { $0.map { pixel(matrix.apply($0.x, $0.y)) } }
                        paint(Rasterizer.fill(polygons, width: width, height: height, evenOdd: false), clips: drawing.clips, softMask: drawing.softMask,
                              rgb: stroke, alpha: drawing.strokeSettings.alpha, on: &canvas, pattern: colorless ? nil : drawing.strokeColor.pattern)
                    }
                }
            }
        }
        draw(page.items, on: &canvas)
        return canvas
    }

    /// A path's subpaths as points, curves flattened into 16 segments.
    static func subpaths(_ path: PDFPage.Path) -> [(points: [PDFPage.Point], closed: Bool)] {
        var result: [(points: [PDFPage.Point], closed: Bool)] = []
        var current: [PDFPage.Point] = []
        for element in path.elements {
            switch element {
            case .move(let point):
                if current.count > 1 { result.append((current, false)) }
                current = [point]
            case .line(let point):
                current.append(point)
            case .curve(let a, let b, let point):
                guard let start = current.last else { continue }
                for step in 1...16 {
                    let t = Double(step) / 16, u = 1 - t
                    current.append(PDFPage.Point(x: u * u * u * start.x + 3 * u * u * t * a.x + 3 * u * t * t * b.x + t * t * t * point.x,
                                                 y: u * u * u * start.y + 3 * u * u * t * a.y + 3 * u * t * t * b.y + t * t * t * point.y))
                }
            case .close:
                if current.count > 1 { result.append((current, true)) }
                current = current.first.map { [$0] } ?? []
            }
        }
        if current.count > 1 { result.append((current, false)) }
        return result
    }
}
