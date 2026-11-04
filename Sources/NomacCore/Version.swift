/// nomac's own version (docs/adr/0012-one-xcode-per-release.md).
public enum NomacVersion {
    /// The version, in ADR 0012's scheme: the major and minor
    /// version of the one Xcode nomac reproduces, then nomac's release counter for that Xcode.
    /// The scheme is this one line, and nothing else depends on it.
    public static let current = "\(XcodeProfile.current.xcode.majorMinor).2"

    /// What `nomac --version` prints: `nomac 27.0.2 (Xcode 27.0, 27A266a)`.
    public static let full = "nomac \(current) (Xcode \(XcodeProfile.current.xcode.version), \(XcodeProfile.current.xcode.build))"
}
