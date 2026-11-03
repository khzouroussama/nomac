import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Asset symbol generation as `assets-experiments symbols` observed it on self-written catalogs.
@Suite struct AssetSymbolsTests {
    struct Name {
        var name: String
        var member: String
        var objectiveC: String
    }

    /// A set name, its Swift member and its Objective-C constant after the prefix (empty: none).
    static let names: [Name] = [
        Name(name: "red", member: "red", objectiveC: "Red"),
        Name(name: "redColor", member: "red", objectiveC: "RedColor"),
        Name(name: "red color", member: "red", objectiveC: "RedColor"),
        Name(name: "AccentColor", member: "accent", objectiveC: "AccentColor"),
        Name(name: "backgroundImage", member: "background", objectiveC: "BackgroundImage"),
        Name(name: "Color", member: "color", objectiveC: "Color"),
        Name(name: "colorful", member: "colorful", objectiveC: "Colorful"),
        Name(name: "ImageView", member: "imageView", objectiveC: "ImageView"),
        Name(name: "ColorColor", member: "color", objectiveC: "ColorColor"),
        Name(name: "redColorImage", member: "red", objectiveC: "RedColorImage"),
        Name(name: "MyCOLOR", member: "my", objectiveC: "MyCOLOR"),
        Name(name: "NSImage", member: "NS", objectiveC: "NSImage"),
        Name(name: "redUIColor", member: "redUI", objectiveC: "RedUIColor"),
        Name(name: "HELLO_COLOR", member: "HELLO", objectiveC: "_HELLO_COLOR"),
        Name(name: "DNSimple", member: "dnSimple", objectiveC: "DNSimple"),
        Name(name: "IDme", member: "iDme", objectiveC: "IDme"),
        Name(name: "CyDIS", member: "cyDIS", objectiveC: "CyDIS"),
        Name(name: "ABCd", member: "abCd", objectiveC: "ABCd"),
        Name(name: "URLString", member: "urlString", objectiveC: "URLString"),
        Name(name: "myURLString", member: "myURLString", objectiveC: "MyURLString"),
        Name(name: "HTTPSConnection", member: "httpsConnection", objectiveC: "HTTPSConnection"),
        Name(name: "iOS", member: "iOS", objectiveC: "IOS"),
        Name(name: "ABC", member: "ABC", objectiveC: "ABC"),
        Name(name: "ABC_def", member: "abcDef", objectiveC: "ABCDef"),
        Name(name: "TETR.IO", member: "TETR_IO", objectiveC: "_TETR_IO"),
        Name(name: "HELLO WORLD", member: "HELLO_WORLD", objectiveC: "_HELLO_WORLD"),
        Name(name: "A1B2", member: "A_1_B_2", objectiveC: "_A_1_B_2"),
        Name(name: "17thShard", member: "_17ThShard", objectiveC: "17ThShard"),
        Name(name: "4K", member: "_4_K", objectiveC: "_4_K"),
        Name(name: "4k", member: "_4K", objectiveC: "4K"),
        Name(name: "42", member: "_42", objectiveC: "42"),
        Name(name: "Time4VPS", member: "time4VPS", objectiveC: "Time4VPS"),
        Name(name: "MP3Player", member: "mp3Player", objectiveC: "MP3Player"),
        Name(name: "my2ndCar", member: "my2NdCar", objectiveC: "My2NdCar"),
        Name(name: "mixed_Case-Name.Here", member: "mixedCaseNameHere", objectiveC: "MixedCaseNameHere"),
        Name(name: "apostrophe's", member: "apostropheS", objectiveC: "ApostropheS"),
        Name(name: "paren(1)", member: "paren1", objectiveC: "Paren1"),
        Name(name: "__double", member: "double", objectiveC: "Double"),
        Name(name: "_private", member: "`private`", objectiveC: "Private"),
        Name(name: "default", member: "`default`", objectiveC: "Default"),
        Name(name: "Self", member: "`self`", objectiveC: "Self"),
        Name(name: "Type", member: "type", objectiveC: "Type"),
        Name(name: "Any", member: "any", objectiveC: "Any"),
        Name(name: "open", member: "open", objectiveC: "Open"),
        Name(name: "café", member: "café", objectiveC: "Caf"),
        Name(name: "Ünïcödé", member: "ünïcödé", objectiveC: "ncd"),
        Name(name: "ÉTÉ", member: "ÉTÉ", objectiveC: "ÉTÉ"),
        Name(name: "ÉTÉColor", member: "ÉTÉ", objectiveC: "TColor"),
        Name(name: "日本", member: "日本", objectiveC: ""),
        Name(name: "日本Color", member: "日本", objectiveC: "Color"),
        Name(name: "x½y", member: "x½Y", objectiveC: "XY"),
        Name(name: "ßtraße", member: "ßtraße", objectiveC: "SStrae"),
        Name(name: "\u{1C5}ungla", member: "\u{1C6}ungla", objectiveC: "ungla"),
        Name(name: "\u{130}stanbul", member: "i\u{307}stanbul", objectiveC: "stanbul"),
        Name(name: "ﬁx", member: "ﬁx", objectiveC: "FIx"),
        Name(name: "Ⅻ", member: "ⅻ", objectiveC: ""),
        Name(name: "١٢٣", member: "١٢٣", objectiveC: "١٢٣"),
        Name(name: "emoji😀", member: "emoji", objectiveC: "Emoji"),
        Name(name: "😀", member: "", objectiveC: ""),
        Name(name: "_", member: "", objectiveC: ""),
    ]

