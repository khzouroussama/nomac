import Foundation
import Testing
import NomacBuildService
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport

/// Synchronized folders (docs/formats/pif.md), on a project written by the test: an app target
/// that lists the `App` folder and takes `Shared.swift` from the `Shared` folder through an
/// exception set, and a framework target that lists the `Kit` and `Shared` folders.
@Suite struct SynchronizedFolderTests {
    static let files: [String: String] = [
        "App/App.swift": "@main struct App {}\n",
        "App/App.entitlements": "<?xml version=\"1.0\"?>\n<plist version=\"1.0\"><dict/></plist>\n",
        "App/Views/ContentView.swift": "struct ContentView {}\n",
        "App/Views/ContentView+Preview.swift": "extension ContentView {}\n",
        "App/Info.plist": "<?xml version=\"1.0\"?>\n<plist version=\"1.0\"><dict><key>UILaunchScreen</key><dict/></dict></plist>\n",
        "App/Assets.xcassets/Contents.json": "{}\n",
        "App/Base.lproj/Main.storyboard": "<?xml version=\"1.0\"?><document/>\n",
        "App/en.lproj/Main.strings": "\"a\" = \"a\";\n",
        "App/de.lproj/Main.strings": "\"a\" = \"a\";\n",
        "App/script.js": "var a = 1;\n",
        "App/.DS_Store": "",
        "App/Config/App.xcconfig": "// App settings\nINFOPLIST_FILE = App/Info.plist\nGENERATE_INFOPLIST_FILE = YES\n#include? \"Missing.xcconfig\"\nSWIFT_VERSION[sdk=iphoneos*] = 6.0\n",
        "Kit/Kit.h": "#import <Foundation/Foundation.h>\n",
        "Kit/Internal.h": "\n",
        "Kit/Kit.swift": "public struct Kit {}\n",
        "Shared/Shared.swift": "struct Shared {}\n",
    ]

