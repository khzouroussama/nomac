import CZlib
import Foundation
import NomacCore
import Testing
@testable import NomacAssets

/// The observed values of `assets_experiments.py` `appearance-pairs`, `image-traits`,
/// `incomplete-icons`, `icon-entries`, `bad-profiles` and `icon-chunks`.
@Suite struct EntryRulesTests {
    static func entry(_ pairs: [(String, String)]) -> [[String: Any]] {
        pairs.map { ["appearance": $0.0, "value": $0.1] }
    }

    @Test func luminosityWithHighContrast() {
        let dark = RenditionAppearance(entry: Self.entry([("luminosity", "dark"), ("contrast", "high")]))
        let light = RenditionAppearance(entry: Self.entry([("contrast", "high"), ("luminosity", "light")]))
        #expect(dark?.rawValue == 3 && dark?.name == "UIAppearanceHighContrastDark")
        #expect(light?.rawValue == 5 && light?.name == "UIAppearanceHighContrastLight")
    }

    static func source(_ width: Int, _ height: Int) -> ImageSet.Source {
        var pixels: [UInt8] = []
        for y in 0..<height { for x in 0..<width { pixels += [UInt8(x % 256), UInt8(y % 256), 0, 255] } }
        return ImageSet.Source(name: "I", filename: "i.png", path: "/i.png", image: PNGImage(width: width, height: height, pixels: pixels))
    }

    static func words(_ bytes: [UInt8]) -> [Int] {
        stride(from: 0, to: bytes.count, by: 4).map { Int(Int32(bitPattern: UInt32(bytes[$0]) | UInt32(bytes[$0 + 1]) << 8 | UInt32(bytes[$0 + 2]) << 16 | UInt32(bytes[$0 + 3]) << 24)) }
    }

    @Test func alignmentInsetsAreInTheMetrics() throws {
        let traits = try EntryTraits(["alignment-insets": ["top": 1, "bottom": 2, "left": -6, "right": 6]], allEntries: [], path: "/s")
        var png = Self.source(16, 16)
        try traits.apply(to: &png, factor: 1, path: "/s")
        #expect(Self.words(ImageSet.geometry(png)[1].value) == [1, -6, 1, 6, 2, 16, 13])
        var raster = Self.source(32, 32)
        try traits.apply(to: &raster, factor: 2, path: "/s")
        #expect(Self.words(ImageSet.geometry(raster)[1].value) == [1, -12, 2, 12, 4, 32, 26])
    }

    @Test func resizingCropsToCapsAndCenter() throws {
        let nine = ["resizing": ["mode": "9-part", "center": ["mode": "stretch", "width": 1, "height": 1], "cap-insets": ["top": 20, "bottom": 30, "left": 18, "right": 24]]]
        var source = Self.source(640, 320)
        try EntryTraits(nine, allEntries: [], path: "/s").apply(to: &source, factor: 1, path: "/s")
        #expect((source.image.width, source.image.height) == (43, 51))
        #expect(source.resizing?.layout == .ninePartStretch)
        #expect(Self.words(ImageSet.geometry(source)[0].value) == [9, 0, 31, 18, 20, 18, 31, 1, 20, 19, 31, 24, 20, 0, 30, 18, 1, 18, 30, 1, 1, 19, 30, 24, 1, 0, 0, 18, 30, 18, 0, 1, 30, 19, 0, 24, 30])
        #expect(Array(source.image.pixels[(43 - 24) * 4..<(43 - 24) * 4 + 2]) == [UInt8((640 - 24) % 256), 0])
        let horizontal = ["resizing": ["mode": "3-part-horizontal", "center": ["mode": "tile", "width": 1], "cap-insets": ["left": 18, "right": 24]]]
        var wide = Self.source(640, 320)
        try EntryTraits(horizontal, allEntries: [], path: "/s").apply(to: &wide, factor: 1, path: "/s")
        #expect(wide.resizing?.layout == .threePartHorizontalTile)
        #expect(Self.words(ImageSet.geometry(wide)[0].value) == [3, 0, 0, 18, 320, 18, 0, 1, 320, 19, 0, 24, 320])
    }

