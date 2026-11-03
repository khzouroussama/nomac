import Foundation
import NomacCore

/// What a PDF page's content draws, as Quartz keeps it when it writes the page again
/// (`QuartzPDF`): each fill or stroke with its path, colors, settings and the clips in force.
/// Operators that paint nothing are dropped, as Quartz drops them (`pdf_experiments.py`: marked
/// content, comments, settings a drawing does not use, empty paths, malformed operands).
struct PDFPage {
    struct Point: Equatable { var x, y: Double }

    struct Rect: Equatable {
        var minX, minY, maxX, maxY: Double

        func intersection(_ other: Rect) -> Rect {
            let minX = max(self.minX, other.minX), minY = max(self.minY, other.minY)
            return Rect(minX: minX, minY: minY, maxX: max(minX, min(maxX, other.maxX)), maxY: max(minY, min(maxY, other.maxY)))
        }

        func union(_ other: Rect) -> Rect {
            Rect(minX: min(minX, other.minX), minY: min(minY, other.minY), maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
        }

        var isEmpty: Bool { minX >= maxX || minY >= maxY }

        /// The bounding box of the rectangle's corners after `matrix`.
        func applying(_ matrix: Matrix) -> Rect {
            let corners = [matrix.apply(minX, minY), matrix.apply(maxX, minY), matrix.apply(maxX, maxY), matrix.apply(minX, maxY)]
            return Rect(minX: corners.map(\.x).min()!, minY: corners.map(\.y).min()!, maxX: corners.map(\.x).max()!, maxY: corners.map(\.y).max()!)
        }
    }

    enum Element: Equatable {
        case move(Point)
        case line(Point)
        case curve(Point, Point, Point)
        case close
    }

    struct Path: Equatable {
        var elements: [Element] = []
        /// Made by `re` under a transformation that flips, which Quartz writes element by element
        /// (`rect-forms`: fill-re-flipped, evenodd-re-flipped; nextcloud's icons).
        var flippedRectangle = false

        init(elements: [Element] = [], flippedRectangle: Bool = false) {
            self.elements = elements
            self.flippedRectangle = flippedRectangle
        }

        /// A rectangle's path from its first corner counterclockwise.
        init(rectangle: Rect) {
            elements = [.move(Point(x: rectangle.minX, y: rectangle.minY)), .line(Point(x: rectangle.maxX, y: rectangle.minY)),
                        .line(Point(x: rectangle.maxX, y: rectangle.maxY)), .line(Point(x: rectangle.minX, y: rectangle.maxY)), .close]
        }

        func applying(_ matrix: Matrix) -> Path {
            Path(elements: elements.map { element -> Element in
                switch element {
                case .move(let p): .move(matrix.apply(p.x, p.y))
                case .line(let p): .line(matrix.apply(p.x, p.y))
                case .curve(let a, let b, let p): .curve(matrix.apply(a.x, a.y), matrix.apply(b.x, b.y), matrix.apply(p.x, p.y))
                case .close: .close
                }
            }, flippedRectangle: flippedRectangle)
        }

        /// The smallest rectangle around the path, curves by their extremes (`groups-2`
        /// curve-bounds: a form's `/BBox` around a curve).
        var bounds: Rect? {
            var points: [Point] = []
            var current: Point?
            for element in elements {
                switch element {
                case .move(let point), .line(let point):
                    points.append(point)
                    current = point
                case .curve(let a, let b, let end):
                    if let start = current {
                        points.append(end)
                        for t in Self.extremes(start.x, a.x, b.x, end.x) + Self.extremes(start.y, a.y, b.y, end.y) {
                            let u = 1 - t
                            points.append(Point(x: u * u * u * start.x + 3 * u * u * t * a.x + 3 * u * t * t * b.x + t * t * t * end.x,
                                                y: u * u * u * start.y + 3 * u * u * t * a.y + 3 * u * t * t * b.y + t * t * t * end.y))
                        }
                    }
                    current = end
                case .close: break
                }
            }
            guard let first = points.first else { return nil }
            return points.dropFirst().reduce(Rect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)) {
                $0.union(Rect(minX: $1.x, minY: $1.y, maxX: $1.x, maxY: $1.y))
            }
        }

        /// The smallest rectangle around the path's points, curves' control points included.
        var controlBounds: Rect? {
            let points = elements.flatMap { element -> [Point] in
                switch element {
                case .move(let point), .line(let point): [point]
                case .curve(let a, let b, let point): [a, b, point]
                case .close: []
                }
            }
            guard let first = points.first else { return nil }
            return points.dropFirst().reduce(Rect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)) {
                $0.union(Rect(minX: $1.x, minY: $1.y, maxX: $1.x, maxY: $1.y))
            }
        }

        /// The parameters in (0, 1) where a cubic's coordinate has a zero derivative.
        private static func extremes(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> [Double] {
            let a = -p0 + 3 * p1 - 3 * p2 + p3, b = 2 * (p0 - 2 * p1 + p2), c = p1 - p0
            let roots: [Double]
            if abs(a) < 1e-12 {
                roots = abs(b) < 1e-12 ? [] : [-c / b]
            } else {
                let discriminant = b * b - 4 * a * c
                guard discriminant >= 0 else { return [] }
                roots = [(-b + discriminant.squareRoot()) / (2 * a), (-b - discriminant.squareRoot()) / (2 * a)]
            }
            return roots.filter { $0 > 0 && $0 < 1 }
        }

        /// The rectangle the path is when it is exactly one closed, axis-aligned four-sided
        /// subpath (`re`, or `m` and three `l`, or four back to the start, then `h`, in either
        /// direction), which Quartz writes as `re` (`details`: rect-as-lines, rect-reversed,
        /// rect-negative; `paths`: rotate; `rect-forms`).
        var rectangle: Rect? {
            var elements = elements
            if elements.count == 6, case .move(let start) = elements[0], elements[4] == .line(start) { elements.remove(at: 4) }
            guard !flippedRectangle, elements.count == 5, case .move(let a) = elements[0], case .line(let b) = elements[1], case .line(let c) = elements[2],
                  case .line(let d) = elements[3], elements[4] == .close else { return nil }
            let horizontalFirst = a.y == b.y && b.x == c.x && c.y == d.y && d.x == a.x
            let verticalFirst = a.x == b.x && b.y == c.y && c.x == d.x && d.y == a.y
            guard horizontalFirst || verticalFirst else { return nil }
            return Rect(minX: min(a.x, c.x), minY: min(a.y, c.y), maxX: max(a.x, c.x), maxY: max(a.y, c.y))
        }
    }

    /// A clip, by the operation that made it: two clips with the same path are two clips, so a
    /// block per clip operation (corpus: cwa's `Icons - Close - Dark - Tap.pdf`, Quartz-written,
    /// restores and sets the same clip again and keeps two blocks).
    struct Clip: Equatable {
        var path: Path
        var evenOdd: Bool
        var serial: Int
        /// Whether Quartz writes it: a rectangle around the rectangles in force changes nothing
        /// and is not, but still bounds a group's `/BBox`.
        var written = true
    }

    /// The color spaces Quartz writes as ICC-based ones: DeviceRGB through an sRGB profile and
    /// DeviceGray through a gray one, and an ICCBased space with its own profile, one space for
    /// all copies of a profile (`colors`, `icc`); DeviceCMYK stays as it is.
    enum ColorSpace: Equatable, Sendable {
        case rgb, gray
        case icc(profile: [UInt8], components: Int)
        /// A transparency group's space when it names none: Quartz writes its Generic RGB profile
        /// (`groups`), nomac its own sRGB one (ADR 0204).
        case genericRGB
        /// A luminosity mask's group space: a space of its own beside the one it names, their
        /// object shared (`smasks-2` gray, rgb; `smasks-3`).
        indirect case maskGroup(ColorSpace)

        /// The space a mask group's space stands for, any other space itself.
        var plain: ColorSpace {
            if case .maskGroup(let space) = self { return space }
            return self
        }

        var profile: (components: Int, alternate: String, data: [UInt8]) {
            switch self {
            case .rgb, .genericRGB: (3, "/DeviceRGB", QuartzPDF.deflate(PDFProfiles.sRGB))
            case .gray: (1, "/DeviceGray", QuartzPDF.deflate(PDFProfiles.gray))
            case .icc(let profile, let components):
                (components, components == 1 ? "/DeviceGray" : components == 3 ? "/DeviceRGB" : "/DeviceCMYK", QuartzPDF.deflate(profile))
            case .maskGroup(let space): space.profile
            }
        }

        var components: Int {
            switch self {
            case .rgb, .genericRGB: 3
            case .gray: 1
            case .icc(_, let components): components
            case .maskGroup(let space): space.components
            }
        }
    }

