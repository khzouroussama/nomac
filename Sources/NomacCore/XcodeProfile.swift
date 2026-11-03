/// The one Xcode release this build of nomac reproduces, and every value nomac takes from it
/// (docs/adr/0012-one-xcode-per-release.md). Moving to another Xcode changes this file, by the
/// procedure of docs/UPGRADING.md: `.github/scripts/xcode_upgrade.py` observes each value again
/// (`nomac sdk profile` prints this one), and `XcodeProfileTests` checks the pins kept elsewhere
/// (Package.swift, Package.resolved, corpus/corpus.json, build-llvm-tools.sh) against it.
public struct XcodeProfile: Sendable, Equatable, Codable {
    /// `Contents/version.plist` of the Xcode.
    public struct Release: Sendable, Equatable, Codable {
        /// `CFBundleShortVersionString`.
        public var version: String
        /// `ProductBuildVersion`, the build developer directories are checked against.
        public var build: String
        /// `XCODE_VERSION_ACTUAL`, which Info.plists record as `DTXcode`.
        public var versionActual: String

        /// The major and minor version, which name nomac's releases for this Xcode (`27.0`).
        public var majorMinor: String {
            let parts = version.split(separator: ".").map(String.init)
            return (parts + ["0", "0"]).prefix(2).joined(separator: ".")
        }
    }

    /// The open-source revisions that reproduce this Xcode.
    public struct Pins: Sendable, Equatable, Codable {
        /// Swift Build's repository: the owner's fork, which adds the upstream patches of
        /// docs/upstream/swift-build.md to swiftlang's revision (ADR 0005).
        public var swiftBuildRepository: String
        /// The revision of that repository, swiftlang's chosen by comparison with this Xcode's
        /// settings with the patches (ADR 0005).
        public var swiftBuildRevision: String
        /// swiftlang/swift-package-manager (ADR 0010).
        public var swiftPMRevision: String
        /// The tag SwiftPM's package PIF builder is vendored from (ADR 0010).
        public var packagePIFBuilderTag: String
        /// The swift.org release paired with this Xcode, for `nomac toolchain install` (ADR 0100).
        public var swiftToolchainTag: String
        /// The swiftlang/llvm-project tag `.github/lld`'s patches apply to (ADR 0102).
        public var llvmProjectTag: String
    }

    /// A tool's answer to `--version --output-format xml1`.
    public struct ToolVersion: Sendable, Equatable, Codable {
        public var bundleVersion: String
        public var shortBundleVersion: String
    }

    /// coremlc's identity: what `what -q` reads from it, which Swift Build parses for its version,
    /// and the versions it records in an ML program's `model.mil` (docs/formats/coreml.md).
    public struct CoreMLCompiler: Sendable, Equatable, Codable {
        public var what: String
        public var version: String
        public var milComponentVersion: String
    }

    /// The strings actool writes into `Assets.car` (ADR 0200, docs/formats/asset-catalog.md).
    public struct AssetCatalog: Sendable, Equatable, Codable {
        public var coreUIVersion: UInt32
        public var coreUIVersionString: String
        public var versionString: String
        public var authoringTool: String
        /// The authoring tool string of a watchOS catalog, whose SDK's CMPhoto build differs.
        public var watchOSAuthoringTool: String
    }

    /// An SDK as `xcodebuild -showsdks -json` lists it.
    public struct SDK: Sendable, Equatable, Codable {
        public var canonicalName: String
        public var platform: String
        public var version: String
        /// `productBuildVersion`; DriverKit's has none.
        public var build: String?
    }

    /// The Mac the reference captures were made on, as their `host.json` records it.
    public struct ReferenceMac: Sendable, Equatable, Codable {
        public var operatingSystemVersion: String
        public var operatingSystemBuild: String
        public var nativeArchitecture: String
    }

    /// The identities of Xcode's tools that nomac does not reimplement. nomac never writes them
    /// (ADR 0101); they are recorded so that an upgrade sees the tools change.
    public struct XcodeTools: Sendable, Equatable, Codable {
        /// `swiftc --version`.
        public var swiftCompiler: String
        /// `clang --version`, first line.
        public var clang: String
        /// The `-target-linker-version` clang passes to every compile.
        public var clangLinkerVersion: String
        /// `ld -version_details`.
        public var linker: String
        /// `tapi --version`.
        public var tapi: String
    }

