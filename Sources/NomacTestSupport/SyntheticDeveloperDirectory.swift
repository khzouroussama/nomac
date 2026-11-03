import Foundation
import NomacCore

/// Writes a minimal, self-authored Xcode-shaped developer directory for tests.
///
/// It contains only the metadata Swift Build reads to register a platform, an SDK
/// and a toolchain. Every value here was written by hand for nomac's tests; no
/// file is copied from, or derived from, an Apple SDK. Tests that need real SDK
/// content run on the macOS reference runner instead (see docs/VERIFICATION.md).
public enum SyntheticDeveloperDirectory {
    /// Version numbers used throughout the synthetic layout.
    public static let xcodeVersion = "27.0"
    public static let xcodeBuild = "27A100"
    public static let sdkVersion = "27.0"

    /// Creates `<root>/Xcode.app/Contents/Developer` and returns its path.
    @discardableResult
    public static func create(at root: String) throws -> String {
        let contents = root + "/Xcode.app/Contents"
        let developer = contents + "/Developer"
        try write([
            "CFBundleShortVersionString": xcodeVersion,
            "ProductBuildVersion": xcodeBuild,
        ], to: contents + "/version.plist")

        try write([
            "Identifier": "com.apple.dt.toolchain.XcodeDefault",
            "DisplayName": "Xcode Default",
            "Version": xcodeVersion,
        ], to: developer + "/Toolchains/XcodeDefault.xctoolchain/ToolchainInfo.plist")

        // The iOS device platform, and its simulator's, whose SDK a target's SDKROOT can name.
        for (directory, name, environment) in [("iPhoneOS", "iphoneos", nil), ("iPhoneSimulator", "iphonesimulator", "simulator")] as [(String, String, String?)] {
            let platform = developer + "/Platforms/\(directory).platform"
            try write([
                "Type": "Platform",
                "Name": name,
                "Identifier": "com.apple.platform.\(name)",
                "Description": environment == nil ? "iOS" : "iOS Simulator",
                "FamilyName": "iOS",
                "FamilyIdentifier": "ios",
                "FamilyPlatforms": ["Device": "iphoneos", "Simulator": "iphonesimulator"],
                "Version": sdkVersion,
                "DefaultProperties": [
                    "DEPLOYMENT_TARGET_SETTING_NAME": "IPHONEOS_DEPLOYMENT_TARGET",
                ] as [String: Any],
            ], to: platform + "/Info.plist")

            let sdk = platform + "/Developer/SDKs/\(directory)\(sdkVersion).sdk"
            var target: [String: Any] = [
                "Archs": ["arm64"],
                "LLVMTargetTripleVendor": "apple",
                "LLVMTargetTripleSys": "ios",
                "DeploymentTargetSettingName": "IPHONEOS_DEPLOYMENT_TARGET",
                "DefaultDeploymentTarget": sdkVersion,
                "MinimumDeploymentTarget": "15.0",
                "MaximumDeploymentTarget": sdkVersion + ".99",
                "PlatformFamilyName": "iOS",
            ]
            target["LLVMTargetTripleEnvironment"] = environment
            let sdkSettings: [String: Any] = [
                "CanonicalName": "\(name)\(sdkVersion)",
                "DisplayName": "\(environment == nil ? "iOS" : "Simulator - iOS") \(sdkVersion)",
                "Version": sdkVersion,
                "IsBaseSDK": "YES",
                "DefaultProperties": [
                    "PLATFORM_NAME": name,
                ],
                "SupportedTargets": [name: target],
            ]
            let json = try JSONSerialization.data(withJSONObject: sdkSettings, options: [.sortedKeys, .prettyPrinted])
            try FileSystem.write(json, to: sdk + "/SDKSettings.json")
            try FileSystem.write(try PropertyLists.xmlData(sdkSettings), to: sdk + "/SDKSettings.plist")
        }
        return developer
    }

    private static func write(_ dict: [String: Any], to path: String) throws {
        try FileSystem.write(try PropertyLists.xmlData(dict), to: path)
    }
}