    struct Color: Equatable {
        /// `nil` for DeviceCMYK and patterns.
        var space: ColorSpace?
        var components: [Double]
        var pattern: Pattern?

        static let black = Color(space: .gray, components: [0])

        static func == (left: Color, right: Color) -> Bool {
            left.space == right.space && left.components == right.components && left.pattern?.key == right.pattern?.key
        }
    }

    /// What a fill is drawn with besides its color: the opacity, fill overprinting and its
    /// mode, the smoothness and the rendering intent.
    struct Settings: Equatable {
        var alpha = 1.0
        var overprint = false
        var overprintMode = 0
        var smoothness = 0.0
        var renderingIntent = "RelativeColorimetric"
    }

    /// What a stroke is drawn with besides its color and line: its opacity, overprinting and adjustment.
    struct StrokeSettings: Equatable {
        var alpha = 1.0
        var overprint = false
        /// Written after the line, before the rendering intent (`strokes-2`).
        var adjust = false
    }

    /// The line a stroke draws: width, cap, join, miter limit and dash.
    struct Line: Equatable {
        var width = 1.0
        var cap = 0
        var join = 0
        var miterLimit = 10.0
        var dash: [Double] = []
        var phase = 0.0
    }

    /// A fill, a stroke or both. A drawing that strokes under a transformation other than the
    /// identity keeps its path in user space with `matrix`, which Quartz writes as `cm`; any other
    /// has its path in page coordinates (`strokes`: scaled, translated, rotated, fill-stroke-scaled).
    struct Drawing {
        var path: Path
        var matrix: Matrix?
        var fill: Bool
        var stroke: Bool
        var evenOdd: Bool
        var color: Color
        var settings: Settings
        var strokeColor: Color
        var strokeSettings: StrokeSettings
        var line: Line
        var clips: [Clip]
        var softMask: SoftMask?

        /// The path in page coordinates.
        var pagePath: Path { matrix.map(path.applying) ?? path }

        /// The area Quartz counts the drawing in for a form's `/BBox`: a fill's path; a stroke's
        /// grown by half its width times the miter limit for miter joins (at least 2), times 2
        /// otherwise, before its transformation; `nil`, everywhere, for a zero width (`groups-3`).
        var bounds: Rect? {
            guard stroke else { return pagePath.bounds }
            guard line.width > 0, let box = path.bounds else { return nil }
            let grow = line.width / 2 * (line.join == 0 ? max(line.miterLimit, 2) : 2)
            let grown = Rect(minX: box.minX - grow, minY: box.minY - grow, maxX: box.maxX + grow, maxY: box.maxY + grow)
            return matrix.map(grown.applying) ?? grown
        }
    }

    /// A drawing, a transparency group Quartz keeps as a form of its own (`groups`) or an image.
    indirect enum Item {
        case drawing(Drawing)
        case group(Group)
        case image(Image)
        case shading(ShadingFill)
        case text(TextRun)

        /// A drawing's paths and paint, or a text's glyphs as one.
        var drawing: Drawing? {
            switch self {
            case .drawing(let drawing): drawing
            case .text(let run): run.drawing
            case .group, .image, .shading: nil
            }
        }
    }

    /// Text shown in an embedded TrueType font (`fonts`): the font's key in ``fonts``, the glyphs
    /// with the space each puts after the previous one's advance in the font, in ems, the
    /// matrix of the first glyph's em in the user space of `drawing.matrix`, the rendering mode
    /// (0 to 3), and the glyphs' outlines as a drawing.
    struct TextRun {
        struct Glyph {
            var glyph: Int
            var name: String?
            var unicode: [UInt16]
            var gap: Double
        }

        var font: Int
        var glyphs: [Glyph]
        var matrix: Matrix
        var mode: Int
        var drawing: Drawing
    }

    /// An image's samples as Quartz keeps them: the filters undone, `space` `nil` for a stencil
    /// mask, which paints the fill color where a sample is 0; a JPEG's bytes kept as they are.
    struct Samples {
        var width: Int
        var height: Int
        var bitsPerComponent: Int
        var space: ColorSpace?
        var data: [UInt8]
        var decode: [Double]?
        var interpolate: Bool
        var jpeg: [UInt8]?
        /// The image's own `/Intent`, which Quartz keeps (`images-2` intent-entry).
        var intent: String? = nil
    }

    /// An image XObject where it is drawn: the object (`key`, its number), its samples and soft
    /// mask, the transformation from the unit square, the clips, the opacity and, for a stencil
    /// mask, the fill color.
    struct Image {
        var key: Int
        var samples: Samples
        var mask: Samples?
        var matrix: Matrix
        var clips: [Clip]
        var alpha: Double
        var softMask: SoftMask?
        var color: Color
        var renderingIntent: String
        var overprint: Bool
        var overprintMode: Int
    }

    /// A transparency group: its items in page coordinates, the clips in force and the opacity
    /// and overprinting where it is drawn, its color space and its bounds, the form's `/BBox`.
    struct Group {
        var items: [Item]
        var clips: [Clip]
        var alpha: Double
        var softMask: SoftMask?
        var space: ColorSpace
        var bounds: Rect
        var overprint: Bool
        var overprintMode: Int
    }

    /// A soft mask: its content, box and matrix; for a luminosity mask its group's space and
    /// backdrop, for any its transfer function.
    struct SoftMask {
        var serial: Int
        var items: [Item]
        var box: Rect
        var matrix: Matrix
        var luminosity: (space: ColorSpace, backdrop: [Double])?
        var transfer: Function?
    }

    var box: Rect
    var items: [Item] = []
    /// The embedded fonts text items show, by key.
    var fonts: [Int: PDFFontProgram] = [:]
    private var clipSerial = 0

    /// Every drawing, those in groups included, in drawing order.
    var drawings: [Drawing] { Self.drawings(items) }

    static func drawings(_ items: [Item]) -> [Drawing] {
        items.flatMap { item -> [Drawing] in
            switch item {
            case .drawing(let drawing): [drawing]
            case .text(let run): [run.drawing]
            case .group(let group): drawings(group.items)
            case .image, .shading: []
            }
        }
    }

    /// Items moved by `matrix`: their paths, clips, images and masks.
    static func transformed(_ items: [Item], by matrix: Matrix) -> [Item] {
        func clips(_ clips: [Clip]) -> [Clip] { clips.map { Clip(path: $0.path.applying(matrix), evenOdd: $0.evenOdd, serial: $0.serial) } }
        func mask(_ mask: SoftMask?) -> SoftMask? {
            mask.map { SoftMask(serial: $0.serial, items: $0.items, box: $0.box, matrix: $0.matrix.concatenating(matrix), luminosity: $0.luminosity, transfer: $0.transfer) }
        }
        return items.map { item -> Item in
            switch item {
            case .drawing(var drawing):
                if let own = drawing.matrix { drawing.matrix = own.concatenating(matrix) } else { drawing.path = drawing.path.applying(matrix) }
                drawing.clips = clips(drawing.clips)
                drawing.softMask = mask(drawing.softMask)
                return .drawing(drawing)
            case .text(var run):
                guard case .drawing(let drawing) = transformed([.drawing(run.drawing)], by: matrix)[0] else { return item }
                run.drawing = drawing
                return .text(run)
            case .group(var group):
                group.items = transformed(group.items, by: matrix)
                group.clips = clips(group.clips)
                group.softMask = mask(group.softMask)
                return .group(group)
            case .image(var image):
                image.matrix = image.matrix.concatenating(matrix)
                image.clips = clips(image.clips)
                image.softMask = mask(image.softMask)
                return .image(image)
            case .shading(var fill):
                fill.matrix = fill.matrix.concatenating(matrix)
                fill.clips = clips(fill.clips)
                fill.softMask = mask(fill.softMask)
                return .shading(fill)
            }
        }
    }

    /// Every image, those in groups included, in drawing order.
    static func images(_ items: [Item]) -> [Image] {
        items.flatMap { item -> [Image] in
            switch item {
            case .drawing, .shading, .text: []
            case .group(let group): images(group.items)
            case .image(let image): [image]
            }
        }
    }
    /// The Info entries Quartz carries over: a non-empty `Producer` and a valid `CreationDate`
    /// in UTC as `YYYYMMDDHHmmSS` (`info`).
    var producer: String?
    var creationDate: String?
    /// The trailer's two identifiers, which Quartz keeps when the file has an Info dictionary and
    /// both are 16 bytes (`ids`: hex-equal-info, hex-different-info, info-empty; zeros otherwise).
    var identifiers: ([UInt8], [UInt8])?

    struct Matrix: Equatable {
        var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

        var isIdentity: Bool { self == Matrix() }

