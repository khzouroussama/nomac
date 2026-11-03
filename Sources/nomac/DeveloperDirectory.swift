import ArgumentParser
import Foundation
import NomacCore
import NomacSDK

/// The Xcode developer directory a command uses: `--developer-dir`, else
/// `$NOMAC_DEVELOPER_DIR`, else the selected `nomac sdk` install. Its Xcode is checked against
/// the one this nomac reproduces (`XcodeBuildCheck`): a warning, or with `strictXcode` an error.
enum DeveloperDirectory {
    static func resolve(option: String?, strictXcode: Bool) throws -> String {
        let path = try locate(option: option)
        try XcodeCheck.developerDirectory(path, strict: strictXcode)
        return path
    }

    /// For commands that need a developer directory only for some workspaces: nil when none is
    /// given and none is installed.
    static func resolveIfAvailable(option: String?, strictXcode: Bool) throws -> String? {
        guard let path = option.map(FileSystem.absolute) ?? (try? locate(option: nil)) else { return nil }
        try XcodeCheck.developerDirectory(path, strict: strictXcode)
        return path
    }

    private static func locate(option: String?) throws -> String {
        if let option { return FileSystem.absolute(option) }
        if let fromEnvironment = ProcessInfo.processInfo.environment["NOMAC_DEVELOPER_DIR"], !fromEnvironment.isEmpty {
            return FileSystem.absolute(fromEnvironment)
        }
        return try SDKStore.default().resolve(build: nil).developerDirectory
    }
}

/// Prints `XcodeBuildCheck`'s warnings, as xcodebuild prints its own.
enum XcodeCheck {
    static var strictHelp: ArgumentHelp {
        ArgumentHelp("Refuse an Xcode other than the one this nomac reproduces (\(XcodeProfile.current.xcode.version), \(XcodeProfile.current.xcode.build)) instead of warning.")
    }

    static func developerDirectory(_ path: String, strict: Bool) throws {
        try version(XcodeVersionInfo.read(developerDirectory: path), at: path, strict: strict)
    }

    static func version(_ version: XcodeVersionInfo?, at path: String, strict: Bool) throws {
        if let warning = try XcodeBuildCheck.check(version, at: path, strict: strict) {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }
}
