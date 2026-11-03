import Foundation
import NomacCore
import NomacPlist
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Icon Composer icons as `assets-experiments icons` observed them: the colors, gradients, stacks,
/// groups and layer images actool writes, which nomac writes byte for byte, and the rendered
/// images, which are nomac's own (ADR 0204).
@Suite struct IconComposerTests {
    static let glyph = """
        <svg width="300" height="280" viewBox="0 0 300 280" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M150 0C170 0 185 10 195 30L295 230C305 250 290 280 265 280C250 280 240 272 232 258L150 110L68 258C60 272 50 280 35 280C10 280 -5 250 5 230L105 30C115 10 130 0 150 0Z" fill="white"/>
        </svg>

        """
    static let dot = "<svg width=\"100\" height=\"100\" viewBox=\"0 0 100 100\" xmlns=\"http://www.w3.org/2000/svg\"><circle cx=\"50\" cy=\"50\" r=\"40\" fill=\"#e04020\"/></svg>\n"
    static let wide = "<svg width=\"200\" height=\"150\" viewBox=\"0 0 200 150\" xmlns=\"http://www.w3.org/2000/svg\"><rect x=\"0\" y=\"0\" width=\"200\" height=\"150\" fill=\"#00ff00\"/></svg>\n"

    /// The experiment's grid: lines every 16 pixels, crosses every 64.
    static func grid(_ side: Int) -> [UInt8] {
        let rows: [[UInt8]] = (0..<side).map { y in
            (0..<side).flatMap { x -> [UInt8] in
                if [31, 32].contains(x % 64) && abs(y % 64 - 32) < 6 || [31, 32].contains(y % 64) && abs(x % 64 - 32) < 6 { return [255, 255, 255, 200] }
                return x % 16 == 0 || y % 16 == 0 ? [255, 255, 255, 40] : [0, 0, 0, 0]
            }
        }
        return ImageSetTests.png(width: side, height: side, colorType: 6, rows: rows)
    }

    static let composite = """
        {"fill": {"linear-gradient": ["srgb:0.20000,0.40000,0.60000,1.00000", "display-p3:0.90000,0.30000,0.10000,1.00000"],
                  "orientation": {"start": {"x": 0.1, "y": 0.2}, "stop": {"x": 0.8, "y": 0.9}}},
         "groups": [
          {"layers": [{"image-name": "glyph.svg", "name": "glyph", "position": {"scale": 0.5, "translation-in-points": [10.25, -20.5]}},
                      {"image-name": "grid.png", "name": "grid", "opacity": 0.5, "fill": {"solid": "gray:0.25000,0.50000"}}],
           "shadow": {"kind": "layer-color", "opacity": 0.7}, "translucency": {"enabled": true, "value": 0.6}},
          {"layers": [{"image-name": "dot.svg", "name": "dot", "blend-mode": "multiply", "glass": false,
                       "fill-specializations": [{"appearance": "dark", "value": {"linear-gradient": ["srgb:1.00000,0.00000,0.00000,1.00000", "gray:0.50000,1.00000"]}}]},
                      {"image-name": "glyph.svg", "name": "copy", "hidden-specializations": [{"value": true}, {"appearance": "dark", "value": false}]}],
           "lighting": "combined", "specular": false, "blur-material": 0.25, "opacity": 0.8,
           "position": {"scale": 1.25, "translation-in-points": [3, 4]}},
          {"layers": [{"image-name": "dot.svg", "name": "gone"}], "hidden": true}]}
        """

    static func writeIcon(_ path: String, json: String) throws {
        try FileSystem.write(Data(json.utf8), to: path + "/icon.json")
        try FileSystem.write(Data(glyph.utf8), to: path + "/Assets/glyph.svg")
        try FileSystem.write(Data(dot.utf8), to: path + "/Assets/dot.svg")
        try FileSystem.write(Data(wide.utf8), to: path + "/Assets/wide.svg")
        try FileSystem.write(Data(grid(64)), to: path + "/Assets/grid.png")
    }

    /// Every rendition of the `composite` case but the rendered images, compared by the SHA-256 of
    /// their CSIs in byte order with actool's.
    @Test func compositeIconGivesActoolsRenditions() throws {
        let temporary = try TemporaryDirectory()
        let path = temporary.path + "/Composite.icon"
        try Self.writeIcon(path, json: Self.composite)
        let icon = try IconComposerIcon(path: path)
        let identifiers = RenditionIdentifier.assign(icon.facetNames)
        let compiled = try icon.compile(identifiers: identifiers, appIcon: true, targetDevices: ["iphone", "ipad"])
        let images = try ImageSet.renditions(compiled.sources.filter { $0.kind != .appIcon }, identifiers: identifiers)
        let csis = (compiled.renditions + images).map(\.csi).sorted { $0.lexicographicallyPrecedes($1) }
        #expect(csis.count == 25)
        #expect(ColorCatalogTests.hex(SHA256.digest(csis.flatMap { $0 })) == "4878c021833f62c193d9bc50a9e55d5be1f80b0675403abd67997fd983b35778")
        #expect(compiled.pngs.map(\.filename) == ["Composite60x60@2x.png", "Composite76x76@2x~ipad.png"])
        #expect(compiled.sources.filter { $0.kind == .appIcon }.count == 6)
    }

