import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacSigning

/// Reading how an executable is signed: not at all, ad hoc, or with a certificate.
@Suite struct BundleSignatureTests {
    @Test func readsTheSigningCertificate() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-bundle-signature")
        let directory = URL(fileURLWithPath: temporary.path)
        let keychain = directory.appendingPathComponent("identity.pem")
        try Data(CertificateSigningTests.issued.utf8).write(to: keychain)
        let identity = try SigningIdentity(named: "006FADAE347D2076C887CF85333A2A1D4BECFF26", pem: CertificateSigningTests.issued, path: keychain.path)
        var paths: [String] = []
        for (name, arguments) in [("unsigned", nil), ("adhoc", ["--sign", "-"]),
                                  ("certificate", ["--sign", identity.certificateSHA1, "--keychain", keychain.path, "--timestamp=none"])] {
            let url = try CodeSignerTests.file(SyntheticMachO.machO(seed: 7), named: name)(directory)
            if let arguments {
                for request in try CodesignArguments.parse(arguments + [url.path]) { _ = try CodeSigner.sign(request) }
            }
            paths.append(url.path)
        }

        #expect(try BundleSignature.of(executable: paths[0]) == .unsigned)
        #expect(try BundleSignature.of(executable: paths[1]) == .adHoc)
        #expect(try BundleSignature.of(executable: paths[2]) == .certificate(sha1: identity.certificateSHA1, commonName: identity.commonName))
        #expect(try BundleSignature.of(executable: directory.appendingPathComponent("missing").path) == .unsigned)
    }
}
