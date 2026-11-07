import Foundation

/// The files nomac keeps from a user's Xcode, as paths relative to `Xcode.app`.
///
/// Two kinds of files are kept (docs/adr/0003-sdk-extraction.md):
///
/// * **Metadata of every platform, SDK and toolchain.** (Including the toolchain's
///   `usr/share/swift/SwiftConstantValues` lists, and each SDK's `usr/lib/libobjc.tbd`, whose
///   presence Swift Build reads for a setting.) Swift Build registers every
///   platform it finds, and several build settings list them (for example
///   `AVAILABLE_PLATFORMS`), so the metadata of all platforms is needed even when building
///   for one. These files are small.
/// * **Payload of the selected platforms.** The SDK itself (headers, `.tbd` stubs, Swift
///   modules), the platform's testing frameworks and UI test runner, and the toolchain's per-platform runtime
///   libraries and Clang resource headers (with the `usr/lib/swift/clang` link to them), and the
///   toolchain modules' API notes (`usr/lib/swift/apinotes`), and the stub executables Swift
///   Build copies into Messages extensions and apps (``messagesStubs``).
/// * **The XCTest and Swift Testing binaries of every platform.** SwiftPM derives the
///   minimum deployment target of package test products from their `LC_BUILD_VERSION`
///   (docs/adr/0010-swift-packages.md). Only the paths that resolve each binary are kept.
/// * **The App Shortcuts phrase lists** of `SiriSSUKitModel.framework` (`prefix`,
///   `standardAppShortcutNegatives`), which every App Shortcuts training expands
///   (docs/formats/app-intents.md), with the links that resolve its `Resources`.
///
/// Nothing is modified: kept files are copied byte for byte, symbolic links stay links.
public struct XcodeSubset: Sendable, Equatable {
    /// Platform directory names (`iPhoneOS`, `iPhoneSimulator`, ...) whose payload is kept.
    public var payloadPlatforms: Set<String>

    /// The default selection: the iOS device platform, which is what nomac builds for, and the
    /// watchOS device platform, whose SDK and Swift runtime an iOS app's embedded watch app builds
    /// with (home-assistant's and pocket-casts' watch targets, arm64_32: "no such module 'Swift'"
    /// with the iOS payload alone), and the macOS platform, whose SDK links what scripts make for
    /// macOS with `xcrun --sdk macosx clang -dynamiclib` (``Xcrun/clangTarget``; Expo's
    /// `create-stub-xcframework.sh`, which `pod install` runs: "library not found for -lSystem"
    /// without it). The macOS payload adds 1.4 GB.
    public static let defaultPayloadPlatforms: Set<String> = ["iPhoneOS", "WatchOS", "MacOSX"]

    public init(payloadPlatforms: Set<String> = XcodeSubset.defaultPayloadPlatforms) {
        self.payloadPlatforms = payloadPlatforms
    }

    /// Decides whether to descend into, or keep, the path `relative` (components inside
    /// `Xcode.app`, for example `["Contents", "Developer", "Platforms"]`).
    ///
    /// - Returns: `.keep` to copy the file or whole directory, `.descend` to look inside a
    ///   directory, or `.skip`.
    public func decide(_ relative: [String], isDirectory: Bool) -> Decision {
        guard relative.first == "Contents" else { return .skip }
        let rest = Array(relative.dropFirst())
        if rest.isEmpty { return .descend }
        if rest.count == 1 {
            if rest[0] == "version.plist" || rest[0] == "Info.plist" { return .keep }
            return rest[0] == "Developer" || rest[0] == "Frameworks" ? .descend : .skip
        }
        if rest[0] == "Frameworks" { return decidePhraseLists(Array(rest.dropFirst())) }
        guard rest[0] == "Developer" else { return .skip }
        let developer = Array(rest.dropFirst())
        switch developer.first {
        case "Platforms":
            return decidePlatforms(Array(developer.dropFirst()), isDirectory: isDirectory)
        case "Toolchains":
            return decideToolchains(Array(developer.dropFirst()), isDirectory: isDirectory)
        default:
            return .skip
        }
    }

    public enum Decision: Sendable, Equatable {
        case keep
        case descend
        case skip
    }

