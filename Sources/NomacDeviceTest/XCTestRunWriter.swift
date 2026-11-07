import Foundation
import NomacPlist

/// What `build-for-testing` built, as the `.xctestrun` describes it.
public struct TestBuildDescription: Sendable {
    /// A built product whose code coverage the run gathers.
    public struct CoverageProduct: Sendable {
        /// The target's identifier in its project.
        public var identifier: String
        /// The product's name (`App.app`).
        public var name: String
        /// The product's binary in the build products folder (`Debug-iphoneos/App.app/App`).
        public var binaryPath: String
        public var isStatic: Bool
        /// The target's compiled files, absolute.
        public var sources: [String]

        public init(identifier: String, name: String, binaryPath: String, isStatic: Bool, sources: [String]) {
            self.identifier = identifier
            self.name = name
            self.binaryPath = binaryPath
            self.isStatic = isStatic
            self.sources = sources
        }
    }

    public struct Product: Sendable {
        /// `wrapper`: a framework or a bundle, which the file lists but does not run. `other`: what
        /// it does not list (a static library, `xctestrun-coverage-libraries`).
        public enum Kind: Sendable { case application, unitTest, uiTest, wrapper, other }

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
    /// The products a run measures: empty when it gathers no coverage.
    public var coverage: [CoverageProduct]
    /// A scheme limited to chosen targets: their identifiers. The others stay out of the report.
    public var coverageReportTargets: Set<String>?
    /// The scheme's test plans; with none, its testables make one file of format 1.
    public var plans: [XCTestPlan]
    /// Format 1: the Test action's language, region and attachment lifetimes, by plan option name.
    public var options: [String: String]
    /// Format 1: what the Test action sets on each testable, by name.
    public var testableOptions: [String: XCTestPlan.Target]

    public init(schemeName: String, containerName: String, projectName: String, projectPath: String, products: [Product], testables: [String],
                arguments: [String], environment: [String: String], sdkName: String, architecture: String, coverage: [CoverageProduct] = [],
                coverageReportTargets: Set<String>? = nil, plans: [XCTestPlan] = [], options: [String: String] = [:], testableOptions: [String: XCTestPlan.Target] = [:]) {
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
        self.coverage = coverage
        self.coverageReportTargets = coverageReportTargets
        self.plans = plans
        self.options = options
        self.testableOptions = testableOptions
    }
}

/// The `.xctestrun` files Xcode 27.0 writes for a scheme: format 1 for its testables, or format 2,
/// one file per test plan (docs/formats/xctestrun.md, `xctest_experiments.py` `xctestrun-*`).
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
    static let profileDataFolder = "__DERIVEDDATA__/Build/ProfileData"
    static let toolchain = "com.apple.dt.toolchain.XcodeDefault"
    /// A scheme's and an autocreated plan's entries have it; those of a plan file do not
    /// (`xctestrun-test-plan`, `-autocreated-plan`).
    static let interoperability = "complete"

    /// Every file the build writes, by name.
    public static func files(_ build: TestBuildDescription) -> [(name: String, data: Data)] {
        if build.plans.isEmpty { return [(fileName(build), XMLPropertyList.data(value(build)))] }
        return build.plans.map { ("\(build.schemeName)_\($0.name)_\(build.sdkName)-\(build.architecture).xctestrun", XMLPropertyList.data(value(build, plan: $0))) }
    }

    public static func fileName(_ build: TestBuildDescription) -> String {
        "\(build.schemeName)_\(build.sdkName)-\(build.architecture).xctestrun"
    }

    static func containerInformation(_ build: TestBuildDescription) -> PropertyListValue {
        .dictionary(["ContainerName": .string(build.containerName), "SchemeName": .string(build.schemeName)])
    }

    /// Format 1: one entry per testable beside the metadata.
    static func value(_ build: TestBuildDescription) -> PropertyListValue {
        var metadata: [String: PropertyListValue] = ["ContainerInfo": containerInformation(build), "FormatVersion": .integer(1)]
        if !build.coverage.isEmpty { metadata["CodeCoverageBuildableInfos"] = coverageInformation(build, reported: build.coverageReportTargets, plural: false) }
        var top: [String: PropertyListValue] = ["__xctestrun_metadata__": .dictionary(metadata)]
        let shared = SharedValues(build)
        var options = build.options.mapValues(XCTestPlan.Value.string)
        options["commandLineArgumentEntries"] = .array(build.arguments.map { .object(["argument": .string($0)]) })
        for (order, name) in build.testables.enumerated() {
            guard let product = shared.testProducts.first(where: { $0.name == name }) else { continue }
            var entry = self.entry(product, build: build, shared: shared, arguments: build.arguments, environment: build.environment, testing: [:], gathersCoverage: !build.coverage.isEmpty)
            apply(options, to: &entry)
            if let target = build.testableOptions[name] { apply(target, to: &entry) }
            entry["RunOrder"] = .integer(order)
            entry["TestInteropMode"] = .string(interoperability)
            top[name] = .dictionary(entry)
        }
        return .dictionary(top)
    }

