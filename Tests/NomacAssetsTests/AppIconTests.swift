import Foundation
import NomacCore
import NomacPlist
import NomacTestSupport
import Testing
@testable import NomacAssets

/// App icon sets as `assets-experiments app-icons` observed them: one that lists sizes without
/// image files compiles to nothing, `--app-icon` naming no set is an error, and a multi-size set
/// gives actool's `Assets.car`, CgBI PNGs and Info.plist keys.
@Suite struct AppIconTests {
    static func writeEmptyAppIcon(_ catalog: String) throws {
        let contents: [String: Any] = [
            "images": [["idiom": "iphone", "scale": "2x", "size": "60x60"], ["idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"]],
            "info": ["author": "xcode", "version": 1],
        ]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: contents), to: catalog + "/AppIcon.appiconset/Contents.json")
    }

    @Test func appIconSetWithoutImagesCompilesToNothing() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.writeEmptyAppIcon(catalog)
        let result = try ColorCatalogTests.compile(catalog, in: temporary.path + "/out", extra: ["--app-icon", "AppIcon"])
        #expect(!result.failed)
        #expect(result.writtenFiles == [temporary.path + "/out/partial.plist"])
    }

    @Test func missingAppIconIsAnErrorButOutputsAreWritten() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, ["Red": [ColorCatalogTests.entry(ColorCatalogTests.rgb("1.000", "0.000", "0.000"))]])
        try Self.writeEmptyAppIcon(catalog)
        let result = try ColorCatalogTests.compile(catalog, in: temporary.path + "/out", extra: ["--app-icon", "Missing"])
        #expect(result.failed)
        let error = "/* com.apple.actool.errors */\n\(catalog): error: None of the input catalogs contained a matching stickers icon set, app icon set, or icon stack named  \"Missing\".\n"
        #expect(result.standardOutput.hasPrefix(error))
        #expect(result.writtenFiles == [temporary.path + "/out/Assets.car", temporary.path + "/out/partial.plist"])
    }

    static let iPhoneEntries = [("20x20", 2), ("20x20", 3), ("29x29", 2), ("29x29", 3), ("40x40", 2), ("40x40", 3), ("60x60", 2), ("60x60", 3)]

    /// Every iPhone size and the App Store icon, image n's pixel (x, y) being (x + n, 7x + y,
    /// 5y + n, 255) modulo 256, the 60 pt 2x one with an `sRGB` chunk; and a launch image set
    /// without files.
    static func writeIconSet(_ catalog: String) throws {
        var images: [[String: Any]] = []
        let entries = iPhoneEntries.map { ("iphone", $0.0, $0.1) } + [("ios-marketing", "1024x1024", 1)]
        for (n, (idiom, size, scale)) in entries.enumerated() {
            let side = Int(size.prefix { $0 != "x" })! * scale
            let rows: [[UInt8]] = (0..<side).map { y in
                (0..<side).flatMap { x -> [UInt8] in [UInt8((x + n) % 256), UInt8((x * 7 + y) % 256), UInt8((y * 5 + n) % 256), 255] }
            }
            let chunks: [(String, [UInt8])] = size == "60x60" && scale == 2 ? [("sRGB", [0])] : []
            try FileSystem.write(Data(ImageSetTests.png(width: side, height: side, colorType: 6, rows: rows, chunks: chunks)),
                                 to: catalog + "/AppIcon.appiconset/i\(n).png")
            images.append(["filename": "i\(n).png", "idiom": idiom, "scale": "\(scale)x", "size": size])
        }
        let info = ["author": "xcode", "version": 1] as [String: Any]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: ["images": images, "info": info]), to: catalog + "/AppIcon.appiconset/Contents.json")
        let launch: [String: Any] = ["orientation": "portrait", "idiom": "iphone", "extent": "full-screen", "minimum-system-version": "8.0", "subtype": "736h", "scale": "3x"]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: ["images": [launch], "info": info]), to: catalog + "/LaunchImage.launchimage/Contents.json")
    }

    @Test func multiSizeSetGivesActoolsOutputs() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.writeIconSet(catalog)
        let out = temporary.path + "/out"
        let result = try Actool.run(try Actool.Options(arguments: [
            catalog, "--compile", out, "--output-format", "human-readable-text", "--notices", "--warnings", "--output-partial-info-plist", out + "/partial.plist",
            "--compress-pngs", "--target-device", "iphone", "--minimum-deployment-target", "15.0", "--platform", "iphoneos",
            "--app-icon", "AppIcon", "--standalone-icon-behavior", "all",
        ]))
        let pngs = Self.iPhoneEntries.map { "AppIcon\($0.0)@\($0.1)x.png" }
        #expect(result.writtenFiles == pngs.map { out + "/" + $0 } + [out + "/Assets.car", out + "/partial.plist"])
        func read(_ name: String) throws -> [UInt8] { Array(try #require(FileManager.default.contents(atPath: out + "/" + name))) }
        #expect(ColorCatalogTests.hex(SHA256.digest(try read("Assets.car"))) == "b8dbb6ba52973268d6800c527ba006b48d5a30b7bd2c007db958a20d69cad378")
        #expect(ColorCatalogTests.hex(SHA256.digest(try pngs.flatMap(read))) == "8ad95bddbe1198225d904ab3e03f27fd2911b114b0e82124b21e0a46aff8f538")
        #expect(ColorCatalogTests.hex(SHA256.digest(try read("partial.plist"))) == "5573b31a4fd9aecdbcbc90645e38f2368ffc6cd53c9fbbaa179ca2982303079a")
    }

    /// A single-size icon targeting iPhone: both resized PNGs, RGBA with `gAMA`, `sRGB`, `cHRM`
    /// and the pixel size in `eXIf`, the iPad key without an icon name (`single-size-icons`).
    @Test func singleSizeSetGivesResizedPNGs() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        let rows: [[UInt8]] = (0..<1024).map { y in (0..<1024).flatMap { x -> [UInt8] in [UInt8(x % 256), UInt8(y % 256), 90] } }
        try FileSystem.write(Data(ImageSetTests.png(width: 1024, height: 1024, colorType: 2, rows: rows, chunks: [("pHYs", [0, 0, 22, 37, 0, 0, 22, 37, 1])])),
                             to: catalog + "/AppIcon.appiconset/icon.png")
        let entry: [String: Any] = ["filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: ["images": [entry], "info": ["author": "xcode", "version": 1]]),
                             to: catalog + "/AppIcon.appiconset/Contents.json")
        let out = temporary.path + "/out"
        let result = try Actool.run(try Actool.Options(arguments: [
            catalog, "--compile", out, "--output-format", "human-readable-text", "--output-partial-info-plist", out + "/partial.plist",
            "--compress-pngs", "--target-device", "iphone", "--minimum-deployment-target", "18.0", "--platform", "iphoneos", "--app-icon", "AppIcon",
        ]))
        #expect(result.writtenFiles.map { ($0 as NSString).lastPathComponent } == ["AppIcon60x60@2x.png", "AppIcon76x76@2x~ipad.png", "Assets.car", "partial.plist"])
        let png = Array(try #require(FileManager.default.contents(atPath: out + "/AppIcon76x76@2x~ipad.png")))
        var chunks: [(type: String, data: [UInt8])] = []
        var offset = 8
        while offset + 8 <= png.count {
            let length = png[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            chunks.append((String(decoding: png[offset + 4..<offset + 8], as: UTF8.self), Array(png[offset + 8..<offset + 8 + length])))
            offset += 12 + length
        }
        #expect(chunks.map(\.type) == ["CgBI", "IHDR", "gAMA", "sRGB", "cHRM", "eXIf", "iDOT", "IDAT", "IDAT", "IEND"])
        #expect(Array(chunks[1].data.prefix(10)) == [0, 0, 0, 152, 0, 0, 0, 152, 8, 6])
        #expect(Array(chunks[5].data.suffix(16)) == [0xA0, 0x03, 0, 4, 0, 0, 0, 1, 0, 0, 0, 152, 0, 0, 0, 0])
        let plist = String(decoding: try #require(FileManager.default.contents(atPath: out + "/partial.plist")), as: UTF8.self)
        #expect(plist.components(separatedBy: "CFBundleIconName").count == 2)
    }

    /// `--include-all-app-icons` with single-size sets for iPhone: the alternate gives renditions
    /// and no PNG; the iPhone key lists it, the iPad key (no iPad icons) neither names the primary
    /// icon nor lists alternates (`alternate-app-icons`).
    @Test func alternateSetsAreListedForTheirDevices() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        let rows: [[UInt8]] = (0..<1024).map { y in (0..<1024).flatMap { x -> [UInt8] in [UInt8(x % 256), UInt8(y % 256), 90] } }
        for name in ["AppIcon", "AltA"] {
            try FileSystem.write(Data(ImageSetTests.png(width: 1024, height: 1024, colorType: 2, rows: rows)), to: catalog + "/\(name).appiconset/icon.png")
            let entry: [String: Any] = ["filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]
            try FileSystem.write(try JSONSerialization.data(withJSONObject: ["images": [entry], "info": ["author": "xcode", "version": 1]]),
                                 to: catalog + "/\(name).appiconset/Contents.json")
        }
        let out = temporary.path + "/out"
        let result = try Actool.run(try Actool.Options(arguments: [
            catalog, "--compile", out, "--output-format", "human-readable-text", "--output-partial-info-plist", out + "/partial.plist",
            "--compress-pngs", "--target-device", "iphone", "--minimum-deployment-target", "18.0", "--platform", "iphoneos",
            "--app-icon", "AppIcon", "--include-all-app-icons",
        ]))
        #expect(!result.writtenFiles.contains { $0.contains("AltA") })
        let data = try #require(FileManager.default.contents(atPath: out + "/partial.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]])
        #expect((plist["CFBundleIcons"]?["CFBundleAlternateIcons"] as? [String: Any])?.keys.sorted() == ["AltA"])
        #expect(plist["CFBundleIcons~ipad"]?["CFBundleAlternateIcons"] == nil)
        #expect((plist["CFBundleIcons~ipad"]?["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconName"] == nil)
    }

    /// A watchOS catalog (`watchos`): the 3x image is left out, the watchOS icon gives no PNG and
    /// only its name in the partial Info.plist; iOS devices with `--platform watchos` stop nomac.
    @Test func watchCatalogsKeepOneAndTwoX() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        let rows: [[UInt8]] = (0..<1024).map { y in (0..<1024).flatMap { x -> [UInt8] in [UInt8(x % 256), UInt8(y % 256), 90] } }
        try FileSystem.write(Data(ImageSetTests.png(width: 1024, height: 1024, colorType: 2, rows: rows)), to: catalog + "/AppIcon.appiconset/icon.png")
        let entry: [String: Any] = ["filename": "icon.png", "idiom": "universal", "platform": "watchos", "size": "1024x1024"]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: ["images": [entry], "info": ["author": "xcode", "version": 1]]),
                             to: catalog + "/AppIcon.appiconset/Contents.json")
        let out = temporary.path + "/out"
        func arguments(_ devices: [String]) -> [String] {
            [catalog, "--compile", out, "--output-format", "human-readable-text", "--output-partial-info-plist", out + "/partial.plist", "--compress-pngs"]
                + devices.flatMap { ["--target-device", $0] } + ["--minimum-deployment-target", "9.0", "--platform", "watchos", "--app-icon", "AppIcon"]
        }
        let result = try Actool.run(try Actool.Options(arguments: arguments(["watch"])))
        #expect(result.writtenFiles.map { ($0 as NSString).lastPathComponent } == ["Assets.car", "partial.plist"])
        let data = try #require(FileManager.default.contents(atPath: out + "/partial.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: [String: String]]])
        #expect(plist == ["CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconName": "AppIcon"]]])
        #expect(throws: NomacError.self) { try Actool.run(try Actool.Options(arguments: arguments(["iphone"]))) }
    }

    /// Watch case sizes as rendition subtypes, and their bits in `BITMAPKEYS` masks, 42mm's before
    /// 40mm's (`watchos` watch-multi case, `complications` screen-widths case).
    @Test func watchCaseSizesAreSubtypesWithTheirOwnMaskBits() {
        #expect(AppIconSet.watchSubtypes["38mm"] == 320 && AppIconSet.watchSubtypes["49mm"] == 502)
        #expect([320, 384, 340, 390, 430, 484, 502].map { RenditionAttribute.subtype.maskBit($0) } == [8, 9, 13, 14, 23, 24, 28])
        #expect(RenditionAttribute.subtype.maskBit(1792) == 16 && RenditionAttribute.dimension2.maskBit(5) == 5)
    }

    /// Ancillary chunks in actool's order, `sRGB` bringing `gAMA` and `cHRM`; `zTXt` is not
    /// written as it was (`app-icons` icon-chunks cases).
    @Test func iconChunksFollowActoolsOrder() throws {
        func image(_ types: [String]) -> PNGImage {
            var image = PNGImage(width: 1, height: 1, pixels: [0, 0, 0, 255])
            image.ancillaryChunks = types.map { PNGImage.Chunk(type: $0, data: $0 == "sRGB" ? [0] : Array($0.utf8)) }
            return image
        }
        let chunks = try IconPNG.ancillaryChunks(image(["tEXt", "sRGB", "eXIf", "pHYs", "iTXt", "tEXt"]), path: "/i.png")
        #expect(chunks.map(\.type) == ["gAMA", "sRGB", "cHRM", "eXIf", "iTXt", "pHYs", "tEXt", "tEXt"])
        #expect(chunks[0].data == IconPNG.bigEndian(45_455))
        #expect(throws: NomacError.self) { try IconPNG.ancillaryChunks(image(["zTXt"]), path: "/i.png") }
    }

    static func icon(_ idiom: String, _ size: String, _ scale: Int) -> AppIconSet.Icon {
        AppIconSet.Icon(idiom: idiom, size: size, scale: scale, filename: "\(idiom)\(size)@\(scale).png", path: "/i.png",
                        image: PNGImage(width: 1, height: 1, pixels: [0, 0, 0, 255]))
    }

    /// `dim2` ranks the set's sizes with the 60 pt 3x image's 90 pt copy; PNG names, Info.plist
    /// files and the notices for older sizes, of targeted devices only (icons-legacy-all).
    @Test func sizesNamesAndNotices() throws {
        let icons = [Self.icon("iphone", "60x60", 2), Self.icon("iphone", "60x60", 3), Self.icon("iphone", "57x57", 2), Self.icon("ipad", "76x76", 1),
                     Self.icon("ipad", "76x76", 2), Self.icon("ipad", "83.5x83.5", 2), Self.icon("ios-marketing", "1024x1024", 1)]
        let asset = AssetCatalog.Asset(name: "AppIcon", type: "appiconset", path: "/C.xcassets/AppIcon.appiconset", contents: [:])
        let compiled = try AppIconSet.compile(asset, icons: icons, catalog: "/C.xcassets", standaloneBehavior: "all", targetDevices: ["iphone"])
        #expect(compiled.sources.map(\.dimension2) == [2, 2, 1, 3, 3, 4, 6, 5])
        #expect(compiled.pngs.map(\.filename) == ["AppIcon60x60@2x.png", "AppIcon60x60@3x.png", "AppIcon57x57@2x.png", "AppIcon76x76~ipad.png",
                                                  "AppIcon76x76@2x~ipad.png", "AppIcon83.5x83.5@2x~ipad.png"])
        let files: (String) -> PropertyListValue? = {
            guard case .dictionary(let icons)? = compiled.infoPlist[$0], case .dictionary(let primary)? = icons["CFBundlePrimaryIcon"] else { return nil }
            return primary["CFBundleIconFiles"]
        }
        #expect(files("CFBundleIcons") == .array([.string("AppIcon57x57"), .string("AppIcon60x60")]))
        #expect(files("CFBundleIcons~ipad") == .array(["AppIcon57x57", "AppIcon60x60", "AppIcon76x76", "AppIcon83.5x83.5"].map { .string($0) }))
        #expect(compiled.notices == [
            "/C.xcassets:./AppIcon.appiconset/[][iphone][57x57][][][2x][][][][]: notice: 57x57@2x app icons only apply to iPhone apps targeting releases of iOS prior to 7.0",
        ])
    }
}
