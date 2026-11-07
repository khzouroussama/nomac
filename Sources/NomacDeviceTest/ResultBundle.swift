import CSQLite
import Foundation
import NomacCore
import NomacPlist

/// The result bundle (`.xcresult`) of a `nomac test`, as far as nomac knows the run: what
/// `xcresulttool get test-results` and `get object --legacy` read, in the layout of Xcode 27.0's
/// (docs/formats/xcresult.md). Failures and skips come from the lines XCTest prints, one line each,
/// with no expected failure's reason; no diagnostics or logs, and the product type where Xcode has
/// the device's marketing name (BACKLOG B-408).
public struct ResultBundle: Sendable {
    /// A failure or a skip XCTest printed for a test case: `<file>:<line>: error: -[<module>.<class>
    /// <method>] : <message>`, a skip without `error: ` (`xcresult-mixed`).
    public struct Note: Sendable, Equatable {
        public var testClass: String
        public var method: String
        public var file: String
        public var line: Int
        public var message: String
        public var isFailure: Bool
    }

    /// The notes in a test run's output.
    public static func notes(in output: String) -> [Note] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let failure = line.range(of: ": error: -[")
            guard let open = failure ?? line.range(of: ": -["), let close = line.range(of: "] : ", range: open.upperBound..<line.endIndex) else { return nil }
            return note(location: line[..<open.lowerBound], name: line[open.upperBound..<close.lowerBound], message: line[close.upperBound...], isFailure: failure != nil)
        }
    }

    private static func note(location: Substring, name: Substring, message: Substring, isFailure: Bool) -> Note? {
        guard let colon = location.lastIndex(of: ":"), let number = Int(location[location.index(after: colon)...]) else { return nil }
        let parts = name.split(separator: " ")
        guard parts.count == 2 else { return nil }
        return Note(testClass: String(parts[0].split(separator: ".").last ?? parts[0]), method: String(parts[1]), file: String(location[..<colon]), line: number, message: String(message), isFailure: isFailure)
    }

    /// `cases` with the notes of each.
    public static func attaching(_ notes: [Note], to cases: [TestCaseResult]) -> [TestCaseResult] {
        cases.map { testCase in
            var result = testCase
            result.notes = notes.filter { $0.testClass == testCase.testClass && $0.method == testCase.method }
            return result
        }
    }

    public struct Device: Sendable, Equatable {
        public var name: String
        public var identifier: String
        public var operatingSystemVersion: String
        public var buildVersion: String
        /// The product type (`iPhone17,2`).
        public var model: String
        public var architecture: String

        public init(name: String, identifier: String, operatingSystemVersion: String, buildVersion: String, model: String, architecture: String) {
            self.name = name
            self.identifier = identifier
            self.operatingSystemVersion = operatingSystemVersion
            self.buildVersion = buildVersion
            self.model = model
            self.architecture = architecture
        }
    }

    public struct Testable: Sendable {
        public var name: String
        public var projectRelativePath: String
        public var isUITest: Bool
        public var language: String
        public var region: String
        public var cases: [TestCaseResult]

        public init(name: String, projectRelativePath: String, isUITest: Bool, language: String, region: String, cases: [TestCaseResult]) {
            self.name = name
            self.projectRelativePath = projectRelativePath
            self.isUITest = isUITest
            self.language = language
            self.region = region
            self.cases = cases
        }
    }

    public struct Configuration: Sendable {
        public var name: String
        public var testables: [Testable]

        public init(name: String, testables: [Testable]) {
            self.name = name
            self.testables = testables
        }
    }

    public var scheme: String
    public var containerName: String
    public var planName: String
    public var device: Device
    public var sdkVersion: String
    public var started: Date
    public var finished: Date
    public var configurations: [Configuration]
    public var uniqueIdentifier: String
    /// What failed besides a test's own result: a runner that did not start or did not finish, whose
    /// tests have no rows. Xcode's record of that is not observed (BACKLOG B-408).
    public var runFailure: String?

    public init(scheme: String, containerName: String, planName: String, device: Device, sdkVersion: String, started: Date, finished: Date,
                configurations: [Configuration], uniqueIdentifier: String = UUID().uuidString, runFailure: String? = nil) {
        self.runFailure = runFailure
        self.scheme = scheme
        self.containerName = containerName
        self.planName = planName
        self.device = device
        self.sdkVersion = sdkVersion
        self.started = started
        self.finished = finished
        self.configurations = configurations
        self.uniqueIdentifier = uniqueIdentifier
    }

    /// The result name each status has in the database and the legacy objects.
    static func resultName(_ status: String) -> String {
        switch status {
        case "passed": "Success"
        case "failed": "Failure"
        case "skipped": "Skipped"
        case "expected failure": "Expected Failure"
        default: status
        }
    }

    /// Writes the bundle at `path`, which must not exist (xcodebuild: "Existing file at -resultBundlePath", 64).
    public func write(to path: String) throws {
        guard !FileManager.default.fileExists(atPath: path) else {
            throw NomacError("Existing file at -resultBundlePath \"\(path)\"", exitStatus: 64)
        }
        try FileSystem.createDirectory(path + "/Data")
        try writeDatabase(to: path + "/database.sqlite3")
        var store = ObjectStore(folder: path + "/Data")
        let root = try rootObject(store: &store)
        let information: PropertyListValue = .dictionary([
            "dateCreated": .date(finished.timeIntervalSinceReferenceDate),
            "directoryImportMode": .string("concurrent"),
            "externalLocations": .array([]),
            "rootId": .dictionary(["hash": .string(root)]),
            "storage": .dictionary(["backend": .string("fileBacked2"), "compression": .string("standard")]),
            "version": .dictionary(["major": .integer(3), "minor": .integer(60)]),
        ])
        try FileSystem.write(XMLPropertyList.data(information), to: path + "/Info.plist")
    }

    // MARK: The database

    /// Seconds since 2001, the time the database stores.
    private static func timestamp(_ date: Date) -> Double { date.timeIntervalSinceReferenceDate }

    private func identifierURL(_ testable: String, _ rest: String? = nil) -> String {
        "test://com.apple.xcode/\(containerName)/\(testable)" + (rest.map { "/" + $0 } ?? "")
    }

    private func writeDatabase(to path: String) throws {
        let database = try Database(path: path)
        for statement in ResultBundleSchema.statements { try database.execute(statement) }
        let started = Self.timestamp(self.started)
        let plan = try database.insert("TestPlans", ["name": .text(planName)])
        let invocation = try database.insert("Invocations", [
            "uniqueIdentifier": .text(uniqueIdentifier), "scheme": .text(scheme), "workspacePath": .text(containerName), "timestamp": .real(started),
        ])
        let platform = try database.insert("Platforms", ["identifier": .text("com.apple.platform.iphoneos"), "userDescription": .text("iOS")])
        let device = try database.insert("Devices", [
            "operatingSystemVersionWithBuildNumber": .text("\(self.device.operatingSystemVersion) (\(self.device.buildVersion))"), "platform_fk": .integer(platform),
            "name": .text(self.device.name), "cpuKind": .text(""), "cpuSpeedInMHz": .integer(0), "identifier": .text(self.device.identifier), "cpuCount": .integer(0),
            "modelUTI": .text(""), "modelName": .text(self.device.model), "modelCode": .text(self.device.model), "nativeArchitecture": .text(self.device.architecture),
            "logicalCPUCoresPerPackage": .integer(0), "busSpeedInMHz": .integer(0), "operatingSystemVersion": .text(self.device.operatingSystemVersion), "isWireless": .integer(0),
            "physicalCPUCoresPerPackage": .integer(0), "isConcreteDevice": .integer(1), "ramSizeInMegabytes": .integer(0),
        ])
        let sdk = try database.insert("SDKs", [
            "identifier": .text("iphoneos\(sdkVersion)"), "operatingSystemVersion": .text(sdkVersion), "isInternal": .integer(0), "name": .text("iOS \(sdkVersion)"),
        ])
        let destination = try database.insert("RunDestinations", [
            "architecture": .text(self.device.architecture), "sdk_fk": .integer(sdk), "name": .text(self.device.name), "device_fk": .integer(device),
        ])
        let action = try database.insert("Actions", [
            "runDestination_fk": .integer(destination), "invocation_fk": .integer(invocation), "started": .real(started), "orderInInvocation": .integer(0),
            "finished": .real(Self.timestamp(finished)), "name": .text("Test"), "testPlan_fk": .integer(plan),
        ])
        var overall: [String: [String]] = [:]
        for configuration in configurations {
            for testable in configuration.testables {
                for testCase in testable.cases {
                    overall["\(testable.name)/\(testCase.testClass)/\(testCase.method)", default: []].append(Self.resultName(testCase.status))
                }
            }
        }
        var testables: [String: Int64] = [:]
        var suites: [String: Int64] = [:]
        var testCases: [String: Int64] = [:]
        for (order, configuration) in configurations.enumerated() {
            let configurationRow = try database.insert("TestPlanConfigurations", ["name": .text(configuration.name), "testPlan_fk": .integer(plan)])
            let run = try database.insert("TestPlanRuns", [
                "testPlan_fk": .integer(plan), "orderInAction": .integer(Int64(order)), "action_fk": .integer(action), "configuration_fk": .integer(configurationRow),
            ])
            for (testableOrder, testable) in configuration.testables.enumerated() {
                let testableRow: Int64
                if let known = testables[testable.name] {
                    testableRow = known
                } else {
                    testableRow = try database.insert("Testables", [
                        "testPlan_fk": .integer(plan), "projectRelativePath": .text(testable.projectRelativePath), "name": .text(testable.name),
                        "testKind": .text(testable.isUITest ? "UI" : "app hosted"), "orderInTestPlan": .integer(Int64(testableOrder)), "identifierURL": .text(identifierURL(testable.name)),
                    ])
                    testables[testable.name] = testableRow
                }
                let testableRun = try database.insert("TestableRuns", [
                    "testPlanRun_fk": .integer(run), "diagnosticsDirectoryName": .text(""), "testable_fk": .integer(testableRow), "orderInTestPlanRun": .integer(Int64(testableOrder)),
                ])
                for (suiteOrder, group) in Self.grouped(testable.cases).enumerated() {
                    let suiteKey = testable.name + "/" + group.name
                    let suiteRow: Int64
                    if let known = suites[suiteKey] {
                        suiteRow = known
                    } else {
                        suiteRow = try database.insert("TestSuites", [
                            "name": .text(group.name), "identifierURL": .text(identifierURL(testable.name, group.name)), "testable_fk": .integer(testableRow),
                            "orderInParent": .integer(Int64(suiteOrder)), "identifier": .text(group.name),
                        ])
                        suites[suiteKey] = suiteRow
                    }
                    let suiteRun = try database.insert("TestSuiteRuns", [
                        "testSuite_fk": .integer(suiteRow), "orderInParent": .integer(Int64(suiteOrder)), "duration": .real(group.cases.reduce(0) { $0 + $1.duration }), "testableRun_fk": .integer(testableRun),
                    ])
                    for (caseOrder, testCase) in group.cases.enumerated() {
                        let url = identifierURL(testable.name, "\(group.name)/\(testCase.method)")
                        let caseKey = suiteKey + "/" + testCase.method
                        let caseRow: Int64
                        if let known = testCases[caseKey] {
                            caseRow = known
                        } else {
                            caseRow = try database.insert("TestCases", [
                                "name": .text(testCase.method + "()"), "identifier": .text("\(group.name)/\(testCase.method)()"), "orderInTestSuite": .integer(Int64(caseOrder)),
                                "identifierURL": .text(url), "testSuite_fk": .integer(suiteRow),
                            ])
                            testCases[caseKey] = caseRow
                            let combined = Self.combined(overall[caseKey] ?? [])
                            _ = try database.insert("TestCaseResultsByDestinationAndConfiguration", ["result": .text(combined), "testCase_fk": .integer(caseRow)])
                            _ = try database.insert("TestCaseResultsByDestinationAndConfiguration", ["result": .text(combined), "destination_fk": .integer(destination), "testCase_fk": .integer(caseRow)])
                        }
                        let result = Self.resultName(testCase.status)
                        var run: [String: Database.Value] = [
                            "orderInTestSuiteRun": .integer(Int64(caseOrder)), "duration": .real(testCase.duration), "testCase_fk": .integer(caseRow), "testSuiteRun_fk": .integer(suiteRun),
                            "identifierURL": .text(url), "result": .text(result),
                        ]
                        if let skip = testCase.notes.first(where: { !$0.isFailure }) {
                            run["skipNotice_fk"] = .integer(try database.insert("SkipNotices", [
                                "fileName": .text(skip.file), "lineNumber": .integer(Int64(skip.line)), "timestamp": .real(started), "message": .text(skip.message),
                            ]))
                        }
                        let caseRun = try database.insert("TestCaseRuns", run)
                        for (issueOrder, failure) in testCase.notes.filter(\.isFailure).enumerated() {
                            let location = try database.insert("SourceCodeLocations", ["filePath": .text(failure.file), "lineNumber": .integer(Int64(failure.line))])
                            let context = try database.insert("SourceCodeContexts", ["location_fk": .integer(location)])
                            _ = try database.insert("TestIssues", [
                                "orderInOwner": .integer(Int64(issueOrder)), "testCaseRun_fk": .integer(caseRun), "uuid": .text(UUID().uuidString), "timestamp": .real(started),
                                "issueType": .text("Assertion Failure"), "sourceCodeContext_fk": .integer(context), "sanitizedDescription": .text(failure.message),
                                "compactDescription": .text(failure.message), "isTopLevel": .integer(1),
                            ])
                        }
                        _ = try database.insert("TestCaseResultsByDestinationAndConfiguration", [
                            "result": .text(result), "destination_fk": .integer(destination), "testCase_fk": .integer(caseRow), "configuration_fk": .integer(configurationRow),
                        ])
                    }
                }
            }
        }
    }

    /// A test's result over its runs: failed if one failed, else the first.
    static func combined(_ results: [String]) -> String {
        results.contains("Failure") ? "Failure" : results.first ?? "Success"
    }

    /// The cases of each class, in the order the classes first ran.
    static func grouped(_ cases: [TestCaseResult]) -> [(name: String, cases: [TestCaseResult])] {
        var groups: [(name: String, cases: [TestCaseResult])] = []
        for testCase in cases {
            if let index = groups.firstIndex(where: { $0.name == testCase.testClass }) {
                groups[index].cases.append(testCase)
            } else {
                groups.append((testCase.testClass, [testCase]))
            }
        }
        return groups
    }

    // MARK: The objects

    private var allCases: [TestCaseResult] { configurations.flatMap { $0.testables.flatMap(\.cases) } }

    private func metrics(counting cases: [TestCaseResult]) -> ResultObject {
        .object("ResultMetrics", [
            "analyzerWarningCount": .integer(0), "errorCount": .integer(0), "testsCount": .integer(cases.count),
            "testsFailedCount": .integer(cases.filter { $0.status == "failed" }.count), "testsSkippedCount": .integer(cases.filter { $0.status == "skipped" }.count),
            "warningCount": .integer(0),
        ])
    }

    private static let noIssues = issues(failures: [])

    private static func issues(failures: [ResultObject], errors: [String] = []) -> ResultObject {
        .object("ResultIssueSummaries", [
            "analyzerWarningSummaries": .array([]),
            "errorSummaries": .array(errors.map { .object("IssueSummary", ["issueType": .string("Error"), "message": .string($0)]) }),
            "testFailureSummaries": .array(failures), "testWarningSummaries": .array([]), "warningSummaries": .array([]),
        ])
    }

    /// `testCaseName` is `<class>.<method>()`, and the location's line numbers count from 0
    /// (`xcresult-mixed`: `EndingLineNumber=9&StartingLineNumber=9` for line 10).
    private var failureSummaries: [ResultObject] {
        allCases.flatMap { testCase in
            testCase.notes.filter(\.isFailure).map { failure in
                .object("TestFailureIssueSummary", [
                    "documentLocationInCreatingWorkspace": .object("DocumentLocation", [
                        "concreteTypeName": .string("DVTTextDocumentLocation"),
                        "url": .string("file://\(failure.file)#EndingLineNumber=\(failure.line - 1)&StartingLineNumber=\(failure.line - 1)"),
                    ]),
                    "issueType": .string("Uncategorized"), "message": .string(failure.message), "testCaseName": .string("\(testCase.testClass).\(testCase.method)()"),
                ])
            }
        }
    }

    private func summaries() -> ResultObject {
        .object("ActionTestPlanRunSummaries", ["summaries": .array(configurations.map { configuration in
            .object("ActionTestPlanRunSummary", [
                "name": .string(configuration.name),
                "testableSummaries": .array(configuration.testables.map { testable in
                    .object("ActionTestableSummary", [
                        "diagnosticsDirectoryName": .string(""), "failureSummaries": .array([]), "identifierURL": .string(identifierURL(testable.name)), "name": .string(testable.name),
                        "projectRelativePath": .string(testable.projectRelativePath), "targetName": .string(testable.name), "testKind": .string(testable.isUITest ? "UI" : "app hosted"),
                        "testLanguage": .string(testable.language), "testRegion": .string(testable.region), "tests": .array([allTests(testable)]),
                    ])
                }),
            ])
        })])
    }

    private func group(_ name: String, url: String, duration: Double, subtests: [ResultObject]) -> ResultObject {
        .object("ActionTestSummaryGroup", [
            "activitySummaries": .array([]), "documentation": .array([]), "duration": .double(duration), "expectedFailures": .array([]), "failureSummaries": .array([]),
            "identifier": .string(name), "identifierURL": .string(url), "name": .string(name), "subtests": .array(subtests), "tags": .array([]), "trackedIssues": .array([]), "warningSummaries": .array([]),
        ])
    }

    private func allTests(_ testable: Testable) -> ResultObject {
        let total = testable.cases.reduce(0) { $0 + $1.duration }
        let classes = Self.grouped(testable.cases).map { suite in
            group(suite.name, url: identifierURL(testable.name, suite.name), duration: suite.cases.reduce(0) { $0 + $1.duration }, subtests: suite.cases.map { testCase in
                .object("ActionTestMetadata", [
                    "activitySummariesCount": .integer(0), "duration": .double(testCase.duration), "failureSummariesCount": .integer(testCase.notes.filter(\.isFailure).count), "identifier": .string("\(suite.name)/\(testCase.method)()"),
                    "identifierURL": .string(identifierURL(testable.name, "\(suite.name)/\(testCase.method)")), "name": .string(testCase.method + "()"),
                    "performanceMetricsCount": .integer(0), "testStatus": .string(Self.resultName(testCase.status)),
                ])
            })
        }
        let bundle = group(testable.name + ".xctest", url: identifierURL(testable.name, testable.name + ".xctest"), duration: total, subtests: classes)
        return group("All tests", url: identifierURL(testable.name, "All%20tests"), duration: total, subtests: [bundle])
    }

    private func reference(_ identifier: String, type: String) -> ResultObject {
        .object("Reference", ["id": .string(identifier), "targetType": .object("TypeDefinition", ["name": .string(type)])])
    }

    private func rootObject(store: inout ObjectStore) throws -> String {
        let testsReference = try store.put(summaries())
        let metadata = try store.put(.object("ActionsInvocationMetadata", [
            "schemeIdentifier": .object("EntityIdentifier", [
                "containerName": .string("\(containerName) project"), "entityName": .string(scheme), "entityType": .string("scheme"), "sharedState": .string("shared"),
            ]),
            "uniqueIdentifier": .string(uniqueIdentifier),
        ]))
        let failed = runFailure != nil || allCases.contains { $0.status == "failed" }
        let notRequested = ResultObject.object("ActionResult", [
            "coverage": .object("CodeCoverageInfo", ["hasCoverageData": .boolean(false)]), "issues": Self.noIssues,
            "metrics": metrics(counting: []), "resultName": .string("build"), "status": .string("notRequested"),
        ])
        let action = ResultObject.object("ActionRecord", [
            "actionResult": .object("ActionResult", [
                "coverage": .object("CodeCoverageInfo", ["hasCoverageData": .boolean(false)]), "issues": Self.issues(failures: failureSummaries, errors: runFailure.map { [$0] } ?? []), "metrics": metrics(counting: allCases), "resultName": .string("action"),
                "status": .string(failed ? "failed" : "succeeded"), "testsRef": reference(testsReference, type: "ActionTestPlanRunSummaries"),
            ]),
            "buildResult": notRequested,
            "endedTime": .date(finished),
            "runDestination": .object("ActionRunDestinationRecord", [
                "displayName": .string(device.name),
                "targetArchitecture": .string(device.architecture),
                "targetDeviceRecord": .object("ActionDeviceRecord", [
                    "identifier": .string(device.identifier), "isConcreteDevice": .boolean(true), "isWireless": .boolean(false), "modelCode": .string(device.model), "modelName": .string(device.model),
                    "name": .string(device.name), "nativeArchitecture": .string(device.architecture), "operatingSystemVersion": .string(device.operatingSystemVersion),
                    "operatingSystemVersionWithBuildNumber": .string("\(device.operatingSystemVersion) (\(device.buildVersion))"),
                    "platformRecord": .object("ActionPlatformRecord", ["identifier": .string("com.apple.platform.iphoneos"), "userDescription": .string("iOS")]),
                ]),
                "targetSDKRecord": .object("ActionSDKRecord", [
                    "identifier": .string("iphoneos\(sdkVersion)"), "isInternal": .boolean(false), "name": .string("iOS \(sdkVersion)"), "operatingSystemVersion": .string(sdkVersion),
                ]),
            ]),
            "schemeCommandName": .string("Test"),
            "schemeTaskName": .string("Action"),
            "startedTime": .date(started),
            "testPlanName": .string(planName),
        ])
        return try store.put(.object("ActionsInvocationRecord", [
            "actions": .array([action]), "issues": Self.issues(failures: failureSummaries, errors: runFailure.map { [$0] } ?? []), "metadataRef": reference(metadata, type: "ActionsInvocationMetadata"), "metrics": metrics(counting: allCases),
        ]))
    }
}

