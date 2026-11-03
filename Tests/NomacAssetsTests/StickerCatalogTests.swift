import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Sticker catalogs as `assets-experiments stickers` observed them (the xcassets case).
@Suite struct StickerCatalogTests {
    static let icons: [(idiom: String, size: String, scale: Int, platform: String?)] = [
        ("iphone", "60x45", 2, nil), ("iphone", "60x45", 3, nil), ("ipad", "67x50", 2, nil), ("ipad", "74x55", 2, nil),
        ("universal", "27x20", 2, "ios"), ("universal", "27x20", 3, "ios"), ("universal", "32x24", 2, "ios"), ("universal", "32x24", 3, "ios"),
        ("ios-marketing", "1024x768", 1, "ios"),
    ]
    static let gif: [UInt8] = Array("GIF89a".utf8) + [
        0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2C,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
    ]

    static func write(_ object: [String: Any], to path: String) throws {
        var object = object
        object["info"] = ["author": "xcode", "version": 1]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: object), to: path)
    }

    static func png(_ width: Int, _ height: Int, _ pixel: (Int, Int) -> [UInt8]) -> Data {
        Data(ImageSetTests.png(width: width, height: height, colorType: 6, rows: (0..<height).map { y in (0..<width).flatMap { pixel($0, y) } }))
    }

    @Test func stickerCatalogGivesActoolsOutputs() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/S.xcassets"
        try Self.write([:], to: catalog + "/Contents.json")
        var images: [[String: Any]] = []
        for (n, icon) in Self.icons.enumerated() {
            let size = icon.size.split(separator: "x").map { Int($0)! * icon.scale }
            try FileSystem.write(Self.png(size[0], size[1]) { x, y in [UInt8((x + n) % 256), UInt8(y * 3 % 256), 90, 255] },
                                 to: catalog + "/iMessage App Icon.stickersiconset/icon\(n).png")
            var entry: [String: Any] = ["filename": "icon\(n).png", "idiom": icon.idiom, "scale": "\(icon.scale)x", "size": icon.size]
            entry["platform"] = icon.platform
            images.append(entry)
        }
        try Self.write(["images": images], to: catalog + "/iMessage App Icon.stickersiconset/Contents.json")
        let pack = catalog + "/Sticker Pack.stickerpack"
        for (name, filename, label) in [("b", "b.png", nil), ("a", "other name.png", "An A"), ("g", "anim.gif", "")] as [(String, String, String?)] {
            let data = filename.hasSuffix(".gif") ? Data(Self.gif) : Self.png(300, 300) { x, _ in [UInt8(x % 256), 40, 200, 255] }
            try FileSystem.write(data, to: pack + "/\(name).sticker/\(filename)")
            var properties: [String: Any] = ["filename": filename]
            properties["accessibility-label"] = label
            try Self.write(["properties": properties], to: pack + "/\(name).sticker/Contents.json")
        }
        try Self.write(["stickers": ["b", "a", "g"].map { ["filename": "\($0).sticker"] }, "properties": ["grid-size": "regular"]], to: pack + "/Contents.json")

        let out = temporary.path + "/out"
        _ = try Actool.run(try Actool.Options(arguments: [
            catalog, "--compile", out, "--output-format", "human-readable-text", "--notices", "--warnings", "--output-partial-info-plist", out + "/partial.plist",
            "--app-icon", "iMessage App Icon", "--compress-pngs", "--include-sticker-content", "--stickers-icon-role", "extension",
            "--sticker-pack-identifier-prefix", "org.example.Stickers.sticker-pack.", "--target-device", "iphone", "--target-device", "ipad",
            "--minimum-deployment-target", "15.0", "--platform", "iphoneos",
        ]))
        func digest(_ names: [String]) throws -> String {
            ColorCatalogTests.hex(SHA256.digest(try names.flatMap { Array(try #require(FileManager.default.contents(atPath: out + "/" + $0))) }))
        }
        let pngs = ["27x20@2x", "27x20@3x", "32x24@2x", "32x24@3x", "60x45@2x", "60x45@3x", "67x50@2x", "74x55@2x"].map { "iMessage App Icon\($0).png" }
        #expect(try digest(["Assets.car"]) == "3a9978031d99d96f61abf784e4dab81c5df96b2f133f73ba9f808b97d868b1b4")
        #expect(try digest(["partial.plist"]) == "25741ff51a5a5a5a0e9dc8e911832bb6ca8a9b017ef2fd9f4d7589486425c9fe")
        #expect(try digest(["Sticker Pack.stickerpack/Info.plist"]) == "3c76e3d8cb4c42b1486203fb8b3485979f58c67c810dfb376d96d08c63be9ca2")
        #expect(try digest(pngs) == "1428594eba6f2fcf66a2a8878ce851747b686403f67ab90803cecc6a9e53803d")
        #expect(try FileSystem.sortedContents(of: out + "/Sticker Pack.stickerpack") == ["Info.plist", "a.png", "b.png", "g.gif"])
    }
}