    /// Colors are named in creation order and kept once: white, the light fill, the dark fill,
    /// then the layers' fills (`icons` fills cases).
    @Test func paintsAreNamedInCreationOrder() throws {
        let temporary = try TemporaryDirectory()
        let path = temporary.path + "/Glyph.icon"
        try Self.writeIcon(path, json: """
            {"fill": {"automatic-gradient": "extended-srgb:0.00000,0.47843,1.00000,1.00000"},
             "groups": [{"layers": [{"image-name": "glyph.svg", "name": "glyph"}, {"image-name": "dot.svg", "name": "dot", "fill": {"solid": "srgb:1.00000,0.00000,0.00000,1.00000"}}]}]}
            """)
        let icon = try IconComposerIcon(path: path)
        let paints = icon.paints()
        #expect(paints.colors.map(\.space) == [6, 4, 2, 2, 1])
        #expect(paints.colors[1].components == [0, Double(Float(0.478)), 1, 1])
        #expect(paints.gradients.map(\.name) == ["Gradient-1", "system-dark"])
        #expect(icon.layerPaint(icon.groups[0].layers[0], .dark) == icon.fill.light)
        #expect(icon.layerPaint(icon.groups[0].layers[0], .light) == nil)
    }

    /// Components keep three decimals of their value (`icons` F08, C05; icecubes' 0.0065).
    @Test(arguments: [(0.12345, 0.123), (0.1235, 0.123), (0.1245, 0.124), (0.0005, 0.001), (0.9995, 1.0), (0.99949, 0.999), (0.00049, 0.0), (0.47843, 0.478), (0.0065, 0.006)])
    func componentsAreRounded(value: Double, stored: Double) {
        #expect(IconComposerIcon.stored(value) == Double(Float(stored)))
    }

    /// A layer's size is the image's times both scales, ties to even; its origin is rounded down
    /// (`icons` positions cases).
    @Test func layersArePlacedOnTheCanvas() throws {
        let temporary = try TemporaryDirectory()
        let path = temporary.path + "/P.icon"
        try Self.writeIcon(path, json: """
            {"groups": [
             {"layers": [{"image-name": "dot.svg", "position": {"scale": 0.33, "translation-in-points": [0.5, 0.25]}}]},
             {"layers": [{"image-name": "dot.svg", "position": {"scale": 1.5, "translation-in-points": [-0.5, -0.75]}}]},
             {"layers": [{"image-name": "dot.svg", "position": {"scale": 0.5, "translation-in-points": [10, 20]}}], "position": {"scale": 2, "translation-in-points": [30, -40]}},
             {"layers": [{"image-name": "wide.svg", "position": {"scale": 1.24, "translation-in-points": [1.5, 2.5]}}]}]}
            """)
        let icon = try IconComposerIcon(path: path)
        let rects = icon.groups.map { icon.rect($0.layers[0], in: $0, .light) }
        #expect(rects.map { [$0.x, $0.y, $0.width, $0.height] } == [[496, 495, 33, 33], [436, 436, 150, 150], [512, 462, 100, 100], [389, 421, 248, 186]])
    }

    /// An SVG layer is white when each fill's Display P3 lightness is 0.85 or more (`icons` white).
    @Test(arguments: [("#FFFFFF", true), ("#D9D9D9", true), ("#D8D8D8", false), ("#FFC0C0", true), ("#FFB6B6", false), ("#B0FFB0", true),
                      ("#C8E8C8", true), ("#E8C8C8", false), ("#E2D2D2", true), ("#EAC3F0", false), ("#808080", false)])
    func whiteLayers(color: String, white: Bool) throws {
        let svg = "<svg width=\"10\" height=\"10\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"10\" height=\"10\" fill=\"\(color)\"/></svg>"
        let image = IconComposerIcon.LayerImage.svg(try SVGImage(data: Data(svg.utf8), path: "c.svg"), data: Array(svg.utf8))
        #expect(image.isWhite == white)
    }

    /// Alternate icons are listed for the targeted devices (`icons` alternate cases).
    @Test func alternateIconsAreListed() throws {
        let temporary = try TemporaryDirectory()
        let path = temporary.path + "/Composite.icon"
        try Self.writeIcon(path, json: Self.composite)
        let icon = try IconComposerIcon(path: path)
        let compiled = try icon.compile(identifiers: RenditionIdentifier.assign(icon.facetNames), appIcon: true, alternates: ["Alt", "Other"], targetDevices: ["iphone"])
        let alternates: PropertyListValue = .dictionary(["Alt": .dictionary(["CFBundleIconName": .string("Alt")]), "Other": .dictionary(["CFBundleIconName": .string("Other")])])
        #expect(compiled.infoPlist["CFBundleIcons"] == .dictionary([
            "CFBundleAlternateIcons": alternates,
            "CFBundlePrimaryIcon": .dictionary(["CFBundleIconFiles": .array([.string("Composite60x60")]), "CFBundleIconName": .string("Composite")]),
        ]))
        #expect(compiled.infoPlist["CFBundleIcons~ipad"] == .dictionary([
            "CFBundlePrimaryIcon": .dictionary(["CFBundleIconFiles": .array([.string("Composite60x60"), .string("Composite76x76")])]),
        ]))
    }

    @Test func iconPNGsHaveActoolsExif() {
        #expect(ColorCatalogTests.hex(IconComposerIcon.exif(width: 120, height: 120))
            == "4d4d002a00000008000187690004000000010000001a000000000003a00100030000000100010000a00200040000000100000078a0030004000000010000007800000000")
    }

    @Test func renderedImagesAreOpaqueAndStable() throws {
        let temporary = try TemporaryDirectory()
        let path = temporary.path + "/Composite.icon"
        try Self.writeIcon(path, json: Self.composite)
        let icon = try IconComposerIcon(path: path)
        let pixels = try IconRenderer.render(icon, appearance: .dark)
        #expect(pixels.count == 1024 * 1024 * 4)
        #expect(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
        #expect(try IconRenderer.render(icon, appearance: .dark) == pixels)
    }
}