        func apply(_ x: Double, _ y: Double) -> Point { Point(x: a * x + c * y + e, y: b * x + d * y + f) }

        var inverted: Matrix? {
            let determinant = a * d - b * c
            guard abs(determinant) > 1e-12 else { return nil }
            return Matrix(a: d / determinant, b: -b / determinant, c: -c / determinant, d: a / determinant,
                          e: (c * f - d * e) / determinant, f: (b * e - a * f) / determinant)
        }

        /// `self` applied first, then `other`.
        func concatenating(_ other: Matrix) -> Matrix {
            Matrix(a: a * other.a + b * other.c, b: a * other.b + b * other.d, c: c * other.a + d * other.c, d: c * other.b + d * other.d,
                   e: e * other.a + f * other.c + other.e, f: e * other.b + f * other.d + other.f)
        }
    }

    private struct State {
        var matrix = Matrix()
        /// `nil` for DeviceCMYK.
        var fillSpace: ColorSpace? = .gray
        var fillPatterns = false
        var fillColor = Color.black
        var settings = Settings()
        var strokeSpace: ColorSpace? = .gray
        var strokePatterns = false
        var strokeColor = Color.black
        var strokeSettings = StrokeSettings()
        var line = Line()
        var clips: [Clip] = []
        var text = TextState()
        var softMask: SoftMask?
        /// Clipped to a path without area: nothing drawn shows.
        var clippedOut = false
        /// Inside a transparency group, where Quartz draws shadings with the perceptual intent.
        var inGroup = false
    }

    /// The text state `q` saves: the font and its key, the rendering mode, the size, character and
    /// word spacing, horizontal scaling, leading and rise.
    private struct TextState {
        var font: [String: PDFValue]?
        var fontKey = 0
        var mode = 0
        var size = 0.0
        var characterSpacing = 0.0
        var wordSpacing = 0.0
        var scale = 1.0
        var leading = 0.0
        var rise = 0.0
    }

    init(file: PDFFile) throws {
        let page = try file.firstPage()
        let path = file.path
        guard let box = (file.resolve(page["CropBox"])?.array ?? file.resolve(page["MediaBox"])?.array)?.compactMap(file.number)
            .map(PDFLexer.contentReading), box.count == 4 else {
            throw NomacError("the PDF's page has no MediaBox", path: path)
        }
        self.box = Rect(minX: min(box[0], box[2]), minY: min(box[1], box[3]), maxX: max(box[0], box[2]), maxY: max(box[1], box[3]))
        let resources = file.resolve(page["Resources"])?.dictionary ?? [:]
        var content: [UInt8] = []
        for stream in file.resolve(page["Contents"]).map({ $0.array ?? [$0] }) ?? [] {
            guard let value = file.resolve(stream) else { continue }
            content += try file.decodedStream(value) + [10]
        }
        try interpret(content, resources: resources, file: file)
        if let number = file.info, let info = file.resolve(.reference(number))?.dictionary {
            if case .string(let bytes)? = file.resolve(info["Producer"]) {
                let text = Self.text(bytes)
                producer = text.isEmpty ? nil : text
            }
            if case .string(let bytes)? = file.resolve(info["CreationDate"]) { creationDate = Self.utcDate(bytes) }
            if let ids = file.identifiers, ids.count == 2, case .string(let first) = ids[0], case .string(let second) = ids[1],
               first.count == 16, second.count == 16 {
                identifiers = (first, second)
            }
        }
    }

