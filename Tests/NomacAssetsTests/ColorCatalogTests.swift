import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Self-written color catalogs and the outputs Xcode 27.0's actool writes for them, recorded
/// as observed facts (sizes, fields and SHA-256 digests) by `assets-experiments colors`.
@Suite struct ColorCatalogTests {
    static func rgb(_ red: String, _ green: String, _ blue: String, _ alpha: String = "1.000", space: String = "srgb") -> [String: Any] {
        ["color-space": space, "components": ["red": red, "green": green, "blue": blue, "alpha": alpha]]
    }

    static func entry(_ color: [String: Any], idiom: String = "universal", _ extra: [String: Any] = [:]) -> [String: Any] {
        var entry: [String: Any] = ["color": color, "idiom": idiom]
        entry.merge(extra) { $1 }
        return entry
    }

    static func writeCatalog(_ root: String, _ colors: [String: [[String: Any]]]) throws {
        let info: [String: Any] = ["info": ["author": "xcode", "version": 1]]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: info), to: root + "/Contents.json")
        for (name, entries) in colors {
            var contents = info
            contents["colors"] = entries
            try FileSystem.write(try JSONSerialization.data(withJSONObject: contents), to: "\(root)/\(name).colorset/Contents.json")
        }
    }

    static func compile(_ catalog: String, in directory: String, extra: [String] = []) throws -> Actool.Result {
        let options = try Actool.Options(arguments: [
            catalog, "--compile", directory, "--output-format", "human-readable-text", "--notices", "--warnings",
            "--export-dependency-info", directory + "/deps", "--output-partial-info-plist", directory + "/partial.plist",
            "--compress-pngs", "--enable-on-demand-resources", "YES", "--development-region", "en",
            "--target-device", "iphone", "--target-device", "ipad", "--minimum-deployment-target", "18.0", "--platform", "iphoneos",
        ] + extra)
        return try Actool.run(options)
    }

    static func car(_ directory: String) throws -> [UInt8] {
        Array(try #require(FileManager.default.contents(atPath: directory + "/Assets.car")))
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    @Test func oneColor() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try Self.writeCatalog(catalog, ["Red": [Self.entry(Self.rgb("1.000", "0.000", "0.000"))]])
        let result = try Self.compile(catalog, in: temporary.path + "/out")
        let car = try Self.car(temporary.path + "/out")
        #expect(car.count == 18152)
        #expect(Self.hex(SHA256.digest(car)) == "9b0822c5e8b90f5eb8343570fe0965bf4297fa55ff93a9843a7ae64dfc2c04a8")
        #expect(Array(car[0x200..<0x204]) == Array("RATC".utf8))
        #expect(result.standardOutput == """
        /* com.apple.actool.compilation-results */
        \(temporary.path)/out/Assets.car
        \(temporary.path)/out/partial.plist


        """)
        let plist = try String(contentsOfFile: temporary.path + "/out/partial.plist", encoding: .utf8)
        #expect(plist.hasSuffix("<plist version=\"1.0\">\n<dict/>\n</plist>\n"))
    }

    @Test func eightColors() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        let red = [Self.entry(Self.rgb("1.000", "0.000", "0.000"))]
        try Self.writeCatalog(catalog, Dictionary(uniqueKeysWithValues: ["a", "b", "c", "Red", "Blue", "Zebra", "aa", "ab"].map { ($0, red) }))
        _ = try Self.compile(catalog, in: temporary.path + "/out")
        let car = try Self.car(temporary.path + "/out")
        #expect(car.count == 20936)
        #expect(Self.hex(SHA256.digest(car)) == "0ac1cfafed4ffa61b05edb409610ad029b89c479662357fe6366c9743b478e5a")
    }

    /// Color spaces, appearances, idioms, display gamuts and component spellings. actool creates
    /// the appearance keys in a random order; the digest is that of actool's output with them
    /// in name order.
    @Test func colorVariants() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        let dark: [String: Any] = ["appearances": [["appearance": "luminosity", "value": "dark"]]]
        let light: [String: Any] = ["appearances": [["appearance": "luminosity", "value": "light"]]]
        let contrast: [String: Any] = ["appearances": [["appearance": "contrast", "value": "high"]]]
        try Self.writeCatalog(catalog, [
            "P3": [Self.entry(Self.rgb("0.200", "0.400", "0.600", "0.500", space: "display-p3"))],
            "ExtSRGB": [Self.entry(Self.rgb("1.200", "-0.100", "0.500", space: "extended-srgb"))],
            "ExtLinear": [Self.entry(Self.rgb("0.200", "0.300", "0.400", space: "extended-linear-srgb"))],
            "Gray": [Self.entry(["color-space": "gray-gamma-22", "components": ["white": "0.500", "alpha": "1.000"]])],
            "ExtGray": [Self.entry(["color-space": "extended-gray", "components": ["white": "0.250", "alpha": "0.750"]])],
            "Ints": [Self.entry(Self.rgb("255", "128", "0"))],
            "Hex": [Self.entry(Self.rgb("0xFF", "0x80", "0x00"))],
            "Dark": [Self.entry(Self.rgb("1.000", "1.000", "1.000")), Self.entry(Self.rgb("0.000", "0.000", "0.000"), dark)],
            "LightDark": [
                Self.entry(Self.rgb("1.000", "0.000", "0.000")), Self.entry(Self.rgb("0.000", "1.000", "0.000"), light),
                Self.entry(Self.rgb("0.000", "0.000", "1.000"), dark),
            ],
            "Contrast": [Self.entry(Self.rgb("1.000", "0.000", "0.000")), Self.entry(Self.rgb("0.000", "1.000", "0.000"), contrast)],
            "Idioms": ["universal", "iphone", "ipad", "mac", "tv", "watch"].enumerated().map { index, idiom in
                Self.entry(Self.rgb(String(format: "%.3f", Double(index + 1) / 10), "0.000", "0.000"), idiom: idiom)
            },
            "Gamut": [
                Self.entry(Self.rgb("1.000", "0.000", "0.000"), ["display-gamut": "sRGB"]),
                Self.entry(Self.rgb("1.000", "0.000", "0.000", space: "display-p3"), ["display-gamut": "display-P3"]),
            ],
            "Empty": [["idiom": "universal"]],
        ])
        _ = try Self.compile(catalog, in: temporary.path + "/out", extra: ["--accent-color", "P3"])
        let car = try Self.car(temporary.path + "/out")
        #expect(car.count == 25288)
        #expect(Self.hex(SHA256.digest(car)) == "88955e0eda11715e4fdcc72d80242dad0979d34b36206a61febc3d6cf3383a28")
        let plist = try String(contentsOfFile: temporary.path + "/out/partial.plist", encoding: .utf8)
        #expect(plist.contains("<dict>\n\t<key>NSAccentColorName</key>\n\t<string>P3</string>\n</dict>\n"))
    }

    @Test func missingAccentColorWarns() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try Self.writeCatalog(catalog, ["Red": [Self.entry(Self.rgb("1.000", "0.000", "0.000"))]])
        let result = try Self.compile(catalog, in: temporary.path + "/out", extra: ["--accent-color", "Nope"])
        let notice = "/* com.apple.actool.notices */\n\(catalog): warning: Accent color ‘Nope’ is not present in any asset catalogs.\n"
        #expect(result.standardOutput.hasPrefix(notice))
    }

    @Test func catalogWithoutRenditionsWritesNoCar() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try Self.writeCatalog(catalog, ["AccentColor": [["idiom": "universal"]]])
        let result = try Self.compile(catalog, in: temporary.path + "/out")
        #expect(!FileManager.default.fileExists(atPath: temporary.path + "/out/Assets.car"))
        #expect(result.writtenFiles == [temporary.path + "/out/partial.plist"])
        let deps = Array(try #require(FileManager.default.contents(atPath: temporary.path + "/out/deps")))
        #expect(deps == Actool.dependencyInfo(inputs: [catalog], outputs: [temporary.path + "/out/partial.plist"]))
        let version: [UInt8] = [0] + Array("actool-\(XcodeProfile.current.actool.bundleVersion)".utf8) + [0]
        #expect(Array(deps.prefix(version.count)) == version)
    }

    static let spellings: [(String, Double)] = [
        ("0.200", Double(Float(0.2))), ("1", 1.0 / 255), ("128", 128.0 / 255), ("0xFF", 1.0), ("0x1", 17.0 / 255),
        ("1e-1", 1.0 / 255), ("  0.5", 0.5), (".5", 0.5), ("1.000000001", 1.0), ("-0.5", -0.5),
    ]

    @Test(arguments: spellings)
    func componentSpellings(text: String, value: Double) throws {
        let asset = AssetCatalog.Asset(name: "C", type: "colorset", path: "/C.colorset", contents: [:])
        #expect(try ColorSet.component(text, name: "red", asset: asset) == value)
    }

    @Test func versionReport() {
        let actool = XcodeProfile.current.actool
        #expect(Actool.versionReport(format: "human-readable-text")
            == "/* com.apple.actool.version */\nbundle-version: \(actool.bundleVersion)\nshort-bundle-version: \(actool.shortBundleVersion)\n\n")
        #expect(Actool.versionReport(format: "xml1").contains(
            "\t<key>com.apple.actool.version</key>\n\t<dict>\n\t\t<key>bundle-version</key>\n\t\t<string>\(actool.bundleVersion)</string>\n"))
        #expect(Actool.versionReport(format: "xml1").contains("\t<key>nomac</key>\n\t<dict>\n\t\t<key>version</key>\n\t\t<string>\(NomacVersion.current)</string>\n"))
    }

    /// A system color is its light or dark components flagged 0x100, then its name (`colors`,
    /// system-colors); names actool does not know and iOS-only names for `universal` stop.
    @Test func systemColorsStoreTheirComponentsAndName() throws {
        let asset = AssetCatalog.Asset(name: "blue", type: "colorset", path: "/blue.colorset", contents: [:])
        let blue = ["platform": "ios", "reference": "systemBlueColor"]
        let observed = "524c4f43010000000101000004000000000000000000000000000000560ee13f000000000000f03f000000000000f03f"
            + "524c4f43010000000f00000073797374656d426c7565436f6c6f72"
        let payload = try ColorSet.payload(blue, appearance: .any, asset: asset)
        #expect(payload.map { String(format: "%02x", $0) }.joined() == observed)
        let label = try ColorSet.payload(["platform": "universal", "reference": "labelColor"], appearance: .dark, asset: asset)
        #expect(Array(label[8..<12]) == [2, 1, 0, 0] && Array(label[16..<32]) == Array(repeating: 0, count: 6) + [0xF0, 0x3F] + Array(repeating: 0, count: 6) + [0xF0, 0x3F])
        for (platform, name) in [("ios", "bogusColor"), ("universal", "linkColor")] {
            #expect(throws: NomacError.self) { try ColorSet.payload(["platform": platform, "reference": name], appearance: .any, asset: asset) }
        }
        #expect(try ColorSet.payload(["platform": "osx", "reference": "labelColor"], appearance: .dark, asset: asset) == label)
        #expect(throws: NomacError.self) { try ColorSet.payload(blue, appearance: .highContrastAny, asset: asset) }
    }
}
