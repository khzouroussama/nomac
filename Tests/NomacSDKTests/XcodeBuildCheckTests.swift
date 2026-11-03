import Foundation
import NomacCore
import NomacSDK
import NomacTestSupport
import Testing

/// `nomac sdk install`, `sdk link` and `--developer-dir` accept the profile's Xcode build, warn
/// on any other, and refuse it with `--strict-xcode` (docs/adr/0012-one-xcode-per-release.md).
@Suite struct XcodeBuildCheckTests {
    let profile = XcodeProfile.current

    @Test func theProfilesBuildPasses() throws {
        let version = XcodeVersionInfo(version: profile.xcode.version, build: profile.xcode.build)
        #expect(try XcodeBuildCheck.check(version, at: "/X.app", strict: false) == nil)
        #expect(try XcodeBuildCheck.check(version, at: "/X.app", strict: true) == nil)
    }

    @Test func anotherBuildWarnsAndStrictRefuses() throws {
        let other = XcodeVersionInfo(version: "27.1", build: "27A9275")
        let warning = try #require(try XcodeBuildCheck.check(other, at: "/X.app", strict: false))
        #expect(warning == "/X.app is Xcode 27.1 (27A9275), but nomac \(NomacVersion.current) reproduces Xcode \(profile.xcode.version) (\(profile.xcode.build)) only; outputs may differ from that Xcode's (--strict-xcode refuses other builds)")
        #expect(throws: NomacError.self) { try XcodeBuildCheck.check(other, at: "/X.app", strict: true) }
    }

    @Test func aDirectoryWithoutVersionIsNotTheProfilesXcode() throws {
        let warning = try #require(try XcodeBuildCheck.check(nil, at: "/X", strict: false))
        #expect(warning.hasPrefix("/X is an Xcode without a readable version.plist, but nomac"))
        #expect(throws: NomacError.self) { try XcodeBuildCheck.check(nil, at: "/X", strict: true) }
    }

    @Test func versionOfADeveloperDirectory() throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path)
        #expect(XcodeVersionInfo.read(developerDirectory: developer) == XcodeVersionInfo(version: SyntheticDeveloperDirectory.xcodeVersion, build: SyntheticDeveloperDirectory.xcodeBuild))
        #expect(XcodeVersionInfo.read(developerDirectory: developer + "/") == XcodeVersionInfo(version: SyntheticDeveloperDirectory.xcodeVersion, build: SyntheticDeveloperDirectory.xcodeBuild))
        #expect(XcodeVersionInfo.read(developerDirectory: tmp.path + "/missing/Contents/Developer") == nil)
    }

    @Test func aRefusedXcodeIsNeitherCopiedNorLinked() throws {
        let tmp = try TemporaryDirectory()
        try SyntheticDeveloperDirectory.create(at: tmp.path + "/source")
        let store = SDKStore(root: tmp.path + "/store")
        let refuse: (XcodeVersionInfo) throws -> Void = { _ = try XcodeBuildCheck.check($0, at: "Xcode.app", strict: true) }
        #expect(throws: NomacError.self) { try store.install(app: tmp.path + "/source/Xcode.app", subset: XcodeSubset(), accept: refuse) }
        #expect(throws: NomacError.self) { try store.link(app: tmp.path + "/source/Xcode.app", accept: refuse) }
        #expect(try store.entries().isEmpty)
    }
}
