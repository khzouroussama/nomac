import Foundation
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport
import Testing
@testable import NomacPackages

/// Synthetic inputs written from the observations in docs/formats/pif.md ("Swift packages"):
/// no Apple file is involved.
enum PackageFixtures {
    /// A developer directory with the parts NomacPackages reads: the tvOS, watchOS and
    /// visionOS SDKs' version maps from iOS, and each platform's testing binaries.
    static func developerDirectory(at root: String) throws -> String {
        let developer = root + "/Xcode.app/Contents/Developer"
        let maps: [(String, String, [String: String])] = [
            ("AppleTVOS", "iOS_tvOS", ["17.0": "17.0", "17.4": "17.4", "18.0": "18.0"]),
            ("WatchOS", "iOS_watchOS", ["17.0": "10.0", "17.4": "10.4", "18.0": "11.0"]),
            ("XROS", "iOS_visionOS", ["17.0": "1.0", "17.4": "1.1", "17.5": "1.2", "18.0": "2.0"]),
        ]
        for (sdk, name, map) in maps {
            let directory = "\(developer)/Platforms/\(sdk).platform/Developer/SDKs/\(sdk).sdk"
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: ["VersionMap": [name: map]])
            try data.write(to: URL(fileURLWithPath: directory + "/SDKSettings.json"))
        }
        let binaries: [(String, UInt32, UInt32)] = [
            ("MacOSX", MachOBuildVersion.platformMacOS, 13 << 16),
            ("MacOSX", MachOBuildVersion.platformMacCatalyst, 16 << 16),
            ("iPhoneOS", MachOBuildVersion.platformIOS, 17 << 16),
            ("AppleTVOS", MachOBuildVersion.platformTvOS, 17 << 16),
            // Xcode 27.0's slices: arm64 and arm64e 26.0, arm64_32 10.0.
            ("WatchOS", MachOBuildVersion.platformWatchOS, 26 << 16),
            ("WatchOS", MachOBuildVersion.platformWatchOS, 26 << 16),
            ("WatchOS", MachOBuildVersion.platformWatchOS, 10 << 16),
            ("XROS", MachOBuildVersion.platformVisionOS, 1 << 16),
        ]
        var slices: [String: [[UInt8]]] = [:]
        for (platform, number, minos) in binaries { slices[platform, default: []].append(machO(platform: number, minos: minos)) }
        for (platform, platformSlices) in slices {
            for framework in ["XCTest", "Testing"] {
                let directory = "\(developer)/Platforms/\(platform).platform/Developer/Library/Frameworks/\(framework).framework"
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try Data(universal(platformSlices)).write(to: URL(fileURLWithPath: "\(directory)/\(framework)"))
            }
        }
        return developer
    }

    /// One 64-bit slice with an `LC_BUILD_VERSION` (`<mach-o/loader.h>`).
    static func machO(platform: UInt32, minos: UInt32) -> [UInt8] {
        let command: [UInt32] = [0x32, 24, platform, minos, 27 << 16, 0]
        return ([0xfeed_facf, 0x0100_000c, 0, 6, 1, 24, 0, 0] + command).flatMap { value in (0..<4).map { UInt8((value >> (8 * $0)) & 0xff) } }
    }

    /// A universal file (`<mach-o/fat.h>`) holding `slices`.
    static func universal(_ slices: [[UInt8]]) -> [UInt8] {
        func bigEndian(_ value: UInt32) -> [UInt8] { (0..<4).reversed().map { UInt8((value >> (8 * $0)) & 0xff) } }
        var bytes = bigEndian(0xcafe_babe) + bigEndian(UInt32(slices.count))
        for (index, slice) in slices.enumerated() {
            bytes += [0x0100_000c, 0, UInt32(4096 * (index + 1)), UInt32(slice.count), 12].flatMap(bigEndian)
        }
        for (index, slice) in slices.enumerated() {
            bytes += [UInt8](repeating: 0, count: 4096 * (index + 1) - bytes.count) + slice
        }
        return bytes
    }

    /// A project whose app target uses the product `Kit` of the package folder `Packages/Kit`
    /// (a file reference, so a root package) and the product `Dep` of `Packages/Dep`
    /// (an XCLocalSwiftPackageReference, so a dependency).
    static func project(at root: String) throws -> String {
        let kit = """
        // swift-tools-version: 6.0
        import PackageDescription

        var products: [Product] = [.library(name: "Kit", targets: ["Kit"])]
        #if os(Linux)
        products.append(.library(name: "LinuxOnly", targets: ["Kit"]))
        #endif

        let package = Package(
            name: "Kit",
            platforms: [.iOS("17.4")],
            products: products,
            targets: [.target(name: "Kit"), .testTarget(name: "KitTests", dependencies: ["Kit"])]
        )
        """
        let dep = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Dep",
            platforms: [.iOS(.v18)],
            products: [.library(name: "Dep", targets: ["Dep"])],
            targets: [.target(name: "Dep"), .testTarget(name: "DepTests", dependencies: ["Dep"])]
        )
        """
        let files = [
            "Packages/Kit/Package.swift": kit,
            "Packages/Kit/Sources/Kit/Kit.swift": "public let kit = 1\n",
            "Packages/Kit/Tests/KitTests/KitTests.swift": "import Testing\n@testable import Kit\n@Test func kitValue() { #expect(kit == 1) }\n",
            "Packages/Dep/Package.swift": dep,
            "Packages/Dep/Sources/Dep/Dep.swift": "public let dep = 1\n",
            "Packages/Dep/Tests/DepTests/DepTests.swift": "import Testing\n@testable import Dep\n@Test func depValue() { #expect(dep == 1) }\n",
            "App.xcodeproj/project.pbxproj": pbxproj,
        ]
        for (path, contents) in files {
            let full = root + "/" + path
            try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try contents.write(toFile: full, atomically: true, encoding: .utf8)
        }
        return root + "/App.xcodeproj"
    }

    static let kitProduct = "E00000000000000000000001"
    static let depProduct = "E00000000000000000000002"

    static let pbxproj = """
    // !$*UTF8*$!
    {
    	archiveVersion = 1;
    	classes = {
    	};
    	objectVersion = 77;
    	objects = {
    		90000000000000000000000A /* Kit in Frameworks */ = {isa = PBXBuildFile; productRef = E00000000000000000000001 /* Kit */; };
    		90000000000000000000000B /* Dep in Frameworks */ = {isa = PBXBuildFile; platformFilters = (ios, maccatalyst, ); productRef = E00000000000000000000002 /* Dep */; };
    		A00000000000000000000001 /* Kit */ = {isa = PBXFileReference; lastKnownFileType = wrapper; name = Kit; path = Packages/Kit; sourceTree = "<group>"; };
    		F00000000000000000000001 /* App.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
    		F00000000000000000000009 /* Frameworks */ = {
    			isa = PBXFrameworksBuildPhase;
    			buildActionMask = 2147483647;
    			files = (
    				90000000000000000000000A /* Kit in Frameworks */,
    				90000000000000000000000B /* Dep in Frameworks */,
    			);
    			runOnlyForDeploymentPostprocessing = 0;
    		};
    		F00000000000000000000002 = {
    			isa = PBXGroup;
    			children = (
    				A00000000000000000000001 /* Kit */,
    				F00000000000000000000003 /* Products */,
    			);
    			sourceTree = "<group>";
    		};
    		F00000000000000000000003 /* Products */ = {
    			isa = PBXGroup;
    			children = (
    				F00000000000000000000001 /* App.app */,
    			);
    			name = Products;
    			sourceTree = "<group>";
    		};
    		C00000000000000000000001 /* App */ = {
    			isa = PBXNativeTarget;
    			buildConfigurationList = F00000000000000000000010;
    			buildPhases = (
    				F00000000000000000000009 /* Frameworks */,
    			);
    			buildRules = (
    			);
    			dependencies = (
    			);
    			name = App;
    			packageProductDependencies = (
    				E00000000000000000000001 /* Kit */,
    				E00000000000000000000002 /* Dep */,
    			);
    			productName = App;
    			productReference = F00000000000000000000001 /* App.app */;
    			productType = "com.apple.product-type.application";
    		};
    		F00000000000000000000006 /* Project object */ = {
    			isa = PBXProject;
    			buildConfigurationList = F00000000000000000000011;
    			developmentRegion = en;
    			knownRegions = (
    				en,
    				Base,
    			);
    			mainGroup = F00000000000000000000002;
    			packageReferences = (
    				D00000000000000000000001 /* Dep */,
    			);
    			productRefGroup = F00000000000000000000003 /* Products */;
    			projectDirPath = "";
    			projectRoot = "";
    			targets = (
    				C00000000000000000000001 /* App */,
    			);
    		};
    		F00000000000000000000007 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
    		F00000000000000000000008 /* Release */ = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };
    		F00000000000000000000012 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
    		F00000000000000000000013 /* Release */ = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Release; };
    		F00000000000000000000010 = {
    			isa = XCConfigurationList;
    			buildConfigurations = (
    				F00000000000000000000012 /* Debug */,
    				F00000000000000000000013 /* Release */,
    			);
    			defaultConfigurationName = Release;
    		};
    		F00000000000000000000011 = {
    			isa = XCConfigurationList;
    			buildConfigurations = (
    				F00000000000000000000007 /* Debug */,
    				F00000000000000000000008 /* Release */,
    			);
    			defaultConfigurationName = Release;
    		};
    		D00000000000000000000001 /* Dep */ = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Dep; };
    		E00000000000000000000001 /* Kit */ = {isa = XCSwiftPackageProductDependency; productName = Kit; };
    		E00000000000000000000002 /* Dep */ = {isa = XCSwiftPackageProductDependency; productName = Dep; };
    	};
    	rootObject = F00000000000000000000006 /* Project object */;
    }
    """
}

@Suite struct SwiftPackagesTests {
    @Test func findsRootPackagesAndDependencies() throws {
        let directory = try TemporaryDirectory()
        let workspace = try XcodeWorkspace.load(path: try PackageFixtures.project(at: directory.path))
        let references = try PackageReferences.find(in: workspace)
        let root = (directory.path as NSString).standardizingPath
        #expect(references.rootPackages == [root + "/Packages/Kit"])
        #expect(references.localDependencies == [root + "/Packages/Dep"])
        #expect(references.remoteDependencies.isEmpty)
        #expect(references.resolvedFile == workspace.path + "/xcshareddata/swiftpm/Package.resolved")
    }

    /// A package folder the workspace references itself is a root package too (cwa).
    @Test func workspacePackageFoldersAreRootPackages() throws {
        let directory = try TemporaryDirectory()
        let project = try PackageFixtures.project(at: directory.path + "/app")
        try FileManager.default.createDirectory(atPath: directory.path + "/Tool", withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"Tool\")\n".write(toFile: directory.path + "/Tool/Package.swift", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: directory.path + "/W.xcworkspace", withIntermediateDirectories: true)
        let relativeProject = String(project.dropFirst(directory.path.count + 1))
        try #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:Tool"></FileRef><FileRef location = "group:\#(relativeProject)"></FileRef></Workspace>"#
            .write(toFile: directory.path + "/W.xcworkspace/contents.xcworkspacedata", atomically: true, encoding: .utf8)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/W.xcworkspace")
        let root = (directory.path as NSString).standardizingPath
        #expect(workspace.packageFolders == [root + "/Tool"])
        #expect(workspace.projects.count == 1)
        #expect(try PackageReferences.find(in: workspace).rootPackages == [root + "/Tool", root + "/app/Packages/Kit"])
    }

    /// The package projects, and the app target's use of them, as Xcode 27.0 builds them.
    @Test func generatesPackageProjectsAsXcodeDoes() async throws {
        let directory = try TemporaryDirectory()
        let developer = try PackageFixtures.developerDirectory(at: directory.path + "/sdk")
        let workspace = try XcodeWorkspace.load(path: try PackageFixtures.project(at: directory.path + "/app"))
        var packages = try SwiftPackages(workspace: workspace, sourcePackagesDirectory: directory.path + "/SourcePackages", developerDirectory: developer)
        let projects = try await packages.load()
        var generator = PIFGenerator(workspace: workspace, packages: projects)
        let document = try generator.generate()

        // As xcodebuild lists them: the root package without a pin, the local dependency `@ local`,
        // at the path the workspace was opened with (icecubes: /tmp/nomac-corpus, not /private/tmp).
        let appFolder = (directory.path as NSString).standardizingPath + "/app"
        #expect(packages.sourcePackages.map(\.listing) == ["Dep: \(appFolder)/Packages/Dep @ local", "Kit: \(appFolder)/Packages/Kit"])

        let objects = document.objects.map(\.contents)
        func project(_ guid: String) throws -> [String: PIFValue] {
            try #require(objects.first { $0.objectValue?["guid"]?.stringValue == guid }?.objectValue)
        }
        func settings(_ object: [String: PIFValue]) -> [String: PIFValue] {
            object["buildConfigurations"]?.arrayValue?.first?.objectValue?["buildSettings"]?.objectValue ?? [:]
        }
        let targetGUIDs = Set(objects.compactMap { $0.objectValue?["guid"]?.stringValue })

        // Root package: no dependency tag, a test product per test target, Xcode's device
        // families, platforms aligned through the SDKs' maps.
        let kit = settings(try project("PACKAGE:kit"))
        #expect(kit["BUILD_SERVER_PROTOCOL_TARGET_TAGS"] == nil)
        #expect(kit["TARGETED_DEVICE_FAMILY"] == .string("1,2,3,4,6,7"))
        #expect(kit["IPHONEOS_DEPLOYMENT_TARGET"] == .string("17.4"))
        #expect(kit["TVOS_DEPLOYMENT_TARGET"] == .string("17.4"))
        #expect(kit["WATCHOS_DEPLOYMENT_TARGET"] == .string("10.4"))
        #expect(kit["XROS_DEPLOYMENT_TARGET"] == .string("1.1"))
        let tests = settings(try project("PACKAGE-PRODUCT:kit_KitTests.KitTests"))
        #expect(tests["MACOSX_DEPLOYMENT_TARGET"] == .string("14.0"))
        #expect(tests["IPHONEOS_DEPLOYMENT_TARGET"] == .string("17.4"))

        // The manifest was evaluated as on a Mac.
        #expect(!targetGUIDs.contains { $0.contains("LinuxOnly") })
        // No umbrella test product and no test runners.
        #expect(!targetGUIDs.contains { $0.contains("PackageTests") || $0.contains("test_runner") })

        // XCLocalSwiftPackageReference: a dependency, without test products.
        #expect(settings(try project("PACKAGE:dep"))["BUILD_SERVER_PROTOCOL_TARGET_TAGS"] == .array([.string("$(inherited)"), .string("dependency")]))
        #expect(!targetGUIDs.contains("PACKAGE-PRODUCT:dep_DepTests.DepTests"))

        // The app target links both products and depends on them.
        let app = try #require(document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"]?.stringValue == "App" }?.contents.objectValue)
        #expect(app["dependencies"] == .array([
            .object(["guid": .string("PACKAGE-PRODUCT:kit_Kit.Kit"), "name": .string("Kit")]),
            .object(["guid": .string("PACKAGE-PRODUCT:dep_Dep.Dep"), "name": .string("Dep"),
                     "platformFilters": .array([.object(["platform": .string("ios")]), .object(["environment": .string("maccatalyst"), "platform": .string("ios")])])]),
        ]))
        let buildFiles = app["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"]?.arrayValue ?? []
        #expect(buildFiles.first == .object([
            "guid": .string(PIFIdentifiers.md5(PackageFixtures.kitProduct)),
            "targetReference": .string("PACKAGE-PRODUCT:kit_Kit.Kit"),
        ]))
        #expect(buildFiles.count == 2)
    }

    /// xcodebuild in a folder with only a `Package.swift` (expo-default's nested build of
    /// ExpoModulesJSI, whose folder is `apple`): the workspace is the package's, named after its
    /// manifest, and the root package's dynamic products are installed.
    @Test func aPackageFolderIsAWorkspace() async throws {
        let directory = try TemporaryDirectory()
        let developer = try PackageFixtures.developerDirectory(at: directory.path + "/sdk")
        try directory.writeExactly("""
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "Lib", products: [.library(name: "Lib", type: .dynamic, targets: ["Lib"])], targets: [.target(name: "Lib")])

            """, to: "apple/Package.swift")
        try directory.writeExactly("public let lib = 1\n", to: "apple/Sources/Lib/Lib.swift")
        let folder = (directory.path as NSString).standardizingPath + "/apple"
        #expect(try await SwiftPackages.manifestName(folder: folder) == "Lib")
        let workspace = XcodeWorkspace.package(folder: folder, name: "Lib")
        #expect(workspace.path == folder + "/.swiftpm/xcode/package.xcworkspace")
        #expect(workspace.packageFolders == [folder])
        var packages = try SwiftPackages(workspace: workspace, sourcePackagesDirectory: directory.path + "/SourcePackages", developerDirectory: developer)
        var generator = PIFGenerator(workspace: workspace, packages: try await packages.load())
        let document = try generator.generate()
        let product = try #require(document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"]?.stringValue == "Lib-product" }?.contents.objectValue)
        for configuration in product["buildConfigurations"]?.arrayValue ?? [] {
            let settings = configuration.objectValue?["buildSettings"]?.objectValue ?? [:]
            #expect(settings["SKIP_INSTALL"] == .string("NO"))
            #expect(settings["INSTALL_PATH"] == .string("/usr/local/lib"))
        }
    }

    /// loader-experiments `package-target-kinds`: a scheme can build what the package's PIF
    /// project has. No binary target is there; a root package has its other targets, a
    /// dependency only those its products use (kickstarter: facebook-ios-sdk's `FBSDKCoreKit`
    /// scheme, which builds a binary target, fails with 66). Executable products are known as
    /// such, since only a launch or profile covers them (`tool`, `Deptool`).
    @Test func schemesCanBuildThePIFTargetsOnly() async throws {
        let directory = try TemporaryDirectory()
        let developer = try PackageFixtures.developerDirectory(at: directory.path + "/sdk")
        let project = try PackageFixtures.project(at: directory.path + "/app")
        for name in ["Kit", "Dep"] {
            let files = [
                "Package.swift": """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "\(name)",
                    platforms: [.iOS(.v18)],
                    products: [.library(name: "\(name)", targets: ["\(name)"]), .executable(name: "\(name)tool", targets: ["\(name)Tool"])],
                    targets: [.target(name: "\(name)", dependencies: ["\(name)Bin"]), .binaryTarget(name: "\(name)Bin", path: "Bin.xcframework"),
                              .target(name: "\(name)Orphan"), .plugin(name: "\(name)Gen", capability: .buildTool()), .executableTarget(name: "\(name)Tool")]
                )
                """,
                "Sources/\(name)Orphan/Orphan.swift": "public let orphan = 1\n",
                "Sources/\(name)Tool/main.swift": "print(1)\n",
                "Plugins/\(name)Gen/plugin.swift": "import PackagePlugin\n",
                "Bin.xcframework/Info.plist": """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0"><dict><key>AvailableLibraries</key><array/><key>CFBundlePackageType</key><string>XFWK</string><key>XCFrameworkFormatVersion</key><string>1.0</string></dict></plist>

                """,
            ]
            for (path, text) in files {
                let full = directory.path + "/app/Packages/\(name)/" + path
                try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try text.write(toFile: full, atomically: true, encoding: .utf8)
            }
        }
        var packages = try SwiftPackages(workspace: try XcodeWorkspace.load(path: project), sourcePackagesDirectory: directory.path + "/SourcePackages", developerDirectory: developer)
        _ = try await packages.load()
        let kit = try #require(packages.sourcePackages.first { $0.name == "Kit" })
        #expect(kit.contents.targets == ["Kit", "KitGen", "KitOrphan", "KitTool"])
        let dep = try #require(packages.sourcePackages.first { $0.name == "Dep" })
        #expect(dep.contents.targets == ["Dep", "DepTool"])
        #expect(!dep.contents.contains("DepBin") && dep.contents.contains("Dep"))
        for package in [kit, dep] {
            #expect(package.contents.products.map(\.isExecutable) == [false, true])
        }
    }

    /// loader-experiments `build-tool-plugin` (BACKLOG B-009): a plugin product and the product
    /// SwiftPM makes for an executable target no product names have schemes, after the declared
    /// products.
    @Test func pluginAndImplicitExecutableProducts() async throws {
        let directory = try TemporaryDirectory()
        let developer = try PackageFixtures.developerDirectory(at: directory.path + "/sdk")
        let project = try PackageFixtures.project(at: directory.path + "/app")
        let files = [
            "Package.swift": """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Kit",
                platforms: [.iOS(.v18)],
                products: [.library(name: "Kit", targets: ["Kit"]), .plugin(name: "KitGen", targets: ["KitGen"])],
                targets: [.target(name: "Kit"), .executableTarget(name: "KitTool"),
                          .plugin(name: "KitGen", capability: .buildTool(), dependencies: ["KitTool"])]
            )
            """,
            "Sources/KitTool/main.swift": "print(1)\n",
            "Plugins/KitGen/plugin.swift": "import PackagePlugin\n",
        ]
        for (path, text) in files {
            let full = directory.path + "/app/Packages/Kit/" + path
            try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: full, atomically: true, encoding: .utf8)
        }
        var packages = try SwiftPackages(workspace: try XcodeWorkspace.load(path: project), sourcePackagesDirectory: directory.path + "/SourcePackages", developerDirectory: developer)
        _ = try await packages.load()
        let kit = try #require(packages.sourcePackages.first { $0.name == "Kit" })
        #expect(kit.contents.products.map(\.name) == ["Kit", "KitGen", "KitTool"])
        #expect(kit.contents.products.map(\.isExecutable) == [false, false, true])
    }

    /// The Mac's branch of a manifest that imports `Darwin.C` loads on Linux too (kickstarter:
    /// facebook-ios-sdk failed with "no such module 'Darwin.C'").
    @Test func loadsManifestsThatImportDarwin() async throws {
        let directory = try TemporaryDirectory()
        let developer = try PackageFixtures.developerDirectory(at: directory.path + "/sdk")
        let project = try PackageFixtures.project(at: directory.path + "/app")
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        import Foundation

        #if os(Linux)
        import Glibc
        #else
        import Darwin.C
        #endif

        let product = getenv("NOMAC_UNSET_VARIABLE") == nil ? "Kit" : "Other"

        let package = Package(
            name: "Kit",
            platforms: [.iOS("17.4")],
            products: [.library(name: product, targets: ["Kit"])],
            targets: [.target(name: "Kit")]
        )
        """.write(toFile: directory.path + "/app/Packages/Kit/Package.swift", atomically: true, encoding: .utf8)
        var packages = try SwiftPackages(workspace: try XcodeWorkspace.load(path: project), sourcePackagesDirectory: directory.path + "/SourcePackages", developerDirectory: developer)
        _ = try await packages.load()
        let kit = try #require(packages.sourcePackages.first { $0.name == "Kit" })
        #expect(kit.contents.products.map(\.name) == ["Kit"])
    }

    @Test func aWorkspaceWithoutPackagesNeedsNoDeveloperDirectory() async throws {
        let directory = try TemporaryDirectory()
        let project = try PackageFixtures.project(at: directory.path)
        let pbxproj = project + "/project.pbxproj"
        var text = try String(contentsOfFile: pbxproj, encoding: .utf8)
        text = text.replacingOccurrences(of: "\t\t\t\tA00000000000000000000001 /* Kit */,\n", with: "")
            .replacingOccurrences(of: "\t\t\t\tD00000000000000000000001 /* Dep */,\n", with: "")
        try text.write(toFile: pbxproj, atomically: true, encoding: .utf8)
        var packages = try SwiftPackages(workspace: try XcodeWorkspace.load(path: project), sourcePackagesDirectory: directory.path + "/SourcePackages", developerDirectory: nil)
        #expect(try await packages.load() == PackageProjects())
    }

    @Test func findsTheToolchainBehindALinkedCompiler() throws {
        let directory = try TemporaryDirectory()
        let toolchain = directory.path + "/toolchain/usr/bin"
        try FileManager.default.createDirectory(atPath: toolchain, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: directory.path + "/toolchain/usr/lib/swift/pm/ManifestAPI", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: directory.path + "/links", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: directory.path + "/shim/bin", withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(atPath: toolchain + "/swift-driver", contents: Data(), attributes: [.posixPermissions: 0o755]))
        #expect(FileManager.default.createFile(atPath: directory.path + "/shim/bin/swiftc", contents: Data(), attributes: [.posixPermissions: 0o755]))
        try FileManager.default.createSymbolicLink(atPath: toolchain + "/swiftc", withDestinationPath: "swift-driver")
        try FileManager.default.createSymbolicLink(atPath: directory.path + "/links/swiftc", withDestinationPath: toolchain + "/swiftc")
        let path = "relative:\(directory.path)/empty:\(directory.path)/shim/bin:\(directory.path)/links:\(toolchain)"
        #expect(SwiftPackages.toolchainBinDirectory(environment: ["PATH": path])?.pathString == FileSystem.resolvingSymbolicLinks(toolchain))
        #expect(SwiftPackages.toolchainBinDirectory(environment: ["PATH": directory.path + "/shim/bin"]) == nil)
        #expect(SwiftPackages.toolchainBinDirectory(environment: ["PATH": path, "SWIFT_EXEC": "/x/swiftc"]) == nil)
        #expect(SwiftPackages.toolchainBinDirectory(environment: ["PATH": directory.path + "/empty"]) == nil)
    }

    /// A release install has no `swiftc` on `PATH`: install.sh keeps swift.org's toolchain in
    /// `<prefix>/swift`, beside `<prefix>/bin/nomac`, which `~/.local/bin/nomac` links to.
    @Test func toolchainInstalledBesideNomacIsFound() throws {
        let directory = try TemporaryDirectory()
        let toolchain = directory.path + "/prefix/swift/usr/bin"
        try FileManager.default.createDirectory(atPath: toolchain, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: directory.path + "/prefix/swift/usr/lib/swift/pm/ManifestAPI", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: directory.path + "/prefix/bin", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: directory.path + "/bin", withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(atPath: toolchain + "/swiftc", contents: Data(), attributes: [.posixPermissions: 0o755]))
        #expect(FileManager.default.createFile(atPath: directory.path + "/prefix/bin/nomac", contents: Data(), attributes: [.posixPermissions: 0o755]))
        try FileManager.default.createSymbolicLink(atPath: directory.path + "/bin/nomac", withDestinationPath: directory.path + "/prefix/bin/nomac")
        let found = SwiftPackages.toolchainBinDirectory(environment: ["PATH": "/nonexistent"], executable: directory.path + "/bin/nomac")
        #expect(found?.pathString == FileSystem.resolvingSymbolicLinks(toolchain))
        #expect(SwiftPackages.toolchainBinDirectory(environment: ["PATH": "/nonexistent"], executable: directory.path + "/elsewhere/nomac") == nil)
    }

    /// Xcode resolves through SwiftPM's shared cache, `~/Library/Caches/org.swift.swiftpm` on the
    /// reference Mac; off macOS SwiftPM's own cache directory, under `$XDG_CACHE_HOME` or `$HOME`,
    /// which GitHub's job containers set apart from the user's home (`/github/home`, not `/root`).
    @Test func sharesSwiftPMsCacheAsXcodeDoes() {
        #if os(macOS)
        #expect(SwiftPackages.sharedCacheDirectory?.pathString == NSHomeDirectory() + "/Library/Caches/org.swift.swiftpm")
        #else
        let environment = ProcessInfo.processInfo.environment
        let caches = environment["XDG_CACHE_HOME"] ?? (environment["HOME"] ?? NSHomeDirectory()) + "/.cache"
        #expect(SwiftPackages.sharedCacheDirectory?.pathString == caches + "/org.swift.swiftpm")
        #endif
    }
}

