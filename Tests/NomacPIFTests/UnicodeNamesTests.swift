import Foundation
import Testing
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport

/// loader-experiments `unicode-nfc` and `unicode-nfd`, written again here: one project whose
/// project file and file names are written in one normalization form, some files and keys in
/// the other.
struct UnicodeProject {
    /// `text` in the form the project file uses.
    let written: (String) -> String
    /// `text` in the other form.
    let other: (String) -> String
    let decomposedProjectFile: Bool
    let directory: TemporaryDirectory
    let document: PIFDocument

    static func pbxproj(_ a: (String) -> String, _ odd: (String) -> String) -> String {
        func q(_ text: String) -> String { "\"\(text)\"" }
        return """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E00000000000000000000001, ); explicitFileTypes = {\(q(a("Ñote.dat"))) = sourcecode.swift; \(q(odd("Ôther.dat"))) = sourcecode.swift; }; explicitFolders = (\(q(odd("Földer"))), ); path = \(q(a("Sÿnc"))); sourceTree = "<group>"; };
        \t\tA00000000000000000000002 = {isa = PBXFileSystemSynchronizedRootGroup; path = \(q(a("Sÿnc2"))); sourceTree = "<group>"; };
        \t\tA00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000004, ); path = \(q(a("Ångström"))); sourceTree = "<group>"; };
        \t\tA00000000000000000000004 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \(q(a("Zürich.swift"))); sourceTree = "<group>"; };
        \t\tE00000000000000000000001 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; additionalCompilerFlagsByRelativePath = {\(q(a("Émoji.swift"))) = "-DONE"; \(q(odd("Ëxtra.swift"))) = "-DTWO"; }; membershipExceptions = (\(q(a("Ïgnored.swift"))), \(q(odd("Ïgnored2.swift"))), \(q(a("Ghöst.swift"))), ); target = C00000000000000000000001; };
        \t\tF00000000000000000000001 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \(q(a("Ünï App.app"))); sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tF00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000001, A00000000000000000000002, A00000000000000000000003, F00000000000000000000001, ); sourceTree = "<group>"; };
        \t\tC00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F00000000000000000000010; buildPhases = (B00000000000000000000001, B00000000000000000000002, ); fileSystemSynchronizedGroups = (A00000000000000000000001, A00000000000000000000002, ); name = \(q(a("Ünï App"))); productName = \(q(a("Ünï App"))); productReference = F00000000000000000000001; productType = "com.apple.product-type.application"; };
        \t\tB00000000000000000000001 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
        \t\tB00000000000000000000002 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
        \t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F00000000000000000000011; developmentRegion = en; knownRegions = (en, Base, ); mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (C00000000000000000000001, ); };
        \t\tD00000000000000000000001 = {isa = XCBuildConfiguration; baseConfigurationReferenceAnchor = A00000000000000000000001; baseConfigurationReferenceRelativePath = \(q(a("Ànchored.xcconfig"))); buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
        \t\tD00000000000000000000002 = {isa = XCBuildConfiguration; baseConfigurationReferenceAnchor = A00000000000000000000001; baseConfigurationReferenceRelativePath = \(q(odd("Ànchored2.xcconfig"))); buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Release; };
        \t\tD00000000000000000000003 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
        \t\tF00000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000001, D00000000000000000000002, ); defaultConfigurationName = Release; };
        \t\tF00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000003, ); defaultConfigurationName = Debug; };
        \t};
        \trootObject = F00000000000000000000006;
        }
        """
    }

    init(decomposed: Bool) throws {
        let nfd: (String) -> String = { $0.decomposedStringWithCanonicalMapping }
        let nfc: (String) -> String = { $0.precomposedStringWithCanonicalMapping }
        let (a, odd) = decomposed ? (nfd, nfc) : (nfc, nfd)
        written = a
        other = odd
        decomposedProjectFile = decomposed
        directory = try TemporaryDirectory()
        let files = [
            a("Sÿnc") + "/" + a("Émoji.swift"), a("Sÿnc") + "/" + odd("Ëxtra.swift"), a("Sÿnc") + "/" + a("Ïgnored.swift"),
            a("Sÿnc") + "/" + a("Ïgnored2.swift"), a("Sÿnc") + "/" + a("Ñote.dat"), a("Sÿnc") + "/" + a("Ôther.dat"),
            a("Sÿnc") + "/" + a("Földer") + "/In.txt", a("Sÿnc") + "/" + a("Ànchored.xcconfig"), a("Sÿnc") + "/" + a("Ànchored2.xcconfig"),
            odd("Sÿnc2") + "/" + a("Twö.swift"), a("Ångström") + "/" + odd("Zürich.swift"),
        ]
        for path in files {
            try directory.writeExactly("\n", to: path)
        }
        let container = directory.path + "/" + a("Café.xcodeproj")
        try directory.writeExactly(Self.pbxproj(a, odd), to: a("Café.xcodeproj") + "/project.pbxproj")
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: container))
        document = try generator.generate()
    }

    func object(_ type: String) throws -> [String: PIFValue] {
        try #require(document.objects.first { $0.type == type }?.contents.objectValue)
    }

    /// Group-tree items by GUID: their path from the root, their own `path` and file type.
    func items() throws -> [String: (path: String, name: String, fileType: String?)] {
        var result: [String: (path: String, name: String, fileType: String?)] = [:]
        func walk(_ node: [String: PIFValue], _ prefix: String) {
            for child in (node["children"]?.arrayValue ?? []).compactMap(\.objectValue) {
                let name = child["path"]?.stringValue ?? ""
                result[child["guid"]?.stringValue ?? ""] = (prefix + "/" + name, name, child["fileType"]?.stringValue)
                walk(child, prefix + "/" + name)
            }
        }
        walk(try #require(try object("project")["groupTree"]?.objectValue), "")
        return result
    }

    func sources() throws -> [[String: PIFValue]] {
        let phases = try #require(try object("target")["buildPhases"]?.arrayValue)
        return try #require(phases.first?.objectValue?["buildFiles"]?.arrayValue).compactMap(\.objectValue)
    }

    func nfd(_ text: String) -> String { text.decomposedStringWithCanonicalMapping }
}

