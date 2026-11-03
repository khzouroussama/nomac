import Foundation
import Testing
@testable import NomacPIF
import NomacTestSupport

/// How synchronized folders are laid out and which phases their members join, from
/// `pif-experiments` rounds 10 to 12 and loader-experiments `synchronized-phases`
/// (docs/formats/pif.md, "Synchronized folders"), on projects written here.
@Suite struct SynchronizedLayoutTests {
    static let phaseObjects = """
    \t\tS00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; path = Src; sourceTree = "<group>"; };
    \t\tH00000000000000000000005 = {isa = PBXHeadersBuildPhase; files = (); };
    \t\tH00000000000000000000006 = {isa = PBXResourcesBuildPhase; files = (); };

    """

    /// The PIF of an app whose synchronized folder `Src` holds `files`, with the build `phases`
    /// (Sources F…04, Headers H…05, Resources H…06).
    static func document(_ files: [String: String], phases: [String] = ["F00000000000000000000004", "H00000000000000000000006"],
                         regions: String = "developmentRegion = en; knownRegions = (en, Base, );") throws -> PIFDocument {
        let directory = try TemporaryDirectory()
        let project = LoaderRulesTests.project(objects: phaseObjects, groupChildren: "S00000000000000000000001, ",
                                               appExtra: "fileSystemSynchronizedGroups = (S00000000000000000000001, );", projectReferences: regions)
            .replacingOccurrences(of: "buildPhases = (F00000000000000000000004, );", with: "buildPhases = (\(phases.joined(separator: ", ")), );")
        try LoaderRulesTests.write(files.merging(["P.xcodeproj/project.pbxproj": project]) { $1 }, to: directory.path)
        return try LoaderRulesTests.generate(directory.path + "/P.xcodeproj")
    }

    static func project(_ document: PIFDocument) throws -> [String: PIFValue] {
        try #require(document.objects.first { $0.type == "project" }?.contents.objectValue)
    }

    static func folder(_ document: PIFDocument) throws -> [[String: PIFValue]] {
        let tree = try #require(try project(document)["groupTree"]?.objectValue)
        let source = try #require(tree["children"]?.arrayValue?.compactMap(\.objectValue).first { $0["path"] == .string("Src") })
        return (source["children"]?.arrayValue ?? []).compactMap(\.objectValue)
    }

    static func label(_ node: [String: PIFValue]) -> String {
        node["name"]?.stringValue ?? node["path"]?.stringValue ?? ""
    }

