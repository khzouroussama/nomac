import Foundation
import NomacCore
import NomacEnvelope
import NomacTestSupport
import Testing
@testable import NomacAssets

/// `nomac check`'s `assets:` domain on a self-written app: a catalog in a synchronized folder and
/// one in a resources phase.
@Suite struct AssetsDomainTests {
    static let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000003; mainGroup = A00000000000000000000002; projectDirPath = ""; targets = (A00000000000000000000010, ); };
        \t\tA00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000035, A00000000000000000000040, A00000000000000000000012, ); sourceTree = "<group>"; };
        \t\tA00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Debug; };
        \t\tA00000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = App; }; name = Debug; };
        \t\tA00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000003; buildPhases = (A00000000000000000000020, ); fileSystemSynchronizedGroups = (A00000000000000000000035, ); name = App; productReference = A00000000000000000000012; productType = "com.apple.product-type.application"; };
        \t\tA00000000000000000000012 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tA00000000000000000000020 = {isa = PBXResourcesBuildPhase; files = (A00000000000000000000021, ); };
        \t\tA00000000000000000000021 = {isa = PBXBuildFile; fileRef = A00000000000000000000040; };
        \t\tA00000000000000000000035 = {isa = PBXFileSystemSynchronizedRootGroup; path = Sources; sourceTree = "<group>"; };
        \t\tA00000000000000000000040 = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Other.xcassets; sourceTree = "<group>"; };
        \t};
        \trootObject = A00000000000000000000001;
        }
        """

    static let info = #""info" : { "author" : "xcode", "version" : 1 }"#

    static func status(_ report: CheckReport, _ id: String) -> CheckReport.Status? {
        report.features.first { $0.id == id }?.status
    }

    @Test func reportsCatalogFeatures() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(Self.project, to: "App.xcodeproj/project.pbxproj")
        try directory.writeExactly("{ \(Self.info) }", to: "Sources/Assets.xcassets/Contents.json")
        try directory.writeExactly("""
            { "colors" : [ { "color" : { "color-space" : "display-p3", "components" : { "red" : "0x1", "green" : "1", "blue" : "0.5", "alpha" : "1.000" } }, "idiom" : "universal",
              "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ] },
              { "color" : { "platform" : "ios", "reference" : "systemBlueColor" }, "idiom" : "iphone" } ], \(Self.info) }
            """, to: "Sources/Assets.xcassets/Accent.colorset/Contents.json")
        try directory.writeExactly("{ \(Self.info), \"properties\" : { \"provides-namespace\" : true } }", to: "Sources/Assets.xcassets/Group/Contents.json")
        try directory.writeExactly(#"{ "data" : [ { "filename" : "a.db", "idiom" : "universal" } ], "info" : { "author" : "xcode", "version" : 1 } }"#,
                                   to: "Sources/Assets.xcassets/Group/Blob.dataset/Contents.json")
        try directory.writeExactly("{ \(Self.info) }", to: "Other.xcassets/Contents.json")
        for (set, pixel) in [("Icon", [UInt8]([200, 10, 10])), ("Gray", [UInt8]([90, 90, 90]))] {
            try directory.writeExactly(#"{ "images" : [ { "filename" : "i.png", "idiom" : "universal", "scale" : "1x" }, { "idiom" : "universal", "scale" : "2x" } ], "info" : { "author" : "xcode", "version" : 1 } }"#,
                                       to: "Other.xcassets/\(set).imageset/Contents.json")
            let png = ImageSetTests.png(width: 1, height: 1, colorType: 2, rows: [pixel])
            try FileSystem.write(Data(png), to: directory.path + "/Other.xcassets/\(set).imageset/i.png")
        }
        let report = CheckReport.make(container: directory.path + "/App.xcodeproj", domains: [AssetsDomain()], options: CheckOptions())
        let expected: [String: CheckReport.Status] = [
            "assets:catalog": .verified,
            "assets:folder=namespace": .verified,
            "assets:colorset": .verified,
            "assets:colorset.color-space=display-p3": .verified,
            "assets:colorset.component=hexadecimal": .verified,
            "assets:colorset.component=integer": .verified,
            "assets:colorset.component=decimal": .verified,
            "assets:colorset.appearance=luminosity:dark": .verified,
            "assets:colorset.idiom=iphone": .verified,
            "assets:colorset.color=reference": .verified,
            "assets:dataset": .verified,
            "assets:dataset.type=unknown-extension": .verified,
            "assets:imageset": .verified,
            "assets:imageset.image=universal-1x": .verified,
            "assets:imageset.image=none": .verified,
            "assets:imageset.file=png": .verified,
            "assets:imageset.pixels=gray": .verified,
        ]
        for (id, status) in expected {
            #expect(Self.status(report, id) == status, "\(id)")
        }
        let catalogs = Set(report.features.first { $0.id == "assets:catalog" }?.uses.map(\.file) ?? [])
        #expect(catalogs.count == 2)
    }

    @Test func descriptionOnlyLeavesCatalogsUnchecked() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(Self.project, to: "App.xcodeproj/project.pbxproj")
        try directory.writeExactly("{ \(Self.info) }", to: "Other.xcassets/Contents.json")
        let scan = try AssetsDomain().scan(directory.path + "/App.xcodeproj", options: CheckOptions(descriptionOnly: true))
        #expect(scan.uses.isEmpty)
        #expect(Set(scan.unchecked.map(\.what)) == ["asset catalog contents", "asset catalogs in a synchronized folder"])
    }

    /// Every verified feature cites an experiment of `assets_experiments.py`, every unverified one
    /// a BACKLOG item.
    @Test func everyCitationResolves() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: repository.appendingPathComponent(".github/scripts/assets_experiments.py"), encoding: .utf8)
        let backlog = try String(contentsOf: repository.appendingPathComponent("docs/BACKLOG.md"), encoding: .utf8)
        for entry in AssetsEnvelope.envelope.entries.values {
            #expect(!entry.evidence.isEmpty, "\(entry.feature)")
            for evidence in entry.evidence {
                if evidence.hasPrefix("assets-experiments:") {
                    #expect(script.contains("    \"\(evidence.dropFirst("assets-experiments:".count))\": exp_"), "\(entry.feature): \(evidence)")
                } else {
                    #expect(backlog.contains("| \(evidence) |"), "\(entry.feature): \(evidence)")
                }
            }
        }
    }
}
