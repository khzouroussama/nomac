import Foundation
import Testing
import NomacCore
@testable import NomacPIF
import NomacProject
import NomacTestSupport

/// Rules confirmed by envelope-experiments (docs/formats/project-file.md), on projects written here.
@Suite struct ProjectFileRulesTests {
    /// `object-versions`: Xcode 27.0 refuses objectVersion 41, 57 and 111 with status 74.
    @Test func unreadableObjectVersionsAreRefused() throws {
        let directory = try TemporaryDirectory()
        for version in [41, 57, 111] {
            let text = LoaderRulesTests.project().replacingOccurrences(of: "objectVersion = 77;", with: "objectVersion = \(version);")
            try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": text], to: directory.path)
            #expect { try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj") } throws: { ($0 as? NomacError)?.exitStatus == 74 }
        }
    }

    /// `object-versions`, `object-versions-newest`: Xcode's outputs do not depend on the
    /// objectVersion it reads.
    @Test func everyReadableObjectVersionGivesOnePIF() throws {
        let directory = try TemporaryDirectory()
        var documents: Set<String> = []
        for version in [42, 46, 55, 63, 77, 110] {
            let text = LoaderRulesTests.project().replacingOccurrences(of: "objectVersion = 77;", with: "objectVersion = \(version);")
            try LoaderRulesTests.write(["V/P.xcodeproj/project.pbxproj": text], to: directory.path)
            documents.insert(try LoaderRulesTests.generate(directory.path + "/V/P.xcodeproj").serialized())
        }
        #expect(documents.count == 1)
    }

