import Foundation
import Testing
import NomacCore
@testable import NomacPIF
import NomacProject
import NomacTestSupport

/// Rules confirmed by `loader-experiments` (docs/formats/pif.md), on projects written here.
@Suite struct LoaderRulesTests {
    /// A project file with one app target `name` (object C…1) compiling App.swift, plus
    /// `objects`, `targets` and `appExtra` lines in the target.
    static func project(name: String = "App", settings: String = "", objects: String = "", targets: [String] = [],
                        groupChildren: String = "", appExtra: String = "", projectReferences: String = "") -> String {
        """
        // !$*UTF8*$!
        {
        	archiveVersion = 1;
        	objectVersion = 77;
        	objects = {
        		A00000000000000000000003 = {isa = PBXBuildFile; fileRef = A00000000000000000000004; };
        		A00000000000000000000004 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
        		F00000000000000000000001 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = \(name).app; sourceTree = BUILT_PRODUCTS_DIR; };
        		F00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000004, \(groupChildren)F00000000000000000000003, ); sourceTree = "<group>"; };
        		F00000000000000000000003 = {isa = PBXGroup; children = (F00000000000000000000001, ); name = Products; sourceTree = "<group>"; };
        		F00000000000000000000004 = {isa = PBXSourcesBuildPhase; files = (A00000000000000000000003, ); };
        		C00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F0000000000000000000000A; buildPhases = (F00000000000000000000004, ); \(appExtra) name = \(name); productName = \(name); productReference = F00000000000000000000001; productType = "com.apple.product-type.application"; };
        		F00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F0000000000000000000000B; mainGroup = F00000000000000000000002; productRefGroup = F00000000000000000000003; projectDirPath = ""; \(projectReferences) projectRoot = ""; targets = (C00000000000000000000001, \(targets.joined(separator: ", "))); };
        		F00000000000000000000007 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; \(settings) }; name = Debug; };
        		F00000000000000000000008 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
        		F0000000000000000000000A = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000007, ); defaultConfigurationName = Debug; };
        		F0000000000000000000000B = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000008, ); defaultConfigurationName = Debug; };
        \(objects)
        	};
        	rootObject = F00000000000000000000006;
        }
        """
    }

