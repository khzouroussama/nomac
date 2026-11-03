import Foundation
import Testing
import NomacCore
import NomacTestSupport
import NomacVerify
@testable import NomacInspect

/// `nomac verify` on a reference where xcodebuild failed (envelope-experiments `object-versions`:
/// Xcode 27.0 refuses objectVersion 57 with status 74): nomac must fail every command alike.
@Suite struct FailedReferenceTests {
    static func reference(at root: String, objectVersion: Int = 77, phase: String? = nil, dumpStatus: Int32) throws -> String {
        let target = phase.map {
            "\t\tT1 = {isa = PBXNativeTarget; buildConfigurationList = L1; buildPhases = (B1, ); name = App; productType = \"com.apple.product-type.application\"; };\n\t\tB1 = \($0);\n"
        } ?? ""
        let project = """
            // !$*UTF8*$!
            {
            \tarchiveVersion = 1;
            \tobjectVersion = \(objectVersion);
            \tobjects = {
            \t\tG1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            \t\tC1 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
            \t\tL1 = {isa = XCConfigurationList; buildConfigurations = (C1, ); defaultConfigurationName = Debug; };
            \t\tP1 = {isa = PBXProject; buildConfigurationList = L1; mainGroup = G1; projectDirPath = ""; projectRoot = ""; targets = (\(phase == nil ? "" : "T1, ")); };
            \(target)\t};
            \trootObject = P1;
            }
            """
        try FileSystem.write(Data(project.utf8), to: root + "/src/P.xcodeproj/project.pbxproj")
        let reference = root + "/ref"
        let host = ["xcodeVersion": "27.0", "xcodeBuild": "27A266a", "developerDirectory": "/Applications/Xcode_27.app/Contents/Developer",
                    "operatingSystemVersion": "27.0.1", "operatingSystemBuild": "27A1", "nativeArchitecture": "arm64", "userName": "tester",
                    "groupName": "staff", "homeDirectory": "/Users/tester", "userCacheDirectory": "/var/folders/cache"] as [String: Any]
        let files: [String: Any] = [
            "app.json": ["id": "failed", "container": "P.xcodeproj"], "source.json": ["path": root + "/src"],
            "host.json": host.merging(["uid": 501, "gid": 20, "environment": [String: String]()]) { $1 },
            "pif/dumpPIF.stdout.cmd": ["exitStatus": dumpStatus], "xcodebuild-list.json.cmd": ["exitStatus": dumpStatus],
        ]
        for (path, value) in files {
            try FileSystem.write(try JSONSerialization.data(withJSONObject: value), to: reference + "/" + path)
        }
        try FileSystem.write(Data("[]\n".utf8), to: reference + "/settings/index.json")
        return reference
    }

    @Test func aProjectBothRefuseMatches() async throws {
        let directory = try TemporaryDirectory()
        let reference = try Self.reference(at: directory.path, objectVersion: 57, dumpStatus: 74)
        let report = try await ReferenceVerifier(referenceDirectory: reference, sourceRoot: directory.path + "/src", developerDirectory: "/nonexistent",
                                                 scratchDirectory: directory.path + "/scratch").run()
        #expect(report.checks.map(\.kind) == ["pif", "list"])
        #expect(report.checks.allSatisfy { $0.status == .identical })
    }

    /// envelope-experiments `dst-subfolders`: xcodebuild aborts on a `dstSubfolder` name it does
    /// not know, recorded as `-6`.
    @Test func aSignalMatchesTheStatusAShellReports() async throws {
        let directory = try TemporaryDirectory()
        let phase = #"{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolder = Other; files = (); runOnlyForDeploymentPostprocessing = 0; }"#
        let reference = try Self.reference(at: directory.path, phase: phase, dumpStatus: -6)
        let report = try await ReferenceVerifier(referenceDirectory: reference, sourceRoot: directory.path + "/src", developerDirectory: "/nonexistent",
                                                 scratchDirectory: directory.path + "/scratch").run()
        #expect(report.checks.map(\.status) == [.identical, .identical])
    }

    @Test func aStatusOtherThanXcodesDiffers() async throws {
        let directory = try TemporaryDirectory()
        let reference = try Self.reference(at: directory.path, objectVersion: 57, dumpStatus: 65)
        let report = try await ReferenceVerifier(referenceDirectory: reference, sourceRoot: directory.path + "/src", developerDirectory: "/nonexistent",
                                                 scratchDirectory: directory.path + "/scratch").run()
        #expect(report.checks.allSatisfy { $0.status == .different })
    }
}
