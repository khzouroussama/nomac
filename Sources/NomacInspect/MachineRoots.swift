import Foundation
import NomacBuildService
import NomacCore
import NomacVerify

/// The machine-specific path roots a comparison rewrites (docs/adr/0004-reference-artifacts.md
/// and docs/adr/0006-machine-specific-roots.md), on the reference side and on nomac's side.
enum MachineRoots {
    /// Swift Build plugin modules whose resource directories appear in settings (`PATH`
    /// starts with the universal platform plugin's resources).
    static let pluginModules = [
        "SWBUniversalPlatform", "SWBApplePlatform", "SWBAndroidPlatform", "SWBGenericUnixPlatform",
        "SWBQNXPlatform", "SWBWebAssemblyPlatform", "SWBWindowsPlatform",
    ]

    /// The resource directory of a Swift Build plugin inside an Xcode installation.
    static func xcodePluginResources(xcodeApp: String, module: String) -> String {
        "\(xcodeApp)/Contents/SharedFrameworks/SwiftBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/PlugIns/\(module)Plugin.bundle/Contents/Frameworks/\(module).framework/Resources"
    }

    /// The resource directory of a Swift Build plugin next to the running nomac executable.
    static func nomacPluginResources(module: String) -> String? {
        SwiftBuildResources.directory(module: module)
    }

    /// The per-user cache directory Swift Build uses for target-mode caches: Darwin's
    /// `DARWIN_USER_CACHE_DIR`, or the temporary directory elsewhere (SWBUtil `userCacheDir()`).
    static func localUserCacheDirectory() -> String {
        #if canImport(Darwin)
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(length, 1))
        _ = confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, length)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #else
        return FileManager.default.temporaryDirectory.path
        #endif
    }

    static func roots(referenceHost: ReferenceHost, referenceSource: String, sourceRoot: String, developerDirectory: String) -> [PathNormalizer.Root] {
        var roots = [
            PathNormalizer.Root(path: referenceSource, symbol: "<SOURCE_ROOT>"),
            PathNormalizer.Root(path: sourceRoot, symbol: "<SOURCE_ROOT>"),
            PathNormalizer.Root(path: referenceHost.developerDirectory, symbol: "<DEVELOPER_DIR>"),
            PathNormalizer.Root(path: developerDirectory, symbol: "<DEVELOPER_DIR>"),
        ]
        let resolvedDeveloper = (developerDirectory as NSString).resolvingSymlinksInPath
        if resolvedDeveloper != developerDirectory {
            roots.append(PathNormalizer.Root(path: resolvedDeveloper, symbol: "<DEVELOPER_DIR>"))
        }
        if let cache = referenceHost.userCacheDirectory, !cache.isEmpty {
            roots.append(PathNormalizer.Root(path: cache, symbol: "<USER_CACHE_DIR>"))
            roots.append(PathNormalizer.Root(path: localUserCacheDirectory(), symbol: "<USER_CACHE_DIR>"))
        }
        let referenceApp = ((referenceHost.developerDirectory as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        for module in pluginModules {
            let symbol = "<SWIFT_BUILD_RESOURCES:\(module)>"
            roots.append(PathNormalizer.Root(path: xcodePluginResources(xcodeApp: referenceApp, module: module), symbol: symbol))
            if let local = nomacPluginResources(module: module) {
                roots.append(PathNormalizer.Root(path: local, symbol: symbol))
            }
        }
        return roots
    }
}
