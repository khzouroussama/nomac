import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Refusals that became rules, with the values actool gave on self-written catalogs.
@Suite struct RefusalRulesTests {
    // MARK: Icon Composer icons and app icon sets of one name (`alternate-app-icons` same-name)

    static let oneIcon = #"{"fill": {"solid": "srgb:1.00000,0.00000,0.00000,1.00000"}, "groups": [{"layers": [{"image-name": "dot.svg", "name": "dot"}]}]}"#

    static func singleSizeSet(_ folder: String, shade: UInt8) throws {
        let rows = [[UInt8]](repeating: [UInt8](repeating: shade, count: 1024 * 3), count: 1024)
        try FileSystem.write(Data(ImageSetTests.png(width: 1024, height: 1024, colorType: 2, rows: rows)), to: folder + "/icon.png")
        try StickerCatalogTests.write(["images": [["filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]]], to: folder + "/Contents.json")
    }

    /// The icon replaces the set of its name, as primary and as alternate, whichever input comes
    /// first; the other sets stay alternates.
    @Test func anIconReplacesTheAppIconSetOfItsName() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try StickerCatalogTests.write([:], to: catalog + "/Contents.json")
        for (name, shade) in [("Main", 10), ("Alt", 120), ("Other", 200)] as [(String, UInt8)] {
            try Self.singleSizeSet(catalog + "/\(name).appiconset", shade: shade)
        }
        for name in ["Main", "Alt"] { try IconComposerTests.writeIcon(temporary.path + "/\(name).icon", json: Self.oneIcon) }
        let out = temporary.path + "/out"
        _ = try Actool.run(try Actool.Options(arguments: [
            catalog, temporary.path + "/Main.icon", temporary.path + "/Alt.icon", "--compile", out, "--output-format", "human-readable-text",
            "--output-partial-info-plist", out + "/partial.plist", "--compress-pngs", "--target-device", "iphone", "--target-device", "ipad",
            "--minimum-deployment-target", "15.0", "--platform", "iphoneos", "--app-icon", "Main", "--include-all-app-icons",
        ]))
        let plist = try #require(FileManager.default.contents(atPath: out + "/partial.plist"))
        let root = try #require(try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])
        let icons = try #require(root["CFBundleIcons"] as? [String: Any])
        #expect(Set((icons["CFBundleAlternateIcons"] as? [String: Any] ?? [:]).keys) == ["Alt", "Other"])
    }

    // MARK: Sticker options (`sticker-options`)

    static func stickerCatalogWithoutImages(_ catalog: String) throws {
        try StickerCatalogTests.write([:], to: catalog + "/Contents.json")
        try StickerCatalogTests.write(["images": []], to: catalog + "/Stickers.stickersiconset/Contents.json")
        try StickerCatalogTests.write(["stickers": [], "properties": ["grid-size": "regular"]], to: catalog + "/Pack.stickerpack/Contents.json")
    }

    /// Without `--app-icon` a stickers icon set and a pack add nothing, whatever the other options
    /// (the options bluewallet's and rainbow's catalogs were swept with).
    @Test(arguments: [[], ["--include-sticker-content"], ["--stickers-icon-role", "extension"],
                      ["--include-sticker-content", "--stickers-icon-role", "extension", "--sticker-pack-identifier-prefix", "org.example."]] as [[String]])
    func withoutAnAppIconStickersAddNothing(_ extra: [String]) throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/S.xcassets", out = temporary.path + "/out"
        try Self.stickerCatalogWithoutImages(catalog)
        let result = try Actool.run(try Actool.Options(arguments: [
            catalog, "--compile", out, "--output-format", "human-readable-text", "--output-partial-info-plist", out + "/partial.plist",
            "--compress-pngs", "--target-device", "iphone", "--minimum-deployment-target", "15.0", "--platform", "iphoneos",
        ] + extra))
        #expect(result.writtenFiles == [out + "/partial.plist"] && !result.failed)
    }

    /// `--stickers-icon-role` leaves icon stacks out of the message for a name nothing has.
    @Test(arguments: [(["--stickers-icon-role", "extension"], "stickers icon set or app icon set"), ([], "stickers icon set, app icon set, or icon stack")] as [([String], String)])
    func theRoleChangesTheMissingIconMessage(_ extra: [String], _ wanted: String) throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/S.xcassets", out = temporary.path + "/out"
        try Self.stickerCatalogWithoutImages(catalog)
        let result = try Actool.run(try Actool.Options(arguments: [
            catalog, "--compile", out, "--output-format", "human-readable-text", "--output-partial-info-plist", out + "/partial.plist", "--app-icon", "Nope",
            "--compress-pngs", "--target-device", "iphone", "--minimum-deployment-target", "15.0", "--platform", "iphoneos",
        ] + extra))
        #expect(result.failed && result.standardOutput.contains("\(catalog): error: None of the input catalogs contained a matching \(wanted) named  \"Nope\"."))
    }

    // MARK: visionOS icon stacks (`icon-stacks`)

    /// A stack of layers, each `nil` (no file) or a PNG of the given size, idiom and scale.
    static func stack(_ path: String, _ layers: [(name: String, image: (width: Int, height: Int, idiom: String, scale: String?)?)]) throws {
        try StickerCatalogTests.write(["layers": layers.map { ["filename": "\($0.name).solidimagestacklayer"] }], to: path + "/Contents.json")
        for layer in layers {
            let set = "\(path)/\(layer.name).solidimagestacklayer/Content.imageset"
            var entry: [String: Any] = ["idiom": layer.image?.idiom ?? "vision", "scale": "2x"]
            if let image = layer.image {
                entry["filename"] = "l.png"
                entry["scale"] = image.scale
                let rows = [[UInt8]](repeating: [UInt8](repeating: 9, count: image.width * 3), count: image.height)
                try FileSystem.write(Data(ImageSetTests.png(width: image.width, height: image.height, colorType: 2, rows: rows)), to: set + "/l.png")
            }
            try StickerCatalogTests.write(["images": [entry]], to: set + "/Contents.json")
        }
    }

    static func fill(_ layer: String, _ frame: String) -> String {
        "The last visionOS App Icon Layer with content, “\(layer)”, must exactly fill the image stack. Its current frame is {{0, 0}, {\(frame)}} while the visionOS App Icon's size is {512, 512}."
    }

    @Test func iconStackChecks() throws {
        let temporary = try TemporaryDirectory()
        let good = (width: 1024, height: 1024, idiom: "vision", scale: Optional("2x"))
        let vlc = (width: 484, height: 512, idiom: "vision", scale: Optional("2x"))
        func small(_ idiom: String) -> (width: Int, height: Int, idiom: String, scale: String?) { (100, 100, idiom, "2x") }
        let cases: [(String, [(name: String, image: (width: Int, height: Int, idiom: String, scale: String?)?)], [String])] = [
            ("good", [("Front", good), ("Back", good)], []),
            ("no content", [("Front", nil), ("Middle", nil), ("Back", nil)], []),
            ("front only", [("Front", good), ("Back", nil)], []),
            ("earlier layer of another size", [("Front", vlc), ("Middle", nil), ("Back", good)], []),
            ("last layer small", [("Front", good), ("Back", vlc)], [Self.fill("Back", "242, 256")]),
            ("last with content small", [("Front", vlc), ("Back", nil)], [Self.fill("Front", "242, 256")]),
            ("half points", [("Front", good), ("Back", (485, 513, "vision", "2x"))], [Self.fill("Back", "242.5, 256.5")]),
            ("no scale is 1x", [("Front", good), ("Back", (1024, 1024, "vision", nil))], [Self.fill("Back", "1024, 1024")]),
            ("no scale fills at 512", [("Front", good), ("Back", (512, 512, "vision", nil))], []),
            ("reality fills", [("Front", (1024, 1024, "reality", "2x")), ("Back", (1024, 1024, "reality", "2x"))], []),
            ("reality small", [("Front", good), ("Back", small("reality"))], [Self.fill("Back", "50, 50")]),
            ("one layer", [("Back", good)], ["The visionOS App Icon “Stack” must have at least 2 layers."]),
            ("one empty layer", [("Back", nil)], ["The visionOS App Icon “Stack” must have at least 2 layers."]),
            ("no layers", [], ["The visionOS App Icon “Stack” must have at least 2 layers."]),
            ("four layers", [("A", good), ("B", good), ("C", good), ("D", good)], ["The visionOS App Icon “Stack” may not have more than 3 layers."]),
            ("one small layer", [("Back", small("vision"))], [Self.fill("Back", "50, 50"), "The visionOS App Icon “Stack” must have at least 2 layers."]),
        ]
        for (index, (what, layers, expected)) in cases.enumerated() {
            let path = temporary.path + "/\(index)/Stack.solidimagestack"
            try Self.stack(path, layers)
            #expect(try SolidImageStack.errors(path) == expected, "\(what)")
        }
    }

    /// Scales actool warns about for the idiom, and layers of more than one image, stop.
    @Test func iconStackShapesNotCoveredStop() throws {
        let temporary = try TemporaryDirectory()
        let path = temporary.path + "/Stack.solidimagestack"
        try Self.stack(path, [("Front", (512, 512, "vision", "1x")), ("Back", (512, 512, "vision", "1x"))])
        #expect(throws: NomacError.self) { try SolidImageStack.errors(path) }
    }

    /// The document errors come twice in the report, and actool still exits with 0.
    @Test func iconStackErrorsAreReportedTwice() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/S.xcassets", out = temporary.path + "/out"
        try StickerCatalogTests.write([:], to: catalog + "/Contents.json")
        try Self.stack(catalog + "/Icon.solidimagestack", [("Front", (1024, 1024, "vision", "2x")), ("Back", (100, 100, "vision", "2x"))])
        let result = try Actool.run(try Actool.Options(arguments: [
            catalog, "--compile", out, "--output-format", "human-readable-text", "--output-partial-info-plist", out + "/partial.plist",
            "--target-device", "iphone", "--minimum-deployment-target", "15.0", "--platform", "iphoneos",
        ]))
        let line = "\(catalog):./Icon.solidimagestack: error: " + Self.fill("Back", "50, 50") + "\n"
        #expect(result.standardOutput.hasPrefix("/* com.apple.actool.document.errors */\n" + line + line + "/* com.apple.actool.compilation-results */\n"))
        #expect(!result.failed)
    }

