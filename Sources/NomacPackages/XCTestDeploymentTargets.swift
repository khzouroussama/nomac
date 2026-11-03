import Foundation
import NomacCore
import struct PackageModel.Platform
import struct PackageModel.PlatformVersion

/// The minimum deployment target of package test products, per platform: the highest of
/// `XCTest.framework/XCTest`'s and `Testing.framework/Testing`'s values in the platform's
/// `Developer/Library/Frameworks`, each the lowest `minos` of its slices built for the platform,
/// and at least 14.0 for macOS. A test product never deploys below it.
///
/// Xcode 27.0's watchOS binaries are arm64 26.0, arm64e 26.0 and arm64_32 10.0, and test
/// products get watchOS 10.0 (package-experiments: a package declaring watchOS 5 or 9 gets 10.0,
/// 10.5 keeps 10.5; kickstarter's `Library-Tests`), where SwiftPM's own `vtool` reading, the
/// first slice, gives 26.0. nomac reads the load commands from the developer directory itself,
/// as `vtool` does not exist on Linux (netnewswire, icecubes: Xcode gives test products macOS
/// 14.0 where the package declares macOS 12).
public enum XCTestDeploymentTargets {
    /// The values for every platform whose testing binaries are in `developerDirectory`, and
    /// the platforms whose binaries are missing.
    public static func compute(developerDirectory: String) -> (targets: [Platform: PlatformVersion], missing: [Platform]) {
        var targets: [Platform: PlatformVersion] = [:]
        var missing: [Platform] = []
        for (platform, directory, machOPlatform) in platforms {
            let frameworks = "\(developerDirectory)/Platforms/\(directory).platform/Developer/Library/Frameworks"
            let versions = ["XCTest", "Testing"].compactMap { name in
                minimumOS(of: "\(frameworks)/\(name).framework/\(name)", platform: machOPlatform)
            }
            let floor: [PlatformVersion] = platform == .macOS ? [PlatformVersion("14.0")] : []
            if versions.isEmpty { missing.append(platform) }
            if let highest = (versions + floor).max() {
                targets[platform] = highest
            }
        }
        return (targets, missing)
    }

    /// Platforms with testing frameworks, the platform directory SwiftPM's `xcrun --sdk`
    /// lookup resolves to, and the `LC_BUILD_VERSION` platform it looks for.
    private static let platforms: [(Platform, String, UInt32)] = [
        (.macOS, "MacOSX", MachOBuildVersion.platformMacOS),
        (.macCatalyst, "MacOSX", MachOBuildVersion.platformMacCatalyst),
        (.iOS, "iPhoneOS", MachOBuildVersion.platformIOS),
        (.tvOS, "AppleTVOS", MachOBuildVersion.platformTvOS),
        (.watchOS, "WatchOS", MachOBuildVersion.platformWatchOS),
        (.visionOS, "XROS", MachOBuildVersion.platformVisionOS),
    ]

    /// The lowest `minos` of the slices built for `platform`.
    private static func minimumOS(of path: String, platform: UInt32) -> PlatformVersion? {
        guard FileManager.default.fileExists(atPath: path),
              let entries = try? MachOBuildVersion.entries(atPath: path) else { return nil }
        return entries.filter { $0.platform == platform }.map { PlatformVersion($0.minimumOS) }.min()
    }
}
