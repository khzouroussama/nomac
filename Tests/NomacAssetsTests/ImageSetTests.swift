import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Image sets as `assets-experiments images` and `packing` observed them on self-written PNGs.
@Suite struct ImageSetTests {
    /// A PNG of the given rows of samples (Adam7 pass rows one after the other when interlaced),
    /// its image data in stored zlib blocks.
    static func png(width: Int, height: Int, colorType: UInt8, rows: [[UInt8]], palette: [UInt8] = [], transparency: [UInt8] = [],
                    depth: UInt8 = 8, interlaced: Bool = false, chunks: [(String, [UInt8])] = []) -> [UInt8] {
        func be(_ value: UInt32) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
        func crc(_ bytes: [UInt8]) -> UInt32 {
            var c: UInt32 = 0xFFFF_FFFF
            for byte in bytes {
                c ^= UInt32(byte)
                for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            }
            return ~c
        }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            be(UInt32(body.count)) + Array(type.utf8) + body + be(crc(Array(type.utf8) + body))
        }
        var raw: [UInt8] = []
        for row in rows {
            raw.append(0)
            raw += row
        }
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        var zlib: [UInt8] = [0x78, 0x01]
        var start = 0
        repeat {
            let end = min(start + 65_535, raw.count)
            let length = UInt16(end - start), complement = ~UInt16(end - start)
            zlib += [end == raw.count ? 1 : 0, UInt8(length & 0xFF), UInt8(length >> 8), UInt8(complement & 0xFF), UInt8(complement >> 8)]
            zlib += raw[start..<end]
            start = end
        } while start < raw.count
        zlib += be(b << 16 | a)
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", be(UInt32(width)) + be(UInt32(height)) + [depth, colorType, 0, 0, interlaced ? 1 : 0])
        for (type, body) in chunks { out += chunk(type, body) }
        if !palette.isEmpty { out += chunk("PLTE", palette) }
        if !transparency.isEmpty { out += chunk("tRNS", transparency) }
        return out + chunk("IDAT", zlib) + chunk("IEND", [])
    }

    @Test func pixelsArePremultipliedBGRA() throws {
        let rgba = Self.png(width: 2, height: 1, colorType: 6, rows: [[200, 100, 50, 128, 9, 9, 9, 0]])
        #expect(try PNGImage(data: rgba, path: "rgba.png").pixels == [25, 50, 100, 128, 0, 0, 0, 0])
        let rgb = Self.png(width: 1, height: 1, colorType: 2, rows: [[10, 20, 30]])
        #expect(try PNGImage(data: rgb, path: "rgb.png").pixels == [30, 20, 10, 255])
        let palette = Self.png(width: 2, height: 1, colorType: 3, rows: [[0, 1]], palette: [255, 0, 0, 0, 0, 255], transparency: [255, 0])
        #expect(try PNGImage(data: palette, path: "palette.png").pixels == [0, 0, 255, 255, 0, 0, 0, 0])
    }

    /// Gray, gray and alpha, bit depths below 8, `tRNS` keys and Adam7 interlacing decode to the
    /// pixels actool stores (`images`, png-forms).
    @Test func pngFormsDecodeToActoolsPixels() throws {
        func pixels(_ png: [UInt8]) throws -> [UInt8] { try PNGImage(data: png, path: "x.png").pixels }
        #expect(try pixels(Self.png(width: 1, height: 1, colorType: 0, rows: [[90]])) == [90, 90, 90, 255])
        #expect(try pixels(Self.png(width: 1, height: 1, colorType: 4, rows: [[200, 128]])) == [100, 100, 100, 128])
        #expect(try pixels(Self.png(width: 2, height: 1, colorType: 0, rows: [[0x3F]], depth: 4)) == [51, 51, 51, 255, 255, 255, 255, 255])
        #expect(try pixels(Self.png(width: 2, height: 1, colorType: 0, rows: [[90, 91]], transparency: [0, 90])) == [0, 0, 0, 0, 91, 91, 91, 255])
        let palette: [UInt8] = [255, 0, 0, 0, 255, 0, 0, 0, 255, 9, 9, 9]
        #expect(try pixels(Self.png(width: 4, height: 1, colorType: 3, rows: [[0b0001_1011]], palette: palette, transparency: [0], depth: 2))
                == [0, 0, 0, 0, 0, 255, 0, 255, 255, 0, 0, 255, 9, 9, 9, 255])
        #expect(try pixels(Self.png(width: 2, height: 1, colorType: 2, rows: [[1, 2, 3, 4, 5, 6]], transparency: [0, 4, 0, 5, 0, 6]))
                == [3, 2, 1, 255, 0, 0, 0, 0])
        let interlaced = Self.png(width: 2, height: 2, colorType: 0, rows: [[10], [20], [30, 40]], interlaced: true)
        #expect(try pixels(interlaced) == [10, 10, 10, 255, 20, 20, 20, 255, 30, 30, 30, 255, 40, 40, 40, 255])
        let gamma = Self.png(width: 1, height: 1, colorType: 0, rows: [[90]], chunks: [("gAMA", [0, 0, 0xB1, 0x8F])])
        #expect(try pixels(gamma) == [90, 90, 90, 255])
        #expect(try pixels(Self.png(width: 1, height: 1, colorType: 0, rows: [[90]], chunks: [("gAMA", [0, 0, 0xC3, 0x50])])) == [99, 99, 99, 255])
        #expect(throws: NomacError.self) { try pixels(Self.png(width: 1, height: 1, colorType: 0, rows: [[0, 90]], depth: 16)) }
    }

    @Test func paletteColorsSortByTheExclusiveOrOfTheirBytes() {
        // Below 8 colors the sort is stable: equal keys keep their order by value.
        let colors: [UInt32] = [0x0000_0003, 0x0000_0001, 0x0000_0102, 0x0000_0002]
        #expect(PaletteOrder.sorted(colors) == [0x0000_0001, 0x0000_0002, 0x0000_0003, 0x0000_0102])
        // From 8 colors with one key, only the first and last change places.
        let equal = (0..<9).map { UInt32($0) * 0x0101 }
        #expect(PaletteOrder.sorted(equal) == [equal[8]] + equal[1..<8] + [equal[0]])
    }

    static func squares(_ count: Int, side: Int) -> [Atlas.Item] {
        (0..<count).map { Atlas.Item(id: $0, width: side, height: side, identifier: UInt16($0)) }
    }

    @Test func atlasesSplitByAreaThenByWhatFitsWithoutGrowing() {
        let cases: [(Int, Int, [Int])] = [
            (32, 20, [18, 2]), (32, 21, [21]), (32, 40, [21, 18, 1]), (24, 34, [32, 2]), (24, 35, [35]), (24, 36, [35, 1]), (48, 9, [8, 1]),
        ]
        for (side, count, expected) in cases {
            #expect(Atlas.split(Self.squares(count, side: side)).map(\.count) == expected, "\(count) squares of \(side)")
        }
    }

    @Test func atlasSizesAreEven() {
        let items = [
            Atlas.Item(id: 2, width: 14, height: 14, identifier: 2), Atlas.Item(id: 1, width: 12, height: 12, identifier: 1),
            Atlas.Item(id: 3, width: 9, height: 9, identifier: 3),
        ]
        let (positions, width, height) = Atlas.layout(Atlas.packingOrder(items))
        #expect(width == 32 && height == 28)
        #expect(positions[2]! == (2, 2) && positions[1]! == (18, 2) && positions[3]! == (2, 18))
    }

    @Test func modeTwoChunksHoldUpTo2MiBOfRows() {
        let observed: [(width: Int, rows: Int)] = [(2688, 111), (1500, 199), (1024, 291), (512, 582)]
        for (width, rows) in observed {
            #expect(Deepmap2Planes.chunkRows(width: width, height: 4096) == rows, "\(width)")
        }
        #expect(Deepmap2Planes.chunkRows(width: 100, height: 50) == 50)
        #expect(Deepmap2Planes.chunkRows(width: 1024, height: 800, format: .gray) == 679)
        #expect(Deepmap2Planes.chunkRows(width: 2000, height: 524, format: .gray) == 348)
    }

    @Test func rowBytesCountOneByteForOpaqueGrayImagesAndFourOtherwise() {
        let observed: [(width: Int, opaque: Bool, gray: Bool, bytes: UInt32)] = [
            (1, true, true, 32), (32, true, true, 32), (33, true, true, 64), (65, true, true, 96), (150, true, true, 160),
            (150, false, true, 608), (28, false, true, 128), (190, false, true, 768), (10, true, false, 64), (61, false, false, 256),
        ]
        for (width, opaque, gray, bytes) in observed {
            #expect(ImageSet.rowBytes(width: width, opaque: opaque, gray: gray) == bytes, "\(width) \(opaque) \(gray)")
        }
    }

    /// The costs equal macOS's `logf` for 1 to 1,025, on Linux too: the sum of their bit patterns
    /// is the one macOS's `logf` gives.
    @Test func filterCostsAreFloatNaturalLogarithms() {
        #expect(Deepmap2Planes.costs[1] == Float(0.6931472))
        #expect(Deepmap2Planes.costs.reduce(UInt64(0)) { $0 + UInt64($1.bitPattern) } == 1_112_155_959_839)
    }

    @Test func aTinyImageIsStoredRaw() throws {
        let payload = try Deepmap2.payload([30, 20, 10, 255], format: .bgra, width: 1, height: 1, opaque: true)
        var expected = ByteWriter()
        expected.append(Array("MLEC".utf8))
        for value: UInt32 in [2, 11, 32, 1, 4, 16, 0] { expected.appendLE(value) }
        expected.append(Array("dmp2".utf8) + [1, 1, 10, 4, 1, 0, 1, 0, 30, 20, 10, 255])
        #expect(payload == expected.bytes)
    }

    /// A gray image is its gray and alpha bytes: 1 × 3 pixels stay raw (`images`, gray).
    @Test func aTinyGrayImageIsStoredRawAsGrayAndAlpha() throws {
        let payload = try Deepmap2.payload([0x44, 0xFF, 0x20, 0xFF, 0x82, 0xFF], format: .gray, width: 1, height: 3, opaque: true)
        var expected = ByteWriter()
        expected.append(Array("MLEC".utf8))
        for value: UInt32 in [2, 11, 34, 1, 2, 18, 0] { expected.appendLE(value) }
        expected.append(Array("dmp2".utf8) + [1, 1, 10, 2, 1, 0, 3, 0, 0x44, 0xFF, 0x20, 0xFF, 0x82, 0xFF])
        #expect(payload == expected.bytes)
    }

    /// Mode 2 of a gray image: the alpha plane, the filters and the gray residuals' two planes.
    @Test func grayModeTwoChunksHoldOneResidualPerPixel() {
        let pixels: [UInt8] = [10, 255, 12, 255, 9, 255, 10, 255, 11, 255, 30, 255]
        let values = (0..<6).map { (y: Int(pixels[$0 * 2]), a: 0, c: 0) }
        let chunk = Deepmap2Planes.chunk(values, alpha: [UInt8](repeating: 255, count: 6), channels: 1, width: 3, top: 0, rows: 2)
        let codes: [UInt16] = [20, 4, 7, 0, 0, 40]
        let body = [UInt8](repeating: 255, count: 6) + [2, 4] + codes.map { UInt8($0 >> 8) } + codes.map { UInt8($0 & 0xFF) }
        #expect(chunk == body + [UInt8](repeating: 0, count: 32 - body.count))
    }

    static func source(_ name: String, width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) -> ImageSet.Source {
        let pixels = (0..<height).flatMap { y in (0..<width).flatMap { x in pixel(x, y) } }
        return ImageSet.Source(name: name, filename: name + ".png", path: "/" + name + ".png", image: PNGImage(width: width, height: height, pixels: pixels))
    }

    static func layout(_ csi: [UInt8]) -> UInt16 { UInt16(csi[36]) | UInt16(csi[37]) << 8 }

    /// Gray images pack in their own classes, and their atlases are gray (`images`, classes-gray).
    @Test func grayImagesAreStoredAsGA8AndPackedApart() throws {
        let sources = [
            Self.source("o1", width: 30, height: 30) { _, _ in [30, 20, 10, 255] },
            Self.source("o2", width: 20, height: 20) { _, _ in [60, 50, 40, 255] },
            Self.source("g1", width: 30, height: 30) { x, _ in [UInt8(x * 8), UInt8(x * 8), UInt8(x * 8), 255] },
            Self.source("g2", width: 20, height: 20) { _, y in [UInt8(y * 9), UInt8(y * 9), UInt8(y * 9), 255] },
            Self.source("t1", width: 10, height: 10) { _, _ in [64, 64, 64, 128] },
            Self.source("t2", width: 12, height: 12) { x, _ in [0, 0, 0, UInt8(x * 20)] },
        ]
        let identifiers = RenditionIdentifier.assign(sources.map(\.name))
        let renditions = try ImageSet.renditions(sources, identifiers: identifiers)
        let atlases = renditions.filter { $0.name.hasPrefix("ZZZZ") }
        #expect(atlases.map(\.name) == ["ZZZZPackedAsset-1.0.1-gamut0", "ZZZZPackedAsset-1.1.0-gamut0", "ZZZZPackedAsset-1.1.1-gamut0"])
        #expect(atlases.map { $0.attributes[.dimension1] } == [nil, 1, 2])
        for atlas in atlases {
            let gray = atlas.name.hasSuffix(".1-gamut0")
            #expect(Array(atlas.csi[24..<28]) == Array((gray ? " 8AG" : "BGRA").utf8))
            #expect(atlas.csi[28] == (gray ? 2 : 1))
        }
        #expect(ImageSet.stored([0, 0, 0, 0, 9, 9, 9, 255], gray: true, opaque: true) == [0, 255, 9, 255])
        #expect(ImageSet.stored([0, 0, 0, 0, 9, 9, 9, 255], gray: true, opaque: false) == [0, 0, 9, 255])
    }

    @Test func smallImagesArePackedByClassAndAloneOnesAreNot() throws {
        let sources = [
            Self.source("o1", width: 30, height: 30) { _, _ in [30, 20, 10, 255] },
            Self.source("o2", width: 20, height: 20) { _, _ in [60, 50, 40, 255] },
            Self.source("o3", width: 10, height: 10) { _, _ in [90, 80, 70, 255] },
            Self.source("b1", width: 12, height: 12) { x, y in (x + y) % 2 == 0 ? [0, 0, 0, 0] : [3, 2, 1, 255] },
            Self.source("big", width: 200, height: 100) { x, y in [UInt8(x % 256), UInt8(y), 7, 255] },
        ]
        let identifiers = RenditionIdentifier.assign(sources.map(\.name))
        let renditions = try ImageSet.renditions(sources, identifiers: identifiers)
        let layouts = Dictionary(uniqueKeysWithValues: renditions.map { ($0.name, Self.layout($0.csi)) })
        #expect(layouts == ["b1": 12, "big": 12, "ZZZZPackedAsset-1.1.0-gamut0": 1004, "o1": 1003, "o2": 1003, "o3": 1003])
        let atlas = renditions.first { $0.name.hasPrefix("ZZZZ") }!
        #expect(!atlas.hasFacet && atlas.attributes == [.scale: 1])
        let link = renditions.first { $0.name == "o3" }!.csi
        let key: [UInt8] = [12, 0, 16, 0, 0, 0, 1, 0, 9, 0, 2, 0, 181, 0, 12, 0, 1, 0, 0, 0, 0, 0]
        #expect(link.indices.contains { Array(link[$0..<min($0 + key.count, link.count)]) == key })
    }

    /// A visionOS icon stack of two layers, each one vision 2x PNG of `side` pixels.
    static func writeIconStack(_ stack: String, side: Int) throws {
        let info: [String: Any] = ["info": ["author": "xcode", "version": 1]]
        var contents = info
        contents["layers"] = [["filename": "Front.solidimagestacklayer"], ["filename": "Back.solidimagestacklayer"]]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: contents), to: stack + "/Contents.json")
        for layer in ["Front", "Back"] {
            let folder = "\(stack)/\(layer).solidimagestacklayer"
            try FileSystem.write(try JSONSerialization.data(withJSONObject: info), to: folder + "/Contents.json")
            var image = info
            image["images"] = [["filename": "l.png", "idiom": "vision", "scale": "2x"]]
            try FileSystem.write(try JSONSerialization.data(withJSONObject: image), to: folder + "/Content.imageset/Contents.json")
            let row = [UInt8](repeating: 200, count: side * 3)
            try FileSystem.write(Data(png(width: side, height: side, colorType: 2, rows: Array(repeating: row, count: side))), to: folder + "/Content.imageset/l.png")
        }
    }

    /// An iOS build compiles nothing from a visionOS icon stack; actool reports an error when its
    /// last layer with content does not fill 512 × 512 points, where nomac stops.
    /// `template-rendering-intent` sets the CSI flags (`images` intents).
    @Test func renderingIntentsSetTheFlags() {
        var source = ImageSet.Source(name: "a", filename: "a.png", path: "/a.png", image: PNGImage(width: 1, height: 1, pixels: [0, 0, 0, 255]))
        let flags = [nil, "template", "original"].map { intent -> UInt32 in
            source.renderingIntent = intent
            return ImageSet.flags(source)
        }
        #expect(flags == [0x10, 0x8, 0])
    }

    /// A profile ColorSync would not use leaves the image untagged, as if the chunk were not there
    /// (`bad-profiles` not-a-profile).
    @Test func unreadableColorProfilesLeaveTheImageUntagged() throws {
        let profile = Array("ICC\0\0".utf8) + [0x78, 0x01, 0x01, 0x04, 0x00, 0xFB, 0xFF] + Array("fake".utf8) + [0x03, 0xFA, 0x01, 0x98]
        let bytes = Self.png(width: 1, height: 1, colorType: 6, rows: [[1, 2, 3, 255]], chunks: [("iCCP", profile)])
        let image = try PNGImage(data: bytes, path: "/p.png")
        #expect(image.pixels == [3, 2, 1, 255] && !image.convertedColors)
    }

    @Test func visionOSIconStacksAddNothingOnIOS() throws {
        let temporary = try TemporaryDirectory()
        try ImageSetTests.writeIconStack(temporary.path + "/Good.solidimagestack", side: 1024)
        #expect(try SolidImageStack.errors(temporary.path + "/Good.solidimagestack").isEmpty)
        try ImageSetTests.writeIconStack(temporary.path + "/Small.solidimagestack", side: 64)
        #expect(try SolidImageStack.errors(temporary.path + "/Small.solidimagestack") == [
            "The last visionOS App Icon Layer with content, “Back”, must exactly fill the image stack. Its current frame is {{0, 0}, {32, 32}} while the visionOS App Icon's size is {512, 512}.",
        ])
    }

    /// Entries of each scale for universal and targeted devices are read, those of devices the
    /// build does not target are left out, and other idioms stop (`images`, idioms).
    @Test func entriesOfScalesAndTargetedDevicesAreRead() throws {
        let temporary = try TemporaryDirectory()
        let folder = temporary.path + "/a.imageset"
        let red = Self.png(width: 1, height: 1, colorType: 2, rows: [[200, 0, 0]])
        for name in ["u2", "p3", "i1"] { try FileSystem.write(Data(red), to: folder + "/\(name).png") }
        let entries: [[String: Any]] = [
            ["filename": "u2.png", "idiom": "universal", "scale": "2x"], ["filename": "p3.png", "idiom": "iphone", "scale": "3x"],
            ["filename": "i1.png", "idiom": "ipad", "scale": "1x"], ["idiom": "universal", "scale": "1x"],
        ]
        let asset = AssetCatalog.Asset(name: "a", type: "imageset", path: folder, contents: ["images": entries])
        let both = try ImageSet.sources(asset, idioms: Idiom.iOS(targetDevices: ["iphone", "ipad"]))
        #expect(both.map { "\($0.filename) \($0.scale) \($0.idiom)" } == ["u2.png 2 0", "p3.png 3 1", "i1.png 1 2"])
        let phone = try ImageSet.sources(asset, idioms: Idiom.iOS(targetDevices: ["iphone"]))
        #expect(phone.map(\.filename) == ["u2.png", "p3.png"])
        let vision = AssetCatalog.Asset(name: "v", type: "imageset", path: folder, contents: [
            "images": [["filename": "u2.png", "idiom": "vision", "scale": "2x"]],
        ])
        #expect(throws: NomacError.self) { try ImageSet.sources(vision, idioms: Idiom.iOS(targetDevices: ["iphone"])) }
    }

    /// Images pack by scale and idiom, below 18,050 pixels times the scale, and atlases are
    /// numbered within their scale and idiom (`images`, scales).
    @Test func imagesPackByScaleAndIdiom() throws {
        func source(_ name: String, _ side: Int, scale: Int, idiom: UInt16 = Idiom.universal) -> ImageSet.Source {
            let pixels = [UInt8](repeating: 0, count: side * side * 4).enumerated().map { $0.offset % 4 == 3 ? 255 : UInt8($0.offset % 4 * 60) }
            return ImageSet.Source(name: name, filename: "\(name)\(scale).png", path: "/\(name)\(scale)\(idiom).png",
                                   image: PNGImage(width: side, height: side, pixels: pixels), scale: scale, idiom: idiom)
        }
        let sources = [
            source("a", 10, scale: 1), source("b", 12, scale: 1), source("a", 20, scale: 2), source("b", 189, scale: 2),
            source("c", 190, scale: 2), source("d", 30, scale: 2), source("a", 20, scale: 2, idiom: Idiom.phone), source("b", 24, scale: 2, idiom: Idiom.phone),
        ]
        let renditions = try ImageSet.renditions(sources, identifiers: RenditionIdentifier.assign(["a", "b", "c", "d"]))
        let atlases = renditions.filter { $0.name.hasPrefix("ZZZZ") }.map { atlas in
            "\(atlas.name) " + [RenditionAttribute.scale, .idiom, .dimension1].map { String(atlas.attributes[$0] ?? 0) }.joined(separator: " ")
        }
        #expect(atlases.sorted() == [
            "ZZZZPackedAsset-1.1.0-gamut0 1 0 0", "ZZZZPackedAsset-2.1.0-gamut0 2 0 0", "ZZZZPackedAsset-2.1.0-gamut0 2 0 1",
            "ZZZZPackedAsset-2.1.0-gamut0 2 1 0",
        ])
        let standalone = renditions.filter { Self.layout($0.csi) == 12 }
        #expect(standalone.map(\.name) == ["c"] && standalone[0].csi[20] == 200)
    }

    /// Half floats as actool's `RGBW` renditions hold them (`profiles` wide cases: 15455 is 1.0928,
    /// 45888 is −0.2266), rounded to nearest even.
    @Test func halfFloatsRoundToNearestEven() {
        #expect(PNGImage.half(1) == 0x3C00 && PNGImage.half(-2) == 0xC000 && PNGImage.half(0) == 0)
        #expect(PNGImage.half(1.0928) == 15455 && PNGImage.half(-0.2266) == 45888)
        #expect(PNGImage.half(1 + 1.0 / 2048) == 0x3C00 && PNGImage.half(1 + 3.0 / 2048) == 0x3C02)
        #expect(PNGImage.half(70000) == 0x7C00 && PNGImage.half(1e-8) == 0)
    }

    /// actool dithers 16-bit samples, so nomac reads 16-bit PNGs only with a profile to convert
    /// from (`profiles` wide case); untagged ones stop it.
    @Test func untaggedSixteenBitImagesStop() throws {
        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
            let body = Array(type.utf8) + data
            return IconPNG.bigEndian(UInt32(data.count)) + body + IconPNG.bigEndian(CopyPNGTests.crc32(body))
        }
        let rows: [UInt8] = [0] + [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xFF, 0xFF]
        let png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", IconPNG.bigEndian(1) + IconPNG.bigEndian(1) + [16, 6, 0, 0, 0])
            + chunk("IDAT", try IconPNG.deflate([rows], windowBits: 15)[0]) + chunk("IEND", [])
        #expect(throws: NomacError.self) { try PNGImage(data: png, path: "/deep.png") }
    }
}

