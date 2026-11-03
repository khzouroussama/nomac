import Foundation
import Testing
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport

/// loader-experiments `synchronized-exceptions`, `synchronized-exceptions-2` and
/// `synchronized-missing-order`, written again: one folder `Src` that every target lists but
/// `Guest`, and the exception sets of each target. Each expectation is the phases Xcode 27.0
/// wrote for the target, each build file as its item's path in `Src` (a variant group as
/// `[name]`) followed by its other keys.
@Suite struct SynchronizedExceptionsTests {
    struct Target {
        var name: String
        var phases: [String]
        var listed = true
        var type = "application"
    }

    static let copy = "dstPath = \"\"; dstSubfolderSpec = 7; name = \"Copy Shared\"; "
    static let plugins = "dstPath = \"\"; dstSubfolderSpec = 13; name = \"Copy PlugIns\"; "

    /// The phases of `targets`, after writing `files` into `Src` and the project, whose exception
    /// sets are `sets` (object bodies, with `TARGET<n>` and `PHASE<n>.<m>` for the IDs of the n-th
    /// target and its m-th phase).
    static func phases(files: [String], targets: [Target], sets: [String]) throws -> [String: [[String]]] {
        let directory = try TemporaryDirectory()
        for name in files {
            try FileSystem.write(Data((name.hasSuffix(".a") ? "!<arch>\n" : "x\n").utf8), to: directory.path + "/Src/" + name)
        }
        let isa = ["sources": "PBXSourcesBuildPhase", "resources": "PBXResourcesBuildPhase", "frameworks": "PBXFrameworksBuildPhase",
                   "headers": "PBXHeadersBuildPhase", "copy": "PBXCopyFilesBuildPhase", "plugins": "PBXCopyFilesBuildPhase"]
        var objects = ""
        var substitutions: [(String, String)] = []
        for (index, target) in targets.enumerated() {
            let id = String(format: "C%023d", index + 1), product = String(format: "F%023d", index + 20)
            substitutions.append(("TARGET\(index + 1)", id))
            var phaseIDs: [String] = []
            for (position, kind) in target.phases.enumerated() {
                let phase = String(format: "B%021d%02d", index + 1, position)
                substitutions.append(("PHASE\(index + 1).\(position)", phase))
                let extra = kind == "copy" ? copy : kind == "plugins" ? plugins : ""
                objects += "\t\t\(phase) = {isa = \(isa[kind]!); buildActionMask = 2147483647; \(extra)files = (); runOnlyForDeploymentPostprocessing = 0; };\n"
                phaseIDs.append(phase)
            }
            objects += "\t\t\(product) = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \(target.name).app; sourceTree = BUILT_PRODUCTS_DIR; };\n"
            objects += "\t\t\(id) = {isa = PBXNativeTarget; buildConfigurationList = F00000000000000000000010; buildPhases = (\(phaseIDs.map { $0 + ", " }.joined())); "
                + (target.listed ? "fileSystemSynchronizedGroups = (S00000000000000000000000, ); " : "")
                + "name = \(target.name); productName = \(target.name); productReference = \(product); productType = \"com.apple.product-type.\(target.type)\"; };\n"
        }
        let setIDs = sets.indices.map { String(format: "S%023d", $0 + 1) }
        for (id, body) in zip(setIDs, sets) {
            objects += "\t\t\(id) = {\(substitutions.reversed().reduce(body) { $0.replacingOccurrences(of: $1.0, with: $1.1) })};\n"
        }
        let products = targets.indices.map { String(format: "F%023d, ", $0 + 20) }.joined()
        let targetIDs = targets.indices.map { String(format: "C%023d, ", $0 + 1) }.joined()
        let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tS00000000000000000000000 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (\(setIDs.map { $0 + ", " }.joined())); path = Src; sourceTree = "<group>"; };
        \(objects)\t\tF00000000000000000000002 = {isa = PBXGroup; children = (S00000000000000000000000, \(products)); sourceTree = "<group>"; };
        \t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F00000000000000000000011; developmentRegion = en; knownRegions = (en, Base, fr, ); mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (\(targetIDs)); };
        \t\tD00000000000000000000001 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
        \t\tD00000000000000000000002 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
        \t\tF00000000000000000000010 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000001, ); defaultConfigurationName = Debug; };
        \t\tF00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (D00000000000000000000002, ); defaultConfigurationName = Debug; };
        \t};
        \trootObject = F00000000000000000000006;
        }
        """
        try FileSystem.write(Data(project.utf8), to: directory.path + "/P.xcodeproj/project.pbxproj")
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj"))
        let document = try generator.generate()
        var paths: [String: String] = [:]
        func walk(_ node: [String: PIFValue], _ prefix: String) {
            for child in (node["children"]?.arrayValue ?? []).compactMap(\.objectValue) {
                let isGroup = child["type"]?.stringValue == "group"
                let path = child["type"]?.stringValue == "variantGroup" ? prefix + "[" + (child["name"]?.stringValue ?? "") + "]"
                    : prefix + (child["path"]?.stringValue ?? "")
                paths[child["guid"]?.stringValue ?? ""] = path
                walk(child, isGroup ? path + "/" : prefix)
            }
        }
        let tree = try #require(document.objects.first { $0.type == "project" }?.contents.objectValue?["groupTree"]?.objectValue)
        walk(tree, "")
        var result: [String: [[String]]] = [:]
        for target in document.objects.filter({ $0.type == "target" }).compactMap(\.contents.objectValue) {
            result[target["name"]?.stringValue ?? ""] = (target["buildPhases"]?.arrayValue ?? []).compactMap(\.objectValue).map { phase in
                (phase["buildFiles"]?.arrayValue ?? []).compactMap(\.objectValue).map { file in
                    let path = (paths[file["fileReference"]?.stringValue ?? ""] ?? "?").replacingOccurrences(of: "Src/", with: "", options: .anchored)
                    let keys = file.keys.filter { !["guid", "fileReference"].contains($0) }.sorted().map { key in
                        "\(key)=" + (file[key]?.stringValue ?? (file[key]?.arrayValue ?? []).compactMap(\.objectValue).map { filter in
                            [filter["environment"]?.stringValue, filter["platform"]?.stringValue].compactMap { $0 }.joined(separator: "-")
                        }.joined(separator: ","))
                    }
                    return ([path] + keys).joined(separator: " ")
                }
            }
        }
        return result
    }

    static let standard = ["sources", "frameworks", "resources"]

    /// `synchronized-exceptions`: `platformFiltersByRelativePath` gives every kind of member its
    /// filters, Mac Catalyst as an environment, and a subfolder's key filters nothing; a build
    /// phase membership exception set adds what it names to its phase, of any kind, a second time
    /// if it is a member already, subfolders included: one block, ordered by the paths, after the
    /// folder's members at `h mod (n + 1)`, with the copy attributes. The paths filters name that
    /// are not on disk, `gone.swift` and `A.swift` next to `a.swift`, are members.
    @Test func platformFiltersAndBuildPhaseMembership() throws {
        let phases = try Self.phases(
            files: ["a.swift", "b.swift", "c.swift", "d.m", "e.png", "f.json", "g.h", "h.a", "i.xcconfig", "en.lproj/L.strings", "fr.lproj/L.strings",
                    "Sub/j.swift", "Sub/k.png"],
            targets: [Target(name: "Filters", phases: ["headers"] + Self.standard, type: "framework"),
                      Target(name: "Phases", phases: Self.standard + ["copy", "plugins"])],
            sets: [
                #"isa = PBXFileSystemSynchronizedBuildFileExceptionSet; platformFiltersByRelativePath = {"/Localized/L.strings" = (ios, ); A.swift = (ios, ); Sub = (ios, ); Sub/j.swift = (watchos, ); a.swift = (ios, ); b.swift = (macos, ); c.swift = (ios, maccatalyst, ); d.m = (maccatalyst, ); e.png = (ios, ); f.json = (tvos, ); g.h = (ios, ); gone.swift = (ios, ); h.a = (macos, ); i.xcconfig = (ios, ); }; target = TARGET1; "#,
                #"isa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet; buildPhase = PHASE2.2; membershipExceptions = (a.swift, f.json, "/Localized/L.strings", Sub/j.swift, gone.swift, ); "#,
                #"isa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet; attributesByRelativePath = {b.swift = (CodeSignOnCopy, ); e.png = (RemoveHeadersOnCopy, ); }; buildPhase = PHASE2.3; membershipExceptions = (e.png, b.swift, Sub, ); "#,
                #"isa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet; attributesByRelativePath = {c.swift = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; buildPhase = PHASE2.4; membershipExceptions = (c.swift, ); "#,
                #"isa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet; buildPhase = PHASE2.0; membershipExceptions = (e.png, a.swift, ); "#,
            ])
        #expect(phases["Filters"] == [
            ["g.h platformFilters=ios"],
            ["Sub/j.swift platformFilters=watchos", "a.swift platformFilters=ios", "A.swift platformFilters=ios", "b.swift platformFilters=macos",
             "c.swift platformFilters=ios,maccatalyst-ios", "d.m platformFilters=maccatalyst-ios", "gone.swift platformFilters=ios"],
            ["h.a platformFilters=macos"],
            ["Sub/k.png", "e.png platformFilters=ios", "f.json platformFilters=tvos", "i.xcconfig platformFilters=ios", "[L.strings] platformFilters=ios"],
        ])
        #expect(phases["Phases"] == [
            ["a.swift", "e.png", "Sub/j.swift", "a.swift", "A.swift", "b.swift", "c.swift", "d.m", "gone.swift"],
            ["h.a"],
            ["Sub/k.png", "e.png", "f.json", "i.xcconfig", "[L.strings]", "Sub/j.swift", "a.swift", "f.json", "gone.swift", "[L.strings]"],
            ["Sub", "b.swift codeSignOnCopy=true", "e.png removeHeadersOnCopy=true"],
            ["c.swift codeSignOnCopy=true removeHeadersOnCopy=true"],
        ])
    }

    /// `synchronized-exceptions-2`: every key of every exception set names a path the folder lists
    /// when no item has that name, compared byte for byte (`B.swift`, `C.swift` next to `b.swift`,
    /// `c.swift`), in an existing subfolder too (`Sub/deep.png`), which a listing target takes last.
    @Test func everyNamedPathIsListed() throws {
        let phases = try Self.phases(
            files: ["a.swift", "b.swift", "c.swift", "e.png", "Sub/j.swift"],
            targets: [Target(name: "Keys", phases: Self.standard), Target(name: "PhaseKeys", phases: Self.standard + ["copy"]),
                      Target(name: "Members", phases: Self.standard)],
            sets: [
                #"isa = PBXFileSystemSynchronizedBuildFileExceptionSet; additionalCompilerFlagsByRelativePath = {flagged.m = "-DX"; }; attributesByRelativePath = {attributed.swift = (Weak, ); }; platformFiltersByRelativePath = {B.swift = (ios, ); filtered.swift = (ios, ); }; target = TARGET1; "#,
                #"isa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet; attributesByRelativePath = {phased.png = (CodeSignOnCopy, ); }; buildPhase = PHASE2.3; membershipExceptions = (phased.png, Sub/deep.png, ); "#,
                #"isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (C.swift, member.swift, ); platformFiltersByRelativePath = {member.swift = (macos, ); }; target = TARGET3; "#,
            ])
        let sources = ["Sub/j.swift", "a.swift", "attributed.swift", "b.swift", "B.swift", "c.swift", "C.swift", "filtered.swift", "flagged.m", "member.swift"]
        let resources = ["e.png", "phased.png", "Sub/deep.png"]
        #expect(phases["Keys"] == [
            ["Sub/j.swift", "a.swift", "attributed.swift shouldLinkWeakly=true", "b.swift", "B.swift platformFilters=ios", "c.swift", "C.swift",
             "filtered.swift platformFilters=ios", "flagged.m additionalCompilerOptions=-DX", "member.swift"],
            [], resources,
        ])
        #expect(phases["PhaseKeys"] == [sources, [], resources, ["Sub/deep.png", "phased.png codeSignOnCopy=true"]])
        #expect(phases["Members"] == [sources.filter { $0 != "C.swift" && $0 != "member.swift" }, [], resources])
    }

    /// `synchronized-missing-order`: a target that lists the folder takes the paths not on disk in
    /// subfolders after its other members, a level at a time; one that does not takes them in
    /// their place.
    @Test func missingPathsInSubfolders() throws {
        let phases = try Self.phases(
            files: ["a.png", "b.swift", "Sub/x.png", "Sub/w.swift", "Sub/Deep/d.png", "Sub2/y.png", "Sub2/z.swift"],
            targets: [Target(name: "Missing", phases: Self.standard), Target(name: "Guest", phases: Self.standard, listed: false)],
            sets: [
                #"isa = PBXFileSystemSynchronizedBuildFileExceptionSet; platformFiltersByRelativePath = {Sub/Deep/m3.swift = (ios, ); Sub/m0.swift = (ios, ); Sub/m1.png = (ios, ); Sub2/m2.png = (ios, ); aa.png = (ios, ); zz.png = (ios, ); }; target = TARGET1; "#,
                #"isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (Sub/m1.png, Sub2/y.png, a.png, Sub/x.png, ); target = TARGET2; "#,
            ])
        #expect(phases["Missing"] == [
            ["Sub/w.swift", "Sub2/z.swift", "b.swift", "Sub/m0.swift platformFilters=ios", "Sub/Deep/m3.swift platformFilters=ios"],
            [],
            ["Sub/Deep/d.png", "Sub/x.png", "Sub2/y.png", "a.png", "aa.png platformFilters=ios", "zz.png platformFilters=ios",
             "Sub/m1.png platformFilters=ios", "Sub2/m2.png platformFilters=ios"],
        ])
        #expect(phases["Guest"] == [[], [], ["Sub/m1.png", "Sub/x.png", "Sub2/y.png", "a.png"]])
    }
}
