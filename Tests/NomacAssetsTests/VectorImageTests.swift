import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// JPEG and SVG image sets as `assets-experiments vector-images` observed them.
@Suite struct VectorImageTests {
    static func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] {
        [0xFF, marker, UInt8((body.count + 2) >> 8), UInt8((body.count + 2) & 0xFF)] + body
    }

    /// A frame header of 40 × 30 and a scan, the rest of a JPEG nomac does not read.
    static let frame = segment(0xC0, [8, 0, 30, 0, 40, 1, 1, 0x11, 0]) + segment(0xDA, [1, 1, 0, 0, 0x3F, 0]) + [0x12, 0x34, 0xFF, 0xD9]
    static let jfif = segment(0xE0, Array("JFIF\0".utf8) + [1, 1, 0, 0, 72, 0, 72, 0, 0])
    static let icc = segment(0xE2, Array("ICC_PROFILE\0".utf8) + [1, 1, 0])
    static let orientation = segment(0xE1, Array("Exif\0\0MM".utf8) + [0, 42, 0, 0, 0, 8, 0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0])

    @Test func jpegSegmentsActoolLeavesOutAreDropped() throws {
        let xmp = Self.segment(0xE1, Array("http://ns.adobe.com/xap/1.0/\0<x/>".utf8))
        let photoshop = Self.segment(0xED, Array("Photoshop 3.0\0".utf8))
        let comment = Self.segment(0xFE, Array("hello".utf8))
        let file = try JPEGFile([0xFF, 0xD8] + Self.jfif + xmp + Self.icc + photoshop + Self.orientation + comment + Self.frame, path: "a.jpg")
        #expect(file.width == 40 && file.height == 30)
        #expect(file.stored == [0xFF, 0xD8] + Self.jfif + Self.orientation + Self.icc + Self.frame)
    }

    @Test func emptyExifIsDropped() throws {
        let empty = Self.segment(0xE1, Array("Exif\0\0II".utf8) + [42, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(try JPEGFile([0xFF, 0xD8] + empty + Self.frame, path: "a.jpg").stored == [0xFF, 0xD8] + Self.frame)
    }

    /// An SVG's images are its size times the scale rounded up, the slice its size rounded half up
    /// at the bottom (10.25 × 7.75 at 3x: 31 × 24, slice 31 × 23 at y 1).
    @Test func svgImagesAndSlices() throws {
        let temporary = try TemporaryDirectory()
        let set = temporary.path + "/A.xcassets/S.imageset"
        try FileSystem.write(Data("<svg width=\"10.25\" height=\"7.75\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"10.25\" height=\"7.75\" fill=\"#e04020\"/></svg>".utf8),
                             to: set + "/s.svg")
        try FileSystem.write(Data(#"{"images": [{"filename": "s.svg", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}"#.utf8), to: set + "/Contents.json")
        let asset = try #require(AssetCatalog.load([temporary.path + "/A.xcassets"]).assets.first)
        let sources = try ImageSet.sources(asset, idioms: ["universal": Idiom.universal])
        #expect(sources.map { [$0.image.width, $0.image.height] } == [[11, 8], [21, 16], [31, 24]])
        #expect(sources.map { [$0.slice!.x, $0.slice!.y, $0.slice!.width, $0.slice!.height] } == [[0, 0, 10, 8], [0, 0, 21, 16], [0, 1, 31, 23]])
        #expect(sources.allSatisfy { $0.rasterized && !$0.isOpaque && ImageSet.flags($0) == 0x14 })
        #expect(sources[0].vectorData != nil && sources[1].vectorData == nil)
    }

    /// A butt-capped line strokes to a rectangle; a miter beyond the limit becomes a bevel; every
    /// piece turns the same way (`svg-masks-strokes`).
    @Test func strokesOutlineTheirSubpaths() throws {
        let line = SVGStroke.outline([([.init(x: 0, y: 0), .init(x: 10, y: 0)], false)], width: 2, cap: "butt", join: "miter", miterLimit: 4)
        #expect(line.count == 1 && Set(line[0].map { "\($0.x),\($0.y)" }) == ["0.0,-1.0", "10.0,-1.0", "10.0,1.0", "0.0,1.0"])
        let sharp: [(points: [SVGImage.Point], closed: Bool)] = [([.init(x: 0, y: 10), .init(x: 5, y: 0), .init(x: 10, y: 10)], false)]
        #expect(SVGStroke.outline(sharp, width: 2, cap: "butt", join: "miter", miterLimit: 4).map(\.count) == [4, 4, 4])
        #expect(SVGStroke.outline(sharp, width: 2, cap: "butt", join: "miter", miterLimit: 1.5).map(\.count) == [4, 4, 3])
        let square = SVGStroke.outline([([.init(x: 0, y: 0), .init(x: 10, y: 0)], false)], width: 2, cap: "square", join: "miter", miterLimit: 4)
        #expect(square[0].map(\.x).min() == -1 && square[0].map(\.x).max() == 11)
        for polygon in SVGStroke.outline(sharp, width: 2, cap: "round", join: "round", miterLimit: 4) {
            #expect(SVGStroke.counterClockwise(polygon).map(\.x) == polygon.map(\.x))
        }
    }

    /// A mask's region is the masked shape's box grown by 10% on each side unless `maskUnits`
    /// says otherwise; its content is collected as shapes.
    @Test func masksKeepTheirRegionAndContent() throws {
        let svg = try SVGImage(data: Data("""
            <svg width="20" height="20" viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg"><defs><mask id="m"><rect width="40" height="40" fill="white"/></mask>\
            <mask id="u" maskUnits="userSpaceOnUse" x="0" y="0" width="5" height="5"><rect width="40" height="40" fill="white"/></mask></defs>\
            <rect x="10" y="10" width="20" height="10" fill="red" mask="url(#m)"/><rect x="0" y="0" width="5" height="5" mask="url(#u)" stroke="blue"/></svg>
            """.utf8), path: "m.svg")
        #expect(svg.shapes.count == 3 && svg.shapes.allSatisfy { $0.masks.count == 1 && $0.masks[0].shapes.count == 1 })
        let region = svg.shapes[0].masks[0].region[0]
        #expect(region.map(\.x).min() == 8 && region.map(\.x).max() == 32 && region.map(\.y).min() == 9 && region.map(\.y).max() == 21)
        #expect(svg.shapes[2].masks[0].region[0].map(\.x).max() == 5)
    }
}