    // Platforms/<Name>.platform/...
    private func decidePlatforms(_ path: [String], isDirectory: Bool) -> Decision {
        guard let platformDir = path.first else { return .descend }
        guard platformDir.hasSuffix(".platform") else { return .skip }
        let platformName = String(platformDir.dropLast(".platform".count))
        let inside = Array(path.dropFirst())
        guard let first = inside.first else { return .descend }
        if first == "Library" {
            return payloadPlatforms.contains(platformName) ? decideApplicationSupport(Array(inside.dropFirst())) : .skip
        }
        if inside.count == 1 {
            if first == "Info.plist" || first == "version.plist" { return .keep }
            return first == "Developer" || (first == "usr" && payloadPlatforms.contains(platformName)) ? .descend : .skip
        }
        if first == "usr" {
            // The device traits app thinning groups devices by (`nomac export`, docs/formats/ipa.md
            // "App thinning").
            guard payloadPlatforms.contains(platformName) else { return .skip }
            if inside == ["usr", "standalone"] { return .descend }
            return inside == ["usr", "standalone", "device_traits.db"] ? .keep : .skip
        }
        guard first == "Developer" else { return .skip }
        let developer = Array(inside.dropFirst())
        let isPayload = payloadPlatforms.contains(platformName)
        switch developer.first {
        case "SDKs":
            return decideSDKs(Array(developer.dropFirst()), isPayload: isPayload, isDirectory: isDirectory)
        case "Library":
            let library = Array(developer.dropFirst())
            guard let kind = library.first else { return .descend }
            if isPayload {
                if kind == "Xcode" { return decideTestRunner(Array(library.dropFirst())) }
                return (kind == "Frameworks" || kind == "PrivateFrameworks") ? .keep : .skip
            }
            return kind == "Frameworks" ? decideTestingBinary(Array(library.dropFirst())) : .skip
        case "usr":
            guard isPayload else { return .skip }
            let usr = Array(developer.dropFirst())
            guard let kind = usr.first else { return .descend }
            return kind == "lib" ? .keep : .skip
        default:
            return .skip
        }
    }

    /// `Library/Xcode/Agents/XCTRunner.app`, which a UI test target's build copies as
    /// `<Target>-Runner.app` (docs/formats/xctestrun.md "What the build products are").
    private func decideTestRunner(_ path: [String]) -> Decision {
        guard let first = path.first else { return .descend }
        guard first == "Agents" else { return .skip }
        guard let agent = path.dropFirst().first else { return .descend }
        return agent == "XCTRunner.app" ? .keep : .skip
    }

    /// The folders of `<Name>.platform/Library/Application Support` whose stub executable Swift
    /// Build copies as the executable of a sticker pack (`MessagesApplicationExtensionStub`) and of
    /// a Messages app (`MessagesApplicationStub`, with its asset catalog): wikipedia's
    /// `Wikipedia Stickers.appex`.
    public static let messagesStubs = ["MessagesApplicationExtensionStub", "MessagesApplicationStub"]

    // Platforms/<Name>.platform/Library/Application Support/<stub>/...
    private func decideApplicationSupport(_ path: [String]) -> Decision {
        guard let first = path.first else { return .descend }
        guard first == "Application Support" else { return .skip }
        guard let stub = path.dropFirst().first else { return .descend }
        return Self.messagesStubs.contains(stub) ? .keep : .skip
    }

    /// The phrase lists of `SiriSSUKitModel.framework` App Shortcuts training reads, by locale.
    static let phraseLists = ["prefix", "standardAppShortcutNegatives"]

    // Frameworks/SiriSSUKitModel.framework/...: the `Resources` and `Versions/Current` links and
    // `Versions/<v>/Resources/<list>`.
    private func decidePhraseLists(_ path: [String]) -> Decision {
        guard path.first == "SiriSSUKitModel.framework" else { return .skip }
        let inside = Array(path.dropFirst())
        switch inside.count {
        case 0: return .descend
        case 1: return inside[0] == "Resources" ? .keep : (inside[0] == "Versions" ? .descend : .skip)
        case 2: return inside[0] == "Versions" ? (inside[1] == "Current" ? .keep : .descend) : .skip
        case 3: return inside[0] == "Versions" && inside[2] == "Resources" ? .descend : .skip
        case 4: return inside[0] == "Versions" && Self.phraseLists.contains(inside[3]) ? .keep : .skip
        default: return .skip
        }
    }

    /// The testing frameworks whose binaries a non-payload platform keeps.
    static let testingFrameworks = ["XCTest", "Testing"]