    static let project = """
    // !$*UTF8*$!
    {
    	archiveVersion = 1;
    	classes = {
    	};
    	objectVersion = 77;
    	objects = {
    		A00000000000000000000001 /* App */ = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000001 /* Exceptions for "App" folder in "App" target */, ); path = App; sourceTree = "<group>"; };
    		A00000000000000000000002 /* Kit */ = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000003 /* Exceptions for "Kit" folder in "Kit" target */, ); path = Kit; sourceTree = "<group>"; };
    		A00000000000000000000003 /* Shared */ = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000002 /* Exceptions for "Shared" folder in "App" target */, ); path = Shared; sourceTree = "<group>"; };
    		E00000000000000000000001 /* Exceptions for "App" folder in "App" target */ = {
    			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
    			membershipExceptions = (
    				Info.plist,
    			);
    			target = C00000000000000000000001 /* App */;
    		};
    		E00000000000000000000002 /* Exceptions for "Shared" folder in "App" target */ = {
    			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
    			membershipExceptions = (
    				Shared.swift,
    			);
    			target = C00000000000000000000001 /* App */;
    		};
    		E00000000000000000000003 /* Exceptions for "Kit" folder in "Kit" target */ = {
    			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
    			additionalCompilerFlagsByRelativePath = {
    				Kit.swift = "-DKIT";
    			};
    			publicHeaders = (
    				Kit.h,
    			);
    			target = C00000000000000000000002 /* Kit */;
    		};
    		F00000000000000000000001 /* App.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
    		F00000000000000000000002 /* Kit.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = Kit.framework; sourceTree = BUILT_PRODUCTS_DIR; };
    		F00000000000000000000003 = {
    			isa = PBXGroup;
    			children = (
    				A00000000000000000000001 /* App */,
    				A00000000000000000000002 /* Kit */,
    				A00000000000000000000003 /* Shared */,
    				F00000000000000000000004 /* Products */,
    			);
    			sourceTree = "<group>";
    		};
    		F00000000000000000000004 /* Products */ = {
    			isa = PBXGroup;
    			children = (
    				F00000000000000000000001 /* App.app */,
    				F00000000000000000000002 /* Kit.framework */,
    			);
    			name = Products;
    			sourceTree = "<group>";
    		};
    		C00000000000000000000001 /* App */ = {
    			isa = PBXNativeTarget;
    			buildConfigurationList = F00000000000000000000010;
    			buildPhases = (
    				B00000000000000000000001 /* Sources */,
    				B00000000000000000000002 /* Frameworks */,
    				B00000000000000000000003 /* Resources */,
    			);
    			buildRules = (
    			);
    			dependencies = (
    			);
    			fileSystemSynchronizedGroups = (
    				A00000000000000000000001 /* App */,
    			);
    			name = App;
    			productName = App;
    			productReference = F00000000000000000000001 /* App.app */;
    			productType = "com.apple.product-type.application";
    		};
    		C00000000000000000000002 /* Kit */ = {
    			isa = PBXNativeTarget;
    			buildConfigurationList = F00000000000000000000011;
    			buildPhases = (
    				B00000000000000000000004 /* Headers */,
    				B00000000000000000000005 /* Sources */,
    			);
    			buildRules = (
    			);
    			dependencies = (
    			);
    			fileSystemSynchronizedGroups = (
    				A00000000000000000000002 /* Kit */,
    				A00000000000000000000003 /* Shared */,
    			);
    			name = Kit;
    			productName = Kit;
    			productReference = F00000000000000000000002 /* Kit.framework */;
    			productType = "com.apple.product-type.framework";
    		};
    		F00000000000000000000005 /* Project object */ = {
    			isa = PBXProject;
    			attributes = {
    				LastUpgradeCheck = 2700;
    			};
    			buildConfigurationList = F00000000000000000000012;
    			developmentRegion = en;
    			hasScannedForEncodings = 0;
    			knownRegions = (
    				en,
    				Base,
    				de,
    			);
    			mainGroup = F00000000000000000000003;
    			preferredProjectObjectVersion = 77;
    			productRefGroup = F00000000000000000000004 /* Products */;
    			projectDirPath = "";
    			projectRoot = "";
    			targets = (
    				C00000000000000000000001 /* App */,
    				C00000000000000000000002 /* Kit */,
    			);
    		};
    		B00000000000000000000001 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    		B00000000000000000000002 /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    		B00000000000000000000003 /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    		B00000000000000000000004 /* Headers */ = {isa = PBXHeadersBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    		B00000000000000000000005 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    		D00000000000000000000001 /* Debug */ = {
    			isa = XCBuildConfiguration;
    			baseConfigurationReferenceAnchor = A00000000000000000000001 /* App */;
    			baseConfigurationReferenceRelativePath = Config/App.xcconfig;
    			buildSettings = {
    				PRODUCT_BUNDLE_IDENTIFIER = org.nomac.synced;
    				PRODUCT_NAME = "$(TARGET_NAME)";
    			};
    			name = Debug;
    		};
    		D00000000000000000000002 /* Debug */ = {
    			isa = XCBuildConfiguration;
    			buildSettings = {
    				PRODUCT_NAME = "$(TARGET_NAME)";
    			};
    			name = Debug;
    		};
    		D00000000000000000000003 /* Debug */ = {
    			isa = XCBuildConfiguration;
    			buildSettings = {
    				SDKROOT = iphoneos;
    			};
    			name = Debug;
    		};
    		F00000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000001 /* Debug */, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
    		F00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000002 /* Debug */, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
    		F00000000000000000000012 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000003 /* Debug */, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
    	};
    	rootObject = F00000000000000000000005 /* Project object */;
    }
    """

    let directory: TemporaryDirectory
    let document: PIFDocument
    let projectGUID = MD5.hex("Synced.xcodeproj")

    init() throws {
        directory = try TemporaryDirectory()
        for (path, contents) in Self.files {
            try FileSystem.write(Data(contents.utf8), to: directory.path + "/" + path)
        }
        try FileSystem.write(Data(Self.project.utf8), to: directory.path + "/Synced.xcodeproj/project.pbxproj")
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/Synced.xcodeproj"))
        document = try generator.generate()
    }