    /// A PDF text string: UTF-16BE after its byte order mark, otherwise one character per byte.
    static func text(_ bytes: [UInt8]) -> String {
        if bytes.starts(with: [0xFE, 0xFF]) {
            let units = stride(from: 2, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
            return String(decoding: units, as: UTF16.self)
        }
        return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    /// A date `D:YYYY[MM[DD[HH[mm[SS[Z|+HH'mm'|-HH'mm']]]]]]` in UTC as `YYYYMMDDHHmmSS`, the
    /// missing fields their least values and no offset meaning UTC (`info`: date-short,
    /// date-local, date-offset, date-negative); `nil` when it is not such a date.
    static func utcDate(_ bytes: [UInt8]) -> String? {
        var text = Substring(String(decoding: bytes, as: UTF8.self))
        if text.hasPrefix("D:") { text = text.dropFirst(2) }
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        guard digits.count >= 4, digits.count <= 14, digits.count % 2 == 0 else { return nil }
        let padded = Array(digits) + Array("0101000000".suffix(14 - digits.count))
        let field = { (start: Int, length: Int) in Int(String(padded[start..<start + length]))! }
        var components = DateComponents(timeZone: TimeZone(identifier: "UTC"), year: field(0, 4), month: field(4, 2), day: field(6, 2),
                                        hour: field(8, 2), minute: field(10, 2), second: field(12, 2))
        var rest = text.dropFirst(digits.count)
        // An offset counts written `HH'` or `HH'mm'`; otherwise the time is taken as UTC (`info`:
        // date-offset-open, -hours, -bare, -hours-quote; cairo writes `+02'00`).
        if let sign = rest.first, sign == "+" || sign == "-", let hours = Int(rest.dropFirst().prefix(2)), rest.dropFirst(3).first == "'" {
            rest = rest.dropFirst(4)
            let minutes = Int(rest.prefix(2))
            if minutes == nil || rest.dropFirst(2).first == "'" {
                components.minute = (components.minute ?? 0) + (hours * 60 + (minutes ?? 0)) * (sign == "+" ? -1 : 1)
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: components) else { return nil }
        let utc = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02d%02d%02d%02d", utc.year!, utc.month!, utc.day!, utc.hour!, utc.minute!, utc.second!)
    }

    private mutating func interpret(_ content: [UInt8], resources: [String: PDFValue], file: PDFFile, state initial: State = State(), depth: Int = 0) throws {
        var lexer = PDFLexer(data: content, path: file.path)
        var operands: [PDFLexer.Token] = []
        var state = initial
        var stack: [State] = []
        var current = Path()
        var currentPoint: Point?
        var subpathStart: Point?
        var pendingClip: Bool?
        let unsupported: [String: String] = [
            "BI": "inline images",
        ]
        var lastArray: [Double] = []
        var lastArrayItems: [PDFLexer.Token] = []
        var textMatrix = Matrix(), lineMatrix = Matrix()
        func number(_ token: PDFLexer.Token) -> Double? {
            switch token {
            case .integer(let value): Double(value)
            case .real(let value, _): value
            default: nil
            }
        }
        /// The operands from `start` on when they are `count` numbers.
        func numbers(_ count: Int, from start: Int = 0) -> [Double]? {
            guard operands.count == start + count else { return nil }
            let values = operands[start...].compactMap(number)
            return values.count == count ? values : nil
        }
        func point(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }
        while let token = try lexer.token() {
            guard case .keyword(let op) = token else {
                if token == .arrayStart || token == .dictionaryStart {
                    // An array (a dash's, a `TJ`'s) is kept by its numbers and strings;
                    // dictionaries are operands of operators Quartz drops (`BDC`).
                    var depth = 1
                    lastArray = []
                    lastArrayItems = []
                    while depth > 0, let next = try lexer.token() {
                        if next == .arrayStart || next == .dictionaryStart { depth += 1 }
                        if next == .arrayEnd || next == .dictionaryEnd { depth -= 1 }
                        guard depth == 1 else { continue }
                        if let value = number(next) { lastArray.append(value) }
                        switch next {
                        case .integer, .real, .string: lastArrayItems.append(next)
                        default: break
                        }
                    }
                    operands.append(.keyword("[]"))
                } else {
                    operands.append(token)
                }
                continue
            }
            defer { operands.removeAll() }
            if let feature = unsupported[op] {
                throw NomacError("PDF images with \(feature) are not supported yet (BACKLOG B-215)", path: file.path)
            }
            switch op {
            case "q": stack.append(state)
            case "Q": if let saved = stack.popLast() { state = saved }
            case "cm":
                guard let v = numbers(6) else { continue }
                state.matrix = Matrix(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4], f: v[5]).concatenating(state.matrix)
            case "m":
                guard let v = numbers(2) else { continue }
                let p = point(v[0], v[1])
                current.elements.append(.move(p))
                currentPoint = p
                subpathStart = p
            case "l":
                guard let v = numbers(2), currentPoint != nil else { continue }
                let p = point(v[0], v[1])
                current.elements.append(.line(p))
                currentPoint = p
            case "c":
                guard let v = numbers(6), currentPoint != nil else { continue }
                let p = point(v[4], v[5])
                current.elements.append(.curve(point(v[0], v[1]), point(v[2], v[3]), p))
                currentPoint = p
            case "v":
                guard let v = numbers(4), let start = currentPoint else { continue }
                let p = point(v[2], v[3])
                current.elements.append(.curve(start, point(v[0], v[1]), p))
                currentPoint = p
            case "y":
                guard let v = numbers(4), currentPoint != nil else { continue }
                let p = point(v[2], v[3])
                current.elements.append(.curve(point(v[0], v[1]), p, p))
                currentPoint = p
            case "h":
                guard currentPoint != nil else { continue }
                current.elements.append(.close)
                currentPoint = subpathStart
            case "re":
                guard let v = numbers(4) else { continue }
                let start = point(v[0], v[1])
                current.elements += [.move(start), .line(point(v[0] + v[2], v[1])), .line(point(v[0] + v[2], v[1] + v[3])),
                                     .line(point(v[0], v[1] + v[3])), .close]
                if state.matrix.a * state.matrix.d - state.matrix.b * state.matrix.c < 0 { current.flippedRectangle = true }
                currentPoint = start
                subpathStart = start
            case "W", "W*": pendingClip = op == "W*"
            case "n", "f", "F", "f*", "S", "s", "B", "B*", "b", "b*":
                if ["s", "b", "b*"].contains(op), currentPoint != nil { current.elements.append(.close) }
                let painted = Self.quartzPath(current)
                let pagePath = painted.applying(state.matrix)
                let fill = ["f", "F", "f*", "B", "B*", "b", "b*"].contains(op), stroke = ["S", "s", "B", "B*", "b", "b*"].contains(op)
                if fill || stroke, !painted.elements.isEmpty, !state.clippedOut {
                    let keepsMatrix = stroke && !state.matrix.isIdentity
                    items.append(.drawing(Drawing(path: keepsMatrix ? painted : pagePath, matrix: keepsMatrix ? state.matrix : nil, fill: fill, stroke: stroke,
                                                  evenOdd: ["f*", "B*", "b*"].contains(op), color: state.fillColor, settings: state.settings,
                                                  strokeColor: state.strokeColor, strokeSettings: state.strokeSettings, line: state.line, clips: state.clips,
                                                  softMask: state.softMask)))
                }
                if let evenOdd = pendingClip, !painted.elements.isEmpty {
                    if let bounds = pagePath.bounds, bounds.maxX > bounds.minX, bounds.maxY > bounds.minY {
                        clipSerial += 1
                        state.clips.append(Clip(path: pagePath, evenOdd: evenOdd, serial: clipSerial, written: Self.clipChanges(pagePath, clips: state.clips)))
                    } else {
                        state.clippedOut = true
                    }
                }
                pendingClip = nil
                current = Path()
                currentPoint = nil
            case "rg", "g", "k", "RG", "G", "K":
                let kind = op.lowercased()
                guard let v = numbers(kind == "rg" ? 3 : kind == "g" ? 1 : 4) else { continue }
                let space: ColorSpace? = kind == "rg" ? .rgb : kind == "g" ? .gray : nil
                if op == kind {
                    (state.fillSpace, state.fillColor) = (space, Color(space: space, components: v))
                } else {
                    (state.strokeSpace, state.strokeColor) = (space, Color(space: space, components: v))
                }
            case "cs", "CS":
                guard operands.count == 1, case .name(let name) = operands[0] else { continue }
                let resource = file.resolve(file.resolve(resources["ColorSpace"])?.dictionary?[name])
                if name == "Pattern" || resource?.name == "Pattern" || resource?.array?.first?.name == "Pattern" {
                    if op == "cs" { state.fillPatterns = true } else { state.strokePatterns = true }
                    continue
                }
                let space = try Self.colorSpace(name, resources: resources, file: file)
                let count = space?.components ?? 4
                let initial = Color(space: space, components: count == 4 ? [0, 0, 0, 1] : [Double](repeating: 0, count: count))
                if op == "cs" {
                    (state.fillSpace, state.fillColor, state.fillPatterns) = (space, initial, false)
                } else {
                    (state.strokeSpace, state.strokeColor, state.strokePatterns) = (space, initial, false)
                }
            case "sc", "scn":
                if state.fillPatterns {
                    guard case .name(let name)? = operands.last else { continue }
                    state.fillColor = Color(space: nil, components: [], pattern: try pattern(name, state: state, resources: resources, file: file))
                    continue
                }
                guard let v = numbers(state.fillSpace?.components ?? 4) else { continue }
                state.fillColor = Color(space: state.fillSpace, components: v)
            case "SC", "SCN":
                if state.strokePatterns {
                    guard case .name(let name)? = operands.last else { continue }
                    state.strokeColor = Color(space: nil, components: [], pattern: try pattern(name, state: state, resources: resources, file: file))
                    continue
                }
                guard let v = numbers(state.strokeSpace?.components ?? 4) else { continue }
                state.strokeColor = Color(space: state.strokeSpace, components: v)
            case "sh":
                guard !state.clippedOut, operands.count == 1, case .name(let name) = operands[0], let entry = file.resolve(resources["Shading"])?.dictionary?[name],
                      let value = file.resolve(entry) else { continue }
                let key: Int
                if case .reference(let number) = entry { key = number } else { key = -clip(Path()).serial }
                items.append(.shading(ShadingFill(shading: try Shading.read(value, key: key, file: file, resources: resources), matrix: state.matrix,
                                                  clips: state.clips, alpha: state.settings.alpha, softMask: state.softMask,
                                                  renderingIntent: state.inGroup ? "Perceptual" : state.settings.renderingIntent,
                                                  overprint: state.settings.overprint,
                                                  overprintMode: state.settings.overprintMode)))
            case "w": if let v = numbers(1) { state.line.width = v[0] }
            case "J": if let v = numbers(1) { state.line.cap = Int(v[0]) }
            case "j": if let v = numbers(1) { state.line.join = Int(v[0]) }
            case "M": if let v = numbers(1) { state.line.miterLimit = v[0] }
            case "d":
                guard operands.count == 2, case .keyword("[]") = operands[0], let phase = numbers(1, from: 1) else { continue }
                state.line.dash = lastArray
                state.line.phase = phase[0]
            case "gs":
                guard operands.count == 1, case .name(let name) = operands[0],
                      let parameters = file.resolve(file.resolve(resources["ExtGState"])?.dictionary?[name])?.dictionary else { continue }
                try Self.checkExtGState(parameters, file: file)
                if let alpha = file.number(parameters["ca"]) { state.settings.alpha = alpha }
                if let alpha = file.number(parameters["CA"]) { state.strokeSettings.alpha = alpha }
                if case .bool(let adjust)? = file.resolve(parameters["SA"]) { state.strokeSettings.adjust = adjust }
                if case .bool(let overprint)? = file.resolve(parameters["OP"]) { state.strokeSettings.overprint = overprint }
                if let width = file.number(parameters["LW"]) { state.line.width = width }
                if let cap = file.number(parameters["LC"]) { state.line.cap = Int(cap) }
                if let join = file.number(parameters["LJ"]) { state.line.join = Int(join) }
                if let limit = file.number(parameters["ML"]) { state.line.miterLimit = limit }
                if case .bool(let overprint)? = file.resolve(parameters["op"] ?? parameters["OP"]) { state.settings.overprint = overprint }
                if let mode = file.number(parameters["OPM"]) { state.settings.overprintMode = Int(mode) }
                if let smoothness = file.number(parameters["SM"]) { state.settings.smoothness = smoothness }
                if let intent = file.resolve(parameters["RI"])?.name { state.settings.renderingIntent = intent }
                if let mask = file.resolve(parameters["SMask"]) {
                    state.softMask = try softMask(mask, matrix: state.matrix, file: file, depth: depth)
                }
            case "Do":
                guard !state.clippedOut, operands.count == 1, case .name(let name) = operands[0], let entry = file.resolve(resources["XObject"])?.dictionary?[name],
                      let xobject = file.resolve(entry), let dictionary = xobject.dictionary else { continue }
                if dictionary["Subtype"]?.name == "Image" {
                    let key: Int
                    if case .reference(let number) = entry { key = number } else { key = -clip(Path()).serial }
                    items.append(.image(Image(key: key, samples: try Self.samples(xobject, file: file, resources: resources),
                                              mask: try file.resolve(dictionary["SMask"]).map { try Self.softMask($0, file: file) },
                                              matrix: state.matrix, clips: state.clips, alpha: state.settings.alpha, softMask: state.softMask,
                                              color: state.fillColor, renderingIntent: state.settings.renderingIntent,
                                              overprint: state.settings.overprint, overprintMode: state.settings.overprintMode)))
                } else {
                    try drawForm(xobject, dictionary, resources: resources, file: file, state: state, depth: depth)
                }
            case "ri":
                guard operands.count == 1, case .name(let intent) = operands[0] else { continue }
                state.settings.renderingIntent = intent
            case "BT":
                textMatrix = Matrix()
                lineMatrix = Matrix()
            case "Tf":
                guard operands.count == 2, case .name(let name) = operands[0], let size = number(operands[1]) else { continue }
                let entry = file.resolve(resources["Font"])?.dictionary?[name]
                state.text.font = file.resolve(entry)?.dictionary
                if case .reference(let number)? = entry { state.text.fontKey = number } else { state.text.fontKey = -clip(Path()).serial }
                state.text.size = size
            case "Tc": if let v = numbers(1) { state.text.characterSpacing = v[0] }
            case "Tr": if let v = numbers(1) { state.text.mode = Int(v[0]) }
            case "Tw": if let v = numbers(1) { state.text.wordSpacing = v[0] }
            case "Tz": if let v = numbers(1) { state.text.scale = v[0] / 100 }
            case "TL": if let v = numbers(1) { state.text.leading = v[0] }
            case "Ts": if let v = numbers(1) { state.text.rise = v[0] }
            case "Td", "TD":
                guard let v = numbers(2) else { continue }
                if op == "TD" { state.text.leading = -v[1] }
                lineMatrix = Matrix(e: v[0], f: v[1]).concatenating(lineMatrix)
                textMatrix = lineMatrix
            case "Tm":
                guard let v = numbers(6) else { continue }
                lineMatrix = Matrix(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4], f: v[5])
                textMatrix = lineMatrix
            case "T*", "'", "\"":
                if op == "\"", operands.count == 3, let spacing = numbers(2) {
                    (state.text.wordSpacing, state.text.characterSpacing) = (spacing[0], spacing[1])
                }
                lineMatrix = Matrix(f: -state.text.leading).concatenating(lineMatrix)
                textMatrix = lineMatrix
                guard op != "T*", case .string(let bytes)? = operands.last else { continue }
                try showText([.string(bytes)], matrix: &textMatrix, state: state, file: file, resources: resources, depth: depth)
            case "Tj":
                guard operands.count == 1, case .string = operands[0] else { continue }
                try showText(operands, matrix: &textMatrix, state: state, file: file, resources: resources, depth: depth)
            case "TJ":
                guard operands == [.keyword("[]")] else { continue }
                try showText(lastArrayItems, matrix: &textMatrix, state: state, file: file, resources: resources, depth: depth)
            default:
                // Flatness, marked content, compatibility sections and anything Quartz does not
                // know: nothing a drawing shows.
                break
            }
        }
    }

    /// A form XObject drawn in place: its content with its matrix applied and clipped by its
    /// bounding box, as Quartz writes it into the page (`xobjects`: form, form-matrix, form-cm,
    /// form-bbox-clip, form-twice, form-nested, form-in-clip). A transparency group stays a form
    /// in page coordinates, its content also clipped by the page and opaque until it sets an
    /// opacity, the opacity in force applying to the group as a whole, kept when it draws
    /// anything (`groups`, `groups-2`: ca-on-do, outside-bbox, empty).
    private mutating func drawForm(_ xobject: PDFValue, _ dictionary: [String: PDFValue], resources: [String: PDFValue], file: PDFFile,
                                   state: State, depth: Int) throws {
        switch dictionary["Subtype"]?.name {
        case "Form":
            guard depth < 16 else { throw NomacError("the PDF's forms are nested too deeply", path: file.path) }
            let space = try file.resolve(dictionary["Group"]).map { try Self.groupSpace($0, resources: resources, file: file) }
            var inner = state
            if let values = file.resolve(dictionary["Matrix"])?.array?.compactMap(file.number).map(PDFLexer.contentReading), values.count == 6 {
                inner.matrix = Matrix(a: values[0], b: values[1], c: values[2], d: values[3], e: values[4], f: values[5]).concatenating(state.matrix)
            }
            let values = file.resolve(dictionary["BBox"])?.array?.compactMap(file.number).map(PDFLexer.contentReading) ?? []
            let formBox = values.count == 4 ? Rect(minX: min(values[0], values[2]), minY: min(values[1], values[3]), maxX: max(values[0], values[2]),
                                                   maxY: max(values[1], values[3])) : nil
            let formResources = file.resolve(dictionary["Resources"])?.dictionary ?? resources
            guard let space else {
                if let formBox { inner.clips.append(clip(Path(rectangle: formBox).applying(inner.matrix))) }
                try interpret(try file.decodedStream(xobject), resources: formResources, file: file, state: inner, depth: depth + 1)
                return
            }
            guard let formBox else { throw NomacError("the PDF has a transparency group without a bounding box", path: file.path) }
            // Its content is clipped to one rectangle: the bounding box of the clips around the `Do`
            // and the form's bounding box, rounded out to whole units, within the page (`groups`
            // in-clip, `groups-2`: in-path-clip, in-two-clips, in-evenodd-clip, bbox-beyond-page;
            // corpus: kickstarter's `icon--apple-pay.pdf`, cwa's `Icons_Settings_Risikoermittlung.pdf`).
            let placed = formBox.applying(inner.matrix)
            var area = placed
            for outer in state.clips {
                guard let bounds = outer.path.bounds else { return }
                area = area.intersection(bounds)
            }
            inner.clips = [clip(Path(rectangle: box.intersection(Rect(minX: area.minX.rounded(.down), minY: area.minY.rounded(.down),
                                                                      maxX: area.maxX.rounded(.up), maxY: area.maxY.rounded(.up)))))]
            // Opaque inside, fill and stroke, but overprinting kept (`groups-4`: stroke-ca-stroke, op, opm).
            inner.settings.alpha = 1
            inner.strokeSettings.alpha = 1
            inner.softMask = nil
            // A shading in it is drawn with the perceptual intent, whatever the one set (`groups-6`).
            inner.inGroup = true
            let outer = items
            items = []
            try interpret(try file.decodedStream(xobject), resources: formResources, file: file, state: inner, depth: depth + 1)
            let content = items
            items = outer
            // Its `/BBox`: what it draws within the clips it sets and its own bounding box.
            let bounds = content.map { (Self.bounds($0, clippedFrom: 1) ?? placed).intersection(placed) }.filter { !$0.isEmpty }.reduce(nil) { $0?.union($1) ?? $1 }
            guard let bounds else { return }
            items.append(.group(Group(items: content, clips: state.clips, alpha: state.settings.alpha, softMask: state.softMask, space: space,
                                      bounds: bounds, overprint: state.settings.overprint, overprintMode: state.settings.overprintMode)))
        default:
            break
        }
    }

    /// A pattern color: a shading pattern, its matrix as given (`shadings`: pattern-fill,
    /// pattern-matrix, pattern-stroke); tiling patterns are not observed yet.
    private mutating func pattern(_ name: String, state: State, resources: [String: PDFValue], file: PDFFile) throws -> Pattern {
        guard let entry = file.resolve(resources["Pattern"])?.dictionary?[name], let dictionary = file.resolve(entry)?.dictionary else {
            throw NomacError("the PDF uses a pattern its resources do not have", path: file.path)
        }
        guard file.number(dictionary["PatternType"]) == 2, let shadingValue = file.resolve(dictionary["Shading"]) else {
            throw NomacError("PDF images with tiling patterns are not supported yet (BACKLOG B-215)", path: file.path)
        }
        guard dictionary["ExtGState"] == nil else {
            throw NomacError("PDF images with a shading pattern's ExtGState are not supported yet (BACKLOG B-215)", path: file.path)
        }
        let key: Int
        if case .reference(let number) = entry { key = number } else { key = -clip(Path()).serial }
        var shadingKey = -clip(Path()).serial
        if case .reference(let number)? = dictionary["Shading"] { shadingKey = number }
        let values = file.resolve(dictionary["Matrix"])?.array?.compactMap(file.number).map(PDFLexer.contentReading) ?? []
        return Pattern(key: key, shading: try Shading.read(shadingValue, key: shadingKey, file: file, resources: resources),
                       matrix: values.count == 6 ? Matrix(a: values[0], b: values[1], c: values[2], d: values[3], e: values[4], f: values[5]) : Matrix())
    }

    /// An ExtGState's `SMask`: `/None`, or an alpha or luminosity mask whose form has a
    /// transparency group (Quartz ignores one without, and a luminosity one whose group names no
    /// space: `smasks` no-group, `smasks-2` no-cs), its content read from the defaults in the
    /// form's space (`smasks`: fill, mask-matrix, under-cm, mask-bbox, mask-ca). A luminosity
    /// mask's group is in a gray or RGB space, its backdrop 0 unless given; a transfer function
    /// other than `/Identity` is kept (`smasks-2`, `smasks-3`).
    private mutating func softMask(_ value: PDFValue, matrix: Matrix, file: PDFFile, depth: Int) throws -> SoftMask? {
        guard let dictionary = value.dictionary else { return nil }
        let unsupported = NomacError("PDF images with soft masks of this kind are not supported yet (BACKLOG B-215)", path: file.path)
        let luminous = dictionary["S"]?.name == "Luminosity"
        guard luminous || dictionary["S"]?.name == "Alpha", luminous || dictionary["BC"] == nil else { throw unsupported }
        guard let form = file.resolve(dictionary["G"]), let entries = form.dictionary, let group = file.resolve(entries["Group"])?.dictionary else { return nil }
        var luminosity: (space: ColorSpace, backdrop: [Double])?
        if luminous {
            guard let value = file.resolve(group["CS"]) else { return nil }
            let space: ColorSpace?
            if case .name(let name) = value {
                space = try Self.colorSpace(name, resources: [:], file: file)
            } else {
                space = try Self.colorSpace("CS", resources: ["ColorSpace": .dictionary(["CS": value])], file: file)
            }
            guard let space, [1, 3].contains(space.components), space != .genericRGB else { throw unsupported }
            let backdrop = file.resolve(dictionary["BC"])?.array?.compactMap(file.number) ?? [Double](repeating: 0, count: space.components)
            guard backdrop.count == space.components else { throw unsupported }
            luminosity = (space, backdrop)
        }
        var transfer: Function?
        if let value = file.resolve(dictionary["TR"]), value != .name("Identity") {
            let function = try Function.read(value, file: file, outputs: 1)
            guard function.domain == [0, 1] else { throw unsupported }
            transfer = function
        }
        guard depth < 16 else { throw NomacError("the PDF's forms are nested too deeply", path: file.path) }
        let box = file.resolve(entries["BBox"])?.array?.compactMap(file.number).map(PDFLexer.contentReading) ?? []
        guard box.count == 4 else { throw NomacError("the PDF has a soft mask without a bounding box", path: file.path) }
        let values = file.resolve(entries["Matrix"])?.array?.compactMap(file.number).map(PDFLexer.contentReading) ?? []
        let formMatrix = values.count == 6 ? Matrix(a: values[0], b: values[1], c: values[2], d: values[3], e: values[4], f: values[5]) : Matrix()
        let outer = items
        items = []
        try interpret(try file.decodedStream(form), resources: file.resolve(entries["Resources"])?.dictionary ?? [:], file: file, depth: depth + 1)
        let content = items
        items = outer
        return SoftMask(serial: clip(Path()).serial, items: content, box: Rect(minX: box[0], minY: box[1], maxX: box[2], maxY: box[3]),
                        matrix: formMatrix.concatenating(matrix), luminosity: luminosity, transfer: transfer)
    }

    private mutating func clip(_ path: Path) -> Clip {
        clipSerial += 1
        return Clip(path: path, evenOdd: false, serial: clipSerial)
    }

    /// Text shown with a Type 3 font, which Quartz draws as its glyphs' content: each glyph's
    /// procedure run under the font matrix, the size, the horizontal scaling, the rise and the
    /// text matrix, its colors applied (`d0` or `d1`) and the rendering mode ignored, the text
    /// matrix moved by its width and the spacings, and by a `TJ` number's thousandths of the size
    /// (`text`: type3-*; corpus: Figma's empty glyphs draw nothing). Other fonts are refused.
    private mutating func showText(_ items: [PDFLexer.Token], matrix: inout Matrix, state: State, file: PDFFile, resources: [String: PDFValue],
                                   depth: Int) throws {
        let text = state.text
        guard let font = text.font else { return }
        let descriptor = file.resolve(font["FontDescriptor"])?.dictionary ?? [:]
        if (font["Subtype"]?.name == "TrueType" && descriptor["FontFile2"] != nil)
            || (font["Subtype"]?.name == "Type1" && file.resolve(descriptor["FontFile3"])?.dictionary?["Subtype"]?.name == "Type1C") {
            return try showEmbedded(items, matrix: &matrix, state: state, font: font, file: file)
        }
        guard font["Subtype"]?.name == "Type3" else { throw Self.fontError(font, file: file) }
        guard depth < 16 else { throw NomacError("the PDF's glyphs are nested too deeply", path: file.path) }
        let values = file.resolve(font["FontMatrix"])?.array?.compactMap(file.number) ?? []
        let fontMatrix = values.count == 6 ? Matrix(a: values[0], b: values[1], c: values[2], d: values[3], e: values[4], f: values[5])
            : Matrix(a: 0.001, d: 0.001)
        let procedures = file.resolve(font["CharProcs"])?.dictionary ?? [:]
        var names: [Int: String] = [:]
        var code = 0
        for item in file.resolve(file.resolve(font["Encoding"])?.dictionary?["Differences"])?.array ?? [] {
            if let number = file.number(item) {
                code = Int(number)
            } else if let name = item.name {
                names[code] = name
                code += 1
            }
        }
        let widths = file.resolve(font["Widths"])?.array?.map { file.number($0) ?? 0 } ?? []
        let firstCharacter = Int(file.number(font["FirstChar"]) ?? 0)
        let glyphResources = file.resolve(font["Resources"])?.dictionary ?? resources
        for item in items {
            guard case .string(let bytes) = item else {
                if case .integer(let value) = item { matrix = Matrix(e: -Double(value) / 1000 * text.size * text.scale).concatenating(matrix) }
                if case .real(let value, _) = item { matrix = Matrix(e: -value / 1000 * text.size * text.scale).concatenating(matrix) }
                continue
            }
            for byte in bytes {
                let character = Int(byte)
                if let name = names[character], let procedure = file.resolve(procedures[name]) {
                    var glyph = state
                    glyph.matrix = fontMatrix.concatenating(Matrix(a: text.size * text.scale, d: text.size, f: text.rise))
                        .concatenating(matrix).concatenating(state.matrix)
                    try interpret(try file.decodedStream(procedure), resources: glyphResources, file: file, state: glyph, depth: depth + 1)
                }
                let index = character - firstCharacter
                let width = index >= 0 && index < widths.count ? widths[index] * fontMatrix.a : 0
                let advance = (width * text.size + text.characterSpacing + (byte == 32 ? text.wordSpacing : 0)) * text.scale
                matrix = Matrix(e: advance).concatenating(matrix)
            }
        }
    }

    /// Text shown with an embedded TrueType or CFF font, which Quartz writes again with its own
    /// subset of the font (`fonts` to `fonts-5`, `cff`, `cff-2`). A TrueType code's glyph is found
    /// through the encoding's Unicode value in the font's Windows map, else the code in its
    /// Macintosh map; a CFF code's by its name in `/Differences`, else in MacRomanEncoding, else
    /// in the font's standard encoding. Each glyph advances by its width, the spacings and a `TJ`
    /// number's thousandths of the size; the space after it is counted from its width in the
    /// font in whole thousandths. A glyph's Unicode value is the PDF's `/ToUnicode` one,
    /// else its name's for WinAnsi names outside MacRomanEncoding, else for TrueType the
    /// encoding's (MacRoman without one).
    private mutating func showEmbedded(_ items: [PDFLexer.Token], matrix: inout Matrix, state: State, font: [String: PDFValue], file: PDFFile) throws {
        let text = state.text
        guard (0...3).contains(text.mode) else {
            throw NomacError("PDF images with text that clips are not supported yet (BACKLOG B-215)", path: file.path)
        }
        let otherEncoding = NomacError("PDF images with text in embedded fonts with other encodings are not supported yet (BACKLOG B-215)", path: file.path)
        let descriptor = file.resolve(font["FontDescriptor"])?.dictionary ?? [:]
        let program: PDFFontProgram
        if let known = fonts[text.fontKey] {
            program = known
        } else if let stream = file.resolve(descriptor["FontFile2"]) {
            program = .trueType(try TrueTypeFont(try file.decodedStream(stream), path: file.path))
        } else if let stream = file.resolve(descriptor["FontFile3"]) {
            program = .cff(try CFFFont(try file.decodedStream(stream), path: file.path))
        } else {
            return
        }
        fonts[text.fontKey] = program
        let lookup: (Int) -> (glyph: Int, unicode: Int?)
        switch program {
        case .trueType(let trueType):
            let encoding: PDFEncoding?
            switch file.resolve(font["Encoding"]) {
            case nil: encoding = nil
            case .name("MacRomanEncoding")?: encoding = .macRoman
            case .name("WinAnsiEncoding")?: encoding = .winAnsi
            default: throw otherEncoding
            }
            lookup = { code in
                let unicode = (encoding ?? .macRoman).unicode(code)
                return (trueType.glyph(code: code, unicode: encoding == nil ? nil : unicode), unicode)
            }
        case .cff(let cff):
            var differences: [Int: String] = [:]
            var macRoman = false
            switch file.resolve(font["Encoding"]) {
            case nil: break
            case .name("MacRomanEncoding")?: macRoman = true
            case .dictionary(let dictionary)?:
                switch file.resolve(dictionary["BaseEncoding"]) {
                case nil: break
                case .name("MacRomanEncoding")?: macRoman = true
                default: throw otherEncoding
                }
                var code = 0
                for item in file.resolve(dictionary["Differences"])?.array ?? [] {
                    if let number = file.number(item) {
                        code = Int(number)
                    } else if let name = item.name {
                        differences[code] = name
                        code += 1
                    }
                }
            default: throw otherEncoding
            }
            lookup = { code in
                if let name = differences[code] ?? (macRoman ? PDFEncoding.macRomanNames[code] : nil) { return (cff.glyph(named: name), nil) }
                return (cff.glyph(code: code), nil)
            }
        }
        let unicodes = try file.resolve(font["ToUnicode"]).map { try Self.unicodes(try file.decodedStream($0), path: file.path) } ?? [:]
        let widths = file.resolve(font["Widths"])?.array?.map { file.number($0) ?? 0 } ?? []
        let firstCharacter = Int(file.number(font["FirstChar"]) ?? 0)
        let scale = text.size * text.scale
        guard scale != 0 else { return }
        var glyphs: [TextRun.Glyph] = []
        var origin = matrix
        var gap = 0.0
        for item in items {
            guard case .string(let bytes) = item else {
                let value: Double
                switch item {
                case .integer(let integer): value = Double(integer)
                case .real(let real, _): value = real
                default: continue
                }
                gap -= value / 1000
                matrix = Matrix(e: -value / 1000 * scale).concatenating(matrix)
                continue
            }
            for byte in bytes {
                let code = Int(byte)
                let (glyph, unicode) = lookup(code)
                let name = program.name(glyph)
                let value = unicodes[code] ?? name.flatMap { PDFEncoding.winAnsiNames[$0] }.map { [UInt16($0)] }
                    ?? unicode.flatMap(UnicodeScalar.init).map { Array(String(Character($0)).utf16) } ?? []
                if glyphs.isEmpty { origin = matrix }
                glyphs.append(TextRun.Glyph(glyph: glyph, name: name, unicode: value, gap: glyphs.isEmpty ? 0 : gap))
                let index = code - firstCharacter
                let width = index >= 0 && index < widths.count ? widths[index] / 1000 : 0
                let advance = width + (text.characterSpacing + (byte == 32 ? text.wordSpacing : 0)) / text.size
                // Spaces count from the widths Quartz writes, in whole thousandths (corpus: cwa's
                // `Illu_Onboarding_Getestet.pdf`, whose -0.0002 Tc stays).
                gap = advance - Double(program.width(glyph)) / 1000
                matrix = Matrix(e: advance * scale).concatenating(matrix)
            }
        }
        guard !glyphs.isEmpty, !state.clippedOut else { return }
        // A show split between Quartz's two fonts of the PDF font is observed without spacing only (`fonts-3` named-odd).
        let macRoman = glyphs.map { $0.name.map { PDFEncoding.macRomanCodes[$0] != nil } ?? false }
        if Set(macRoman).count > 1, glyphs.contains(where: { abs($0.gap) > 1e-6 }) {
            throw NomacError("PDF images with spaced text in glyphs of both of Quartz's fonts of a PDF font are not supported yet (BACKLOG B-215)",
                             path: file.path)
        }
        let em = Matrix(a: scale, d: text.size, f: text.rise).concatenating(origin)
        var path = Path()
        var x = 0.0
        for (index, glyph) in glyphs.enumerated() {
            if index > 0 { x += Double(program.width(glyphs[index - 1].glyph)) / 1000 + glyph.gap }
            path.elements += program.path(glyph.glyph).applying(Matrix(e: x).concatenating(em)).elements
        }
        self.items.append(.text(TextRun(font: text.fontKey, glyphs: glyphs, matrix: em, mode: text.mode,
                                   drawing: Drawing(path: path, matrix: state.matrix, fill: text.mode == 0 || text.mode == 2,
                                                    stroke: text.mode == 1 || text.mode == 2, evenOdd: false, color: state.fillColor,
                                                    settings: state.settings, strokeColor: state.strokeColor, strokeSettings: state.strokeSettings,
                                                    line: state.line, clips: state.clips, softMask: state.softMask))))
    }

    /// A `/ToUnicode` CMap's values by one-byte code, as UTF-16.
    static func unicodes(_ data: [UInt8], path: String) throws -> [Int: [UInt16]] {
        var lexer = PDFLexer(data: data, path: path)
        var tokens: [PDFLexer.Token] = []
        while let token = try lexer.token() { tokens.append(token) }
        func units(_ token: PDFLexer.Token) -> [UInt16]? {
            guard case .string(let bytes) = token, bytes.count >= 2 else { return nil }
            return stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
        }
        func code(_ token: PDFLexer.Token) -> Int? {
            guard case .string(let bytes) = token, bytes.count == 1 else { return nil }
            return Int(bytes[0])
        }
        var result: [Int: [UInt16]] = [:]
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            if tokens[index] == .keyword("beginbfchar") {
                while index + 2 < tokens.count, tokens[index + 1] != .keyword("endbfchar") {
                    if let code = code(tokens[index + 1]), let value = units(tokens[index + 2]) { result[code] = value }
                    index += 2
                }
            } else if tokens[index] == .keyword("beginbfrange") {
                while index + 3 < tokens.count, tokens[index + 1] != .keyword("endbfrange") {
                    guard let low = code(tokens[index + 1]), let high = code(tokens[index + 2]), low <= high else { index += 1; continue }
                    if tokens[index + 3] == .arrayStart {
                        var at = index + 4
                        for code in low...high where at < tokens.count && tokens[at] != .arrayEnd {
                            if let value = units(tokens[at]) { result[code] = value }
                            at += 1
                        }
                        while at < tokens.count && tokens[at] != .arrayEnd { at += 1 }
                        index = at
                    } else {
                        if let value = units(tokens[index + 3]), let last = value.last {
                            for code in low...high { result[code] = value.dropLast() + [last + UInt16(code - low)] }
                        }
                        index += 3
                    }
                }
            }
        }
        return result
    }

