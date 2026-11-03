import ArgumentParser
import Foundation
import NomacCore
import NomacSDK

/// `nomac doctor`: report what nomac needs and whether it is present.
struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check the installed Xcode and tools."
    )

    func run() throws {
        print(NomacVersion.full)
        let store = SDKStore.default()
        let entries = try store.entries()
        if entries.isEmpty {
            print("[missing] Xcode SDK: none installed (run 'nomac sdk install <Xcode.xip | Xcode.app>')")
        } else {
            let selected = store.selectedBuild()
            for entry in entries {
                let note = entry.version.build == selected ? " (selected)" : ""
                let reproduced = entry.version.build == XcodeProfile.current.xcode.build
                print("[\(reproduced ? "ok" : "warning")] Xcode \(entry.version.version) (\(entry.version.build))\(note): \(entry.developerDirectory)"
                      + (reproduced ? "" : " (nomac \(NomacVersion.current) reproduces Xcode \(XcodeProfile.current.xcode.version) (\(XcodeProfile.current.xcode.build)) only)"))
            }
            #if !os(macOS)
            if let entry = entries.first(where: { $0.version.build == selected }) {
                printLaunchersOnPath(entry.developerDirectory + "/usr/bin")
            }
            #endif
        }
        for tool in ExternalTools.all {
            if let path = tool.locate() {
                let result = try? Subprocess.run(path, tool.versionArguments)
                let reported = (result?.outputString ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
                let matches = reported.contains(tool.pinnedVersion)
                print("[\(matches ? "ok" : "warning")] \(tool.executable) at \(path): \(reported.isEmpty ? "version unknown" : reported) (nomac is tested with \(tool.pinnedVersion))")
            } else {
                print("[missing] \(tool.executable): \(tool.purpose)")
                print("          install: \(tool.installation)")
            }
        }
    }

    /// Off macOS, `xcodebuild` and `xcrun` are the launchers `nomac toolchain install` writes into
    /// the developer directory's `usr/bin`; tools that run them outside a build, as CocoaPods'
    /// `pod install` does for React Native's Podfile (`xcodebuild -version`), find them on PATH.
    func printLaunchersOnPath(_ bin: String) {
        let launcher = bin + "/xcodebuild"
        guard FileSystem.exists(launcher) else { return }
        if Subprocess.locate("xcodebuild").map(FileSystem.resolvingSymbolicLinks) == FileSystem.resolvingSymbolicLinks(launcher) {
            print("[ok] xcodebuild and xcrun on PATH: \(bin)")
        } else {
            print("[missing] xcodebuild and xcrun on PATH: tools outside a build run them (CocoaPods' pod install)")
            print("          add: export PATH=\(bin):$PATH")
        }
    }
}