    // Platforms/<Name>.platform/Developer/Library/Frameworks/<Name>.framework/...: the binary,
    // and for a versioned framework the `Versions/Current` link and `Versions/<v>/<Name>`.
    private func decideTestingBinary(_ path: [String]) -> Decision {
        guard let frameworkDir = path.first else { return .descend }
        guard frameworkDir.hasSuffix(".framework") else { return .skip }
        let name = String(frameworkDir.dropLast(".framework".count))
        guard Self.testingFrameworks.contains(name) else { return .skip }
        let inside = Array(path.dropFirst())
        switch inside.count {
        case 0: return .descend
        case 1: return inside[0] == name ? .keep : (inside[0] == "Versions" ? .descend : .skip)
        case 2: return inside[0] == "Versions" ? (inside[1] == "Current" ? .keep : .descend) : .skip
        case 3: return inside[0] == "Versions" && inside[2] == name ? .keep : .skip
        default: return .skip
        }
    }

    // Platforms/<Name>.platform/Developer/SDKs/<Name><Version>.sdk/...
    private func decideSDKs(_ path: [String], isPayload: Bool, isDirectory: Bool) -> Decision {
        guard let sdkDir = path.first else { return .descend }
        guard sdkDir.hasSuffix(".sdk") else { return .skip }
        if isPayload { return .keep }
        // SDK directories are often symbolic links to the versioned SDK (iPhoneOS.sdk ->
        // iPhoneOS27.0.sdk). A link is a file here: keep it so both names resolve.
        if path.count == 1 { return isDirectory ? .descend : .keep }
        let inside = Array(path.dropFirst())
        if Self.sdkMetadataFiles.contains(inside) { return .keep }
        return Self.sdkMetadataFiles.contains { $0.count > inside.count && Array($0.prefix(inside.count)) == inside } ? .descend : .skip
    }

    /// The files kept from every SDK, as paths inside the `.sdk` directory: its settings, its
    /// system version, and `usr/lib/libobjc.tbd`, whose presence Swift Build reads for
    /// `LINK_OBJC_RUNTIME` (SWBCore `Settings.swift`, `addSDKSettings`; netnewswire's macOS
    /// targets and moonlight's tvOS target printed `NO` without it, Xcode `YES`). That file
    /// links to `libobjc.A.tbd` in every SDK of Xcode 27.0 but DriverKit's, which has neither,
    /// and Swift Build follows the link.
    static let sdkMetadataFiles: [[String]] = [
        ["SDKSettings.json"],
        ["SDKSettings.plist"],
        ["System", "Library", "CoreServices", "SystemVersion.plist"],
        ["usr", "lib", "libobjc.tbd"],
        ["usr", "lib", "libobjc.A.tbd"],
    ]

    // Toolchains/<Name>.xctoolchain/...
    private func decideToolchains(_ path: [String], isDirectory: Bool) -> Decision {
        guard let toolchainDir = path.first else { return .descend }
        guard toolchainDir.hasSuffix(".xctoolchain") else { return .skip }
        let inside = Array(path.dropFirst())
        guard let first = inside.first else { return .descend }
        if inside.count == 1 {
            if first == "ToolchainInfo.plist" { return .keep }
            return first == "usr" ? .descend : .skip
        }
        guard first == "usr" else { return .skip }
        // The toolchain's Swift constant-value protocol lists feed SWIFT_EMIT_CONST_VALUE_PROTOCOLS.
        let constantValues = ["usr", "share", "swift", "SwiftConstantValues"]
        if inside.count <= constantValues.count {
            if Array(constantValues.prefix(inside.count)) == inside {
                return inside.count == constantValues.count ? .keep : .descend
            }
        }
        guard inside[1] == "lib" else { return .skip }
        let lib = Array(inside.dropFirst(2))
        guard let kind = lib.first else { return .descend }
        switch kind {
        case "clang", "arc":
            return payloadPlatforms.isEmpty ? .skip : .keep
        case "swift", "swift_static":
            guard let platform = lib.dropFirst().first else { return .descend }
            // `usr/lib/swift/clang` links to Clang's resource directory; the Swift compiler's
            // Clang importer reads the builtin headers through it (docs/adr/0100-linux-toolchain.md).
            // `usr/lib/swift/apinotes` holds the API notes of the toolchain's own modules
            // (Dispatch, os, std, std_span, std_string_view), which the compiler applies when it
            // imports them, C++ interoperability included.
            if kind == "swift", ["clang", "apinotes"].contains(platform) { return payloadPlatforms.isEmpty ? .skip : .keep }
            return payloadSDKNames.contains(platform) ? .keep : .skip
        default:
            return .skip
        }
    }

    /// Lower-case SDK directory names used inside the toolchain (`iphoneos`, `iphonesimulator`).
    private var payloadSDKNames: Set<String> {
        Set(payloadPlatforms.map { $0.lowercased() })
    }
}