    /// Why text in a font other than a Type 3 or embedded TrueType one stops nomac: Quartz writes
    /// it with a subset of the font, embedded or else macOS's own.
    private static func fontError(_ font: [String: PDFValue], file: PDFFile) -> NomacError {
        var descriptors = [font["FontDescriptor"]]
        for descendant in file.resolve(font["DescendantFonts"])?.array ?? [] {
            descriptors.append(file.resolve(descendant)?.dictionary?["FontDescriptor"])
        }
        let embedded = descriptors.contains { descriptor in
            let entries = file.resolve(descriptor)?.dictionary ?? [:]
            return ["FontFile", "FontFile2", "FontFile3"].contains { entries[$0] != nil }
        }
        return embedded
            ? NomacError("PDF images with text in embedded Type 1, CFF or CID fonts are not supported yet (BACKLOG B-215)", path: file.path)
            : NomacError("PDF images with text in a font the PDF does not embed are not supported: Quartz draws it with macOS's own font, "
                         + "which is not part of Xcode", path: file.path)
    }

    /// An image XObject's samples (`images`): 1, 2, 4, 8 or 16 bits of DeviceGray, DeviceRGB or a
    /// gray or RGB ICC profile, or a stencil mask, with their `/Decode` and `/Interpolate`.
    private static func samples(_ xobject: PDFValue, file: PDFFile, resources: [String: PDFValue]) throws -> Samples {
        guard let dictionary = xobject.dictionary, let width = file.number(dictionary["Width"]), let height = file.number(dictionary["Height"]),
              width >= 1, height >= 1 else {
            throw NomacError("the PDF has an image without a size", path: file.path)
        }
        let filters = (file.resolve(dictionary["Filter"]).map { $0.array ?? [$0] } ?? []).compactMap { file.resolve($0)?.name }
        let isJPEG = filters == ["DCTDecode"] || filters == ["DCT"]
        if !isJPEG, filters.contains(where: { ["DCTDecode", "DCT", "JPXDecode", "JBIG2Decode", "CCITTFaxDecode"].contains($0) }) {
            throw NomacError("PDF images with JPEG 2000, JBIG2 or fax-encoded image XObjects are not supported yet (BACKLOG B-215)", path: file.path)
        }
        let stencil = file.resolve(dictionary["ImageMask"]) == .bool(true)
        let bits = stencil ? 1 : Int(file.number(dictionary["BitsPerComponent"]) ?? 8)
        let space: ColorSpace?
        if stencil {
            space = nil
        } else {
            let value = file.resolve(dictionary["ColorSpace"])
            switch value {
            case .name(let name)?: space = try colorSpace(name, resources: resources, file: file)
            case let value?: space = try colorSpace("CS", resources: ["ColorSpace": .dictionary(["CS": value])], file: file)
            case nil: throw NomacError("the PDF has an image without a color space", path: file.path)
            }
        }
        guard stencil || space != nil, [1, 2, 4, 8, 16].contains(bits), file.resolve(dictionary["Mask"]) == nil else {
            throw NomacError("PDF images with CMYK or color-keyed image XObjects are not supported yet (BACKLOG B-215)", path: file.path)
        }
        let components = space?.components ?? 1
        var jpeg: [UInt8]?
        let data: [UInt8]
        if isJPEG, case .stream(_, let raw) = xobject {
            // A JPEG Quartz keeps byte for byte (`images` jpeg-gray), decoded for the rasters.
            let decoded = try JPEGDecoder.decode(raw, path: file.path)
            guard decoded.width == Int(width), decoded.height == Int(height), decoded.components == components, bits == 8 else {
                throw NomacError("the PDF has a JPEG image whose size or components differ from its dictionary's", path: file.path)
            }
            (jpeg, data) = (raw, decoded.pixels)
        } else {
            data = try file.decodedStream(xobject)
        }
        guard data.count >= (Int(width) * components * bits + 7) / 8 * Int(height) else {
            throw NomacError("the PDF has an image with fewer samples than its size", path: file.path)
        }
        let decode = file.resolve(dictionary["Decode"])?.array?.compactMap(file.number)
        return Samples(width: Int(width), height: Int(height), bitsPerComponent: bits, space: space, data: data,
                       decode: decode?.count == 2 * components ? decode : nil, interpolate: file.resolve(dictionary["Interpolate"]) == .bool(true), jpeg: jpeg,
                       intent: file.resolve(dictionary["Intent"])?.name)
    }