@Suite struct SourcePackageTests {
    @Test func readsPinsOfEveryResolvedFormat() throws {
        let directory = try TemporaryDirectory()
        let current = directory.path + "/v3.resolved"
        try #"""
        {"originHash": "x", "pins": [
          {"identity": "zip", "kind": "remoteSourceControl", "location": "https://github.com/marmelroy/Zip.git", "state": {"revision": "bca30f6d6c7d37cbc4aa8f6b0002e281dcc36195"}},
          {"identity": "emojitext", "kind": "remoteSourceControl", "location": "https://github.com/Dimillian/EmojiText", "state": {"branch": "fix-ios26", "revision": "3b11459a19c9406176a08b0f0599b98f88113296"}},
          {"identity": "nuke", "kind": "remoteSourceControl", "location": "https://github.com/kean/Nuke", "state": {"revision": "30f7a7e72e0607d304fbf69c799474bd5fb6d1ce", "version": "13.2.0"}}
        ], "version": 3}
        """#.write(toFile: current, atomically: true, encoding: .utf8)
        let pins = SourcePackage.pins(resolvedFile: current) { _ in "unused" }
        #expect(pins.mapValues(\.description) == ["zip": "bca30f6", "emojitext": "fix-ios26 (3b11459)", "nuke": "13.2.0"])
        #expect(pins["zip"]?.location == "https://github.com/marmelroy/Zip.git")

        let legacy = directory.path + "/v1.resolved"
        try #"""
        {"object": {"pins": [{"package": "Nuke", "repositoryURL": "https://github.com/kean/Nuke.git", "state": {"branch": null, "revision": "30f7a7e", "version": "12.0.0"}}]}, "version": 1}
        """#.write(toFile: legacy, atomically: true, encoding: .utf8)
        let legacyPins = SourcePackage.pins(resolvedFile: legacy) { $0.split(separator: "/").last.map { $0.replacingOccurrences(of: ".git", with: "").lowercased() } ?? $0 }
        #expect(legacyPins.mapValues(\.description) == ["nuke": "12.0.0"])
        #expect(SourcePackage.pins(resolvedFile: directory.path + "/missing") { $0 }.isEmpty)
    }
}

@Suite struct PlatformAlignmentTests {
    @Test func looksUpTheGreatestVersionNotAboveTheDeclaredOne() throws {
        let directory = try TemporaryDirectory()
        let alignment = PlatformAlignment(developerDirectory: try PackageFixtures.developerDirectory(at: directory.path))
        #expect(alignment.version(of: .visionOS, alignedWith: "17.4.1") == "1.1")
        #expect(alignment.version(of: .visionOS, alignedWith: "17.6") == "1.2")
        #expect(alignment.version(of: .watchOS, alignedWith: "18.3") == "11.0")
        #expect(alignment.version(of: .tvOS, alignedWith: "16.4") == nil)
        #expect(alignment.version(of: .macOS, alignedWith: "18.0") == nil)
    }

    @Test func aPlatformWithoutAnSDKIsNotAligned() {
        #expect(PlatformAlignment(developerDirectory: "/nonexistent").version(of: .tvOS, alignedWith: "18.0") == nil)
    }
}

@Suite struct XCTestDeploymentTargetsTests {
    @Test func readsTheTestingBinariesAndKeepsMacOS14() throws {
        let directory = try TemporaryDirectory()
        let result = XCTestDeploymentTargets.compute(developerDirectory: try PackageFixtures.developerDirectory(at: directory.path))
        #expect(result.missing.isEmpty)
        #expect(result.targets[.macOS] == "14.0")
        #expect(result.targets[.macCatalyst] == "16.0")
        #expect(result.targets[.iOS] == "17.0")
        #expect(result.targets[.tvOS] == "17.0")
        #expect(result.targets[.watchOS] == "10.0")
        #expect(result.targets[.visionOS] == "1.0")
    }

    @Test func reportsMissingBinaries() {
        let result = XCTestDeploymentTargets.compute(developerDirectory: "/nonexistent")
        #expect(result.targets == [.macOS: "14.0"])
        #expect(Set(result.missing) == [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS])
    }
}

/// loader-experiments `macros` and `unlinked-products`, and swiftfin's product named in the
/// wrong remote package, written again here: packages with a macro each, one of them a git
/// repository at a file URL that the project names as a remote package.
enum ProductFixtures {
    static func package(_ name: String, at directory: String) throws {
        let manifest = """
        // swift-tools-version: 6.0
        import CompilerPluginSupport
        import PackageDescription

        let package = Package(
            name: "\(name)",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [.library(name: "\(name)Kit", targets: ["\(name)Kit"])],
            targets: [.macro(name: "\(name)Macros"), .target(name: "\(name)Kit", dependencies: ["\(name)Macros"])]
        )
        """
        for (path, contents) in ["Package.swift": manifest, "Sources/\(name)Macros/Plugin.swift": "struct Plugin {}\n", "Sources/\(name)Kit/\(name)Kit.swift": "public let kit = 1\n"] {
            try FileSystem.write(Data(contents.utf8), to: directory + "/" + path)
        }
    }

    /// A target of a fixture project: each phase (its `isa`, with any other keys) links the
    /// product dependencies at `linked`; each entry of `dependencies` (product, package reference)
    /// is an object of its own, numbered in order, and `packageProductDependencies` lists those at
    /// `listed`, else all.
    struct Target {
        static let frameworks = "PBXFrameworksBuildPhase", embed = "PBXCopyFilesBuildPhase; dstPath = \"\"; dstSubfolderSpec = 10"
        var phases: [(isa: String, linked: [Int])]
        var dependencies: [(String, String?)]
        var listed: [Int]?
    }

    /// A project whose targets each have one phase, a Frameworks phase or else a Sources phase,
    /// that links the product dependencies at `linked`, all of them listed.
    static func project(at root: String, targets: [(frameworks: Bool, linked: [Int], dependencies: [(String, String?)])]) throws -> String {
        try project(at: root, targets: targets.map(Target.init))
    }

    static func project(at root: String, targets: [Target]) throws -> String {
        try package("Remote", at: root + "/Remote")
        try package("Local", at: root + "/Packages/Local")
        try package("Root", at: root + "/Packages/Root")
        let git = try #require(Subprocess.locate("git"))
        for arguments in [["init", "-q"], ["add", "."], ["-c", "user.name=nomac", "-c", "user.email=nomac@example.invalid", "commit", "-q", "-m", "1.0.0"], ["tag", "1.0.0"]] {
            #expect(try Subprocess.run(git, arguments, currentDirectory: root + "/Remote").exitStatus == 0)
        }
        var objects = """
        \t\tA00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Packages/Root; sourceTree = "<group>"; };
        \t\tD00000000000000000000001 = {isa = XCRemoteSwiftPackageReference; repositoryURL = "file://\(root)/Remote"; requirement = {kind = exactVersion; version = 1.0.0; }; };
        \t\tD00000000000000000000002 = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Local; };
        \t\tF00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000001, ); sourceTree = "<group>"; };
        \t\tF0000000000000000000000L = {isa = XCConfigurationList; buildConfigurations = (F0000000000000000000000D, ); defaultConfigurationName = Debug; };
        \t\tF0000000000000000000000D = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };

        """
        var targetIDs: [String] = []
        var products = 0
        for (index, target) in targets.enumerated() {
            let id = String(format: "C%023d", index + 1)
            targetIDs.append(id)
            var dependencyIDs: [String] = []
            for (product, package) in target.dependencies {
                products += 1
                dependencyIDs.append(String(format: "E%023d", products))
                objects += "\t\t\(dependencyIDs.last!) = {isa = XCSwiftPackageProductDependency; \(package.map { "package = \($0); " } ?? "")productName = \(product); };\n"
            }
            var phaseIDs: [String] = []
            for (phaseIndex, phase) in target.phases.enumerated() {
                var buildFiles: [String] = []
                for (position, linked) in phase.linked.enumerated() {
                    buildFiles.append(String(format: "B%019d%02d%03d", index + 1, phaseIndex, position))
                    objects += "\t\t\(buildFiles.last!) = {isa = PBXBuildFile; productRef = \(dependencyIDs[linked]); };\n"
                }
                phaseIDs.append(String(format: "P%021d%02d", index + 1, phaseIndex))
                objects += "\t\t\(phaseIDs.last!) = {isa = \(phase.isa); buildActionMask = 2147483647; files = (\(buildFiles.map { $0 + ", " }.joined())); runOnlyForDeploymentPostprocessing = 0; };\n"
            }
            let listed = target.listed.map { $0.map { dependencyIDs[$0] } } ?? dependencyIDs
            objects += "\t\t\(id) = {isa = PBXNativeTarget; buildConfigurationList = F0000000000000000000000L; buildPhases = (\(phaseIDs.map { $0 + ", " }.joined())); name = App\(index + 1); "
                + "packageProductDependencies = (\(listed.map { $0 + ", " }.joined())); productName = App\(index + 1); productReference = \(String(format: "R%023d", index + 1)); productType = \"com.apple.product-type.application\"; };\n"
                + "\t\t\(String(format: "R%023d", index + 1)) = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App\(index + 1).app; sourceTree = BUILT_PRODUCTS_DIR; };\n"
        }
        let pbxproj = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \(objects)\t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F0000000000000000000000L; developmentRegion = en; knownRegions = (en, Base, ); mainGroup = F00000000000000000000002; packageReferences = (D00000000000000000000001, D00000000000000000000002, ); projectDirPath = ""; projectRoot = ""; targets = (\(targetIDs.map { $0 + ", " }.joined())); };
        \t};
        \trootObject = F00000000000000000000006;
        }
        """
        try FileSystem.write(Data(pbxproj.utf8), to: root + "/App.xcodeproj/project.pbxproj")
        return root + "/App.xcodeproj"
    }

    static func document(targets: [(frameworks: Bool, linked: [Int], dependencies: [(String, String?)])], in directory: TemporaryDirectory,
                         skipsMacroValidation: Bool = false) async throws -> PIFDocument {
        try await document(targets: targets.map(Target.init), in: directory, skipsMacroValidation: skipsMacroValidation)
    }

    static func document(targets: [Target], in directory: TemporaryDirectory, skipsMacroValidation: Bool = false) async throws -> PIFDocument {
        let developer = try PackageFixtures.developerDirectory(at: directory.path + "/sdk")
        let workspace = try XcodeWorkspace.load(path: try project(at: (directory.path as NSString).standardizingPath + "/app", targets: targets))
        var packages = try SwiftPackages(workspace: workspace, sourcePackagesDirectory: directory.path + "/SourcePackages", developerDirectory: developer,
                                         skipsMacroValidation: skipsMacroValidation)
        var generator = PIFGenerator(workspace: workspace, packages: try await packages.load())
        return try generator.generate()
    }

    static func target(_ name: String, in document: PIFDocument) throws -> [String: PIFValue] {
        try #require(document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"]?.stringValue == name }?.contents.objectValue)
    }
}