/// A stored object of a result bundle, typed as xcresulttool's legacy objects are.
indirect enum ResultObject {
    case object(String, [String: ResultObject])
    case array([ResultObject])
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case date(Date)

    /// The text a stored object holds (docs/formats/xcresult.md): `[T[K2:_nV<n>:<type>]` the first
    /// time a type appears in the object, `[S<n>:<type>` after it, keys sorted as `K<n>:<key>`, a
    /// scalar's value under `_v` as `V<n>:<value>`, an array's elements after its type.
    func serialized() -> String {
        var seen: Set<String> = []
        return text(&seen)
    }

    private func text(_ seen: inout Set<String>) -> String {
        func field(_ text: String) -> String { "\(text.utf8.count):\(text)" }
        func open(_ type: String, _ seen: inout Set<String>) -> String {
            seen.insert(type).inserted ? "[T[K2:_nV\(field(type))]" : "[S\(field(type))"
        }
        func scalar(_ type: String, _ value: String, _ seen: inout Set<String>) -> String { open(type, &seen) + "K2:_vV\(field(value))]" }
        switch self {
        case .object(let type, let fields):
            var result = open(type, &seen)
            for key in fields.keys.sorted() { result += "K\(field(key))" + fields[key]!.text(&seen) }
            return result + "]"
        case .array(let elements):
            var result = open("Array", &seen)
            for element in elements { result += element.text(&seen) }
            return result + "]"
        case .string(let value): return scalar("String", value, &seen)
        case .integer(let value): return scalar("Int", String(value), &seen)
        case .double(let value): return scalar("Double", String(value), &seen)
        case .boolean(let value): return scalar("Bool", value ? "true" : "false", &seen)
        case .date(let value): return scalar("Date", Self.dateText(value), &seen)
        }
    }

    /// `2026-11-07T00:58:43.857+0000`.
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter.string(from: date)
    }
}