    /// Format 2: the plan, its coverage, and its configurations, each listing its enabled targets.
    /// The scheme's own arguments and variables do not join a plan's (`xctestrun-plan-launch-env`).
    static func value(_ build: TestBuildDescription, plan: XCTestPlan) -> PropertyListValue {
        var top: [String: PropertyListValue] = [
            "ContainerInfo": containerInformation(build),
            "TestPlan": .dictionary(["IsDefault": .boolean(plan.isDefault), "Name": .string(plan.name)]),
            "__xctestrun_metadata__": .dictionary(["FormatVersion": .integer(2)]),
        ]
        switch plan.coverage {
        case .off: break
        case .all: top["CodeCoverageBuildableInfos"] = coverageInformation(build, reported: nil, plural: true)
        case .targets(let reported): top["CodeCoverageBuildableInfos"] = coverageInformation(build, reported: reported, plural: true)
        }
        let shared = SharedValues(build)
        top["TestConfigurations"] = .array(plan.configurations.map { configuration in
            let targets: [PropertyListValue] = plan.targets.filter(\.isEnabled).compactMap { target in
                guard let product = shared.testProducts.first(where: { $0.name == target.name }) else { return nil }
                var entry = self.entry(product, build: build, shared: shared, arguments: [], environment: [:], testing: ["XCODE_TEST_PLAN_NAME": .string(plan.name)],
                                       gathersCoverage: plan.coverage != .off)
                apply(configuration.options, to: &entry)
                apply(target, to: &entry)
                if plan.isAutocreated { entry["TestInteropMode"] = .string(interoperability) }
                if product.kind == .uiTest, case .dictionary(var variables)? = entry["UITargetAppEnvironmentVariables"] {
                    variables["XCODE_TEST_PLAN_NAME"] = .string(plan.name)
                    entry["UITargetAppEnvironmentVariables"] = .dictionary(variables)
                }
                return .dictionary(entry)
            }
            return .dictionary(["IsEnabled": .boolean(true), "Name": .string(configuration.name), "TestTargets": .array(targets)])
        })
        return .dictionary(top)
    }

    /// A configuration's options in an entry (`xctestrun-plan-options`, `-never`, `-languages`,
    /// `-configurations`, `-config-overrides`): disabled variables and arguments stay out, and a
    /// language or region joins the arguments of the test and of the app a UI test drives.
    static func apply(_ options: [String: XCTestPlan.Value], to entry: inout [String: PropertyListValue]) {
        if case .dictionary(var variables)? = entry["EnvironmentVariables"] {
            for item in options["environmentVariableEntries"]?.array ?? [] {
                guard let fields = item.object, fields["enabled"]?.boolean != false, let key = fields["key"]?.string else { continue }
                variables[key] = .string(fields["value"]?.string ?? "")
            }
            entry["EnvironmentVariables"] = .dictionary(variables)
        }
        let arguments = (options["commandLineArgumentEntries"]?.array ?? []).compactMap { item -> String? in
            guard let fields = item.object, fields["enabled"]?.boolean != false else { return nil }
            return fields["argument"]?.string
        }
        let language = options["language"]?.string
        let region = options["region"]?.string
        let localization = languageArguments(language: language, region: region)
        entry["CommandLineArguments"] = .array((arguments + localization).map { .string($0) })
        if entry["UITargetAppCommandLineArguments"] != nil { entry["UITargetAppCommandLineArguments"] = .array(localization.map { .string($0) }) }
        if let language { entry["TestLanguage"] = .string(language) }
        if let region { entry["TestRegion"] = .string(region) }
        if let enabled = options["testTimeoutsEnabled"]?.boolean { entry["TestTimeoutsEnabled"] = .boolean(enabled) }
        if let seconds = options["defaultTestExecutionTimeAllowance"]?.number { entry["DefaultTestExecutionTimeAllowance"] = .integer(seconds) }
        if let seconds = options["maximumTestExecutionTimeAllowance"]?.number { entry["MaximumTestExecutionTimeAllowance"] = .integer(seconds) }
        if let ordering = options["testExecutionOrdering"]?.string { entry["TestExecutionOrdering"] = .string(ordering) }
        if options["testRepetitionMode"]?.string == "retryOnFailure" {
            entry["TestRepetitionPolicy"] = .dictionary([
                "XCTMaximumIterations": .integer(options["maximumTestRepetitions"]?.number ?? 3),
                "XCTRepeatInNewRunnerProcess": .boolean(false),
                "XCTRepetitionMode": .integer(2),
            ])
        }
        switch options["diagnosticCollectionPolicy"]?.string {
        case "Always"?: entry["DiagnosticCollectionPolicy"] = .integer(2)
        case "Never"?: entry["DiagnosticCollectionPolicy"] = .integer(0)
        default: break
        }
        if let format = options["preferredScreenCaptureFormat"]?.string { entry["PreferredScreenCaptureFormat"] = .string(format) }
        if let lifetime = options["uiTestingScreenshotsLifetime"]?.string { entry["SystemAttachmentLifetime"] = .string(lifetime) }
        if let lifetime = options["userAttachmentLifetime"]?.string { entry["UserAttachmentLifetime"] = .string(lifetime) }
    }

