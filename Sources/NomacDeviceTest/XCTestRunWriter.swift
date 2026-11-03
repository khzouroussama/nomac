import Foundation
import NomacPlist

/// What `build-for-testing` built, as the `.xctestrun` describes it.
public struct TestBuildDescription: Sendable {
    public struct Product: Sendable {
        public enum Kind: Sendable { case application, unitTest, uiTest, other }

        public var name: String
        public var moduleName: String
        public var bundleIdentifier: String
        /// The product's path in the build products folder (`Debug-iphoneos/App.app`).
        public var path: String
        public var executableName: String
        public var kind: Kind
        /// A unit test's host app, by product path, or nil for an unhosted bundle.
        public var hostPath: String?
        /// A UI test's target app (`TEST_TARGET_NAME`), by product path.
        public var targetApplicationPath: String?

        public init(name: String, moduleName: String, bundleIdentifier: String, path: String, executableName: String, kind: Kind,
                    hostPath: String? = nil, targetApplicationPath: String? = nil) {
            self.name = name
            self.moduleName = moduleName
            self.bundleIdentifier = bundleIdentifier
            self.path = path
            self.executableName = executableName
            self.kind = kind
            self.hostPath = hostPath
            self.targetApplicationPath = targetApplicationPath
        }

        /// A UI test's runner app: the platform's `XCTRunner.app` copied as `<name>-Runner.app`
        /// around the bundle, identified as the bundle with `.xctrunner`.
        var runnerPath: String { ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent }
    }

    public var schemeName: String
    public var containerName: String
    public var projectName: String
    /// The project's path from the container's folder (`App.xcodeproj`).
    public var projectPath: String
    /// The built products in build order.
    public var products: [Product]
    /// The scheme's testables, by name, in its order.
    public var testables: [String]
    public var arguments: [String]
    public var environment: [String: String]
    /// The SDK and architecture of the file name (`iphoneos27.0`, `arm64`).
    public var sdkName: String
    public var architecture: String

    public init(schemeName: String, containerName: String, projectName: String, projectPath: String, products: [Product], testables: [String],
                arguments: [String], environment: [String: String], sdkName: String, architecture: String) {
        self.schemeName = schemeName
        self.containerName = containerName
        self.projectName = projectName
        self.projectPath = projectPath
        self.products = products
        self.testables = testables
        self.arguments = arguments
        self.environment = environment
        self.sdkName = sdkName
        self.architecture = architecture
    }
}

/// The `.xctestrun` Xcode 27.0 writes for a scheme with testables, format 1
/// (docs/formats/xctestrun.md, `xctest_experiments.py` `xctestrun-*`).
public enum XCTestRunWriter {
    /// Xcode's variables for every test process, before the scheme's.
    static let defaultEnvironment: [String: String] = [
        "APP_DISTRIBUTOR_ID_OVERRIDE": "com.apple.AppStore", "DYLD_INSERT_LIBRARIES": "/usr/lib/libRPAC.dylib",
        "IDE_CHOSEN_LOGGING_METHOD": "1", "OS_ACTIVITY_DT_MODE": "YES", "PERFC_ENABLE_EXTENDED_DIAGNOSTIC_FORMAT": "1",
        "PERFC_ENABLE_PROFILE_MODE": "1", "PERFC_RESET_INSERT_LIBRARIES": "1", "PERFC_SUPPRESS_SYSTEM_REPORTS": "1",
        "SQLITE_ENABLE_THREAD_ASSERTIONS": "1", "TERM": "dumb",
    ]
    /// The host of an unhosted test bundle.
    static let unhostedHost = "__PLATFORMS__/iPhoneOS.platform/Developer/Library/Xcode/Agents/xctest"

    public static func fileName(_ build: TestBuildDescription) -> String {
        "\(build.schemeName)_\(build.sdkName)-\(build.architecture).xctestrun"
    }

    public static func data(_ build: TestBuildDescription) -> Data {
        XMLPropertyList.data(value(build))
    }

