import Foundation
import NomacCore
import NomacPlist

/// A test plan (`.xctestplan`, JSON), as far as `build-for-testing` turns it into an `.xctestrun`
/// (docs/formats/xctestrun.md "Format 2"). The options are those the corpus's and the holdout's 68
/// plans use, each observed (`xctest_experiments.py` `xctestrun-plan-*`); another stops with its
/// name, since a build would not know what Xcode does with it.
public struct XCTestPlan: Sendable {
    public enum Value: Sendable, Equatable, Decodable {
        case boolean(Bool)
        case number(Int)
        case string(String)
        case array([Value])
        case object([String: Value])
        case null

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let flag = try? container.decode(Bool.self) {
                self = .boolean(flag)
            } else if let number = try? container.decode(Int.self) {
                self = .number(number)
            } else if let text = try? container.decode(String.self) {
                self = .string(text)
            } else if let items = try? container.decode([Value].self) {
                self = .array(items)
            } else {
                self = .object(try container.decode([String: Value].self))
            }
        }

        var string: String? { if case .string(let text) = self { text } else { nil } }
        var number: Int? { if case .number(let number) = self { number } else { nil } }
        var boolean: Bool? { if case .boolean(let flag) = self { flag } else { nil } }
        var object: [String: Value]? { if case .object(let fields) = self { fields } else { nil } }
        var array: [Value]? { if case .array(let items) = self { items } else { nil } }
    }

    public struct Configuration: Sendable {
        public var name: String
        /// The configuration's options over the plan's default ones, key by key.
        public var options: [String: Value]
    }

    public struct Target: Sendable {
        public var name: String
        /// The target's identifier in its project (`<identifier>:primary` names it in coverage's lists).
        public var identifier: String
        public var isEnabled: Bool
        public var parallelizable: Bool?
        /// A scheme's testable with `parallelizable = "NO"` (`xctestrun-scheme-parallel-no`).
        public var inProcessParallelizable: Bool?
        public var skippedTests: [String]?
        public var selectedTests: [String]?
        /// A scheme's testable has this on its own; a plan file has it per configuration.
        public var testExecutionOrdering: String?

        public init(name: String, identifier: String, isEnabled: Bool = true, parallelizable: Bool? = nil, inProcessParallelizable: Bool? = nil, skippedTests: [String]? = nil,
                    selectedTests: [String]? = nil, testExecutionOrdering: String? = nil) {
            self.name = name
            self.identifier = identifier
            self.isEnabled = isEnabled
            self.parallelizable = parallelizable
            self.inProcessParallelizable = inProcessParallelizable
            self.skippedTests = skippedTests
            self.selectedTests = selectedTests
            self.testExecutionOrdering = testExecutionOrdering
        }
    }

    public enum Coverage: Sendable, Equatable {
        case off
        case all
        /// Only these targets, by identifier, count in the report.
        case targets(Set<String>)
    }

    public var name: String
    public var isDefault: Bool
    /// Xcode's plan of a scheme's testables, not a file.
    public var isAutocreated = false
    public var configurations: [Configuration]
    public var targets: [Target]
    public var coverage: Coverage

    /// Options that leave no trace in an entry of the `.xctestrun`: `locationScenario`
    /// (`plan-location`), `mainThreadCheckerEnabled` and `performanceAntipatternCheckerEnabled`
    /// (`plan-options`, `plan-never`), and those read elsewhere.
    static let ignoredOptions: Set<String> = ["locationScenario", "mainThreadCheckerEnabled", "performanceAntipatternCheckerEnabled", "targetForVariableExpansion", "codeCoverage"]
    /// Options with a key of their own in each entry; `XCTestRunWriter.apply` writes them.
    static let writtenOptions: Set<String> = [
        "environmentVariableEntries", "commandLineArgumentEntries", "language", "region", "testTimeoutsEnabled", "defaultTestExecutionTimeAllowance",
        "maximumTestExecutionTimeAllowance", "testExecutionOrdering", "testRepetitionMode", "maximumTestRepetitions", "diagnosticCollectionPolicy",
        "preferredScreenCaptureFormat", "uiTestingScreenshotsLifetime", "userAttachmentLifetime",
    ]

    /// `testRepetitionMode` values observed.
    static let repetitionModes: Set<String> = ["retryOnFailure"]

    /// The plan Xcode makes of a scheme with `shouldAutocreateTestPlan` or autocreated itself, named
    /// as the scheme: its one configuration carries the scheme's test arguments, variables and
    /// `options`, and it gathers coverage (`xctestrun-autocreated-plan`, `-env`,
    /// `-scheme-lists-autocreated`, `-no-scheme`; the rule for coverage: loader-experiments
    /// `coverage-autocreated-plan`).
    public init(autocreatedFor scheme: String, testables: [Target], arguments: [String], environment: [String: String], options: [String: String] = [:]) {
        name = scheme
        isDefault = true
        configurations = [Configuration(name: "Test Scheme Action", options: options.mapValues(Value.string).merging([
            "environmentVariableEntries": .array(environment.sorted { $0.key < $1.key }.map { .object(["key": .string($0.key), "value": .string($0.value)]) }),
            "commandLineArgumentEntries": .array(arguments.map { .object(["argument": .string($0)]) }),
        ]) { $1 })]
        targets = testables
        coverage = .all
        isAutocreated = true
    }

    public init(path: String, isDefault: Bool) throws {
        guard let data = FileSystem.contents(atPath: path) else { throw NomacError("cannot read the test plan", path: path) }
        let plan: [String: Value]
        do {
            plan = try JSONDecoder().decode([String: Value].self, from: data)
        } catch {
            throw NomacError("the test plan is not readable JSON", path: path)
        }
        name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        self.isDefault = isDefault
        let defaults = plan["defaultOptions"]?.object ?? [:]
        configurations = (plan["configurations"]?.array ?? []).map { configuration in
            let fields = configuration.object ?? [:]
            return Configuration(name: fields["name"]?.string ?? "", options: defaults.merging(fields["options"]?.object ?? [:]) { $1 })
        }
        targets = (plan["testTargets"]?.array ?? []).compactMap { entry in
            guard let fields = entry.object, let target = fields["target"]?.object, let name = target["name"]?.string, let identifier = target["identifier"]?.string else { return nil }
            return Target(name: name, identifier: identifier, isEnabled: fields["enabled"]?.boolean ?? true, parallelizable: fields["parallelizable"]?.boolean,
                          skippedTests: fields["skippedTests"]?.array?.compactMap(\.string), selectedTests: fields["selectedTests"]?.array?.compactMap(\.string))
        }
        switch defaults["codeCoverage"] {
        case .boolean(false)?: coverage = .off
        case .object(let fields)?:
            coverage = .targets(Set((fields["targets"]?.array ?? []).compactMap { $0.object?["identifier"]?.string }))
        default: coverage = .all
        }
        for configuration in configurations {
            for key in configuration.options.keys.sorted() where !Self.ignoredOptions.contains(key) && !Self.writtenOptions.contains(key) {
                throw NomacError("the test plan's configuration \"\(configuration.name)\" uses the option \(key), whose .xctestrun is not implemented (BACKLOG B-408)", path: path)
            }
            if let mode = configuration.options["testRepetitionMode"]?.string, !Self.repetitionModes.contains(mode) {
                throw NomacError("the test plan's configuration \"\(configuration.name)\" repeats tests with \(mode), whose .xctestrun is not observed (BACKLOG B-408)", path: path)
            }
        }
    }

    /// The plan with each configuration's variables and arguments expanded by `expand` for its
    /// `targetForVariableExpansion`; without one they stay as written (`xctestrun-plan-expansion`,
    /// `-no-expansion`).
    public func expandingVariables(_ expand: (_ text: String, _ targetIdentifier: String) async throws -> String) async throws -> XCTestPlan {
        var plan = self
        for index in plan.configurations.indices {
            let options = plan.configurations[index].options
            guard let target = options["targetForVariableExpansion"]?.object?["identifier"]?.string else { continue }
            func expanded(_ list: String, _ field: String) async throws -> Value? {
                guard let items = options[list]?.array else { return nil }
                var result: [Value] = []
                for item in items {
                    guard var fields = item.object, let text = fields[field]?.string else { continue }
                    fields[field] = .string(try await expand(text, target))
                    result.append(.object(fields))
                }
                return .array(result)
            }
            if let variables = try await expanded("environmentVariableEntries", "value") { plan.configurations[index].options["environmentVariableEntries"] = variables }
            if let arguments = try await expanded("commandLineArgumentEntries", "argument") { plan.configurations[index].options["commandLineArgumentEntries"] = arguments }
        }
        return plan
    }
}
