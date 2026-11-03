import Foundation

/// Swift Build's resource bundles, which SwiftPM installs next to the nomac executable (and
/// next to the test bundle in tests, which macOS loads into a helper of the toolchain):
/// `SwiftBuild_<Module>.bundle`, with the resources at its top level on Linux and under
/// `Contents/Resources` on macOS.
public enum SwiftBuildResources {
    private final class Marker {}

    /// The resource directory of a Swift Build module's bundle, or `nil` if it is not installed
    /// next to the running executable or the bundle nomac's code was loaded from.
    public static func directory(module: String) -> String? {
        let executable = (CommandLine.arguments.first.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) ?? ""
        let candidates = [(executable as NSString).deletingLastPathComponent, (Bundle.main.bundlePath as NSString).deletingLastPathComponent, Bundle.main.bundlePath,
                          (Bundle(for: Marker.self).bundlePath as NSString).deletingLastPathComponent]
        for directory in candidates {
            let bundle = "\(directory)/SwiftBuild_\(module).bundle"
            if FileManager.default.fileExists(atPath: bundle + "/Contents/Resources") {
                return bundle + "/Contents/Resources"
            }
            if FileManager.default.fileExists(atPath: bundle) {
                return bundle
            }
        }
        return nil
    }
}
