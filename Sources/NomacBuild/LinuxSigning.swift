import Foundation

/// How builds sign off macOS, where there is neither `/usr/bin/codesign` nor an Apple-issued
/// identity: ad hoc, with `nomac codesign` (docs/adr/0102-linker.md).
public enum LinuxSigning {
    /// Synthesized settings, below the command line's: `CODESIGN` is looked up in Swift Build's
    /// tool search paths, where `nomac toolchain install` puts the `codesign` launcher; the other
    /// two are what packaging's `signing_experiments.py` passes xcodebuild, with the identity, to
    /// sign ad hoc. The identity stays the project's: ``identity(for:)`` answers for it.
    public static let overrides = [
        "CODESIGN": "codesign",
        "AD_HOC_CODE_SIGNING_ALLOWED": "YES",
        "PROVISIONING_PROFILE_REQUIRED": "NO",
    ]

    /// The identity a target signs with for the `CODE_SIGN_IDENTITY` it resolves: none for an
    /// empty one, for which Xcode 27.0 signs nothing, ad-hoc signing allowed or not (a Swift
    /// package's dynamic product and an app, `signing_identity_experiments.py`), and ad hoc for any
    /// other, for want of a keychain holding an Apple-issued identity (B-302).
    public static func identity(for requested: String) -> String {
        requested.isEmpty ? "" : "-"
    }
}
