/// A font program a PDF embeds and Quartz writes again as a subset: TrueType (`FontFile2`) or
/// CFF (`FontFile3` of subtype `Type1C`), with what Quartz writes for each (`fonts` to
/// `fonts-5`, `cff` to `cff-3`).
enum PDFFontProgram {
    case trueType(TrueTypeFont)
    case cff(CFFFont)

    /// A glyph's advance in ems.
    func advance(_ glyph: Int) -> Double {
        switch self {
        case .trueType(let font): Double(font.advance(glyph)) / font.unitsPerEm
        case .cff(let font): font.advance(glyph)
        }
    }

    /// A glyph's outline in ems, where Quartz draws it.
    func path(_ glyph: Int) -> PDFPage.Path {
        switch self {
        case .trueType(let font): font.path(glyph)
        case .cff(let font): font.path(glyph)
        }
    }

    func name(_ glyph: Int) -> String? {
        switch self {
        case .trueType(let font): font.name(glyph)
        case .cff(let font): font.name(glyph)
        }
    }

    /// The prefix of the font's resource names: `/TTn`, `/Tcn`.
    var resourcePrefix: String {
        if case .trueType = self { return "TT" }
        return "Tc"
    }

    var subtype: String {
        if case .trueType = self { return "/TrueType" }
        return "/Type1"
    }

    var postScriptName: String? {
        switch self {
        case .trueType(let font): font.postScriptName
        case .cff(let font): font.name
        }
    }

    /// A glyph's width in `/Widths`: its advance in thousandths of the em, rounded.
    func width(_ glyph: Int) -> Int { Int((advance(glyph) * 1000).rounded()) }

    /// The descriptor's entries from `/FontBBox` to `/MaxWidth`, in thousandths of the em.
    /// TrueType: the box's origin and size from `head` rounded each (its far corner their sum:
    /// SF Pro's 1249.51 written 1249), ascent, descent and maximum advance from `hhea`, cap and x
    /// heights as ``TrueTypeFont/capHeight`` says, the average width from OS/2. CFF: the box
    /// grown on each side by 6% of the em, at most 31 font units (`cff-3`, from 16 to 4,096
    /// units), its origin and size rounded each; the ascent and descent its top and bottom
    /// before growing; cap and x heights 8/9 and 2/3 of the ascent, truncated; `StemV` and
    /// `StemH` the Private DICT's `StdVW` and `StdHW`, the average width its `defaultWidthX`
    /// when not 0, the maximum width the grown box's (`cff`, `cff-2`; corpus: cwa's SF fonts).
    func descriptorEntries() -> [String] {
        func box(_ values: [Double]) -> [Int] {
            let x = Int(values[0].rounded()), y = Int(values[1].rounded())
            return [x, y, x + Int((values[2] - values[0]).rounded()), y + Int((values[3] - values[1]).rounded())]
        }
        func array(_ values: [Int]) -> String { "[\(values.map(String.init).joined(separator: " "))]" }
        switch self {
        case .trueType(let font):
            let (minX, minY, maxX, maxY) = font.bounds
            let scale = 1000 / font.unitsPerEm
            return ["/FontBBox", array(box([minX, minY, maxX, maxY].map { Double($0) * scale })), "/ItalicAngle", QuartzPDF.number(font.italicAngle),
                    "/Ascent", "\(font.thousandths(font.ascent))", "/Descent", "\(font.thousandths(font.descent))",
                    "/CapHeight", "\(font.thousandths(font.capHeight))", "/StemV", "0", "/XHeight", "\(font.thousandths(font.xHeight))"]
                + (font.averageWidth.map { ["/AvgWidth", "\(font.thousandths($0))"] } ?? [])
                + ["/MaxWidth", "\(font.thousandths(font.advanceWidthMax))"]
        case .cff(let font):
            let scale = font.scale * 1000
            let grow = min(31, (0.06 / font.scale).rounded())
            let (minX, minY, maxX, maxY) = font.bounds
            let grown = box([minX - grow, minY - grow, maxX + grow, maxY + grow].map { $0 * scale })
            let ascent = Int((maxY * scale).rounded())
            return ["/FontBBox", array(grown), "/ItalicAngle", "0", "/Ascent", "\(ascent)", "/Descent", "\(Int((minY * scale).rounded()))",
                    "/CapHeight", "\(ascent * 8 / 9)", "/StemV", "\(Int(((font.stemV ?? 0) * scale).rounded()))", "/XHeight", "\(ascent * 2 / 3)"]
                + (font.stemH.map { ["/StemH", "\(Int(($0 * scale).rounded()))"] } ?? [])
                + (font.defaultWidth != 0 ? ["/AvgWidth", "\(Int((font.defaultWidth * scale).rounded()))"] : [])
                + ["/MaxWidth", "\(grown[2] - grown[0])"]
        }
    }

    /// The program's stream: its descriptor key, its dictionary's entries and its bytes, a
    /// subset of the glyphs `codes` show (ADR 0204).
    func program(_ codes: [(code: Int, glyph: Int)]) -> (key: String, entries: [String], data: [UInt8]) {
        switch self {
        case .trueType(let font):
            let data = font.subset(codes)
            return ("/FontFile2", ["/Length1", "\(data.count)"], data)
        case .cff(let font):
            return ("/FontFile3", ["/Subtype", "/Type1C"], font.subset(codes.map(\.glyph)))
        }
    }
}
