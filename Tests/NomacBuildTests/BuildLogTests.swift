import Foundation
@_spi(Testing) import SwiftBuild
import Testing
@testable import NomacBuild
import NomacBuildService
import NomacCore
import NomacTestSupport

@Suite struct BuildLogTests {
    final class Collected: @unchecked Sendable {
        var text = ""
    }

    /// xcodebuild's block for a task with output (retro-rampage's Engine, Xcode 27.0): the rule
    /// with its target, the command line, the output, an empty line.
    @Test func writesEachTaskAsXcodebuildDoes() throws {
        let collected = Collected()
        var printer = LogPrinter { collected.text += $0 }
        printer.handle(.targetStarted(.init(targetID: 1, targetGUID: "G", targetName: "Engine", type: .native, projectName: "Rampage",
                                            projectPath: try AbsolutePath(validating: "/src/Rampage.xcodeproj"), projectIsPackage: false,
                                            projectNameIsUniqueInWorkspace: true, configurationName: "Release", configurationIsDefault: false)))
        printer.handle(.taskStarted(.init(taskID: 7, targetID: 1, taskSignature: "S", ruleInfo: "ExtractAppIntentsMetadata",
                                          commandLineDisplayString: "    cd /src/Source\n    /x/appintentsmetadataprocessor --module-name Engine\n",
                                          executionDescription: "Extract app intents metadata")))
        printer.handle(.output(.init(data: Data("Starting export\nwarning: skipped\n".utf8), locationContext: .task(taskID: 7, targetID: 1),
                                     locationContext2: .init(targetID: 1, taskSignature: "S"))))
        printer.handle(.taskComplete(.init(taskID: 7, taskSignature: "S", result: .failed, signalled: false)))
        #expect(collected.text == "ExtractAppIntentsMetadata (in target 'Engine' from project 'Rampage')\n    cd /src/Source\n"
                + "    /x/appintentsmetadataprocessor --module-name Engine\nStarting export\nwarning: skipped\n\n")
        #expect(printer.failedTasks == ["ExtractAppIntentsMetadata (in target 'Engine' from project 'Rampage')"])
    }

    /// A task's own diagnostic goes in its block after the command line, with the target, as
    /// xcodebuild prints the framework Copy's in the device workstream's signing app (Xcode 27.0),
    /// and so does output that comes without the task's signature (that app's CodeSign): not
    /// before the block, as both arrive while the task runs.
    @Test func writesTaskDiagnosticsInTheTasksBlock() throws {
        let collected = Collected()
        var printer = LogPrinter { collected.text += $0 }
        printer.handle(.targetStarted(.init(targetID: 1, targetGUID: "G", targetName: "App", type: .native, projectName: "Signing",
                                            projectPath: try AbsolutePath(validating: "/src/Signing.xcodeproj"), projectIsPackage: false,
                                            projectNameIsUniqueInWorkspace: true, configurationName: "Release", configurationIsDefault: false)))
        printer.handle(.taskStarted(.init(taskID: 3, targetID: 1, taskSignature: "C", ruleInfo: "Copy /dd/App.app/Frameworks/Kit.framework /dd/Kit.framework",
                                          commandLineDisplayString: "    cd /src\n    builtin-copy -strip-debug-symbols /dd/Kit.framework /dd/App.app/Frameworks\n",
                                          executionDescription: "Copy Kit.framework")))
        printer.handle(.diagnostic(.init(kind: .warning, location: .unknown, locationContext: .task(taskID: 3, targetID: 1),
                                         locationContext2: .init(targetID: 1, taskSignature: "C"), component: .default,
                                         message: "not stripping binary because it is signed: /x/bitcode_strip /dd/Kit -r -o /dd/Kit",
                                         appendToOutputStream: true)))
        printer.handle(.output(.init(data: Data("/dd/Kit.framework: replacing existing signature\n".utf8), locationContext: .task(taskID: 3, targetID: 1),
                                     locationContext2: .init(targetID: 1))))
        #expect(collected.text.isEmpty)
        printer.handle(.taskComplete(.init(taskID: 3, taskSignature: "C", result: .success, signalled: false)))
        #expect(collected.text == "Copy /dd/App.app/Frameworks/Kit.framework /dd/Kit.framework (in target 'App' from project 'Signing')\n"
                + "    cd /src\n    builtin-copy -strip-debug-symbols /dd/Kit.framework /dd/App.app/Frameworks\n"
                + "warning: not stripping binary because it is signed: /x/bitcode_strip /dd/Kit -r -o /dd/Kit (in target 'App' from project 'Signing')\n"
                + "/dd/Kit.framework: replacing existing signature\n\n")
    }

    /// A diagnostic's notes follow it, indented, as in xcodebuild's log of an xcframework whose
    /// signature it refuses (`signature_record_experiments.py` `build-corrupt`).
    @Test func writesADiagnosticsNotesUnderIt() {
        let collected = Collected()
        var printer = LogPrinter { collected.text += $0 }
        func note(_ message: String) -> SwiftBuildMessage.DiagnosticInfo {
            .init(kind: .note, location: .unknown, locationContext: .global, locationContext2: .init(), component: .default, message: message,
                  appendToOutputStream: false)
        }
        printer.handle(.diagnostic(.init(kind: .error, location: .path("/src/Vendor.xcframework", fileLocation: nil), locationContext: .global,
                                         locationContext2: .init(), component: .default, message: "The signature of “Vendor.xcframework” cannot be verified.",
                                         appendToOutputStream: false,
                                         childDiagnostics: [note("Codesign verification failed"), note("/src/Vendor.xcframework: unsupported type or version of signature")])))
        #expect(collected.text == """
            /src/Vendor.xcframework: error: The signature of “Vendor.xcframework” cannot be verified.
                note: Codesign verification failed
                note: /src/Vendor.xcframework: unsupported type or version of signature

            """)
    }

    /// A task that completes under another signature than it started with (rn-bare's SDK
    /// explicit-module tasks on Linux) is the same task: its failure is not lost.
    @Test func matchesTasksByIdentifier() {
        let collected = Collected()
        var printer = LogPrinter { collected.text += $0 }
        printer.handle(.taskStarted(.init(taskID: 9, targetID: nil, taskSignature: "P0:::Pcm", ruleInfo: "SwiftExplicitDependencyGeneratePcm arm64 /m.pcm",
                                          commandLineDisplayString: "    cd /\n", executionDescription: "Compile")))
        printer.handle(.output(.init(data: Data("error: no\n".utf8), locationContext: .globalTask(taskID: 9),
                                     locationContext2: .init(taskSignature: "P1:::hash"))))
        printer.handle(.taskComplete(.init(taskID: 9, taskSignature: "P1:::hash", result: .failed, signalled: false)))
        printer.finish()
        #expect(printer.failedTasks == ["SwiftExplicitDependencyGeneratePcm arm64 /m.pcm"])
        #expect(collected.text == "SwiftExplicitDependencyGeneratePcm arm64 /m.pcm\n    cd /\nerror: no\n\n")
    }

    /// A build tool plugin xcodebuild could not apply fails the scheme's build before it has a
    /// configuration (`build_plugin_experiments.py` prebuildCommand, Xcode 27.0).
    @Test func summarizesAPluginFailureAsXcodebuildDoes() {
        let summary = BuildOperation.failureSummary(
            failedTasks: ["Apply build tool plug-in “GenPlugin” to target “Lib” in package “gen”", "eyJ"],
            schemeAction: BuildOperation.schemeAction(archive: false, container: "workspace", name: "Gen", scheme: "Lib", configuration: nil))
        #expect(summary == "\nThe following build commands failed:\n\tApply build tool plug-in “GenPlugin” to target “Lib” in package “gen”\n\teyJ\n"
                + "\tBuilding workspace Gen with scheme Lib\n(3 failures)\n")
    }

    /// What xcodebuild printed after `** BUILD FAILED **` for a failing Ld of retro-rampage's
    /// Engine scheme (Xcode 27.0, OTHER_LDFLAGS=-lnomacmissing).
    @Test func summarizesFailuresAsXcodebuildDoes() {
        let summary = BuildOperation.failureSummary(
            failedTasks: ["Ld /dd/Build/Products/Release-iphoneos/Engine.framework/Engine normal (in target 'Engine' from project 'Rampage')"],
            schemeAction: BuildOperation.schemeAction(archive: false, container: "project", name: "Rampage", scheme: "Engine", configuration: "Release"))
        #expect(summary == "\nThe following build commands failed:\n"
                + "\tLd /dd/Build/Products/Release-iphoneos/Engine.framework/Engine normal (in target 'Engine' from project 'Rampage')\n"
                + "\tBuilding project Rampage with scheme Engine and configuration Release\n(2 failures)\n")
    }

    /// What xcodebuild printed after `** ARCHIVE FAILED **` when archiving retro-rampage's
    /// Rampage scheme with a compiler flag Swift rejects (Xcode 27.0).
    @Test func summarizesArchiveFailuresAsXcodebuildDoes() {
        let failed = "SwiftDriver Engine normal arm64 com.apple.xcode.tools.swift.compiler (in target 'Engine' from project 'Rampage')"
        #expect(BuildOperation.failureSummary(failedTasks: [failed],
                                              schemeAction: BuildOperation.schemeAction(archive: true, container: "project", name: "Rampage", scheme: "Rampage", configuration: "Release"))
                == "\nThe following build commands failed:\n\t" + failed + "\n\tArchiving project Rampage with scheme Rampage\n(2 failures)\n")
    }

    /// failure_experiments.py: a workspace's scheme names the workspace, a failure while planning
    /// leaves only the scheme's line ("(1 failure)"), and a `-target` build has no scheme's line,
    /// so failing while planning it prints no summary.
    @Test func summarizesEveryObservedForm() {
        let workspace = BuildOperation.schemeAction(archive: false, container: "workspace", name: "W", scheme: "App", configuration: "Debug")
        #expect(workspace == "Building workspace W with scheme App and configuration Debug")
        #expect(BuildOperation.schemeAction(archive: true, container: "workspace", name: "W", scheme: "App", configuration: "Release")
                == "Archiving workspace W with scheme App")
        #expect(BuildOperation.failureSummary(failedTasks: [], schemeAction: workspace)
                == "\nThe following build commands failed:\n\tBuilding workspace W with scheme App and configuration Debug\n(1 failure)\n")
        #expect(BuildOperation.failureSummary(failedTasks: ["SwiftCompile normal arm64 /src/App.swift (in target 'App' from project 'P')"], schemeAction: nil)
                == "\nThe following build commands failed:\n\tSwiftCompile normal arm64 /src/App.swift (in target 'App' from project 'P')\n(1 failure)\n")
        #expect(BuildOperation.failureSummary(failedTasks: [], schemeAction: nil) == nil)
    }
}

@Suite struct ProvisioningTests {
    /// Xcode 27.0 signs ad hoc as "Sign to Run Locally", with no entitlements.
    @Test func answersAdHocSigningAsXcode() {
        let adHoc = PlanningDelegate.provisioning(signingIdentity: "-", entitlementsFile: nil, entitlements: nil, targetName: "App")
        #expect(adHoc.identityHash == "-" && adHoc.identityName == "Sign to Run Locally")
        #expect(adHoc.signedEntitlements == nil && adHoc.profileUUID == nil && adHoc.errors.isEmpty)
        #expect(PlanningDelegate.provisioning(signingIdentity: "-", entitlementsFile: "App/App.entitlements",
                                             entitlements: ["aps-environment": .plString("development")], targetName: "App").errors == [[
            "description": "\"App\" requires a provisioning profile.",
            "recoverySuggestion": "Enable development signing and select a provisioning profile in the Signing & Capabilities editor.",
        ]])
        #expect(PlanningDelegate.provisioning(signingIdentity: "-", entitlementsFile: "App/App.entitlements", entitlements: [:],
                                             targetName: "App").identityHash == "-")
        #expect(PlanningDelegate.provisioning(signingIdentity: "", entitlementsFile: nil, entitlements: nil, targetName: "App").identityHash == nil)
    }

    /// Off macOS a target with an identity signs ad hoc, and one without signs nothing, as Xcode
    /// 27.0 leaves a Swift package's dynamic product unsigned (signing_identity_experiments.py).
    @Test func signsOffMacOSOnlyWhatHasAnIdentity() {
        #expect(LinuxSigning.identity(for: "") == "")
        #expect(LinuxSigning.identity(for: "-") == "-")
        #expect(LinuxSigning.identity(for: "Apple Development") == "-")
        #expect(LinuxSigning.overrides["CODE_SIGN_IDENTITY"] == nil)
    }
}

/// Off macOS the reference Mac's TMPDIR is made where the build's tasks will look for it.
@Suite struct HostTemporaryDirectoryTests {
    @Test func createsTheReferencesTemporaryFolder() throws {
        let tmp = try TemporaryDirectory()
        let folder = tmp.path + "/var/folders/h8/abc/T/"
        let host = HostIdentity(userName: "u", groupName: "staff", uid: 501, gid: 20, homeDirectory: "/Users/u", operatingSystemVersion: [27, 0],
                                operatingSystemBuild: "26A1", nativeArchitecture: "arm64", isMacOS: true, environment: ["TMPDIR": folder])
        try HostTemporaryDirectory.prepare(host)
        #expect(FileSystem.isDirectory(folder))
        try HostTemporaryDirectory.prepare(host)
    }
}
