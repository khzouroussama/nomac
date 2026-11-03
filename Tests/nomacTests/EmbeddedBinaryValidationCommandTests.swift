import Foundation
import Testing
@testable import nomac

/// `nomac embeddedBinaryValidationUtility`: Xcode 27.0's messages and exit statuses
/// (embedded_binary_validation_experiments.py).
@Suite struct EmbeddedBinaryValidationCommandTests {
    func app(extension changes: [String: Any?]) throws -> (bundle: String, infoPlist: String, root: String) {
        let root = NSTemporaryDirectory() + "embedded-validation-\(UUID().uuidString)"
        let bundle = root + "/App.app/PlugIns/W.appex"
        try FileManager.default.createDirectory(atPath: bundle, withIntermediateDirectories: true)
        let parent: [String: Any] = ["CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
        var embedded = parent.merging(["CFBundleIdentifier": "com.example.app.W", "NSExtension": [String: Any]()]) { $1 }
        for (key, value) in changes { embedded[key] = value }
        for (path, dictionary) in [(root + "/App.app/Info.plist", parent), (bundle + "/Info.plist", embedded)] {
            try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0).write(to: URL(fileURLWithPath: path))
        }
        return (bundle, root + "/App.app/Info.plist", root)
    }

    @Test func reportsAnExtensionsIdentifierAndVersionsAsXcode() throws {
        let unprefixed = try app(extension: ["CFBundleIdentifier": "com.other.w", "CFBundleVersion": "7"])
        defer { try? FileManager.default.removeItem(atPath: unprefixed.root) }
        #expect(EmbeddedBinaryValidationCommand.validate([unprefixed.bundle, "-info-plist-path", unprefixed.infoPlist]) == (1, """
            error: Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier.

            \t\tEmbedded Binary Bundle Identifier:\tcom.other.w
            \t\tParent App Bundle Identifier:\t\tcom.example.app



            """))

        let versions = try app(extension: ["CFBundleShortVersionString": "2.0", "CFBundleVersion": nil])
        defer { try? FileManager.default.removeItem(atPath: versions.root) }
        #expect(EmbeddedBinaryValidationCommand.validate([versions.bundle, "-info-plist-path", versions.infoPlist])
            == (0, "warning: The CFBundleVersion of an app extension (null) must match that of its containing parent app ('1').\n"))
        #expect(EmbeddedBinaryValidationCommand.validate([versions.bundle, "-signing-cert", "-", "-info-plist-path", versions.infoPlist]) == (1, """
            error: Embedded binary is not signed with the same certificate as the parent app. Verify the embedded binary target's code sign settings match the parent app's.

            \t\tEmbedded Binary Signing Certificate:\tNot Code Signed
            \t\tParent App Signing Certificate:\t\t- (Ad Hoc Code Signed)



            """))
        #expect(EmbeddedBinaryValidationCommand.validate([]) == (1, "error: must provide a path to an embedded binary\n"))
        #expect(EmbeddedBinaryValidationCommand.validate([versions.bundle, versions.bundle]) == (1, "error: multiple input paths specified\n"))
    }
}