/// Image set entries with appearances, as `assets-experiments image-appearances` showed them.
@Suite struct ImageAppearanceTests {
    /// Luminosity dark and light and high contrast; two appearances at once are not known.
    @Test func entriesNameOneAppearance() throws {
        let asset = AssetCatalog.Asset(name: "A", type: "imageset", path: "A.imageset", contents: [:])
        func appearance(_ pairs: [[String: String]]) throws -> RenditionAppearance {
            try ImageSet.entryAppearance(["filename": "a.png", "appearances": pairs], asset: asset)
        }
        #expect(try appearance([]) == .any)
        #expect(try appearance([["appearance": "luminosity", "value": "dark"]]) == .dark)
        #expect(try appearance([["appearance": "luminosity", "value": "light"]]) == .light)
        #expect(try appearance([["appearance": "contrast", "value": "high"]]) == .highContrastAny)
        #expect(try appearance([["appearance": "luminosity", "value": "dark"], ["appearance": "contrast", "value": "high"]]) == .highContrastDark)
        #expect(throws: NomacError.self) { try appearance([["appearance": "luminosity", "value": "dark"], ["appearance": "luminosity", "value": "light"]]) }
    }

    /// watchOS keeps only the colors and images for any appearance (`image-appearances` watch
    /// cases, home-assistant's watch catalogs).
    @Test func watchKeepsOnlyTheAnyAppearance() throws {
        let dark = [["appearance": "luminosity", "value": "dark"]]
        let red = ColorCatalogTests.rgb("1.000", "0.000", "0.000")
        let colors = AssetCatalog.Asset(name: "tint", type: "colorset", path: "tint.colorset",
                                        contents: ["colors": [ColorCatalogTests.entry(red), ColorCatalogTests.entry(red, ["appearances": dark])]])
        #expect(try ColorSet.renditions(colors, idioms: ["universal": Idiom.universal], watch: false).count == 2)
        #expect(try ColorSet.renditions(colors, idioms: ["universal": Idiom.universal], watch: true).count == 1)
        let images = AssetCatalog.Asset(name: "pic", type: "imageset", path: "pic.imageset",
                                        contents: ["images": [["filename": "missing.png", "idiom": "universal", "scale": "2x", "appearances": dark]]])
        let watch = try Actool.Platform(Actool.Options(arguments: ["A.xcassets", "--compile", "out", "--platform", "watchos", "--target-device", "watch"]))
        #expect(try ImageSet.sources(images, idioms: ["universal": Idiom.universal], platform: watch).isEmpty)
    }

    /// Of deepmap2 candidates of one size, actool takes the planes (mode 2) before LZ (mode 3):
    /// the image-contrast case's 16 × 16 image, whose two candidates take 144 bytes.
    @Test func planesWinTiesWithLZ() throws {
        let pixels = (0..<16 * 16).flatMap { index -> [UInt8] in
            let x = index % 16, y = index / 16
            return (x + y) % 5 == 0 ? [0, 0, 0, 0] : [0, UInt8(x), 240, 255]
        }
        let planes = Deepmap2Planes.encode(pixels, format: .bgra, width: 16, height: 16)
        #expect(planes.count == Deepmap2.lzCompressed(pixels, format: .bgra, width: 16, height: 16).count)
        #expect(try Deepmap2.best(pixels, format: .bgra, width: 16, height: 16) == planes)
    }
}
