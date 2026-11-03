import Foundation
import NomacCore
import NomacDevice
import NomacSigning

extension TunnelTCPConnection: PollableStream {}

/// What testmanagerd's sessions exchange (docs/formats/xctest-device.md): the selectors of
/// `XCTestManager_DaemonConnectionInterface` and `XCTestDriverInterface`, and the archived
/// `XCTCapabilities` and `XCTestConfiguration`, as go-ios's `testmanagerd` package and
/// pymobiledevice3's `testmanaged` sends them to iOS 17 and later.
public enum TestManager {
    public static let serviceName = "com.apple.dt.testmanagerd.remote"
    public static let daemonChannel = "dtxproxy:XCTestManager_IDEInterface:XCTestManager_DaemonConnectionInterface"
    public static let driverChannel = "dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface"
    /// The protocol version go-ios and pymobiledevice3 start test plans with.
    public static let protocolVersion = 36

    /// The capabilities the IDE announces when it starts a session.
    public static let ideCapabilities: [String] = [
        "XCTIssue capability", "daemon container sandbox extension", "delayed attachment transfer",
        "expected failure test capability", "request diagnostics for specific devices", "skipped test capability",
        "test case run configurations", "test iterations", "test timeout capability", "ubiquitous test identifiers",
    ]

    public static func capabilities(_ names: [String], value: Archived = .integer(1)) -> Archived {
        .object(Archived.Object(["XCTCapabilities", "NSObject"], [("capabilities-dictionary", .keyed(names.map { ($0, value) }))]))
    }

    /// The test configuration the runner asks for in `_XCT_testRunnerReadyWithCapabilities:`.
    public static func configuration(session: UUID, testBundlePath: String, productModuleName: String, target: TestTarget.Application?,
                                     testsToRun: [String] = [], testsToSkip: [String] = []) -> Archived {
        var fields: [(String, Archived)] = [
            ("aggregateStatisticsBeforeCrash", .keyed([("XCSuiteRecordsKey", .keyed([]))])),
            ("automationFrameworkPath", .string("/System/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework")),
            ("baselineFileRelativePath", .null),
            ("baselineFileURL", .null),
            ("defaultTestExecutionTimeAllowance", .null),
            ("disablePerformanceMetrics", .boolean(false)),
            ("emitOSLogs", .boolean(false)),
            ("gatherLocalizableStringsData", .boolean(false)),
            ("initializeForUITesting", .boolean(target != nil)),
            ("maximumTestExecutionTimeAllowance", .null),
            ("randomExecutionOrderingSeed", .null),
            ("reportActivities", .boolean(true)),
            ("reportResultsToIDE", .boolean(true)),
            ("sessionIdentifier", .uuid(bytes(session))),
            ("systemAttachmentLifetime", .integer(2)),
            ("testApplicationUserOverrides", .null),
            ("testBundleRelativePath", .null),
            ("testBundleURL", .url("file://" + testBundlePath)),
            ("testExecutionOrdering", .integer(0)),
            ("testsDrivenByIDE", .boolean(false)),
            ("testsMustRunOnMainThread", .boolean(true)),
            ("testTimeoutsEnabled", .boolean(false)),
            ("treatMissingBaselinesAsFailures", .boolean(false)),
            ("userAttachmentLifetime", .integer(0)),
            ("preferredScreenCaptureFormat", .integer(2)),
            ("IDECapabilities", capabilities(ideCapabilities, value: .boolean(true))),
        ]
        if let target {
            fields += [
                ("productModuleName", .string(productModuleName)),
                ("targetApplicationBundleID", .string(target.bundleIdentifier)),
                ("targetApplicationPath", .string(target.path)),
                ("targetApplicationArguments", .array(target.arguments.map { .string($0) })),
                ("targetApplicationEnvironment", .keyed(target.environment.sorted { $0.key < $1.key }.map { ($0.key, .string($0.value)) })),
            ]
        }
        if !testsToRun.isEmpty {
            fields += [("testsToRun", .set(testsToRun.map { .string($0) })), ("testIdentifiersToRun", identifierSet(testsToRun))]
        }
        if !testsToSkip.isEmpty {
            fields += [("testsToSkip", .set(testsToSkip.map { .string($0) })), ("testIdentifiersToSkip", identifierSet(testsToSkip))]
        }
        return .object(Archived.Object(["XCTestConfiguration", "NSObject"], fields))
    }

