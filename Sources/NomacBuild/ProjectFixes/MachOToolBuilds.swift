import Foundation
import NomacCore
import NomacProject

/// The Linux build of a tool that a build setting names as a Mach-O executable: an ELF executable of
/// the same name in a sibling of the tool's folder (`hermes-compiler/hermesc/linux64-bin/hermesc`
/// beside `osx-bin/hermesc`, ADR 0184). The rule behind ``ProjectFixes/machOToolLinuxBuild``: `nomac
/// build` off macOS sets it as an override, and `nomac check` reports the same choice.
public enum MachOToolBuilds {
    public struct Build: Hashable, Sendable {
        public var path: String
        public var machine: UInt16

        var machineName: String { Self.machineNames[machine] ?? "machine \(machine)" }

        static let machineNames: [UInt16: String] = [62: "x86_64", 183: "aarch64"]
    }

    public enum Choice: Hashable, Sendable {
        case none
        case runs(Build)
        case several([Build])
        case otherMachines([Build])
    }

    public struct Resolution: Sendable {
        public var settings: [String: String] = [:]
        public var notes: [String] = []
        public var warnings: [String] = []
        public var applied: [String] = []
    }

    static var hostMachine: UInt16 {
        #if arch(arm64)
        183
        #else
        62
        #endif
    }

    /// The ELF `e_machine` of `path`; nil when it is not a little-endian ELF file.
    static func elfMachine(_ path: String) -> UInt16? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let header = [UInt8](handle.readData(ofLength: 20))
        guard header.count == 20, header.starts(with: [0x7f, 0x45, 0x4c, 0x46]), header[5] == 1 else { return nil }
        return UInt16(header[18]) | UInt16(header[19]) << 8
    }

    /// The ELF executables named as `executable` in the other folders beside its folder.
    static func builds(of executable: String) -> [Build] {
        let folder = (executable as NSString).deletingLastPathComponent
        let parent = (folder as NSString).deletingLastPathComponent
        let name = (executable as NSString).lastPathComponent
        let siblings = ((try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []).sorted()
        return siblings.compactMap { sibling in
            let path = parent + "/" + sibling + "/" + name
            guard parent + "/" + sibling != folder, FileSystem.isFile(path), FileManager.default.isExecutableFile(atPath: path),
                  let machine = elfMachine(path) else { return nil }
            return Build(path: path, machine: machine)
        }
    }

    /// Whether the kernel takes the executable, which for another machine's takes user-mode
    /// emulation: started and stopped at once, without waiting for it to do anything. On a Mac,
    /// where `nomac check` tells what a Linux build does, it says yes.
    static func canRun(_ path: String) -> Bool {
        #if os(macOS)
        return true
        #else
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.terminate()
        process.waitUntilExit()
        return true
        #endif
    }

    /// The one build this machine runs: its own machine's, else one it emulates.
    static func choice(among builds: [Build], hostMachine: UInt16 = MachOToolBuilds.hostMachine, runs: (String) -> Bool = canRun) -> Choice {
        guard !builds.isEmpty else { return .none }
        let native = builds.filter { $0.machine == hostMachine }
        if native.count == 1 { return .runs(native[0]) }
        if native.count > 1 { return .several(native) }
        let emulated = builds.filter { runs($0.path) }
        if emulated.count == 1 { return .runs(emulated[0]) }
        return emulated.isEmpty ? .otherMachines(builds) : .several(emulated)
    }

    /// Each setting that names a Mach-O tool, with the choice for it: one override applies to every
    /// target, so a setting naming several tools needs them to come to the same build.
    static func choices(for settings: [String: Set<String>], runs: (String) -> Bool = canRun) -> [String: (executables: [String], choice: Choice)] {
        settings.mapValues { executables in
            let sorted = executables.sorted()
            let choices = Set(sorted.map { choice(among: builds(of: $0), runs: runs) })
            guard choices.count > 1 else { return (sorted, choices.first ?? .none) }
            return (sorted, .several(sorted.flatMap { builds(of: $0) }))
        }
    }

    /// The overrides for `workspace`'s settings, except those given on the command line. A build
    /// only for other machines becomes a stand-in that stops the build, if it comes to run the tool,
    /// with what to do instead of "Exec format error": a phase may never run it (Debug bundling).
    public static func resolve(workspace: XcodeWorkspace, commandLine: [String: String], scratch: String) throws -> Resolution {
        var resolution = Resolution()
        for (setting, found) in choices(for: BuildDomain.machOToolSettings(of: workspace)).sorted(by: { $0.key < $1.key }) where commandLine[setting] == nil {
            let tool = found.executables.joined(separator: ", ")
            switch found.choice {
            case .none:
                break
            case .runs(let build):
                resolution.settings[setting] = build.path
                let emulated = build.machine == hostMachine ? "" : " (\(build.machineName), through this machine's user-mode emulation)"
                resolution.notes.append("\(setting) names the macOS executable \(tool); building with the Linux one beside it, \(build.path)\(emulated)")
                resolution.applied.append("\(setting) is \(build.path)\(emulated)")
            case .several(let builds):
                let listed = builds.map(\.path).joined(separator: ", ")
                resolution.warnings.append("\(setting) names the macOS executable \(tool), and more than one Linux build fits this machine (\(listed)): name one on the command line, \(setting)=<path>")
            case .otherMachines(let builds):
                let message = cannotRun(setting: setting, tool: tool, builds: builds)
                let name = ((found.executables.first ?? setting) as NSString).lastPathComponent
                let standIn = scratch + "/machine-tools/" + MD5.hex(setting + tool) + "/" + name
                try FileSystem.write(Data(standInScript(message: message).utf8), to: standIn)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: standIn)
                resolution.settings[setting] = standIn
                resolution.warnings.append(message)
                resolution.applied.append("\(setting) stops the build, if the build runs it, and says what to install")
            }
        }
        return resolution
    }

    static func cannotRun(setting: String, tool: String, builds: [Build]) -> String {
        let listed = builds.map { "\($0.path) (\($0.machineName))" }.joined(separator: ", ")
        let host = Build(path: "", machine: hostMachine).machineName
        return "\(setting) names the macOS executable \(tool), and this \(host) machine cannot run the Linux build beside it, \(listed), without user-mode emulation: install qemu-user-static (Docker Desktop has emulation), or build on a machine of that architecture"
    }

    static func standInScript(message: String) -> String {
        "#!/bin/sh\necho 'error: \(message.replacingOccurrences(of: "'", with: "'\\''"))' >&2\nexit 1\n"
    }
}
