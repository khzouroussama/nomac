import Foundation
import NomacCore
import Testing
@testable import NomacAssets

/// Symbol templates as `assets-experiments symbol-sets` and the corpus's symbol sets observed them.
@Suite struct SymbolSetTests {
    static func template(guides: String, glyphs: String, style: String = "", version: String = "<text>Template v.3.0</text>") throws -> SymbolSet.Template {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd">\
            <style>\(style)</style>\(version)<g id="Guides">\(guides)</g><g id="Symbols">\(glyphs)</g></svg>
            """
        return try SymbolSet.parse(Data(svg.utf8), path: "a.svg")
    }

    static let lines = """
        <line id="Baseline-M" x1="0" x2="10" y1="1126" y2="1126"/><line id="Capline-M" x1="0" x2="10" y1="1055.541" y2="1055.541"/>\
        <line id="Baseline-S" x1="0" x2="10" y1="696" y2="696"/><line id="Capline-S" x1="0" x2="10" y1="625.541" y2="625.541"/>
        """

    @Test func pathMarginsSitHalfTheirStrokeWidthLeftWhenStroked() throws {
        let margins = #"<path id="left-margin-Regular-S" d="M100,600 l0,110"/><path id="Baseline-L" d="M0,1556 l10,0"/>"#
        let stroked = try Self.template(guides: ##"<g stroke="#27AAE1" stroke-width="2">"## + margins + "</g>", glyphs: "")
        #expect(stroked.margins["left-margin-Regular-S"] == 99)
        #expect(stroked.guides["Baseline-L"] == 1556)
        #expect(try Self.template(guides: #"<g stroke-width="2">"# + margins + "</g>", glyphs: "").margins["left-margin-Regular-S"] == 100)
        #expect(try Self.template(guides: #"<g stroke="black">"# + margins + "</g>", glyphs: "").margins["left-margin-Regular-S"] == 99.5)
    }

    @Test func templateOneMarginsAreRectangleWidthsAndItsVersionReadsZero() throws {
        let template = try Self.template(
            guides: Self.lines + #"<rect id="left-margin" x="0" y="0" width="8" height="100"/><rect id="right-margin" x="50" y="0" width="12.5" height="100"/>"#,
            glyphs: #"<g id="Regular-M" transform="translate(1, 1126)"><path d="M0 0L40 0L40-70Z"/></g>"#,
            version: "<text><tspan>Template v.1.0</tspan></text>")
        #expect(template.version == 0)
        let sides = try #require(SymbolSet.ownSidebearings(template, "Regular-M", 0.5))
        #expect(sides.left == 4 && sides.right == 6.25)
    }

    @Test func groupTranslationsPlaceGuidesAndGlyphs() throws {
        let template = try Self.template(guides: #"<g transform="translate(0, 100)">"# + Self.lines + "</g>",
                                         glyphs: #"<g id="Regular-S" transform="matrix(1.5,0,0,1,10,20)"><path d="M0 0L40 0L40-70Z"/></g>"#)
        #expect(template.guides["Baseline-M"] == 1226)
        let transform = try #require(template.glyph("Regular-S")).transform
        #expect([transform.a, transform.d, transform.e, transform.f] == [1.5, 1, 10, 20])
    }

    @Test func glyphSVGFollowsTheStyleSheetsRules() throws {
        let style = ".monochrome-0 {-sfsymbols-motion-group:1;opacity:1.0} .SFSymbolsPreviewWireframe {fill:none;stroke:black;stroke-width:0.5} .defaults {-b:1;-a:2}"
        let glyph = """
            <g id="Regular-S" transform="translate(100, 696)"><path class="SFSymbolsPreviewWireframe" d="M0,0 L40,0 L40,-70 Z" sodipodi:nodetypes="ccc"/>\
            <g id="Arrow" transform="translate(20, -30)" stroke="#000000" stroke-width="0.2"><path class="monochrome-0" d="M0 0L10-10Z"/></g></g>
            """
        let template = try Self.template(guides: Self.lines, glyphs: glyph, style: style)
        #expect(try SymbolSet.glyphSVG(template, "Regular-S", 0.5, path: "a.svg") == """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg version="1.1" viewBox="0 0 20.25 35.25"><defs><style>.defaults{-a:2;-b:1;}.monochrome-0{opacity:1.0;-sfsymbols-motion-group:1;}</style></defs>\
            <g id="s" transform="matrix(0.5 0 0 0.5 0.125 35.125)"><path class="" d="M0 0L40 0L40-70Z" fill="none" stroke="black" stroke-width="0.25" nodetypes="ccc"/>\
            <g id="Arrow" stroke="#000000" stroke-width="0.2" transform="translate(20, -30)"><path class="monochrome-0" d="M0 0L10-10Z" opacity="1.0"/></g></g></svg>

            """)
    }
}
