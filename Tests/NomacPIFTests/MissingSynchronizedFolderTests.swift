import Foundation
import Testing
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport

/// loader-experiments `synchronized-missing`, written again here: synchronized folders that are
/// not on disk (`Gone`, which no target lists, as home-assistant's `Sources/Shared/Iconic`, and
/// `Listed`, whose exception set names a top-level and a nested file) and one whose path is a
/// file (`File.swift`), next to `Present`.
@Suite struct MissingSynchronizedFolderTests {
    static let project = """
    // !$*UTF8*$!
    {
    \tarchiveVersion = 1;
    \tobjectVersion = 77;
    \tobjects = {
    \t\tS00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; path = Gone; sourceTree = "<group>"; };
    \t\tS00000000000000000000002 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (S00000000000000000000012, ); path = Listed; sourceTree = "<group>"; };
    \t\tS00000000000000000000003 = {isa = PBXFileSystemSynchronizedRootGroup; path = File.swift; sourceTree = "<group>"; };
    \t\tS00000000000000000000005 = {isa = PBXFileSystemSynchronizedRootGroup; path = Present; sourceTree = "<group>"; };
    \t\tS00000000000000000000012 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (Info.plist, Sub/Deep.swift, ); target = C00000000000000000000001; };
    \t\tF00000000000000000000001 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
    \t\tF00000000000000000000002 = {isa = PBXGroup; children = (S00000000000000000000001, S00000000000000000000002, S00000000000000000000003, S00000000000000000000005, F00000000000000000000001, ); sourceTree = "<group>"; };
    \t\tC00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F00000000000000000000010; buildPhases = (B00000000000000000000001, B00000000000000000000002, ); fileSystemSynchronizedGroups = (S00000000000000000000002, S00000000000000000000003, S00000000000000000000005, ); name = App; productName = App; productReference = F00000000000000000000001; productType = "com.apple.product-type.application"; };
    \t\tB00000000000000000000001 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    \t\tB00000000000000000000002 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    \t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F00000000000000000000011; developmentRegion = en; knownRegions = (en, Base, ); mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (C00000000000000000000001, ); };
    \t\tD00000000000000000000001 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_STYLE = Automatic; PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
    \t\tD00000000000000000000002 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
    \t\tF00000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000001, ); defaultConfigurationName = Debug; };
    \t\tF00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000002, ); defaultConfigurationName = Debug; };
    \t};
    \trootObject = F00000000000000000000006;
    }
    """

    /// Xcode reads such a folder as an empty one: a group with no children but the top-level
    /// paths its exception sets name, in the group tree with the GUID of the folder's object, and
    /// no build files.
    @Test func aFolderThatIsNotOnDiskIsEmpty() throws {
        let directory = try TemporaryDirectory()
        try FileSystem.write(Data("let file = 1\n".utf8), to: directory.path + "/File.swift")
        try FileSystem.write(Data("let a = 1\n".utf8), to: directory.path + "/Present/a.swift")
        try FileSystem.write(Data(Self.project.utf8), to: directory.path + "/P.xcodeproj/project.pbxproj")
        let workspace = try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj")
        var generator = PIFGenerator(workspace: workspace)
        let document = try generator.generate()
        let project = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue)
        let folders = try #require(project["groupTree"]?.objectValue?["children"]?.arrayValue).compactMap(\.objectValue)
        let projectGUID = PIFIdentifiers.projectGUID(projectPath: workspace.projects[0].path, workspace: workspace)
        #expect(folders[0] == ["guid": .string(PIFIdentifiers.objectGUID(projectGUID: projectGUID, objectID: "S00000000000000000000001")),
                               "name": .string("Gone"), "path": .string("Gone"), "sourceTree": .string("<group>"), "type": .string("group")])
        #expect(folders[1]["children"]?.arrayValue?.compactMap { $0.objectValue?["path"]?.stringValue } == ["Info.plist"])
        #expect(folders[2]["name"] == .string("File.swift") && folders[2]["children"] == nil)
        let target = try #require(document.objects.first { $0.type == "target" }?.contents.objectValue)
        let phases = try #require(target["buildPhases"]?.arrayValue).compactMap { $0.objectValue?["buildFiles"]?.arrayValue?.count }
        #expect(phases == [1, 0])
    }
}
