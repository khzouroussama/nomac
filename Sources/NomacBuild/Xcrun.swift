import Foundation
import NomacCore

/// `xcrun` off macOS, for the scripts builds run (docs/formats/build.md "xcrun"), as Xcode 27.0's
/// `xcrun` answers them (`.github/scripts/xcrun_experiments.py`).
public struct Xcrun: Equatable, Sendable {
    public enum Query: String, CaseIterable, Sendable {
        case sdkPath = "--show-sdk-path"
        case sdkVersion = "--show-sdk-version"
        case sdkBuildVersion = "--show-sdk-build-version"
        case sdkPlatformPath = "--show-sdk-platform-path"
        case sdkPlatformVersion = "--show-sdk-platform-version"
    }

    public enum Action: Equatable, Sendable {
        case find(String)
        case show(Query)
        case run(tool: String, arguments: [String])
    }

    /// What xcrun prints on standard error and exits with when it fails.
    public struct Failure: Error, Equatable {
        public var message: String
        public var exitStatus: Int32
    }

    public var sdk: String?
    public var action: Action

    /// The options before the tool's name; everything after it is the tool's.
    public static func parse(_ arguments: [String]) throws -> Xcrun {
        var sdk: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--sdk", "-sdk":
                guard index + 1 < arguments.count else { throw NomacError("xcrun \(argument) needs an SDK name or path") }
                sdk = arguments[index + 1]
                index += 2
            case "--find", "-f":
                guard index + 1 < arguments.count else { throw NomacError("xcrun \(argument) needs a tool name") }
                return Xcrun(sdk: sdk, action: .find(arguments[index + 1]))
            case let option where Query(rawValue: option) != nil:
                return Xcrun(sdk: sdk, action: .show(Query(rawValue: option)!))
            case "-v", "--verbose", "-l", "--log", "-n", "--no-cache", "-k", "--kill-cache", "-r", "--run", "--toolchain", "--version":
                throw NomacError("nomac's xcrun does not take \(argument) (BACKLOG B-123)")
            case let option where option.hasPrefix("-"):
                throw Failure(message: "xcrun: error: unrecognized option: \(option)\n", exitStatus: 64)
            default:
                return Xcrun(sdk: sdk, action: .run(tool: argument, arguments: Array(arguments[(index + 1)...])))
            }
        }
        throw NomacError("nomac's xcrun needs a tool name or a query (BACKLOG B-123)")
    }

    /// An SDK as xcrun names it, by its path and its platform's, and the folder that holds it.
    public struct SDK: Equatable, Sendable {
        public var path: String
        public var platformPath: String
        public var directory: String

        public init(path: String, platformPath: String, directory: String? = nil) {
            self.path = path
            self.platformPath = platformPath
            self.directory = directory ?? path
        }

        var settingsPath: String { directory + "/SDKSettings.json" }
    }

    private static let platforms = [
        "macosx": "MacOSX", "iphoneos": "iPhoneOS", "iphonesimulator": "iPhoneSimulator", "appletvos": "AppleTVOS",
        "appletvsimulator": "AppleTVSimulator", "watchos": "WatchOS", "watchsimulator": "WatchSimulator", "xros": "XROS",
        "xrsimulator": "XRSimulator", "driverkit": "DriverKit",
    ]

    /// The SDK `--sdk` names, else `SDKROOT`, else macOS's: a path names itself, and a name the
    /// SDK of its platform, by the path with its version (`iPhoneOS27.0.sdk`); without either,
    /// `MacOSX.sdk` (xcrun_experiments.py `sdk-path*`).
    public func resolveSDK(developerDirectory: String, environment: [String: String]) throws -> SDK {
        guard let name = sdk ?? environment["SDKROOT"] else {
            return SDK(path: developerDirectory + "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
                       platformPath: developerDirectory + "/Platforms/MacOSX.platform")
        }
        if name.hasPrefix("/") {
            let platform = name.range(of: ".platform/").map { String(name[..<$0.lowerBound]) + ".platform" } ?? (name as NSString).deletingLastPathComponent
            return SDK(path: name, platformPath: platform)
        }
        let family = String(name.prefix { $0.isLetter })
        let requested = String(name.dropFirst(family.count))
        guard let platformName = Self.platforms[family] else { throw Self.unknownSDK(name) }
        let platform = developerDirectory + "/Platforms/\(platformName).platform"
        let directory = platform + "/Developer/SDKs"
        let candidates = ([platformName + ".sdk"] + ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted())
            .filter { $0.hasPrefix(platformName) && $0.hasSuffix(".sdk") }
        for candidate in candidates {
            guard let version = Self.string("Version", inJSON: directory + "/" + candidate + "/SDKSettings.json"),
                  requested.isEmpty || requested == version else { continue }
            return SDK(path: directory + "/\(platformName)\(version).sdk", platformPath: platform, directory: directory + "/" + candidate)
        }
        throw Self.unknownSDK(name)
    }

    static func unknownSDK(_ name: String) -> Failure {
        Failure(message: "xcrun: error: unable to lookup item 'Path' in SDK '\(name)'\n", exitStatus: 1)
    }

    /// The answer to a query (SDKSettings.json's `Version`, SystemVersion.plist's
    /// `ProductBuildVersion`, the platform's Info.plist's `Version`).
    public static func answer(_ query: Query, sdk: SDK) throws -> String {
        let value: String?
        switch query {
        case .sdkPath: value = sdk.path
        case .sdkPlatformPath: value = sdk.platformPath
        case .sdkVersion: value = string("Version", inJSON: sdk.settingsPath)
        case .sdkBuildVersion: value = string("ProductBuildVersion", inPropertyList: sdk.directory + "/System/Library/CoreServices/SystemVersion.plist")
        case .sdkPlatformVersion: value = string("Version", inPropertyList: sdk.platformPath + "/Info.plist")
        }
        guard let value else { throw NomacError("the SDK has no answer to xcrun \(query.rawValue)", path: sdk.path) }
        return value
    }

    /// The tool in the toolchain, the developer directory, then `PATH` (xcrun_experiments.py
    /// `find-*`: swift, clang and ld in the toolchain, actool and xcodebuild in `usr/bin`).
    public static func find(_ tool: String, sdk: SDK, developerDirectory: String, environment: [String: String]) throws -> String {
        let directories = [developerDirectory + "/Toolchains/XcodeDefault.xctoolchain/usr/bin", developerDirectory + "/usr/bin"]
            + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        if let found = directories.map({ $0 + "/" + tool }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        throw Failure(message: """
            xcrun: error: sh -c '\(developerDirectory)/usr/bin/xcodebuild -sdk \(sdk.path) -find \(tool) 2> /dev/null' failed with exit code 17664: (null) (errno=Undefined error: 0)
            xcrun: error: unable to find utility "\(tool)", not a developer tool or in PATH

            """, exitStatus: 72)
    }

    /// The tool's environment: `SDKROOT` the SDK `--sdk` names, kept when inherited, else macOS's
    /// with `CPATH` and `LIBRARY_PATH`; `MANPATH` the SDK's, platform's, developer directory's and
    /// toolchain's manuals before the inherited ones (xcrun_experiments.py `env*`). The tools of
    /// a macOS SDK run on the build machine, which off macOS is not a Mac: they get no `SDKROOT`.
    public func environment(for sdk: SDK, developerDirectory: String, inherited: [String: String], hostIsMac: Bool) -> [String: String] {
        var environment = inherited
        if self.sdk != nil {
            environment["SDKROOT"] = sdk.path
        } else if inherited["SDKROOT"] == nil {
            environment["SDKROOT"] = sdk.path
            environment["CPATH"] = "/usr/local/include"
            environment["LIBRARY_PATH"] = "/usr/local/lib"
        }
        environment["MANPATH"] = [sdk.path + "/usr/share/man", sdk.platformPath + "/usr/share/man", developerDirectory + "/usr/share/man",
                                  developerDirectory + "/Toolchains/XcodeDefault.xctoolchain/usr/share/man", inherited["MANPATH"] ?? ""].joined(separator: ":")
        if !hostIsMac && sdk.platformPath.hasSuffix("/MacOSX.platform") {
            environment["SDKROOT"] = nil
        }
        return environment
    }

    /// The tool's arguments: as given, except that off macOS the Swift drivers run for macOS's
    /// SDK, which then compile and run for the Linux build machine, get the toolchain's resource
    /// directory for it, without which they find no `SwiftShims` (swiftfin's "Generate Strings",
    /// `xcrun --sdk macosx swift <script>`; ``LinuxToolchain/hostResourceDirectory``), and that
    /// clang gets the target Xcode's clang takes when none is given (``clangTarget``).
    public static func arguments(for tool: String, _ arguments: [String], sdk: SDK, developerDirectory: String, hostIsMac: Bool,
                                 environment: [String: String] = [:]) -> [String] {
        guard !hostIsMac else { return arguments }
        let name = (tool as NSString).lastPathComponent
        if sdk.platformPath.hasSuffix("/MacOSX.platform"), ["swift", "swiftc"].contains(name) {
            return ["-resource-dir", developerDirectory + "/Toolchains/XcodeDefault.xctoolchain/usr/" + LinuxToolchain.hostResourceDirectory] + arguments
        }
        if ["clang", "clang++", "cc", "c++"].contains(name), let target = clangTarget(arguments, sdk: sdk, environment: environment) {
            return target + arguments
        }
        return arguments
    }

    /// Off macOS, clang compiles for the build machine unless told otherwise, where Xcode's clang
    /// compiles for the SDK: `<arch>-apple-<os><version>`, the architecture `-arch`'s, else the
    /// machine's, the version `<PLATFORM>_DEPLOYMENT_TARGET`'s, else the SDK's. Observed with
    /// Xcode 27.0, `xcrun --sdk iphoneos|macosx clang -x c - -dynamiclib -v`: `arm64-apple-ios27.0.0`
    /// and `arm64-apple-macosx27.0.0` (LC_BUILD_VERSION minos 27.0), minos 16.4 and 13.0 with
    /// `IPHONEOS_DEPLOYMENT_TARGET=16.4` and `MACOSX_DEPLOYMENT_TARGET=13.0`, `arm64e-apple-ios27.0.0`
    /// with `-arch arm64e`. macOS's SDK keeps running for the build machine (above) unless the
    /// output is one only a Mach-O link makes (`-dynamiclib`, `-bundle`, `-install_name`): Expo's
    /// `create-stub-xcframework.sh` makes such a dylib for CocoaPods to read.
    static func clangTarget(_ arguments: [String], sdk: SDK, environment: [String: String]) -> [String]? {
        let platforms = ["iPhoneOS": ("ios", "IPHONEOS_DEPLOYMENT_TARGET"), "MacOSX": ("macosx", "MACOSX_DEPLOYMENT_TARGET")]
        let platform = ((sdk.platformPath as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let (os, deploymentSetting) = platforms[platform],
              !arguments.contains(where: { $0 == "-target" || $0 == "--target" || $0.hasPrefix("--target=") }),
              platform != "MacOSX" || arguments.contains(where: { ["-dynamiclib", "-bundle", "-install_name"].contains($0) }),
              let version = environment[deploymentSetting] ?? (try? answer(.sdkVersion, sdk: sdk)) else { return nil }
        #if arch(x86_64)
        let machine = "x86_64"
        #else
        let machine = "arm64"
        #endif
        let architecture = arguments.firstIndex(of: "-arch").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? machine
        return ["-target", "\(architecture)-apple-\(os)\(version)"] + (arguments.contains("-isysroot") ? [] : ["-isysroot", sdk.path])
    }

    private static func string(_ key: String, inJSON path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object[key] as? String
    }

    private static func string(_ key: String, inPropertyList path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return object[key] as? String
    }
}
