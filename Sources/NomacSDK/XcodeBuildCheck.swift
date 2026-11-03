import NomacCore

/// Whether an Xcode is the build this nomac reproduces (docs/adr/0012-one-xcode-per-release.md):
/// any other build is reported, as a warning or, when strict, as an error.
public enum XcodeBuildCheck {
    /// The warning for the Xcode at `path` whose version is `version` (nil when it has none), or
    /// nil when it is `profile`'s build. With `strict`, the warning is thrown as an error instead.
    public static func check(_ version: XcodeVersionInfo?, at path: String, strict: Bool, profile: XcodeProfile = .current) throws -> String? {
        let expected = profile.xcode
        guard version?.build != expected.build else { return nil }
        let found = version.map { "Xcode \($0.version) (\($0.build))" } ?? "an Xcode without a readable version.plist"
        let message = "\(path) is \(found), but nomac \(NomacVersion.current) reproduces Xcode \(expected.version) (\(expected.build)) only"
        if strict {
            throw NomacError(message, notes: ["use Xcode \(expected.version) (\(expected.build)), or the nomac release made for this Xcode"])
        }
        return message + "; outputs may differ from that Xcode's (--strict-xcode refuses other builds)"
    }
}
