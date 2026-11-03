import Foundation
import Testing
import NomacBuildService
import NomacCore
import NomacProject
import NomacTestSupport
@testable import NomacInspect

/// loader-experiments `unicode-nfc` and `unicode-nfd`, written again here: a project `Café`
/// with the apps `Ünï App`, which the shared scheme `Schémé` launches through a container
/// written in the other form, and `Ötro`, which gets an autocreated scheme; its configurations
/// are Debug and `Bêta`. What xcodebuild did with each name in each form is the expectation.
@Suite struct UnicodeSchemesTests {
    static let forms = [false, true]

    static func pbxproj(_ a: (String) -> String) -> String {
        func q(_ text: String) -> String { "\"\(a(text))\"" }
        func target(_ index: Int, _ name: String) -> String {
            """
            \t\tR0000000000000000000000\(index) = {isa = PBXFileReference; explicitFileType = wrapper.application; path = \(q(name + ".app")); sourceTree = BUILT_PRODUCTS_DIR; };
            \t\tC0000000000000000000000\(index) = {isa = PBXNativeTarget; buildConfigurationList = L0000000000000000000000\(index); buildPhases = (); name = \(q(name)); productName = \(q(name)); productReference = R0000000000000000000000\(index); productType = "com.apple.product-type.application"; };
            \t\tL0000000000000000000000\(index) = {isa = XCConfigurationList; buildConfigurations = (D0000000000000000000000\(index), E0000000000000000000000\(index), ); defaultConfigurationName = Debug; };
            \t\tD0000000000000000000000\(index) = {isa = XCBuildConfiguration; baseConfigurationReference = X00000000000000000000001; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
            \t\tE0000000000000000000000\(index) = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = \(q("Bêta")); };

            """
        }
        return """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tX00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = \(q("Ödd.xcconfig")); sourceTree = "<group>"; };
        \t\tF00000000000000000000002 = {isa = PBXGroup; children = (X00000000000000000000001, R00000000000000000000001, R00000000000000000000002, ); sourceTree = "<group>"; };
        \(target(1, "Ünï App"))\(target(2, "Ötro"))\
        \t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F000000000000000000000PL; mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (C00000000000000000000001, C00000000000000000000002, ); };
        \t\tF000000000000000000000PL = {isa = XCConfigurationList; buildConfigurations = (F000000000000000000000PD, F000000000000000000000PB, ); defaultConfigurationName = Debug; };
        \t\tF000000000000000000000PD = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
        \t\tF000000000000000000000PB = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = \(q("Bêta")); };
        \t};
        \trootObject = F00000000000000000000006;
        }

        """
    }

    /// Writes the project in `decomposed` form or not under a temporary directory and runs
    /// `body` with an inspector of it, the form of the project file, the other form and the
    /// directory.
    static func withInspector(decomposed: Bool, _ body: (BuildSettingsInspector, (String) -> String, (String) -> String, String) async throws -> Void) async throws {
        let nfd: (String) -> String = { $0.decomposedStringWithCanonicalMapping }
        let nfc: (String) -> String = { $0.precomposedStringWithCanonicalMapping }
        let (a, odd) = decomposed ? (nfd, nfc) : (nfc, nfd)
        let directory = try TemporaryDirectory()
        let container = directory.path + "/app/" + a("Café.xcodeproj")
        try directory.writeExactly(pbxproj(a), to: "app/" + a("Café.xcodeproj") + "/project.pbxproj")
        try directory.writeExactly(SchemeFixtures.scheme(build: [("C00000000000000000000001", "container:" + odd("Café.xcodeproj"), true)]),
                                   to: "app/" + a("Café.xcodeproj") + "/xcshareddata/xcschemes/" + a("Schémé") + ".xcscheme")
        try directory.writeExactly("FROM_ODD_XCCONFIG = 1\n", to: "app/" + odd("Ödd.xcconfig"))
        try await SchemeFixtures.withInspector(of: try XcodeWorkspace.load(path: container), in: directory.path) { inspector in
            try await body(inspector, a, odd, directory.path)
        }
    }

    static func status(_ work: () async throws -> Void) async -> Int32? {
        do {
            try await work()
            return nil
        } catch {
            return (error as? NomacError)?.exitStatus
        }
    }

