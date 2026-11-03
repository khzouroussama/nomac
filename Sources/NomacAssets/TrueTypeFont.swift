import Foundation
import NomacCore

/// A TrueType font program as a PDF embeds it (`FontFile2`): its metrics, character maps, names
/// and glyph outlines, which nomac draws and subsets again (`pdf_experiments.py` fonts).
struct TrueTypeFont {
    let unitsPerEm: Double
    let bounds: (Int, Int, Int, Int)
    let ascent: Int
    let descent: Int
    let advanceWidthMax: Int
    let italicAngle: Double
    private let os2Heights: (capHeight: Int, xHeight: Int)?
    let averageWidth: Int?
    let postScriptName: String?
    private let advances: [Int]
    private let sideBearings: [Int]
    private let tables: [String: [UInt8]]
    private let offsets: [Int]
    private let maps: [String: [Int: Int]]
    private let names: [String]

    init(_ data: [UInt8], path: String) throws {
        func u16(_ bytes: [UInt8], _ at: Int) -> Int { at + 1 < bytes.count ? Int(bytes[at]) << 8 | Int(bytes[at + 1]) : 0 }
        func s16(_ bytes: [UInt8], _ at: Int) -> Int { Int(Int16(truncatingIfNeeded: u16(bytes, at))) }
        func u32(_ bytes: [UInt8], _ at: Int) -> Int { u16(bytes, at) << 16 | u16(bytes, at + 2) }
        guard data.count >= 12 else { throw NomacError("the PDF embeds a font nomac cannot read", path: path) }
        var tables: [String: [UInt8]] = [:]
        for index in 0..<u16(data, 4) {
            let entry = 12 + 16 * index
            let tag = String(decoding: data[entry..<min(entry + 4, data.count)], as: UTF8.self)
            let offset = u32(data, entry + 8), length = u32(data, entry + 12)
            guard offset + length <= data.count else { continue }
            tables[tag] = Array(data[offset..<(offset + length)])
        }
        guard let head = tables["head"], let hhea = tables["hhea"], let maxp = tables["maxp"], let hmtx = tables["hmtx"],
              let loca = tables["loca"], tables["glyf"] != nil else {
            throw NomacError("PDF images with text in TrueType fonts without outlines are not supported yet (BACKLOG B-215)", path: path)
        }
        self.tables = tables
        unitsPerEm = Double(max(u16(head, 18), 1))
        bounds = (s16(head, 36), s16(head, 38), s16(head, 40), s16(head, 42))
        ascent = s16(hhea, 4)
        descent = s16(hhea, 6)
        advanceWidthMax = u16(hhea, 10)
        let glyphCount = u16(maxp, 4)
        let metrics = max(u16(hhea, 34), 1)
        advances = (0..<glyphCount).map { u16(hmtx, 4 * min($0, metrics - 1)) }
        sideBearings = (0..<glyphCount).map { $0 < metrics ? s16(hmtx, 4 * $0 + 2) : s16(hmtx, 4 * metrics + 2 * ($0 - metrics)) }
        let long = s16(head, 50) == 1
        offsets = (0...glyphCount).map { long ? u32(loca, 4 * $0) : 2 * u16(loca, 2 * $0) }
        let post = tables["post"] ?? []
        italicAngle = Double(Int32(truncatingIfNeeded: u32(post, 4))) / 65536
        switch u32(post, 0) {
        case 0x10000:
            names = PDFEncoding.macintoshGlyphNames
        case 0x20000:
            let count = u16(post, 32)
            var strings: [String] = []
            var at = 34 + 2 * count
            while at < post.count {
                let length = Int(post[at])
                strings.append(String(decoding: post[min(at + 1, post.count)..<min(at + 1 + length, post.count)], as: UTF8.self))
                at += 1 + length
            }
            names = (0..<count).map { glyph in
                let index = u16(post, 34 + 2 * glyph)
                if index < 258 { return PDFEncoding.macintoshGlyphNames[index] }
                return index - 258 < strings.count ? strings[index - 258] : ""
            }
        default:
            names = []
        }
        if let os2 = tables["OS/2"], os2.count >= 90, u16(os2, 0) >= 2 {
            os2Heights = (s16(os2, 88), s16(os2, 86))
        } else {
            os2Heights = nil
        }
        averageWidth = tables["OS/2"].map { s16($0, 2) }
        var name: String?
        if let table = tables["name"] {
            let storage = u16(table, 4)
            for index in 0..<u16(table, 2) {
                let record = 6 + 12 * index
                let (platform, nameID) = (u16(table, record), u16(table, record + 6))
                let length = u16(table, record + 8), offset = storage + u16(table, record + 10)
                guard nameID == 6, offset + length <= table.count else { continue }
                let bytes = Array(table[offset..<(offset + length)])
                if platform == 3 || platform == 0 {
                    name = String(decoding: stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }, as: UTF16.self)
                    break
                }
                if platform == 1 { name = String(decoding: bytes, as: UTF8.self) }
            }
        }
        postScriptName = name
        var maps: [String: [Int: Int]] = [:]
        if let cmap = tables["cmap"] {
            for index in 0..<u16(cmap, 2) {
                let record = 4 + 8 * index
                let key = "\(u16(cmap, record)),\(u16(cmap, record + 2))"
                let start = u32(cmap, record + 4)
                var map: [Int: Int] = [:]
                switch u16(cmap, start) {
                case 0:
                    for code in 0..<256 where start + 6 + code < cmap.count { map[code] = Int(cmap[start + 6 + code]) }
                case 4:
                    let segments = u16(cmap, start + 6) / 2
                    let ends = start + 14, starts = ends + 2 * segments + 2, deltas = starts + 2 * segments, ranges = deltas + 2 * segments
                    for segment in 0..<segments {
                        let first = u16(cmap, starts + 2 * segment), last = u16(cmap, ends + 2 * segment)
                        let delta = u16(cmap, deltas + 2 * segment), range = u16(cmap, ranges + 2 * segment)
                        guard first <= last, last != 0xFFFF || first != 0xFFFF else { continue }
                        for code in first...last {
                            if range == 0 {
                                map[code] = (code + delta) & 0xFFFF
                            } else {
                                let glyph = u16(cmap, ranges + 2 * segment + range + 2 * (code - first))
                                if glyph != 0 { map[code] = (glyph + delta) & 0xFFFF }
                            }
                        }
                    }
                case 6:
                    let first = u16(cmap, start + 6)
                    for index in 0..<u16(cmap, start + 8) { map[first + index] = u16(cmap, start + 10 + 2 * index) }
                case 12:
                    for group in 0..<u32(cmap, start + 12) {
                        let at = start + 16 + 12 * group
                        let (first, last, glyph) = (u32(cmap, at), u32(cmap, at + 4), u32(cmap, at + 8))
                        guard last >= first, last - first < 0x10000 else { continue }
                        for code in first...last { map[code] = glyph + code - first }
                    }
                default: break
                }
                maps[key] = map
            }
        }
        self.maps = maps
    }

    /// A glyph's name in `post`, `nil` without one (format 3).
    func name(_ glyph: Int) -> String? { glyph < names.count && !names[glyph].isEmpty ? names[glyph] : nil }

    /// A value in font units in thousandths of the em, rounded, as Quartz writes metrics.
    func thousandths(_ value: Int) -> Int { thousandths(Double(value)) }

    func thousandths(_ value: Double) -> Int { Int((value * 1000 / unitsPerEm).rounded()) }

    /// The cap height Quartz writes, in font units: OS/2's, else the mean of the tops of `H` and
    /// `O`, else 8/9 of the ascent (`fonts`, `fonts-5`).
    var capHeight: Double { os2Heights.map { Double($0.capHeight) } ?? measuredHeight("H", "O") ?? Double(ascent * 8 / 9) }

    /// The x height Quartz writes, in font units: OS/2's, else the mean of the tops of `x` and
    /// `o`, else 2/3 of the ascent (`fonts`, `fonts-5`).
    var xHeight: Double { os2Heights.map { Double($0.xHeight) } ?? measuredHeight("x", "o") ?? Double(ascent * 2 / 3) }

    /// The mean of two letters' glyphs' tops, a letter the font lacks counting 0; `nil` when it
    /// lacks both (`fonts-5`: heights, heights-no-h).
    private func measuredHeight(_ first: Character, _ second: Character) -> Double? {
        let glyphs = [first, second].map { glyph(code: Int($0.asciiValue!), unicode: Int($0.asciiValue!)) }
        guard glyphs.contains(where: { $0 != 0 }) else { return nil }
        return glyphs.map { glyph -> Double in
            let data = glyphData(glyph)
            return glyph == 0 || data.count < 10 ? 0 : Double(Int16(bitPattern: UInt16(data[8]) << 8 | UInt16(data[9])))
        }.reduce(0, +) / 2
    }

    /// A glyph's advance in font units.
    func advance(_ glyph: Int) -> Int { glyph < advances.count ? advances[glyph] : 0 }

    /// The glyph a simple font's character code shows: by the character's Unicode value through
    /// the Windows Unicode map, else by the code through the Macintosh map, else the symbol
    /// map at 0xF000, else the code in the Windows Unicode map (PDF 1.7 § 9.6.6.4; `fonts-2` none).
    func glyph(code: Int, unicode: Int?) -> Int {
        if let unicode, let glyph = maps["3,1"]?[unicode] ?? maps["0,3"]?[unicode] { return glyph }
        if let glyph = maps["1,0"]?[code] { return glyph }
        if let glyph = maps["3,0"]?[0xF000 + code] ?? maps["3,0"]?[code] ?? maps["3,1"]?[code] { return glyph }
        return 0
    }

    /// A glyph's raw description in `glyf`.
    private func glyphData(_ glyph: Int) -> [UInt8] {
        guard glyph + 1 < offsets.count, let glyf = tables["glyf"], offsets[glyph] < offsets[glyph + 1], offsets[glyph + 1] <= glyf.count else { return [] }
        return Array(glyf[offsets[glyph]..<offsets[glyph + 1]])
    }

    /// A glyph's contours in font units, quadratic curves as they are: points with whether
    /// they are on the curve; composite glyphs flattened.
    private func contours(_ glyph: Int, depth: Int = 0) -> [[(x: Double, y: Double, onCurve: Bool)]] {
        let data = glyphData(glyph)
        guard data.count >= 10, depth < 8 else { return [] }
        func u16(_ at: Int) -> Int { at + 1 < data.count ? Int(data[at]) << 8 | Int(data[at + 1]) : 0 }
        func s16(_ at: Int) -> Int { Int(Int16(truncatingIfNeeded: u16(at))) }
        let count = s16(0)
        if count < 0 {
            var result: [[(x: Double, y: Double, onCurve: Bool)]] = []
            var at = 10
            while at + 4 <= data.count {
                let flags = u16(at), component = u16(at + 2)
                at += 4
                var dx = 0.0, dy = 0.0
                if flags & 1 != 0 { dx = Double(s16(at)); dy = Double(s16(at + 2)); at += 4 } else {
                    dx = Double(Int8(bitPattern: data[at])); dy = Double(Int8(bitPattern: data[at + 1])); at += 2
                }
                var (a, b, c, d) = (1.0, 0.0, 0.0, 1.0)
                if flags & 0x8 != 0 { a = Double(s16(at)) / 16384; d = a; at += 2 }
                else if flags & 0x40 != 0 { a = Double(s16(at)) / 16384; d = Double(s16(at + 2)) / 16384; at += 4 }
                else if flags & 0x80 != 0 {
                    a = Double(s16(at)) / 16384; b = Double(s16(at + 2)) / 16384; c = Double(s16(at + 4)) / 16384; d = Double(s16(at + 6)) / 16384
                    at += 8
                }
                result += contours(component, depth: depth + 1).map { contour in
                    contour.map { (x: a * $0.x + c * $0.y + dx, y: b * $0.x + d * $0.y + dy, onCurve: $0.onCurve) }
                }
                if flags & 0x20 == 0 { break }
            }
            return result
        }
        var ends: [Int] = []
        for index in 0..<count { ends.append(u16(10 + 2 * index)) }
        guard let last = ends.last else { return [] }
        let points = last + 1
        var at = 10 + 2 * count
        at += 2 + u16(at)
        var flags: [UInt8] = []
        while flags.count < points, at < data.count {
            let flag = data[at]; at += 1
            flags.append(flag)
            if flag & 8 != 0, at < data.count {
                let repeats = Int(data[at]); at += 1
                flags += [UInt8](repeating: flag, count: repeats)
            }
        }
        func coordinates(short: UInt8, same: UInt8) -> [Double] {
            var value = 0, result: [Double] = []
            for flag in flags.prefix(points) {
                if flag & short != 0 {
                    let delta = at < data.count ? Int(data[at]) : 0; at += 1
                    value += flag & same != 0 ? delta : -delta
                } else if flag & same == 0 {
                    value += s16(at); at += 2
                }
                result.append(Double(value))
            }
            return result
        }
        let xs = coordinates(short: 2, same: 16), ys = coordinates(short: 4, same: 32)
        var result: [[(x: Double, y: Double, onCurve: Bool)]] = []
        var start = 0
        for end in ends where end < xs.count && end < ys.count && end >= start {
            result.append((start...end).map { (x: xs[$0], y: ys[$0], onCurve: flags[$0] & 1 != 0) })
            start = end + 1
        }
        return result
    }

    /// A glyph's outline as a path in units of the em, quadratic curves made cubic, moved for its
    /// left edge to be its left side bearing, as Quartz draws it (corpus: wikipedia's
    /// `notifications-type-default.pdf`, a bell whose bearing differs from its edge).
    func path(_ glyph: Int) -> PDFPage.Path {
        var elements: [PDFPage.Element] = []
        let data = glyphData(glyph)
        let shift = data.count >= 10 && glyph < sideBearings.count ? Double(sideBearings[glyph] - Int(Int16(bitPattern: UInt16(data[2]) << 8 | UInt16(data[3])))) : 0
        func point(_ x: Double, _ y: Double) -> PDFPage.Point { PDFPage.Point(x: (x + shift) / unitsPerEm, y: y / unitsPerEm) }
        for contour in contours(glyph) where !contour.isEmpty {
            // Start on a point on the curve, or between two off-curve points.
            var points = contour
            if let first = points.firstIndex(where: \.onCurve) {
                points = Array(points[first...] + points[..<first])
            } else {
                let a = points[0], b = points[1 % points.count]
                points.insert((x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, onCurve: true), at: 0)
            }
            var current = points[0]
            elements.append(.move(point(current.x, current.y)))
            var control: (x: Double, y: Double)?
            for next in points.dropFirst() + [points[0]] {
                if next.onCurve {
                    if let c = control {
                        elements.append(.curve(point(current.x + 2 / 3 * (c.x - current.x), current.y + 2 / 3 * (c.y - current.y)),
                                               point(next.x + 2 / 3 * (c.x - next.x), next.y + 2 / 3 * (c.y - next.y)), point(next.x, next.y)))
                    } else {
                        elements.append(.line(point(next.x, next.y)))
                    }
                    current = next
                    control = nil
                } else if let c = control {
                    let middle = (x: (c.x + next.x) / 2, y: (c.y + next.y) / 2, onCurve: true)
                    elements.append(.curve(point(current.x + 2 / 3 * (c.x - current.x), current.y + 2 / 3 * (c.y - current.y)),
                                           point(middle.x + 2 / 3 * (c.x - middle.x), middle.y + 2 / 3 * (c.y - middle.y)), point(middle.x, middle.y)))
                    current = middle
                    control = (next.x, next.y)
                } else {
                    control = (next.x, next.y)
                }
            }
            elements.append(.close)
        }
        return PDFPage.Path(elements: elements)
    }

    /// A TrueType font of the glyphs `codes` show, glyph 0 first: their outlines (composite ones
    /// flattened), advances and side bearings and the font's metrics, a Macintosh map of the
    /// codes. Its bytes are nomac's own (ADR 0204).
    func subset(_ codes: [(code: Int, glyph: Int)]) -> [UInt8] {
        func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
        func be32(_ value: Int) -> [UInt8] { be16(value >> 16) + be16(value & 0xFFFF) }
        let all = [0] + codes.map(\.glyph)
        var outlines: [[UInt8]] = []
        for glyph in all {
            let contours = contours(glyph)
            let points = contours.flatMap { $0 }
            guard !points.isEmpty else { outlines.append([]); continue }
            let xs = points.map { Int($0.x.rounded()) }, ys = points.map { Int($0.y.rounded()) }
            var data = be16(contours.count) + be16(xs.min()!) + be16(ys.min()!) + be16(xs.max()!) + be16(ys.max()!)
            var end = -1
            for contour in contours { end += contour.count; data += be16(end) }
            data += be16(0) + points.map { $0.onCurve ? 1 : 0 }
            for values in [xs, ys] {
                var last = 0
                for value in values { data += be16(value - last); last = value }
            }
            outlines.append(data + [UInt8](repeating: 0, count: (4 - data.count % 4) % 4))
        }
        var loca: [UInt8] = [], offset = 0
        for outline in outlines { loca += be32(offset); offset += outline.count }
        loca += be32(offset)
        var head = tables["head"] ?? [UInt8](repeating: 0, count: 54)
        head.replaceSubrange(8..<12, with: [0, 0, 0, 0])
        head.replaceSubrange(50..<52, with: be16(1))
        var hhea = tables["hhea"] ?? [UInt8](repeating: 0, count: 36)
        hhea.replaceSubrange(34..<36, with: be16(all.count))
        var maxp = tables["maxp"] ?? [UInt8](repeating: 0, count: 6)
        maxp.replaceSubrange(4..<6, with: be16(all.count))
        let hmtx = all.flatMap { be16(advance($0)) + be16($0 < sideBearings.count ? sideBearings[$0] : 0) }
        var map = [UInt8](repeating: 0, count: 256)
        for (index, entry) in codes.enumerated() where entry.code < 256 { map[entry.code] = UInt8(index + 1) }
        let cmap = be16(0) + be16(1) + be16(1) + be16(0) + be32(12) + be16(0) + be16(262) + be16(0) + map
        let post = be32(0x30000) + [UInt8](repeating: 0, count: 28)
        let fontTables: [(String, [UInt8])] = [("cmap", cmap), ("glyf", outlines.flatMap { $0 }), ("head", head), ("hhea", hhea), ("hmtx", hmtx),
                                               ("loca", loca), ("maxp", maxp), ("post", post)]
        var result = be32(0x10000) + be16(fontTables.count) + be16(128) + be16(3) + be16(fontTables.count * 16 - 128)
        var body: [UInt8] = []
        var at = 12 + 16 * fontTables.count
        for (tag, table) in fontTables {
            let padded = table + [UInt8](repeating: 0, count: (4 - table.count % 4) % 4)
            let sum = stride(from: 0, to: padded.count, by: 4).reduce(UInt32(0)) {
                $0 &+ (UInt32(padded[$1]) << 24 | UInt32(padded[$1 + 1]) << 16 | UInt32(padded[$1 + 2]) << 8 | UInt32(padded[$1 + 3]))
            }
            result += Array(tag.utf8) + be32(Int(sum)) + be32(at) + be32(table.count)
            body += padded
            at += padded.count
        }
        return result + body
    }
}