    /// A plan's test target or a scheme's testable in its entry.
    static func apply(_ target: XCTestPlan.Target, to entry: inout [String: PropertyListValue]) {
        if let parallelizable = target.parallelizable { entry["ParallelizationEnabled"] = .boolean(parallelizable) }
        if let inProcess = target.inProcessParallelizable { entry["InProcessParallelizationEnabled"] = .boolean(inProcess) }
        if let skipped = target.skippedTests { entry["SkipTestIdentifiers"] = .array(skipped.map { .string($0) }) }
        if let selected = target.selectedTests { entry["OnlyTestIdentifiers"] = .array(selected.map { .string($0) }) }
        if let ordering = target.testExecutionOrdering { entry["TestExecutionOrdering"] = .string(ordering) }
    }

    /// The arguments of a language and a region (`xctestrun-plan-languages`): Xcode's two
    /// pseudolanguages have their own; a region alone reads as English's.
    static func languageArguments(language: String?, region: String?) -> [String] {
        switch language {
        case "IDELaunchSchemeLanguageRLO"?:
            return ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES", "-NSForceRightToLeftLocalizedStrings", "YES"]
        case "IDELaunchSchemeLanguageDoubleLocalizedStrings"?:
            return ["-NSDoubleLocalizedStrings", "YES"]
        default:
            var arguments: [String] = []
            if let language {
                let rightToLeft = Locale.Language(identifier: language).characterDirection == .rightToLeft
                arguments += ["-AppleLanguages", "(\(language))", "-AppleTextDirection", rightToLeft ? "YES" : "NO"]
            }
            if let region { arguments += ["-AppleLocale", "\(language ?? "en")_\(region)"] }
            return arguments
        }
    }

    /// One built product's measured code: sorted by name, its files sorted; several files are named
    /// from the folder they share, one by its whole path (`xctestrun-coverage-*`). Format 2 has
    /// `Architectures` and `ProductPaths`, lists, where format 1 has one of each.
    static func coverageInformation(_ build: TestBuildDescription, reported: Set<String>?, plural: Bool) -> PropertyListValue {
        .array(build.coverage.sorted { $0.name < $1.name }.map { product in
            let path = "__TESTROOT__/" + product.binaryPath
            var information: [String: PropertyListValue] = [
                plural ? "Architectures" : "Architecture": plural ? .array([.string(build.architecture)]) : .string(build.architecture),
                "BuildableIdentifier": .string(product.identifier + ":primary"),
                "IncludeInReport": .boolean(reported?.contains(product.identifier) ?? true),
                "IsStatic": .boolean(product.isStatic),
                "Name": .string(product.name),
                plural ? "ProductPaths" : "ProductPath": plural ? .array([.string(path)]) : .string(path),
                "Toolchains": .array([.string(toolchain)]),
            ]
            let files = sourceFiles(product.sources)
            information["SourceFiles"] = .array(files.relative.map { .string($0) })
            if let prefix = files.prefix { information["SourceFilesCommonPathPrefix"] = .string(prefix) }
            return .dictionary(information)
        })
    }

