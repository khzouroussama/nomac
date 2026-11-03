import Foundation
import Testing
@testable import NomacBuild
import NomacCore
import NomacTestSupport

/// `nomac xcrun`, against the answers of Xcode 27.0's xcrun in `.github/scripts/xcrun_experiments.py`.
@Suite struct XcrunTests {
    /// A developer directory with an iOS and a macOS SDK laid out as Xcode's: the SDK folder
    /// unversioned, its version in SDKSettings.json, its build in SystemVersion.plist.
    private func developerDirectory(in tmp: TemporaryDirectory) throws -> String {
        let developer = tmp.path + "/Xcode.app/Contents/Developer"
        for (platform, version, build) in [("iPhoneOS", "27.0", "24A430"), ("MacOSX", "27.0", "26A425")] {
            let root = developer + "/Platforms/\(platform).platform"
            try FileSystem.write(try PropertyLists.xmlData(["Version": version]), to: root + "/Info.plist")
            let sdk = root + "/Developer/SDKs/\(platform).sdk"
            try FileSystem.write(Data(#"{"Version": "\#(version)"}"#.utf8), to: sdk + "/SDKSettings.json")
            try FileSystem.write(try PropertyLists.xmlData(["ProductBuildVersion": build]), to: sdk + "/System/Library/CoreServices/SystemVersion.plist")
        }
        return developer
    }

    @Test func parsesTheCommandLinesScriptsRun() throws {
        #expect(try Xcrun.parse(["--sdk", "macosx", "swift", "Scripts/GenerateStrings.swift"])
                == Xcrun(sdk: "macosx", action: .run(tool: "swift", arguments: ["Scripts/GenerateStrings.swift"])))
        #expect(try Xcrun.parse(["-sdk", "macosx", "swift", "VerifyNoBS.swift", "--xcode", "a b"])
                == Xcrun(sdk: "macosx", action: .run(tool: "swift", arguments: ["VerifyNoBS.swift", "--xcode", "a b"])))
        #expect(try Xcrun.parse(["-f", "swift"]) == Xcrun(sdk: nil, action: .find("swift")))
        #expect(try Xcrun.parse(["--sdk", "iphoneos", "--find", "clang"]) == Xcrun(sdk: "iphoneos", action: .find("clang")))
        #expect(try Xcrun.parse(["--sdk", "iphoneos", "--show-sdk-build-version"]) == Xcrun(sdk: "iphoneos", action: .show(.sdkBuildVersion)))
        #expect(throws: Xcrun.Failure(message: "xcrun: error: unrecognized option: --nomac-unknown\n", exitStatus: 64)) {
            try Xcrun.parse(["--nomac-unknown"])
        }
    }

    @Test func namesSDKsAsXcrunDoes() throws {
        let tmp = try TemporaryDirectory()
        let developer = try developerDirectory(in: tmp)
        let ios = developer + "/Platforms/iPhoneOS.platform"
        func path(_ sdk: String?, _ environment: [String: String] = [:]) throws -> String {
            try Xcrun(sdk: sdk, action: .show(.sdkPath)).resolveSDK(developerDirectory: developer, environment: environment).path
        }
        #expect(try path(nil) == developer + "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
        #expect(try path("iphoneos") == ios + "/Developer/SDKs/iPhoneOS27.0.sdk")
        #expect(try path("iphoneos27.0") == ios + "/Developer/SDKs/iPhoneOS27.0.sdk")
        #expect(try path("macosx") == developer + "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
        #expect(try path(nil, ["SDKROOT": "iphoneos"]) == ios + "/Developer/SDKs/iPhoneOS27.0.sdk")
        #expect(try path(nil, ["SDKROOT": ios + "/Developer/SDKs/iPhoneOS27.0.sdk"]) == ios + "/Developer/SDKs/iPhoneOS27.0.sdk")
        #expect(throws: Xcrun.Failure(message: "xcrun: error: unable to lookup item 'Path' in SDK 'nomacos'\n", exitStatus: 1)) { try path("nomacos") }
        #expect(throws: Xcrun.Failure.self) { try path("iphoneos26.0") }

        let sdk = try Xcrun(sdk: "iphoneos", action: .show(.sdkPath)).resolveSDK(developerDirectory: developer, environment: [:])
        #expect(try Xcrun.answer(.sdkVersion, sdk: sdk) == "27.0")
        #expect(try Xcrun.answer(.sdkBuildVersion, sdk: sdk) == "24A430")
        #expect(try Xcrun.answer(.sdkPlatformPath, sdk: sdk) == ios)
        #expect(try Xcrun.answer(.sdkPlatformVersion, sdk: sdk) == "27.0")
    }

    @Test func findsToolsWhereXcrunDoes() throws {
        let tmp = try TemporaryDirectory()
        let developer = try developerDirectory(in: tmp)
        let tools = [developer + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift", developer + "/usr/bin/swift",
                     developer + "/usr/bin/actool", tmp.path + "/bin/git"]
        for tool in tools {
            try FileSystem.write(Data("#!/bin/sh\n".utf8), to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool)
        }
        let sdk = try Xcrun(sdk: nil, action: .find("swift")).resolveSDK(developerDirectory: developer, environment: [:])
        let environment = ["PATH": tmp.path + "/bin"]
        #expect(try Xcrun.find("swift", sdk: sdk, developerDirectory: developer, environment: environment) == tools[0])
        #expect(try Xcrun.find("actool", sdk: sdk, developerDirectory: developer, environment: environment) == tools[2])
        #expect(try Xcrun.find("git", sdk: sdk, developerDirectory: developer, environment: environment) == tools[3])
        #expect(throws: Xcrun.Failure(message: """
            xcrun: error: sh -c '\(developer)/usr/bin/xcodebuild -sdk \(sdk.path) -find nomac-no-such-tool 2> /dev/null' failed with exit code 17664: (null) (errno=Undefined error: 0)
            xcrun: error: unable to find utility "nomac-no-such-tool", not a developer tool or in PATH

            """, exitStatus: 72)) {
            try Xcrun.find("nomac-no-such-tool", sdk: sdk, developerDirectory: developer, environment: environment)
        }
    }

    @Test func givesToolsXcrunsEnvironment() throws {
        let tmp = try TemporaryDirectory()
        let developer = try developerDirectory(in: tmp)
        let iphoneos = developer + "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk"
        let macosx = developer + "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
        let inherited = ["SDKROOT": iphoneos, "PATH": "/usr/bin"]
        let script = Xcrun(sdk: "macosx", action: .run(tool: "swift", arguments: []))
        let sdk = try script.resolveSDK(developerDirectory: developer, environment: inherited)
        let onMac = script.environment(for: sdk, developerDirectory: developer, inherited: inherited, hostIsMac: true)
        #expect(onMac["SDKROOT"] == macosx)
        #expect(onMac["MANPATH"] == "\(macosx)/usr/share/man:\(developer)/Platforms/MacOSX.platform/usr/share/man:\(developer)/usr/share/man:\(developer)/Toolchains/XcodeDefault.xctoolchain/usr/share/man:")
        #expect(onMac["CPATH"] == nil)
        let offMac = script.environment(for: sdk, developerDirectory: developer, inherited: inherited, hostIsMac: false)
        #expect(offMac["SDKROOT"] == nil)
        #expect(offMac["PATH"] == "/usr/bin")

        let plain = Xcrun(sdk: nil, action: .run(tool: "env", arguments: []))
        let kept = plain.environment(for: try plain.resolveSDK(developerDirectory: developer, environment: inherited),
                                     developerDirectory: developer, inherited: inherited, hostIsMac: true)
        #expect(kept["SDKROOT"] == iphoneos)
        let defaulted = plain.environment(for: try plain.resolveSDK(developerDirectory: developer, environment: [:]),
                                          developerDirectory: developer, inherited: [:], hostIsMac: true)
        #expect(defaulted["SDKROOT"] == developer + "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
        #expect(defaulted["CPATH"] == "/usr/local/include")
        #expect(defaulted["LIBRARY_PATH"] == "/usr/local/lib")
    }

    /// Off macOS, `xcrun --sdk macosx swift <script>` runs the script on Linux, with the resource
    /// directory that has swift.org's headers; on a Mac and for other SDKs the arguments stay.
    @Test func runsSwiftForTheBuildMachineWithItsResources() throws {
        let tmp = try TemporaryDirectory()
        let developer = try developerDirectory(in: tmp)
        let macosx = try Xcrun(sdk: "macosx", action: .show(.sdkPath)).resolveSDK(developerDirectory: developer, environment: [:])
        let iphoneos = try Xcrun(sdk: "iphoneos", action: .show(.sdkPath)).resolveSDK(developerDirectory: developer, environment: [:])
        #expect(Xcrun.arguments(for: "swift", ["GenerateStrings.swift"], sdk: macosx, developerDirectory: developer, hostIsMac: false)
                == ["-resource-dir", developer + "/Toolchains/XcodeDefault.xctoolchain/usr/lib/nomac/swift", "GenerateStrings.swift"])
        #expect(Xcrun.arguments(for: "swift", ["GenerateStrings.swift"], sdk: macosx, developerDirectory: developer, hostIsMac: true) == ["GenerateStrings.swift"])
        #expect(Xcrun.arguments(for: "swift", ["a.swift"], sdk: iphoneos, developerDirectory: developer, hostIsMac: false) == ["a.swift"])
        #expect(Xcrun.arguments(for: "clang", ["-c", "a.c"], sdk: macosx, developerDirectory: developer, hostIsMac: false) == ["-c", "a.c"])
    }

    /// Off macOS, clang gets the target Xcode's clang takes without one: the SDK's platform and
    /// version, or the deployment target the environment names, and `-arch`'s architecture; for
    /// macOS's SDK only when the output is a Mach-O library.
    @Test func compilesForTheSDKAsXcodesClang() throws {
        let tmp = try TemporaryDirectory()
        let developer = try developerDirectory(in: tmp)
        let macosx = try Xcrun(sdk: "macosx", action: .show(.sdkPath)).resolveSDK(developerDirectory: developer, environment: [:])
        let iphoneos = try Xcrun(sdk: "iphoneos", action: .show(.sdkPath)).resolveSDK(developerDirectory: developer, environment: [:])
        #if arch(x86_64)
        let machine = "x86_64"
        #else
        let machine = "arm64"
        #endif
        let stub = ["-x", "c", "-", "-dynamiclib", "-o", "stub", "-install_name", "@rpath/X.framework/X"]
        #expect(Xcrun.arguments(for: "clang", stub, sdk: macosx, developerDirectory: developer, hostIsMac: false)
                == ["-target", "\(machine)-apple-macosx27.0", "-isysroot", macosx.path] + stub)
        #expect(Xcrun.arguments(for: "clang", ["-c", "a.c"], sdk: iphoneos, developerDirectory: developer, hostIsMac: false,
                                environment: ["IPHONEOS_DEPLOYMENT_TARGET": "16.4"])
                == ["-target", "\(machine)-apple-ios16.4", "-isysroot", iphoneos.path, "-c", "a.c"])
        #expect(Xcrun.arguments(for: "clang++", ["-arch", "arm64e", "-c", "a.cpp"], sdk: iphoneos, developerDirectory: developer, hostIsMac: false)
                == ["-target", "arm64e-apple-ios27.0", "-isysroot", iphoneos.path, "-arch", "arm64e", "-c", "a.cpp"])
        #expect(Xcrun.arguments(for: "clang", ["-target", "arm64-apple-ios17.0", "-c", "a.c"], sdk: iphoneos, developerDirectory: developer, hostIsMac: false)
                == ["-target", "arm64-apple-ios17.0", "-c", "a.c"])
        #expect(Xcrun.arguments(for: "clang", stub, sdk: macosx, developerDirectory: developer, hostIsMac: true) == stub)
    }
}