    var groupTree: [String: PIFValue] {
        get throws { try #require(document.objects[1].contents.objectValue?["groupTree"]?.objectValue) }
    }

    func children(_ node: [String: PIFValue]?) -> [[String: PIFValue]] {
        (node?["children"]?.arrayValue ?? []).compactMap(\.objectValue)
    }

    func label(_ node: [String: PIFValue]) -> String {
        node["type"]?.stringValue == "variantGroup" ? "variant:" + (node["name"]?.stringValue ?? "") : (node["path"]?.stringValue ?? "")
    }

    /// Group-tree paths by GUID.
    func paths() throws -> [String: String] {
        var result: [String: String] = [:]
        func walk(_ node: [String: PIFValue], _ prefix: String) {
            for child in children(node) {
                let path = prefix.isEmpty ? label(child) : prefix + "/" + label(child)
                result[child["guid"]?.stringValue ?? ""] = path
                walk(child, child["type"]?.stringValue == "variantGroup" ? prefix : path)
            }
        }
        walk(try groupTree, "")
        return result
    }

    func target(_ name: String) throws -> [String: PIFValue] {
        try #require(document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"]?.stringValue == name }?.contents.objectValue)
    }

    func phase(_ target: [String: PIFValue], _ type: String) throws -> [[String: PIFValue]] {
        let phases = (target["buildPhases"]?.arrayValue ?? []).compactMap(\.objectValue)
        let phase = try #require(phases.first { $0["type"]?.stringValue == "com.apple.buildphase.\(type)" })
        return (phase["buildFiles"]?.arrayValue ?? []).compactMap(\.objectValue)
    }

    @Test func folderBecomesAGroupWithTheItemsOnDisk() throws {
        let app = try #require(children(try groupTree).first { $0["path"] == .string("App") })
        #expect(app["guid"] == .string(projectGUID + MD5.hex("A00000000000000000000001")))
        #expect(app["name"] == .string("App"))
        // Groups first; then files and variant groups, by name without extension first; hidden
        // files skipped.
        #expect(children(app).map(label) == ["Config", "Views", "App.entitlements", "App.swift", "Assets.xcassets", "Info.plist", "variant:Main.storyboard", "script.js"])
        let views = try #require(children(app).first { $0["path"] == .string("Views") })
        #expect(views["name"] == .string("Views"))
        #expect(children(views).map(label) == ["ContentView.swift", "ContentView+Preview.swift"])
        let types = Dictionary(uniqueKeysWithValues: children(app).map { (label($0), $0["fileType"]?.stringValue) })
        #expect(types["Assets.xcassets"] == "folder.assetcatalog")
        #expect(types["Info.plist"] == "text.plist.xml")
        #expect(types["App.entitlements"] == "text.plist.entitlements")
        #expect(app["children"]?.arrayValue?.allSatisfy { $0.objectValue?["guid"]?.stringValue?.count == 44 } == true)
    }

    @Test func localizedFilesBecomeVariantGroups() throws {
        let app = try #require(children(try groupTree).first { $0["path"] == .string("App") })
        let main = try #require(children(app).first { $0["type"] == .string("variantGroup") })
        #expect(main["name"] == .string("Main.storyboard"))
        #expect(main["path"] == .string(""))
        // Base, then the development region, then the others in order, as Xcode 27.0's -dumpPIF of
        // this project lists them (`pif-experiments` variants-order).
        #expect(children(main).map { $0["path"]?.stringValue } == ["Base.lproj/Main.storyboard", "en.lproj/Main.strings", "de.lproj/Main.strings"])
        #expect(children(main).map { $0["regionVariantName"]?.stringValue } == ["Base", "en", "de"])
    }

    @Test func membersJoinTheirTargetsPhases() throws {
        let paths = try paths()
        let app = try target("App")
        // The App folder's members minus its exception (Info.plist), plus Shared.swift, which
        // the Shared folder's exception set adds for a target that does not list the folder,
        // placed as Xcode 27.0's -dumpPIF of this project places it.
        #expect(try phase(app, "sources").map { paths[$0["fileReference"]?.stringValue ?? ""] } == ["App/Views/ContentView.swift", "App/Views/ContentView+Preview.swift", "Shared/Shared.swift", "App/App.swift"])
        #expect(try phase(app, "resources").map { paths[$0["fileReference"]?.stringValue ?? ""] } == ["App/Config/App.xcconfig", "App/Assets.xcassets", "App/variant:Main.storyboard", "App/script.js"])
        #expect(try phase(app, "frameworks").isEmpty)
        let kit = try target("Kit")
        let headers = try phase(kit, "headers")
        #expect(headers.map { paths[$0["fileReference"]?.stringValue ?? ""] } == ["Kit/Internal.h", "Kit/Kit.h"])
        #expect(headers.map { $0["headerVisibility"]?.stringValue } == [nil, "public"])
        let sources = try phase(kit, "sources")
        #expect(sources.map { paths[$0["fileReference"]?.stringValue ?? ""] } == ["Shared/Shared.swift", "Kit/Kit.swift"])
        #expect(sources.last?["additionalCompilerOptions"] == .string("-DKIT"))
        // A member has its own build-file GUID in each target.
        #expect(try phase(app, "sources")[2]["guid"] != sources.first?["guid"])
    }

    @Test func anchoredXcconfigAndGeneratedInfoPlist() throws {
        let paths = try paths()
        let app = try target("App")
        let configuration = try #require(app["buildConfigurations"]?.arrayValue?.first?.objectValue)
        #expect(paths[configuration["baseConfigurationFileReference"]?.stringValue ?? ""] == "App/Config/App.xcconfig")
        // INFOPLIST_FILE comes from the xcconfig; the file has no CFBundleIdentifier and the
        // Info.plist is generated.
        #expect(app["provisioningSourceData"]?.arrayValue?.first?.objectValue?["bundleIdentifierFromInfoPlist"] == .string("$(PRODUCT_BUNDLE_IDENTIFIER)"))
        #expect(app["predominantSourceCodeLanguage"] == .string("Xcode.SourceCodeLanguage.Swift"))
    }

    @Test func guidsAreStable() throws {
        var again = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/Synced.xcodeproj"))
        #expect(try again.generate().serialized() == document.serialized())
    }

    @Test func swiftBuildLoadsTheGeneratedPIF() async throws {
        let developer = try SyntheticDeveloperDirectory.create(at: directory.path + "/xcode")
        let pifPath = directory.path + "/synced.pif"
        try FileSystem.write(Data(document.serialized().utf8), to: pifPath)
        let guid = projectGUID + MD5.hex("C00000000000000000000001")
        let (targets, app) = try await SwiftBuildEngine.withWorkspace(developerDirectory: developer, pifPath: pifPath, host: .current()) { session in
            (try await session.targets(), try await session.exportedBuildSettings(targetGUID: guid, request: SettingsRequest(configuration: "Debug")))
        }
        #expect(targets.map(\.name) == ["App", "Kit"])
        // Read from the xcconfig that the synchronized folder holds.
        #expect(app["INFOPLIST_FILE"] == "App/Info.plist")
        #expect(app["GENERATE_INFOPLIST_FILE"] == "YES")
    }
}

@Suite struct XCConfigFileTests {
    @Test func readsAssignmentsIncludesAndComments() throws {
        let directory = try TemporaryDirectory()
        try FileSystem.write(Data("A = 1 // one\nB = base\n".utf8), to: directory.path + "/Base.xcconfig")
        try FileSystem.write(Data("#include \"Base.xcconfig\"\n#include? \"Missing.xcconfig\"\nB = override;\nC[sdk=iphoneos*] = conditional\n// D = commented\n".utf8), to: directory.path + "/App.xcconfig")
        #expect(XCConfigFile.settings(at: directory.path + "/App.xcconfig") == ["A": "1", "B": "override"])
        #expect(XCConfigFile.conditionalSettingNames(at: directory.path + "/App.xcconfig") == ["C"])
    }
}