    static func sourceFiles(_ paths: [String]) -> (prefix: String?, relative: [String]) {
        guard paths.count > 1, var folder = paths.first.map({ ($0 as NSString).deletingLastPathComponent + "/" }) else { return (nil, paths) }
        for path in paths {
            while !path.hasPrefix(folder), folder != "/" {
                let parent = (String(folder.dropLast()) as NSString).deletingLastPathComponent
                folder = parent == "/" ? parent : parent + "/"
            }
        }
        return (folder, paths.map { String($0.dropFirst(folder.count)) }.sorted())
    }

    /// What every entry of a file holds alike.
    struct SharedValues {
        let bundles: [TestBuildDescription.Product]
        let testProducts: [TestBuildDescription.Product]
        let dependents: [String]
        let identifiers: [String]
        let processes: [String]

        init(_ build: TestBuildDescription) {
            bundles = build.products.filter { $0.kind != .other }
            testProducts = bundles.filter { $0.kind == .unitTest || $0.kind == .uiTest }
            let runners = bundles.filter { $0.kind == .uiTest }.map(\.runnerPath)
            dependents = Array(Set(bundles.map(\.path) + runners)).sorted().map { "__TESTROOT__/" + $0 }
            identifiers = Array(Set(bundles.map(\.bundleIdentifier).filter { !$0.isEmpty })).sorted()
            processes = Array(Set(bundles.filter { $0.kind == .application }.map(\.executableName)
                + testProducts.filter { $0.kind == .uiTest }.map { $0.name + "-Runner" })).sorted()
        }
    }

    static func entry(_ product: TestBuildDescription.Product, build: TestBuildDescription, shared: SharedValues, arguments: [String], environment: [String: String],
                      testing: [String: PropertyListValue], gathersCoverage: Bool) -> [String: PropertyListValue] {
        var entry: [String: PropertyListValue] = [
            "BlueprintName": .string(product.name),
            "BlueprintProviderName": .string(build.projectName),
            "BlueprintProviderRelativePath": .string(build.projectPath),
            "BundleIdentifiersForCrashReportEmphasis": .array(shared.identifiers.map { .string($0) }),
            "CommandLineArguments": .array(arguments.map { .string($0) }),
            "DefaultTestExecutionTimeAllowance": .integer(600),
            "DependentProductPaths": .array(shared.dependents.map { .string($0) }),
            "DiagnosticCollectionPolicy": .integer(1),
            "EnvironmentVariables": .dictionary(defaultEnvironment.merging(environment) { $1 }.mapValues { .string($0) }),
            "IsMemoryTaggingAddressSanitizerEnabled": .boolean(false),
            "PreferredScreenCaptureFormat": .string("screenRecording"),
            "ProcessNamesForCrashReportCollection": .array(shared.processes.map { .string($0) }),
            "ProductModuleName": .string(product.moduleName),
            "SystemAttachmentLifetime": .string("deleteOnSuccess"),
            "TestLanguage": .string(""),
            "TestRegion": .string(""),
            "TestTimeoutsEnabled": .boolean(false),
            "ToolchainsSettingValue": .array([]),
            "UserAttachmentLifetime": .string("deleteOnSuccess"),
        ]
        if gathersCoverage { entry["ClangProfileDataDirectoryPath"] = .string(profileDataFolder) }
        var variables: [String: PropertyListValue] = testing
        variables["XCODE_SCHEME_NAME"] = .string(build.schemeName)
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
            if let host = product.hostPath, let hostProduct = shared.bundles.first(where: { $0.path == host }) {
                entry["IsAppHostedTestBundle"] = .boolean(true)
                entry["TestBundlePath"] = .string("__TESTHOST__/" + String(product.path.dropFirst(host.count + 1)))
                entry["TestHostBundleIdentifier"] = .string(hostProduct.bundleIdentifier)
                entry["TestHostPath"] = .string("__TESTROOT__/" + host)
                variables["DYLD_INSERT_LIBRARIES"] = .string("__TESTHOST__/Frameworks/libXCTestBundleInject.dylib:/usr/lib/libRPAC.dylib")
                variables["XCInjectBundleInto"] = .string("unused")
            } else {
                entry["TestBundlePath"] = .string("__TESTROOT__/" + product.path)
                entry["TestHostPath"] = .string(unhostedHost)
                variables["DYLD_INSERT_LIBRARIES"] = .string("/usr/lib/libRPAC.dylib")
            }
            variables["PERFC_SUPPRESS_SYSTEM_REPORTS"] = .string("1")
        }
        entry["TestingEnvironmentVariables"] = .dictionary(variables)
        return entry
    }
}
