import Foundation
import Testing
import NomacCore
@testable import NomacPIF
import NomacProject
import NomacTestSupport

/// Target rules from `loader-experiments` (docs/formats/pif.md), on projects written here.
@Suite struct TargetRulesTests {
    struct Target {
        var id: String
        var name: String
        var productType = "com.apple.product-type.application"
        var productPath: String?
        /// Build settings by configuration name, in configuration order.
        var configurations: [(String, String)] = [("Debug", "")]
        var extra = ""
        /// The file reference of its configurations' base xcconfig.
        var base: String?
    }

    /// A project of `targets`, each with its own product reference, plus `objects`. The project
    /// sets `CODE_SIGN_STYLE`, so that no provisioning setting needs Swift Build.
    static func project(_ targets: [Target], objects: String = "", groupChildren: String = "", attributes: String = "") -> String {
        var text = ""
        for (index, target) in targets.enumerated() {
            let product = "F1\(String(format: "%022d", index))"
            let list = "F2\(String(format: "%022d", index))"
            let configurations = target.configurations.enumerated().map { position, entry in
                (id: "F3\(String(format: "%020d", index))\(String(format: "%02d", position))", name: entry.0, settings: entry.1)
            }
            text += "\t\t\(product) = {isa = PBXFileReference; explicitFileType = wrapper.application; path = \"\(target.productPath ?? target.name + ".app")\"; sourceTree = BUILT_PRODUCTS_DIR; };\n"
            for configuration in configurations {
                let base = target.base.map { "baseConfigurationReference = \($0); " } ?? ""
                text += "\t\t\(configuration.id) = {isa = XCBuildConfiguration; \(base)buildSettings = {\(configuration.settings)}; name = \(configuration.name); };\n"
            }
            text += "\t\t\(list) = {isa = XCConfigurationList; buildConfigurations = (\(configurations.map { $0.id + ", " }.joined())); defaultConfigurationName = \(configurations[0].name); };\n"
            text += "\t\t\(target.id) = {isa = PBXNativeTarget; buildConfigurationList = \(list); buildPhases = (); \(target.extra) name = \"\(target.name)\"; productName = \"\(target.name)\"; productReference = \(product); productType = \"\(target.productType)\"; };\n"
        }
        return """
        // !$*UTF8*$!
        {
        	archiveVersion = 1;
        	objectVersion = 77;
        	objects = {
        		F00000000000000000000002 = {isa = PBXGroup; children = (\(groupChildren)); sourceTree = "<group>"; };
        		F00000000000000000000006 = {isa = PBXProject; attributes = {\(attributes)}; buildConfigurationList = F0000000000000000000000B; mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (\(targets.map { $0.id + ", " }.joined())); };
        		F00000000000000000000008 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_STYLE = Automatic; SDKROOT = iphoneos; }; name = Debug; };
        		F00000000000000000000009 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_STYLE = Automatic; SDKROOT = iphoneos; }; name = Release; };
        		F0000000000000000000000B = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000008, F00000000000000000000009, ); defaultConfigurationName = Debug; };
        \(text)\(objects)
        	};
        	rootObject = F00000000000000000000006;
        }
        """
    }

    static func generator(_ files: [String: String]) throws -> (PIFGenerator, PIFDocument) {
        let directory = try TemporaryDirectory()
        try LoaderRulesTests.write(files, to: directory.path)
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj"))
        let document = try generator.generate()
        return (generator, document)
    }

    static func targets(_ targets: [Target], objects: String = "", groupChildren: String = "", attributes: String = "",
                        files: [String: String] = [:]) throws -> [String: [String: PIFValue]] {
        let (_, document) = try generator(files.merging(["P.xcodeproj/project.pbxproj": project(targets, objects: objects, groupChildren: groupChildren, attributes: attributes)]) { a, _ in a })
        return Dictionary(uniqueKeysWithValues: document.objects.filter { $0.type == "target" }.compactMap(\.contents.objectValue)
            .compactMap { contents in contents["name"]?.stringValue.map { ($0, contents) } })
    }

    // MARK: Build rules

