import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// `nomac assetutil`'s thinning against macOS's assetutil (`distribution_experiments.py`
/// `car-thinning`): the experiment's catalogs, compiled here by nomac's actool (identical to
/// actool's on them), thinned for five trait sets of Xcode 27.0's iOS 18.0 descriptors (an iPad
/// as Mac, an iPhone @3x and one @2x, an sRGB iPad, an APPLE11 iPhone), each digest assetutil's.
@Suite struct CARThinningTests {
    typealias Images = [(name: String, renditions: [(idiom: String, scale: Int)])]
    static let catalogs: [(name: String, images: Images)] = [
        ("thinning", [("shared", [("universal", 1), ("iphone", 2), ("iphone", 3), ("ipad", 2)]), ("pad-only", [("ipad", 2)]),
                      ("phone-low", [("iphone", 1)])]),
        ("scales", [("all", [("universal", 1), ("universal", 2), ("universal", 3)]), ("one-three", [("universal", 1), ("universal", 3)]),
                    ("two", [("universal", 2)]), ("three", [("universal", 3)]), ("one-two", [("universal", 1), ("universal", 2)])]),
        ("idioms", [("universal-phone", [("universal", 1), ("iphone", 1)]), ("universal3-phone2", [("universal", 3), ("iphone", 2)]),
                    ("pad1-universal2", [("ipad", 1), ("universal", 2)]), ("phone", [("iphone", 2), ("iphone", 3)]),
                    ("pad", [("ipad", 1), ("ipad", 2)]), ("universal2-pad2", [("universal", 2), ("ipad", 2)])]),
        ("app", []),
    ]

    static func traits(_ idiom: String, _ scale: Int, _ subtype: Int, _ gamut: String, hosted: [String], _ graphics: String, _ fallbacks: String,
                       _ memory: Int) -> ThinningTraits {
        ThinningTraits(idiom: idiom, scale: scale, subtype: subtype, subtypeFallbacks: nil, displayGamut: gamut, hostedIdioms: hosted,
                       graphicsClass: graphics, graphicsFallbacks: fallbacks.split(separator: ":").map(String.init), memory: memory, deploymentTarget: "18.0")
    }

    /// The trait sets by their `device_traits.db` IDs, as the database spells them.
    static let traitSets: [(id: Int, traits: ThinningTraits)] = [
        (10, traits("pad", 2, 32401, "P3", hosted: [], "APPLE6", "APPLE5:APPLE4:APPLE3:APPLE3v1:APPLE2:APPLE1:GLES2,0", 16)),
        (164, traits("phone", 3, 2436, "P3", hosted: ["car"], "APPLE5", "APPLE4:APPLE3:APPLE3v1:APPLE2:APPLE1:GLES2,0", 3)),
        (132, traits("phone", 2, 1792, "P3", hosted: ["car"], "APPLE5", "APPLE4:APPLE3:APPLE3v1:APPLE2:APPLE1:GLES2,0", 4)),
        (52, traits("phone", 3, 2622, "P3", hosted: ["car"], "APPLE11", "APPLE10:APPLE9:APPLE8:APPLE7:APPLE6:APPLE5:APPLE4:APPLE3:APPLE3v1:APPLE2:APPLE1:GLES2,0", 12)),
        (11, traits("pad", 2, 2160, "sRGB", hosted: [], "APPLE6", "APPLE5:APPLE4:APPLE3v1:APPLE2:APPLE1:GLES2,0", 4)),
    ]

    static let digests: [String: [Int: String]] = [
        "thinning": [10: "0cd5c5a6634e723d1cc52e37184c66c250a8f05693178b876606b5c274b2a546", 164: "b380de50e13d3f68243b485d979d6c94c5d056b42bc781bfc4e384ca12ccead3",
                     132: "c1fcf3f8a453a445a40f22e357637983e8e7c4c762a2a22b141ea1193a30e2fb", 52: "95b86ca81bd95c358e31ba5f20889c02e2e7a2599fc36b852002fb04b30d8e2b",
                     11: "6986d9fabb9b76626628fdc36d15d621c1718b13ee85d2e8ce0181d7ced25439"],
        "scales": [10: "163bdf3aa39d54c25f94fc8fdd80f20bd02326359b654a2b9216c759618c1c18", 164: "b25db06c3fe36e1b2c21c70833ed14f9d5aefc08f9a227334454bf415d7195ae",
                   132: "ffdf4fd19044ef3170a3cd7f43e186a104aca33e3f71f0371d741280010ef7fe", 52: "50d93cc73698b8860b37fdcab03121aa5f9d5d70c9aee989f78c7332d725f4e3",
                   11: "3637a010f0040a2e909d988f9540b149ddb11471a3c3240505d72177c431a1dd"],
        "idioms": [10: "a396e775b26af65c577962a40d629df51303383ab577149e8583b89d15de0cf4", 164: "dfe8ccc71dda363e88d905d0ec989b17311062d37158249afa4691a107755835",
                   132: "514f5c73e95944fbd7cf406f64acda35efe18f3fa764cde914e929de5a4a9031", 52: "abb0379aca607aeefcd71795fe4498540a7b5328ada37ca798871d16231dda0a",
                   11: "85749146f0f8962861329690ba4fcff099e82c8c3c24451b63bfab89e6755e35"],
        "app": [10: "9488ea6859630b3edb42a7264712ad42a1f0d76659fbd070d0dc0f87659a7ea2", 164: "039e5b9d2bed1eb7d1552bb9cfc6acbb4785d4383dfd1602f1495ed2be44391a",
                132: "bd0f1bf577c0a955cfd567228f1d22bf2d444321073eefd0e04559fd594380aa", 52: "c408ee6078eaa36f9208da1186dcf91263f8cf1db7ce00b646427c054d215836",
                11: "948ff0e2dbe1d85026a76959d2ded4b4ff1d814b80ae88ea0c1f149ddd88c932"],
    ]

