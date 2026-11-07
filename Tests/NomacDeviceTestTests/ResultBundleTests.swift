import Foundation
@testable import NomacDeviceTest
import NomacCore
import Testing

/// The result bundle's parts, against Xcode 27.0's (`xctest_experiments.py` `xcresult-*`,
/// docs/formats/xcresult.md), and on a Mac read back by Xcode's own `xcresulttool`.
@Suite struct ResultBundleTests {
    /// The lines `xcodebuild test` of `xcresult-mixed` printed for its failure and its skip.
    static let printed = """
    Test Case '-[AppTests.CounterTests testFails]' started.
    /w/AppTests/CounterTests.swift:10: error: -[AppTests.CounterTests testFails] : XCTAssertEqual failed: ("2") is not equal to ("3") - one more than one
    Test Case '-[AppTests.CounterTests testFails]' failed (0.002 seconds).
    /w/AppTests/CounterTests.swift:14: -[AppTests.CounterTests testSkipped] : Test skipped - not on this device
    Test Case '-[AppTests.CounterTests testSkipped]' skipped (0.006 seconds).
    """
    static let cases = ResultBundle.attaching(ResultBundle.notes(in: printed), to: [
        TestCaseResult(testClass: "CounterTests", method: "testExpectedFailure", status: "expected failure", duration: 0.24),
        TestCaseResult(testClass: "CounterTests", method: "testFails", status: "failed", duration: 0.002),
        TestCaseResult(testClass: "CounterTests", method: "testNext", status: "passed", duration: 0.0003),
        TestCaseResult(testClass: "CounterTests", method: "testSkipped", status: "skipped", duration: 0.006),
        TestCaseResult(testClass: "OtherTests", method: "testOther", status: "passed", duration: 0.01),
    ])
    static let device = ResultBundle.Device(name: "iPhone", identifier: "00008140-00FACE00FACE001E", operatingSystemVersion: "27.0.1", buildVersion: "24A446", model: "iPhone17,2", architecture: "arm64e")
    static func bundle(configurations: [ResultBundle.Configuration]? = nil) -> ResultBundle {
        ResultBundle(scheme: "App", containerName: "App", planName: "App", device: device, sdkVersion: "27.0", started: Date(timeIntervalSince1970: 1_800_000_000), finished: Date(timeIntervalSince1970: 1_800_000_010),
                     configurations: configurations ?? [.init(name: "Test Scheme Action", testables: [.init(name: "AppTests", projectRelativePath: "App.xcodeproj", isUITest: false, language: "", region: "", cases: cases)])])
    }

    /// RFC 7693's example, and an input longer than a block, against Python's `hashlib.blake2b`.
    @Test func blake2bAsTheRFC() {
        func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
        #expect(hex(BLAKE2b.hash(Array("abc".utf8))) == "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
        #expect(hex(BLAKE2b.hash([UInt8](repeating: 0, count: 300))).hasPrefix("104b2a75c9b7062f1e945d3d366fd4e4"))
        #expect(BLAKE2b.hash([]).count == 64)
    }

    /// `[T` the first time a type appears, `[S` after it, keys sorted.
    @Test func objectText() {
        let text = ResultObject.object("Record", ["b": .string("x"), "a": .array([.string("y")]), "c": .integer(2), "d": .boolean(false)]).serialized()
        #expect(text == "[T[K2:_nV6:Record]K1:a[T[K2:_nV5:Array][T[K2:_nV6:String]K2:_vV1:y]]K1:b[S6:StringK2:_vV1:x]K1:c[T[K2:_nV3:Int]K2:_vV1:2]K1:d[T[K2:_nV4:Bool]K2:_vV5:false]]")
    }

    @Test func aFrameOfRawBlocks() {
        #expect(ObjectStore.zstandardFrame(Array("ab".utf8)) == [0x28, 0xb5, 0x2f, 0xfd, 0x00, 0x48, 0x11, 0x00, 0x00, 0x61, 0x62])
        #expect(ObjectStore.zstandardFrame([]) == [0x28, 0xb5, 0x2f, 0xfd, 0x00, 0x48, 0x01, 0x00, 0x00])
        #expect(ObjectStore.identifier([1, 2, 3]).hasPrefix("0~"))
        #expect(!ObjectStore.identifier([1, 2, 3]).contains("+") && !ObjectStore.identifier([1, 2, 3]).contains("/"))
    }