    /// `XCTTestIdentifierSet` of `Class` or `Class/method` names: options 3 for a class, 2 for a method.
    static func identifierSet(_ names: [String]) -> Archived {
        .object(Archived.Object(["XCTTestIdentifierSet", "NSObject"], [("identifiers", .array(names.map { name in
            let components = name.split(separator: "/").map(String.init)
            return .object(Archived.Object(["XCTTestIdentifier", "NSObject"], [
                ("c", .array(components.map { .string($0) })), ("o", .integer(components.count == 1 ? 3 : 2)),
            ]))
        }))]))
    }

    static func bytes(_ uuid: UUID) -> [UInt8] {
        withUnsafeBytes(of: uuid.uuid, Array.init)
    }
}

/// One test bundle to run: its host on the device and how to launch it.
public struct TestTarget: Sendable {
    public struct Application: Sendable {
        public var bundleIdentifier: String
        public var path: String
        public var arguments: [String]
        public var environment: [String: String]

        public init(bundleIdentifier: String, path: String, arguments: [String] = [], environment: [String: String] = [:]) {
            self.bundleIdentifier = bundleIdentifier
            self.path = path
            self.arguments = arguments
            self.environment = environment
        }
    }

    public var name: String
    public var hostBundleIdentifier: String
    /// The test bundle's path in its host, `PlugIns/<name>.xctest`.
    public var testBundleRelativePath: String
    public var productModuleName: String
    public var isUITest: Bool
    /// The app a UI test drives, by bundle identifier (its path is looked up on the device).
    public var targetApplication: String?
    public var arguments: [String]
    public var environment: [String: String]
    public var targetArguments: [String]
    public var targetEnvironment: [String: String]
    public var testsToRun: [String]
    public var testsToSkip: [String]

    public init(name: String, hostBundleIdentifier: String, testBundleRelativePath: String, productModuleName: String, isUITest: Bool,
                targetApplication: String? = nil, arguments: [String] = [], environment: [String: String] = [:],
                targetArguments: [String] = [], targetEnvironment: [String: String] = [:], testsToRun: [String] = [], testsToSkip: [String] = []) {
        self.name = name
        self.hostBundleIdentifier = hostBundleIdentifier
        self.testBundleRelativePath = testBundleRelativePath
        self.productModuleName = productModuleName
        self.isUITest = isUITest
        self.targetApplication = targetApplication
        self.arguments = arguments
        self.environment = environment
        self.targetArguments = targetArguments
        self.targetEnvironment = targetEnvironment
        self.testsToRun = testsToRun
        self.testsToSkip = testsToSkip
    }
}

/// A test case's outcome, as `_XCT_testCaseWithIdentifier:didFinishWithStatus:duration:` reports it.
public struct TestCaseResult: Equatable, Sendable {
    public var testClass: String
    public var method: String
    /// `passed`, `failed`, `skipped` or `expected failure`.
    public var status: String
    public var duration: Double
}

public struct TestRunResult: Sendable {
    public var cases: [TestCaseResult] = []
    /// The plan finished (`_XCT_didFinishExecutingTestPlan`); false when the runner went away first.
    public var finished = false
    public var bootstrapError: String?

    public var failed: Bool { !finished || bootstrapError != nil || cases.contains { $0.status == "failed" } }
}

/// Runs a test bundle on a device: two testmanagerd sessions in the CoreDevice tunnel, the host
/// launched by the app service with its standard output and error on one stdio socket, the
/// runner's callbacks answered until the plan finishes, then the host killed (the order go-ios
/// follows for iOS 17 and later, and the services Xcode 27.0's CoreDeviceService opened for
/// `xcodebuild test`, observed in the Mac's log: docs/formats/xctest-device.md).
public final class DeviceTestSession {
    public static let stdioServiceName = "com.apple.coredevice.openstdiosocket"
    public static let signalFeature = "com.apple.coredevice.feature.sendsignaltoprocess"

    private let session: DeviceSession

    public init(session: DeviceSession) {
        self.session = session
    }

    /// The installed apps' `Path`, `Container` and `CFBundleExecutable` by bundle identifier,
    /// from installation_proxy's `Lookup`.
    public func lookup(_ bundleIdentifiers: [String]) throws -> [String: [String: String]] {
        let stream = try session.service(InstallationProxy.serviceName)
        try PropertyListMessages.send([
            "Command": .string("Lookup"),
            "ClientOptions": .dictionary([
                "BundleIDs": .array(bundleIdentifiers.map { .string($0) }),
                "ReturnAttributes": .array(["CFBundleIdentifier", "CFBundleExecutable", "Path", "Container"].map { .string($0) }),
            ]),
        ], on: stream)
        var apps: [String: [String: String]] = [:]
        while true {
            let reply = try PropertyListMessages.receive(from: stream, source: "installation_proxy")
            if case .dictionary(let result)? = reply["LookupResult"] {
                for (identifier, attributes) in result {
                    guard case .dictionary(let values) = attributes else { continue }
                    apps[identifier] = values.compactMapValues { if case .string(let text) = $0 { text } else { nil } }
                }
            }
            if try InstallationProxy.status(reply).status == "Complete" { return apps }
        }
    }