extension ProductFixtures.Target {
    init(_ target: (frameworks: Bool, linked: [Int], dependencies: [(String, String?)])) {
        self.init(phases: [(target.frameworks ? Self.frameworks : "PBXSourcesBuildPhase", target.linked)], dependencies: target.dependencies)
    }
}

@Suite struct PackageProductTests {
    static let remote = "D00000000000000000000001", local = "D00000000000000000000002"

    /// Without a Package.resolved, Xcode resolves the remote packages, creates the workspace's
    /// `xcshareddata/swiftpm/configuration` folder and writes the file (envelope-experiments
    /// `package-resolved`: `no-workspace`, a project without project.xcworkspace).
    @Test func resolvesWithoutAPackageResolvedAsXcodeDoes() async throws {
        let directory = try TemporaryDirectory()
        _ = try await ProductFixtures.document(targets: [(true, [0], [("RemoteKit", Self.remote)])], in: directory)
        let swiftpm = (directory.path as NSString).standardizingPath + "/app/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
        #expect(FileSystem.isDirectory(swiftpm + "/configuration"))
        let pins = SourcePackage.pins(resolvedFile: swiftpm + "/Package.resolved") { _ in "unused" }
        #expect(pins["remote"]?.version == "1.0.0")
    }

    /// Xcode approves the macros of local and root packages, not those of a remote package the
    /// user has not trusted (swiftfin; loader-experiments `macros`).
    @Test func approvesTheMacrosOfLocalPackagesOnly() async throws {
        let approval = try await Self.approval(skipsMacroValidation: false)
        #expect(approval["PACKAGE-TARGET:RemoteMacros"] == .string("false"))
        #expect(approval["PACKAGE-TARGET:LocalMacros"] == .string("true"))
        #expect(approval["PACKAGE-TARGET:RootMacros"] == .string("true"))
        #expect(approval["PACKAGE-TARGET:RemoteKit"] == .string("true"))
    }