/// What Xcode 27.0 wrote in its PIF for ``UnicodeProject`` in each form.
@Suite struct UnicodeNamesTests {
    static let forms = [false, true]

    /// The workspace and the project are named and found by their decomposed paths, whatever the
    /// form on disk; the GUIDs hash those spellings.
    @Test(arguments: forms) func containerPathsAreDecomposed(decomposed: Bool) throws {
        let fixture = try UnicodeProject(decomposed: decomposed)
        let workspace = try fixture.object("workspace")
        let project = try fixture.object("project")
        let path = fixture.nfd(FileSystem.absolute(fixture.directory.path) + "/Café.xcodeproj")
        #expect(workspace["name"]?.stringValue?.isIdentical(to: fixture.nfd("Café")) == true)
        #expect(workspace["path"]?.stringValue?.isIdentical(to: path + "/project.xcworkspace") == true)
        #expect(workspace["guid"] == .string(MD5.hex(fixture.nfd("Café"))))
        #expect(project["path"]?.stringValue?.isIdentical(to: path) == true)
        #expect(project["guid"] == .string(MD5.hex(fixture.nfd("Café.xcodeproj"))))
        #expect(project["groupTree"]?.objectValue?["name"]?.stringValue?.isIdentical(to: fixture.nfd("Café")) == true)
    }

    /// Names from the project file keep their form; the product reference's name is decomposed.
    @Test(arguments: forms) func projectFileNamesKeepTheirForm(decomposed: Bool) throws {
        let fixture = try UnicodeProject(decomposed: decomposed)
        let target = try fixture.object("target")
        #expect(target["name"]?.stringValue?.isIdentical(to: fixture.written("Ünï App")) == true)
        #expect(target["productReference"]?.objectValue?["name"]?.stringValue?.isIdentical(to: fixture.nfd("Ünï App.app")) == true)
        let items = try fixture.items().values
        #expect(items.contains { $0.name.isIdentical(to: fixture.written("Ångström")) })
        #expect(items.contains { $0.name.isIdentical(to: fixture.written("Zürich.swift")) })
        #expect(items.contains { $0.name.isIdentical(to: fixture.written("Sÿnc")) })
    }

    /// A synchronized folder's items are decomposed, whatever their form on disk, and found when
    /// the folder's path is written in another form than the folder's on disk.
    @Test(arguments: forms) func synchronizedItemsAreDecomposed(decomposed: Bool) throws {
        let fixture = try UnicodeProject(decomposed: decomposed)
        let paths = try fixture.items().values.map(\.path)
        let root = "/" + fixture.written("Sÿnc") + "/"
        for name in ["Émoji.swift", "Ëxtra.swift", "Ïgnored.swift", "Ïgnored2.swift", "Ghöst.swift", "Ñote.dat", "Ôther.dat", "Földer"] {
            #expect(paths.contains { $0.isIdentical(to: root + fixture.nfd(name)) }, "\(name)")
        }
        #expect(paths.contains { $0.isIdentical(to: "/" + fixture.written("Sÿnc2") + "/" + fixture.nfd("Twö.swift")) })
    }

    /// Exception sets, explicit file types and anchored xcconfig paths name an item only when
    /// they are written decomposed; explicit folders in either form. A missing file an exception
    /// set names is listed decomposed.
    @Test(arguments: forms) func keysMatchTheDecomposedNames(decomposed: Bool) throws {
        let fixture = try UnicodeProject(decomposed: decomposed)
        let items = try fixture.items()
        func item(_ name: String) -> (path: String, name: String, fileType: String?)? {
            items.values.first { $0.name.isIdentical(to: fixture.nfd(name)) }
        }
        let writtenDecomposed = fixture.decomposedProjectFile
        #expect((item("Ñote.dat")?.fileType == "sourcecode.swift") == writtenDecomposed)
        #expect((item("Ôther.dat")?.fileType == "sourcecode.swift") == !writtenDecomposed)
        #expect(item("Földer")?.fileType == "folder")

        let members = try fixture.sources()
        func member(_ name: String) -> [String: PIFValue]? {
            members.first { items[$0["fileReference"]?.stringValue ?? ""]?.name.isIdentical(to: fixture.nfd(name)) == true }
        }
        #expect((member("Ïgnored.swift") == nil) == writtenDecomposed)
        #expect((member("Ïgnored2.swift") == nil) == !writtenDecomposed)
        #expect((member("Ghöst.swift") == nil) == writtenDecomposed)
        #expect((member("Émoji.swift")?["additionalCompilerOptions"] == .string("-DONE")) == writtenDecomposed)
        #expect((member("Ëxtra.swift")?["additionalCompilerOptions"] == .string("-DTWO")) == !writtenDecomposed)
        #expect(member("Twö.swift") != nil)

        let configurations = try #require(try fixture.object("target")["buildConfigurations"]?.arrayValue).compactMap(\.objectValue)
        func base(_ name: String) -> String? {
            configurations.first { $0["name"] == .string(name) }?["baseConfigurationFileReference"]?.stringValue.flatMap { items[$0]?.name }
        }
        #expect((base("Debug")?.isIdentical(to: fixture.nfd("Ànchored.xcconfig")) == true) == writtenDecomposed)
        #expect((base("Release")?.isIdentical(to: fixture.nfd("Ànchored2.xcconfig")) == true) == !writtenDecomposed)
    }
}
