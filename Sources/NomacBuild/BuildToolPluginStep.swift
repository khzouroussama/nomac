import Foundation
import NomacCore
import NomacPackages
import NomacSDK

/// The step of a build that applies the package targets' build tool plugins before Swift Build
/// plans it, with what Xcode 27.0 gives them (`build_plugin_experiments.py`; docs/formats/build.md
/// "Build tool plugins").
public enum BuildToolPluginStep {
    /// The plugin runner of a build whose products go to `buildProducts` and intermediates to
    /// `intermediates`, with `developerDirectory`'s Xcode.
    ///
    /// On a Mac, the plugins are compiled with Xcode's compiler against
    /// `SharedFrameworks/SwiftPM.framework/SharedSupport/PluginAPI`, told that the tools built from
    /// source are in `/${BUILD_DIR}/${CONFIGURATION}`, the products of their macOS builds, and
    /// their commands run in macOS's sandbox. Off macOS, the plugins and their tools are built for the build machine:
    /// with the toolchain that evaluates the manifests, against nomac's `PackagePlugin` and
    /// `XcodeProjectPlugin`, which it builds for that compiler under nomac's home, the tools in
    /// `${CONFIGURATION}-linux-<architecture>`, where Swift Build puts its Linux builds, and the
    /// commands without a sandbox, as script phases (ADR 0103).
    public static func plugins(buildProducts: String, intermediates: String, developerDirectory: String,
                               log: @escaping @Sendable (String) -> Void) -> BuildToolPlugins {
        #if os(macOS)
        let contents = ((developerDirectory as NSString).deletingLastPathComponent as NSString)
        return BuildToolPlugins(buildProducts: buildProducts, intermediates: intermediates,
                                swiftCompiler: developerDirectory + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
                                pluginLibraries: contents.appendingPathComponent("SharedFrameworks/SwiftPM.framework/SharedSupport"),
                                builtToolsDirectory: "/${BUILD_DIR}/${CONFIGURATION}",
                                pluginTarget: (Self.machineArchitecture() + "-apple-macos",
                                               developerDirectory + "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX\(XcodeProfile.current.sdks.first { $0.platform == "macosx" }?.version ?? "").sdk"), log: log)
        #else
        return BuildToolPlugins(buildProducts: buildProducts, intermediates: intermediates, swiftCompiler: nil, pluginLibraries: nil,
                                builtToolsDirectory: "/${BUILD_DIR}/${CONFIGURATION}-linux-" + machineArchitecture(), pluginTarget: nil,
                                pluginAPICache: SDKStore.default().root + "/scratch/plugin-api", log: log)
        #endif
    }

    static func machineArchitecture() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
