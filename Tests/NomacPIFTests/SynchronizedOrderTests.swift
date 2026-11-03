import Foundation
import Testing
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport

/// Where synchronized folders' members go in a build phase (docs/formats/pif.md "Order in a
/// phase"), on projects shaped like `pif-experiments`' and written again here: one app target,
/// folders Alpha, Beta and Gamma. Each expectation is the order Xcode 27.0's -dumpPIF reported.
@Suite struct SynchronizedOrderTests {
    struct Project {
        var folders: [(name: String, files: [String])]
        /// The folders the target lists, when not all of them in group-tree order.
        var listed: [String]?
        /// Paths each folder's exception set names for the target.
        var exceptions: [String: [String]] = [:]
        /// Files the Sources phase holds itself.
        var ownSources: [String] = []
        /// Positions in the Sources phase of build files whose file reference is missing.
        var dangling: [Int] = []

        func id(_ prefix: Character, _ index: Int) -> String {
            String(prefix) + String(repeating: "0", count: 23 - String(index).count) + String(index)
        }

        var text: String {
            var objects = ""
            var roots: [String: String] = [:]
            for (index, folder) in folders.enumerated() {
                let root = id("A", index + 1)
                roots[folder.name] = root
                var exception = ""
                if let paths = exceptions[folder.name] {
                    exception = "exceptions = (\(id("E", index + 1)), ); "
                    objects += "\t\t\(id("E", index + 1)) = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (\(paths.map { "\"\($0)\", " }.joined())); target = C00000000000000000000001; };\n"
                }
                objects += "\t\t\(root) = {isa = PBXFileSystemSynchronizedRootGroup; \(exception)path = \(folder.name); sourceTree = \"<group>\"; };\n"
            }
            var own: [String] = [], ownReferences = ""
            for (index, name) in ownSources.enumerated() {
                objects += "\t\t\(id("O", index + 1)) = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \(name); sourceTree = \"<group>\"; };\n"
                objects += "\t\t\(id("Q", index + 1)) = {isa = PBXBuildFile; fileRef = \(id("O", index + 1)); };\n"
                own.append(id("Q", index + 1))
                ownReferences += "\(id("O", index + 1)), "
            }
            for (index, position) in dangling.enumerated() {
                objects += "\t\t\(id("X", index + 1)) = {isa = PBXBuildFile; fileRef = \(id("Y", index + 1)); };\n"
                own.insert(id("X", index + 1), at: position)
            }
            let rootList = folders.map { roots[$0.name]! + ", " }.joined()
            let targetRoots = (listed ?? folders.map(\.name)).map { roots[$0]! + ", " }.joined()
            objects += """
            \t\tF00000000000000000000001 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = T.app; sourceTree = BUILT_PRODUCTS_DIR; };
            \t\tF00000000000000000000002 = {isa = PBXGroup; children = (\(rootList)\(ownReferences)); sourceTree = "<group>"; };
            \t\tF00000000000000000000004 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\(own.map { $0 + ", " }.joined())); runOnlyForDeploymentPostprocessing = 0; };
            \t\tF00000000000000000000005 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
            \t\tC00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F00000000000000000000010; buildPhases = (F00000000000000000000004, F00000000000000000000005, ); fileSystemSynchronizedGroups = (\(targetRoots)); name = T; productName = T; productReference = F00000000000000000000001; productType = "com.apple.product-type.application"; };
            \t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F00000000000000000000011; mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (C00000000000000000000001, ); };
            \t\tF00000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000012, ); defaultConfigurationName = Release; };
            \t\tF00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (F00000000000000000000007, ); defaultConfigurationName = Release; };
            \t\tF00000000000000000000012 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Release; };
            \t\tF00000000000000000000007 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };

            """
            return "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tobjectVersion = 77;\n\tobjects = {\n\(objects)\t};\n\trootObject = F00000000000000000000006;\n}\n"
        }

        /// The file names of the target's Sources and Resources phases.
        func phases() throws -> (sources: [String], resources: [String]) {
            let directory = try TemporaryDirectory()
            for folder in folders {
                try FileManager.default.createDirectory(atPath: directory.path + "/" + folder.name, withIntermediateDirectories: true)
                for file in folder.files { try FileSystem.write(Data(), to: directory.path + "/" + folder.name + "/" + file) }
            }
            for name in ownSources { try FileSystem.write(Data(), to: directory.path + "/" + name) }
            try FileSystem.write(Data(text.utf8), to: directory.path + "/P.xcodeproj/project.pbxproj")
            var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj"))
            let document = try generator.generate()
            var names: [String: String] = [:]
            func walk(_ node: [String: PIFValue]) {
                for child in node["children"]?.arrayValue?.compactMap(\.objectValue) ?? [] {
                    if let guid = child["guid"]?.stringValue, let path = child["path"]?.stringValue { names[guid] = (path as NSString).lastPathComponent }
                    walk(child)
                }
            }
            walk(try #require(document.objects[1].contents.objectValue?["groupTree"]?.objectValue))
            let target = try #require(document.objects.first { $0.type == "target" }?.contents.objectValue)
            let phases = try #require(target["buildPhases"]?.arrayValue).compactMap(\.objectValue)
            func files(_ index: Int) -> [String] {
                (phases[index]["buildFiles"]?.arrayValue ?? []).compactMap { $0.objectValue?["fileReference"]?.stringValue.flatMap { names[$0] } }
            }
            return (files(0), files(1))
        }
    }

    static func swift(_ prefix: String, _ numbers: ClosedRange<Int>, padded: Bool = true) -> [String] {
        numbers.map { prefix + (padded ? String(format: "%02d", $0) : String($0)) + ".swift" }
    }

    /// `grid-7-4` and `order-flat-7-4`: the same sizes, the block elsewhere with other names.
    @Test func secondFolderGoesInAtItsHashedPosition() throws {
        let padded = try Project(folders: [("Alpha", Self.swift("a", 1...7)), ("Beta", Self.swift("b", 1...4))]).phases()
        #expect(padded.sources == Self.swift("a", 1...2) + Self.swift("b", 1...4) + Self.swift("a", 3...7))
        let flat = try Project(folders: [("Alpha", Self.swift("a", 1...7, padded: false)), ("Beta", Self.swift("b", 1...4, padded: false))]).phases()
        #expect(flat.sources == Self.swift("a", 1...6, padded: false) + Self.swift("b", 1...4, padded: false) + ["a7.swift"])
    }

    /// `grid3-1-3-1`: the third folder can go into the second's block.
    @Test func laterFoldersGoIntoTheListSoFar() throws {
        let order = try Project(folders: [("Alpha", ["a01.swift"]), ("Beta", Self.swift("b", 1...3)), ("Gamma", ["c01.swift"])]).phases()
        #expect(order.sources == ["b01.swift", "c01.swift", "b02.swift", "b03.swift", "a01.swift"])
    }

    /// `order-excluded-counts`, `order-other-kinds`, `order-nested-names`: what the hash covers.
    @Test func theHashCoversItemsOfThePhasesKind() throws {
        let alpha = Self.swift("a", 1...5)
        let excluded = try Project(folders: [("Alpha", alpha), ("Beta", ["b00.swift"] + Self.swift("b", 1...3))], exceptions: ["Beta": ["b00.swift"]]).phases()
        #expect(excluded.sources == Self.swift("a", 1...2) + Self.swift("b", 1...3) + Self.swift("a", 3...5))
        let kinds = try Project(folders: [("Alpha", alpha + ["a.json"]), ("Beta", Self.swift("b", 1...3) + ["r1.json", "r2.json"])]).phases()
        #expect(kinds.sources == Self.swift("a", 1...4) + Self.swift("b", 1...3) + ["a05.swift"])
        #expect(kinds.resources == ["a.json", "r1.json", "r2.json"])
        let nested = try Project(folders: [("Alpha", alpha), ("Beta", ["s/b01.swift", "s/t/b02.swift", "b03.swift"])]).phases()
        #expect(nested.sources == Self.swift("a", 1...4) + ["b02.swift", "b01.swift", "b03.swift", "a05.swift"])
    }

    /// `order-unlisted-folder`, `order-own-files`, `order-target-lists-second-first`.
    @Test func whatTheListStartsWithAndTheFolderOrder() throws {
        let alpha = Self.swift("a", 1...5), beta = Self.swift("b", 1...3)
        let unlisted = try Project(folders: [("Alpha", alpha), ("Beta", beta)], listed: ["Alpha"], exceptions: ["Beta": ["b02.swift", "b03.swift"]]).phases()
        #expect(unlisted.sources == ["a01.swift", "b02.swift", "b03.swift"] + Self.swift("a", 2...5))
        let own = try Project(folders: [("Alpha", Self.swift("a", 1...3))], ownSources: ["o1.swift", "o2.swift", "o3.swift", "o4.swift"]).phases()
        #expect(own.sources == ["o1.swift"] + Self.swift("a", 1...3) + ["o2.swift", "o3.swift", "o4.swift"])
        let reversed = try Project(folders: [("Alpha", alpha), ("Beta", beta)], listed: ["Beta", "Alpha"]).phases()
        #expect(reversed.sources == Self.swift("a", 1...4) + beta + ["a05.swift"])
    }

    /// loader-experiments `dangling-synchronized`: a build file whose file reference is missing
    /// counts where the members go, though the PIF leaves it out (N3M1D0, N3M1D04, N3M2D0).
    @Test func buildFilesWithMissingReferencesCount() throws {
        let own = ["r0.swift", "r1.swift", "r2.swift"]
        let front = try Project(folders: [("Feature", ["m0.swift"])], ownSources: own, dangling: [0]).phases()
        #expect(front.sources == ["r0.swift", "m0.swift", "r1.swift", "r2.swift"])
        let ends = try Project(folders: [("Feature", ["m0.swift"])], ownSources: own, dangling: [0, 4]).phases()
        #expect(ends.sources == own + ["m0.swift"])
        let two = try Project(folders: [("Feature", ["m0.swift", "m1.swift"])], ownSources: own, dangling: [0]).phases()
        #expect(two.sources == ["m0.swift", "m1.swift"] + own)
    }
}
