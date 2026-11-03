import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Complication sets as `assets-experiments complications` showed actool compiling them.
@Suite struct ComplicationSetTests {
    /// A complication set listing `roles`, holding image sets `folders`, each with one watch entry
    /// for the 38mm screen width naming `c.png`.
    static func complicationSet(_ catalog: String, _ name: String, roles: [String: String], folders: [String]) throws {
        let set = catalog + "/\(name).complicationset"
        var contents = AssetSymbolsTests.info
        contents["assets"] = roles.map { ["filename": $0.key, "idiom": "watch", "role": $0.value] }
        try AssetSymbolsTests.write(contents, to: set + "/Contents.json")
        for folder in folders {
            var images = AssetSymbolsTests.info
            images["images"] = [["filename": "c.png", "idiom": "watch", "scale": "2x", "screen-width": "<=145"]]
            try AssetSymbolsTests.write(images, to: set + "/\(folder)/Contents.json")
            try FileSystem.write(Data([0]), to: set + "/\(folder)/c.png")
        }
    }

    /// Only the set `--complication` names is compiled, its image sets named under it with their
    /// roles; in the asset symbols it is a namespace.
    @Test func onlyTheNamedSetIsCompiled() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.complicationSet(catalog, "Complication", roles: ["Circular.imageset": "circular", "Gone.imageset": "modular"], folders: ["Circular.imageset"])
        try Self.complicationSet(catalog, "Other", roles: ["Modular.imageset": "modular"], folders: ["Modular.imageset"])
        let assets = try AssetCatalog.load([catalog], complication: "Complication").assets
        #expect(assets.map(\.name) == ["Complication", "Complication/Circular"])
        #expect(assets.map(\.complicationRole) == [nil, "circular"])
        #expect(try AssetCatalog.load([catalog]).assets.isEmpty)
        #expect(try AssetSymbols.scan([catalog], targetDevices: ["watch"], complication: "Complication").map(\.fullName) == ["Complication/Circular"])
        #expect(try AssetSymbols.scan([catalog], targetDevices: ["watch"], complication: nil).isEmpty)
    }

    /// An unknown role and an image set the list leaves out get warnings; nomac stops on them.
    @Test func whatActoolWarnsAboutStops() throws {
        for (roles, folders) in [(["Odd.imageset": "bogus"], ["Odd.imageset"]), (["Circular.imageset": "circular"], ["Circular.imageset", "Unlisted.imageset"])] {
            let temporary = try TemporaryDirectory()
            let catalog = temporary.path + "/A.xcassets"
            try ColorCatalogTests.writeCatalog(catalog, [:])
            try Self.complicationSet(catalog, "Complication", roles: roles, folders: folders)
            #expect(throws: NomacError.self) { try AssetCatalog.load([catalog], complication: "Complication") }
        }
    }

    /// Each role has a size per screen width; other sizes get warnings in an order that changes.
    @Test func imagesHaveTheirRolesSize() throws {
        func image(_ width: Int, _ height: Int) -> PNGImage { PNGImage(width: width, height: height, pixels: []) }
        try ComplicationSet.checkSize(image(32, 32), role: "circular", screenWidth: "<=145", path: "c.png")
        try ComplicationSet.checkSize(image(342, 108), role: "graphic-large-rectangular", screenWidth: ">183", path: "c.png")
        #expect(throws: NomacError.self) { try ComplicationSet.checkSize(image(34, 32), role: "circular", screenWidth: "<=145", path: "c.png") }
        #expect(throws: NomacError.self) { try ComplicationSet.checkSize(image(84, 84), role: "graphic-bezel", screenWidth: "<=145", path: "c.png") }
        #expect(throws: NomacError.self) { try ComplicationSet.checkSize(image(32, 32), role: "circular", screenWidth: nil, path: "c.png") }
    }

    /// Xcode's four screen widths are watch case subtypes.
    @Test func screenWidthsAreSubtypes() {
        #expect(["<=145", ">145", ">161", ">183"].map { ImageSet.screenWidthSubtypes[$0] } == [320, 384, 340, 390])
    }
}
