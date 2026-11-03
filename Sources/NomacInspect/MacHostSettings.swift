import Foundation
import NomacBuildService

/// The settings Swift Build takes from the machine it runs on rather than from the host identity
/// nomac gives it (`SWBSystemInfo`), made a Mac's when it does not run on macOS
/// (docs/formats/show-build-settings.md, "Settings of the machine").
///
/// Swift Build fixes its host operating system when it is compiled (SWBUtil
/// `ProcessInfo.hostOperatingSystem()`) and reads the CPU from the process (`Architecture.host`).
/// From them SWBCore `Settings.swift` sets `HOST_PLATFORM` (and, off macOS only, the default
/// `SDKROOT = $(HOST_PLATFORM)`), `NATIVE_ARCH` and `NATIVE_ARCH_ACTUAL` (spelled as `uname -m`
/// off macOS), `NATIVE_ARCH_32_BIT` and `NATIVE_ARCH_64_BIT` (on macOS only) and the
/// `MAC_OS_X_*` settings (on macOS only). Passed as synthesized overrides, the Mac's values also
/// reach what Swift Build derives from them: `HOST_ARCH` (`$(NATIVE_ARCH_ACTUAL)`), the bound SDK
/// of a target that sets no `SDKROOT`, the `SUPPORTED_PLATFORMS` and `VALID_ARCHS` of host tools.
public enum MacHostSettings {
    #if os(macOS)
    static let swiftBuildRunsOnMacOS = true
    #else
    static let swiftBuildRunsOnMacOS = false
    #endif

    /// The overrides that make Swift Build evaluate settings as a Mac with `host`'s identity does
    /// (`nomac inspect`, `list`, `verify` and the PIF's evaluated settings); none on macOS, where
    /// it already does.
    public static func overrides(host: HostIdentity) -> [String: String] {
        overrides(host: host, onMacOS: swiftBuildRunsOnMacOS)
    }

    static func overrides(host: HostIdentity, onMacOS: Bool) -> [String: String] {
        guard !onMacOS else { return [:] }
        var settings = ["HOST_PLATFORM": "macosx"]
        // `Architecture.as32bit` and `as64bit` clear and set `CPU_ARCH_ABI64` in the CPU type.
        let counterparts = ["arm64": ("arm", "arm64"), "x86_64": ("i386", "x86_64")]
        if let (bits32, bits64) = counterparts[host.nativeArchitecture] {
            settings["NATIVE_ARCH"] = host.nativeArchitecture
            settings["NATIVE_ARCH_ACTUAL"] = host.nativeArchitecture
            settings["NATIVE_ARCH_32_BIT"] = bits32
            settings["NATIVE_ARCH_64_BIT"] = bits64
        }
        return settings.merging(buildOverrides(host: host, onMacOS: onMacOS)) { $1 }
    }

    /// The overrides of a build (`nomac build`): only the `MAC_OS_X_*` settings, which a build
    /// writes into its products (a framework's Info.plist built on Linux lacked
    /// `BuildMachineOSBuild`, `$(MAC_OS_X_PRODUCT_BUILD_VERSION)`, its only difference from Xcode's:
    /// retro-rampage `Engine`, Release). `HOST_PLATFORM` and `NATIVE_ARCH*` stay the machine's,
    /// because Swift Build also builds host tools (macros, plugins) for them, and those run here.
    /// Off macOS, `nomac build` refuses to run without a Mac identity (`--host-identity`, B-060).
    public static func buildOverrides(host: HostIdentity) -> [String: String] {
        buildOverrides(host: host, onMacOS: swiftBuildRunsOnMacOS)
    }

    static func buildOverrides(host: HostIdentity, onMacOS: Bool) -> [String: String] {
        guard !onMacOS, host.isMacOS else { return [:] }
        return macOSVersionSettings(host)
    }

    /// The `MAC_OS_X_*` settings Swift Build computes on macOS from the system information.
    static func macOSVersionSettings(_ host: HostIdentity) -> [String: String] {
        let version = host.operatingSystemVersion + Array(repeating: 0, count: max(0, 3 - host.operatingSystemVersion.count))
        let major = String(format: "%02d", version[0])
        let minor = String(format: "%02d", version[1])
        let update = String(format: "%02d", version[2])
        let legacy = version[0] <= 10
        return [
            "MAC_OS_X_VERSION_MAJOR": legacy ? major + minor + "00" : major + "0000",
            "MAC_OS_X_VERSION_MINOR": legacy ? minor + update : major + minor + "00",
            "MAC_OS_X_VERSION_ACTUAL": major + minor + update,
            "MAC_OS_X_PRODUCT_BUILD_VERSION": host.operatingSystemBuild,
        ]
    }
}