    /// An image's `/SMask`: an 8-bit DeviceGray image Quartz keeps as it is (`images` rgb-smask).
    private static func softMask(_ value: PDFValue, file: PDFFile) throws -> Samples {
        let mask = try samples(value, file: file, resources: [:])
        // A `/Matte` is dropped, the samples kept as they are (`images-3` smask-matte).
        guard mask.space == .gray, mask.bitsPerComponent == 8, mask.decode == nil else {
            throw NomacError("PDF images with soft masks other than 8-bit gray ones are not supported yet (BACKLOG B-215)", path: file.path)
        }
        return mask
    }

    /// A transparency group's color space: Quartz's Generic RGB when it names none, DeviceRGB's
    /// or a three-component ICC profile's as for colors (`groups` group-cs, `groups-2` icc-cs).
    private static func groupSpace(_ group: PDFValue, resources: [String: PDFValue], file: PDFFile) throws -> ColorSpace {
        guard let dictionary = group.dictionary, dictionary["S"]?.name == "Transparency" else {
            throw NomacError("PDF images with groups other than transparency groups are not supported yet (BACKLOG B-215)", path: file.path)
        }
        guard let value = file.resolve(dictionary["CS"]) else { return .genericRGB }
        let space: ColorSpace?
        switch value {
        case .name(let name): space = try colorSpace(name, resources: [:], file: file)
        default: space = try colorSpace("CS", resources: ["ColorSpace": .dictionary(["CS": value])], file: file)
        }
        guard let space, space.components == 3 else {
            throw NomacError("PDF images with transparency groups in a color space other than RGB are not supported yet (BACKLOG B-215)", path: file.path)
        }
        return space
    }