    static func solid(_ width: Int, _ height: Int, _ rgb: [UInt8]) -> [UInt8] {
        ImageSetTests.png(width: width, height: height, colorType: 2, rows: Array(repeating: Array((0..<width).flatMap { _ in rgb }), count: height))
    }

    static func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    /// The catalog as the experiment writes it, compiled by nomac's actool for iPhone and iPad.
    static func compile(_ name: String, _ images: Images, in directory: String) throws -> [UInt8] {
        let catalog = directory + "/Assets.xcassets"
        try FileSystem.write(json(["info": ["author": "xcode", "version": 1]]), to: catalog + "/Contents.json")
        for (set, renditions) in images {
            var entries: [[String: Any]] = []
            for (index, rendition) in renditions.enumerated() {
                let filename = "\(rendition.idiom)@\(rendition.scale)x.png"
                let scale = rendition.scale
                try FileSystem.write(Data(solid(8 * scale + index, 8 * scale, [UInt8(40 * scale), UInt8(30 * index), 200])),
                                     to: "\(catalog)/\(set).imageset/\(filename)")
                entries.append(["idiom": rendition.idiom, "scale": "\(scale)x", "filename": filename])
            }
            try FileSystem.write(json(["images": entries, "info": ["author": "xcode", "version": 1]]), to: "\(catalog)/\(set).imageset/Contents.json")
        }
        var icon: [String] = []
        if name == "app" {
            func color(_ red: String) -> [String: Any] {
                ["color": ["color-space": "srgb", "components": ["red": red, "green": "0.200", "blue": "0.400", "alpha": "1.000"]], "idiom": "universal"]
            }
            var dark = color("0.900")
            dark["appearances"] = [["appearance": "luminosity", "value": "dark"]]
            try FileSystem.write(json(["colors": [color("0.100"), dark], "info": ["author": "xcode", "version": 1]]), to: catalog + "/Accent.colorset/Contents.json")
            try FileSystem.write(Data(solid(1024, 1024, [20, 120, 220])), to: catalog + "/AppIcon.appiconset/icon.png")
            try FileSystem.write(Data(solid(1024, 1024, [10, 10, 40])), to: catalog + "/AppIcon.appiconset/dark.png")
            try FileSystem.write(json(["images": [
                ["filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
                ["appearances": [["appearance": "luminosity", "value": "dark"]], "filename": "dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
            ], "info": ["author": "xcode", "version": 1]]), to: catalog + "/AppIcon.appiconset/Contents.json")
            icon = ["--app-icon", "AppIcon", "--compress-pngs"]
        }
        _ = try Actool.run(try Actool.Options(arguments: [catalog, "--compile", directory, "--platform", "iphoneos", "--minimum-deployment-target", "18.0",
                                                          "--target-device", "iphone", "--target-device", "ipad"] + icon
                                                + ["--output-partial-info-plist", directory + "/partial.plist"]))
        return [UInt8](try Data(contentsOf: URL(fileURLWithPath: directory + "/Assets.car")))
    }

    @Test(arguments: catalogs.map(\.name))
    func thinsAsAssetutil(_ name: String) throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-thinning")
        let car = try Self.compile(name, Self.catalogs.first { $0.name == name }!.images, in: temporary.path)
        for (id, traits) in Self.traitSets {
            let thinned = try CARThinning.thin(car, for: traits, path: "Assets.car")
            #expect(SHA256.digest(thinned).map { String(format: "%02x", $0) }.joined() == Self.digests[name]![id], "trait set \(id)")
        }
    }

    @Test func refusesWhatIsNotObserved() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-thinning")
        let car = try Self.compile("scales", Self.catalogs[1].images, in: temporary.path)
        var tv = Self.traitSets[0].traits
        tv.idiom = "tv"
        #expect(throws: NomacError("thinning for idiom 'tv' is not supported yet (BACKLOG B-465)", path: "Assets.car")) {
            try CARThinning.thin(car, for: tv, path: "Assets.car")
        }
        var metal = Self.traitSets[0].traits
        metal.graphicsClass = "MTL2,2"
        #expect(throws: NomacError.self) { try CARThinning.thin(car, for: metal, path: "Assets.car") }
    }
}