    /// The answers of the reference Mac to a package manifest's host conditions (ADR 0010).
    public struct ManifestHostConditions: Sendable, Equatable, Codable {
        /// By condition, written `name(argument)` without spaces.
        public var answers: [String: Bool]
        /// Condition kinds whose unlisted arguments are false.
        public var closedKinds: [String]
    }

    public var xcode: Release
    public var pins: Pins
    public var actool: ToolVersion
    public var ibtool: ToolVersion
    public var coremlc: CoreMLCompiler
    public var assetCatalog: AssetCatalog
    public var sdks: [SDK]
    /// What a Linux machine presents to Swift Build as its Mac unless `--host-identity` names
    /// another (B-060): the source of `BuildMachineOSBuild` and the `MAC_OS_X_*` settings.
    public var referenceMac: ReferenceMac
    /// The Info.plist keys Swift Build writes from the developer directory and the Mac into an
    /// iOS device build (build-experiments `app-without-packages`).
    public var infoPlist: [String: String]
    public var xcodeTools: XcodeTools
    public var manifestHostConditions: ManifestHostConditions
    /// The `objectVersion`s this Xcode reads; it fails every command with status 74 on the others
    /// (envelope-experiments `object-versions`, 41 to 111).
    public var readableObjectVersions: [Int]

    public func sdk(_ canonicalName: String) -> SDK? {
        sdks.first { $0.canonicalName == canonicalName }
    }
}