    /// The environment the host is launched with: the `.xctestrun`'s, with the variables that
    /// point XCTest at the session (go-ios's `startTestRunner17`).
    public static func launchEnvironment(_ target: TestTarget, hostPath: String, session: UUID) -> [String: String] {
        var environment = target.environment.mapValues { $0.replacingOccurrences(of: "__TESTHOST__", with: hostPath) }
        environment["DYLD_FRAMEWORK_PATH"] = "/System/Developer/Library/Frameworks"
        environment["DYLD_LIBRARY_PATH"] = "/System/Developer/usr/lib"
        environment["NSUnbufferedIO"] = "YES"
        environment["XCTestBundlePath"] = hostPath + "/" + target.testBundleRelativePath
        environment["XCTestConfigurationFilePath"] = ""
        environment["XCTestManagerVariant"] = "DDI"
        environment["XCTestSessionIdentifier"] = session.uuidString
        if let libraries = environment["DYLD_INSERT_LIBRARIES"] {
            environment["DYLD_INSERT_LIBRARIES"] = libraries.split(separator: ":").map { library in
                library.hasSuffix("/libXCTestBundleInject.dylib") ? "/System/Developer/usr/lib/libXCTestBundleInject.dylib" : String(library)
            }.joined(separator: ":")
        }
        return environment
    }

    /// The app service's launch input with the stdio socket for standard input, output and
    /// error, and the launch options as a property list (`platformSpecificOptions`).
    public static func launchInput(bundleIdentifier: String, arguments: [String], environment: [String: String], options: [String: PropertyListValue],
                                   stdio: [UInt8]) -> XPCObject {
        .dictionary([
            .init("applicationSpecifier", .dictionary([.init("bundleIdentifier", .dictionary([.init("_0", .string(bundleIdentifier))]))])),
            .init("options", .dictionary([
                .init("arguments", .array(arguments.map { .string($0) })),
                .init("environmentVariables", .dictionary(environment.keys.sorted().map { .init($0, .string(environment[$0]!)) })),
                .init("standardIOUsesPseudoterminals", .bool(true)),
                .init("startStopped", .bool(false)),
                .init("terminateExisting", .bool(true)),
                .init("user", .dictionary([.init("shortName", .string("mobile"))])),
                .init("platformSpecificOptions", .data(PropertyListValue.xmlDocument(.dictionary(options)))),
            ])),
            .init("standardIOIdentifiers", .dictionary([
                .init("standardInput", .uuid(stdio)), .init("standardOutput", .uuid(stdio)), .init("standardError", .uuid(stdio)),
            ])),
        ])
    }