    /// loader-experiments `build-rule-keys`.
    @Test func buildRulesAsXcodeWritesThem() throws {
        let objects = """
        		B00000000000000000000001 = {isa = PBXBuildRule; compilerSpec = com.apple.compilers.proxy.script; filePatterns = "*.x"; fileType = pattern.proxy; };
        		B00000000000000000000002 = {isa = PBXBuildRule; compilerSpec = com.apple.compilers.llvm.clang.1_0; filePatterns = "*.c"; fileType = sourcecode.c.c; runOncePerArchitecture = 0; script = "true"; };
        		B00000000000000000000003 = {isa = PBXBuildRule; compilerSpec = com.apple.compilers.proxy.script; fileType = pattern.proxy; outputFiles = (a.c, ); outputFilesCompilerFlags = ("-DA=\\"x y\\" -DB='p q' -DC\\\\ D  -E", "", ); script = "true\\n"; };
        """
        let app = try #require(try Self.targets([Target(id: "C00000000000000000000001", name: "App", extra: "buildRules = (B00000000000000000000001, B00000000000000000000002, B00000000000000000000003, );")],
                                                objects: objects)["App"])
        let rules = (app["buildRules"]?.arrayValue ?? []).compactMap(\.objectValue)
        try #require(rules.count == 3)
        // A script rule without a script or runOncePerArchitecture.
        #expect(rules[0]["runOncePerArchitecture"] == .bool(true))
        #expect(rules[0]["scriptContents"] == .string(""))
        #expect(rules[0]["filePatterns"] == .string("*.x"))
        // Patterns and a script only where the file type and the compiler use them.
        #expect(rules[1]["runOncePerArchitecture"] == .bool(false))
        #expect(rules[1]["scriptContents"] == nil)
        #expect(rules[1]["filePatterns"] == nil)
        #expect(rules[2]["filePatterns"] == .string(""))
        #expect(rules[2]["name"] == .string("Files '' using Script"))
        #expect(rules[2]["outputFilesCompilerFlags"] == .array([
            .array(["-DA=x y", "-DB=p q", "-DC D", "-E"].map(PIFValue.string)), .array([]),
        ]))
    }

    // MARK: Class prefix

    /// loader-experiments `class-prefix`, `class-prefix-empty`, `class-prefix-unset`.
    @Test func nativeAndAggregateTargetsCarryTheClassPrefix() throws {
        let objects = """
        		C00000000000000000000002 = {isa = PBXAggregateTarget; buildConfigurationList = F0000000000000000000000B; buildPhases = (); dependencies = (); name = Agg; productName = Agg; };
        		C00000000000000000000003 = {isa = PBXLegacyTarget; buildConfigurationList = F0000000000000000000000B; buildPhases = (); buildToolPath = /usr/bin/make; dependencies = (); name = Legacy; passBuildSettingsInEnvironment = 1; productName = Legacy; };
        """
        func prefixes(_ attributes: String) throws -> [String: PIFValue?] {
            let directory = try TemporaryDirectory()
            let text = Self.project([Target(id: "C00000000000000000000001", name: "App")], objects: objects, attributes: attributes)
                .replacingOccurrences(of: "targets = (C00000000000000000000001, )", with: "targets = (C00000000000000000000001, C00000000000000000000002, C00000000000000000000003, )")
            try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": text], to: directory.path)
            let document = try LoaderRulesTests.generate(directory.path + "/P.xcodeproj")
            return Dictionary(uniqueKeysWithValues: try ["App", "Agg", "Legacy"].map { ($0, try LoaderRulesTests.target(document, $0)["classPrefix"]) })
        }
        #expect(try prefixes("CLASSPREFIX = XY; ") == ["App": .string("XY"), "Agg": .string("XY"), "Legacy": nil])
        #expect(try prefixes("CLASSPREFIX = \"\"; ") == ["App": .string(""), "Agg": .string(""), "Legacy": nil])
        #expect(try prefixes("") == ["App": nil, "Agg": nil, "Legacy": nil])
    }

    // MARK: Product names

    /// loader-experiments `product-names`, `product-names-order`, `product-types-sdks`,
    /// `product-types-restricted`.
    @Test func productNamesAreTheFullProductName() throws {
        let targets = try Self.targets([
            Target(id: "C00000000000000000000001", name: "Unset"),
            Target(id: "C00000000000000000000002", name: "Caf\u{E9}", configurations: [("Debug", "PRODUCT_NAME = \"$(TARGET_NAME)\";")]),
            Target(id: "C00000000000000000000003", name: "Dynamic", productType: "com.apple.product-type.library.dynamic", productPath: "libDynamic.dylib",
                   configurations: [("Debug", "PRODUCT_NAME = \"$(TARGET_NAME)\";")]),
            Target(id: "C00000000000000000000004", name: "Static", productType: "com.apple.product-type.library.static", productPath: "Other.a",
                   configurations: [("Debug", "PRODUCT_NAME = Lib;")]),
            Target(id: "C00000000000000000000005", name: "Order", configurations: [("Release", "PRODUCT_NAME = First;"), ("Debug", "PRODUCT_NAME = Second;")]),
            Target(id: "C00000000000000000000006", name: "Watch", productType: "com.apple.product-type.application.watchapp2", productPath: "W\u{E9}.app",
                   configurations: [("Debug", "PRODUCT_NAME = Watch;")]),
            Target(id: "C00000000000000000000007", name: "OnWatch", productType: "com.apple.product-type.application.watchapp2",
                   configurations: [("Debug", "PRODUCT_NAME = OnWatch; SDKROOT = watchsimulator;")]),
            Target(id: "C00000000000000000000008", name: "Tool", productType: "com.apple.product-type.tool", productPath: "tool",
                   configurations: [("Debug", "PRODUCT_NAME = \"\\U00dcn\\U00ef\";")]),
        ])
        func name(_ target: String) -> String? { targets[target]?["productReference"]?.objectValue?["name"]?.stringValue }
        #expect(name("Unset") == ".app")
        #expect(name("Caf\u{E9}") == "Cafe\u{301}.app")
        #expect(name("Dynamic") == "Dynamic.dylib")
        #expect(name("Static") == "libLib.a")
        #expect(name("Order") == "Second.app")
        #expect(name("Watch") == "W\u{E9}.app")
        #expect(name("OnWatch") == "OnWatch.app")
        #expect(name("Tool") == "U\u{308}ni\u{308}")
    }

    /// loader-experiments `product-names-empty` (ish's `MakeXcodeAutoCompleteWork`): a name that
    /// would be empty is the target's, not the reference's path.
    @Test func emptyProductNamesAreTheTargetsName() throws {
        let targets = try Self.targets([
            Target(id: "C00000000000000000000001", name: "UnsetTool", productType: "com.apple.product-type.tool", productPath: "OtherPath",
                   configurations: [("Debug-Other", "SDKROOT = macosx;")]),
            Target(id: "C00000000000000000000002", name: "EmptyTool", productType: "com.apple.product-type.tool",
                   configurations: [("Debug", "PRODUCT_NAME = \"\"; SDKROOT = macosx;")]),
        ])
        func name(_ target: String) -> String? { targets[target]?["productReference"]?.objectValue?["name"]?.stringValue }
        #expect(name("UnsetTool") == "UnsetTool")
        #expect(name("EmptyTool") == "EmptyTool")
    }

    /// loader-experiments `swift-wholemodule`, `-42` to `-70` (delta): below objectVersion 50, a
    /// configuration's own `-Owholemodule` becomes `-O` and the whole-module compilation mode.
    @Test func wholeModuleOptimizationIsSplitBelowObjectVersion50() throws {
        let targets = [
            Target(id: "C00000000000000000000001", name: "Plain", configurations: [("Debug", "SWIFT_OPTIMIZATION_LEVEL = \"-Owholemodule\";")]),
            Target(id: "C00000000000000000000002", name: "WithMode",
                   configurations: [("Debug", "SWIFT_COMPILATION_MODE = singlefile; SWIFT_OPTIMIZATION_LEVEL = \"-Owholemodule\";")]),
            Target(id: "C00000000000000000000003", name: "Conditional",
                   configurations: [("Debug", "\"SWIFT_OPTIMIZATION_LEVEL[sdk=iphoneos*]\" = \"-Owholemodule\";")]),
        ]
        func settings(_ version: Int) throws -> [String: [String: PIFValue]] {
            let text = Self.project(targets).replacingOccurrences(of: "objectVersion = 77;", with: "objectVersion = \(version);")
            let (_, document) = try Self.generator(["P.xcodeproj/project.pbxproj": text])
            return Dictionary(uniqueKeysWithValues: document.objects.filter { $0.type == "target" }.compactMap(\.contents.objectValue).compactMap { target in
                target["name"]?.stringValue.flatMap { name in
                    target["buildConfigurations"]?.arrayValue?.first?.objectValue?["buildSettings"]?.objectValue.map { (name, $0) }
                }
            })
        }
        let old = try settings(49), new = try settings(50)
        #expect(old["Plain"]?["SWIFT_OPTIMIZATION_LEVEL"] == .string("-O"))
        #expect(old["Plain"]?["SWIFT_COMPILATION_MODE"] == .string("wholemodule"))
        #expect(old["WithMode"]?["SWIFT_OPTIMIZATION_LEVEL"] == .string("-Owholemodule"))
        #expect(old["Conditional"]?["SWIFT_OPTIMIZATION_LEVEL[sdk=iphoneos*]"] == .string("-Owholemodule"))
        #expect(new["Plain"]?["SWIFT_OPTIMIZATION_LEVEL"] == .string("-Owholemodule"))
        #expect(new["Plain"]?["SWIFT_COMPILATION_MODE"] == nil)
    }

    /// loader-experiments `root-group-name`, `-name-path` (wordpress): the root group is named
    /// after the project, its main group's `path` kept.
    @Test func theRootGroupIsNamedAfterTheProject() throws {
        let text = Self.project([Target(id: "C00000000000000000000001", name: "App")])
            .replacingOccurrences(of: "F00000000000000000000002 = {isa = PBXGroup; children", with: "F00000000000000000000002 = {isa = PBXGroup; name = CustomTemplate; path = Sources; children")
        let (_, document) = try Self.generator(["P.xcodeproj/project.pbxproj": text])
        let tree = document.objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue
        #expect(tree?["name"] == .string("P"))
        #expect(tree?["path"] == .string("Sources"))
    }

    /// loader-experiments `mig-codegen` (ish's `mach_exc.defs`): the Client and Server attributes
    /// of any build file, with case.
    @Test func migAttributesNameTheFilesToGenerate() {
        #expect(ProjectGenerator.migCodegenFiles(attributes: []) == nil)
        #expect(ProjectGenerator.migCodegenFiles(attributes: ["Client"]) == "client")
        #expect(ProjectGenerator.migCodegenFiles(attributes: ["Server", "Public"]) == "server")
        #expect(ProjectGenerator.migCodegenFiles(attributes: ["Server", "Client"]) == "both")
        #expect(ProjectGenerator.migCodegenFiles(attributes: ["server"]) == nil)
    }

    /// loader-experiments `dependency-proxies` (session's `SessionUtil`): proxies into the project
    /// resolve by remote ID; those that name no target keep their place, by `remoteInfo`, else
    /// `name`, else nameless.
    @Test func dependenciesThroughProxiesIntoTheProject() throws {
        let proxy = { (id: String, remote: String, info: String) in
            "\t\t\(id) = {isa = PBXContainerItemProxy; containerPortal = F00000000000000000000006; proxyType = 1; remoteGlobalIDString = \(remote);\(info) };\n"
        }
        let objects = proxy("X1", "C00000000000000000000002", " remoteInfo = Lib;") + proxy("X2", "C99999999999999999999991", " remoteInfo = Gone;")
            + proxy("X3", "C99999999999999999999992", " remoteInfo = GoneTarget;") + proxy("X4", "C99999999999999999999993", "")
            + proxy("X5", "C99999999999999999999994", "")
            + "\t\tD1 = {isa = PBXTargetDependency; targetProxy = X1; };\n\t\tD2 = {isa = PBXTargetDependency; targetProxy = X2; };\n"
            + "\t\tD3 = {isa = PBXTargetDependency; target = C99999999999999999999992; targetProxy = X3; };\n"
            + "\t\tD4 = {isa = PBXTargetDependency; targetProxy = X4; };\n\t\tD5 = {isa = PBXTargetDependency; name = Named; targetProxy = X5; };\n"
        let targets = try Self.targets([
            Target(id: "C00000000000000000000001", name: "App", extra: "dependencies = (D2, D1, D3, D4, D5, );"),
            Target(id: "C00000000000000000000002", name: "Lib", productType: "com.apple.product-type.framework"),
        ], objects: objects)
        let lib = targets["Lib"]?["guid"]
        #expect(targets["App"]?["dependencies"] == .array([
            .object(["name": .string("Gone")]), .object(["guid": lib!, "name": .string("Lib")]), .object(["name": .string("GoneTarget")]),
            .object([:]), .object(["name": .string("Named")]),
        ]))
    }

    /// Macros other than `$(TARGET_NAME)`, conditions and naming settings are left to Swift
    /// Build, in the product's configuration only (`product-names`: `$(NOMAC_NAME)`,
    /// `[sdk=iphoneos*]`, `WRAPPER_EXTENSION`).
    @Test func productNamesWithMacrosAreEvaluated() throws {
        let project = Self.project([
            Target(id: "C00000000000000000000001", name: "Custom", configurations: [("Debug", "PRODUCT_NAME = \"$(NOMAC_NAME)\"; NOMAC_NAME = Custom;"), ("Release", "")]),
            Target(id: "C00000000000000000000002", name: "Conditional", configurations: [("Debug", "PRODUCT_NAME = Base; \"PRODUCT_NAME[sdk=iphoneos*]\" = Device;")]),
            Target(id: "C00000000000000000000003", name: "Wrapper", productType: "com.apple.product-type.bundle", configurations: [("Debug", "WRAPPER_EXTENSION = plugin;")]),
            Target(id: "C00000000000000000000004", name: "Plain", configurations: [("Debug", "PRODUCT_NAME = \"$(TARGET_NAME)\";")]),
        ])
        let directory = try TemporaryDirectory()
        try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": project], to: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj")
        var first = PIFGenerator(workspace: workspace)
        _ = try first.generate()
        #expect(first.unevaluatedSettings == Set(["C00000000000000000000001", "C00000000000000000000002", "C00000000000000000000003"].map {
            TargetSettingsQuery(projectPath: workspace.projects[0].path, targetID: $0, configuration: "Debug")
        }))
        let evaluated = Dictionary(uniqueKeysWithValues: first.unevaluatedSettings.map { ($0, ["FULL_PRODUCT_NAME": "Caf\u{E9} \($0.targetID.suffix(1)).app"]) })
        var second = PIFGenerator(workspace: workspace, evaluatedSettings: evaluated)
        let document = try second.generate()
        #expect(second.unevaluatedSettings.isEmpty)
        #expect(try LoaderRulesTests.target(document, "Custom")["productReference"]?.objectValue?["name"] == .string("Cafe\u{301} 1.app"))
        #expect(try LoaderRulesTests.target(document, "Plain")["productReference"]?.objectValue?["name"] == .string("Plain.app"))
    }

    /// envelope-experiments `survey-shapes-3`: a test bundle names its baselines when its
    /// product's extension is `xctest`, whatever its type.
    @Test func baselinesFollowTheProductsExtension() throws {
        let ocunit = "com.apple.product-type.bundle.ocunit-test", unit = "com.apple.product-type.bundle.unit-test"
        let directory = try TemporaryDirectory()
        try LoaderRulesTests.write(["P.xcodeproj/project.pbxproj": Self.project([
            Target(id: "C00000000000000000000001", name: "OCUnit", productType: ocunit, productPath: "OCUnit.xctest",
                   configurations: [("Debug", "PRODUCT_NAME = OCUnit;")]),
            Target(id: "C00000000000000000000002", name: "OCUnitXCTest", productType: ocunit, productPath: "OCUnitXCTest.xctest",
                   configurations: [("Debug", "PRODUCT_NAME = OCUnitXCTest; WRAPPER_EXTENSION = xctest;")]),
            Target(id: "C00000000000000000000003", name: "Unit", productType: unit, productPath: "Unit.xctest",
                   configurations: [("Debug", "PRODUCT_NAME = Unit;")]),
            Target(id: "C00000000000000000000004", name: "UnitOCTest", productType: unit, productPath: "UnitOCTest.xctest",
                   configurations: [("Debug", "PRODUCT_NAME = UnitOCTest; WRAPPER_EXTENSION = octest;")]),
        ])], to: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj")
        let evaluated = [("C00000000000000000000002", "OCUnitXCTest.xctest"), ("C00000000000000000000004", "UnitOCTest.octest")].map { id, name in
            (TargetSettingsQuery(projectPath: workspace.projects[0].path, targetID: id, configuration: "Debug"), ["FULL_PRODUCT_NAME": name])
        }
        var generator = PIFGenerator(workspace: workspace, evaluatedSettings: Dictionary(uniqueKeysWithValues: evaluated))
        let document = try generator.generate()
        func target(_ name: String) throws -> [String: PIFValue] { try LoaderRulesTests.target(document, name) }
        #expect(try target("OCUnit")["productReference"]?.objectValue?["name"] == .string("OCUnit.octest"))
        #expect(try target("OCUnit")["performanceTestsBaselinesPath"] == nil)
        #expect(try target("OCUnitXCTest")["performanceTestsBaselinesPath"] != nil)
        #expect(try target("Unit")["performanceTestsBaselinesPath"] != nil)
        #expect(try target("UnitOCTest")["performanceTestsBaselinesPath"] == nil)
    }

    // MARK: Languages

    /// loader-experiments `language-fallback`, `language-synchronized`: excluded items count
    /// only when no build file counts for a language, and only for the target's phase kinds; an
    /// assembly member wins and leaves the key out.
    @Test func excludedSynchronizedItemsDecideWhenMembersHaveNoLanguage() throws {
        let objects = """
        		A00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000001, E00000000000000000000002, E00000000000000000000003, ); path = Src; sourceTree = "<group>"; };
        		E00000000000000000000001 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (a.swift, b.m, c.m, ); target = C00000000000000000000001; };
        		E00000000000000000000002 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (a.swift, ); target = C00000000000000000000002; };
        		E00000000000000000000003 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (a.swift, b.m, c.m, ); target = C00000000000000000000003; };
        		W00000000000000000000001 = {isa = PBXSourcesBuildPhase; files = (); };
        		W00000000000000000000002 = {isa = PBXSourcesBuildPhase; files = (); };
        		W00000000000000000000003 = {isa = PBXResourcesBuildPhase; files = (); };
        		W00000000000000000000004 = {isa = PBXSourcesBuildPhase; files = (); };
        		A00000000000000000000002 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000004, ); path = Asm; sourceTree = "<group>"; };
        		E00000000000000000000004 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (b.swift, c.swift, ); target = C00000000000000000000004; };
        """
        func target(_ id: String, _ name: String, _ phases: String, folder: String = "A00000000000000000000001") -> Target {
            Target(id: id, name: name, extra: "fileSystemSynchronizedGroups = (\(folder), ); buildPhases = (\(phases));")
        }
        let targets = try Self.targets([
            target("C00000000000000000000001", "AllExcluded", "W00000000000000000000001, "),
            target("C00000000000000000000002", "SwiftExcluded", "W00000000000000000000002, "),
            target("C00000000000000000000003", "ResourcesOnly", "W00000000000000000000003, "),
            target("C00000000000000000000004", "AssemblyMember", "W00000000000000000000004, ", folder: "A00000000000000000000002"),
        ], objects: objects, groupChildren: "A00000000000000000000001, A00000000000000000000002, ",
           files: ["Src/a.swift": "", "Src/b.m": "", "Src/c.m": "", "Asm/a.s": "", "Asm/b.swift": "", "Asm/c.swift": ""])
        #expect(targets["AllExcluded"]?["predominantSourceCodeLanguage"] == .string("Xcode.SourceCodeLanguage.Objective-C"))
        #expect(targets["SwiftExcluded"]?["predominantSourceCodeLanguage"] == .string("Xcode.SourceCodeLanguage.Objective-C"))
        #expect(targets["ResourcesOnly"]?["predominantSourceCodeLanguage"] == nil)
        #expect(targets["AssemblyMember"] != nil)
        #expect(targets["AssemblyMember"]?["predominantSourceCodeLanguage"] == nil)
    }

    /// loader-experiments `language-fallback-missing`: excluded items count once per file type,
    /// on disk or not, so the order of the languages alone decides among them.
    @Test func excludedSynchronizedItemsCountOncePerType() throws {
        let cases: [(name: String, excluded: [String], files: [String], language: String?)] = [
            ("ManySwift", ["a.swift", "b.swift", "c.swift", "d.m"], ["a.swift", "b.swift", "c.swift", "d.m"], "Objective-C"),
            ("ManyObjC", ["a.m", "b.m", "c.m", "d.c"], ["a.m", "b.m", "c.m", "d.c"], "C"),
            ("SwiftNotOnDisk", ["b.m", "g1.swift", "g2.swift", "g3.swift"], ["b.m"], "Objective-C"),
            ("ObjCNotOnDisk", ["a.swift", "g.m"], ["a.swift"], "Objective-C"),
            ("OnlyNotOnDisk", ["g1.swift", "g2.swift", "g.m"], [], "Objective-C"),
            ("NoLanguageOnDisk", ["g.swift"], ["a.json"], "Swift"),
            ("AssemblyNotOnDisk", ["a.swift", "g1.s", "g2.s"], ["a.swift"], nil),
        ]
        var objects = "", children = "", files: [String: String] = [:], targetsToWrite: [Target] = []
        for (index, item) in cases.enumerated() {
            let number = String(format: "%023d", index + 1)
            objects += "A\(number) = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E\(number), ); path = \(item.name); sourceTree = \"<group>\"; };\n"
            objects += "E\(number) = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (\(item.excluded.joined(separator: ", ")), ); target = C\(number); };\n"
            objects += "W\(number) = {isa = PBXSourcesBuildPhase; files = (); };\n"
            children += "A\(number), "
            for file in item.files { files["\(item.name)/\(file)"] = "" }
            if item.files.isEmpty { files["\(item.name)/.keep"] = "" }
            targetsToWrite.append(Target(id: "C\(number)", name: item.name, extra: "fileSystemSynchronizedGroups = (A\(number), ); buildPhases = (W\(number), );"))
        }
        let targets = try Self.targets(targetsToWrite, objects: objects, groupChildren: children, files: files)
        for item in cases {
            #expect(targets[item.name] != nil)
            #expect(targets[item.name]?["predominantSourceCodeLanguage"] == item.language.map { .string("Xcode.SourceCodeLanguage.\($0)") }, "\(item.name)")
        }
    }

    // MARK: Info.plist

    /// loader-experiments `info-plist-conditions`.
    @Test func generatedInfoPlistsAndConditions() throws {
        let (generator, document) = try Self.generator(["P.xcodeproj/project.pbxproj": Self.project([
            Target(id: "C00000000000000000000001", name: "Container", productType: "com.apple.product-type.application.watchapp2-container"),
            Target(id: "C00000000000000000000002", name: "Lowercase", configurations: [("Debug", "GENERATE_INFOPLIST_FILE = yes;")]),
            Target(id: "C00000000000000000000003", name: "On", configurations: [("Debug", "GENERATE_INFOPLIST_FILE = on;")]),
            Target(id: "C00000000000000000000004", name: "Plain"),
            Target(id: "C00000000000000000000005", name: "Device", configurations: [("Debug", "\"INFOPLIST_FILE[sdk=iphoneos*]\" = Device/Info.plist;")]),
        ])])
        func identifier(_ name: String) throws -> PIFValue? {
            try LoaderRulesTests.target(document, name)["provisioningSourceData"]?.arrayValue?.first?.objectValue?["bundleIdentifierFromInfoPlist"]
        }
        #expect(try identifier("Container") == .string("$(PRODUCT_BUNDLE_IDENTIFIER)"))
        #expect(try identifier("Lowercase") == .string("$(PRODUCT_BUNDLE_IDENTIFIER)"))
        #expect(try identifier("On") == .string(""))
        #expect(try identifier("Plain") == .string(""))
        #expect(generator.unevaluatedSettings.map(\.targetID) == ["C00000000000000000000005"])
    }

    @Test func booleansReadAsNSStringBoolValue() {
        for text in ["YES", "yes", "true", "T", "7", " YES", "\tYES", "+1", "-1", "007"] {
            #expect(ProjectGenerator.boolValue(text), "\(text)")
        }
        for text in ["NO", "on", "0", "00", "-0", "0Y", "0t", "+YES", "\nYES", "nope", ""] {
            #expect(!ProjectGenerator.boolValue(text), "\(text)")
        }
    }

    /// loader-experiments `xcconfig-conditions`, `info-plist-conditions`: with a condition, Xcode
    /// chooses the assignment matching the SDK whatever the xcconfig's order, and never one with
    /// an `[arch=…]` or `[config=…]` condition, where Swift Build may have evaluated another.
    @Test func conditionedSettingsTakeXcodesChoice() throws {
        let objects = """
        		X00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Name.xcconfig; sourceTree = "<group>"; };
        		X00000000000000000000002 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Generate.xcconfig; sourceTree = "<group>"; };
        """
        let directory = try TemporaryDirectory()
        try LoaderRulesTests.write([
            "P.xcodeproj/project.pbxproj": Self.project([
                Target(id: "C00000000000000000000001", name: "Name", base: "X00000000000000000000001"),
                Target(id: "C00000000000000000000002", name: "Generate", configurations: [("Debug", "PRODUCT_NAME = Generate;")], base: "X00000000000000000000002"),
                Target(id: "C00000000000000000000003", name: "Config", configurations: [("Debug", "PRODUCT_NAME = Config; \"INFOPLIST_FILE[config=Debug]\" = Info.plist;")]),
            ], objects: objects, groupChildren: "X00000000000000000000001, X00000000000000000000002, "),
            "Name.xcconfig": "PRODUCT_NAME[sdk=iphoneos*] = Cond\nPRODUCT_NAME = Plain\n",
            "Generate.xcconfig": "GENERATE_INFOPLIST_FILE[sdk=iphoneos*] = YES\nGENERATE_INFOPLIST_FILE = NO\n",
            "Info.plist": "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.nomac.config</string></dict></plist>\n",
        ], to: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj")
        // What Swift Build answers: an xcconfig's last assignment, and `config` conditions applied.
        let swiftBuild = ["C00000000000000000000001": ["FULL_PRODUCT_NAME": "Plain.app", "PRODUCT_NAME": "Plain"],
                          "C00000000000000000000002": ["GENERATE_INFOPLIST_FILE": "NO"],
                          "C00000000000000000000003": ["INFOPLIST_FILE": "Info.plist"]]
        let evaluated = Dictionary(uniqueKeysWithValues: swiftBuild.map { id, values in
            (TargetSettingsQuery(projectPath: workspace.projects[0].path, targetID: id, configuration: "Debug"), values.merging(["SDK_NAME": "iphoneos27.0"]) { a, _ in a })
        })
        var generator = PIFGenerator(workspace: workspace, evaluatedSettings: evaluated)
        let document = try generator.generate()
        func target(_ name: String) throws -> [String: PIFValue] { try LoaderRulesTests.target(document, name) }
        func identifier(_ name: String) throws -> PIFValue? { try target(name)["provisioningSourceData"]?.arrayValue?.first?.objectValue?["bundleIdentifierFromInfoPlist"] }
        #expect(try target("Name")["productReference"]?.objectValue?["name"] == .string("Cond.app"))
        #expect(try identifier("Generate") == .string("$(PRODUCT_BUNDLE_IDENTIFIER)"))
        #expect(try identifier("Config") == .string(""))
    }

    // MARK: Search paths

    /// loader-experiments `synchronized-search-paths`, `-folders`: an XCFramework adds no path;
    /// `unicode-nfc`: a folder written `Hëaders` is decomposed.
    @Test func synchronizedLibrariesAddSearchPaths() throws {
        let objects = """
        		A00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000001, ); path = "My Libs"; sourceTree = "<group>"; };
        		E00000000000000000000001 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = ("Sub/libB.a", ); target = C00000000000000000000001; };
        		W00000000000000000000001 = {isa = PBXFrameworksBuildPhase; files = (); };
        		W00000000000000000000002 = {isa = PBXResourcesBuildPhase; files = (); };
        """
        func target(_ id: String, _ name: String, _ phase: String, _ settings: String = "") -> Target {
            Target(id: id, name: name, configurations: [("Debug", settings)], extra: "fileSystemSynchronizedGroups = (A00000000000000000000001, ); buildPhases = (\(phase), );")
        }
        let targets = try Self.targets([
            target("C00000000000000000000001", "Linked", "W00000000000000000000001"),
            target("C00000000000000000000002", "Own", "W00000000000000000000001", "LIBRARY_SEARCH_PATHS = /custom; FRAMEWORK_SEARCH_PATHS = \"\";"),
            target("C00000000000000000000003", "Resources", "W00000000000000000000002"),
        ], objects: objects, groupChildren: "A00000000000000000000001, ", files: [
            "My Libs/libA.a": "!<arch>\n", "My Libs/Sub/libB.a": "!<arch>\n", "My Libs/it's/K.framework/Info.plist": "x\n",
            "My Libs/XC/X.xcframework/Info.plist": "x\n", "My Libs/H\u{EB}aders/libH.a": "!<arch>\n",
        ])
        func settings(_ name: String) -> [String: PIFValue]? {
            targets[name]?["buildConfigurations"]?.arrayValue?.first?.objectValue?["buildSettings"]?.objectValue
        }
        #expect(settings("Linked")?["LIBRARY_SEARCH_PATHS"] == .string(#"$(inherited) $(PROJECT_DIR)/My\ Libs/He\#u{308}aders $(PROJECT_DIR)/My\ Libs/Sub $(PROJECT_DIR)/My\ Libs"#))
        #expect(settings("Linked")?["FRAMEWORK_SEARCH_PATHS"] == .string(#"$(inherited) $(PROJECT_DIR)/My\ Libs/it\'s"#))
        #expect(settings("Own")?["LIBRARY_SEARCH_PATHS"] == .string(#"/custom $(PROJECT_DIR)/My\ Libs/He\#u{308}aders $(PROJECT_DIR)/My\ Libs/Sub $(PROJECT_DIR)/My\ Libs"#))
        #expect(settings("Own")?["FRAMEWORK_SEARCH_PATHS"] == .string(#"$(PROJECT_DIR)/My\ Libs/it\'s"#))
        #expect(settings("Resources")?["LIBRARY_SEARCH_PATHS"] == nil)
    }

    /// loader-experiments `synchronized-search-paths` (OwnSettingWithPath): a configuration keeps
    /// the paths it already has as words; a quoted path is another word.
    @Test func searchPathsKeepTheConfigurationsOwn() throws {
        let objects = """
        		A00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; path = Libs; sourceTree = "<group>"; };
        		W00000000000000000000001 = {isa = PBXFrameworksBuildPhase; files = (); };
        """
        let settings = #"LIBRARY_SEARCH_PATHS = "$(inherited) $(PROJECT_DIR)/Libs"; FRAMEWORK_SEARCH_PATHS = "\"$(PROJECT_DIR)/Libs\"";"#
        let targets = try Self.targets([Target(id: "C00000000000000000000001", name: "Already", configurations: [("Debug", settings)],
                                               extra: "fileSystemSynchronizedGroups = (A00000000000000000000001, ); buildPhases = (W00000000000000000000001, );")],
                                       objects: objects, groupChildren: "A00000000000000000000001, ",
                                       files: ["Libs/libA.a": "!<arch>\n", "Libs/Sub/libB.a": "!<arch>\n", "Libs/K.framework/Info.plist": "x\n"])
        let configuration = targets["Already"]?["buildConfigurations"]?.arrayValue?.first?.objectValue?["buildSettings"]?.objectValue
        #expect(configuration?["LIBRARY_SEARCH_PATHS"] == .string("$(inherited) $(PROJECT_DIR)/Libs $(PROJECT_DIR)/Libs/Sub"))
        #expect(configuration?["FRAMEWORK_SEARCH_PATHS"] == .string(#""$(PROJECT_DIR)/Libs" $(PROJECT_DIR)/Libs"#))
    }
}
