import Foundation
import NomacCore
import NomacEnvelope
import NomacProject
import NomacTestSupport
import Testing
@testable import NomacBuild

/// The Linux build beside a Mach-O tool that a setting names, on the layout of React Native's
/// `hermes-compiler/hermesc` (`osx-bin/hermesc`, `linux64-bin/hermesc`, x86_64, `win64-bin/hermesc.exe`).
@Suite struct MachOToolBuildsTests {
    static let machO: [UInt8] = [0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]
    static let x86_64: UInt16 = 62
    static let aarch64: UInt16 = 183
    static let unknownMachine: UInt16 = 0xbeef
    static let host = MachOToolBuilds.hostMachine

    private func elf(_ machine: UInt16) -> [UInt8] {
        [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0] + [UInt8](repeating: 0, count: 10) + [UInt8(machine & 0xff), UInt8(machine >> 8)]
    }

    private func executable(_ bytes: [UInt8], at path: String, mode: Int = 0o755) throws {
        try FileSystem.write(Data(bytes), to: path)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    private func app(machine: UInt16) throws -> (directory: TemporaryDirectory, tool: String, build: String) {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(BuildDomainTests.project, to: "ios/App.xcodeproj/project.pbxproj")
        try directory.writeExactly("""
            PODS_ROOT = ${SRCROOT}/Pods
            HERMES_CLI_PATH = $(PODS_ROOT)/../../node_modules/hermes-compiler/hermesc/osx-bin/hermesc

            """, to: "ios/App.release.xcconfig")
        let folder = directory.path + "/node_modules/hermes-compiler/hermesc"
        try executable(Self.machO, at: folder + "/osx-bin/hermesc")
        try executable(elf(machine), at: folder + "/linux64-bin/hermesc")
        return (directory, folder + "/osx-bin/hermesc", folder + "/linux64-bin/hermesc")
    }

    @Test func findsELFExecutablesOfTheNameInSiblingFolders() throws {
        let directory = try TemporaryDirectory()
        let folder = directory.path + "/hermesc"
        try executable(Self.machO, at: folder + "/osx-bin/hermesc")
        try executable(elf(Self.x86_64), at: folder + "/linux64-bin/hermesc")
        try executable(elf(Self.aarch64), at: folder + "/linux-arm64/hermesc")
        try executable(elf(Self.x86_64), at: folder + "/other-name/hermesc2")
        try executable(elf(Self.x86_64), at: folder + "/not-executable/hermesc", mode: 0o644)
        try executable(Array("#!/bin/sh\n".utf8), at: folder + "/script/hermesc")
        try executable(Self.machO, at: folder + "/macos-too/hermesc")
        try executable(elf(Self.x86_64), at: folder + "/deeper/bin/hermesc")
        try executable(elf(Self.x86_64), at: folder + "/osx-bin/hermesc-elf")
        try FileManager.default.createDirectory(atPath: folder + "/directory/hermesc", withIntermediateDirectories: true)

        #expect(MachOToolBuilds.builds(of: folder + "/osx-bin/hermesc") == [
            MachOToolBuilds.Build(path: folder + "/linux-arm64/hermesc", machine: Self.aarch64),
            MachOToolBuilds.Build(path: folder + "/linux64-bin/hermesc", machine: Self.x86_64),
        ])
    }

    @Test func choosesTheBuildThatFitsTheMachine() {
        let intel = MachOToolBuilds.Build(path: "/t/linux64-bin/hermesc", machine: Self.x86_64)
        let arm = MachOToolBuilds.Build(path: "/t/linux-arm64/hermesc", machine: Self.aarch64)
        let secondArm = MachOToolBuilds.Build(path: "/t/linux-arm/hermesc", machine: Self.aarch64)

        #expect(MachOToolBuilds.choice(among: [], hostMachine: Self.aarch64, runs: { _ in true }) == .none)
        #expect(MachOToolBuilds.choice(among: [intel, arm], hostMachine: Self.aarch64, runs: { _ in true }) == .runs(arm))
        #expect(MachOToolBuilds.choice(among: [intel, arm], hostMachine: Self.x86_64, runs: { _ in true }) == .runs(intel))
        #expect(MachOToolBuilds.choice(among: [arm, secondArm], hostMachine: Self.aarch64, runs: { _ in true }) == .several([arm, secondArm]))
        #expect(MachOToolBuilds.choice(among: [intel], hostMachine: Self.aarch64, runs: { _ in true }) == .runs(intel))
        #expect(MachOToolBuilds.choice(among: [intel], hostMachine: Self.aarch64, runs: { _ in false }) == .otherMachines([intel]))
    }

    @Test func overridesTheSettingOfTheProject() throws {
        let (directory, tool, build) = try app(machine: Self.host)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/ios/App.xcodeproj")
        let resolution = try MachOToolBuilds.resolve(workspace: workspace, commandLine: [:], scratch: directory.path + "/scratch")
        #expect(resolution.settings == ["HERMES_CLI_PATH": build])
        #expect(resolution.notes == ["HERMES_CLI_PATH names the macOS executable \(tool); building with the Linux one beside it, \(build)"])
        #expect(resolution.warnings.isEmpty)
        #expect(resolution.applied == ["HERMES_CLI_PATH is \(build)"])
    }

    @Test func theCommandLineWins() throws {
        let (directory, _, _) = try app(machine: Self.host)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/ios/App.xcodeproj")
        let resolution = try MachOToolBuilds.resolve(workspace: workspace, commandLine: ["HERMES_CLI_PATH": "/mine/hermesc"], scratch: directory.path + "/scratch")
        #expect(resolution.settings.isEmpty)
        #expect(resolution.notes.isEmpty)
    }

    @Test func checkCountsTheToolAsHandled() throws {
        let (directory, _, _) = try app(machine: Self.host)
        let container = directory.path + "/ios/App.xcodeproj"
        let scan = try BuildDomain().scan(container, options: CheckOptions())
        #expect(scan.uses.map { "\($0.feature) \($0.object)" } == [
            "build:setting=mach-o-executable-linux-build HERMES_CLI_PATH = $(PODS_ROOT)/../../node_modules/hermes-compiler/hermesc/osx-bin/hermesc; "
                + "Linux build: ../node_modules/hermes-compiler/hermesc/linux64-bin/hermesc",
        ])
        let report = CheckReport.make(container: container, domains: [BuildDomain()], options: CheckOptions())
        #expect(report.features.map(\.status) == [.verified])
    }

    @Test func aSettingNamingTwoToolsWithDifferentBuildsStaysTheProjects() throws {
        let (directory, tool, _) = try app(machine: Self.host)
        let other = directory.path + "/tools/macos/hermesc"
        try executable(Self.machO, at: other)
        try executable(elf(Self.host), at: directory.path + "/tools/linux/hermesc")
        let choices = MachOToolBuilds.choices(for: ["HERMES_CLI_PATH": [tool, other]], runs: { _ in true })
        guard case .several(let builds)? = choices["HERMES_CLI_PATH"]?.choice else {
            Issue.record("expected several builds")
            return
        }
        #expect(builds.count == 2)
    }

    @Test func standInSaysWhatToInstall() throws {
        let directory = try TemporaryDirectory()
        let build = MachOToolBuilds.Build(path: "/n/linux64-bin/hermesc", machine: Self.x86_64)
        let message = MachOToolBuilds.cannotRun(setting: "HERMES_CLI_PATH", tool: "/n/osx-bin/hermes'c", builds: [build])
        #expect(message.contains("/n/linux64-bin/hermesc (x86_64)"))
        #expect(message.contains("install qemu-user-static"))
        try executable(Array(MachOToolBuilds.standInScript(message: message).utf8), at: directory.path + "/hermesc")
        let result = try Subprocess.run(directory.path + "/hermesc", [])
        #expect(result.exitStatus == 1)
        #expect(result.errorString == "error: \(message)\n")
    }

    #if !os(macOS)
    /// No kernel runs an ELF file of an unknown machine, as an arm64 machine without user-mode
    /// emulation does not run x86_64 ones: "Exec format error" from the kernel, here seen by the probe.
    @Test func aBuildNoEmulationRunsBecomesAStandIn() throws {
        let (directory, tool, build) = try app(machine: Self.unknownMachine)
        #expect(!MachOToolBuilds.canRun(build))
        let workspace = try XcodeWorkspace.load(path: directory.path + "/ios/App.xcodeproj")
        let resolution = try MachOToolBuilds.resolve(workspace: workspace, commandLine: [:], scratch: directory.path + "/scratch")
        let standIn = try #require(resolution.settings["HERMES_CLI_PATH"])
        #expect(standIn.hasPrefix(directory.path + "/scratch/machine-tools/"))
        #expect(standIn.hasSuffix("/hermesc"))
        let message = MachOToolBuilds.cannotRun(setting: "HERMES_CLI_PATH", tool: tool, builds: [MachOToolBuilds.Build(path: build, machine: Self.unknownMachine)])
        #expect(resolution.warnings == [message])
        #expect(try Subprocess.run(standIn, []).errorString == "error: \(message)\n")

        let scan = try BuildDomain().scan(directory.path + "/ios/App.xcodeproj", options: CheckOptions())
        #expect(scan.uses.map(\.feature) == ["build:setting=mach-o-executable"])
        #expect(scan.uses[0].object.hasSuffix("which this machine cannot run without user-mode emulation: install qemu-user-static"))
    }

    @Test func theProbeRunsWhatTheMachineRuns() throws {
        #expect(MachOToolBuilds.canRun("/bin/true"))
    }
    #endif
}
