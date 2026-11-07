import Foundation
import NomacCore
import NomacEnvelope
import NomacProject
import NomacTestSupport
import Testing
@testable import NomacBuild

/// The fixes nomac applies to how a project's tools run (ADR 0184): the table, the preload run by
/// Node, where there is one, on files shaped as expo-modules-autolinking 58.0.17's `apple.js`, what
/// the build and `nomac check` tell the user, and the document.
@Suite struct ProjectFixesTests {
    static let check = "if (process.platform !== 'darwin') {"
    static let linuxCheck = "if (process.platform !== 'darwin' && process.platform !== 'linux') {"
    static let file = "expo-modules-autolinking/build/platforms/apple/apple.js"
    static let line = "note: project fix expo-autolinking-scan: changed in memory, not on disk: \(file): \"\(check)\" is now \"\(linuxCheck)\"\n"
    static let module = """
        exports.scan = function () {
            \(check)
                return null;
            }
            return 'scanned';
        };

        """
    static let hasNode = Subprocess.locate("node") != nil
    static let machO: [UInt8] = [0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]

    private func run(_ arguments: [String], preload: String, nodeOptions: String? = nil, record: String? = nil) throws -> (output: String, error: String) {
        var environment = ProcessInfo.processInfo.environment
        environment["NODE_OPTIONS"] = (nodeOptions.map { $0 + " " } ?? "") + "--require \"\(preload)\""
        environment[NodePreload.recordVariable] = record
        let result = try Subprocess.run(try #require(Subprocess.locate("node")), arguments, environment: environment)
        return (result.outputString, result.errorString)
    }

    /// Reports `platform` as Node's system, so that the check's outcome shows on any machine.
    private func script(requiring path: String, platform: String) -> String {
        "Object.defineProperty(process, 'platform', {value: '\(platform)'}); console.log(require('\(path)').scan());"
    }

    private func executable(_ bytes: [UInt8], at path: String) throws {
        try FileSystem.write(Data(bytes), to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    /// A project shaped as CocoaPods' integration of an Expo app, with a host's ELF `hermesc` beside
    /// the Mach-O one and `apple.js` as npm installs it.
    private func app() throws -> TemporaryDirectory {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(BuildDomainTests.project, to: "ios/App.xcodeproj/project.pbxproj")
        try directory.writeExactly("""
            PODS_ROOT = ${SRCROOT}/Pods
            HERMES_CLI_PATH = $(PODS_ROOT)/../../node_modules/hermes-compiler/hermesc/osx-bin/hermesc

            """, to: "ios/App.release.xcconfig")
        let machine = MachOToolBuilds.hostMachine
        let elf = [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0] + [UInt8](repeating: 0, count: 10) + [UInt8(machine & 0xff), UInt8(machine >> 8)]
        try executable(Self.machO, at: directory.path + "/node_modules/hermes-compiler/hermesc/osx-bin/hermesc")
        try executable(elf, at: directory.path + "/node_modules/hermes-compiler/hermesc/linux64-bin/hermesc")
        try directory.writeExactly(Self.module, to: "node_modules/" + Self.file)
        return directory
    }

    @Test func everyFixSaysWhatWhyAndWhenToDropIt() {
        #expect(ProjectFixes.all.map(\.id) == ["expo-autolinking-scan", "mach-o-tool-linux-build", "macro-plugin-from-package", "sentry-auto-upload"])
        for fix in ProjectFixes.all {
            #expect(!fix.tool.isEmpty)
            #expect(!fix.why.isEmpty)
            #expect(!fix.dropWhen.isEmpty)
            #expect(BuildDomain.envelope.entry(for: fix.feature)?.status == .verified)
        }
        guard case .inMemoryEdit(let file, let old, let new) = ProjectFixes.expoAutolinkingScan.change else {
            Issue.record("expected an in-memory edit")
            return
        }
        #expect(file == Self.file)
        #expect(old == Self.check)
        #expect(new == Self.linuxCheck)
    }

    @Test func nodeOptionsFollowTheUsersValue() {
        var overrides: [String: String] = [:]
        var synthesized: [String: String] = [:]
        NodePreload.apply(preload: "/s/p.cjs", record: "/s/r.log", to: &overrides, synthesized: &synthesized)
        #expect(overrides.isEmpty)
        #expect(synthesized == ["NODE_OPTIONS": "$(inherited) --require \"/s/p.cjs\"", "NOMAC_PROJECT_FIXES_RECORD": "/s/r.log"])

        overrides = ["NODE_OPTIONS": "--max-old-space-size=4096"]
        synthesized = [:]
        NodePreload.apply(preload: "/s/p.cjs", record: "/s/r.log", to: &overrides, synthesized: &synthesized)
        #expect(overrides["NODE_OPTIONS"] == "--max-old-space-size=4096 --require \"/s/p.cjs\"")
        #expect(synthesized == ["NOMAC_PROJECT_FIXES_RECORD": "/s/r.log"])
    }

    @Test func preloadIsNamedByItsContents() throws {
        let directory = try TemporaryDirectory()
        let path = try NodePreload.write(in: directory.path)
        #expect(try NodePreload.write(in: directory.path) == path)
        #expect(path.hasSuffix(".cjs"))
        let source = String(decoding: try #require(FileSystem.contents(atPath: path)), as: UTF8.self)
        #expect(source.contains(Self.check))
        #expect(source.contains(Self.linuxCheck))
    }

    @Test(.enabled(if: hasNode)) func replacesInMemoryAndLeavesTheFile() throws {
        let directory = try TemporaryDirectory()
        let preload = try NodePreload.write(in: directory.path + "/with space")
        try directory.writeExactly(Self.module, to: "node_modules/" + Self.file)
        let target = directory.path + "/node_modules/" + Self.file

        let result = try run(["-e", script(requiring: target, platform: "linux")], preload: preload, nodeOptions: "--no-warnings")
        #expect(result.output == "scanned\n")
        #expect(result.error == Self.line)
        #expect(String(decoding: try #require(FileSystem.contents(atPath: target)), as: UTF8.self) == Self.module)

        #expect(try run(["-e", script(requiring: target, platform: "win32")], preload: preload).output == "null\n")
    }

    @Test(.enabled(if: hasNode)) func worksFromAnESModule() throws {
        let directory = try TemporaryDirectory()
        let preload = try NodePreload.write(in: directory.path)
        try directory.writeExactly(Self.module, to: "node_modules/" + Self.file)
        try directory.writeExactly("""
            import { scan } from '\(directory.path)/node_modules/\(Self.file)';
            Object.defineProperty(process, 'platform', {value: 'linux'});
            console.log(scan());

            """, to: "main.mjs")
        let result = try run([directory.path + "/main.mjs"], preload: preload)
        #expect(result.output == "scanned\n")
        #expect(result.error == Self.line)
    }

    @Test(.enabled(if: hasNode)) func doesNothingWithoutTheExactStatementOrPath() throws {
        let directory = try TemporaryDirectory()
        let preload = try NodePreload.write(in: directory.path)
        try directory.writeExactly(Self.module.replacingOccurrences(of: Self.check, with: "if (process.platform === 'win32') {"), to: "fixed/node_modules/" + Self.file)
        try directory.writeExactly(Self.module, to: "other/apple.js")

        let fixed = try run(["-e", script(requiring: directory.path + "/fixed/node_modules/" + Self.file, platform: "linux")], preload: preload)
        #expect(fixed.output == "scanned\n")
        #expect(fixed.error.isEmpty)

        let other = try run(["-e", script(requiring: directory.path + "/other/apple.js", platform: "linux")], preload: preload)
        #expect(other.output == "null\n")
        #expect(other.error.isEmpty)
    }

    @Test func aBuildWithNothingToFixPrintsNoSummary() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(BuildDomainTests.project, to: "ios/App.xcodeproj/project.pbxproj")
        try directory.writeExactly("\n", to: "ios/App.release.xcconfig")
        var overrides: [String: String] = [:], synthesized: [String: String] = [:]
        let run = try ProjectFixRun(workspace: try XcodeWorkspace.load(path: directory.path + "/ios/App.xcodeproj"), commandLine: [:],
                                    scratch: directory.path + "/scratch", overrides: &overrides, synthesized: &synthesized)
        #expect(run.notes.isEmpty)
        #expect(run.summary().isEmpty)
    }

    @Test(.enabled(if: hasNode)) func theSummaryRepeatsWhatApplied() throws {
        let directory = try app()
        let scratch = directory.path + "/scratch"
        var overrides: [String: String] = [:], synthesized: [String: String] = [:]
        var fixes = try ProjectFixRun(workspace: try XcodeWorkspace.load(path: directory.path + "/ios/App.xcodeproj"), commandLine: [:],
                                      scratch: scratch, overrides: &overrides, synthesized: &synthesized)
        let tool = directory.path + "/node_modules/hermes-compiler/hermesc"
        #expect(synthesized["HERMES_CLI_PATH"] == tool + "/linux64-bin/hermesc")
        #expect(fixes.notes == ["note: project fix mach-o-tool-linux-build: HERMES_CLI_PATH names the macOS executable \(tool)/osx-bin/hermesc; building with the Linux one beside it, \(tool)/linux64-bin/hermesc"])
        #expect(fixes.summary() == [
            "note: nomac applied 1 project fix to how this project's tools run; your files on disk are not changed:",
            "note:   mach-o-tool-linux-build: HERMES_CLI_PATH is \(tool)/linux64-bin/hermesc",
            "note: what they do, what you may have to change yourself, and --no-project-fixes to turn them off: \(CheckReport.projectCompatibilityDocument)",
        ])

        // What a script phase's Node does with the build's environment.
        let preload = try #require(try FileManager.default.contentsOfDirectory(atPath: scratch).first { $0.hasSuffix(".cjs") })
        let record = try #require(synthesized[NodePreload.recordVariable])
        _ = try run(["-e", "require('\(directory.path)/node_modules/\(Self.file)')"], preload: scratch + "/" + preload, record: record)
        fixes.builtMacroPlugins(["ExpoModulesMacros"])
        #expect(fixes.summary() == [
            "note: nomac applied 3 project fixes to how this project's tools run; your files on disk are not changed:",
            "note:   expo-autolinking-scan: \(Self.file) changed in memory",
            "note:   mach-o-tool-linux-build: HERMES_CLI_PATH is \(tool)/linux64-bin/hermesc",
            "note:   macro-plugin-from-package: ExpoModulesMacros built for this machine",
            "note: what they do, what you may have to change yourself, and --no-project-fixes to turn them off: \(CheckReport.projectCompatibilityDocument)",
        ])
    }

    @Test func checkListsTheFixesApartFromTheEnvelope() throws {
        let directory = try app()
        let container = directory.path + "/ios/App.xcodeproj"
        var report = CheckReport.make(container: container, domains: [BuildDomain()], options: CheckOptions())
        report.fixes = ProjectFixes.listing(in: report)

        #expect(report.outside.isEmpty)
        #expect(report.fixes.map(\.id) == ["expo-autolinking-scan", "mach-o-tool-linux-build"])
        let text = report.text()
        #expect(text.contains("Project fixes a Linux build applies to this project (not problems; they do not change the exit status):"))
        #expect(text.contains("  expo-autolinking-scan: expo-modules-autolinking\n"))
        #expect(text.contains("  mach-o-tool-linux-build: any build setting"))
        #expect(text.contains("'nomac build --no-project-fixes': \(CheckReport.projectCompatibilityDocument)"))
        #expect(text.hasSuffix("Every feature is inside the envelope.\n"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(report.json().utf8)) as? [String: Any])
        #expect(json["inside"] as? Bool == true)
        #expect((json["projectFixes"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == ["expo-autolinking-scan", "mach-o-tool-linux-build"])

        try directory.writeExactly(Self.module.replacingOccurrences(of: Self.check, with: "if (false) {"), to: "node_modules/" + Self.file)
        var fixed = CheckReport.make(container: container, domains: [BuildDomain()], options: CheckOptions())
        fixed.fixes = ProjectFixes.listing(in: fixed)
        #expect(fixed.fixes.map(\.id) == ["mach-o-tool-linux-build"])
    }

    /// The document names every fix, and every `build:` feature it says `nomac check` reports is one.
    @Test func theDocumentMatchesTheTable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let document = try String(contentsOf: root.appendingPathComponent("docs/PROJECT-COMPATIBILITY.md"), encoding: .utf8)
        for fix in ProjectFixes.all { #expect(document.contains("`\(fix.id)`")) }
        let features = try NSRegularExpression(pattern: "`(build:[^`]+)`").matches(in: document, range: NSRange(document.startIndex..., in: document))
            .map { String(document[Range($0.range(at: 1), in: document)!]) }
        #expect(features.count > 5)
        for feature in features { #expect(BuildDomain.envelope.entry(for: feature) != nil, "\(feature)") }
    }
}
