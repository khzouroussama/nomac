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
        every test passed. A trailing 'test-without-building' action is accepted. With \
        -resultBundlePath, writes an .xcresult that xcresulttool reads (docs/formats/xcresult.md).

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

    @Option(name: .customLong("resultBundlePath", withSingleDash: true), help: "Write a result bundle here (.xcresult), which must not exist.")
    var resultBundlePath: String?

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
        let bundlePath = resultBundlePath.map(FileSystem.absolute)
        if let bundlePath, FileManager.default.fileExists(atPath: bundlePath) {
            throw NomacError("Existing file at -resultBundlePath \"\(bundlePath)\"", exitStatus: 64)
        }
        print("Command line invocation:\n    \(CommandLine.arguments.joined(separator: " "))\n")
        if let bundlePath { print("Writing result bundle at path:\n\t\(bundlePath)\n") }
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
        let started = Date()
        var configurations: [ResultBundle.Configuration] = []
        for option in Array(Set(run.entries.flatMap(\.unappliedOptions))).sorted() {
            FileHandle.standardError.write(Data("warning: the test plan asks for \(option), which nomac test does not do yet (BACKLOG B-408)\n".utf8))
        }
        for entry in run.entries {
            let only = Self.selection(onlyTesting, of: entry.name)
            let skipped = Self.selection(skipTesting, of: entry.name)
            if !onlyTesting.isEmpty && only == nil { continue }
            if skipped == [] { continue }
            var barriers = OutputBarrierFilter()
            var printed: [UInt8] = []
            let result = try tests.run(try run.target(entry, testsToRun: only ?? [], testsToSkip: skipped ?? [])) { bytes in
                let filtered = barriers.filter(bytes)
                printed += filtered
                FileHandle.standardOutput.write(Data(filtered))
            }
            let remainder = barriers.finish()
            printed += remainder
            FileHandle.standardOutput.write(Data(remainder))
            if let error = result.bootstrapError {
                FileHandle.standardError.write(Data("\(entry.name): error: \(error)\n".utf8))
            }
            failed = failed || result.failed
            let testable = ResultBundle.Testable(name: entry.name, projectRelativePath: entry.projectRelativePath, isUITest: entry.isUITest, language: entry.language, region: entry.region,
                                                 cases: ResultBundle.attaching(ResultBundle.notes(in: String(decoding: printed, as: UTF8.self)), to: result.cases))
            let configuration = entry.configuration ?? "Test Scheme Action"
            if configurations.last?.name == configuration {
                configurations[configurations.count - 1].testables.append(testable)
            } else {
                configurations.append(ResultBundle.Configuration(name: configuration, testables: [testable]))
            }
        }
        if let bundlePath {
            func text(_ key: String) -> String { if case .string(let value)? = try? session.value(key: key) { value } else { "" } }
            let identity = ResultBundle.Device(name: text("DeviceName"), identifier: device, operatingSystemVersion: text("ProductVersion"), buildVersion: text("BuildVersion"),
                                               model: text("ProductType"), architecture: text("CPUArchitecture"))
            try ResultBundle(scheme: run.schemeName, containerName: run.containerName, planName: run.planName ?? run.schemeName, device: identity, sdkVersion: run.sdkVersion,
                             started: started, finished: Date(), configurations: configurations).write(to: bundlePath)
            print("Test session results, code coverage, and logs:\n\t\(bundlePath)\n")
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