/// The `Data` folder: `data.<id>` a Zstandard frame of the object's text, `refs.<id>` a zero byte for
/// no references; the id is `0~` and the base64url of the frame's BLAKE2b.
struct ObjectStore {
    let folder: String

    mutating func put(_ object: ResultObject) throws -> String {
        let frame = Self.zstandardFrame(Array(object.serialized().utf8))
        let identifier = Self.identifier(frame)
        try FileSystem.write(Data(frame), to: folder + "/data." + identifier)
        try FileSystem.write(Data([0]), to: folder + "/refs." + identifier)
        return identifier
    }

    static func identifier(_ frame: [UInt8]) -> String {
        "0~" + Data(BLAKE2b.hash(frame)).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }

    /// A frame of raw blocks, which any Zstandard reader takes (RFC 8878): the magic number, the
    /// frame header xcresulttool's frames start with, then blocks of at most 128 KiB less a byte.
    static func zstandardFrame(_ bytes: [UInt8]) -> [UInt8] {
        var frame: [UInt8] = [0x28, 0xb5, 0x2f, 0xfd, 0x00, 0x48]
        guard !bytes.isEmpty else { return frame + [1, 0, 0] }
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 0x1ffff, bytes.count)
            let header = UInt32(end - offset) << 3 | (end == bytes.count ? 1 : 0)
            frame += [UInt8(truncatingIfNeeded: header), UInt8(truncatingIfNeeded: header >> 8), UInt8(truncatingIfNeeded: header >> 16)]
            frame += bytes[offset..<end]
            offset = end
        }
        return frame
    }
}

/// The few SQLite calls the database needs.
final class Database {
    enum Value {
        case text(String)
        case integer(Int64)
        case real(Double)
    }

    private var handle: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else { throw NomacError("cannot create the database", path: path) }
    }

    deinit { sqlite3_close(handle) }

    func execute(_ statement: String) throws {
        guard sqlite3_exec(handle, statement, nil, nil, nil) == SQLITE_OK else {
            throw NomacError("the result bundle's database refused: \(String(cString: sqlite3_errmsg(handle)))")
        }
    }

    func insert(_ table: String, _ values: [String: Value]) throws -> Int64 {
        let keys = values.keys.sorted()
        let sql = "INSERT INTO \"\(table)\" (\(keys.joined(separator: ", "))) VALUES (\(keys.map { _ in "?" }.joined(separator: ", ")))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NomacError("the result bundle's database refused: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, key) in keys.enumerated() {
            let position = Int32(index + 1)
            switch values[key]! {
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, transient)
            case .integer(let number): sqlite3_bind_int64(statement, position, number)
            case .real(let number): sqlite3_bind_double(statement, position, number)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NomacError("the result bundle's database refused: \(String(cString: sqlite3_errmsg(handle)))")
        }
        return sqlite3_last_insert_rowid(handle)
    }
}
