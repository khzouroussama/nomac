import Foundation
import Testing
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport

/// `pif-experiments` rounds 5 and 6, on one project: the target lists the `Alpha` folder and
/// takes `Beta`'s files through an exception set; both exception sets name files that are not
/// on disk, and both folders hold localized files in regions `knownRegions` lacks.
@Suite struct SynchronizedFolderRulesTests {
    static let files: [String: String] = [
        "Alpha/a01.swift": "let a01 = 1\n",
        "Alpha/sub/ja.lproj/L.strings": "\"a\" = \"a\";\n",
        "Alpha/en.lproj/A.strings": "\"a\" = \"a\";\n",
        "Alpha/zu.lproj/A.strings": "\"a\" = \"a\";\n",
        "Alpha/af.lproj/B.strings": "\"a\" = \"a\";\n",
        "Alpha/de.lproj/C.strings": "\"a\" = \"a\";\n",
        "Alpha/mul.lproj/C.strings": "\"a\" = \"a\";\n",
        "Beta/b01.swift": "let b01 = 1\n",
        "Beta/fr.lproj/L.strings": "\"a\" = \"a\";\n",
    ]

    static let project = """
    // !$*UTF8*$!
    {
    \tarchiveVersion = 1;
    \tobjectVersion = 77;
    \tobjects = {
    \t\tA00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000001, ); path = Alpha; sourceTree = "<group>"; };
    \t\tA00000000000000000000002 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000002, ); path = Beta; sourceTree = "<group>"; };
    \t\tE00000000000000000000001 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (gone.swift, sub/gone.swift, gone.xcconfig, nosub/gone.swift, ); target = C00000000000000000000001; };
    \t\tE00000000000000000000002 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (b01.swift, gone.swift, ); target = C00000000000000000000001; };
    \t\tF00000000000000000000001 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = T.app; sourceTree = BUILT_PRODUCTS_DIR; };
    \t\tF00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000001, A00000000000000000000002, F00000000000000000000001, ); sourceTree = "<group>"; };
    \t\tC00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F00000000000000000000010; buildPhases = (B00000000000000000000001, B00000000000000000000002, ); fileSystemSynchronizedGroups = (A00000000000000000000001, ); name = T; productName = T; productReference = F00000000000000000000001; productType = "com.apple.product-type.application"; };
    \t\tB00000000000000000000001 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    \t\tB00000000000000000000002 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    \t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F00000000000000000000011; developmentRegion = en; knownRegions = (en, Base, ); mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (C00000000000000000000001, ); };
    \t\tD00000000000000000000001 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
    \t\tD00000000000000000000002 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
    \t\tF00000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000001, ); defaultConfigurationName = Debug; };
    \t\tF00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000002, ); defaultConfigurationName = Debug; };
    \t};
    \trootObject = F00000000000000000000006;
    }
    """

    let document: PIFDocument

    init() throws {
        let directory = try TemporaryDirectory()
        for (path, contents) in Self.files {
            try FileSystem.write(Data(contents.utf8), to: directory.path + "/" + path)
        }
        try FileSystem.write(Data(Self.project.utf8), to: directory.path + "/P.xcodeproj/project.pbxproj")
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj"))
        document = try generator.generate()
    }