    // MARK: System colors (`colors`, system-color-platforms)

    static func payload(_ name: String, platform: String?, dark: Bool = false) throws -> [UInt8] {
        let asset = AssetCatalog.Asset(name: "c", type: "colorset", path: "/c.colorset", contents: [:])
        return try ColorSet.systemColor(name, platform: platform, appearance: dark ? .dark : .any, asset: asset)
    }

    static func color(space: UInt32, _ components: [UInt32], name: String) -> [UInt8] {
        var out = ByteWriter()
        out.append(Array("RLOC".utf8))
        out.appendLE(UInt32(1))
        out.appendLE(space | 0x100)
        out.appendLE(UInt32(components.count))
        for component in components { out.appendLE(Double(Float(bitPattern: component))) }
        out.append(Array("RLOC".utf8))
        out.appendLE(UInt32(1))
        out.appendLE(UInt32(name.utf8.count))
        out.append(Array(name.utf8))
        return out.bytes
    }

    @Test func groupedTableBackgroundHasItsValues() throws {
        let name = "groupTableViewBackgroundColor"
        #expect(try Self.payload(name, platform: "ios") == Self.color(space: 4, [0x3F72F1AA, 0x3F72F1AA, 0x3F781062, 0x3F800000], name: name))
        #expect(try Self.payload(name, platform: "ios", dark: true) == Self.color(space: 6, [0x00000000, 0x3F800000], name: name))
    }