    @Test func failuresAndSkipsFromTheOutput() {
        let notes = ResultBundle.notes(in: Self.printed)
        #expect(notes == [
            .init(testClass: "CounterTests", method: "testFails", file: "/w/AppTests/CounterTests.swift", line: 10, message: #"XCTAssertEqual failed: ("2") is not equal to ("3") - one more than one"#, isFailure: true),
            .init(testClass: "CounterTests", method: "testSkipped", file: "/w/AppTests/CounterTests.swift", line: 14, message: "Test skipped - not on this device", isFailure: false),
        ])
        #expect(Self.cases[1].notes.count == 1 && Self.cases[0].notes.isEmpty)
    }

    @Test func statusesAndGroups() {
        #expect(["passed", "failed", "skipped", "expected failure"].map(ResultBundle.resultName) == ["Success", "Failure", "Skipped", "Expected Failure"])
        #expect(ResultBundle.grouped(Self.cases).map(\.name) == ["CounterTests", "OtherTests"])
        #expect(ResultBundle.combined(["Success", "Failure"]) == "Failure")
        #expect(ResultBundle.combined(["Skipped"]) == "Skipped")
    }

    @Test func anExistingPathIsRefusedAsXcodebuildRefusesIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xcresult-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        #expect(throws: NomacError("Existing file at -resultBundlePath \"\(folder)\"", exitStatus: 64)) { try Self.bundle().write(to: folder) }
    }

    @Test func theBundlesLayout() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xcresult-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try Self.bundle().write(to: folder + "/App.xcresult")
        #expect(FileManager.default.fileExists(atPath: folder + "/App.xcresult/Info.plist"))
        #expect(FileManager.default.fileExists(atPath: folder + "/App.xcresult/database.sqlite3"))
        let stored = try FileManager.default.contentsOfDirectory(atPath: folder + "/App.xcresult/Data")
        #expect(stored.filter { $0.hasPrefix("data.0~") }.count == 3 && stored.filter { $0.hasPrefix("refs.0~") }.count == 3)
    }

    #if os(macOS)
    func tool(_ arguments: [String]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcresulttool"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Xcode's own reader, on a bundle made with no Xcode.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DEVELOPER_DIR"]?.contains("Xcode_27") == true)) func xcresulttoolReadsIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xcresult-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let path = folder + "/App.xcresult"
        try Self.bundle().write(to: path)
        let summary = try tool(["get", "test-results", "summary", "--path", path])
        #expect(summary["result"] as? String == "Failed")
        #expect(summary["totalTestCount"] as? Int == 5)
        #expect(summary["passedTests"] as? Int == 2)
        #expect(summary["failedTests"] as? Int == 1)
        #expect(summary["skippedTests"] as? Int == 1)
        #expect(summary["expectedFailures"] as? Int == 1)
        #expect(summary["title"] as? String == "Test - App")
        let configurations = try #require(summary["devicesAndConfigurations"] as? [[String: Any]])
        #expect((configurations[0]["testPlanConfiguration"] as? [String: Any])?["configurationName"] as? String == "Test Scheme Action")
        #expect((configurations[0]["device"] as? [String: Any])?["platform"] as? String == "iOS")
        let failures = try #require(summary["testFailures"] as? [[String: Any]])
        #expect(failures.count == 1)
        #expect(failures[0]["failureText"] as? String == #"XCTAssertEqual failed: ("2") is not equal to ("3") - one more than one"#)
        #expect(failures[0]["testIdentifierString"] as? String == "CounterTests/testFails()")
        #expect(failures[0]["targetName"] as? String == "AppTests")
        let tests = try tool(["get", "test-results", "tests", "--path", path])
        let plan = try #require((tests["testNodes"] as? [[String: Any]])?.first)
        #expect(plan["nodeType"] as? String == "Test Plan")
        let availability = try tool(["get", "content-availability", "--path", path])
        #expect(availability["hasTestResults"] as? Bool == true)
        let root = try tool(["get", "object", "--legacy", "--format", "json", "--path", path])
        #expect((root["_type"] as? [String: Any])?["_name"] as? String == "ActionsInvocationRecord")
    }
    #endif
}