    @Test func setNamesBecomeSwiftMembersAndObjectiveCConstants() {
        for name in Self.names {
            #expect(AssetSymbolName.member(name.name) == name.member, "\(name.name)")
            #expect(AssetSymbolName.objectiveC(name.name) == name.objectiveC, "\(name.name)")
        }
    }

    static let namespaces: [(String, String)] = [
        ("my folder", "MyFolder"), ("icons_v2", "IconsV2"), ("UI", "UI"), ("3D", "_3_D"), ("class", "Class"),
        ("Ns-A", "NsA"), ("ns_b", "NsB"), ("redColor", "Red"), ("ABC.DEF", "ABC_DEF"), ("😀", ""),
    ]

    @Test func namespaceFoldersBecomeEnums() {
        for (folder, symbol) in Self.namespaces {
            #expect(AssetSymbolName.namespace(folder) == symbol, "\(folder)")
        }
    }

    static var info: [String: Any] { ["info": ["author": "xcode", "version": 1]] }

    static func write(_ object: [String: Any], to path: String) throws {
        try FileSystem.write(try JSONSerialization.data(withJSONObject: object), to: path)
    }

    static func color(_ folder: String, _ name: String) throws {
        var contents = info
        contents["colors"] = [ColorCatalogTests.entry(ColorCatalogTests.rgb("1.000", "0.000", "0.000"))]
        try write(contents, to: "\(folder)/\(name).colorset/Contents.json")
    }

    /// A set whose entry names a file for `idiom`; symbol mode reads only whether the file exists.
    static func image(_ folder: String, _ name: String, idiom: String = "universal", type: String = "imageset", file: Bool = true) throws {
        let filename = type == "symbolset" ? "i.svg" : "i.png"
        var contents = info
        contents[type == "symbolset" ? "symbols" : "images"] = [["filename": filename, "idiom": idiom, "scale": "1x"]]
        try write(contents, to: "\(folder)/\(name).\(type)/Contents.json")
        if file { try FileSystem.write(Data([0]), to: "\(folder)/\(name).\(type)/\(filename)") }
    }

