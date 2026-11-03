import Foundation
import Testing
import NomacCore
import NomacSDK
import NomacTestSupport

@Suite struct SDKStoreTests {
    @Test func installCopiesTheSubsetUnmodified() throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/source")
        let app = (developer as NSString).deletingLastPathComponent.replacingOccurrences(of: "/Contents", with: "")
        // A file outside the subset that must not be copied.
        try FileSystem.write(Data("binary".utf8), to: app + "/Contents/MacOS/Xcode")
        try FileSystem.write(Data("tool".utf8), to: developer + "/usr/bin/xcodebuild")

        let store = SDKStore(root: tmp.path + "/store")
        let entry = try store.install(app: app, subset: XcodeSubset())
        #expect(entry.version == XcodeVersionInfo(version: SyntheticDeveloperDirectory.xcodeVersion, build: SyntheticDeveloperDirectory.xcodeBuild))
        #expect(entry.kind == "copy")
        #expect(entry.payloadPlatforms == ["MacOSX", "WatchOS", "iPhoneOS"])

        let copiedPlatform = entry.developerDirectory + "/Platforms/iPhoneOS.platform/Info.plist"
        let originalPlatform = developer + "/Platforms/iPhoneOS.platform/Info.plist"
        #expect(FileManager.default.contents(atPath: copiedPlatform) == FileManager.default.contents(atPath: originalPlatform))
        #expect(FileSystem.isFile(entry.appPath + "/Contents/version.plist"))
        #expect(FileSystem.isFile(entry.developerDirectory + "/Toolchains/XcodeDefault.xctoolchain/ToolchainInfo.plist"))
        #expect(!FileManager.default.fileExists(atPath: entry.appPath + "/Contents/MacOS/Xcode"))
        #expect(!FileManager.default.fileExists(atPath: entry.developerDirectory + "/usr/bin/xcodebuild"))

        #expect(try store.entries() == [entry])
        #expect(try store.resolve(build: nil) == entry)
    }

    @Test func installPreservesSymbolicLinks() throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/source")
        let sdks = developer + "/Platforms/iPhoneOS.platform/Developer/SDKs"
        try FileManager.default.createSymbolicLink(atPath: sdks + "/iPhoneOS.sdk", withDestinationPath: "iPhoneOS\(SyntheticDeveloperDirectory.sdkVersion).sdk")
        let app = tmp.path + "/source/Xcode.app"
        let entry = try SDKStore(root: tmp.path + "/store").install(app: app, subset: XcodeSubset())
        let link = entry.developerDirectory + "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link) == "iPhoneOS\(SyntheticDeveloperDirectory.sdkVersion).sdk")
    }

    @Test func linkRecordsAnInstalledXcodeWithoutCopying() throws {
        let tmp = try TemporaryDirectory()
        try SyntheticDeveloperDirectory.create(at: tmp.path + "/source")
        let store = SDKStore(root: tmp.path + "/store")
        let entry = try store.link(app: tmp.path + "/source/Xcode.app")
        #expect(entry.kind == "link")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: entry.appPath) == tmp.path + "/source/Xcode.app")
        #expect(FileSystem.isFile(entry.developerDirectory + "/Platforms/iPhoneOS.platform/Info.plist"))
    }

    @Test func selectAndRemove() throws {
        let tmp = try TemporaryDirectory()
        try SyntheticDeveloperDirectory.create(at: tmp.path + "/source")
        let store = SDKStore(root: tmp.path + "/store")
        #expect(throws: NomacError.self) { try store.resolve(build: nil) }
        let entry = try store.link(app: tmp.path + "/source/Xcode.app")
        try store.select(build: entry.version.build)
        #expect(store.selectedBuild() == entry.version.build)
        #expect(throws: NomacError.self) { try store.select(build: "1A1") }
        try store.remove(build: entry.version.build)
        #expect(store.selectedBuild() == nil)
        #expect(try store.entries().isEmpty)
    }

    @Test func installFromXIPRunsUnxipAndCopiesTheSubset() throws {
        let tmp = try TemporaryDirectory()
        try SyntheticDeveloperDirectory.create(at: tmp.path + "/payload")
        // A stand-in for unxip: copies the synthetic Xcode.app into the output directory.
        let fakeUnxip = tmp.path + "/unxip"
        try FileSystem.write(Data("#!/bin/sh\nset -e\ncp -R \"\(tmp.path)/payload/Xcode.app\" \"$2/Xcode.app\"\n".utf8), to: fakeUnxip)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeUnxip)
        let xip = tmp.path + "/Xcode_27.xip"
        try FileSystem.write(Data("xar!".utf8), to: xip)

        let store = SDKStore(root: tmp.path + "/store")
        let entry = try store.install(xip: xip, subset: XcodeSubset(), unxip: fakeUnxip)
        #expect(entry.source == xip)
        #expect(FileSystem.isFile(entry.developerDirectory + "/Platforms/iPhoneOS.platform/Info.plist"))
        // The expanded staging directory is removed afterwards.
        let leftovers = try FileSystem.sortedContents(of: tmp.path + "/store/xcode").filter { $0.hasPrefix(".") }
        #expect(leftovers.isEmpty)
    }

    @Test func rejectsADirectoryThatIsNotXcode() throws {
        let tmp = try TemporaryDirectory()
        try FileSystem.createDirectory(tmp.path + "/NotXcode.app/Contents")
        #expect(throws: NomacError.self) {
            try SDKStore(root: tmp.path + "/store").install(app: tmp.path + "/NotXcode.app", subset: XcodeSubset())
        }
    }
}
