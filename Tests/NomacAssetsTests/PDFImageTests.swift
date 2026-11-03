import Foundation
import Testing
@testable import NomacAssets

/// PDF image sets as actool stores them: the page written again by Quartz's rules
/// (`pdf_experiments.py`, Xcode 27.0) and rasters at each scale (ADR 0204).
@Suite struct PDFImageTests {
    static func pdf(_ content: String, box: String = "0 0 20 10", resources: String = "", info: String? = nil, extra: [String] = []) -> [UInt8] {
        var objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [\(box)] /Contents 4 0 R /Resources << \(resources) >> >>",
                       "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"] + extra
        if let info { objects.append(info) }
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n" + offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R\(info == nil ? "" : " /Info \(objects.count) 0 R") >>\nstartxref\n\(xref)\n%%EOF\n"
        return Array(text.utf8)
    }

    static func page(_ content: String, box: String = "0 0 20 10", resources: String = "", info: String? = nil, extra: [String] = []) throws -> PDFPage {
        try PDFPage(file: PDFFile(data: pdf(content, box: box, resources: resources, info: info, extra: extra), path: "test.pdf"))
    }

    static func form(_ content: String, bbox: String = "0 0 20 10", entries: String = "") -> String {
        "<< /Type /XObject /Subtype /Form /BBox [\(bbox)]\(entries) /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
    }

    /// The content stream Quartz writes, decompressed.
    static func content(_ page: PDFPage) throws -> String {
        String(decoding: try PDFFile.inflate(QuartzPDF.contentStream(page), path: "test"), as: UTF8.self)
    }

    @Test func numbers() {
        let cases: [(Double, String)] = [
            (0.1234567891, "0.1234568"), (9.87654321, "9.876543"), (1234567.891, "1234568"), (12345678.9, "12345679"), (0.0000049, "0.0000049"),
            (0.0000012345678, "0.000001234568"), (0.0000009, "0"), (5.0000009, "5"), (4.9999991, "5"), (5.0000011, "5.000001"),
            (9.99999949, "10"), (-3.0000004, "-3"), (-0.0000049, "-0.0000049"), (2.5, "2.5"), (-0.0, "0"), (0.0100001, "0.0100001"),
            (0.1200001, "0.12"), (0.1000011, "0.1000011"), (0.0300001, "0.03"), (-0.2000001, "-0.2"), (0.095999904, "0.09599990"),
            (0.099000099, "0.09900010"), (0.12000015, "0.1200001"), (1.1000006, "1.100001"), (10.1000001, "10.1"),
        ]
        for (value, text) in cases { #expect(QuartzPDF.number(value) == text, "\(value)") }
    }

    /// Quartz's parsing: digits, trailing zeros included, as an integer times a power of ten
    /// (cwa's `Stars_half.pdf`, firefox's `firefoxLoader.pdf` and `logo_mastercard.pdf`).
    @Test func parsedNumbers() {
        func real(_ word: String) -> Double {
            if case .real(let value, _) = PDFLexer.number(word) { return value }
            return .nan
        }
        #expect(QuartzPDF.number(real("22.054075") + real("-2.215820")) == "19.83825")
        #expect(QuartzPDF.number(real("100.911980") + real("-0.002930")) == "100.909")
        #expect(QuartzPDF.number(real("0.000000") + real("186.781250")) == "186.7812")
        #expect(real("-4.50") == -4.5)
        #expect(PDFLexer.number("12") == .integer(12))
        // Content operands are read from their bytes as from their text.
        var generator = SystemRandomNumberGenerator()
        var words = ["0", "-0", "+7", ".5", "-.5", "5.", "-", "+", ".", "1.2.3", "1e5", "007.0100", "123456789012345678", "1234567890123456789",
                     "123456789.012345", "1234567890.123456", "-99999999999999999999.5", "12a"]
        for _ in 0..<2000 {
            let digits = (0..<Int.random(in: 1...17, using: &generator)).map { _ in String(Int.random(in: 0...9, using: &generator)) }.joined()
            let cut = Int.random(in: 0...digits.count, using: &generator)
            let sign = ["", "-", "+"].randomElement(using: &generator)!
            words.append(sign + (Bool.random(using: &generator) ? digits : String(digits.prefix(cut)) + "." + String(digits.dropFirst(cut))))
        }
        for word in words { #expect(PDFLexer.number(Array(word.utf8)[...]) == PDFLexer.number(word), "\(word)") }
    }

    @Test func linesBreakOncePastColumn72() {
        let units = Array(repeating: "1.25 1.75", count: 9) + ["l"]
        let text = QuartzPDF.Writer.wrapped(units)
        #expect(text.split(separator: "\n").map(\.count) == [79, 11])
        #expect(QuartzPDF.Writer.wrapped(["<<", ">>"]) == "<< >>")
    }

    @Test func fillsAreWrittenInPageCoordinates() throws {
        #expect(try Self.content(Self.page("q 0 1 -1 0 15 2 cm 1 0 0 rg 0 0 6 4 re f Q")) == "q Q q /Cs1 cs 1 0 0 sc 11 2 4 6 re f Q")
        #expect(try Self.content(Self.page("1 0 0 rg 2 2 m 10 9 18 2 v h f")) == "q Q q /Cs1 cs 1 0 0 sc 2 2 m 2 2 10 9 18 2 c h f Q")
        #expect(try Self.content(Self.page("1 0 0 rg 2 2 16 6 re 6 4 8 2 re f*"))
            == "q Q q /Cs1 cs 1 0 0 sc 2 2 m 18 2 l 18 8 l 2 8 l h 6 4 m 14 4 l 14 6 l 6 6\nl h f* Q")
        #expect(try Self.content(Self.page("1 0 0 rg 2 2 m 2 8 l 18 8 l 18 2 l h f")) == "q Q q /Cs1 cs 1 0 0 sc 2 2 16 6 re f Q")
        #expect(try Self.content(Self.page("1 0 0 rg 2 2 m n 2 2 m 18 2 l 18 1e1 l h f")) == "q Q q /Cs1 cs 1 0 0 sc 2 2 m 18 2 l h f Q")
        #expect(try Self.content(Self.page("2 2 16 6 re f")) == "q Q q 2 2 16 6 re f Q")
        #expect(try Self.content(Self.page("")) == "q Q")
    }

    @Test func colorsAndOpacityAreWrittenWhenTheyChange() throws {
        #expect(try Self.content(Self.page("1 0 0 rg 2 2 6 6 re f 10 2 6 6 re f")) == "q Q q /Cs1 cs 1 0 0 sc 2 2 6 6 re f 10 2 6 6 re f Q")
        let states = "/ExtGState << /G1 << /ca 0.5 >> /G2 << /ca 0.25 >> >>"
        #expect(try Self.content(Self.page("q /G1 gs 1 0 0 rg 1 1 4 4 re f Q q /G2 gs 1 0 0 rg 7 1 4 4 re f Q q /G1 gs 1 0 0 rg 13 1 4 4 re f Q", resources: states))
            == "q Q q /Cs1 cs 1 0 0 sc /Gs1 gs 1 1 4 4 re f /Cs1 cs 1 0 0 sc /Gs2 gs 7 1 4 4\nre f /Cs1 cs 1 0 0 sc /Gs1 gs 13 1 4 4 re f Q")
        #expect(try Self.content(Self.page("0.2 0.4 0.6 rg 2 2 6 6 re f 0.5 g 10 2 6 6 re f")) == "q Q q /Cs1 cs 0.2 0.4 0.6 sc 2 2 6 6 re f /Cs2 cs 0.5 sc 10 2 6 6 re f Q")
    }

    @Test func otherSettingsAreWrittenAroundTheColor() throws {
        let states = "/ExtGState << /A << /ca 0.5 >> /O << /op true >> /M << /OPM 1 >> /S << /SM 0.02 >> /R << /RI /Perceptual >> >>"
        #expect(try Self.content(Self.page("/R gs /S gs /M gs /O gs /A gs 1 0 0 rg 1 1 4 4 re f", resources: states))
            == "q Q q /Perceptual ri /Gs1 gs /Cs1 cs 1 0 0 sc /Gs2 gs /Gs3 gs /Gs4 gs 1 1 4 4\nre f Q")
        #expect(try Self.content(Self.page("q /Perceptual ri 1 0 0 rg 1 1 4 4 re f Q q 1 0 0 rg 7 1 4 4 re f Q"))
            == "q Q q /Perceptual ri /Cs1 cs 1 0 0 sc 1 1 4 4 re f /RelativeColorimetric ri\n7 1 4 4 re f Q")
        #expect(try Self.content(Self.page("q /M gs 1 0 0 rg 1 1 4 4 re f Q q 1 0 0 rg 7 1 4 4 re f Q", resources: states))
            == "q Q q /Cs1 cs 1 0 0 sc /Gs1 gs 1 1 4 4 re f /Gs2 gs 7 1 4 4 re f Q")
    }

    @Test func movesAndClipsAsQuartzKeepsThem() throws {
        #expect(try Self.content(Self.page("1 0 0 rg 2 2 16 6 re 5 5 m f")) == "q Q q /Cs1 cs 1 0 0 sc 2 2 m 18 2 l 18 8 l 2 8 l h 5 5 m f Q")
        #expect(try Self.content(Self.page("1 0 0 rg 1 1 m 2 2 m 18 2 l 9 9 l h f")) == "q Q q /Cs1 cs 1 0 0 sc 2 2 m 18 2 l 9 9 l h f Q")
        #expect(try Self.content(Self.page("q 0 0 10 10 re W n 1 0 0 rg 2 2 6 6 re f Q q 0 0 10 10 re W n 0 0 1 rg 3 3 4 4 re f Q"))
            == "q Q q 0 0 10 10 re W n /Cs1 cs 1 0 0 sc 2 2 6 6 re f Q q 0 0 10 10 re W n\n/Cs1 cs 0 0 1 sc 3 3 4 4 re f Q")
    }

    @Test func clipsOpenBlocks() throws {
        #expect(try Self.content(Self.page("q 2 2 12 6 re W n 6 0 12 10 re W n 1 0 0 rg 0 0 20 10 re f Q")) == "q Q q 6 2 8 6 re W n /Cs1 cs 1 0 0 sc 0 0 20 10 re f Q")
        #expect(try Self.content(Self.page("q 2 1 16 8 re W n 2 2 m 6 9 14 9 18 2 c h W n 1 0 0 rg 0 0 20 10 re f Q"))
            == "q Q q 2 2 m 6 9 14 9 18 2 c h W n 2 1 16 8 re W n /Cs1 cs 1 0 0 sc 0 0 20 10\nre f Q")
        #expect(try Self.content(Self.page("1 0 0 rg q 0 0 10 10 re W n 2 2 6 6 re f Q 10 2 6 6 re f"))
            == "q Q q 0 0 10 10 re W n /Cs1 cs 1 0 0 sc 2 2 6 6 re f Q q /Cs1 cs 1 0 0 sc\n10 2 6 6 re f Q")
        #expect(try Self.content(Self.page("q 4 2 12 6 re W 1 0 0 rg f Q")) == "q Q q /Cs1 cs 1 0 0 sc 4 2 12 6 re f Q")
    }

    @Test func strokesKeepTheirTransformation() throws {
        #expect(try Self.content(Self.page("0 0 1 RG 2 w 1 J 1 j 3 3 m 10 8 l 17 3 l S")) == "q Q q 2 w 1 J 1 j /Cs1 CS 0 0 1 SC 3 3 m 10 8 l 17 3 l S Q")
        #expect(try Self.content(Self.page("q 2 0 0 2 0 0 cm 1 0 0 rg 0 0 1 RG 1 w 1 1 7 3 re B Q"))
            == "q Q q /Cs1 cs 1 0 0 sc /Cs1 CS 0 0 1 SC q 2 0 0 2 0 0 cm 1 1 7 3 re B Q Q")
        #expect(try Self.content(Self.page("0 0 1 RG 1 w [3 2 1] 1.5 d 3 3 m 17 7 l S")) == "q Q q [ 3 2 1 ] 1.5 d /Cs1 CS 0 0 1 SC 3 3 m 17 7 l S Q")
        #expect(try Self.content(Self.page("0 0 1 RG 2 w 3 3 m 17 3 l 10 8 l s")) == "q Q q 2 w /Cs1 CS 0 0 1 SC 3 3 m 17 3 l 10 8 l h S Q")
        let states = "/ExtGState << /G1 << /OP true >> /G2 << /CA 0.5 /ca 0.25 >> >>"
        #expect(try Self.content(Self.page("/G1 gs 0 0 1 RG 2 w 3 3 m 17 7 l S", resources: states)) == "q Q q 2 w /Cs1 CS 0 0 1 SC /Gs1 gs /Gs2 gs 3 3 m 17 7 l S Q")
        #expect(try Self.content(Self.page("/G2 gs 1 0 0 rg 0 0 1 RG 2 w 3 3 14 4 re B", resources: states))
            == "q Q q 2 w /Cs1 cs 1 0 0 sc /Gs1 gs /Cs1 CS 0 0 1 SC /Gs2 gs 3 3 14 4 re B\nQ")
    }

    @Test func formsAreDrawnInPlace() throws {
        let xobject = "/XObject << /X1 5 0 R >>"
        #expect(try Self.content(Self.page("/X1 Do", resources: xobject, extra: [Self.form("1 0 0 rg 0 0 8 4 re f", entries: " /Matrix [2 0 0 2 1 1]")]))
            == "q Q q 1 1 40 20 re W n /Cs1 cs 1 0 0 sc 1 1 16 8 re f Q")
        #expect(try Self.content(Self.page("q 0 0 10 10 re W n /X1 Do Q", resources: xobject, extra: [Self.form("1 0 0 rg 2 2 16 6 re f")]))
            == "q Q q 0 0 10 10 re W n /Cs1 cs 1 0 0 sc 2 2 16 6 re f Q")
    }

    /// Transparency groups stay forms, numbered and ordered as Quartz writes them (`groups`,
    /// `groups-2`, `groups-3`).
    @Test func groupsStayForms() throws {
        let xobject = "/XObject << /X1 5 0 R >>", group = " /Group << /S /Transparency >>"
        func objects(_ page: PDFPage) -> (order: [String], text: String) {
            let text = String(decoding: QuartzPDF.rewrite(page).map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
            let order = text.split(separator: "\n").filter { $0.hasSuffix(" 0 obj") }.map { String($0.split(separator: " ")[0]) }
            return (order, text)
        }
        let plain = try Self.page("/X1 Do", resources: xobject, extra: [Self.form("1 0 0 rg 4 3 6 2 re f", entries: group)])
        #expect(try Self.content(plain) == "q Q q /Fm1 Do Q")
        let (order, text) = objects(plain)
        #expect(order == ["4", "1", "3", "6", "5", "9", "7", "10", "8", "2", "11", "12"])
        #expect(text.contains("6 0 obj\n<< /Type /XObject /Subtype /Form /FormType 1 /BBox [4 3 10 5] /Resources 5 0 R\n/Group << /S /Transparency /CS 7 0 R /I true /K false >>"))
        #expect(text.contains("<< /Type /Catalog /Pages 2 0 R /Version /1.4 >>"))
        let opacity = try Self.page("/G1 gs /X1 Do", resources: xobject + " /ExtGState << /G1 << /ca 0.5 >> >>",
                                    extra: [Self.form("1 0 0 rg 2 2 16 6 re f", entries: group)])
        #expect(try Self.content(opacity) == "q Q q /Gs1 gs /Fm1 Do Q")
        if case .group(let found)? = opacity.items.first, case .drawing(let drawing)? = found.items.first {
            #expect(found.alpha == 0.5 && drawing.settings.alpha == 1)
        } else {
            Issue.record("no group")
        }
        let twice = try Self.page("/X1 Do q 1 0 0 1 10 0 cm /X1 Do Q", resources: xobject,
                                  extra: [Self.form("1 0 0 rg 1 1 6 6 re f", bbox: "0 0 10 10", entries: group)])
        #expect(try Self.content(twice) == "q Q q /Fm1 Do Q q /Fm2 Do Q")
        #expect(objects(opacity).order == ["4", "1", "3", "6", "5", "7", "10", "8", "11", "9", "2", "12", "13"])
        let after = try Self.page("/X1 Do 0 0 1 rg 0 0 4 4 re f", resources: xobject, extra: [Self.form("1 0 0 rg 6 2 12 6 re f", entries: group)])
        #expect(try Self.content(after) == "q Q q /Fm1 Do /Cs1 cs 0 0 1 sc 0 0 4 4 re f Q")
        let outside = try Self.page("/X1 Do", resources: xobject, extra: [Self.form("1 0 0 rg 10 2 4 4 re f", bbox: "0 0 5 5", entries: group)])
        #expect(try Self.content(outside) == "q Q")
        #expect(!objects(outside).text.contains("/Version"))
    }

    /// Type 3 text is drawn as its glyphs' content (`text`).
    @Test func type3TextIsDrawnAsItsGlyphs() throws {
        let glyph = "1 0 d0 0 0 1 1 re f"
        let font = "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
            + "/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1"
            + String(repeating: " 0", count: 31) + " 1] >>"
        func content(_ text: String) throws -> String {
            try Self.content(Self.page("1 0 0 rg " + text, resources: "/Font << /F1 6 0 R >>",
                                       extra: ["<< /Length \(glyph.utf8.count) >>\nstream\n\(glyph)\nendstream", font]))
        }
        #expect(try content("BT /F1 4 Tf 2 2 Td [(\\000) -500 (\\000)] TJ ET") == "q Q q /Cs1 cs 1 0 0 sc 2 2 4 4 re f 8 2 4 4 re f Q")
        #expect(try content("BT /F1 2 Tf 1 Tc 3 Tw 50 Tz 2 2 Td (\\000\\040\\000) Tj ET")
            == "q Q q /Cs1 cs 1 0 0 sc 2 2 1 2 re f 3.5 2 1 2 re f 6.5 2 1 2 re f Q")
        #expect(try content("q 1 0 0 1 2 0 cm BT 2 0 0 2 3 1 Tm /F1 2 Tf (\\000\\000) Tj ET Q") == "q Q q /Cs1 cs 1 0 0 sc 5 1 4 4 re f 9 1 4 4 re f Q")
        #expect(try content("BT /F1 2 Tf 3 TL 1 6 Td (\\000) Tj T* (\\000) Tj 1 Ts (\\000) Tj ET")
            == "q Q q /Cs1 cs 1 0 0 sc 1 6 2 2 re f 1 3 2 2 re f 3 4 2 2 re f Q")
    }

    /// Text in other fonts stops nomac, with why when the font is not embedded.
    @Test func otherFontsAreRefused() throws {
        let page = "BT /F1 12 Tf 2 2 Td (a) Tj ET"
        let named = "<< /Type /Font /Subtype /TrueType /BaseFont /Helvetica /FontDescriptor 6 0 R >>"
        do {
            _ = try Self.page(page, resources: "/Font << /F1 5 0 R >>", extra: [named, "<< /Type /FontDescriptor /FontName /Helvetica >>"])
            Issue.record("not refused")
        } catch {
            #expect("\(error)".contains("does not embed"))
        }
        do {
            _ = try Self.page(page, resources: "/Font << /F1 5 0 R >>", extra: [named.replacingOccurrences(of: "TrueType", with: "Type1"),
                                                                               "<< /Type /FontDescriptor /FontName /Helvetica /FontFile3 7 0 R >>"])
            Issue.record("not refused")
        } catch {
            #expect("\(error)".contains("embedded Type 1, CFF or CID fonts"))
        }
    }

    /// A TrueType font written here, its glyphs squares from x 100 to 900 and from y 0 to their
    /// height, each advance the em, glyph 0 empty: Windows Unicode map, `post` names when given,
    /// a name table with `name`.
    static func trueType(_ glyphs: [(character: Character, height: Int, name: String?)], name: String = "SquareSans-Bold",
                         unitsPerEm: Int = 1000, box: (Int, Int, Int, Int) = (0, 0, 1000, 1000), sideBearing: Int = 0) -> [UInt8] {
        func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
        func be32(_ value: Int) -> [UInt8] { be16(value >> 16) + be16(value & 0xFFFF) }
        var outlines: [[UInt8]] = [[]]
        for glyph in glyphs {
            let xs = [100, 100, 900, 900], ys = [0, glyph.height, glyph.height, 0]
            var data = be16(1) + be16(100) + be16(0) + be16(900) + be16(glyph.height) + be16(3) + be16(0) + [1, 1, 1, 1]
            for values in [xs, ys] {
                var last = 0
                for value in values { data += be16(value - last); last = value }
            }
            outlines.append(data + [UInt8](repeating: 0, count: (4 - data.count % 4) % 4))
        }
        var loca: [UInt8] = [], offset = 0
        for outline in outlines { loca += be32(offset); offset += outline.count }
        loca += be32(offset)
        let sorted = glyphs.enumerated().sorted { $0.element.character < $1.element.character }
        let segments = sorted.map { (Int($0.element.character.asciiValue!), $0.offset + 1) } + [(0xFFFF, 0)]
        let count = segments.count
        let body = be16(2 * count) + be16(2) + be16(0) + be16(0) + segments.flatMap { be16($0.0) } + be16(0) + segments.flatMap { be16($0.0) }
            + segments.flatMap { be16($0.1 == 0 ? 1 : ($0.1 - $0.0) & 0xFFFF) } + segments.flatMap { _ in be16(0) }
        var post = be32(0x30000) + [UInt8](repeating: 0, count: 28)
        if glyphs.contains(where: { $0.name != nil }) {
            post = be32(0x20000) + [UInt8](repeating: 0, count: 28) + be16(glyphs.count + 1) + be16(0)
                + glyphs.indices.flatMap { be16(258 + $0) } + glyphs.flatMap { [UInt8(($0.name ?? "").utf8.count)] + Array(($0.name ?? "").utf8) }
        }
        let text = Array(name.utf16).flatMap { be16(Int($0)) }
        let tables: [(String, [UInt8])] = [
            ("cmap", be16(0) + be16(1) + be16(3) + be16(1) + be32(12) + be16(4) + be16(6 + body.count) + be16(0) + body),
            ("glyf", outlines.flatMap { $0 }),
            ("head", be32(0x10000) + be32(0x10000) + be32(0) + be32(0x5F0F3CF5) + be16(0) + be16(unitsPerEm) + [UInt8](repeating: 0, count: 16)
                + be16(box.0) + be16(box.1) + be16(box.2) + be16(box.3) + be16(0) + be16(8) + be16(2) + be16(1) + be16(0)),
            ("hhea", be32(0x10000) + be16(unitsPerEm) + be16(0) + be16(0) + be16(unitsPerEm) + [UInt8](repeating: 0, count: 22) + be16(outlines.count)),
            ("hmtx", outlines.flatMap { _ in be16(unitsPerEm) + be16(sideBearing) }),
            ("loca", loca),
            ("maxp", be32(0x10000) + be16(outlines.count) + [UInt8](repeating: 0, count: 26)),
            ("name", be16(0) + be16(1) + be16(18) + be16(3) + be16(1) + be16(0x409) + be16(6) + be16(text.count) + be16(0) + text),
            ("post", post),
        ]
        var font = be32(0x10000) + be16(tables.count) + be16(128) + be16(3) + be16(tables.count * 16 - 128)
        var data: [UInt8] = []
        for (tag, table) in tables {
            font += Array(tag.utf8) + be32(0) + be32(12 + 16 * tables.count + data.count) + be32(table.count)
            data += table + [UInt8](repeating: 0, count: (4 - table.count % 4) % 4)
        }
        return font + data
    }

    /// A page showing `content` with the TrueType font `program` as /F1.
    static func trueTypePage(_ content: String, _ program: [UInt8], widths: String = "1000 1000 1000", encoding: String = "/WinAnsiEncoding") throws -> PDFPage {
        let font = "<< /Type /Font /Subtype /TrueType /BaseFont /Square /FirstChar 65 /LastChar 67 /Widths [\(widths)] /FontDescriptor 6 0 R "
            + "/Encoding \(encoding) >>"
        let descriptor = "<< /Type /FontDescriptor /FontName /Square /Flags 32 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 "
            + "/CapHeight 700 /StemV 80 /FontFile2 7 0 R >>"
        var bytes = pdf("1 0 0 rg " + content, resources: "/Font << /F1 5 0 R >>", extra: [font, descriptor, "FONT"])
        let marker = Array("FONT".utf8)
        let at = bytes.firstRange(of: marker)!
        bytes.replaceSubrange(at, with: Array("<< /Length \(program.count) >>\nstream\n".utf8) + program + Array("\nendstream".utf8))
        return try PDFPage(file: PDFFile(data: bytes, path: "test.pdf"))
    }

    static let squares: [(character: Character, height: Int, name: String?)] = [("A", 700, nil), ("B", 1000, nil), ("C", 900, nil)]

    /// Text in an embedded TrueType font: one `BT` per show under the first glyph's em, the
    /// glyphs at Quartz's codes, spacing as `Tc` and `TJ` numbers (`fonts`, `fonts-3`).
    @Test func trueTypeTextIsWrittenWithQuartzsFonts() throws {
        func content(_ text: String, glyphs: [(character: Character, height: Int, name: String?)] = Self.squares, widths: String = "1000 1000 1000") throws -> String {
            try Self.content(Self.trueTypePage(text, Self.trueType(glyphs), widths: widths))
        }
        #expect(try content("BT /F1 4 Tf 1 2 Td [(A) -500 (B) -200 (C)] TJ ET")
            == "q Q q /Cs1 cs 1 0 0 sc BT 0.5 Tc 4 0 0 4 1 2 Tm /TT2 1 Tf [ (!\") 300 (#) ]\nTJ 0 Tc ET Q")
        #expect(try content("q 1 0 0 1 2 1 cm BT 2 0 0 2 1 1 Tm /F1 3 Tf (AB) Tj ET Q")
            == "q Q q /Cs1 cs 1 0 0 sc q 1 0 0 1 2 1 cm BT 6 0 0 6 1 1 Tm /TT2 1 Tf (!\") Tj\nET Q Q")
        #expect(try content("BT /F1 4 Tf 1 Tc 50 Tz 1 2 Td (AB) Tj ET") == "q Q q /Cs1 cs 1 0 0 sc BT 0.25 Tc 2 0 0 4 1 2 Tm /TT2 1 Tf (!\") Tj 0 Tc ET\nQ")
        #expect(try content("BT /F1 4 Tf 1 2 Td (AB) Tj ET", widths: "600 800 1000")
            == "q Q q /Cs1 cs 1 0 0 sc BT -0.4 Tc 4 0 0 4 1 2 Tm /TT2 1 Tf (!\") Tj 0 Tc ET\nQ")
        #expect(try content("BT /F1 6 Tf 1 2 Td (A) Tj 0 0 1 rg (BA) Tj ET")
            == "q Q q /Cs1 cs 1 0 0 sc BT 6 0 0 6 1 2 Tm /TT2 1 Tf (!) Tj ET /Cs1 cs 0 0 1\nsc BT 6 0 0 6 7 2 Tm /TT2 1 Tf (\"!) Tj ET Q")
        #expect(try content("0 0 1 RG BT 1 Tr /F1 8 Tf 2 2 Td (A) Tj ET") == "q Q q /Cs1 CS 0 0 1 SC 1 Tr BT 8 0 0 8 2 2 Tm /TT2 1 Tf (!) Tj ET Q")
        #expect(try content("BT 3 Tr /F1 8 Tf 2 2 Td (A) Tj ET 1 1 2 2 re f")
            == "q Q q 3 Tr BT 8 0 0 8 2 2 Tm /TT2 1 Tf (!) Tj ET /Cs1 cs 1 0 0 sc 1 1 2 2\nre f Q")
        let named = Self.squares.map { ($0.character, $0.height, String($0.character)) }
        #expect(try content("BT /F1 6 Tf 1 2 Td (BA) Tj ET", glyphs: named) == "q Q q /Cs1 cs 1 0 0 sc BT 6 0 0 6 1 2 Tm /TT1 1 Tf (BA) Tj ET Q")
        let odd: [(character: Character, height: Int, name: String?)] = [("A", 700, "square"), ("B", 1000, "bar"), ("C", 900, "triangle")]
        #expect(try content("BT /F1 6 Tf 1 2 Td (BA) Tj ET", glyphs: odd)
            == "q Q q /Cs1 cs 1 0 0 sc BT 6 0 0 6 1 2 Tm /TT1 1 Tf (|) Tj /TT2 1 Tf (!) Tj\nET Q")
        #expect(throws: (any Error).self) { try content("BT /F1 6 Tf 1 2 Td [(B) -100 (A)] TJ ET", glyphs: odd) }
        #expect(throws: (any Error).self) { try content("BT 4 Tr /F1 6 Tf 1 2 Td (A) Tj ET") }
    }

    /// The fonts after the catalog, each Quartz font of a PDF font numbered at its first glyph,
    /// the MacRoman one first even when unused (`fonts`, `fonts-3`, `fonts-5`).
    @Test func trueTypeFontsAreWrittenAfterTheCatalog() throws {
        let file = QuartzPDF.rewrite(try Self.trueTypePage("BT /F1 4 Tf 1 2 Td [(A) -500 (B)] TJ ET", Self.trueType(Self.squares)))
        let text = String(decoding: file.map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
        #expect(text.matches(of: /\n(\d+) 0 obj\n/).map { Int($0.1)! } == [4, 1, 3, 8, 5, 2, 9, 7, 11, 10, 12, 13])
        #expect(text.contains("3 0 obj\n<< /ProcSet [ /PDF /Text ] /ColorSpace << /Cs1 5 0 R >> /Font << /TT2 7 0 R\n>> >>"))
        #expect(text.contains("7 0 obj\n<< /Type /Font /Subtype /TrueType /BaseFont /AAAAAC+SquareSans-Bold /FontDescriptor\n10 0 R /ToUnicode "
            + "11 0 R /FirstChar 33 /LastChar 34 /Widths [ 1000 1000 ]\n>>"))
        #expect(text.contains("10 0 obj\n<< /Type /FontDescriptor /FontName /AAAAAC+SquareSans-Bold /Flags 4 /FontBBox\n[0 0 1000 1000] "
            + "/ItalicAngle 0 /Ascent 1000 /Descent 0 /CapHeight 888 /StemV\n0 /XHeight 666 /MaxWidth 1000 /FontFile2 12 0 R >>"))
        #expect(text.contains("12 0 obj\n<< /Length1 "))
        #expect(QuartzPDF.Document.toUnicode([(33, 1, [0x43]), (34, 2, [0x41]), (35, 3, [0x42]), (36, 4, [0x20AC])])
            == "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo <<\n  /Registry (Adobe)\n  /Ordering (UCS)\n"
            + "  /Supplement 0\n>> def\n/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<00><FF>\nendcodespacerange\n"
            + "3 beginbfrange\n<21><21><0043>\n<22><23><0041>\n<24><24><20ac>\nendbfrange\nendcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n")
        let named = Self.squares.map { ($0.character, $0.height, String($0.character)) }
        let macRoman = QuartzPDF.rewrite(try Self.trueTypePage("BT /F1 6 Tf 1 2 Td (CA) Tj ET", Self.trueType(named), widths: "600 800 900"))
        let macText = String(decoding: macRoman.map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
        #expect(macText.contains("6 0 obj\n<< /Type /Font /Subtype /TrueType /BaseFont /AAAAAB+SquareSans-Bold /FontDescriptor\n9 0 R /Encoding "
            + "/MacRomanEncoding /FirstChar 65 /LastChar 67 /Widths [ 1000\n0 1000 ] >>"))
        #expect(macText.contains("/Flags 32 "))
    }

    /// Metrics in thousandths of the em: the box's origin and size rounded each, cap and x
    /// heights from `H` and `O`, `x` and `o`, glyphs placed at their side bearing (`fonts-5`;
    /// corpus: Helvetica's and SF Compact's subsets).
    @Test func trueTypeMetricsFollowQuartz() throws {
        let program = try TrueTypeFont(Self.trueType(Self.squares, unitsPerEm: 2048, box: (-1947, -985, 2961, 2297)), path: "test")
        #expect(program.thousandths(-1947) == -951)
        #expect(program.thousandths(2961) == 1446)
        let file = QuartzPDF.rewrite(try Self.trueTypePage("BT /F1 4 Tf 1 2 Td (A) Tj ET", Self.trueType(Self.squares, unitsPerEm: 2048,
                                                                                                           box: (-1947, -985, 2961, 2297))))
        #expect(String(decoding: file.map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self).contains("[-951 -481 1445 1122]"))
        let letters = try TrueTypeFont(Self.trueType([("A", 610, nil), ("H", 620, nil), ("O", 640, nil), ("x", 410, nil), ("o", 430, nil)]), path: "test")
        #expect(letters.capHeight == 630)
        #expect(letters.xHeight == 420)
        let noH = try TrueTypeFont(Self.trueType([("O", 640, nil), ("o", 430, nil)]), path: "test")
        #expect(noH.capHeight == 320)
        #expect(try TrueTypeFont(Self.trueType(Self.squares), path: "test").capHeight == 888)
        let bearing = try TrueTypeFont(Self.trueType(Self.squares, sideBearing: 0), path: "test")
        #expect(bearing.path(1).bounds?.minX == 0)
    }

    @Test func trueTypeTextIsDrawnInRasters() throws {
        let page = try Self.trueTypePage("BT /F1 10 Tf 0 0 Td (B) Tj ET", Self.trueType(Self.squares))
        let canvas = PDFRaster.draw(page, width: 20, height: 10, colors: try PDFRaster.Colors(page), extended: false)
        let pixel = { (x: Int, y: Int) in Array(canvas.pixels[(y * 20 + x) * 4..<(y * 20 + x) * 4 + 4]) }
        #expect(pixel(2, 5) == [1, 0, 0, 1])
        #expect(pixel(15, 5) == [0, 0, 0, 0])
    }

    /// Spaces between glyphs as Quartz writes them: the first as `Tc` unless one is 0, the
    /// others as `TJ` numbers, whole after a `Tc` (`fonts-6`).
    @Test func spacesFollowQuartz() throws {
        func show(_ text: String) throws -> String {
            let content = try Self.content(Self.trueTypePage("BT 4 0 0 4 1 2 Tm /F1 1 Tf \(text) ET", Self.trueType(Self.squares)))
            return String(content[content.range(of: "BT")!.lowerBound..<content.range(of: "ET")!.upperBound])
                .replacingOccurrences(of: "\n", with: " ")
        }
        #expect(try show("[(A) -500 (B) (C)] TJ") == "BT 4 0 0 4 1 2 Tm /TT2 1 Tf [ (!) -500 (\"#) ] TJ ET")
        #expect(try show("[(A) -0.1 (B) -0.4 (C)] TJ") == "BT 0.0001 Tc 4 0 0 4 1 2 Tm /TT2 1 Tf (!\"#) Tj 0 Tc ET")
        #expect(try show("[(A) -0.1 (B) -10 (C)] TJ") == "BT 0.0001 Tc 4 0 0 4 1 2 Tm /TT2 1 Tf [ (!\") -10 (#) ] TJ 0 Tc ET")
        #expect(try show("[(AB) -0.1 (C)] TJ") == "BT 4 0 0 4 1 2 Tm /TT2 1 Tf [ (!\") -0.1 (#) ] TJ ET")
        #expect(try show("[(A) -200 (B) -500 (C) -500 (A)] TJ") == "BT 0.2 Tc 4 0 0 4 1 2 Tm /TT2 1 Tf [ (!\") -300 (#) -300 (!) ] TJ 0 Tc ET")
    }

    /// A CFF font written here: squares from x 100 to 900 and from y 0 to their height, each
    /// advance `units`, glyph 0 empty, named by `names` (the character by default), the standard
    /// encoding, `units` per em, Private DICT `StdHW` 30 and `StdVW` 60.
    static func cff(_ glyphs: [(character: Character, height: Int)], names: [Character: String] = [:], units: Int = 1000,
                    box: (Int, Int, Int, Int) = (0, 0, 1000, 1000)) -> [UInt8] {
        func number(_ value: Int) -> [UInt8] {
            switch value {
            case -107...107: [UInt8(value + 139)]
            case 108...1131: [UInt8(247 + (value - 108) / 256), UInt8((value - 108) % 256)]
            case -1131 ... -108: [UInt8(251 + (-value - 108) / 256), UInt8((-value - 108) % 256)]
            default: [28, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
            }
        }
        func int32(_ value: Int) -> [UInt8] { [29, UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
        let scale = units / 1000
        let strings = glyphs.map { Array((names[$0.character] ?? String($0.character)).utf8) } + [Array("SquareSans-Bold".utf8)]
        let charset: [UInt8] = [0] + glyphs.indices.flatMap { [UInt8((391 + $0) >> 8), UInt8((391 + $0) & 0xFF)] }
        let charStrings = CFFFont.indexBytes([number(units) + [14]] + glyphs.map { glyph in
            number(units) + number(100 * scale) + number(0) + [21] + number(0) + number(glyph.height * scale) + [5]
                + number(800 * scale) + number(0) + [5] + number(0) + number(-glyph.height * scale) + [5] + [14]
        })
        let privateDictionary = number(30) + [10] + number(60) + [11] + number(0) + [20] + number(0) + [21]
        let header: [UInt8] = [1, 0, 4, 4] + CFFFont.indexBytes([Array("SquareSans-Bold".utf8)])
        var matrix: [UInt8] = []
        if units != 1000 {
            let digits = Array(String(format: "%.10f", 1 / Double(units)).drop { $0 == "0" }.reversed().drop { $0 == "0" }.reversed())
            var nibbles = digits.map { $0 == "." ? UInt8(0xA) : UInt8(String($0))! } + [0xF]
            if nibbles.count % 2 == 1 { nibbles.append(0xF) }
            let real = [UInt8(30)] + stride(from: 0, to: nibbles.count, by: 2).map { nibbles[$0] << 4 | nibbles[$0 + 1] }
            matrix = real + number(0) + number(0) + real + number(0) + number(0) + [12, 7]
        }
        func top(_ charsetAt: Int, _ charStringsAt: Int, _ privateAt: Int) -> [UInt8] {
            number(391 + glyphs.count) + [2] + matrix + number(box.0) + number(box.1) + number(box.2) + number(box.3) + [5]
                + int32(charsetAt) + [15] + int32(charStringsAt) + [17] + int32(privateDictionary.count) + int32(privateAt) + [18]
        }
        let middle = CFFFont.indexBytes(strings) + CFFFont.indexBytes([])
        let charsetAt = header.count + CFFFont.indexBytes([top(0, 0, 0)]).count + middle.count
        let charStringsAt = charsetAt + charset.count
        return header + CFFFont.indexBytes([top(charsetAt, charStringsAt, charStringsAt + charStrings.count)]) + middle + charset + charStrings + privateDictionary
    }

    /// A page showing `content` with the CFF font `program` as /F1.
    static func cffPage(_ content: String, _ program: [UInt8], encoding: String = "") throws -> PDFPage {
        let font = "<< /Type /Font /Subtype /Type1 /BaseFont /Square /FirstChar 65 /LastChar 67 /Widths [1000 1000 1000] /FontDescriptor 6 0 R\(encoding) >>"
        let descriptor = "<< /Type /FontDescriptor /FontName /Square /Flags 32 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 "
            + "/CapHeight 700 /StemV 80 /FontFile3 7 0 R >>"
        var bytes = pdf("1 0 0 rg " + content, resources: "/Font << /F1 5 0 R >>", extra: [font, descriptor, "FONT"])
        bytes.replaceSubrange(bytes.firstRange(of: Array("FONT".utf8))!, with: Array("<< /Subtype /Type1C /Length \(program.count) >>\nstream\n".utf8)
            + program + Array("\nendstream".utf8))
        return try PDFPage(file: PDFFile(data: bytes, path: "test.pdf"))
    }

    /// Text in an embedded CFF font: Quartz's `/Tcn` fonts, a `/Differences` encoding for the
    /// identity one, the box grown by 6% of the em up to 31 units, the Private DICT's stems
    /// (`cff` to `cff-3`).
    @Test func cffTextIsWrittenWithQuartzsFonts() throws {
        let squares: [(character: Character, height: Int)] = [("A", 700), ("B", 1000), ("C", 900)]
        #expect(try Self.content(Self.cffPage("BT /F1 6 Tf 1 2 Td (BA) Tj ET", Self.cff(squares)))
            == "q Q q /Cs1 cs 1 0 0 sc BT 6 0 0 6 1 2 Tm /Tc1 1 Tf (BA) Tj ET Q")
        let page = try Self.cffPage("BT /F1 6 Tf 1 2 Td (BA) Tj ET", Self.cff(squares, names: ["A": "square", "B": "bar"]),
                                    encoding: " /Encoding << /Differences [65 /square /bar] >>")
        #expect(try Self.content(page) == "q Q q /Cs1 cs 1 0 0 sc BT 6 0 0 6 1 2 Tm /Tc1 1 Tf (|) Tj /Tc2 1 Tf (!) Tj\nET Q")
        let text = String(decoding: QuartzPDF.rewrite(page).map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
        #expect(text.contains("<< /Type /Font /Subtype /Type1 /BaseFont /AAAAAC+SquareSans-Bold /FontDescriptor\n12 0 R /Encoding << /Type "
            + "/Encoding /Differences [ 33 /square ] >> /ToUnicode\n13 0 R /FirstChar 33 /LastChar 33 /Widths [ 1000 ] >>"))
        #expect(text.contains("[-31 -31 1031 1031] /ItalicAngle 0 /Ascent 1000 /Descent 0"))
        #expect(text.contains("/StemV 60") && text.contains("/StemH 30") && text.contains("/MaxWidth 1062"))
        #expect(text.contains("<< /Subtype /Type1C /Length "))
        let small = try CFFFont(Self.cff(squares.map { ($0.character, $0.height) }, units: 500, box: (0, 0, 500, 500)), path: "test")
        #expect(PDFFontProgram.cff(small).descriptorEntries().prefix(2) == ["/FontBBox", "[-60 -60 1060 1060]"])
        #expect(small.advance(1) == 1)
    }

    @Test func cffTextIsDrawnInRasters() throws {
        let page = try Self.cffPage("BT /F1 10 Tf 0 0 Td (B) Tj ET", Self.cff([("A", 700), ("B", 1000), ("C", 900)]))
        let canvas = PDFRaster.draw(page, width: 20, height: 10, colors: try PDFRaster.Colors(page), extended: false)
        let pixel = { (x: Int, y: Int) in Array(canvas.pixels[(y * 20 + x) * 4..<(y * 20 + x) * 4 + 4]) }
        #expect(pixel(2, 5) == [1, 0, 0, 1])
        #expect(pixel(15, 5) == [0, 0, 0, 0])
    }

    /// An image XObject's dictionary followed by its samples (Flate-compressed when `flate`).
    static func image(_ samples: [UInt8], width: Int, height: Int, entries: String) -> [UInt8] {
        Array("<< /Type /XObject /Subtype /Image /Width \(width) /Height \(height)\(entries) /Length \(samples.count) >>\nstream\n".utf8)
            + samples + Array("\nendstream".utf8)
    }

    /// A baseline JPEG of one 8-bit gray component, every block flat mid gray.
    static func grayJPEG(width: Int, height: Int) -> [UInt8] {
        func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] { [0xFF, marker, UInt8((body.count + 2) >> 8), UInt8((body.count + 2) & 0xFF)] + body }
        let blocks = ((width + 7) / 8) * ((height + 7) / 8)
        var bits = String(repeating: "00", count: blocks)
        bits += String(repeating: "1", count: (8 - bits.count % 8) % 8)
        let scan = stride(from: 0, to: bits.count, by: 8).map { UInt8(String(Array(bits)[$0..<($0 + 8)]), radix: 2)! }
        return [0xFF, 0xD8] + segment(0xDB, [0] + [UInt8](repeating: 1, count: 64))
            + segment(0xC0, [8, UInt8(height >> 8), UInt8(height & 0xFF), UInt8(width >> 8), UInt8(width & 0xFF), 1, 1, 0x11, 0])
            + segment(0xC4, [0x00, 1] + [UInt8](repeating: 0, count: 15) + [0]) + segment(0xC4, [0x10, 1] + [UInt8](repeating: 0, count: 15) + [0])
            + segment(0xDA, [1, 1, 0, 0, 0x3F, 0]) + scan + [0xFF, 0xD9]
    }

    /// Image XObjects stay images, numbered and written as Quartz does (`images`).
    @Test func imagesStayImages() throws {
        func file(_ content: String, resources: String, objects: [[UInt8]]) throws -> (page: PDFPage, text: String, order: [String]) {
            var data = Self.pdf(content, resources: resources)
            // The test file's objects 5 on, as raw bytes: rebuilt with them appended.
            let text = String(decoding: data, as: UTF8.self)
            var body = Array(text[..<text.range(of: "xref")!.lowerBound].utf8)
            var offsets = text.components(separatedBy: "xref\n0 5\n0000000000 65535 f \n")[1].split(separator: "\n").prefix(4).map { Int($0.prefix(10))! }
            for (index, object) in objects.enumerated() {
                offsets.append(body.count)
                body += Array("\(index + 5) 0 obj\n".utf8) + object + Array("\nendobj\n".utf8)
            }
            let xref = body.count
            body += Array("xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n".utf8) + offsets.flatMap { Array(String(format: "%010d 00000 n \n", $0).utf8) }
            body += Array("trailer\n<< /Size \(offsets.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8)
            data = body
            let page = try PDFPage(file: PDFFile(data: data, path: "test.pdf"))
            let written = String(decoding: QuartzPDF.rewrite(page).map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
            return (page, written, written.split(separator: "\n").filter { $0.hasSuffix(" 0 obj") }.map { String($0.split(separator: " ")[0]) })
        }
        let rgb: [UInt8] = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0], gray: [UInt8] = [0, 85, 170, 255]
        let draw = "q 16 0 0 8 2 1 cm /Im1 Do Q", xobject = "/XObject << /Im1 5 0 R >>"
        let masked = try file(draw, resources: xobject, objects: [Self.image(rgb, width: 2, height: 2, entries: " /ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask 6 0 R"),
                                                               Self.image(gray, width: 2, height: 2, entries: " /ColorSpace /DeviceGray /BitsPerComponent 8")])
        #expect(try Self.content(masked.page) == "q Q q q 16 0 0 8 2 1 cm /Im1 Do Q Q")
        #expect(masked.order == ["4", "1", "3", "5", "7", "8", "6", "2", "9", "10"])
        #expect(masked.text.contains("<< /ProcSet [ /PDF /ImageB /ImageC /ImageI ] /XObject << /Im1 5 0 R >> >>"))
        #expect(masked.text.contains("/Width 2 /Height 2 /ColorSpace 6 0 R /SMask\n7 0 R /BitsPerComponent 8"))
        #expect(masked.text.contains("/ColorSpace /DeviceGray\n/BitsPerComponent 8"))
        #expect(masked.text.contains("/Version /1.4"))
        let stencil = try file("0 0 1 rg " + draw, resources: xobject, objects: [Self.image([0x40, 0x80], width: 2, height: 2, entries: " /ImageMask true")])
        #expect(try Self.content(stencil.page) == "q Q q /Cs1 cs 0 0 1 sc q 16 0 0 8 2 1 cm /Im1 Do Q Q")
        #expect(stencil.order == ["4", "1", "3", "5", "7", "6", "2", "8", "9"])
        let jpeg = Self.grayJPEG(width: 16, height: 8)
        let kept = try file(draw, resources: xobject, objects: [Self.image(jpeg, width: 16, height: 8,
                                                                           entries: " /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /DCTDecode")])
        #expect(kept.text.contains("/Length \(jpeg.count) /Filter /DCTDecode"))
        if case .image(let image)? = kept.page.items.first {
            #expect(image.samples.data == [UInt8](repeating: 128, count: 128))
        } else {
            Issue.record("no image")
        }
    }

    /// Alpha soft masks: an ExtGState after the colors, the mask's form after the color spaces
    /// (`smasks`).
    @Test func alphaSoftMasks() throws {
        let mask = Self.form("0 0 0 rg 4 2 12 6 re f", entries: " /Group << /S /Transparency >>")
        let states = "/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> /G2 << /SMask /None >> >>"
        let page = try Self.page("/G1 gs 1 0 0 rg 0 0 8 10 re f /G2 gs 10 0 10 10 re f", resources: states, extra: [mask])
        #expect(try Self.content(page) == "q Q q /Cs1 cs 1 0 0 sc /Gs1 gs 0 0 8 10 re f /Gs2 gs 10 0 10 10 re f Q")
        let text = String(decoding: QuartzPDF.rewrite(page).map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
        #expect(text.split(separator: "\n").filter { $0.hasSuffix(" 0 obj") }.map { String($0.split(separator: " ")[0]) }
            == ["4", "1", "3", "6", "7", "10", "5", "9", "8", "2", "11", "12"])
        #expect(text.contains("<< /Type /ExtGState /SMask << /G 9 0 R /S /Alpha >> >>"))
        #expect(text.contains("<< /Type /ExtGState /SMask /None >>"))
        #expect(text.contains("<< /Type /XObject /Subtype /Form /FormType 1 /Resources 8 0 R /BBox [0 0 20 10]"))
        #expect(text.contains("/CS /DeviceGray /I true /K false"))
        let ignored = try Self.page("/G1 gs 1 0 0 rg 0 0 20 10 re f", resources: states, extra: [Self.form("0 0 0 rg 4 2 12 6 re f")])
        #expect(try Self.content(ignored) == "q Q q /Cs1 cs 1 0 0 sc 0 0 20 10 re f Q")
    }

    /// Shadings and shading patterns: functions sampled again or kept, numbered and ordered as
    /// Quartz does (`shadings`).
    /// Luminosity masks: `/BC` written, a gray group its own space sharing DeviceGray's object,
    /// a transfer function sampled, a group without a space ignored (`smasks-2`).
    @Test func luminositySoftMasks() throws {
        func file(_ mask: String, group: String = " /CS /DeviceGray", entries: String = "", extra: [String] = []) throws -> (content: String, file: String) {
            let page = try Self.page("/G1 gs 1 0 0 rg 0 0 20 10 re f", resources: "/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R\(entries) >> >> >>",
                                     extra: [Self.form(mask, entries: " /Group << /S /Transparency\(group) >>")] + extra)
            return (try Self.content(page), String(decoding: QuartzPDF.rewrite(page).map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self))
        }
        let gray = try file("0.5 g 4 2 12 6 re f")
        #expect(gray.file.contains("<< /Type /ExtGState /SMask << /G 8 0 R /S /Luminosity /BC [ 0 ] >> >>"))
        #expect(gray.file.contains("/Group << /S /Transparency /CS 10 0 R /I true /K false >>"))
        #expect(gray.file.contains("<< /ProcSet [ /PDF ] /ColorSpace << /Cs3 10 0 R >> >>"))
        #expect(gray.file.split(separator: "\n").filter { $0.hasSuffix(" 0 obj") }.map { String($0.split(separator: " ")[0]) }
            == ["4", "1", "3", "6", "9", "5", "8", "7", "11", "10", "2", "12", "13"])
        let rgb = try file("0 0 1 rg 4 2 12 6 re f", group: " /CS /DeviceRGB", entries: " /BC [1 0 0]")
        #expect(rgb.file.contains("/S /Luminosity /BC [ 1 0 0 ] >> >>") && rgb.file.contains("/CS 5 0 R /I true"))
        let transfer = try file("0.5 g 4 2 12 6 re f", entries: " /TR 6 0 R", extra: ["<< /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >>"])
        #expect(transfer.file.contains("/S /Luminosity /BC [ 0 ] /TR 9 0 R\n>> >>"))
        #expect(transfer.file.contains("9 0 obj\n<< /FunctionType 0 /BitsPerSample 8 /Size [ 4096 ] /Domain [ 0 1 ] /Range\n[ 0 1 ]"))
        #expect(try file("0.5 g 4 2 12 6 re f", entries: " /TR /Identity").file.contains("/BC [ 0 ] >> >>"))
        #expect(try file("0.5 g 4 2 12 6 re f", group: "").content == "q Q q /Cs1 cs 1 0 0 sc 0 0 20 10 re f Q")
        let rgbGroup = try file("0.5 g 4 2 12 6 re f", group: " /CS /DeviceRGB")
        #expect(rgbGroup.file.contains("/CS 5 0 R /I true") && rgbGroup.file.contains("/ColorSpace << /Cs3 10 0 R >>"))
        let postscript = try file("0.5 g 4 2 12 6 re f", entries: " /TR 6 0 R",
                                  extra: ["<< /FunctionType 4 /Domain [0 1] /Range [0 1] /Length 14 >>\nstream\n{ 1 exch sub }\nendstream"])
        #expect(postscript.file.contains("/TR 9 0 R"))
        #expect(postscript.file.range(of: "/Type /Catalog")!.lowerBound < postscript.file.range(of: "9 0 obj\n<< /FunctionType 4")!.lowerBound)
        let page = try Self.page("/G1 gs 1 0 0 rg 0 0 20 10 re f", resources: "/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> >>",
                                 extra: [Self.form("1 g 0 0 10 10 re f", entries: " /Group << /S /Transparency /CS /DeviceGray >>")])
        let canvas = PDFRaster.draw(page, width: 20, height: 10, colors: try PDFRaster.Colors(page), extended: false)
        #expect(canvas.pixels[(5 * 20 + 5) * 4 + 3] > 0.99)
        #expect(canvas.pixels[(5 * 20 + 15) * 4 + 3] == 0)
    }

    /// What shadings, images and groups are drawn with: the rendering intent, opacity and
    /// overprinting as fills, a shading in a group perceptual, a group's stroke opacity dropped;
    /// the forms' ExtGStates after the page's in number order (`shadings-2`, `images-2`,
    /// `groups-4`, `groups-5`, `groups-6`).
    @Test func settingsBeforeShadingsImagesAndGroups() throws {
        let shading = "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> >>"
        #expect(try Self.content(Self.page("/G1 gs /Sh1 sh", resources: "/Shading << /Sh1 \(shading) >> /ExtGState << /G1 << /OPM 1 /ca 0.5 >> >>"))
            == "q Q q /Gs1 gs /Gs2 gs /Sh1 sh Q")
        let image = "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8 /Intent /Perceptual /Length 4 >>\n"
            + "stream\n\u{0}U\u{78}\u{7F}\nendstream"
        let imagePage = try Self.page("/Saturation ri /G1 gs q 16 0 0 8 2 1 cm /Im1 Do Q", resources: "/XObject << /Im1 5 0 R >> /ExtGState << /G1 << /op true >> >>",
                                      extra: [image])
        #expect(try Self.content(imagePage) == "q Q q /Saturation ri /Gs1 gs q 16 0 0 8 2 1 cm /Im1 Do Q Q")
        #expect(String(decoding: QuartzPDF.rewrite(imagePage).map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self).contains("/Intent\n/Perceptual"))
        let group = Self.form("/G2 gs /Sh1 sh", entries: " /Group << /S /Transparency >> /Resources << /ExtGState << /G2 << /ca 0.25 >> >> /Shading << /Sh1 \(shading) >> >>")
        let groupPage = try Self.page("/G1 gs /X1 Do", resources: "/XObject << /X1 5 0 R >> /ExtGState << /G1 << /OPM 1 /CA 0.5 >> >>", extra: [group])
        #expect(try Self.content(groupPage) == "q Q q /Gs1 gs /Fm1 Do Q")
        let file = String(decoding: QuartzPDF.rewrite(groupPage).map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
        let numbers = file.matches(of: /\n(\d+) 0 obj\n<< \/Type \/ExtGState/).map { Int($0.1)! }
        #expect(numbers == numbers.sorted() && numbers.count == 2)
        #expect(file.contains("<< /Type /ExtGState /OPM 1 >>") && !file.contains("/CA"))
    }

    @Test func shadingsAndPatterns() throws {
        func order(_ page: PDFPage) -> (order: [String], text: String) {
            let text = String(decoding: QuartzPDF.rewrite(page).map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
            return (text.split(separator: "\n").filter { $0.hasSuffix(" 0 obj") }.map { String($0.split(separator: " ")[0]) }, text)
        }
        let axial = "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>"
        let exponential = "<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"
        let sh = try Self.page("/Sh1 sh", resources: "/Shading << /Sh1 5 0 R >>", extra: [axial, exponential])
        #expect(try Self.content(sh) == "q Q q /Sh1 sh Q")
        let written = order(sh)
        #expect(written.order == ["4", "1", "3", "5", "8", "6", "7", "2", "9", "10"])
        #expect(written.text.contains("<< /ColorSpace 6 0 R /ShadingType 2 /Coords [ 2 0 18 0 ] /Domain [ 0 1 ]"))
        #expect(written.text.contains("<< /FunctionType 0 /BitsPerSample 8 /Size [ 1365 ] /Domain [ 0 1 ] /Range"))
        let program = "{ dup 1 exch sub exch 0 exch }"
        let postScript = "<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length \(program.utf8.count) >>\nstream\n\(program)\nendstream"
        let kept = order(try Self.page("/Sh1 sh", resources: "/Shading << /Sh1 5 0 R >>", extra: [axial, postScript]))
        #expect(kept.order == ["4", "1", "3", "5", "8", "6", "2", "9", "7", "10"])
        let pattern = try Self.page("/Pattern cs /P1 scn 2 2 16 6 re f", resources: "/Pattern << /P1 5 0 R >>",
                                    extra: ["<< /PatternType 2 /Shading 6 0 R >>", axial.replacingOccurrences(of: "6 0 R", with: "7 0 R"), exponential])
        #expect(try Self.content(pattern) == "q Q q /Pattern cs /P1 scn 2 2 16 6 re f Q")
        #expect(order(pattern).order == ["4", "1", "3", "6", "7", "10", "8", "9", "2", "11", "12"])
        #expect(PostScriptCalculator.run(Array(program.utf8), input: 0.25, outputs: 3) == [0.75, 0, 0.25])
        #expect(PostScriptCalculator.run(Array("{ dup 0.5 gt { pop 1 } { 2 mul } ifelse }".utf8), input: 0.25, outputs: 1) == [0.5])
    }

    /// A group's content is clipped to the bounding box of the page, the clips around it and its
    /// own, rounded out (`groups-2` in-path-clip; corpus: kickstarter's `icon--apple-pay.pdf`).
    @Test func groupContentClipsToWholeUnits() throws {
        let xobject = "/XObject << /X1 5 0 R >>", group = " /Group << /S /Transparency >>"
        func clip(_ page: String, bbox: String = "0 0 20 10") throws -> PDFPage.Rect? {
            guard case .group(let found)? = try Self.page(page, resources: xobject, extra: [Self.form("1 0 0 rg 0 0 20 10 re f", bbox: bbox, entries: group)])
                .items.first, case .drawing(let drawing)? = found.items.first else { return nil }
            return drawing.clips.first?.path.rectangle
        }
        #expect(try clip("q 2 2 m 10 2 l 6 8 l h W n /X1 Do Q") == PDFPage.Rect(minX: 2, minY: 2, maxX: 10, maxY: 8))
        #expect(try clip("/X1 Do", bbox: "0.026 0.43 19.79 9.98") == PDFPage.Rect(minX: 0, minY: 0, maxX: 20, maxY: 10))
        #expect(try clip("/X1 Do", bbox: "-5 -5 30 15") == PDFPage.Rect(minX: 0, minY: 0, maxX: 20, maxY: 10))
    }

    /// A PDF per luminosity appearance, each compiled with it; an atlas link's key lists the
    /// appearance after the scale (`appearances`).
    /// A PDF per idiom is compiled as it alone, its renditions keyed with its idiom; a file per
    /// scale stops nomac (`entries-2`).
    @Test func idiomEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-pdf-idioms-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(Self.pdf("1 0 0 rg 2 2 16 6 re f")).write(to: folder.appendingPathComponent("a.pdf"))
        try Data(Self.pdf("0 0 1 rg 2 2 16 6 re f")).write(to: folder.appendingPathComponent("b.pdf"))
        let idioms = ["universal": Idiom.universal, "ipad": Idiom.pad]
        let asset = AssetCatalog.Asset(name: "A", type: "imageset", path: folder.path,
                                       contents: ["images": [["filename": "a.pdf", "idiom": "universal"], ["filename": "b.pdf", "idiom": "ipad"]]])
        let sources = try ImageSet.sources(asset, idioms: idioms)
        #expect(sources.map(\.idiom) == [Idiom.universal, Idiom.universal, Idiom.universal, Idiom.pad, Idiom.pad, Idiom.pad])
        #expect(sources.filter { $0.vectorData != nil }.map(\.idiom) == [Idiom.universal, Idiom.pad])
        let scales = AssetCatalog.Asset(name: "A", type: "imageset", path: folder.path,
                                        contents: ["images": [["filename": "a.pdf", "idiom": "universal", "scale": "1x"],
                                                              ["filename": "b.pdf", "idiom": "universal", "scale": "2x"]]])
        #expect(throws: (any Error).self) { try ImageSet.sources(scales, idioms: idioms) }
    }

    @Test func appearances() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-pdf-appearances-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(Self.pdf("1 0 0 rg 2 2 16 6 re f")).write(to: folder.appendingPathComponent("a.pdf"))
        try Data(Self.pdf("0 0 1 rg 2 2 16 6 re f")).write(to: folder.appendingPathComponent("b.pdf"))
        let dark: [String: Any] = ["filename": "b.pdf", "idiom": "universal", "appearances": [["appearance": "luminosity", "value": "dark"]]]
        let asset = AssetCatalog.Asset(name: "A", type: "imageset", path: folder.path,
                                       contents: ["images": [["filename": "a.pdf", "idiom": "universal"], dark]])
        let sources = try ImageSet.sources(asset, idioms: ["universal": Idiom.universal])
        #expect(sources.map(\.appearance) == [0, 0, 0, 1, 1, 1])
        #expect(sources.filter { $0.vectorData != nil }.map(\.appearance) == [0, 1])
        #expect(ImageSet.keyBytes([(.appearance, 1), (.scale, 2), (.element, 9), (.part, 181)]) == [1, 0, 9, 0, 2, 0, 181, 0, 12, 0, 2, 0, 7, 0, 1, 0, 0, 0, 0, 0])
        var both = dark
        both["appearances"] = [["appearance": "luminosity", "value": "dark"], ["appearance": "contrast", "value": "high"]]
        #expect(throws: (any Error).self) { try ImageSet.entryAppearance(both, asset: asset) }
    }

    /// Details the corpus showed: offsets only with their apostrophes (`info`), PostScript programs
    /// written again (`postscript`), every trailer read, objects right after `endobj`.
    @Test func corpusDetails() throws {
        #expect(PDFPage.utcDate(Array("D:20240615123456+02'00'".utf8)) == "20240615103456")
        #expect(PDFPage.utcDate(Array("D:20240615123456+02'".utf8)) == "20240615103456")
        #expect(PDFPage.utcDate(Array("D:20240615123456+02'00".utf8)) == "20240615123456")
        #expect(PDFPage.utcDate(Array("D:20240615123456+0200".utf8)) == "20240615123456")
        let program = "{  0.361688 exch dup 0.000000 gt { dup 0.000000 sub -0.189139 mul 1.000000 mul 0.1234567891 add } if 1 div }\n"
        #expect(String(decoding: PostScriptCalculator.rewritten(Array(program.utf8)), as: UTF8.self)
            == "{ 0.361688 exch dup 0 gt { dup -0.189139 mul 0.123457 add } if 1 div }")
        #expect(String(decoding: PostScriptCalculator.rewritten(Array("{ dup 0.000000 sub 0.000000 mul 0.000000 add exch }".utf8)), as: UTF8.self)
            == "{ 0 exch }")
        #expect(String(decoding: PostScriptCalculator.rewritten(Array("{ 123.4567891 mul 12345678.5 add 0.0000006 add -1.860232 0 1 add 2 1 sub 0 2 mul }".utf8)),
                       as: UTF8.self) == "{ 123.4568 mul 12345678 add 0 add -1.860232 1 1 0 }")
        var text = String(decoding: Self.pdf("1 0 0 rg 2 2 16 6 re f"), as: UTF8.self)
        text = text.replacingOccurrences(of: "trailer\n<<", with: "trailer\n<< /Info 6 0 R")
        text = text.replacingOccurrences(of: "endobj\nxref", with: "endobj6 0 obj\n<< /Producer (P) >>\nendobj\nxref")
        text += "trailer\n<< /Size 7 >>\n"
        #expect(try PDFPage(file: PDFFile(data: Array(text.utf8), path: "test.pdf")).producer == "P")
    }

    /// A rectangle clip around the rectangles in force is not written; a clip without area hides
    /// what is drawn under it (corpus: kickstarter's `icon-expansion.pdf`, cwa's flags).
    @Test func clipsThatChangeNothing() throws {
        #expect(try Self.content(Self.page("q 2 2 10 6 re W n 1 0 0 rg 2 2 4 4 re f q 0 0 20 10 re W n 6 2 4 4 re f Q Q"))
            == "q Q q 2 2 10 6 re W n /Cs1 cs 1 0 0 sc 2 2 4 4 re f 6 2 4 4 re f Q")
        #expect(try Self.content(Self.page("1 0 0 rg q 3 1 m 3 9 l W n 2 2 4 4 re f Q 8 2 4 4 re f")) == "q Q q /Cs1 cs 1 0 0 sc 8 2 4 4 re f Q")
    }

    @Test func groupBoundsFollowQuartz() throws {
        let xobject = "/XObject << /X1 5 0 R >>", group = " /Group << /S /Transparency >>"
        func bounds(_ content: String, page: String = "/X1 Do", bbox: String = "0 0 20 10") throws -> PDFPage.Rect? {
            guard case .group(let found)? = try Self.page(page, resources: xobject, extra: [Self.form(content, bbox: bbox, entries: group)]).items.first else { return nil }
            return found.bounds
        }
        #expect(try bounds("1 0 0 rg 2 2 m 2 12 18 12 18 2 c f", bbox: "0 0 20 20") == PDFPage.Rect(minX: 2, minY: 2, maxX: 18, maxY: 9.5))
        #expect(try bounds("2 w 5 5 m 15 5 l S", bbox: "-100 -100 200 200") == PDFPage.Rect(minX: -5, minY: -5, maxX: 25, maxY: 15))
        #expect(try bounds("2 w 1 j 5 5 m 15 5 l S", bbox: "-100 -100 200 200") == PDFPage.Rect(minX: 3, minY: 3, maxX: 17, maxY: 7))
        #expect(try bounds("4 w 3 M 5 5 m 15 5 l S", bbox: "-100 -100 200 200") == PDFPage.Rect(minX: -1, minY: -1, maxX: 21, maxY: 11))
        #expect(try bounds("0 w 5 5 m 15 5 l S", bbox: "-100 -100 200 200") == PDFPage.Rect(minX: -100, minY: -100, maxX: 200, maxY: 200))
        #expect(try bounds("1 w 1 M q 2 0 0 2 0 0 cm 5 3 m 8 3 l S Q", bbox: "-100 -100 200 200") == PDFPage.Rect(minX: 8, minY: 4, maxX: 18, maxY: 8))
        #expect(try bounds("0 0 1 RG 2 w 1 1 m 8 4 l S 1 0 0 rg 1 6 4 2 re f", page: "q 0 1 -1 0 15 0 cm /X1 Do Q")
            == PDFPage.Rect(minX: 5, minY: 0, maxX: 15, maxY: 18))
        #expect(try bounds("4 0 8 10 re W n 1 0 0 rg 2 2 16 6 re f") == PDFPage.Rect(minX: 4, minY: 2, maxX: 12, maxY: 8))
        #expect(try bounds("1 0 0 rg 2 2 16 6 re f", page: "q 0 0 10 10 re W n /X1 Do Q") == PDFPage.Rect(minX: 2, minY: 2, maxX: 18, maxY: 8))
    }

    @Test func theFileTakesQuartzsLayout() throws {
        let file = QuartzPDF.rewrite(try Self.page("/G1 gs 1 0 0 rg 2 2 16 6 re f", resources: "/ExtGState << /G1 << /ca 0.5 >> >>"))
        let text = String(decoding: file.map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
        #expect(file.starts(with: Array("%PDF-1.3\n%".utf8) + [0xC4, 0xE5, 0xF2, 0xE5, 0xEB, 0xA7, 0xF3, 0xA0, 0xD0, 0xC4, 0xC6, 0x0A]))
        let numbers = text.matches(of: /\n(\d+) 0 obj\n/).map { Int($0.1)! }
        #expect(numbers == [4, 1, 3, 6, 7, 5, 2, 8, 9])
        #expect(text.contains("3 0 obj\n<< /ProcSet [ /PDF ] /ColorSpace << /Cs1 5 0 R >> /ExtGState << /Gs1 6 0 R\n>> >>\nendobj"))
        #expect(text.contains("2 0 obj\n<< /Type /Pages /MediaBox [0 0 20 10] /Count 1 /Kids [ 1 0 R ] >>\nendobj"))
        #expect(text.hasSuffix("trailer\n<< /Size 10 /Root 8 0 R /Info 9 0 R /ID [ <00000000000000000000000000000000>\n<00000000000000000000000000000000> ] >>\nstartxref\n\(text.range(of: "\nxref\n")!.lowerBound.utf16Offset(in: text) + 1)\n%%EOF\n"))
    }

    @Test func infoKeepsTheProducerAndTheCreationDate() throws {
        let page = try Self.page("", info: "<< /Producer (a\\(b\\)c\\\\d\\ne) /Title (T) /CreationDate (D:20240615123456+02'00') /ModDate (D:20250101) >>")
        #expect(page.producer == "a(b)c\\d\ne")
        #expect(page.creationDate == "20240615103456")
        #expect(QuartzPDF.literal(page.producer!) == "(a\\(b\\)c\\\\d\\012e)")
        #expect(QuartzPDF.literal("Café").unicodeScalars.map(\.value) == [40, 0xFE, 0xFF, 92, 48, 48, 48, 67, 92, 48, 48, 48, 97, 92, 48, 48, 48, 102, 92, 48, 48, 48, 0xE9, 41])
        #expect(PDFPage.utcDate(Array("D:2024".utf8)) == "20240101000000")
        #expect(PDFPage.utcDate(Array("D:20240615123456-05'30'".utf8)) == "20240615180456")
        #expect(PDFPage.utcDate(Array("Value".utf8)) == nil)
    }

    @Test func unobservedFeaturesAreRefused() {
        #expect(throws: (any Error).self) { try Self.page("/G1 gs 1 0 0 rg 2 2 16 6 re f", resources: "/ExtGState << /G1 << /BM /Multiply >> >>") }
    }

    @Test func rastersFillTheImage() {
        let page = try! Self.page("1 0 0 rg 0 0 10 5 re f")
        let canvas = PDFRaster.draw(page, width: 40, height: 20, colors: try! PDFRaster.Colors(page), extended: false)
        let pixel = { (x: Int, y: Int) in Array(canvas.pixels[(y * 40 + x) * 4..<(y * 40 + x) * 4 + 4]) }
        #expect(pixel(5, 15) == [1, 0, 0, 1])
        #expect(pixel(30, 5) == [0, 0, 0, 0])
    }
}