    static func write(_ files: [String: String], to root: String) throws {
        for (path, text) in files {
            let full = root + "/" + path
            try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: full, atomically: true, encoding: .utf8)
        }
    }

    static func generate(_ container: String) throws -> PIFDocument {
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: container))
        return try generator.generate()
    }

    static func target(_ document: PIFDocument, _ name: String) throws -> [String: PIFValue] {
        try #require(document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"]?.stringValue == name }?.contents.objectValue)
    }

    @Test func listSettingsAreJoinedWithoutQuoting() throws {
        let directory = try TemporaryDirectory()
        let settings = #"OTHER_SWIFT_FLAGS = ("$(inherited)", "-D", "FLAG WITH SPACE", "quote\"inside", "back\\slash", );"#
        try Self.write(["P.xcodeproj/project.pbxproj": Self.project(settings: settings)], to: directory.path)
        let app = try Self.target(try Self.generate(directory.path + "/P.xcodeproj"), "App")
        let flags = app["buildConfigurations"]?.arrayValue?.first?.objectValue?["buildSettings"]?.objectValue?["OTHER_SWIFT_FLAGS"]
        #expect(flags == .string(#"$(inherited) -D FLAG WITH SPACE quote"inside back\slash"#))
    }

    @Test func workspaceProjectsAreIdentifiedAndOrderedByRelativePath() throws {
        let directory = try TemporaryDirectory()
        let reference = """
        		B00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = "wrapper.pb-project"; path = ../One/P.xcodeproj; sourceTree = "<group>"; };
        		B00000000000000000000002 = {isa = PBXGroup; children = (); name = Products; sourceTree = "<group>"; };
        		B00000000000000000000005 = {isa = PBXContainerItemProxy; containerPortal = B00000000000000000000001; proxyType = 1; remoteGlobalIDString = C00000000000000000000001; remoteInfo = App; };
        		B00000000000000000000006 = {isa = PBXTargetDependency; name = App; targetProxy = B00000000000000000000005; };
        """
        try Self.write([
            "W.xcworkspace/contents.xcworkspacedata": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Workspace version = "1.0">
               <FileRef location = "group:Two/P.xcodeproj"></FileRef>
               <FileRef location = "group:Three/Q.xcodeproj"></FileRef>
               <FileRef location = "group:One/P.xcodeproj"></FileRef>
            </Workspace>
            """,
            "One/P.xcodeproj/project.pbxproj": Self.project(name: "App"),
            "Two/P.xcodeproj/project.pbxproj": Self.project(name: "Other"),
            "Three/Q.xcodeproj/project.pbxproj": Self.project(
                name: "Client", objects: reference, groupChildren: "B00000000000000000000001, ",
                appExtra: "dependencies = (B00000000000000000000006, );",
                projectReferences: "projectReferences = ({ProductGroup = B00000000000000000000002; ProjectRef = B00000000000000000000001; }, );"),
        ], to: directory.path)
        let document = try Self.generate(directory.path + "/W.xcworkspace")
        let projects = document.objects.filter { $0.type == "project" }.compactMap { $0.contents.objectValue }
        #expect(projects.map { $0["guid"] } == ["One/P.xcodeproj", "Three/Q.xcodeproj", "Two/P.xcodeproj"].map { .string(MD5.hex($0)) })
        #expect(try Self.target(document, "Client")["dependencies"] == .array([.object([
            "guid": .string(MD5.hex("One/P.xcodeproj") + MD5.hex("C00000000000000000000001")),
            "name": .string("App (from P.xcodeproj)"),
        ])]))
    }

    /// `workspace-twins`: in two projects with the same object IDs, each app's build file names
    /// its own project's framework.
    @Test func productReferencesAreMatchedWithinTheirProject() throws {
        let directory = try TemporaryDirectory()
        func project(_ prefix: String) -> String {
            """
            // !$*UTF8*$!
            {
            	archiveVersion = 1;
            	objectVersion = 77;
            	objects = {
            		B00000000000000000000001 = {isa = PBXBuildFile; fileRef = F00000000000000000000009; };
            		B00000000000000000000002 = {isa = PBXFrameworksBuildPhase; files = (B00000000000000000000001, ); };
            		F00000000000000000000001 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = \(prefix)App.app; sourceTree = BUILT_PRODUCTS_DIR; };
            		F00000000000000000000009 = {isa = PBXFileReference; explicitFileType = wrapper.framework; path = \(prefix)Fw.framework; sourceTree = BUILT_PRODUCTS_DIR; };
            		F00000000000000000000002 = {isa = PBXGroup; children = (F00000000000000000000001, F00000000000000000000009, ); sourceTree = "<group>"; };
            		C00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F0000000000000000000000A; buildPhases = (B00000000000000000000002, ); name = \(prefix)App; productReference = F00000000000000000000001; productType = "com.apple.product-type.application"; };
            		C00000000000000000000002 = {isa = PBXNativeTarget; buildConfigurationList = F0000000000000000000000A; buildPhases = (); name = \(prefix)Fw; productReference = F00000000000000000000009; productType = "com.apple.product-type.framework"; };
            		F00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F0000000000000000000000B; mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (C00000000000000000000001, C00000000000000000000002, ); };
            		F00000000000000000000007 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
            		F00000000000000000000008 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
            		F0000000000000000000000A = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000007, ); defaultConfigurationName = Debug; };
            		F0000000000000000000000B = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000008, ); defaultConfigurationName = Debug; };
            	};
            	rootObject = F00000000000000000000006;
            }
            """
        }
        try Self.write([
            "W.xcworkspace/contents.xcworkspacedata": #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:One/P.xcodeproj"></FileRef><FileRef location = "group:Two/P.xcodeproj"></FileRef></Workspace>"#,
            "One/P.xcodeproj/project.pbxproj": project("One"),
            "Two/P.xcodeproj/project.pbxproj": project("Two"),
        ], to: directory.path)
        let document = try Self.generate(directory.path + "/W.xcworkspace")
        for folder in ["One", "Two"] {
            let buildFiles = try Self.target(document, folder + "App")["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"]
            #expect(buildFiles == .array([.object([
                "guid": .string(MD5.hex(folder + "/P.xcodeproj") + MD5.hex("B00000000000000000000001")),
                "targetReference": .string(MD5.hex(folder + "/P.xcodeproj") + MD5.hex("C00000000000000000000002")),
            ])]))
        }
    }

    @Test func aggregateTargetsAndBuildRules() throws {
        let directory = try TemporaryDirectory()
        let objects = """
        		B00000000000000000000001 = {isa = PBXBuildRule; compilerSpec = com.apple.compilers.proxy.script; filePatterns = "*.foo"; fileType = pattern.proxy; isEditable = 1; outputFiles = ("$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).swift", ); script = "true"; };
        		C00000000000000000000002 = {isa = PBXAggregateTarget; buildConfigurationList = F0000000000000000000000C; buildPhases = (); dependencies = (); name = Agg; productName = Agg; };
        		F00000000000000000000009 = {isa = XCBuildConfiguration; buildSettings = {}; name = Debug; };
        		F0000000000000000000000C = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000009, ); defaultConfigurationName = Debug; };
        """
        try Self.write(["P.xcodeproj/project.pbxproj": Self.project(objects: objects, targets: ["C00000000000000000000002"], appExtra: "buildRules = (B00000000000000000000001, );")], to: directory.path)
        let document = try Self.generate(directory.path + "/P.xcodeproj")
        let rule = try #require(try Self.target(document, "App")["buildRules"]?.arrayValue?.first?.objectValue)
        // An unnamed rule gets Xcode's name (loader-experiments `build-rules`; gomap).
        #expect(rule["name"] == .string("Files '*.foo' using Script"))
        #expect(ProjectGenerator.buildRuleName(compiler: "com.apple.compilers.llvm.clang.1_0", fileType: "sourcecode.c.c", filePatterns: nil) == "C source files using Apple Clang")
        #expect(ProjectGenerator.buildRuleName(compiler: "com.apple.xcode.tools.ibtool.compiler", fileType: "text.json", filePatterns: nil) == "(null) using com.apple.xcode.tools.ibtool.compiler")
        #expect(rule["inputFileListPaths"] == .array([]))
        #expect(rule["outputFileListPaths"] == .array([]))
        let aggregate = try Self.target(document, "Agg")
        #expect(aggregate["buildRules"] == .array([]))
        #expect(aggregate["provisioningSourceData"] == .array([.object([
            "bundleIdentifierFromInfoPlist": .string(""), "configurationName": .string("Debug"), "provisioningStyle": .int(0),
        ])]))
    }

    /// loader-experiments `file-encodings`; cwa's `.xib` files.
    @Test func fileTextEncodingDependsOnTheFileType() throws {
        let directory = try TemporaryDirectory()
        let objects = ["sourcecode.swift", "file.xib", "file", "image.png"].enumerated().map { index, type in
            "\t\tB0000000000000000000000\(index) = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = \(type); path = f\(index); sourceTree = \"<group>\"; };"
        }.joined(separator: "\n")
        try Self.write(["P.xcodeproj/project.pbxproj": Self.project(objects: objects, groupChildren: (0..<4).map { "B0000000000000000000000\($0), " }.joined())], to: directory.path)
        let tree = try #require(try Self.generate(directory.path + "/P.xcodeproj").objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue)
        let files = (tree["children"]?.arrayValue ?? []).compactMap(\.objectValue).filter { $0["path"]?.stringValue?.hasPrefix("f") == true }
        #expect(files.map { $0["fileTextEncoding"]?.stringValue } == ["utf-8", nil, "utf-8", nil])
    }

    /// loader-experiments `copy-files`, `copy-files-18`; wikipedia's man pages (spec 0 with an
    /// absolute dstPath).
    @Test func copyFilesDestinationsBySubfolderSpec() throws {
        func destinations(_ specs: [Int?]) throws -> [PIFValue?] {
            let directory = try TemporaryDirectory()
            let ids = specs.indices.map { String(format: "B%023d", $0) }
            let objects = zip(ids, specs).map { id, spec in
                "\t\t\(id) = {isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = /usr/share/man/man1/; \(spec.map { "dstSubfolderSpec = \($0); " } ?? "")files = (); runOnlyForDeploymentPostprocessing = 0; };"
            }.joined(separator: "\n")
            let project = Self.project(objects: objects).replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (\(ids.map { $0 + ", " }.joined()));")
            try Self.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
            let phases = try Self.target(try Self.generate(directory.path + "/P.xcodeproj"), "App")["buildPhases"]?.arrayValue ?? []
            #expect(phases.allSatisfy { $0.objectValue?["destinationSubpath"] == .string("/usr/share/man/man1/") })
            return phases.map { $0.objectValue?["destinationSubfolder"] }
        }
        let expected = ["", "$(WRAPPER_NAME)", "$(INFOPLIST_PATH)", "$(PKGINFO_PATH)", "$(EXECUTABLE_PATH)", "$(CONTENTS_FOLDER_PATH)",
                        "$(EXECUTABLE_FOLDER_PATH)", "$(UNLOCALIZED_RESOURCES_FOLDER_PATH)", "$(PUBLIC_HEADERS_FOLDER_PATH)",
                        "$(PRIVATE_HEADERS_FOLDER_PATH)", "$(FRAMEWORKS_FOLDER_PATH)", "$(SHARED_FRAMEWORKS_FOLDER_PATH)",
                        "$(SHARED_SUPPORT_FOLDER_PATH)", "$(PLUGINS_FOLDER_PATH)", "$(SCRIPTS_FOLDER_PATH)", "$(JAVA_FOLDER_PATH)",
                        "<builtProductsDir>", "$(EXECUTABLE_PATH)", ""]
        #expect(try destinations(Array(0...17) + [nil]) == expected.map { .string($0) })
        #expect(throws: NomacError.self) { try destinations([18]) }
    }

    /// loader-experiments `provisioning-style`; cwa (CODE_SIGN_STYLE), netnewswire (the attribute).
    @Test func provisioningStyleFollowsCodeSignStyleThenTheAttribute() throws {
        func style(settings: String, attribute: String?) throws -> PIFValue? {
            let directory = try TemporaryDirectory()
            let attributes = attribute.map { "attributes = {TargetAttributes = {C00000000000000000000001 = {ProvisioningStyle = \($0); }; }; };" } ?? ""
            try Self.write(["P.xcodeproj/project.pbxproj": Self.project(settings: settings, projectReferences: attributes)], to: directory.path)
            return try Self.target(try Self.generate(directory.path + "/P.xcodeproj"), "App")["provisioningSourceData"]?.arrayValue?.first?.objectValue?["provisioningStyle"]
        }
        #expect(try style(settings: "CODE_SIGN_STYLE = Manual;", attribute: nil) == .int(1))
        #expect(try style(settings: "CODE_SIGN_STYLE = manual;", attribute: nil) == .int(0))
        #expect(try style(settings: "CODE_SIGN_STYLE = Automatic;", attribute: "Manual") == .int(0))
        #expect(try style(settings: "", attribute: "Manual") == .int(1))
        #expect(try style(settings: #"CODE_SIGN_STYLE = "";"#, attribute: "Manual") == .int(1))
    }

    /// loader-experiments `provisioning-profile`, `provisioning-profile-project`.
    @Test func aProvisioningProfileMakesATargetWithoutStyleManual() throws {
        func styles(debug: String, release: String, attribute: String? = nil) throws -> [PIFValue?] {
            let directory = try TemporaryDirectory()
            let attributes = attribute.map { "attributes = {TargetAttributes = {C00000000000000000000001 = {ProvisioningStyle = \($0); }; }; };" } ?? ""
            let releaseConfiguration = "\t\tF00000000000000000000009 = {isa = XCBuildConfiguration; buildSettings = {\(release) }; name = Release; };"
            let project = Self.project(settings: debug, objects: releaseConfiguration, projectReferences: attributes)
                .replacingOccurrences(of: "buildConfigurations = (F00000000000000000000007, );", with: "buildConfigurations = (F00000000000000000000007, F00000000000000000000009, );")
            try Self.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
            let data = try Self.target(try Self.generate(directory.path + "/P.xcodeproj"), "App")["provisioningSourceData"]?.arrayValue ?? []
            return data.map { $0.objectValue?["provisioningStyle"] }
        }
        let profile = #"PROVISIONING_PROFILE_SPECIFIER = "Some Profile";"#
        #expect(try styles(debug: "", release: profile) == [.int(1), .int(1)])
        #expect(try styles(debug: "CODE_SIGN_STYLE = Automatic;", release: profile) == [.int(0), .int(1)])
        #expect(try styles(debug: "", release: #"CODE_SIGN_STYLE = Automatic; PROVISIONING_PROFILE = " ";"#) == [.int(1), .int(0)])
        #expect(try styles(debug: "CODE_SIGN_STYLE = manual;", release: #"CODE_SIGN_STYLE = ""; "# + profile) == [.int(0), .int(1)])
        #expect(try styles(debug: "", release: profile, attribute: "Automatic") == [.int(0), .int(0)])
        #expect(try styles(debug: "", release: #"PROVISIONING_PROFILE_SPECIFIER = ""; CODE_SIGN_IDENTITY = "iPhone Distribution"; DEVELOPMENT_TEAM = ABCDE12345;"#) == [.int(0), .int(0)])
    }

    /// Settings written with an SDK condition, at any level, are left to Swift Build; profiles
    /// only where the target's style can come from them (loader-experiments `provisioning-fallback`,
    /// `provisioning-profile`, `infoplist-macros`; mastodon's `PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]`).
    @Test func conditionalSettingsAreEvaluated() throws {
        func queued(settings: String, xcconfig: String? = nil, attribute: String? = nil) throws -> [String] {
            let directory = try TemporaryDirectory()
            let attributes = attribute.map { "attributes = {TargetAttributes = {C00000000000000000000001 = {ProvisioningStyle = \($0); }; }; };" } ?? ""
            var project = Self.project(settings: settings, projectReferences: attributes)
            if let xcconfig {
                try Self.write(["Base.xcconfig": xcconfig], to: directory.path)
                project = Self.project(settings: settings, objects: "\t\tB00000000000000000000001 = {isa = PBXFileReference; path = Base.xcconfig; sourceTree = \"<group>\"; };",
                                       groupChildren: "B00000000000000000000001, ", projectReferences: attributes)
                    .replacingOccurrences(of: "F00000000000000000000007 = {isa = XCBuildConfiguration;", with: "F00000000000000000000007 = {isa = XCBuildConfiguration; baseConfigurationReference = B00000000000000000000001;")
            }
            try Self.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
            var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj"))
            _ = try generator.generate()
            return generator.unevaluatedSettings.map(\.configuration)
        }
        let profile = #""PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" = "Some Profile";"#
        #expect(try queued(settings: profile) == ["Debug"])
        #expect(try queued(settings: #""CODE_SIGN_STYLE[sdk=iphoneos*]" = Manual;"#) == ["Debug"])
        #expect(try queued(settings: #""INFOPLIST_FILE[sdk=iphoneos*]" = App/Info.plist;"#) == ["Debug"])
        #expect(try queued(settings: "", xcconfig: "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] = Some Profile\n") == ["Debug"])
        #expect(try queued(settings: "CODE_SIGN_STYLE = Automatic; " + profile).isEmpty)
        #expect(try queued(settings: profile, attribute: "Manual").isEmpty)
        #expect(try queued(settings: #"PROVISIONING_PROFILE_SPECIFIER = "Some Profile";"#).isEmpty)
        // Without a style or a profile as written, the identity decides (`provisioning-defaults`).
        #expect(try queued(settings: "") == ["Debug"])
    }

    /// loader-experiments `intents-codegen`, `codegen-file-types`; mastodon's `(codegen)`.
    @Test func codegenVisibilityFollowsTheFileTypeAndTheAttributes() {
        func visibility(_ fileType: String?, _ attributes: [String] = []) -> String? {
            ProjectGenerator.intentsCodegenVisibility(fileType: fileType, attributes: attributes)
        }
        #expect(visibility("file.intentdefinition") == "public")
        #expect(visibility("file.mlmodel") == "project")
        #expect(visibility("folder.mlpackage") == "project")
        #expect(visibility("wrapper.mlmodelc") == nil)
        #expect(visibility("sourcecode.swift", ["codegen"]) == nil)
        #expect(visibility(nil) == nil)
        #expect(visibility("file.mlmodel", ["codegen"]) == "public")
        #expect(visibility("file.intentdefinition", ["codegen", "no_codegen"]) == "no_codegen")
        #expect(visibility("file.intentdefinition", ["project_codegen", "private_codegen"]) == "private")
        #expect(visibility("file.intentdefinition", ["codegen", "private_codegen"]) == "public")
        #expect(visibility("file.mlmodel", ["project_codegen"]) == "project")
        #expect(visibility("file.intentdefinition", ["CodeSignOnCopy", "codegen"]) == "public")
        #expect(visibility("file.intentdefinition", ["Project", "Foo", "codegen"]) == "public")
        #expect(visibility("file.intentdefinition", ["Weak", "codegen"]) == nil)
        #expect(visibility("file.intentdefinition", ["Public", "no_codegen"]) == nil)
        #expect(visibility("file.intentdefinition", ["Private", "codegen"]) == nil)
        #expect(visibility("file.intentdefinition", ["CodeSignOnCopy"]) == nil)
        #expect(visibility("file.intentdefinition", ["public_codegen"]) == nil)
        #expect(visibility("file.intentdefinition", ["Codegen"]) == nil)
    }

    /// loader-experiments `intents-codegen` and `variant-regions`: only Sources build files carry
    /// the key; a variant group takes its Base variant's type, the variant's region being its
    /// `.lproj` folder (nextcloud's `Intent.intentdefinition`).
    @Test func sourcesBuildFilesOfIntentDefinitionsCarryTheirCodegenVisibility() throws {
        let directory = try TemporaryDirectory()
        let objects = """
        \t\tB00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = file.intentdefinition; path = I.intentdefinition; sourceTree = "<group>"; };
        \t\tB00000000000000000000002 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = en.lproj/V.strings; sourceTree = "<group>"; };
        \t\tB00000000000000000000003 = {isa = PBXFileReference; lastKnownFileType = file.intentdefinition; name = Base; path = Base.lproj/V.intentdefinition; sourceTree = "<group>"; };
        \t\tB00000000000000000000004 = {isa = PBXVariantGroup; children = (B00000000000000000000002, B00000000000000000000003, ); name = V.intentdefinition; sourceTree = "<group>"; };
        \t\tB00000000000000000000005 = {isa = PBXFileReference; lastKnownFileType = file.intentdefinition; name = Base; path = fr.lproj/W.intentdefinition; sourceTree = "<group>"; };
        \t\tB00000000000000000000006 = {isa = PBXVariantGroup; children = (B00000000000000000000005, ); name = W.intentdefinition; sourceTree = "<group>"; };
        \t\tB10000000000000000000001 = {isa = PBXBuildFile; fileRef = B00000000000000000000001; settings = {ATTRIBUTES = (CodeSignOnCopy, codegen, ); }; };
        \t\tB10000000000000000000004 = {isa = PBXBuildFile; fileRef = B00000000000000000000004; };
        \t\tB10000000000000000000006 = {isa = PBXBuildFile; fileRef = B00000000000000000000006; };
        \t\tB20000000000000000000001 = {isa = PBXBuildFile; fileRef = B00000000000000000000001; };
        \t\tF00000000000000000000005 = {isa = PBXResourcesBuildPhase; files = (B20000000000000000000001, ); };
        """
        let project = Self.project(objects: objects, groupChildren: "B00000000000000000000001, B00000000000000000000004, B00000000000000000000006, ")
            .replacingOccurrences(of: "files = (A00000000000000000000003, );", with: "files = (A00000000000000000000003, B10000000000000000000001, B10000000000000000000004, B10000000000000000000006, );")
            .replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (F00000000000000000000004, F00000000000000000000005, );")
        try Self.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
        let document = try Self.generate(directory.path + "/P.xcodeproj")
        let phases = (try Self.target(document, "App")["buildPhases"]?.arrayValue ?? []).compactMap(\.objectValue)
        #expect(phases.map { ($0["buildFiles"]?.arrayValue ?? []).map { $0.objectValue?["intentsCodegenVisibility"]?.stringValue } } == [[nil, "public", "public", nil], [nil]])
        let tree = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue)
        let regions = (tree["children"]?.arrayValue ?? []).compactMap(\.objectValue).filter { $0["type"] == .string("variantGroup") }
            .map { ($0["children"]?.arrayValue ?? []).map { $0.objectValue?["regionVariantName"]?.stringValue } }
        #expect(regions == [["en", "Base"], ["fr"]])
    }

    /// loader-experiments `source-languages`: headers count for Objective-C++ (cwa's CWASQLite),
    /// ties go to the first language name.
    @Test func predominantLanguageCountsHeaders() throws {
        func language(headers: Int) throws -> PIFValue? {
            let directory = try TemporaryDirectory()
            var objects = "\t\tF00000000000000000000005 = {isa = PBXHeadersBuildPhase; files = (\((0..<headers).map { "B1000000000000000000000\($0), " }.joined())); };\n"
            for index in 0..<headers {
                objects += "\t\tB0000000000000000000000\(index) = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = h\(index).h; sourceTree = \"<group>\"; };\n"
                objects += "\t\tB1000000000000000000000\(index) = {isa = PBXBuildFile; fileRef = B0000000000000000000000\(index); };\n"
            }
            let project = Self.project(objects: objects).replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (F00000000000000000000004, F00000000000000000000005, );")
            try Self.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
            return try Self.target(try Self.generate(directory.path + "/P.xcodeproj"), "App")["predominantSourceCodeLanguage"]
        }
        #expect(try language(headers: 0) == .string("Xcode.SourceCodeLanguage.Swift"))
        #expect(try language(headers: 1) == .string("Xcode.SourceCodeLanguage.Objective-C-Plus-Plus"))
        #expect(try language(headers: 2) == .string("Xcode.SourceCodeLanguage.Objective-C-Plus-Plus"))
    }

    /// Group-tree file types by path, and the document, of a project whose references declare
    /// `declared` ([(path, attributes, source tree)]) next to `files` on disk, with more
    /// `objects`, main group `children` and build `phases` of the app.
    static func referenceTypes(_ declared: [(String, String, String)], files: [String: String], objects extra: String = "",
                               children: String = "", phases: String = "") throws -> (types: [String: String], document: PIFDocument) {
        let directory = try TemporaryDirectory()
        var objects = extra
        for (index, (path, attributes, tree)) in declared.enumerated() {
            objects += "\t\tB\(String(format: "%023d", index)) = {isa = PBXFileReference; \(attributes) path = \"\(path)\"; sourceTree = \"\(tree)\"; };\n"
        }
        let groupChildren = declared.indices.map { "B\(String(format: "%023d", $0)), " }.joined() + children
        let project = Self.project(objects: objects, groupChildren: groupChildren)
            .replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (F00000000000000000000004, \(phases));")
        try Self.write(files.merging(["P.xcodeproj/project.pbxproj": project]) { $1 }, to: directory.path)
        let document = try Self.generate(directory.path + "/P.xcodeproj")
        var types: [String: String] = [:]
        func walk(_ node: [String: PIFValue]) {
            for child in (node["children"]?.arrayValue ?? []).compactMap(\.objectValue) {
                if let path = child["path"]?.stringValue, let type = child["fileType"]?.stringValue { types[path] = type }
                walk(child)
            }
        }
        walk(try #require(document.objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue))
        return (types, document)
    }

    /// loader-experiments `declared-types`: Xcode keeps a declared type it knows, whatever is on
    /// disk, and types a reference whose type it does not know from disk (signal's module maps,
    /// `sourcecode.module`; `wrapper.mlmodelc` on a plain file). `file` and
    /// `wrapper.framework.static` are typed again as lastKnownFileType, not as explicitFileType.
    @Test func declaredTypesXcodeDoesNotKnowAreTypedFromDisk() throws {
        let group = "<group>"
        let (types, _) = try Self.referenceTypes([
            ("Signal.modulemap", "lastKnownFileType = sourcecode.module;", group),
            ("m.zzz", "lastKnownFileType = sourcecode.module;", group),
            ("N.mlmodelc", "lastKnownFileType = wrapper.mlmodelc;", group),
            ("D.mlmodelc", "lastKnownFileType = wrapper.mlmodelc;", group),
            ("Dir", "lastKnownFileType = nomac.unknown;", group),
            ("a.swift", "lastKnownFileType = file;", group),
            ("b.swift", "explicitFileType = file;", group),
            ("blob.zzz", "lastKnownFileType = file;", group),
            ("Gone.framework", "lastKnownFileType = wrapper.framework.static;", group),
            ("Static.framework", "explicitFileType = wrapper.framework.static;", group),
            ("F.framework", "lastKnownFileType = wrapper.framework;", group),
            ("k.swift", "lastKnownFileType = sourcecode.c.objc;", group),
            ("e.swift", "explicitFileType = nomac.unknown; lastKnownFileType = sourcecode.c.objc;", group),
            ("n.swift", "", group),
            ("gone", "", group),
            ("Trees/binary", "lastKnownFileType = nomac.unknown;", "SOURCE_ROOT"),
            ("gen.modulemap", "lastKnownFileType = sourcecode.module;", "BUILT_PRODUCTS_DIR"),
            ("gen-text", "lastKnownFileType = file;", "BUILT_PRODUCTS_DIR"),
        ], files: ["Signal.modulemap": "framework module Signal {}\n", "m.zzz": "module M {}\n", "N.mlmodelc": "x\n", "D.mlmodelc/x": "x\n",
                   "Dir/x": "x\n", "a.swift": "let a = 1\n", "b.swift": "let b = 1\n", "blob.zzz": "a\u{0}\u{1}b\n", "F.framework": "x\n",
                   "k.swift": "let k = 1\n", "e.swift": "let e = 1\n", "Trees/binary": "a\u{0}\u{1}b\n"])
        #expect(types["Signal.modulemap"] == "sourcecode.module-map")
        #expect(types["m.zzz"] == "text")
        #expect(types["N.mlmodelc"] == "text")
        #expect(types["D.mlmodelc"] == "wrapper")
        #expect(types["Dir"] == "folder")
        #expect(types["a.swift"] == "sourcecode.swift")
        #expect(types["b.swift"] == "file")
        #expect(types["blob.zzz"] == "file")
        #expect(types["Gone.framework"] == "wrapper.framework")
        #expect(types["Static.framework"] == "wrapper.framework.static")
        #expect(types["F.framework"] == "wrapper.framework")
        #expect(types["k.swift"] == "sourcecode.c.objc")
        #expect(types["e.swift"] == "sourcecode.c.objc")
        #expect(types["n.swift"] == "sourcecode.swift")
        #expect(types["gone"] == "text")
        #expect(types["Trees/binary"] == "file")
        #expect(types["gen.modulemap"] == "sourcecode.module-map")
        #expect(types["gen-text"] == "text")
    }

    /// pif-experiments `explicit-types`: a synchronized folder's `explicitFileTypes` give a type
    /// Xcode knows, `file` included; with one it does not know, the item is typed from disk.
    @Test func synchronizedExplicitTypesXcodeDoesNotKnow() throws {
        let root = """
        		S00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {unknown.swift = nomac.unknown; file.swift = file; known.zzz = sourcecode.swift; Unknown.mlmodelc = wrapper.mlmodelc; }; path = Src; sourceTree = "<group>"; };

        """
        let (types, _) = try Self.referenceTypes([], files: ["Src/unknown.swift": "let u = 1\n", "Src/file.swift": "let f = 1\n", "Src/known.zzz": "let k = 1\n",
                                                             "Src/Unknown.mlmodelc": "x\n"], objects: root, children: "S00000000000000000000001, ")
        #expect(types["unknown.swift"] == "sourcecode.swift")
        #expect(types["file.swift"] == "file")
        #expect(types["known.zzz"] == "sourcecode.swift")
        #expect(types["Unknown.mlmodelc"] == "text")
    }

    /// loader-experiments `declared-types-2` and `declared-language`: the type Xcode gives
    /// decides `fileTextEncoding` and the language a build file counts for (App.swift, two Swift
    /// files declared `file` and one Objective-C file: Swift, where a tie would give Objective-C).
    @Test func theTypeXcodeGivesDecidesEncodingAndLanguage() throws {
        let objects = """
        		A00000000000000000000005 = {isa = PBXBuildFile; fileRef = B00000000000000000000001; };
        		A00000000000000000000006 = {isa = PBXBuildFile; fileRef = B00000000000000000000002; };
        		A00000000000000000000007 = {isa = PBXBuildFile; fileRef = B00000000000000000000003; };
        		F00000000000000000000005 = {isa = PBXSourcesBuildPhase; files = (A00000000000000000000005, A00000000000000000000006, A00000000000000000000007, ); };

        """
        let (types, document) = try Self.referenceTypes([
            ("x.png", "fileEncoding = 4; lastKnownFileType = nomac.unknown;", "<group>"),
            ("x.swift", "lastKnownFileType = file;", "<group>"),
            ("y.swift", "lastKnownFileType = file;", "<group>"),
            ("z.m", "lastKnownFileType = sourcecode.c.objc;", "<group>"),
        ], files: ["x.png": "x\n", "x.swift": "let x = 1\n", "y.swift": "let y = 1\n", "z.m": "int z;\n"], objects: objects, phases: "F00000000000000000000005, ")
        #expect(types["x.png"] == "image.png")
        let tree = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue)
        let png = try #require(tree["children"]?.arrayValue?.compactMap(\.objectValue).first { $0["path"] == .string("x.png") })
        #expect(png["fileTextEncoding"] == nil)
        #expect(try Self.target(document, "App")["predominantSourceCodeLanguage"] == .string("Xcode.SourceCodeLanguage.Swift"))
    }

    /// loader-experiments `regions-classic` to `regions-classic-5`: the development region goes
    /// first when knownRegions lacks it; variant groups add the regions of their children's
    /// `.lproj` folders, Base included and `mul` excepted, whatever the children's names; a
    /// child outside a `.lproj` folder is listed before its variant group, which goes when no
    /// child is left; an empty variant group stays.
    @Test func variantGroupsAddTheirRegions() throws {
        let groups: [(String, [(String?, String)])] = [
            ("B.strings", [("Base", "Base.lproj/B.strings")]), ("I.strings", [("it", "it.lproj/I.strings")]),
            ("M.strings", [("ko", "ko.lproj/M.strings"), (nil, "M.strings"), ("ja", "ja.lproj/M.strings")]),
            ("R.strings", [(nil, "R.strings"), (nil, "sub/R.strings")]), ("F.strings", [("Foo", "es.lproj/F.strings")]),
            ("U.strings", [("mul", "mul.lproj/U.strings")]), ("E.strings", []),
        ]
        var objects = "", children = ""
        for (groupIndex, (name, variants)) in groups.enumerated() {
            var references = ""
            for (index, (region, path)) in variants.enumerated() {
                let id = "B\(groupIndex)\(String(format: "%022d", index))"
                let named = region.map { "name = \($0); " } ?? ""
                objects += "\t\t\(id) = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; \(named)path = \"\(path)\"; sourceTree = \"<group>\"; };\n"
                references += "\(id), "
            }
            let group = "V\(String(format: "%023d", groupIndex))"
            objects += "\t\t\(group) = {isa = PBXVariantGroup; children = (\(references)); name = \(name); sourceTree = \"<group>\"; };\n"
            children += "\(group), "
        }
        let directory = try TemporaryDirectory()
        let project = Self.project(objects: objects, groupChildren: children, projectReferences: "developmentRegion = pt; knownRegions = (fr, de, );")
        try Self.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
        let contents = try #require(try Self.generate(directory.path + "/P.xcodeproj").objects.first { $0.type == "project" }?.contents.objectValue)
        #expect(contents["knownRegions"] == .array(["pt", "fr", "de", "Base", "it", "ko", "ja", "es"].map(PIFValue.string)))
        let tree = (contents["groupTree"]?.objectValue?["children"]?.arrayValue ?? []).compactMap(\.objectValue).dropFirst()
        #expect(tree.map { $0["name"]?.stringValue ?? $0["path"]?.stringValue ?? "" } ==
                ["B.strings", "I.strings", "M.strings", "M.strings", "R.strings", "sub/R.strings", "F.strings", "U.strings", "E.strings", "Products"])
        #expect(tree.map { $0["type"]?.stringValue ?? "" } ==
                ["variantGroup", "variantGroup", "file", "variantGroup", "file", "file", "variantGroup", "variantGroup", "variantGroup", "group"])
        let regions = tree.map { ($0["children"]?.arrayValue ?? []).compactMap { $0.objectValue?["regionVariantName"]?.stringValue } }
        #expect(regions[3] == ["ko", "ja"])
        #expect(regions[6] == ["es"])
    }

    /// `pif-experiments` variants-order-fr: a synchronized variant group lists Base, then the
    /// development region, then the other regions in name order.
    @Test func synchronizedVariantsListBaseThenTheDevelopmentRegion() throws {
        let directory = try TemporaryDirectory()
        let root = "\t\tS00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; path = Alpha; sourceTree = \"<group>\"; };\n"
        var files = ["P.xcodeproj/project.pbxproj": Self.project(objects: root, groupChildren: "S00000000000000000000001, ",
                                                                  projectReferences: "developmentRegion = fr; knownRegions = (fr, en, Base, );")]
        for region in ["en-GB", "ab", "fr", "Base", "en", "de"] { files["Alpha/\(region).lproj/R.strings"] = "\"k\" = \"v\";\n" }
        try Self.write(files, to: directory.path)
        let contents = try #require(try Self.generate(directory.path + "/P.xcodeproj").objects.first { $0.type == "project" }?.contents.objectValue)
        let alpha = try #require(contents["groupTree"]?.objectValue?["children"]?.arrayValue?.compactMap(\.objectValue).first { $0["path"] == .string("Alpha") })
        let variants = try #require(alpha["children"]?.arrayValue?.first?.objectValue?["children"]?.arrayValue)
        #expect(variants.compactMap { $0.objectValue?["regionVariantName"]?.stringValue } == ["Base", "fr", "ab", "de", "en", "en-GB"])
    }

    /// `pif-experiments` round 9: a synchronized folder's libraries and frameworks add search
    /// paths to the configurations of a target with a Frameworks phase, excluded members too,
    /// after a value the target has; only without a Frameworks phase does nothing change.
    @Test func synchronizedLibrariesAddSearchPaths() throws {
        func settings(frameworksPhase: Bool) throws -> [String: PIFValue] {
            let directory = try TemporaryDirectory()
            let objects = """
            \t\tS00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000001, ); path = Src; sourceTree = "<group>"; };
            \t\tE00000000000000000000001 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (excluded/libX.a, ); target = C00000000000000000000001; };
            \t\tF00000000000000000000005 = {isa = PBXFrameworksBuildPhase; files = (); };

            """
            var project = Self.project(settings: "LIBRARY_SEARCH_PATHS = /opt/lib;", objects: objects, groupChildren: "S00000000000000000000001, ",
                                       appExtra: "fileSystemSynchronizedGroups = (S00000000000000000000001, );")
            if frameworksPhase {
                project = project.replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (F00000000000000000000004, F00000000000000000000005, );")
            }
            try Self.write(["P.xcodeproj/project.pbxproj": project, "Src/libA.a": "!<arch>\n", "Src/object.dylib": "x\n", "Src/excluded/libX.a": "!<arch>\n",
                            "Src/My Libs/libB.a": "!<arch>\n", "Src/sub/E.framework/E": "x\n", "Src/F.xcframework/Info.plist": "x\n", "Src/a.swift": "let a = 1\n"],
                           to: directory.path)
            let app = try Self.target(try Self.generate(directory.path + "/P.xcodeproj"), "App")
            return try #require(app["buildConfigurations"]?.arrayValue?.first?.objectValue?["buildSettings"]?.objectValue)
        }
        let withPhase = try settings(frameworksPhase: true)
        #expect(withPhase["LIBRARY_SEARCH_PATHS"] == .string(#"/opt/lib $(PROJECT_DIR)/Src/excluded $(PROJECT_DIR)/Src/My\ Libs $(PROJECT_DIR)/Src"#))
        #expect(withPhase["FRAMEWORK_SEARCH_PATHS"] == .string("$(inherited) $(PROJECT_DIR)/Src/sub"))
        let withoutPhase = try settings(frameworksPhase: false)
        #expect(withoutPhase["LIBRARY_SEARCH_PATHS"] == .string("/opt/lib"))
        #expect(withoutPhase["FRAMEWORK_SEARCH_PATHS"] == nil)
        #expect(ProjectGenerator.addingSearchPaths(["$(PROJECT_DIR)/Src"], to: "$(inherited) $(PROJECT_DIR)/Src") == "$(inherited) $(PROJECT_DIR)/Src")
        let unicode = try TemporaryDirectory()
        let objects = "\t\tS00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; path = Src; sourceTree = \"<group>\"; };\n"
            + "\t\tF00000000000000000000005 = {isa = PBXFrameworksBuildPhase; files = (); };\n"
        let project = Self.project(objects: objects, groupChildren: "S00000000000000000000001, ", appExtra: "fileSystemSynchronizedGroups = (S00000000000000000000001, );")
            .replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (F00000000000000000000004, F00000000000000000000005, );")
        try Self.write(["P.xcodeproj/project.pbxproj": project, "Src/H\u{EB}aders/libA.a": "!<arch>\n"], to: unicode.path)
        let app = try Self.target(try Self.generate(unicode.path + "/P.xcodeproj"), "App")
        let decomposed = try #require(app["buildConfigurations"]?.arrayValue?.first?.objectValue?["buildSettings"]?.objectValue?["LIBRARY_SEARCH_PATHS"]?.stringValue)
        #expect(decomposed.unicodeScalars.elementsEqual("$(inherited) $(PROJECT_DIR)/Src/He\u{308}aders".unicodeScalars))
        #expect(ProjectGenerator.addingSearchPaths(["$(PROJECT_DIR)/Src"], to: "$(PROJECT_DIR)/Src") == "$(PROJECT_DIR)/Src")
    }

    /// `pif-experiments` libraries-folder-paths: a synchronized folder without a name is named
    /// after its whole path.
    @Test func synchronizedFoldersAreNamedByTheirPath() throws {
        let root = "\t\tS00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; path = Outer/Libs; sourceTree = \"<group>\"; };\n"
        let (_, document) = try Self.referenceTypes([], files: ["Outer/Libs/a.swift": "let a = 1\n"], objects: root, children: "S00000000000000000000001, ")
        let tree = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue)
        let folder = try #require(tree["children"]?.arrayValue?.compactMap(\.objectValue).first { $0["path"] == .string("Outer/Libs") })
        #expect(folder["name"] == .string("Outer/Libs"))
    }

    @Test func versionGroupsTakeTheTypeOfTheirExtension() throws {
        let directory = try TemporaryDirectory()
        let objects = """
        		A00000000000000000000005 = {isa = PBXFileReference; lastKnownFileType = wrapper.xcdatamodel; path = Model.xcdatamodel; sourceTree = "<group>"; };
        		A00000000000000000000002 = {isa = XCVersionGroup; children = (A00000000000000000000005, ); currentVersion = A00000000000000000000005; path = Model.xcdatamodeld; sourceTree = "<group>"; versionGroupType = wrapper.xcdatamodel; };
        """
        try Self.write(["P.xcodeproj/project.pbxproj": Self.project(objects: objects, groupChildren: "A00000000000000000000002, ")], to: directory.path)
        let document = try Self.generate(directory.path + "/P.xcodeproj")
        let tree = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue)
        let group = try #require(tree["children"]?.arrayValue?.compactMap(\.objectValue).first { $0["type"] == .string("versionGroup") })
        #expect(group["fileType"] == .string("wrapper.xcdatamodeld"))
    }

    /// loader-experiments `variant-build-files`: a build file that names a variant group names
    /// its children outside `.lproj` folders, then the group unless they were all its children;
    /// a Sources build file of an intent definition child carries its codegen visibility.
    @Test func buildFilesOfVariantGroupsNameTheirChildrenOutsideLprojFolders() throws {
        let groups: [(String, [(String, String)], String)] = [
            ("V1.strings", [("V1.strings", "text.plist.strings")], "R"), ("V2.strings", [("fr.lproj/V2.strings", "text.plist.strings"), ("V2.strings", "text.plist.strings")], "R"),
            ("V3.strings", [("a/V3.strings", "text.plist.strings"), ("b/V3.strings", "text.plist.strings")], "R"), ("V4.strings", [], "R"),
            ("V6.intentdefinition", [("V6.intentdefinition", "file.intentdefinition")], "S"),
        ]
        var objects = "", children = "", resources = "", sources = ""
        for (groupIndex, (name, variants, phase)) in groups.enumerated() {
            var references = ""
            for (index, (path, type)) in variants.enumerated() {
                let id = "B\(groupIndex)\(String(format: "%022d", index))"
                objects += "\t\t\(id) = {isa = PBXFileReference; lastKnownFileType = \(type); path = \"\(path)\"; sourceTree = \"<group>\"; };\n"
                references += "\(id), "
            }
            let group = "V\(String(format: "%023d", groupIndex))", buildFile = "Y\(String(format: "%023d", groupIndex))"
            objects += "\t\t\(group) = {isa = PBXVariantGroup; children = (\(references)); name = \(name); sourceTree = \"<group>\"; };\n"
            objects += "\t\t\(buildFile) = {isa = PBXBuildFile; fileRef = \(group); };\n"
            children += "\(group), "
            if phase == "R" { resources += "\(buildFile), " } else { sources += "\(buildFile), " }
        }
        objects += "\t\tF00000000000000000000005 = {isa = PBXResourcesBuildPhase; files = (\(resources)); };\n"
        let directory = try TemporaryDirectory()
        let project = Self.project(objects: objects, groupChildren: children)
            .replacingOccurrences(of: "files = (A00000000000000000000003, );", with: "files = (A00000000000000000000003, \(sources));")
            .replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (F00000000000000000000004, F00000000000000000000005, );")
        try Self.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
        let document = try Self.generate(directory.path + "/P.xcodeproj")
        let projectGUID = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue?["guid"]?.stringValue)
        let phases = try #require(try Self.target(document, "App")["buildPhases"]?.arrayValue?.compactMap(\.objectValue))
        let ids = { (index: Int) in (phases[index]["buildFiles"]?.arrayValue ?? []).compactMap(\.objectValue) }
        let guid = { (id: String) in PIFIdentifiers.objectGUID(projectGUID: projectGUID, objectID: id) }
        #expect(ids(1).map { $0["fileReference"]?.stringValue } == ["B0" + String(repeating: "0", count: 22), "B1" + String(repeating: "0", count: 21) + "1",
                                                                    "V" + String(repeating: "0", count: 22) + "1", "B2" + String(repeating: "0", count: 22),
                                                                    "B2" + String(repeating: "0", count: 21) + "1", "V" + String(repeating: "0", count: 22) + "3"].map(guid))
        #expect(ids(1)[2]["guid"] == .string(guid("Y" + String(repeating: "0", count: 22) + "1")))
        #expect(Set(ids(1).compactMap { $0["guid"]?.stringValue }).count == 6)
        #expect(ids(0)[1]["fileReference"] == .string(guid("B4" + String(repeating: "0", count: 22))))
        #expect(ids(0)[1]["intentsCodegenVisibility"] == .string("public"))
    }

    /// loader-experiments `lproj-groups`: a child is in a `.lproj` folder when the path it
    /// resolves to, through its groups, is (mattermost's `Localizable.strings` in a group whose
    /// path is `ar.lproj`); a child the variant group does not keep is listed under the variant
    /// group's path.
    @Test func variantGroupChildrenAreInTheLprojFolderTheirGroupsName() throws {
        let groups: [(name: String, path: String?, variantPath: String?, child: String)] = [
            ("ar.lproj", "x/ar.lproj", nil, "L1.strings"), ("it.lproj", nil, nil, "L3.strings"), ("es.lproj", "es.lproj", "sub", "L4.strings"),
        ]
        var objects = "", children = ""
        for (index, group) in groups.enumerated() {
            let id = String(format: "%023d", index)
            objects += "\t\tB\(id) = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = ar; path = \(group.child); sourceTree = \"<group>\"; };\n"
            objects += "\t\tV\(id) = {isa = PBXVariantGroup; children = (B\(id), ); name = \(group.child); " + (group.variantPath.map { "path = \($0); " } ?? "")
                + "sourceTree = \"<group>\"; };\n"
            objects += "\t\tG\(id) = {isa = PBXGroup; children = (V\(id), ); name = \(group.name); " + (group.path.map { "path = \"\($0)\"; " } ?? "")
                + "sourceTree = \"<group>\"; };\n"
            children += "G\(id), "
        }
        let directory = try TemporaryDirectory()
        try Self.write(["P.xcodeproj/project.pbxproj": Self.project(objects: objects, groupChildren: children, projectReferences: "knownRegions = (en, Base, );")],
                       to: directory.path)
        let contents = try #require(try Self.generate(directory.path + "/P.xcodeproj").objects.first { $0.type == "project" }?.contents.objectValue)
        let tree = (contents["groupTree"]?.objectValue?["children"]?.arrayValue ?? []).compactMap(\.objectValue)
        let inner = tree.dropFirst().prefix(3).map { $0["children"]?.arrayValue?.first?.objectValue }
        #expect(inner.map { $0?["type"]?.stringValue } == ["variantGroup", "file", "file"])
        #expect(inner[0]?["children"]?.arrayValue?.first?.objectValue?["regionVariantName"] == .string("ar"))
        #expect(inner.map { $0?["path"]?.stringValue } == ["", "L3.strings", "sub/L4.strings"])
        #expect(contents["knownRegions"] == .array(["en", "Base", "ar"].map(PIFValue.string)))
    }

    /// loader-experiments `declared-encodings`: a reference typed `file` has no fileTextEncoding,
    /// whatever its declared type, while one typed `text` from disk keeps it (mattermost's fonts,
    /// declared `explicitFileType = undefined; lastKnownFileType = unknown; fileEncoding = 9`).
    @Test func filesTypedFileHaveNoTextEncoding() throws {
        let declared = ["explicitFileType = undefined; lastKnownFileType = unknown;", "lastKnownFileType = file;", "explicitFileType = file;",
                        "explicitFileType = undefined; lastKnownFileType = unknown;"]
        let paths = ["a.ttf", "b.ttf", "c.ttf", "d.ttf"]
        let objects = declared.enumerated().map { index, attributes in
            "\t\tB0000000000000000000000\(index) = {isa = PBXFileReference; \(attributes) fileEncoding = 9; path = \(paths[index]); sourceTree = \"<group>\"; };"
        }.joined(separator: "\n")
        let directory = try TemporaryDirectory()
        try Self.write(["P.xcodeproj/project.pbxproj": Self.project(objects: objects, groupChildren: (0..<4).map { "B0000000000000000000000\($0), " }.joined()),
                        "a.ttf": "\u{0}\u{1}binary\n", "b.ttf": "\u{0}\u{1}binary\n", "c.ttf": "\u{0}\u{1}binary\n", "d.ttf": "plain text\n"], to: directory.path)
        let tree = try #require(try Self.generate(directory.path + "/P.xcodeproj").objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue)
        let files = (tree["children"]?.arrayValue ?? []).compactMap(\.objectValue).filter { $0["path"]?.stringValue?.hasSuffix(".ttf") == true }
        #expect(files.map { $0["fileType"]?.stringValue } == ["file", "file", "file", "text"])
        #expect(files.map { $0["fileTextEncoding"]?.stringValue } == [nil, nil, nil, "iso-8859-2"])
    }

    /// loader-experiments `regions-case`, `-2`, `-4`, `-5`, `-6`: an ordinary variant group's
    /// regions are spelled as Foundation spells them on a Mac when that changes only case and
    /// separators, names of languages are kept, and equal spellings match; the development region
    /// is matched exactly.
    @Test func ordinaryRegionsAreSpelledCanonically() throws {
        let regions = ["de", "De", "pt-BR", "PT-br", "ZH-hans", "Es", "fr", "ENGLISH", "base", "Mul", "FR", "German", "german"]
        var objects = "", children = ""
        for (index, region) in regions.enumerated() {
            let id = String(format: "%023d", index)
            objects += "\t\tB\(id) = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; path = \"\(region).lproj/X\(index).strings\"; sourceTree = \"<group>\"; };\n"
            objects += "\t\tV\(id) = {isa = PBXVariantGroup; children = (B\(id), ); name = X\(index).strings; sourceTree = \"<group>\"; };\n"
            children += "V\(id), "
        }
        let directory = try TemporaryDirectory()
        let project = Self.project(objects: objects, groupChildren: children, projectReferences: "developmentRegion = EN; knownRegions = (en, Base, Fr, );")
        try Self.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
        let contents = try #require(try Self.generate(directory.path + "/P.xcodeproj").objects.first { $0.type == "project" }?.contents.objectValue)
        #expect(contents["knownRegions"] == .array(["EN", "en", "Base", "Fr", "de", "pt-BR", "zh-Hans", "es", "english", "German", "german"].map(PIFValue.string)))
        let spellings = ["English": "English", "French": "French", "Nynorsk": "Nynorsk", "FRENCH": "french", "Klingon": "klingon", "Brazilian": "brazilian",
                         "zh_hans": "zh-Hans", "Zh-HANT-tw": "zh-Hant-TW", "Sr-latn-RS": "sr-Latn-RS", "EN-us": "en-US", "Nl-be": "nl-BE",
                         "ES-419": "es-419", "aBc": "abc", "x-Private": "x-private", "Portuguese_BR": "portuguese_BR",
                         "Norwegian_Nynorsk": "norwegian-nynorsk", "Base": "Base", "BASE": "Base", "MUL": "mul"]
        for (region, spelling) in spellings {
            #expect(ProjectGenerator.canonicalRegion(region) == spelling, "\(region)")
        }
    }

    /// loader-experiments `language-types`, `language-pairs`, `language-weights`: files count by
    /// type, ties go by Xcode's order, and seven types count for languages the PIF leaves out.
    @Test func predominantLanguageCountsEachTypeApart() throws {
        func language(_ types: [String]) throws -> PIFValue? {
            let directory = try TemporaryDirectory()
            var objects = "", files = ""
            for (index, type) in types.enumerated() {
                let id = String(format: "%022d", index)
                objects += "\t\tB0\(id) = {isa = PBXFileReference; lastKnownFileType = \(type); path = f\(index); sourceTree = \"<group>\"; };\n"
                objects += "\t\tB1\(id) = {isa = PBXBuildFile; fileRef = B0\(id); };\n"
                files += "B1\(id), "
            }
            let project = Self.project(objects: objects).replacingOccurrences(of: "files = (A00000000000000000000003, );", with: "files = (\(files));")
            try Self.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
            return try Self.target(try Self.generate(directory.path + "/P.xcodeproj"), "App")["predominantSourceCodeLanguage"]
        }
        let swift = "sourcecode.swift"
        #expect(try language([swift, swift, swift, "sourcecode.c.h", "sourcecode.c.h", "sourcecode.cpp.objcpp", "sourcecode.cpp.objcpp"])
                == .string("Xcode.SourceCodeLanguage.Swift"))
        #expect(try language(["sourcecode.c.c", "sourcecode.nasm"]) == .string("Xcode.SourceCodeLanguage.Intel-Assembly"))
        #expect(try language(["sourcecode.cpp.cpp", "sourcecode.clips"]) == .string("Xcode.SourceCodeLanguage.Clips"))
        #expect(try language(["sourcecode.ada", swift]) == nil)
        #expect(try language(["sourcecode.rez", "sourcecode.protobuf"]) == .string("Xcode.SourceCodeLanguage.Protobuf"))
        #expect(try language(["sourcecode.rez", "sourcecode.rez", "sourcecode.protobuf"]) == nil)
        #expect(try language(["sourcecode.ada", "sourcecode.pascal", "sourcecode.c.objc", "sourcecode.c.objc"]) == .string("Xcode.SourceCodeLanguage.Objective-C"))
    }

    /// The differential fuzzer: synchronized members count for the language only when a phase
    /// of the target receives them.
    @Test func synchronizedMembersCountForTheLanguageInTheTargetsPhases() throws {
        let directory = try TemporaryDirectory()
        let objects = "\t\tS00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; path = Src; sourceTree = \"<group>\"; };\n"
            + "\t\tH00000000000000000000006 = {isa = PBXResourcesBuildPhase; files = (); };\n"
        let project = Self.project(objects: objects, groupChildren: "S00000000000000000000001, ", appExtra: "fileSystemSynchronizedGroups = (S00000000000000000000001, );")
            .replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (H00000000000000000000006, );")
        try Self.write(["P.xcodeproj/project.pbxproj": project, "Src/a.swift": "let a = 1\n", "Src/b.swift": "let b = 1\n", "Src/c.json": "{}\n"], to: directory.path)
        #expect(try Self.target(try Self.generate(directory.path + "/P.xcodeproj"), "App")["predominantSourceCodeLanguage"] == nil)
    }
}