    static func namespace(_ folder: String, _ name: String) throws -> String {
        var contents = info
        contents["properties"] = ["provides-namespace": true]
        try write(contents, to: "\(folder)/\(name)/Contents.json")
        return folder + "/" + name
    }

    struct Generated {
        var result: Actool.Result
        var swift: String
        var header: String
        var index: [String: Any]
    }

    static func generate(_ catalogs: [String], in directory: String, deploymentTarget: String = "15.0", extensions: String? = "YES") throws -> Generated {
        let derived = directory + "/derived"
        var arguments = catalogs + [
            "--compile", directory + "/app", "--output-format", "human-readable-text", "--notices", "--warnings",
            "--export-dependency-info", directory + "/deps", "--output-partial-info-plist", directory + "/partial.plist",
            "--app-icon", "AppIcon", "--compress-pngs", "--enable-on-demand-resources", "YES", "--development-region", "en",
            "--target-device", "iphone", "--minimum-deployment-target", deploymentTarget, "--platform", "iphoneos",
            "--bundle-identifier", "org.nomac.symbols",
        ]
        if let extensions { arguments += ["--generate-swift-asset-symbol-extensions", extensions] }
        arguments += [
            "--generate-swift-asset-symbols", derived + "/GeneratedAssetSymbols.swift",
            "--generate-objc-asset-symbols", derived + "/GeneratedAssetSymbols.h",
            "--generate-asset-symbol-index", derived + "/GeneratedAssetSymbols-Index.plist",
        ]
        let result = try Actool.run(try Actool.Options(arguments: arguments))
        let index = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: URL(fileURLWithPath: derived + "/GeneratedAssetSymbols-Index.plist")), format: nil)
        return Generated(
            result: result,
            swift: try String(contentsOfFile: derived + "/GeneratedAssetSymbols.swift", encoding: .utf8),
            header: try String(contentsOfFile: derived + "/GeneratedAssetSymbols.h", encoding: .utf8),
            index: index as? [String: Any] ?? [:])
    }

    static func sections(_ swift: String) -> [String] {
        swift.split(separator: "\n").filter { $0.hasPrefix("// MARK: - ") }.map { String($0.dropFirst(11).dropLast(2)) }
    }

    @Test func onlyTheSymbolFilesAreWritten() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.color(catalog, "brandColor")
        try Self.image(catalog, "logo")
        let out = temporary.path + "/out"
        let generated = try Self.generate([catalog], in: out)
        let files = ["-Index.plist", ".h", ".swift"].map { out + "/derived/GeneratedAssetSymbols" + $0 }
        #expect(generated.result.writtenFiles == files)
        #expect(generated.result.standardOutput == "/* com.apple.actool.compilation-results */\n" + files.map { $0 + "\n" }.joined() + "\n")
        for path in ["/app", "/deps", "/partial.plist"] {
            #expect(!FileManager.default.fileExists(atPath: out + path))
        }
    }

    @Test func sectionsDependOnTheDeploymentTargetAndExtensions() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.image(catalog, "logo")
        let base = ["Color Symbols", "Image Symbols"]
        let extensions = ["Color Symbol Extensions", "Image Symbol Extensions", "Thinnable Asset Support"]
        let cases: [(String, String?, [String])] = [
            ("15.0", "YES", base + extensions + ["Backwards Deployment Support"]),
            ("16.4", nil, base + extensions + ["Backwards Deployment Support"]),
            ("15.0", "NO", base + ["Backwards Deployment Support"]),
            ("17.0", "YES", base + extensions),
            ("17.0", "NO", base),
        ]
        for (index, (target, flag, expected)) in cases.enumerated() {
            let swift = try Self.generate([catalog], in: temporary.path + "/out\(index)", deploymentTarget: target, extensions: flag).swift
            #expect(Self.sections(swift) == expected, "\(target) \(flag ?? "-")")
            #expect(swift.hasSuffix(expected.last == "Backwards Deployment Support" ? "}\n#endif" : "\n\n"))
            #expect(swift.contains("extension DeveloperToolsSupport.ImageResource {") == (target == "17.0"))
            #expect(swift.contains("import UIKit") == (target != "17.0" || flag == "YES"))
        }
    }

    @Test func duplicateEmptyAndConflictingSymbolsAreWarnings() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        for name in ["red", "redColor", "_"] { try Self.color(catalog, name) }
        let generated = try Self.generate([catalog], in: temporary.path + "/out")
        let swift = generated.swift
        #expect(swift.contains("    static let red = ColorResource(name: \"red\", bundle: resourceBundle)\n"))
        #expect(swift.contains("    #warning(\"The \\\"redColor\\\" color asset name resolves to the symbol \\\"red\\\" which already exists. Try renaming the asset.\")\n"))
        #expect(swift.contains("    #warning(\"The \\\"_\\\" color asset name resolves to an empty symbol. Try renaming the asset.\")\n"))
        for framework in ["NSColor", "UIColor", "Color"] {
            #expect(swift.contains("#warning(\"The \\\"red\\\" color asset name resolves to a conflicting \(framework) symbol \\\"red\\\". Try renaming the asset.\")"))
        }
        #expect(!swift.contains("static var red:"))
        #expect(swift.components(separatedBy: "#warning").count - 1 == 5)
        let header = generated.header
        #expect(header.contains("static NSString * const ACBundleID AC_SWIFT_PRIVATE = @\"org.nomac.symbols\";"))
        #expect(header.contains("static NSString * const ACColorNameRedColor AC_SWIFT_PRIVATE = @\"redColor\";"))
        #expect(header.contains("#warning The \"_\" color asset name resolves to an empty symbol. Try renaming the asset.\n"))
        let colors = generated.index["colors"] as? [[String: String]] ?? []
        #expect(colors.map { $0["swiftSymbol"] ?? "" } == ["red", "red"])
    }

    @Test func namespacesNestInSwiftAndPrefixInObjectiveC() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.color(catalog, "Accent")
        try Self.color(catalog, "brandColor")
        let space = try Self.namespace(catalog, "Space")
        try Self.color(space, "spaceColor")
        let generated = try Self.generate([catalog], in: temporary.path + "/out")
        let order = ["static let accent", "enum Space {", "static let space = ColorResource(name: \"Space/spaceColor\"", "static let brand"]
        let positions = order.compactMap { generated.swift.range(of: $0)?.lowerBound }
        #expect(positions.count == order.count && positions == positions.sorted())
        #expect(generated.swift.contains("            .init(resource: .Space.space)\n"))
        let shapeStyle = generated.swift.components(separatedBy: "extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {\n\n")[1]
        #expect(shapeStyle.components(separatedBy: "\n}\n")[0].contains("static var brand"))
        #expect(!shapeStyle.components(separatedBy: "\n}\n")[0].contains("Space"))
        #expect(generated.header.contains("static NSString * const ACColorNameSpaceSpaceColor AC_SWIFT_PRIVATE = @\"Space/spaceColor\";"))
        let colors = generated.index["colors"] as? [[String: String]] ?? []
        let entry = colors.first { $0["relativePath"] == "./Space/spaceColor.colorset" }
        #expect(entry?["objcSymbol"] == "ACColorNameSpaceColor")
        #expect(entry?["swiftSymbol"] == "space")
        #expect(entry?["catalogPath"] == catalog)
    }

    /// `é` is after `f` composed and before it decomposed, however the file system stores it.
    @Test func swiftSortsComposedAndTheHeaderDecomposed() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.color(catalog, "éa")
        try Self.color(catalog, "f")
        let generated = try Self.generate([catalog], in: temporary.path + "/out", extensions: "NO")
        let swift = generated.swift
        #expect(swift.firstRange(of: "static let f =")!.lowerBound < swift.firstRange(of: "static let éa =")!.lowerBound)
        let header = generated.header
        #expect(header.firstRange(of: "ACColorNamea ")!.lowerBound < header.firstRange(of: "ACColorNameF ")!.lowerBound)
    }

    /// Only sets the build has something for: an entry for `universal` or a target device naming
    /// an image file or with a color (on iPhone colors and symbols for `car` too).
    @Test func setsWithNothingForTheTargetsAreLeftOut() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.image(catalog, "iphoneOnly", idiom: "iphone")
        try Self.image(catalog, "ipadOnly", idiom: "ipad")
        try Self.image(catalog, "macOnly", idiom: "mac")
        try Self.image(catalog, "carSymbol", idiom: "car", type: "symbolset")
        var noColor = Self.info
        noColor["colors"] = [["idiom": "universal"]]
        try Self.write(noColor, to: catalog + "/template.colorset/Contents.json")
        var carColor = Self.info
        carColor["colors"] = [ColorCatalogTests.entry(ColorCatalogTests.rgb("1.000", "0.000", "0.000"), idiom: "car")]
        try Self.write(carColor, to: catalog + "/carColor.colorset/Contents.json")
        #expect(try AssetSymbols.scan([catalog], targetDevices: ["iphone"], complication: nil).map(\.name) == ["carColor", "carSymbol", "iphoneOnly"])
        #expect(try AssetSymbols.scan([catalog], targetDevices: ["ipad"], complication: nil).map(\.name) == ["ipadOnly"])
    }

    /// A catalog's `generate-swift-asset-symbol-extensions` property overrides the option for its
    /// assets: an enabled catalog of colors gives color extensions with `NO`, the image section
    /// stays out (home-assistant's Colors.xcassets, `symbol-extensions`); other values stop.
    @Test func catalogPropertyOverridesTheExtensionsOption() throws {
        let temporary = try TemporaryDirectory()
        let colors = temporary.path + "/Colors.xcassets", images = temporary.path + "/Images.xcassets"
        try ColorCatalogTests.writeCatalog(colors, ["tint": [ColorCatalogTests.entry(ColorCatalogTests.rgb("1.000", "0.000", "0.000"))]])
        var enabled = Self.info
        enabled["properties"] = ["generate-swift-asset-symbol-extensions": "enabled"]
        try Self.write(enabled, to: colors + "/Contents.json")
        try ColorCatalogTests.writeCatalog(images, [:])
        try Self.image(images, "pic")
        let assets = try AssetSymbols.scan([colors, images], targetDevices: ["iphone"], complication: nil)
        #expect(assets.map(\.catalogExtensions) == [true, nil])
        let source = try AssetSymbols(assets: assets, options: .init(bundleIdentifier: nil, backDeployment: false, extensions: false)).swiftSource()
        #expect(source.contains("// MARK: - Color Symbol Extensions -") && source.contains("static var tint: UIKit.UIColor"))
        #expect(!source.contains("// MARK: - Image Symbol Extensions -") && source.contains("// MARK: - Thinnable Asset Support -"))
        enabled["properties"] = ["generate-swift-asset-symbol-extensions": "maybe"]
        try Self.write(enabled, to: colors + "/Contents.json")
        #expect(throws: NomacError.self) { try AssetSymbols.scan([colors], targetDevices: ["iphone"], complication: nil) }
    }

    /// Sets actool warns about in its report, which nomac does not write yet.
    @Test func setsActoolWarnsAboutStop() throws {
        let cases: [(String, (String) throws -> Void)] = [
            ("missing file", { try Self.image($0, "a", file: false) }),
            ("car image", { try Self.image($0, "a", idiom: "car") }),
            ("file no entry names", { try Self.image($0, "a"); try FileSystem.write(Data([0]), to: $0 + "/a.imageset/extra.png") }),
            ("symbol file no entry names", { try Self.image($0, "a", type: "symbolset"); try FileSystem.write(Data([0]), to: $0 + "/a.symbolset/b.svg") }),
        ]
        for (what, write) in cases {
            let temporary = try TemporaryDirectory()
            let catalog = temporary.path + "/A.xcassets"
            try ColorCatalogTests.writeCatalog(catalog, [:])
            try write(catalog)
            #expect(throws: NomacError.self, "\(what)") { try AssetSymbols.scan([catalog], targetDevices: ["iphone"], complication: nil) }
        }
    }

    /// Files no entry names are left alone unless actool would warn about them (flutter's
    /// `LaunchImage.imageset/README.md`); visionOS icon stacks add nothing on iOS.
    @Test func unnamedFilesAndIconStacksAreIgnored() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.image(catalog, "launch")
        try FileSystem.write(Data([0]), to: catalog + "/launch.imageset/README.md")
        try FileSystem.write(Data([0]), to: catalog + "/launch.imageset/extra.PNG")
        try ImageSetTests.writeIconStack(catalog + "/Icon.solidimagestack", side: 1024)
        #expect(try AssetSymbols.scan([catalog], targetDevices: ["iphone"], complication: nil).map(\.name) == ["launch"])
    }

    /// Symbol sets are images in the Swift file and the header (after the image sets there), and
    /// `symbols` in the index; Icon Composer icons add nothing (swiftfin).
    @Test func symbolSetsAreImagesListedApart() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.image(catalog, "alpha")
        try Self.image(catalog, "beta", type: "symbolset")
        try Self.image(catalog, "gamma")
        try Self.write(["groups": []], to: temporary.path + "/Icon.icon/icon.json")
        let generated = try Self.generate([catalog, temporary.path + "/Icon.icon"], in: temporary.path + "/out")
        let swift = generated.swift.components(separatedBy: "// MARK: - Image Symbols -")[1]
        #expect(swift.firstRange(of: "static let alpha")!.lowerBound < swift.firstRange(of: "static let beta")!.lowerBound)
        #expect(swift.firstRange(of: "static let beta")!.lowerBound < swift.firstRange(of: "static let gamma")!.lowerBound)
        let header = generated.header
        #expect(header.firstRange(of: "ACImageNameGamma")!.lowerBound < header.firstRange(of: "ACImageNameBeta")!.lowerBound)
        let images = (generated.index["images"] as? [[String: String]] ?? []).map { $0["relativePath"] ?? "" }
        let symbols = (generated.index["symbols"] as? [[String: String]] ?? []).map { $0["relativePath"] ?? "" }
        #expect(images == ["./alpha.imageset", "./gamma.imageset"] && symbols == ["./beta.symbolset"])
    }

    @Test func dataSetsAppIconsAndSetsWithoutContentsAreLeftOut() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.color(catalog, "kept")
        try FileSystem.createDirectory(catalog + "/noContents.colorset")
        try FileSystem.write(Data([0]), to: catalog + "/noContents.imageset/stray")
        try Self.write(Self.info, to: catalog + "/blob.dataset/Contents.json")
        try AppIconTests.writeEmptyAppIcon(catalog)
        try Self.write(Self.info, to: catalog + "/Sprites.spriteatlas/Contents.json")
        try Self.image(catalog + "/Sprites.spriteatlas", "sprite")
        try Self.image(try Self.namespace(catalog, "Atlas.spriteatlas"), "inAtlas")
        try Self.image(catalog + "/ABC.DEF", "dotted")
        let assets = try AssetSymbols.scan([catalog], targetDevices: ["iphone"], complication: nil)
        #expect(assets.map(\.fullName) == ["dotted", "Atlas/inAtlas", "sprite", "kept"])
        #expect(assets.map(\.relativePath) == [
            "./ABC.DEF/dotted.imageset", "./Atlas.spriteatlas/inAtlas.imageset", "./Sprites.spriteatlas/sprite.imageset", "./kept.colorset",
        ])
    }
}
