import Foundation
import NomacCore

/// The version of an Xcode installation, read from `Xcode.app/Contents/version.plist`.
public struct XcodeVersionInfo: Sendable, Equatable, Codable {
    /// The marketing version, for example `27.0`.
    public var version: String
    /// The product build version, for example `27A266a`. nomac uses it as the install key.
    public var build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    /// Reads the version of the Xcode whose `Contents/Developer` is `developerDirectory`, or nil
    /// when it has no `version.plist` to read.
    public static func read(developerDirectory: String) -> XcodeVersionInfo? {
        try? read(appPath: ((developerDirectory as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent)
    }

    /// Reads the version of the Xcode at `appPath` (an `Xcode.app` directory).
    public static func read(appPath: String) throws -> XcodeVersionInfo {
        let plistPath = appPath + "/Contents/version.plist"
        let dict = try PropertyLists.readDictionary(at: plistPath)
        guard let version = dict["CFBundleShortVersionString"] as? String else {
            throw NomacError("missing CFBundleShortVersionString; is this an Xcode installation?", path: plistPath)
        }
        guard let build = dict["ProductBuildVersion"] as? String, !build.isEmpty, !build.contains("/") else {
            throw NomacError("missing or invalid ProductBuildVersion; is this an Xcode installation?", path: plistPath)
        }
        return XcodeVersionInfo(version: version, build: build)
    }
}
