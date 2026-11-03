import Foundation
import Testing
import NomacBuildService
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport

/// Tests against Fixtures/Fixture.xcodeproj, a project file written by hand for these tests.
@Suite struct PIFGeneratorTests {
    static let fixtureProject = Bundle.module.resourcePath! + "/Fixtures/Fixture.xcodeproj"
    let projectGUID = MD5.hex("Fixture.xcodeproj")

    func objectGUID(_ id: String) -> String { projectGUID + MD5.hex(id) }

    func generate() throws -> PIFDocument {
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: Self.fixtureProject))
        return try generator.generate()
    }

    func target(_ document: PIFDocument, named name: String) -> [String: PIFValue]? {
        document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"]?.stringValue == name }?.contents.objectValue
    }

    @Test func implicitWorkspaceAndProjectIdentity() throws {
        let document = try generate()
        #expect(document.objects.map(\.type) == ["workspace", "project", "target", "target", "target"])
        let workspace = try #require(document.objects[0].contents.objectValue)
        #expect(workspace["guid"] == .string(MD5.hex("Fixture")))
        #expect(workspace["path"] == .string(FileSystem.absolute(Self.fixtureProject) + "/project.xcworkspace"))
        let project = try #require(document.objects[1].contents.objectValue)
        #expect(project["guid"] == .string(projectGUID))
        #expect(project["defaultConfigurationName"] == .string("Release"))
        #expect(project["knownRegions"] == .array([.string("en"), .string("Base")]))
        #expect(project["projectDirectory"] == .string((FileSystem.absolute(Self.fixtureProject) as NSString).deletingLastPathComponent))
    }

    @Test func missingProjectsAndWorkspacesAreNamed() throws {
        let directory = try TemporaryDirectory()
        let project = directory.path + "/Missing.xcodeproj"
        #expect(throws: NomacError("the project does not exist", path: project)) {
            try XcodeWorkspace.load(path: project)
        }
        let workspace = directory.path + "/Missing.xcworkspace"
        #expect(throws: NomacError("the workspace does not exist", path: workspace)) {
            try XcodeWorkspace.load(path: workspace)
        }
    }

    @Test func listSettingsBecomeSpaceSeparatedStrings() throws {
        let project = try #require(try generate().objects[1].contents.objectValue)
        let debug = try #require(project["buildConfigurations"]?.arrayValue?.first?.objectValue)
        #expect(debug["guid"] == .string(objectGUID("AD0000000000000000000001")))
        #expect(debug["buildSettings"]?.objectValue?["GCC_PREPROCESSOR_DEFINITIONS"] == .string("DEBUG=1 $(inherited)"))
    }

    @Test func groupTreeOmitsProductsAndRecordsVariants() throws {
        let project = try #require(try generate().objects[1].contents.objectValue)
        let root = try #require(project["groupTree"]?.objectValue)
        #expect(root["name"] == .string("Fixture"))
        let children = try #require(root["children"]?.arrayValue)
        let products = try #require(children.last?.objectValue)
        #expect(products["name"] == .string("Products"))
        #expect(products["children"] == nil)
        let app = try #require(children.first?.objectValue?["children"]?.arrayValue)
        let main = try #require(app.first?.objectValue)
        #expect(main["fileTextEncoding"] == .string("utf-8"))
        let storyboard = try #require(app.last?.objectValue)
        #expect(storyboard["type"] == .string("variantGroup"))
        let base = try #require(storyboard["children"]?.arrayValue?.first?.objectValue)
        #expect(base["regionVariantName"] == .string("Base"))
        #expect(base["path"] == .string("Base.lproj/Main.storyboard"))
    }

    @Test func productsOfTargetsAreTargetReferences() throws {
        let document = try generate()
        let app = try #require(target(document, named: "App"))
        let phases = try #require(app["buildPhases"]?.arrayValue).compactMap(\.objectValue)
        #expect(phases.map { $0["type"]?.stringValue } == [
            "com.apple.buildphase.shell-script", "com.apple.buildphase.sources", "com.apple.buildphase.frameworks",
            "com.apple.buildphase.resources", "com.apple.buildphase.copy-files",
        ])
        let kitGUID = objectGUID("A70000000000000000000002")
        let link = try #require(phases[2]["buildFiles"]?.arrayValue?.first?.objectValue)
        #expect(link["targetReference"] == .string(kitGUID))
        let embed = try #require(phases[4]["buildFiles"]?.arrayValue?.first?.objectValue)
        #expect(embed["codeSignOnCopy"] == .string("true"))
        #expect(embed["removeHeadersOnCopy"] == .string("true"))
        #expect(phases[4]["destinationSubfolder"] == .string("$(FRAMEWORKS_FOLDER_PATH)"))
        #expect(phases[0]["originalObjectID"] == .string("A80000000000000000000007"))
        #expect(phases[0]["sandboxingOverride"] == .string("basedOnBuildSetting"))
        #expect(app["dependencies"] == .array([.object(["guid": .string(kitGUID), "name": .string("Kit")])]))
        #expect(app["provisioningSourceData"]?.arrayValue?.first?.objectValue?["provisioningStyle"] == .int(1))
        #expect(app["provisioningSourceData"]?.arrayValue?.first?.objectValue?["bundleIdentifierFromInfoPlist"] == .string("$(PRODUCT_BUNDLE_IDENTIFIER)"))
        #expect(app["predominantSourceCodeLanguage"] == .string("Xcode.SourceCodeLanguage.Swift"))
    }

    @Test func buildFileSettings() throws {
        let kit = try #require(target(try generate(), named: "Kit"))
        let phases = try #require(kit["buildPhases"]?.arrayValue).compactMap(\.objectValue)
        #expect(phases[0]["buildFiles"]?.arrayValue?.first?.objectValue?["headerVisibility"] == .string("public"))
        #expect(phases[1]["buildFiles"]?.arrayValue?.first?.objectValue?["additionalCompilerOptions"] == .string("-DKIT"))
    }

    @Test func testBundlesNameTheirBaselines() throws {
        let tests = try #require(target(try generate(), named: "AppTests"))
        #expect(tests["performanceTestsBaselinesPath"] == .string(FileSystem.absolute(Self.fixtureProject) + "/xcshareddata/xcbaselines/A70000000000000000000003.xcbaseline"))
    }

    @Test func swiftBuildLoadsTheGeneratedPIF() async throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let pifPath = tmp.path + "/fixture.pif"
        try FileSystem.write(Data(try generate().serialized().utf8), to: pifPath)
        let (targets, kit) = try await SwiftBuildEngine.withWorkspace(developerDirectory: developer, pifPath: pifPath, host: .current()) { session in
            (try await session.targets(),
             try await session.exportedBuildSettings(targetGUID: objectGUID("A70000000000000000000002"), request: SettingsRequest(configuration: "Debug")))
        }
        #expect(targets.map(\.name) == ["App", "Kit", "AppTests"])
        #expect(kit["PRODUCT_NAME"] == "Kit")
        #expect(kit["WRAPPER_EXTENSION"] == "framework")
        #expect(kit["GCC_PREPROCESSOR_DEFINITIONS"] == "DEBUG=1 ")
    }
}