    /// Runs `target`, handing the host's output to `output` as it arrives.
    public func run(_ target: TestTarget, output: ([UInt8]) -> Void) throws -> TestRunResult {
        let wanted = [target.hostBundleIdentifier] + (target.targetApplication.map { [$0] } ?? [])
        let apps = try lookup(wanted)
        guard let host = apps[target.hostBundleIdentifier], let hostPath = host["Path"] else {
            throw NomacError("\(target.hostBundleIdentifier) is not installed on the device")
        }
        var application: TestTarget.Application?
        if let identifier = target.targetApplication {
            guard let path = apps[identifier]?["Path"] else { throw NomacError("\(identifier) is not installed on the device") }
            application = .init(bundleIdentifier: identifier, path: path, arguments: target.targetArguments, environment: target.targetEnvironment)
        }

        let (network, ports) = try session.openCoreDevice()
        func port(_ name: String) throws -> UInt16 {
            guard let port = ports[name] else {
                let mounted = (try? session.developerDiskImageMounted()) ?? false
                throw NomacError("the device lists no \(name)", notes: mounted ? [] : [DeviceSession.developerDiskImageNote])
            }
            return port
        }
        let wait = { try network.receivePacket() }
        let identifier = UUID()
        let configuration = TestManager.configuration(session: identifier, testBundlePath: hostPath + "/" + target.testBundleRelativePath,
                                                      productModuleName: target.productModuleName, target: application,
                                                      testsToRun: target.testsToRun, testsToSkip: target.testsToSkip)

        let main = DTXConnection(stream: try network.connect(port: try port(TestManager.serviceName)))
        let control = DTXConnection(stream: try network.connect(port: try port(TestManager.serviceName)))
        let mainChannel = try main.openChannel(TestManager.daemonChannel, wait: wait)
        let started = try main.send("_IDE_initiateSessionWithIdentifier:capabilities:",
                                    [.object(.uuid(TestManager.bytes(identifier))), .object(TestManager.capabilities(TestManager.ideCapabilities))],
                                    channel: mainChannel)
        var result = TestRunResult()
        var events: [DTXMessage] = []
        _ = try main.reply(to: started, wait: wait) { events.append($0) }

        let stdio = try network.connect(port: try port(Self.stdioServiceName))
        let stdioIdentifier = try stdio.read(16)
        let appService = try RemoteXPCConnection(stream: try network.connect(port: try port(AppService.serviceName)))
        let options: [String: PropertyListValue] = target.isUITest
            ? ["ActivateSuspended": .integer(1), "StartSuspendedKey": .integer(0), "__ActivateSuspended": .integer(1)] : [:]
        let launched = try CoreDeviceService.invoke(AppService.launchFeature, input: Self.launchInput(
            bundleIdentifier: target.hostBundleIdentifier, arguments: target.arguments,
            environment: Self.launchEnvironment(target, hostPath: hostPath, session: identifier), options: options, stdio: stdioIdentifier),
                                                    on: appService)
        guard let pid = AppService.processIdentifier(launched) else { throw NomacError("the device launched \(target.hostBundleIdentifier) without a process identifier") }

        let controlChannel = try control.openChannel(TestManager.daemonChannel, wait: wait)
        let controlStarted = try control.send("_IDE_initiateControlSessionWithCapabilities:", [.object(TestManager.capabilities([]))], channel: controlChannel)
        _ = try control.reply(to: controlStarted, wait: wait)
        let authorized = try control.send("_IDE_authorizeTestSessionWithProcessID:", [.object(.integer(Int(pid)))], channel: controlChannel)
        _ = try control.reply(to: authorized, wait: wait) { events.append($0) }

        func handle(_ message: DTXMessage, on connection: DTXConnection) throws {
            guard message.kind == .dispatch, let selector = message.selector else { return }
            switch selector {
            case "_XCT_testRunnerReadyWithCapabilities:":
                try connection.reply(to: message, with: configuration)
                try connection.send("_IDE_startExecutingTestPlanWithProtocolVersion:", [.object(.integer(TestManager.protocolVersion))],
                                    channel: connection.key(of: message), expectsReply: false)
                return
            case "_XCT_didFinishExecutingTestPlan":
                result.finished = true
            case "_XCT_didFailToBootstrapWithError:", "_XCT_initializationForUITestingDidFailWithError:":
                result.bootstrapError = DTXConnection.describe(try? message.arguments.first?.archived())
            case "_XCT_testCaseWithIdentifier:didFinishWithStatus:duration:":
                if message.arguments.count == 3, case .object(let test) = try message.arguments[0].archived(),
                   case .array(let components)? = test["c"] {
                    let names = components.compactMap(\.string)
                    result.cases.append(TestCaseResult(testClass: names.first ?? "", method: names.dropFirst().first ?? "",
                                                       status: try message.arguments[1].archived().string ?? "",
                                                       duration: try message.arguments[2].archived().real ?? 0))
                }
            default:
                break
            }
            if message.expectsReply { try connection.reply(to: message) }
        }

        for event in events { try handle(event, on: main) }
        while !result.finished && result.bootstrapError == nil {
            var progressed = false
            for connection in [main, control] {
                while let message = try connection.next() {
                    try handle(message, on: connection)
                    progressed = true
                }
            }
            if stdio.availableCount > 0 {
                output(try stdio.read(stdio.availableCount))
                progressed = true
            }
            if stdio.isClosed && !progressed { break }
            if !progressed { try wait() }
        }
        _ = try? CoreDeviceService.invoke(Self.signalFeature, input: .dictionary([
            .init("process", .dictionary([.init("processIdentifier", .int64(pid))])), .init("signal", .int64(9)),
        ]), on: appService)
        while !stdio.isClosed {
            if stdio.availableCount > 0 { output(try stdio.read(stdio.availableCount)) } else { try wait() }
        }
        if stdio.availableCount > 0 { output(try stdio.read(stdio.availableCount)) }
        return result
    }
}