    /// Each phase's build files of the app, by type, as paths in the group tree.
    static func phases(_ document: PIFDocument) throws -> [String: [String]] {
        var paths: [String: String] = [:]
        func walk(_ node: [String: PIFValue]) {
            for child in (node["children"]?.arrayValue ?? []).compactMap(\.objectValue) {
                if let guid = child["guid"]?.stringValue { paths[guid] = label(child) }
                walk(child)
            }
        }
        walk(try #require(try project(document)["groupTree"]?.objectValue))
        var result: [String: [String]] = [:]
        for phase in try LoaderRulesTests.target(document, "App")["buildPhases"]?.arrayValue?.compactMap(\.objectValue) ?? [] {
            let files = (phase["buildFiles"]?.arrayValue ?? []).compactMap { $0.objectValue?["fileReference"]?.stringValue }.map { paths[$0] ?? $0 }
            result[String(phase["type"]?.stringValue?.split(separator: ".").last ?? "")] = files
        }
        return result
    }

    @Test func sameStemNamesListHeaderExtensionsFirst() {
        let names = ["Y-1.c", "Y.c", "Y.h", "Y_1.c", "Y 1.c", "Ya.c", "Y.m", "X.pch", "X.hpp", "X.h", "X.a", "U.H", "U.c", "w.c", "W.h",
                     "N10.c", "N2.h", "N10.h", "N2.c", "M.h.h", "M.h"]
        #expect(names.sorted(by: SynchronizedFolder.finderOrder) == [
            "M.h", "M.h.h", "N2.h", "N2.c", "N10.h", "N10.c", "U.c", "U.H", "w.c", "W.h", "X.h", "X.hpp", "X.a", "X.pch",
            "Y.h", "Y.c", "Y.m", "Y 1.c", "Y_1.c", "Y-1.c", "Ya.c",
        ])
    }

    @Test func dotFilesAreItemsButIgnoredNamesAreNot() throws {
        let document = try Self.document([
            "Src/a.swift": "let a = 1\n", "Src/.gitkeep": "", "Src/.hidden.swift": "let h = 1\n", "Src/.DS_Store": "x", "Src/.git/HEAD": "x\n",
            "Src/sub/.git": "gitdir: x\n", "Src/.svn/x": "x\n", "Src/.hg/x": "x\n", "Src/CVS/x": "x\n", "Src/a.swift~": "x\n", "Src/.#lock": "x\n",
            "Src/._a.swift": "x\n", "Src/.bzr/x": "x\n", "Src/en.lproj/.hidden.strings": "\"k\" = \"v\";\n", "Src/.lproj/W.strings": "\"k\" = \"v\";\n",
        ])
        let items = try Self.folder(document)
        #expect(items.map(Self.label) == [".bzr", "sub", ".gitkeep", ".hidden.strings", ".hidden.swift", "a.swift", "W.strings"])
        #expect(items[1]["children"] == nil)
        #expect(items[2]["fileType"] == .string("text"))
        let dotted = try #require(items[6]["children"]?.arrayValue?.first?.objectValue)
        #expect(dotted["path"] == .string(".lproj/W.strings"))
        #expect(dotted["regionVariantName"] == nil)
        #expect(try Self.project(document)["knownRegions"] == .array(["en", "Base", ".lproj"].map(PIFValue.string)))
        let sources = try Self.phases(document)["sources"]
        #expect(sources == ["App.swift", ".hidden.swift", "a.swift"])
    }

    @Test func stringTablesJoinBaseDocumentsOfTheirStem() throws {
        let strings = "\"k\" = \"v\";\n"
        let document = try Self.document([
            "Src/Base.lproj/S.storyboard": "<document/>\n", "Src/en.lproj/S.strings": strings, "Src/Base.lproj/H.h": "\n", "Src/en.lproj/H.strings": strings,
            "Src/en.lproj/E.intentdefinition": "<plist/>\n", "Src/fr.lproj/E.strings": strings, "Src/Base.lproj/U.storyboard": "<document/>\n",
            "Src/en.lproj/U.stringsdict": strings, "Src/fr.lproj/U.xcstrings": "{}\n", "Src/Base.lproj/F2.storyboard": "<document/>\n",
            "Src/Base.lproj/F2.strings": strings, "Src/en.lproj/F2.strings": strings, "Src/Base.lproj/R.nib": "x\n", "Src/en.lproj/R.strings": strings,
        ])
        let groups = try Self.folder(document)
        #expect(groups.map(Self.label) == ["E.intentdefinition", "E.strings", "F2.storyboard", "H.h", "H.strings", "R.nib", "S.storyboard",
                                           "U.storyboard", "U.stringsdict"])
        #expect(groups.map { ($0["children"]?.arrayValue ?? []).compactMap { $0.objectValue?["path"]?.stringValue } } == [
            ["en.lproj/E.intentdefinition"], ["fr.lproj/E.strings"], ["Base.lproj/F2.strings", "en.lproj/F2.strings"], ["Base.lproj/H.h"],
            ["en.lproj/H.strings"], ["Base.lproj/R.nib", "en.lproj/R.strings"], ["Base.lproj/S.storyboard", "en.lproj/S.strings"],
            ["Base.lproj/U.storyboard", "fr.lproj/U.xcstrings"], ["en.lproj/U.stringsdict"],
        ])
    }

    @Test func intentDefinitionAndMetalLibraryVariantsGetASecondBuildFile() throws {
        let document = try Self.document([
            "Src/Base.lproj/A.intentdefinition": "<plist/>\n", "Src/en.lproj/A.strings": "\"k\" = \"v\";\n", "Src/Base.lproj/K.metallib": "x\n",
            "Src/Base.lproj/M.mlmodel": "x\n", "Src/en.lproj/T.intentdefinition": "<plist/>\n", "Src/fr.lproj/T.intentdefinition": "<plist/>\n",
        ])
        let resources = try #require(try LoaderRulesTests.target(document, "App")["buildPhases"]?.arrayValue?.compactMap(\.objectValue)
            .first { $0["type"] == .string("com.apple.buildphase.resources") }?["buildFiles"]?.arrayValue?.compactMap(\.objectValue))
        #expect(try Self.phases(document)["resources"] == ["A.intentdefinition", "Base.lproj/A.intentdefinition", "K.metallib", "Base.lproj/K.metallib",
                                                         "M.mlmodel", "T.intentdefinition", "en.lproj/T.intentdefinition", "fr.lproj/T.intentdefinition"])
        let guids = resources.map { $0["guid"]?.stringValue ?? "" }
        #expect(guids[0] == guids[1] && guids[2] == guids[3] && guids[5] == guids[6])
        #expect(Set(guids).count == 5)
    }

    @Test func membersJoinThePhasesOfTheirType() throws {
        let files = ["Src/a.swift": "let a = 1\n", "Src/t.modulemap": "x\n", "Src/t.r": "x\n", "Src/t.ts": "x\n", "Src/t.apinotes": "x\n", "Src/t.md": "x\n",
                     "Src/t.jar": "x\n", "Src/t.h": "\n", "Src/P.playground/x": "x\n", "Src/t.entitlements": "<plist/>\n"]
        let phases = try Self.phases(try Self.document(files, phases: ["H00000000000000000000005", "F00000000000000000000004", "H00000000000000000000006"]))
        #expect(phases == ["headers": ["t.h", "t.apinotes"], "sources": ["App.swift", "a.swift"], "resources": ["t.md"]])
        #expect(try Self.phases(try Self.document(files))["resources"] == ["t.md"])
    }

    @Test func coreDataModelFoldersAreVersionGroups() throws {
        let document = try Self.document(["Src/M.xcdatamodeld/M.xcdatamodel/contents": "<model/>\n", "Src/M.xcdatamodeld/M 2.xcdatamodel/contents": "<model/>\n",
                                          "Src/M.xcdatamodeld/notes": "x\n", "Src/E.xcdatamodeld/notes": "x\n"])
        let items = try Self.folder(document)
        #expect(items.map { $0["type"]?.stringValue ?? "" } == ["versionGroup", "versionGroup"])
        #expect(items[0]["name"] == .string("E.xcdatamodeld") && items[0]["children"] == nil)
        #expect(items[1]["fileType"] == .string("wrapper.xcdatamodeld"))
        #expect(items[1]["children"]?.arrayValue?.compactMap { $0.objectValue?["path"]?.stringValue } == ["M.xcdatamodel", "M 2.xcdatamodel"])
        let sources = try Self.phases(document)["sources"]
        #expect(sources == ["E.xcdatamodeld", "M.xcdatamodeld", "App.swift"])
    }

    @Test func synchronizedRegionsKeepTheirSpelling() throws {
        let strings = "\"k\" = \"v\";\n"
        let document = try Self.document(["Src/IT.lproj/S.strings": strings, "Src/MUL.lproj/T.strings": strings,
                                          "Src/BASE.lproj/V.strings": strings], regions: "developmentRegion = en; knownRegions = (en, Base, it, );")
        #expect(try Self.project(document)["knownRegions"] == .array(["en", "Base", "it", "IT", "MUL", "BASE"].map(PIFValue.string)))
    }
}