    /// Where an item draws within the clips from the `start`th on (those its group's content
    /// sets), `nil` when it is not bounded (`groups`: in-clip, content-larger; `groups-2`:
    /// clip-inside, nested-matrix; `groups-3` w0).
    private static func bounds(_ item: Item, clippedFrom start: Int) -> Rect? {
        let (area, clips): (Rect?, [Clip]) = switch item {
        case .drawing(let drawing): (drawing.bounds, drawing.clips)
        case .text(let run): (run.drawing.bounds, run.drawing.clips)
        case .group(let group): (group.bounds, group.clips)
        case .image(let image): (Rect(minX: 0, minY: 0, maxX: 1, maxY: 1).applying(image.matrix), image.clips)
        case .shading(let fill): (nil, fill.clips)
        }
        var result = area
        // A clip counts with its curves' control points (corpus: cwa's
        // `Icons_Settings_Risikoermittlung.pdf`, a curve clip to 3.000218 bounds a group at 3).
        for clip in clips.dropFirst(start) {
            guard let box = clip.path.controlBounds else { return nil }
            result = result?.intersection(box) ?? box
        }
        return result
    }

    /// The color space `name` names: a device space, or a resource that is one or an ICCBased
    /// space (`nil` for DeviceCMYK).
    static func colorSpace(_ name: String, resources: [String: PDFValue], file: PDFFile) throws -> ColorSpace? {
        let value = file.resolve(file.resolve(resources["ColorSpace"])?.dictionary?[name]) ?? .name(name)
        switch value {
        case .name("DeviceRGB"): return .rgb
        case .name("DeviceGray"): return .gray
        case .name("DeviceCMYK"): return nil
        case .array(let items) where items.first?.name == "ICCBased" && items.count == 2:
            guard let stream = file.resolve(items[1]), let components = file.number(stream.dictionary?["N"]) else { break }
            guard [1, 3].contains(Int(components)) else {
                throw NomacError("PDF images with ICCBased CMYK colors are not supported yet (BACKLOG B-215)", path: file.path)
            }
            return .icc(profile: try file.decodedStream(stream), components: Int(components))
        default: break
        }
        let kind = value.name ?? value.array?.first?.name ?? name
        throw NomacError("PDF images with the color space \(kind) are not supported yet (BACKLOG B-215)", path: file.path)
    }

