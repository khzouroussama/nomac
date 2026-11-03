import Foundation
import struct PackageModel.Platform
import struct PackageModel.PlatformVersion

/// The tvOS, watchOS and visionOS versions Xcode gives a package that declares only an iOS
/// version (`suggestAlignedPlatformVersionGiveniOSVersion`).
///
/// They are the SDKs' own version maps: the `VersionMap` of `SDKSettings.json` in the tvOS,
/// watchOS and visionOS SDKs (`iOS_tvOS`, `iOS_watchOS`, `iOS_visionOS`), looked up at the
/// greatest iOS version not above the declared one. `package-experiments` checked every iOS
/// minor version from 15.0 to 27.4 with Xcode 27.0: the maps reproduce all of them (iOS 17.4.1
/// gives tvOS 17.4, iOS 17.5 gives visionOS 1.2, iOS 26.1 gives watchOS 26.0). SwiftPM keeps
/// the platform's oldest supported version when the mapped one is older.
public struct PlatformAlignment: Sendable {
    /// For each platform, the map's entries sorted by iOS version.
    private let maps: [Platform: [(iOS: PlatformVersion, version: PlatformVersion)]]

    /// The maps of the SDKs in `developerDirectory`; a platform without an SDK is not aligned.
    public init(developerDirectory: String) {
        var maps: [Platform: [(iOS: PlatformVersion, version: PlatformVersion)]] = [:]
        for (platform, sdk, mapName) in Self.sources {
            let path = "\(developerDirectory)/Platforms/\(sdk).platform/Developer/SDKs/\(sdk).sdk/SDKSettings.json"
            guard let data = FileManager.default.contents(atPath: path),
                  let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let versionMap = settings["VersionMap"] as? [String: Any],
                  let map = versionMap[mapName] as? [String: String] else { continue }
            maps[platform] = map.map { (iOS: PlatformVersion($0.key), version: PlatformVersion($0.value)) }
                .sorted { $0.iOS < $1.iOS }
        }
        self.maps = maps
    }

    /// The platform, its SDK directory name and the name of its map from iOS.
    private static let sources: [(Platform, String, String)] = [
        (.tvOS, "AppleTVOS", "iOS_tvOS"),
        (.watchOS, "WatchOS", "iOS_watchOS"),
        (.visionOS, "XROS", "iOS_visionOS"),
    ]

    /// The version of `platform` aligned with `iOSVersion`, or nil when the platform has no map
    /// or the map starts after `iOSVersion`.
    public func version(of platform: Platform, alignedWith iOSVersion: PlatformVersion) -> String? {
        maps[platform]?.last(where: { $0.iOS <= iOSVersion })?.version.versionString
    }
}
