import ArgumentParser
import Foundation
import NomacCore
import NomacDevice
import NomacDeviceTest

/// `nomac test`: an `.xctestrun`'s test bundles on a device, as `xcodebuild test-without-building
/// -xctestrun` runs them (docs/formats/xctest-device.md).
struct TestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run an .xctestrun's tests on a device.",
        discussion: """
        Installs the apps the .xctestrun depends on, then runs each test target in its run order: \
        the host app (or the UI test runner) launched by the CoreDevice app service, its tests \
        driven through testmanagerd, its output printed as it arrives. The status is 0 when \
        every test passed. A trailing 'test-without-building' action is accepted.

        Example:
          nomac test -xctestrun Build/Products/App_iphoneos27.0-arm64.xctestrun \\
              -destination 'platform=iOS,id=<UDID>'
        """
    )

    @Option(name: .customLong("xctestrun", withSingleDash: true), help: "The .xctestrun 'xcodebuild build-for-testing' wrote.")
    var xctestrun: String

    @Option(name: .customLong("destination", withSingleDash: true), help: "The device, as 'platform=iOS,id=<UDID>'.")
    var destination: String

    @Option(name: .customLong("only-testing", withSingleDash: true), help: "Run only this target, class or test (Target[/Class[/test]]); repeatable.")
    var onlyTesting: [String] = []

    @Option(name: .customLong("skip-testing", withSingleDash: true), help: "Skip this target, class or test; repeatable.")
    var skipTesting: [String] = []

    @Option(name: .customLong("ddi"), help: "The Developer Disk Image to mount when the device has none (default: the one 'nomac sdk install' extracted).")
    var ddi: String?

    @Argument(help: "xcodebuild's action, 'test-without-building'.")
    var actions: [String] = []

    func run() throws {
        guard actions.allSatisfy({ $0 == "test-without-building" }) else {
            throw NomacError("nomac test takes the action 'test-without-building', not '\(actions.joined(separator: " "))'")
        }
        let device = try Self.deviceIdentifier(destination)
        let run = try XCTestRun(path: FileSystem.absolute(xctestrun))
        print("Command line invocation:\n    \(CommandLine.arguments.joined(separator: " "))\n")
        fflush(nil)
        FileHandle.standardError.write(Data("Testing started\n".utf8))

        let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
        try mountDeveloperDiskImageIfNeeded(session, ddi: ddi)
        for app in run.applications {
            try session.install(ipa: try ipaBytes(app, device: device), name: ((app as NSString).lastPathComponent as NSString).deletingPathExtension + ".ipa",
                                progress: { _, _ in })
        }
        let tests = DeviceTestSession(session: session)
        var failed = false
        for entry in run.entries {
            let only = Self.selection(onlyTesting, of: entry.name)
            let skipped = Self.selection(skipTesting, of: entry.name)
            if !onlyTesting.isEmpty && only == nil { continue }
            if skipped == [] { continue }
            var barriers = OutputBarrierFilter()
            let result = try tests.run(try run.target(entry, testsToRun: only ?? [], testsToSkip: skipped ?? [])) { bytes in
                FileHandle.standardOutput.write(Data(barriers.filter(bytes)))
            }
            FileHandle.standardOutput.write(Data(barriers.finish()))
            if let error = result.bootstrapError {
                FileHandle.standardError.write(Data("\(entry.name): error: \(error)\n".utf8))
            }
            failed = failed || result.failed
        }
        print(failed ? "** TEST EXECUTE FAILED **\n" : "** TEST EXECUTE SUCCEEDED **\n")
        if failed { throw ExitCode(65) }
    }

    /// The UDID of `platform=iOS,id=<UDID>`.
    static func deviceIdentifier(_ destination: String) throws -> String {
        var fields: [String: String] = [:]
        for field in destination.split(separator: ",") {
            let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        guard fields["platform"] == "iOS", let identifier = fields["id"] else {
            throw NomacError("nomac test runs on a device named by 'platform=iOS,id=<UDID>', not '\(destination)'")
        }
        return identifier
    }

    /// The tests of `target` that `specifiers` (`Target[/Class[/test]]`) name: nil when none
    /// names the target, empty when one names all of it.
    static func selection(_ specifiers: [String], of target: String) -> [String]? {
        var tests: [String]?
        for specifier in specifiers {
            let components = specifier.split(separator: "/", maxSplits: 1).map(String.init)
            guard components.first == target else { continue }
            if components.count == 1 { return [] }
            tests = (tests ?? []) + [components[1]]
        }
        return tests
    }
}
