import Foundation
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport
import Testing

/// File references no group holds, as `orphan_reference_experiments.py` observed Xcode 27.0 list them.
@Suite struct RecoveredReferencesTests {
    private static func project(sources: String = "B3", resources: String = "", held: String = "", product: String = "A2", base: String = "") -> String {
        """
        // !$*UTF8*$!
        {
        archiveVersion = 1; classes = {}; objectVersion = 77;
        objects = {
        A1 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = main.swift; sourceTree = "<group>"; };
        A2 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = T.app; sourceTree = BUILT_PRODUCTS_DIR; };
        A3 = {isa = PBXFileReference; explicitFileType = undefined; includeInIndex = 0; lastKnownFileType = sourcecode.swift; path = "Sub/extra.swift"; sourceTree = "<group>"; };
        A5 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Sub/second.swift"; sourceTree = "<group>"; };
        A6 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = base.xcconfig; sourceTree = "<group>"; };
        B1 = {isa = PBXBuildFile; fileRef = A1; };
        B3 = {isa = PBXBuildFile; fileRef = A3; };
        B5 = {isa = PBXBuildFile; fileRef = A5; };
        C1 = {isa = PBXGroup; children = (A1, \(held) C2); sourceTree = "<group>"; };
        C2 = {isa = PBXGroup; children = (\(product)); name = Products; sourceTree = "<group>"; };
        D1 = {isa = PBXSourcesBuildPhase; files = (B1, \(sources)); };
        D2 = {isa = PBXResourcesBuildPhase; files = (\(resources)); };
        E1 = {isa = PBXNativeTarget; buildConfigurationList = F1; buildPhases = (D1, D2); name = T; productName = T; productReference = A2; productType = "com.apple.product-type.application"; };
        E2 = {isa = PBXProject; buildConfigurationList = F2; mainGroup = C1; productRefGroup = C2; projectDirPath = ""; projectRoot = ""; targets = (E1); };
        F1 = {isa = XCConfigurationList; buildConfigurations = (G1); defaultConfigurationName = Release; };
        F2 = {isa = XCConfigurationList; buildConfigurations = (G2); defaultConfigurationName = Release; };
        G1 = {isa = XCBuildConfiguration; \(base) buildSettings = {PRODUCT_NAME = T; }; name = Release; };
        G2 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };
        };
        rootObject = E2;
        }
        """
    }

    /// The main group's children, as (name or path, its children's paths).
    private func children(_ text: String) throws -> [(String, [String])] {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(text, to: "T.xcodeproj/project.pbxproj")
        try directory.writeExactly("let extra = 1\n", to: "Sub/extra.swift")
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/T.xcodeproj"))
        let document = try generator.generate()
        let project = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue)
        let tree = try #require(project["groupTree"]?.objectValue?["children"]?.arrayValue).compactMap(\.objectValue)
        return tree.map { child -> (String, [String]) in
            let name = child["name"]?.stringValue ?? child["path"]?.stringValue ?? ""
            let paths = (child["children"]?.arrayValue ?? []).compactMap { $0.objectValue?["path"]?.stringValue }
            return (name, paths)
        }
    }

    @Test func aFileReferenceNoGroupHoldsGoesLastInAGroupOfItsOwn() throws {
        let tree = try children(Self.project())
        #expect(tree.map(\.0) == ["main.swift", "Products", "Recovered References"])
        #expect(tree.last?.1 == ["Sub/extra.swift"])
    }

    @Test func aHeldReferenceMakesNoGroup() throws {
        #expect(try children(Self.project(held: "A3,")).map(\.0) == ["main.swift", "Sub/extra.swift", "Products"])
    }

    /// `two`, `two-phase-reversed` and `two-in-two-phases`: the phases' order, whatever the names and IDs.
    @Test func theyFollowTheBuildPhases() throws {
        #expect(try children(Self.project(sources: "B3, B5")).last?.1 == ["Sub/extra.swift", "Sub/second.swift"])
        #expect(try children(Self.project(sources: "B5, B3")).last?.1 == ["Sub/second.swift", "Sub/extra.swift"])
        #expect(try children(Self.project(sources: "B5", resources: "B3")).last?.1 == ["Sub/second.swift", "Sub/extra.swift"])
    }

    /// `orphan-xcconfig`, `orphan-source-and-xcconfig`: a base configuration too, after the phases' files.
    @Test func aBaseConfigurationIsRecoveredAfterThem() throws {
        #expect(try children(Self.project(base: "baseConfigurationReference = A6;")).last?.1 == ["Sub/extra.swift", "base.xcconfig"])
        #expect(try children(Self.project(sources: "", base: "baseConfigurationReference = A6;")).last?.1 == ["base.xcconfig"])
    }

    /// `orphan-unused`, `orphan-product`: nothing names the first, and a product is represented in its target.
    @Test func neitherAnUnusedReferenceNorAProductIs() throws {
        #expect(try children(Self.project(sources: "")).map(\.0) == ["main.swift", "Products"])
        #expect(try children(Self.project(held: "A3,", product: "")).map(\.0) == ["main.swift", "Sub/extra.swift", "Products"])
    }
}