    static func value(_ build: TestBuildDescription) -> PropertyListValue {
        var top: [String: PropertyListValue] = [
            "__xctestrun_metadata__": .dictionary([
                "ContainerInfo": .dictionary(["ContainerName": .string(build.containerName), "SchemeName": .string(build.schemeName)]),
                "FormatVersion": .integer(1),
            ]),
        ]
        let bundles = build.products.filter { $0.kind != .other }
        let testProducts = bundles.filter { $0.kind == .unitTest || $0.kind == .uiTest }
        let runners = bundles.filter { $0.kind == .uiTest }.map(\.runnerPath)
        let dependents = Array(Set(bundles.map(\.path) + runners)).sorted().map { "__TESTROOT__/" + $0 }
        let identifiers = Array(Set(bundles.map(\.bundleIdentifier))).sorted()
        let processes = Array(Set(bundles.filter { $0.kind == .application }.map(\.executableName)
            + testProducts.filter { $0.kind == .uiTest }.map { $0.name + "-Runner" })).sorted()
        let environment = defaultEnvironment.merging(build.environment) { $1 }
        for (order, name) in build.testables.enumerated() {
            guard let product = testProducts.first(where: { $0.name == name }) else { continue }
            var entry: [String: PropertyListValue] = [
                "BlueprintName": .string(product.name),
                "BlueprintProviderName": .string(build.projectName),
                "BlueprintProviderRelativePath": .string(build.projectPath),
                "BundleIdentifiersForCrashReportEmphasis": .array(identifiers.map { .string($0) }),
                "CommandLineArguments": .array(build.arguments.map { .string($0) }),
                "DefaultTestExecutionTimeAllowance": .integer(600),
                "DependentProductPaths": .array(dependents.map { .string($0) }),
                "DiagnosticCollectionPolicy": .integer(1),
                "EnvironmentVariables": .dictionary(environment.mapValues { .string($0) }),
                "IsMemoryTaggingAddressSanitizerEnabled": .boolean(false),
                "PreferredScreenCaptureFormat": .string("screenRecording"),
                "ProcessNamesForCrashReportCollection": .array(processes.map { .string($0) }),
                "ProductModuleName": .string(product.moduleName),
                "RunOrder": .integer(order),
                "SystemAttachmentLifetime": .string("deleteOnSuccess"),
                "TestInteropMode": .string("complete"),
                "TestLanguage": .string(""),
                "TestRegion": .string(""),
                "TestTimeoutsEnabled": .boolean(false),
                "ToolchainsSettingValue": .array([]),
                "UserAttachmentLifetime": .string("deleteOnSuccess"),
            ]
            var testing: [String: PropertyListValue] = ["XCODE_SCHEME_NAME": .string(build.schemeName)]
            switch product.kind {
            case .uiTest:
                let runner = product.runnerPath
                entry["IsUITestBundle"] = .boolean(true)
                entry["IsXCTRunnerHostedTestBundle"] = .boolean(true)
                entry["TestBundlePath"] = .string("__TESTHOST__/PlugIns/" + (product.path as NSString).lastPathComponent)
                entry["TestHostBundleIdentifier"] = .string(product.bundleIdentifier + ".xctrunner")
                entry["TestHostPath"] = .string("__TESTROOT__/" + runner)
                entry["UITargetAppCommandLineArguments"] = .array([])
                entry["UITargetAppEnvironmentVariables"] = .dictionary([
                    "APP_DISTRIBUTOR_ID_OVERRIDE": .string("com.apple.AppStore"), "XCODE_SCHEME_NAME": .string(build.schemeName),
                ])
                if let target = product.targetApplicationPath { entry["UITargetAppPath"] = .string("__TESTROOT__/" + target) }
                entry["UITargetAppPerformanceAntipatternCheckerEnabled"] = .boolean(true)
            default:
                if let host = product.hostPath, let hostProduct = bundles.first(where: { $0.path == host }) {
                    entry["IsAppHostedTestBundle"] = .boolean(true)
                    entry["TestBundlePath"] = .string("__TESTHOST__/" + String(product.path.dropFirst(host.count + 1)))
                    entry["TestHostBundleIdentifier"] = .string(hostProduct.bundleIdentifier)
                    entry["TestHostPath"] = .string("__TESTROOT__/" + host)
                    testing["DYLD_INSERT_LIBRARIES"] = .string("__TESTHOST__/Frameworks/libXCTestBundleInject.dylib:/usr/lib/libRPAC.dylib")
                    testing["XCInjectBundleInto"] = .string("unused")
                } else {
                    entry["TestBundlePath"] = .string("__TESTROOT__/" + product.path)
                    entry["TestHostPath"] = .string(unhostedHost)
                    testing["DYLD_INSERT_LIBRARIES"] = .string("/usr/lib/libRPAC.dylib")
                }
                testing["PERFC_SUPPRESS_SYSTEM_REPORTS"] = .string("1")
            }
            entry["TestingEnvironmentVariables"] = .dictionary(testing)
            top[name] = .dictionary(entry)
        }
        return .dictionary(top)
    }
}