    @Test func oneLanguageDirectionFlagsTheSet() throws {
        let left: [String: Any] = ["filename": "a.png", "language-direction": "left-to-right"]
        let right: [String: Any] = ["filename": "b.png", "language-direction": "right-to-left"]
        let plain: [String: Any] = ["filename": "c.png"]
        let alone = try EntryTraits(left, allEntries: [left], path: "/s")
        #expect(alone.direction == 5 && alone.flippable)
        let pair = try EntryTraits(right, allEntries: [left, right], path: "/s")
        #expect(pair.direction == 4 && !pair.flippable)
        #expect(throws: NomacError.self) { try EntryTraits(left, allEntries: [left, plain], path: "/s") }
        let items = [Atlas.Item(id: 0, width: 16, height: 16, identifier: 23553, direction: 5), Atlas.Item(id: 1, width: 16, height: 16, identifier: 26709, direction: 4),
                     Atlas.Item(id: 2, width: 16, height: 16, identifier: 42285), Atlas.Item(id: 3, width: 16, height: 16, identifier: 23369)]
        #expect(Atlas.packingOrder(items).map(\.id) == [3, 2, 1, 0])
    }

    @Test func requiredIconsOfTheTargetedDevices() {
        func icon(_ idiom: String, _ size: String, _ scale: Int) -> AppIconSet.Icon { AppIconTests.icon(idiom, size, scale) }
        let both = ["iphone", "ipad"]
        #expect(AppIconSet.requiredIconWarnings([], targetDevices: both) == [
            "A 60x60@2x app icon is required for iPhone apps targeting iOS 7.0 and later",
            "A 76x76@2x app icon is required for iPad apps targeting iOS 7.0 and later",
            "A 83.5x83.5@2x app icon is required for iPad apps targeting iOS 9.0 and later",
            "A 1024x1024 app store icon is required for iOS apps",
        ])
        #expect(AppIconSet.requiredIconWarnings([icon("iphone", "60x60", 2), icon("ios-marketing", "1024x1024", 1)], targetDevices: ["iphone"]).isEmpty)
        #expect(AppIconSet.requiredIconWarnings([icon("iphone", "60x60", 2)], targetDevices: ["iphone"]) == ["A 1024x1024 app store icon is required for iOS apps"])
    }

    @Test func iconSetWarningsComeInThreePasses() {
        var problems = AppIconSet.Problems()
        problems.unassigned = [.init(idiom: "iphone", size: "40x40", scale: "1x", filename: "b.png"), .init(idiom: "tv", size: "400x240", scale: "1x", filename: "a.png")]
        problems.entries = [("./AppIcon.appiconset/[][iphone][29x29][][][2x][][][][]", "wrong")]
        let lines = problems.warnings(folder: "AppIcon.appiconset", name: "AppIcon", required: ["needed"]).map(\.message)
        #expect(lines == ["The app icon set \"AppIcon\" has 2 unassigned children.", "wrong", "needed",
                          "The app icon set \"AppIcon\" has an unassigned child.", "wrong", "The app icon set \"AppIcon\" has 2 unassigned children.", "wrong"])
    }

    /// zlib's stream of `data`.
    static func zlibbed(_ data: [UInt8]) throws -> [UInt8] {
        try IconPNG.deflate([data], windowBits: 15)[0]
    }

    @Test func damagedProfilesLeaveImagesUntagged() throws {
        let stream = try Self.zlibbed(Array(repeating: 7, count: 300))
        let name = Array("P3".utf8)
        #expect(PNGImage.readableProfile(name + [0, 0] + stream)?.count == 300)
        var badSum = stream
        badSum[badSum.count - 1] ^= 1
        #expect(PNGImage.readableProfile(name + [0, 0] + badSum)?.count == 300)
        #expect(PNGImage.readableProfile(name + [0, 0] + stream + [0, 0, 0])?.count == 300)
        #expect(PNGImage.readableProfile(name) == nil)
        #expect(PNGImage.readableProfile(name + [0]) == nil)
        #expect(PNGImage.readableProfile(name + [0, 0]) == nil)
        #expect(PNGImage.readableProfile([0, 0] + stream) == nil)
        #expect(PNGImage.readableProfile(Array(repeating: 0x4E, count: 90) + [0, 0] + stream) == nil)
        #expect(PNGImage.readableProfile(name + [0, 1] + stream) == nil)
        #expect(PNGImage.readableProfile(name + [0, 0] + stream.prefix(stream.count / 2)) == nil)
        #expect(PNGImage.readableProfile(name + [0, 0] + Array(0..<200)) == nil)
    }

    @Test func iconPNGsKeepProfilesByTheirOwnRule() throws {
        var profile: [UInt8] = [0, 0, 1, 0x2C] + Array(repeating: 7, count: 296)
        func chunk(_ name: [UInt8], _ data: [UInt8]) throws -> PNGImage.Chunk { PNGImage.Chunk(type: "iCCP", data: name + [0, 0] + (try Self.zlibbed(data))) }
        let name = Array("P3".utf8)
        #expect(try IconPNG.iconProfile(chunk(name, profile), plain: false) != nil)
        #expect(try IconPNG.iconProfile(chunk([], profile), plain: false) == nil)
        #expect(try IconPNG.iconProfile(chunk(name, Array(profile.prefix(200))), plain: false) == nil)
        let long = try #require(try IconPNG.iconProfile(chunk(Array(repeating: 0x4E, count: 90), profile), plain: false))
        #expect(long.data.firstIndex(of: 0) == 80)
        profile[0...3] = [0, 0, 0, 9]
        let cut = try #require(try IconPNG.iconProfile(chunk(name, profile), plain: true))
        #expect(PNGImage.inflated(Array(cut.data[(cut.data.firstIndex(of: 0)! + 2)...]), windowBits: 15)?.count == 9)
    }

    @Test func iconChunksInLibpngsOrder() throws {
        func image(_ before: [String], after: [String] = []) -> PNGImage {
            var image = PNGImage(width: 1, height: 1, pixels: [0, 0, 0, 255])
            image.ancillaryChunks = before.map { PNGImage.Chunk(type: $0, data: []) } + after.map { PNGImage.Chunk(type: $0, data: [], afterData: true) }
            return image
        }
        let all = try IconPNG.ancillaryChunks(image(["tEXt", "sPLT", "tIME", "pHYs", "sCAL", "pCAL", "oFFs", "vpAg", "caNv", "eXIf", "iTXt", "cHRM", "sBIT", "gAMA", "cICP", "prVW"]), path: "/i.png", plain: false)
        #expect(all.early.map(\.type) == ["gAMA", "sBIT", "cHRM", "vpAg", "caNv", "eXIf", "iTXt"])
        #expect(all.late.map(\.type) == ["oFFs", "pCAL", "sCAL", "pHYs", "tIME", "sPLT", "tEXt"])
        let after = try IconPNG.ancillaryChunks(image([], after: ["tEXt", "iTXt", "tIME", "pHYs", "eXIf"]), path: "/i.png", plain: false)
        #expect(after.tail.map(\.type) == ["tIME", "tEXt"])
        #expect((after.early + after.late).isEmpty)
    }

    @Test func halvesFromFourThousandNinetySixPixels() {
        func image(_ width: Int, _ height: Int, depth: Int = 8, interlaced: Bool = false) -> PNGImage {
            var image = PNGImage(width: width, height: height, pixels: [])
            image.stored.depth = depth
            image.stored.interlaced = interlaced
            return image
        }
        #expect(IconPNG.isHalved(image(64, 64)) && IconPNG.isHalved(image(2048, 2)) && IconPNG.isHalved(image(69, 60)))
        #expect(!IconPNG.isHalved(image(65, 63)) && !IconPNG.isHalved(image(4097, 1)) && !IconPNG.isHalved(image(68, 60)))
        #expect(!IconPNG.isHalved(image(300, 300, depth: 4)) && !IconPNG.isHalved(image(300, 300, depth: 16)) && !IconPNG.isHalved(image(300, 300, interlaced: true)))
    }
}