    /// `-skipMacroValidation` approves the remote package's macros too (swiftfin's `-dumpPIF`
    /// with the option: its four remote macro targets become true, nothing else changes).
    @Test func approvesEveryMacroWhenValidationIsSkipped() async throws {
        let approval = try await Self.approval(skipsMacroValidation: true)
        #expect(approval["PACKAGE-TARGET:RemoteMacros"] == .string("true"))
        #expect(approval["PACKAGE-TARGET:LocalMacros"] == .string("true"))
        #expect(approval["PACKAGE-TARGET:RootMacros"] == .string("true"))
    }

    static func approval(skipsMacroValidation: Bool) async throws -> [String: PIFValue] {
        let directory = try TemporaryDirectory()
        let document = try await ProductFixtures.document(targets: [(true, [0, 1, 2], [("RemoteKit", remote), ("LocalKit", local), ("RootKit", nil)])], in: directory,
                                                          skipsMacroValidation: skipsMacroValidation)
        return Dictionary(uniqueKeysWithValues: document.objects.compactMap { object -> (String, PIFValue)? in
            guard let contents = object.contents.objectValue, let guid = contents["guid"]?.stringValue, let approved = contents["approvedByUser"] else { return nil }
            return (guid, approved)
        })
    }

    /// A product the named remote package lacks is found in the other packages by name
    /// (swiftfin: `PulseLogHandler`, named in the Pulse package, is the PulseLogHandler
    /// package's); each product dependency object is listed, so a product named twice is
    /// listed twice (swiftfin).
    @Test func findsProductsByNameAndListsEveryDependencyObject() async throws {
        let directory = try TemporaryDirectory()
        let document = try await ProductFixtures.document(targets: [(true, [0, 1, 2], [("RemoteKit", Self.remote), ("LocalKit", Self.remote), ("LocalKit", Self.local)])], in: directory)
        let app = try ProductFixtures.target("App1", in: document)
        #expect(app["dependencies"] == .array(["remote_RemoteKit.RemoteKit", "local_LocalKit.LocalKit", "local_LocalKit.LocalKit"].map { product in
            .object(["guid": .string("PACKAGE-PRODUCT:" + product), "name": .string(String(product.split(separator: ".").last!))])
        }))
    }

    /// The products of a target's `dependencies` are its first Frameworks phase's, one entry per
    /// build file, the added ones included; another phase's products count for none
    /// (loader-experiments `product-duplicates`: `FwEmbed`, as home-assistant's `WatchApp` with
    /// `PromiseKitDynamic`, `FwSameTwice`, `UnlinkedTwo`, `ListedSecondFw`, `FwResources`).
    @Test func listsTheProductsOfTheFirstFrameworksPhaseOnly() async throws {
        typealias Target = ProductFixtures.Target
        let directory = try TemporaryDirectory()
        let kit = ("LocalKit", Self.local), root = ("RootKit", nil as String?)
        let document = try await ProductFixtures.document(targets: [
            Target(phases: [(Target.frameworks, [0]), (Target.embed, [1])], dependencies: [kit, kit], listed: []),
            Target(phases: [(Target.frameworks, [0, 0])], dependencies: [kit], listed: []),
            Target(phases: [(Target.frameworks, [])], dependencies: [kit, kit]),
            Target(phases: [(Target.frameworks, [1]), (Target.frameworks, [0]), ("PBXResourcesBuildPhase", [2])], dependencies: [kit, root, kit], listed: [0, 1]),
        ], in: directory)
        let names = try (1...4).map { index in
            try ProductFixtures.target("App\(index)", in: document)["dependencies"]?.arrayValue?.compactMap { $0.objectValue?["name"]?.stringValue }
        }
        #expect(names == [["LocalKit"], ["LocalKit", "LocalKit"], ["LocalKit", "LocalKit"], ["LocalKit", "RootKit"]])
    }

    /// Xcode inserts a build file for each product dependency the Frameworks phase does not
    /// link at the start of that phase, in `packageProductDependencies` order; a target without
    /// a Frameworks phase lists none of them (loader-experiments `unlinked-products`: App7, App2).
    @Test func addsUnlinkedProductsToTheFrameworksPhase() async throws {
        let directory = try TemporaryDirectory()
        let document = try await ProductFixtures.document(targets: [
            (true, [1], [("RootKit", nil), ("RemoteKit", Self.remote), ("LocalKit", Self.local)]),
            (false, [], [("RootKit", nil)]),
        ], in: directory)
        let first = try ProductFixtures.target("App1", in: document)
        let buildFiles = first["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"]?.arrayValue ?? []
        #expect(buildFiles == [("E00000000000000000000003", "local_LocalKit.LocalKit"), ("E00000000000000000000001", "root_RootKit.RootKit"), ("E00000000000000000000002", "remote_RemoteKit.RemoteKit")].map { id, product in
            .object(["guid": .string(PIFIdentifiers.md5(id)), "targetReference": .string("PACKAGE-PRODUCT:" + product)])
        })
        #expect(first["dependencies"]?.arrayValue?.compactMap { $0.objectValue?["name"]?.stringValue } == ["LocalKit", "RootKit", "RemoteKit"])
        let second = try ProductFixtures.target("App2", in: document)
        #expect(second["dependencies"] == .array([]))
        #expect(second["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"] == .array([]))
    }
}
