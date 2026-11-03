import ArgumentParser
import Foundation
import NomacCore
import NomacSigning

/// `nomac embeddedBinaryValidationUtility`: Xcode's check of an app extension or app that an app
/// embeds, which Swift Build runs as `ValidateEmbeddedBinary` after copying it
/// (`<bundle> [-signing-cert <identity>] -info-plist-path <app's Info.plist>`), behind the launcher
/// `nomac toolchain install` writes where Xcode keeps the tool. As Xcode 27.0's
/// (`.github/scripts/embedded_binary_validation_experiments.py`): it changes nothing and reports on
/// standard error, stopping at the first error (exit status 1): the bundle's Info.plist, the
/// parent's, then, with a signing identity, the bundle's signature (`-` takes an ad hoc one), then,
/// for an app extension (an Info.plist with `NSExtension` or `EXAppExtensionAttributes`), the
/// bundle identifier, which must start with the parent's, and one warning for a `CFBundleVersion`,
/// else a `CFBundleShortVersionString`, that differs from the parent's.
struct EmbeddedBinaryValidationCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "embeddedBinaryValidationUtility",
        abstract: "Validate an app extension or app embedded in an app, as Xcode's embeddedBinaryValidationUtility does.",
        discussion: "Takes <bundle> [-signing-cert <identity>] -info-plist-path <path> (.github/scripts/embedded_binary_validation_experiments.py).",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "<bundle> [-signing-cert <identity>] -info-plist-path <path>")
    var arguments: [String] = []

    func run() throws {
        let (status, messages) = Self.validate(arguments)
        FileHandle.standardError.write(Data(messages.utf8))
        if status != 0 { throw ExitCode(status) }
    }

    static let mismatchedCertificate = "error: Embedded binary is not signed with the same certificate as the parent app. Verify the embedded binary target's code sign settings match the parent app's.\n\n\t\tEmbedded Binary Signing Certificate:\t%@\n\t\tParent App Signing Certificate:\t\t%@\n\n\n"
    static let unprefixedIdentifier = "error: Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier.\n\n\t\tEmbedded Binary Bundle Identifier:\t%@\n\t\tParent App Bundle Identifier:\t\t%@\n\n\n"

    /// The exit status and what the tool writes on standard error.
    static func validate(_ arguments: [String]) -> (Int32, String) {
        var bundle: String?
        var identity: String?
        var parentInfoPlist: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "-signing-cert" where index + 1 < arguments.count:
                identity = arguments[index + 1]
                index += 1
            case "-info-plist-path" where index + 1 < arguments.count:
                parentInfoPlist = arguments[index + 1]
                index += 1
            default:
                if bundle != nil { return (1, "error: multiple input paths specified\n") }
                bundle = arguments[index]
            }
            index += 1
        }
        guard let bundle else { return (1, "error: must provide a path to an embedded binary\n") }
        guard let info = dictionary(at: bundle + "/Info.plist") else {
            // macOS names the bundle by an object whose address changes with each run.
            return (1, "error: Couldn't load Info dictionary for <DVTFilePath:0x0:'\(bundle)'>\n")
        }
        var parent: [String: Any] = [:]
        if let parentInfoPlist {
            guard let loaded = dictionary(at: parentInfoPlist) else { return (1, "error: cannot compute parent bundle path\n") }
            parent = loaded
        }
        if let identity, !identity.isEmpty {
            let executable = (info["CFBundleExecutable"] as? String).map { bundle + "/" + $0 }
            let signature = (executable.flatMap { try? BundleSignature.of(executable: $0) }) ?? .unsigned
            let matches = switch signature {
            case .adHoc: identity == "-"
            case .certificate(let sha1, _): sha1.caseInsensitiveCompare(identity) == .orderedSame
            case .unsigned: false
            }
            if !matches {
                let embedded = switch signature {
                case .unsigned: "Not Code Signed"
                case .adHoc: "- (Ad Hoc Code Signed)"
                case .certificate(_, let commonName): commonName
                }
                // An identity other than `-` is one macOS looks up in the keychain; nomac has none to look in.
                let expected = identity == "-" ? "- (Ad Hoc Code Signed)" : "(null)"
                return (1, String(format: mismatchedCertificate, embedded, expected))
            }
        }
        guard info["NSExtension"] != nil || info["EXAppExtensionAttributes"] != nil else { return (0, "") }
        let identifier = info["CFBundleIdentifier"] as? String
        if let parentIdentifier = parent["CFBundleIdentifier"] as? String, !(identifier?.hasPrefix(parentIdentifier) ?? false) {
            return (1, String(format: unprefixedIdentifier, identifier ?? "(null)", parentIdentifier))
        }
        for key in ["CFBundleVersion", "CFBundleShortVersionString"] {
            let value = info[key] as? String, parentValue = parent[key] as? String
            guard value != parentValue else { continue }
            func quoted(_ text: String?) -> String { text.map { "'\($0)'" } ?? "null" }
            return (0, "warning: The \(key) of an app extension (\(quoted(value))) must match that of its containing parent app (\(quoted(parentValue))).\n")
        }
        return (0, "")
    }

    static func dictionary(at path: String) -> [String: Any]? {
        FileManager.default.contents(atPath: path).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    }
}