    var project: [String: PIFValue] {
        get throws { try #require(document.objects.first { $0.type == "project" }?.contents.objectValue) }
    }

    /// Group-tree paths by GUID, with their file types.
    func files() throws -> [String: (path: String, fileType: String?)] {
        var result: [String: (path: String, fileType: String?)] = [:]
        func walk(_ node: [String: PIFValue], _ prefix: String) {
            for child in (node["children"]?.arrayValue ?? []).compactMap(\.objectValue) {
                let path = prefix + "/" + (child["path"]?.stringValue ?? "")
                result[child["guid"]?.stringValue ?? ""] = (path, child["fileType"]?.stringValue)
                walk(child, path)
            }
        }
        walk(try #require(try project["groupTree"]?.objectValue), "")
        return result
    }

    /// Variant group by variant group in group-tree order, the subfolder's first; the
    /// development region's variant and `mul` add nothing; a folder the target does not list
    /// adds its regions too.
    @Test func addsTheRegionsOfLocalizedItems() throws {
        #expect(try project["knownRegions"] == .array(["en", "Base", "ja", "zu", "af", "de", "fr"].map(PIFValue.string)))
    }

    /// A missing file an exception set names at a folder's top level is listed with the type its
    /// extension names, and joins the target when the folder is not listed; one in a subfolder is
    /// listed when the subfolder exists (loader-experiments `synchronized-missing-order`), not
    /// when it does not (round 5).
    @Test func listsMissingExceptedFiles() throws {
        let files = try files()
        let paths = Dictionary(files.values.map { ($0.path, $0.fileType) }, uniquingKeysWith: { first, _ in first })
        #expect(paths["/Alpha/gone.swift"] == "sourcecode.swift")
        #expect(paths["/Alpha/gone.xcconfig"] == "text.xcconfig")
        #expect(paths["/Beta/gone.swift"] == "sourcecode.swift")
        #expect(paths["/Alpha/sub/gone.swift"] == "sourcecode.swift")
        #expect(paths["/Alpha/nosub/gone.swift"] == nil)
        let target = try #require(document.objects.first { $0.type == "target" }?.contents.objectValue)
        let sources = try #require(target["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"]?.arrayValue)
        #expect(Set(sources.compactMap { files[$0.objectValue?["fileReference"]?.stringValue ?? ""]?.path }) == ["/Alpha/a01.swift", "/Beta/b01.swift", "/Beta/gone.swift"])
    }
}

/// loader-experiments `codegen-members` and `synchronized-headers`: a framework whose folder holds
/// intent definitions, a Core ML model, headers and sources that the exception set's attributes
/// and header lists name.
@Suite struct SynchronizedBuildFileRulesTests {
    static let files = ["Plain.intentdefinition", "Model.mlmodel", "Weak.intentdefinition", "Listed.intentdefinition", "Attribute.swift",
                        "Listed.h", "Attribute.h"]

    static let project = """
    // !$*UTF8*$!
    {
    \tarchiveVersion = 1;
    \tobjectVersion = 77;
    \tobjects = {
    \t\tA00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000001, ); path = Src; sourceTree = "<group>"; };
    \t\tE00000000000000000000001 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; attributesByRelativePath = {Model.mlmodel = (no_codegen, ); Weak.intentdefinition = (Weak, codegen, ); Attribute.swift = (Public, ); Attribute.h = (Public, ); }; publicHeaders = (Listed.intentdefinition, Listed.h, ); target = C00000000000000000000001; };
    \t\tF00000000000000000000001 = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = Kit.framework; sourceTree = BUILT_PRODUCTS_DIR; };
    \t\tF00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000001, F00000000000000000000001, ); sourceTree = "<group>"; };
    \t\tC00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F00000000000000000000010; buildPhases = (B00000000000000000000001, B00000000000000000000002, ); fileSystemSynchronizedGroups = (A00000000000000000000001, ); name = Kit; productName = Kit; productReference = F00000000000000000000001; productType = "com.apple.product-type.framework"; };
    \t\tB00000000000000000000001 = {isa = PBXHeadersBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    \t\tB00000000000000000000002 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    \t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F00000000000000000000011; developmentRegion = en; knownRegions = (en, Base, ); mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (C00000000000000000000001, ); };
    \t\tD00000000000000000000001 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
    \t\tD00000000000000000000002 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
    \t\tF00000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000001, ); defaultConfigurationName = Debug; };
    \t\tF00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000002, ); defaultConfigurationName = Debug; };
    \t};
    \trootObject = F00000000000000000000006;
    }
    """

    /// The build files of each phase by member name, without their GUIDs.
    func phases() throws -> [[String: [String: PIFValue]]] {
        let directory = try TemporaryDirectory()
        for name in Self.files {
            try FileSystem.write(Data("\n".utf8), to: directory.path + "/Src/" + name)
        }
        try FileSystem.write(Data(Self.project.utf8), to: directory.path + "/P.xcodeproj/project.pbxproj")
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj"))
        let document = try generator.generate()
        let tree = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue)
        let folder = try #require(tree["children"]?.arrayValue?.first?.objectValue)
        let names = Dictionary(uniqueKeysWithValues: (folder["children"]?.arrayValue ?? []).compactMap(\.objectValue).map {
            ($0["guid"]?.stringValue ?? "", $0["path"]?.stringValue ?? "")
        })
        let target = try #require(document.objects.first { $0.type == "target" }?.contents.objectValue)
        return (target["buildPhases"]?.arrayValue ?? []).compactMap(\.objectValue).map { phase in
            Dictionary(uniqueKeysWithValues: (phase["buildFiles"]?.arrayValue ?? []).compactMap(\.objectValue).map { file in
                (names[file["fileReference"]?.stringValue ?? ""] ?? "", file.filter { $0.key != "guid" && $0.key != "fileReference" })
            })
        }
    }

    @Test func membersCarryCodegenVisibilityAndHeaderVisibility() throws {
        let phases = try phases()
        #expect(phases.count == 2)
        #expect(phases[0] == ["Listed.h": ["headerVisibility": .string("public")], "Attribute.h": [:]])
        #expect(phases[1] == [
            "Plain.intentdefinition": ["intentsCodegenVisibility": .string("public")],
            "Model.mlmodel": ["intentsCodegenVisibility": .string("no_codegen")],
            "Weak.intentdefinition": ["shouldLinkWeakly": .bool(true)],
            "Listed.intentdefinition": ["intentsCodegenVisibility": .string("public")],
            "Attribute.swift": ["headerVisibility": .string("public")],
        ])
    }
}