    /// A shared scheme is found by its name in either form, and its container written in the
    /// other form names the project; the project's name and DerivedData folder are decomposed,
    /// the folder named by the decomposed path's hash. The xcconfig the project file names in
    /// one form is read from the file on disk in the other.
    @Test(arguments: forms) func sharedSchemeFindsItsContainer(decomposed: Bool) async throws {
        try await Self.withInspector(decomposed: decomposed) { inspector, a, odd, directory in
            for name in [a("Schémé"), odd("Schémé")] {
                let blocks = try await inspector.blocks(.init(selection: .scheme(name), destination: "generic/platform=iOS"))
                #expect(blocks.map(\.target) == [a("Ünï App")])
                let settings = try #require(blocks.first?.dictionary)
                #expect(settings["PROJECT_NAME"]?.isIdentical(to: "Café".decomposed) == true)
                let path = (FileSystem.absolute(directory) + "/app/Café.xcodeproj").decomposed
                let folder = DerivedData.defaultRoot(home: HostIdentity.current().homeDirectory) + "/" + "Café".decomposed + "-" + DerivedData.folderHash(path)
                #expect(settings["BUILD_DIR"]?.isIdentical(to: folder + "/Build/Products") == true)
                #expect(settings["FROM_ODD_XCCONFIG"] == "1")
            }
        }
    }

    /// An autocreated scheme and a target are found by their names' bytes only (65 otherwise);
    /// without a scheme, a configuration the project lacks in these bytes gives way to the default.
    @Test(arguments: forms) func namesMatchByteForByte(decomposed: Bool) async throws {
        try await Self.withInspector(decomposed: decomposed) { inspector, a, odd, _ in
            let autocreated = try await inspector.blocks(.init(selection: .scheme(a("Ötro")), destination: "generic/platform=iOS"))
            #expect(autocreated.map(\.target) == [a("Ötro")])
            #expect(await Self.status { _ = try await inspector.blocks(.init(selection: .scheme(odd("Ötro")), destination: "generic/platform=iOS")) } == 65)
            #expect(await Self.status { _ = try await inspector.blocks(.init(selection: .targets([odd("Ünï App")]))) } == 65)

            let own = BuildSettingsInspector.Invocation(selection: .targets([a("Ünï App")]), configuration: a("Bêta"))
            #expect(inspector.unknownConfiguration(own) == nil)
            let ownBlocks = try await inspector.blocks(own)
            // Swift Build keeps one spelling of canonically equivalent strings per process, so
            // the other form's test may have chosen the spelling.
            #expect(ownBlocks.first?.dictionary["CONFIGURATION"] == a("Bêta"))
            let otherForm = BuildSettingsInspector.Invocation(selection: .targets([a("Ünï App")]), configuration: odd("Bêta"))
            #expect(inspector.unknownConfiguration(otherForm)?.isIdentical(to: odd("Bêta")) == true)
            let otherBlocks = try await inspector.blocks(otherForm)
            #expect(otherBlocks.first?.dictionary["CONFIGURATION"] == "Debug")
        }
    }
}

/// loader-experiments `derived-data-names`: the DerivedData folder Xcode 27.0 chose for each
/// project or workspace name.
@Suite struct DerivedDataNameTests {
    @Test func whitespaceRunsBecomeOneUnderscore() {
        let observed: [(String, String)] = [
            ("App 2", "App_2"), ("Two  Spaces", "Two_Spaces"), (" Leading", "_Leading"), ("Trailing ", "Trailing_"),
            ("Tab\tName", "Tab_Name"), ("New\nLine", "New_Line"), ("Return\rName", "Return_Name"), ("Space \t Tab", "Space_Tab"),
            ("Under_ Space", "Under__Space"), ("All Projects", "All_Projects"),
            ("VTab\u{0B}Name", "VTab\u{0B}Name"), ("Feed\u{0C}Name", "Feed\u{0C}Name"), ("Next\u{85}Line", "Next\u{85}Line"),
            ("No\u{A0}Break", "No\u{A0}Break"), ("Em\u{2003}Space", "Em\u{2003}Space"), ("Ideo\u{3000}Space", "Ideo\u{3000}Space"),
            ("A+B", "A+B"), ("A&B", "A&B"), ("Colon:Name", "Colon:Name"), ("Quote'Name", "Quote'Name"), ("日本", "日本"),
        ]
        for (name, folder) in observed {
            #expect(DerivedData.folderName(name).isIdentical(to: folder), "\(name.debugDescription)")
        }
    }

    /// `Ünï Kit.xcodeproj`, written in NFC on disk: the folder name and the hashed path are
    /// decomposed (xcodebuild's BUILD_DIR there).
    @Test func namesAndPathsAreDecomposed() {
        let path = "/tmp/nomac-dd/\u{DC}n\u{EF} Kit.xcodeproj"
        let locations = DerivedData.locations(name: "\u{DC}n\u{EF} Kit", containerPath: path, home: "/Users/tester", customRoot: nil)
        let observed = "/Users/tester/Library/Developer/Xcode/DerivedData/U\u{308}ni\u{308}_Kit-cltxrzbpzzgpseewxrqjpnjfmwdx/Build/Products"
        #expect(locations.buildProductsPath.isIdentical(to: observed))
    }
}
