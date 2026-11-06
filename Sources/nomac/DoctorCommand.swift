import ArgumentParser
import Foundation
import NomacBuild
import NomacCore
import NomacDevice
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
                printLaunchersOnPath(developerDirectory: entry.developerDirectory)
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
        #if !os(macOS)
        printUSBMux()
        #endif
    }

    /// Installing on a device goes through usbmuxd, which a Linux machine may not have.
    func printUSBMux() {
        let host = USBMuxHost.current
        guard let daemon = host.daemon() else {
            print("[missing] usbmuxd: nomac install, run and test reach a device through it")
            print("          install: sudo apt-get install -y usbmuxd (or dnf, pacman, zypper)")
            return
        }
        print("[ok] usbmuxd at \(daemon)" + (host.exists("/var/run/usbmuxd") ? ": running" : ": starts when a device is plugged in"))
    }

    /// Off macOS, `xcodebuild` and `xcrun` are the launchers `nomac toolchain install` writes into
    /// the developer directory's `usr/bin`; tools that run them outside a build, as CocoaPods'
    /// `pod install` does for React Native's Podfile (`xcodebuild -version`), find them on PATH,
    /// in that folder or as the forwarders the install writes beside a linked nomac.
    func printLaunchersOnPath(developerDirectory: String) {
        let bin = developerDirectory + "/usr/bin"
        let launcher = bin + "/xcodebuild"
        guard FileSystem.exists(launcher) else { return }
        let found = Subprocess.locate("xcodebuild")
        let forwarder = Data(LinuxToolchain.forwarder("xcodebuild", developerDirectory: developerDirectory).utf8)
        if found.map(FileSystem.resolvingSymbolicLinks) == FileSystem.resolvingSymbolicLinks(launcher) {
            print("[ok] xcodebuild and xcrun on PATH: \(bin)")
        } else if let found, FileSystem.contents(atPath: found) == forwarder {
            print("[ok] xcodebuild and xcrun on PATH: \((found as NSString).deletingLastPathComponent)")
        } else {
            print("[missing] xcodebuild and xcrun on PATH: tools outside a build run them (CocoaPods' pod install)")
            print("          add: export PATH=\(bin):$PATH")
        }
    }
}