    /// The ExtGState entries drawings can be made with: opacities, overprinting, smoothness, the
    /// rendering intent, line settings and stroke adjustment, and entries Quartz does not write (`extgstate`: FL, SA for fills;
    /// `strokes` LW-gs: a dash `D` is not applied).
    private static func checkExtGState(_ parameters: [String: PDFValue], file: PDFFile) throws {
        let ignored: Set<String> = ["Type", "ca", "CA", "LW", "LC", "LJ", "ML", "D", "FL", "SM", "SA", "OP", "op", "OPM", "AIS", "TK", "RI"]
        for (key, value) in parameters where !ignored.contains(key) {
            switch (key, file.resolve(value)) {
            case ("BM", .name("Normal")?), ("BM", .name("Compatible")?), ("SMask", .name("None")?), ("SMask", .dictionary?): continue
            default: throw NomacError("PDF images with the ExtGState entry \(key) are not supported yet (BACKLOG B-215)", path: file.path)
            }
        }
        if case .bool(true)? = file.resolve(parameters["AIS"]) {
            throw NomacError("PDF images with alpha as shape are not supported yet (BACKLOG B-215)", path: file.path)
        }
    }

    /// Whether clipping to `path` changes what the clips in force let through: not a rectangle
    /// around the rectangles in force (kickstarter's `icon-expansion.pdf`, a group's content
    /// clipping again to what its own clip already is), which Quartz does not write. A path
    /// without area clips everything out, and Quartz drops what is drawn under it (cwa's
    /// `Flags - Liechtenstein.pdf`, `x y m x y2 l W n`).
    static func clipChanges(_ path: Path, clips: [Clip]) -> Bool {
        guard let rectangle = path.rectangle else { return true }
        let inForce = clips.compactMap(\.path.rectangle)
        guard let first = inForce.first else { return true }
        let area = inForce.dropFirst().reduce(first) { $0.intersection($1) }
        return !(rectangle.minX <= area.minX && rectangle.minY <= area.minY && rectangle.maxX >= area.maxX && rectangle.maxY >= area.maxY)
    }

    /// The path as Quartz keeps it: a move right after a move replaces it, and a path that is
    /// only moves is none (`paths` empty-path); a move after the last subpath stays (corpus:
    /// 34 + 15 + 5 cwa, firefox and wikipedia files whose paths end `x y m W* n` or `x y m f`).
    private static func quartzPath(_ path: Path) -> Path {
        var kept: [Element] = []
        for element in path.elements {
            if case .move = element, case .move? = kept.last { kept.removeLast() }
            kept.append(element)
        }
        return kept.contains(where: { if case .move = $0 { false } else { true } }) ? Path(elements: kept, flippedRectangle: path.flippedRectangle) : Path()
    }
}