    /// Every platform, or none, gives the iOS values for the names none of them warns about; the
    /// iOS-only names and unknown ones warn, where nomac stops.
    @Test(arguments: [nil, "universal", "osx", "tvos", "watchos", "xros", "visionos"] as [String?])
    func platformsGiveTheIOSValues(_ platform: String?) throws {
        for name in SystemColors.values.keys.sorted() where SystemColors.values[name]!.universal {
            #expect(try Self.payload(name, platform: platform) == Self.payload(name, platform: "ios"))
            #expect(try Self.payload(name, platform: platform, dark: true) == Self.payload(name, platform: "ios", dark: true))
        }
        #expect(throws: NomacError.self) { try Self.payload("groupTableViewBackgroundColor", platform: platform) }
        #expect(throws: NomacError.self) { try Self.payload("bogusColor", platform: platform) }
    }

    // MARK: Image entries actool assigns (`symbols`, image-entry-scales)

    static func entry(_ catalog: String, _ name: String, idiom: String, scale: String?, file: Bool = true) throws {
        var entry: [String: Any] = ["idiom": idiom]
        entry["scale"] = scale
        if file { entry["filename"] = "i.png" }
        try StickerCatalogTests.write(["images": [entry]], to: "\(catalog)/\(name).imageset/Contents.json")
        if file { try FileSystem.write(Data([0]), to: "\(catalog)/\(name).imageset/i.png") }
    }