extension XcodeProfile {
    /// Xcode 27.0 (27A266a) on the owner's Mac (macOS 27.0.1, Apple silicon): `xcodebuild
    /// -version` and `-showsdks -json`, the tools' `--version`, the corpus references' `host.json`.
    public static let current = XcodeProfile(
        xcode: Release(version: "27.0", build: "27A266a", versionActual: "2700"),
        pins: Pins(
            swiftBuildRepository: "https://github.com/khzouroussama/swift-build.git",
            swiftBuildRevision: "79a7d991515d3b2cdea37db6a72b4cb9c19d8377",
            swiftPMRevision: "8054c59f07a9c8cc8e67b3ec57870710c7154854",
            packagePIFBuilderTag: "swift-6.4.1-RELEASE",
            swiftToolchainTag: "swift-6.4.0-RELEASE",
            llvmProjectTag: "swift-6.4.0-RELEASE"),
        actool: ToolVersion(bundleVersion: "25098", shortBundleVersion: "27.0"),
        ibtool: ToolVersion(bundleVersion: "25098", shortBundleVersion: "27.0"),
        coremlc: CoreMLCompiler(what: "PROGRAM:coremlcompiler  PROJECT:CoreML-3600.25.1", version: "3600.25.1", milComponentVersion: "3600.16.1"),
        assetCatalog: AssetCatalog(
            coreUIVersion: 1010,
            coreUIVersionString: "@(#)PROGRAM:CoreUI  PROJECT:CoreUI-1010 [LAR]",
            versionString: "Xcode 27.0 (27A266a) via AssetCatalogAgent-AssetRuntime",
            authoringTool: "@(#)PROGRAM:CoreThemeDefinition  PROJECT:CoreThemeDefinition-664 [LAR] [IIO-2851][LAR] AppleJPEG[1][32]  CMPhoto[1][219]] [IR-120(hw)]",
            watchOSAuthoringTool: "@(#)PROGRAM:CoreThemeDefinition  PROJECT:CoreThemeDefinition-664 [LAR] [IIO-2851][LAR] AppleJPEG[1][32]  CMPhoto[1][218]] [IR-120(hw)]"),
        sdks: [
            SDK(canonicalName: "driverkit27.0", platform: "driverkit", version: "27.0", build: nil),
            SDK(canonicalName: "iphoneos27.0", platform: "iphoneos", version: "27.0", build: "24A430"),
            SDK(canonicalName: "iphonesimulator27.0", platform: "iphonesimulator", version: "27.0", build: "24A430"),
            SDK(canonicalName: "macosx27.0", platform: "macosx", version: "27.0", build: "26A425"),
            SDK(canonicalName: "appletvos27.0", platform: "appletvos", version: "27.0", build: "24J360"),
            SDK(canonicalName: "appletvsimulator27.0", platform: "appletvsimulator", version: "27.0", build: "24J360"),
            SDK(canonicalName: "xros27.0", platform: "xros", version: "27.0", build: "24M361"),
            SDK(canonicalName: "xrsimulator27.0", platform: "xrsimulator", version: "27.0", build: "24M361"),
            SDK(canonicalName: "watchos27.0", platform: "watchos", version: "27.0", build: "24R360"),
            SDK(canonicalName: "watchsimulator27.0", platform: "watchsimulator", version: "27.0", build: "24R360"),
        ],
        referenceMac: ReferenceMac(operatingSystemVersion: "27.0.1", operatingSystemBuild: "26A434", nativeArchitecture: "arm64"),
        infoPlist: [
            "BuildMachineOSBuild": "26A434",
            "DTCompiler": "com.apple.compilers.llvm.clang.1_0",
            "DTPlatformBuild": "24A430",
            "DTPlatformName": "iphoneos",
            "DTPlatformVersion": "27.0",
            "DTSDKBuild": "24A430",
            "DTSDKName": "iphoneos27.0",
            "DTXcode": "2700",
            "DTXcodeBuild": "27A266a",
        ],
        xcodeTools: XcodeTools(
            swiftCompiler: "Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)",
            clang: "Apple clang version 21.0.0 (clang-2100.3.34.2)",
            clangLinkerVersion: "1166.2",
            linker: "27037.1",
            tapi: "Apple TAPI version 21.0.0 (tapi-2100.3.8.1)"),
        manifestHostConditions: ManifestHostConditions(
            answers: [
                "os(macOS)": true,
                "os(OSX)": true,
                "arch(arm64)": true,
                "_endian(little)": true,
                "_pointerBitWidth(_64)": true,
                "_runtime(_ObjC)": true,
                "_hasAtomicBitWidth(_64)": true,
                "_hasAtomicBitWidth(_128)": true,
                "canImport(AVFoundation)": true,
                "canImport(Accelerate)": true,
                "canImport(ActivityKit)": true,
                "canImport(AppIntents)": true,
                "canImport(AppKit)": true,
                "canImport(Combine)": true,
                "canImport(CommonCrypto)": true,
                "canImport(CompilerPluginSupport)": true,
                "canImport(Compression)": true,
                "canImport(CoreFoundation)": true,
                "canImport(CoreGraphics)": true,
                "canImport(CoreImage)": true,
                "canImport(CoreLocation)": true,
                "canImport(CoreML)": true,
                "canImport(CoreServices)": true,
                "canImport(CoreText)": true,
                "canImport(CryptoKit)": true,
                "canImport(Darwin)": true,
                "canImport(Darwin.C)": true,
                "canImport(Dispatch)": true,
                "canImport(Foundation)": true,
                "canImport(FoundationModels)": true,
                "canImport(ImageIO)": true,
                "canImport(Metal)": true,
                "canImport(NaturalLanguage)": true,
                "canImport(Network)": true,
                "canImport(OSLog)": true,
                "canImport(ObjectiveC)": true,
                "canImport(Observation)": true,
                "canImport(PackageDescription)": true,
                "canImport(QuartzCore)": true,
                "canImport(RegexBuilder)": true,
                "canImport(SQLite3)": true,
                "canImport(Security)": true,
                "canImport(StoreKit)": true,
                "canImport(Swift)": true,
                "canImport(SwiftData)": true,
                "canImport(SwiftUI)": true,
                "canImport(Synchronization)": true,
                "canImport(System)": true,
                "canImport(SystemConfiguration)": true,
                "canImport(Testing)": true,
                "canImport(UniformTypeIdentifiers)": true,
                "canImport(UserNotifications)": true,
                "canImport(Vision)": true,
                "canImport(WebKit)": true,
                "canImport(WidgetKit)": true,
                "canImport(XCTest)": true,
                "canImport(_Concurrency)": true,
                "canImport(_StringProcessing)": true,
                "canImport(os)": true,
                "canImport(zlib)": true,
                "canImport(Android)": false,
                "canImport(Bionic)": false,
                "canImport(CRT)": false,
                "canImport(FoundationEssentials)": false,
                "canImport(FoundationInternationalization)": false,
                "canImport(FoundationNetworking)": false,
                "canImport(FoundationXML)": false,
                "canImport(Glibc)": false,
                "canImport(MobileCoreServices)": false,
                "canImport(Musl)": false,
                "canImport(UIKit)": false,
                "canImport(WASILibc)": false,
                "canImport(WatchKit)": false,
                "canImport(WinSDK)": false,
                "canImport(ucrt)": false,
            ],
            closedKinds: ["_endian", "_pointerBitWidth", "_runtime", "arch", "os", "targetEnvironment"]),
        readableObjectVersions: Array(42...56) + [60, 63] + Array(70...77) + [90, 100, 110])
}