    /// `object-ids`: an object's GUID is the project GUID followed by the MD5 of its ID as written,
    /// for IDs that are not 24 hexadecimal digits too (`OBJ_7`, `P::App::Target`, lower case).
    @Test func objectIDsOfAnyShapeAreHashedAsWritten() throws {
        let directory = try TemporaryDirectory()
        let ids = ["C00000000000000000000001": "OBJ_7", "A00000000000000000000004": "\"P::App::Source\"", "F00000000000000000000002": "0546d1a38e13bd319cc9755b5ca7e1a0"]
        var text = LoaderRulesTests.project()
        for (hex, id) in ids { text = text.replacingOccurrences(of: hex, with: id) }
        try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": text], to: directory.path)
        let document = try LoaderRulesTests.generate(directory.path + "/P.xcodeproj")
        let project = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue)
        let projectGUID = try #require(project["guid"]?.stringValue)
        let app = try LoaderRulesTests.target(document, "App")
        #expect(app["guid"]?.stringValue == projectGUID + MD5.hex("OBJ_7"))
        let group = try #require(project["groupTree"]?.objectValue)
        #expect(group["guid"]?.stringValue == projectGUID + MD5.hex("0546d1a38e13bd319cc9755b5ca7e1a0"))
        let source = try #require(group["children"]?.arrayValue?.first?.objectValue)
        #expect(source["guid"]?.stringValue == projectGUID + MD5.hex("P::App::Source"))
    }

    /// `workspace-refs`: the files, folders and missing projects a workspace lists besides its
    /// projects leave no trace in the PIF.
    @Test func aWorkspaceLeavesOtherItemsAndMissingProjectsOut() throws {
        let directory = try TemporaryDirectory()
        try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": LoaderRulesTests.project(), "Podfile": "", "Docs/Guide.md": ""], to: directory.path)
        var documents: [String] = []
        for locations in [["group:P.xcodeproj"],
                          ["group:Pods/Pods.xcodeproj", "group:P.xcodeproj", "group:Podfile", "group:Docs", "container:Missing.txt", "group:Gone/Gone.xcodeproj"]] {
            let references = locations.map { "<FileRef location = \"\($0)\"></FileRef>" }.joined()
            try LoaderRulesTests.write(["W.xcworkspace/contents.xcworkspacedata": "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Workspace version = \"1.0\">\(references)</Workspace>"],
                                       to: directory.path)
            documents.append(try LoaderRulesTests.generate(directory.path + "/W.xcworkspace").serialized())
        }
        #expect(documents[0] == documents[1])
    }

    /// `survey-shapes`: a build file's ASSET_TAGS are the PIF's `assetTags`, sorted, in any phase;
    /// an empty list gives none.
    @Test func assetTagsAreSorted() throws {
        let directory = try TemporaryDirectory()
        let text = LoaderRulesTests.project().replacingOccurrences(
            of: "A00000000000000000000003 = {isa = PBXBuildFile; fileRef = A00000000000000000000004; };",
            with: "A00000000000000000000003 = {isa = PBXBuildFile; fileRef = A00000000000000000000004; settings = {ASSET_TAGS = (Zeta, Alpha, ); }; };")
        try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": text], to: directory.path)
        let app = try LoaderRulesTests.target(try LoaderRulesTests.generate(directory.path + "/P.xcodeproj"), "App")
        let file = try #require(app["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"]?.arrayValue?.first?.objectValue)
        #expect(file["assetTags"] == .array([.string("Alpha"), .string("Zeta")]))
    }

    /// `variant-groups`: a variant group's children not directly in a `.lproj` folder are lifted
    /// out, before the group, each with a build file of its own before the group's; a group left
    /// without children goes; the regions of the children that stay join `knownRegions` when it
    /// lacks them in any case.
    @Test func variantGroupChildrenOutsideLprojAreLifted() throws {
        let directory = try TemporaryDirectory()
        let objects = """
            V1 = {isa = PBXVariantGroup; children = (C1, C2, C3, ); name = Extra.strings; sourceTree = "<group>"; };
            C1 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = en.lproj/Extra.strings; sourceTree = "<group>"; };
            C2 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = de; path = Extra/de.strings; sourceTree = "<group>"; };
            C3 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = FR; path = FR.lproj/Extra.strings; sourceTree = "<group>"; };
            V2 = {isa = PBXVariantGroup; children = (C4, ); name = Other.strings; sourceTree = "<group>"; };
            C4 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = nl; path = nl.LPROJ/Other.strings; sourceTree = "<group>"; };
            V3 = {isa = PBXVariantGroup; children = (C5, ); name = More.strings; sourceTree = "<group>"; };
            C5 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = it; path = it.lproj/More.strings; sourceTree = "<group>"; };
            B1 = {isa = PBXBuildFile; fileRef = V1; };
            B2 = {isa = PBXBuildFile; fileRef = V2; };
            R1 = {isa = PBXResourcesBuildPhase; files = (B1, B2, ); };
            """
        var text = LoaderRulesTests.project(objects: objects, groupChildren: "V1, V2, V3, ")
        text = text.replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (F00000000000000000000004, R1, );")
        text = text.replacingOccurrences(of: "mainGroup = F00000000000000000000002;", with: "knownRegions = (en, fr, ); mainGroup = F00000000000000000000002;")
        try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": text], to: directory.path)
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj"))
        let document = try generator.generate()
        let project = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue)
        let projectGUID = try #require(project["guid"]?.stringValue)
        let tree = try #require(project["groupTree"]?.objectValue?["children"]?.arrayValue).compactMap(\.objectValue)
        #expect(tree.dropFirst().map { $0["type"]?.stringValue ?? "" } == ["file", "variantGroup", "file", "variantGroup", "group"])
        #expect(tree[1]["path"] == .string("Extra/de.strings"))
        #expect(tree[2]["children"]?.arrayValue?.compactMap { $0.objectValue?["regionVariantName"]?.stringValue } == ["en", "FR"])
        #expect(tree[3]["path"] == .string("nl.LPROJ/Other.strings"))
        #expect(project["knownRegions"] == .array(["en", "fr", "it"].map(PIFValue.string)))
        let app = try LoaderRulesTests.target(document, "App")
        let resources = try #require(app["buildPhases"]?.arrayValue?.last?.objectValue?["buildFiles"]?.arrayValue).compactMap(\.objectValue)
        #expect(resources.map { $0["fileReference"]?.stringValue } == ["C2", "V1", "C4"].map { projectGUID + MD5.hex($0) })
        #expect(resources[1]["guid"] == .string(projectGUID + MD5.hex("B1")))
        #expect(generator.randomBuildFileReferences == Set(["C2", "C4"].map { projectGUID + MD5.hex($0) }))
    }

    /// `dst-subfolders`: the `dstSubfolder` names Xcode 26 and later write, and xcodebuild's
    /// abort (134) on a name it does not know.
    @Test func copyFilesDestinationsByName() throws {
        let directory = try TemporaryDirectory()
        for (name, destination) in [("PlugIns", "$(PLUGINS_FOLDER_PATH)"), ("Product", "<builtProductsDir>"), ("None", "")] {
            let objects = "P1 = {isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = \"\"; dstSubfolder = \(name); files = (); runOnlyForDeploymentPostprocessing = 0; };"
            var text = LoaderRulesTests.project(objects: objects)
            text = text.replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (F00000000000000000000004, P1, );")
            try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": text], to: directory.path)
            let app = try LoaderRulesTests.target(try LoaderRulesTests.generate(directory.path + "/P.xcodeproj"), "App")
            #expect(app["buildPhases"]?.arrayValue?.last?.objectValue?["destinationSubfolder"] == .string(destination))
        }
        let objects = "P1 = {isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = \"\"; dstSubfolder = XPCServices; files = (); runOnlyForDeploymentPostprocessing = 0; };"
        try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": LoaderRulesTests.project(objects: objects).replacingOccurrences(
            of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (F00000000000000000000004, P1, );")], to: directory.path)
        #expect { try LoaderRulesTests.generate(directory.path + "/P.xcodeproj") } throws: { ($0 as? NomacError)?.exitStatus == 134 }
    }

    /// `survey-shapes-4`: the singular `platformFilter` counts for `ios` and `maccatalyst` only;
    /// the list form counts for every name.
    @Test func singularPlatformFiltersOtherThanIOSAreDropped() {
        #expect(ProjectGenerator.filterNames(nil, "maccatalyst") == ["maccatalyst"])
        #expect(ProjectGenerator.filterNames(nil, "ios") == ["ios"])
        for name in ["macos", "tvos", "watchos", "xros", "driverkit"] {
            #expect(ProjectGenerator.filterNames(nil, name) == nil)
            #expect(ProjectGenerator.filterNames([name], nil) == [name])
        }
    }
}