    /// With and without a file; `watch` 2x, `vision` 2x, `car` 2x and 3x (pocket-casts') are assigned.
    @Test(arguments: [
        ("car", "1x"), ("ipad", "3x"), ("mac", "3x"), ("tv", "3x"), ("vision", "1x"), ("vision", "3x"), ("watch", "1x"), ("watch", "3x"),
        ("ios-marketing", "1x"), ("ios-marketing", "2x"), ("ios-marketing", "3x"), ("ios-marketing", nil),
    ] as [(String, String?)])
    func entriesActoolWarnsAboutStop(_ idiom: String, _ scale: String?) throws {
        let temporary = try TemporaryDirectory()
        try StickerCatalogTests.write([:], to: temporary.path + "/A.xcassets/Contents.json")
        try Self.entry(temporary.path + "/A.xcassets", "a", idiom: idiom, scale: scale)
        #expect(throws: NomacError.self) { try AssetSymbols.scan([temporary.path + "/A.xcassets"], targetDevices: ["iphone", "ipad"], complication: nil) }
    }

    /// The sets each target lists: `car` entries count on iPhone, and `vision`, `watch`, `tv` and
    /// `mac` ones never, without a warning.
    @Test func assignedEntriesAreListedForTheirTargets() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try StickerCatalogTests.write([:], to: catalog + "/Contents.json")
        for scale in ["2x", "3x", nil] { try Self.entry(catalog, "car\(scale ?? "none")", idiom: "car", scale: scale) }
        for scale in ["2x", nil] {
            try Self.entry(catalog, "vision\(scale ?? "none")", idiom: "vision", scale: scale)
            try Self.entry(catalog, "watch\(scale ?? "none")", idiom: "watch", scale: scale)
        }
        for scale in ["1x", "2x", nil] {
            try Self.entry(catalog, "tv\(scale ?? "none")", idiom: "tv", scale: scale)
            try Self.entry(catalog, "mac\(scale ?? "none")", idiom: "mac", scale: scale)
            try Self.entry(catalog, "ipad\(scale ?? "none")", idiom: "ipad", scale: scale)
        }
        func listed(_ devices: [String]) throws -> [String] { try AssetSymbols.scan([catalog], targetDevices: devices, complication: nil).map(\.name).sorted() }
        let cars = ["car2x", "car3x", "carnone"], iPads = ["ipad1x", "ipad2x", "ipadnone"]
        #expect(try listed(["iphone"]) == cars)
        #expect(try listed(["ipad"]) == iPads)
        #expect(try listed(["iphone", "ipad"]) == cars + iPads)
        #expect(try AssetSymbols.scan([catalog], targetDevices: ["iphone", "ipad"], complication: nil).allSatisfy(\.isThinnable))
    }

    /// Image and color entries for `car` come with iPhone among the targets (idiom 4); data set
    /// ones are unassigned children (`images`, car-entries).
    @Test func carEntriesGoWithIPhone() throws {
        let temporary = try TemporaryDirectory()
        let folder = temporary.path + "/c.imageset"
        let rows = [[UInt8]](repeating: [UInt8](repeating: 9, count: 8 * 3), count: 8)
        try FileSystem.write(Data(ImageSetTests.png(width: 8, height: 8, colorType: 2, rows: rows)), to: folder + "/p.png")
        func image(_ scale: String?) -> AssetCatalog.Asset {
            var entry: [String: Any] = ["idiom": "car", "filename": "p.png"]
            entry["scale"] = scale
            return AssetCatalog.Asset(name: "c", type: "imageset", path: folder, contents: ["images": [entry]])
        }
        let phone = Idiom.iOS(targetDevices: ["iphone"]), pad = Idiom.iOS(targetDevices: ["ipad"])
        for (scale, value) in [("2x", 2), ("3x", 3), (nil, 1)] as [(String?, Int)] {
            let sources = try ImageSet.sources(image(scale), idioms: phone)
            #expect(sources.map(\.idiom) == [Idiom.car] && sources.map(\.scale) == [value])
            #expect(try ImageSet.sources(image(scale), idioms: pad).isEmpty)
        }
        #expect(throws: NomacError.self) { try ImageSet.sources(image("1x"), idioms: phone) }
        let color = AssetCatalog.Asset(name: "c", type: "colorset", path: "/c.colorset", contents: [
            "colors": [ColorCatalogTests.entry(ColorCatalogTests.rgb("1.000", "0.000", "0.000"), idiom: "car")],
        ])
        #expect(try ColorSet.renditions(color, idioms: phone, watch: false).map { $0.attributes[.idiom] } == [Idiom.car])
        #expect(try ColorSet.renditions(color, idioms: pad, watch: false).isEmpty)
        let data = AssetCatalog.Asset(name: "d", type: "dataset", path: temporary.path + "/d.dataset", contents: ["data": [["idiom": "car", "filename": "b.txt"]]])
        #expect(throws: NomacError.self) { try DataSet.renditions(data, idioms: phone) }
        #expect(throws: NomacError.self) { try DataSet.renditions(data, idioms: pad) }
    }

    /// Sticker catalogs add nothing to the symbol files.
    @Test func stickersAreLeftOutOfTheSymbols() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/S.xcassets"
        try Self.stickerCatalogWithoutImages(catalog)
        #expect(try AssetSymbols.scan([catalog], targetDevices: ["iphone"], complication: nil).isEmpty)
    }

    // MARK: Type identifiers (`data`, dynamic-identifiers, type-identifier-table)

    @Test(arguments: [
        ("db", "dyn.age80k2u"), ("", "dyn.age8u"), ("meta", "dyn.age8043pyqe"), ("a", "dyn.age80c"), ("b", "dyn.age80e"), ("d", "dyn.age80k"),
        ("a-b", "dyn.age80cppc"), ("a_b", "dyn.age80c15c"), ("a+b", "dyn.age80cn5c"), ("a~b", "dyn.age80c9xc"), ("a'b", "dyn.age80cm5c"),
        ("a%b", "dyn.age80cmpc"), ("a?b", "dyn.age80ct5c"), ("a=b", "dyn.age80c1b7qk"), ("a,b", "dyn.age80c1bqqk"), ("a:b", "dyn.age80c1b4qk"),
        ("a\\b", "dyn.age80c1c6qk"), ("日本", "dyn.age88rf7f64sn2"),
    ])
    func dynamicIdentifiers(_ pathExtension: String, _ identifier: String) {
        #expect(DataSet.dynamicIdentifier(pathExtension: pathExtension) == identifier)
    }

    @Test(arguments: [
        ("f.DB", "dyn.age80k2u"), ("f.Db", "dyn.age80k2u"), ("f.META", "dyn.age8043pyqe"), ("a.png.meta", "dyn.age8043pyqe"),
        ("noext", "dyn.age8u"), ("trailing.", "dyn.age8u"), (".hidden", "dyn.age8u"), ("f.a b", "dyn.age8u"),
        ("f.é", "dyn.age80pxeb"), ("f.Éa", "dyn.age80pxebqe"), ("f.ÉA", "dyn.age80pxebqe"), ("f.ß", "dyn.age86hh2"), ("f.İ", "dyn.age80xxeh"),
        ("f.PNG", "public.png"), ("f.Json", "public.json"), ("f.TXT", "public.plain-text"), ("f.Mp3", "public.mp3"), ("f.ZIP", "public.zip-archive"),
        ("f.HEIC", "public.heic"), ("f.C", "public.c-source"), ("a.b.C", "public.c-source"),
        ("f.c", "public.c-source"), ("f.f", "public.fortran-source"), ("f.h", "public.c-header"), ("f.m", "public.objective-c-source"),
        ("f.o", "public.object-code"), ("f.y", "public.yacc-source"), ("f.z", "public.z-archive"), ("f.7z", "org.7-zip.7-zip-archive"),
        ("f.asm", "dyn.age80c65r"), ("f.woff", "dyn.age81s55gq2"), ("f.woff2", "dyn.age81s55gq23a"), ("f.sqlite", "dyn.age81g6pqrf4gn"), ("f.dat", "dyn.age80k2py"),
    ])
    func typeIdentifiers(_ filename: String, _ identifier: String) {
        #expect(DataSet.typeIdentifier(filename: filename) == identifier)
    }
}
