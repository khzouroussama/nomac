import Foundation
import NomacCore
import NomacTestSupport
import struct SWBUtil.CodeSignatureInfo
import Testing
@testable import NomacSigning

/// What Swift Build's `CodeSignatureInfo` records of a signed xcframework, the same on macOS, where
/// `SecCode` reads the signature, and elsewhere, where Swift Build reads its bytes
/// (docs/formats/code-signature.md "Signature records"). The digests are of the records xcodebuild
/// wrote for these bytes (`signature_record_experiments.py`, `fixture-unsigned`, `fixture-adhoc`).
@Suite struct SignatureRecordTests {
    static let metadata = ["library": "libVendor.a", "platform": "ios"]

    static let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>AvailableLibraries</key>
        \t<array>
        \t\t<dict>
        \t\t\t<key>HeadersPath</key>
        \t\t\t<string>Headers</string>
        \t\t\t<key>LibraryIdentifier</key>
        \t\t\t<string>ios-arm64</string>
        \t\t\t<key>LibraryPath</key>
        \t\t\t<string>libVendor.a</string>
        \t\t\t<key>SupportedArchitectures</key>
        \t\t\t<array>
        \t\t\t\t<string>arm64</string>
        \t\t\t</array>
        \t\t\t<key>SupportedPlatform</key>
        \t\t\t<string>ios</string>
        \t\t</dict>
        \t</array>
        \t<key>CFBundlePackageType</key>
        \t<string>XFWK</string>
        \t<key>XCFrameworkFormatVersion</key>
        \t<string>1.0</string>
        </dict>
        </plist>

        """

    static func xcframework(in directory: String, info: String = info) throws -> String {
        let path = directory + "/Vendor.xcframework"
        try FileSystem.write(Data(info.utf8), to: path + "/Info.plist")
        try FileSystem.write(Data("!<arch>\n".utf8), to: path + "/ios-arm64/libVendor.a")
        try FileSystem.write(Data("int vendor(void);\n".utf8), to: path + "/ios-arm64/Headers/Vendor.h")
        return path
    }

    static func recordDigest(_ record: CodeSignatureInfo) throws -> String {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return hex(CodeSignature.sha256([UInt8](try encoder.encode(record))))
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The xcframework signed as `identity` from `pem`, with no team unless its chain counts as
    /// Apple's. It has a `CFBundleIdentifier`, as nomac does not sign a bundle without one with a
    /// certificate (B-303).
    static func signed(pem: String, identity name: String, apple: Bool = false, in directory: String) throws -> (path: String, chain: [X509Certificate]) {
        let identified = info.replacingOccurrences(of: "\t<key>CFBundlePackageType</key>", with: "\t<key>CFBundleIdentifier</key>\n\t<string>org.nomac.vendor</string>\n\t<key>CFBundlePackageType</key>")
        let path = try xcframework(in: directory, info: identified)
        let shaped = try SigningIdentity(named: name, pem: pem, path: directory + "/identity.pem")
        let identity = SigningIdentity(chain: shaped.chain, appleRoots: apple ? [shaped.chain.last!.sha1Hex] : [], sign: shaped.sign)
        _ = try CodeSigner.sign(CodeSigner.Request(path: path, identity: "-", force: true), identity: identity)
        return (path, identity.chain)
    }

    @Test func recordsAnUnsignedXCFramework() async throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-signature-record")
        let record = try await CodeSignatureInfo.load(from: try Self.xcframework(in: temporary.path), additionalInfo: Self.metadata)
        #expect(!record.isSigned)
        #expect(record.identifier == nil && record.source == nil && record.cdHashes == nil && record.certificates == nil)
        #expect(record.signatureType == nil && record.signatureIdentifier == nil)
        #expect(try Self.recordDigest(record) == "c8c52cdfa316a7c07eebdebb17faf1e01dd5e547ea17979f463be2aa8f343204")
    }

    @Test func recordsAnAdHocXCFramework() async throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-signature-record")
        let path = try Self.xcframework(in: temporary.path)
        _ = try CodeSigner.sign(CodeSigner.Request(path: path, identity: "-"))
        let record = try await CodeSignatureInfo.load(from: path, additionalInfo: Self.metadata)
        #expect(record.isSigned)
        #expect(record.identifier == "Vendor-cc0d157269cf9a74f69248a93778c68ca15c77e7")
        #expect(record.source == "embedded")
        #expect(record.cdHashes?.map(Self.hex) == ["3c95200b80986f01e2bfbfa26865a54784660ad8"])
        #expect(record.certificates == nil && record.signatureType == nil && record.signatureIdentifier == nil)
        #expect(record.timestamp == nil && !record.isSecureTimestamp && record.mainExecutable == nil && record.runtimeVersion == nil)
        #expect(try Self.recordDigest(record) == "0b6cececce166ba84c008b1ca0f3af1b42d37f02bc9e3ec0d789c666a8353006")
    }

    /// A self-signed certificate has no team: the record names the certificate's SHA-256.
    @Test func recordsASelfSignedXCFramework() async throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-signature-record")
        let (path, chain) = try Self.signed(pem: CertificateSigningTests.selfSigned, identity: "nomac Test Signing", in: temporary.path)
        let record = try await CodeSignatureInfo.load(from: path, additionalInfo: nil, skipValidation: true)
        #expect(record.isSigned)
        #expect(record.identifier == "org.nomac.vendor")
        #expect(record.certificates == chain.map { Data($0.der) })
        #expect(record.signatureType == .selfSigned)
        #expect(record.signatureIdentifier == Self.hex(CodeSignature.sha256(chain[0].der)).uppercased())
        #expect(record.timestamp == nil && !record.isSecureTimestamp)
    }

    /// The code directory's team names the signer; the certificates go from the signer to the
    /// root, though the signature holds them shortest first.
    @Test func recordsATeamAndTheChainFromTheSignerToTheRoot() async throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-signature-record")
        let (path, chain) = try Self.signed(pem: TestIdentities.appleShaped, identity: "Apple Development: nomac Test (ABCDE12345)", apple: true, in: temporary.path)
        #expect(chain.count == 3)
        let record = try await CodeSignatureInfo.load(from: path, additionalInfo: nil, skipValidation: true)
        #expect(record.certificates == chain.map { Data($0.der) })
        #expect(record.signatureType == .appleDeveloperProgram)
        #expect(record.signatureIdentifier == "ABCDE12345")
    }

    /// `CodeDirectory` is what makes a bundle signed: without it, the rest of `_CodeSignature` does
    /// not count (`direct-partial`); cut short, the signature cannot be read (`direct-corrupt`).
    @Test func readsOnlyACompleteCodeDirectory() async throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-signature-record")
        let path = try Self.xcframework(in: temporary.path)
        _ = try CodeSigner.sign(CodeSigner.Request(path: path, identity: "-"))
        let directory = path + "/_CodeSignature/CodeDirectory"
        let bytes = try Data(contentsOf: URL(fileURLWithPath: directory))
        try FileSystem.write(bytes.prefix(20), to: directory)
        await #expect(throws: (any Error).self) {
            try await CodeSignatureInfo.load(from: path, additionalInfo: nil)
        }
        try FileManager.default.removeItem(atPath: directory)
        #expect(try await !CodeSignatureInfo.load(from: path, additionalInfo: nil).isSigned)
    }
}
