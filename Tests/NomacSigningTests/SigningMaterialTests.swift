import Crypto
import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacSigning

/// The key, the certificate signing request and the identity file a machine with no keychain needs
/// (docs/INSTALL-ON-IPHONE.md), on the self-made test identity.
@Suite struct SigningMaterialTests {
    static let blocks = PEM.blocks(in: TestIdentities.appleShaped)
    static let key = blocks.first { $0.label == "PRIVATE KEY" }!.text
    static let certificates = blocks.filter { $0.label == "CERTIFICATE" }.map(\.der)
    static let roots: Set<String> = [try! X509Certificate(der: certificates.last!, path: "root").sha1Hex]
    static let now = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!

    /// `openssl req -new -key <the test key> -subj "/CN=nomac development/C=US"` of OpenSSL 3.0.13
    /// and 3.6.5 (`first_run_experiments.py` `csr`): 920 bytes.
    @Test func requestIsOpenSSLsForTheSameKey() throws {
        let request = try CertificateRequest.pem(commonName: "nomac development", privateKey: Self.key, path: "test")
        #expect(request.utf8.count == 920)
        #expect(SHA256.hash(data: Array(request.utf8)).map { String(format: "%02x", $0) }.joined()
            == "89a9b2b02538aa6a966f5010484f2c16fe57241c7eaf1c9a489870c2a3b26017")
    }

    @Test func newKeyIsAnRSA2048KeyInPKCS8() throws {
        let key = try CertificateRequest.newPrivateKey()
        #expect(key.hasPrefix("-----BEGIN PRIVATE KEY-----\n"))
        #expect(try PEM.rsaPrivateKey(in: key, path: "test").keySizeInBits == 2048)
    }

    @Test func aFileWithoutAKeyIsSaid() {
        #expect(throws: NomacError("no RSA private key in the file", path: "test")) {
            try CertificateRequest.pem(commonName: "x", privateKey: "not a key", path: "test")
        }
    }

    @Test func certificateFromDERAndFromPEM() throws {
        let leaf = Self.certificates[0]
        #expect(try IdentityFile.certificate(leaf, path: "a.cer") == leaf)
        #expect(try IdentityFile.certificate(Array(PEM.text(label: "CERTIFICATE", der: leaf).utf8), path: "a.pem") == leaf)
        #expect(throws: NomacError("malformed certificate", path: "b.cer")) { try IdentityFile.certificate(Array("nonsense".utf8), path: "b.cer") }
    }

    /// The key, then the leaf, the intermediate and the root: a file `--keychain` reads.
    @Test func identityFileHoldsTheKeyAndTheChainInOrder() throws {
        let (text, identity) = try IdentityFile.make(certificate: Self.certificates[0], chain: Array(Self.certificates[1...]), privateKey: Self.key,
                                                     keyPath: "k", certificatePath: "c", at: Self.now, roots: Self.roots)
        #expect(PEM.blocks(in: text).map(\.label) == ["PRIVATE KEY", "CERTIFICATE", "CERTIFICATE", "CERTIFICATE"])
        #expect(PEM.blocks(in: text).filter { $0.label == "CERTIFICATE" }.map(\.der) == Self.certificates)
        #expect(identity.commonName == "Apple Development: nomac Test (ABCDE12345)")
        #expect(identity.teamIdentifier == "ABCDE12345")
        #expect(try SigningIdentity(named: "Apple Development", pem: text, path: "identity.pem").commonName == identity.commonName)
    }

    @Test func anotherKeyIsRefusedWithWhatToDo() throws {
        let other = try CertificateRequest.newPrivateKey()
        do {
            _ = try IdentityFile.make(certificate: Self.certificates[0], chain: Array(Self.certificates[1...]), privateKey: other,
                                      keyPath: "k", certificatePath: "c", at: Self.now, roots: Self.roots)
            Issue.record("another key was taken")
        } catch let error as NomacError {
            #expect(error.message == "this is not the key of the certificate")
            #expect(error.notes.contains { $0.contains("nomac signing request") })
        }
    }

    @Test func anExpiredCertificateIsRefused() {
        let later = ISO8601DateFormatter().date(from: "2040-01-01T00:00:00Z")!
        #expect(throws: NomacError.self) {
            try IdentityFile.make(certificate: Self.certificates[0], chain: Array(Self.certificates[1...]), privateKey: Self.key,
                                  keyPath: "k", certificatePath: "c", at: later, roots: Self.roots)
        }
    }

    @Test func aChainNotEndingAtApplesRootIsRefused() throws {
        do {
            _ = try IdentityFile.make(certificate: Self.certificates[0], chain: Array(Self.certificates[1...]), privateKey: Self.key,
                                      keyPath: "k", certificatePath: "c", at: Self.now)
            Issue.record("the self-made root was taken")
        } catch let error as NomacError {
            #expect(error.message == "the certificate's chain does not end at Apple Root CA")
        }
    }

    @Test func aMissingIntermediateIsRefused() {
        #expect(throws: NomacError.self) {
            try IdentityFile.make(certificate: Self.certificates[0], chain: [], privateKey: Self.key, keyPath: "k", certificatePath: "c", at: Self.now, roots: Self.roots)
        }
    }

    /// A certificate with the given issuer, the rest of it empty: what `authorities(above:)` reads.
    static func issued(by attributes: [(oid: [UInt8], value: String)]) -> [UInt8] {
        let issuer = X509Builder.name(attributes.map { ($0.oid, DER.element(0x0c, Array($0.value.utf8))) })
        let body = DER.element(0xa0, DER.element(0x02, [2])) + DER.element(0x02, [1]) + X509Builder.sha256WithRSA + issuer + DER.element(0x30, []) + DER.element(0x30, []) + DER.element(0x30, [])
        return DER.element(0x30, DER.element(0x30, body))
    }

    static let commonName: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]
    static let unit: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x0b]

    /// Observed: the owner's Apple Development certificate names this issuer, its Authority
    /// Information Access gives the same bytes as the page's AppleWWDRCAG3.cer.
    @Test func applesG3CertificatesNeedG3AndTheRoot() throws {
        let leaf = Self.issued(by: [(Self.commonName, "Apple Worldwide Developer Relations Certification Authority"), (Self.unit, "G3")])
        #expect(try IdentityFile.authorities(above: leaf, path: "c") == [IdentityFile.developerRelationsG3, IdentityFile.appleRoot])
    }

    @Test func anotherIssuerStopsWithTheChainOption() throws {
        let leaf = Self.issued(by: [(Self.commonName, "Apple Worldwide Developer Relations Certification Authority"), (Self.unit, "G6")])
        do {
            _ = try IdentityFile.authorities(above: leaf, path: "c")
            Issue.record("G6 was taken")
        } catch let error as NomacError {
            #expect(error.message.contains("G6"))
            #expect(error.notes.first?.contains("--chain") == true)
        }
    }

    @Test func aDownloadMustBeWhatApplePublished() throws {
        let bytes: [UInt8] = [1, 2, 3]
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let authority = IdentityFile.Authority(name: "test", url: "https://example.org/test.cer", sha256: digest)
        #expect(try IdentityFile.verified(bytes, as: authority) == bytes)
        #expect(throws: NomacError.self) { try IdentityFile.verified([4], as: authority) }
    }

    /// The addresses of apple.com/certificateauthority on 2026-11-06 (AppleRootCA.cer, which this
    /// page's route once named, is 404) and the root nomac already trusts profiles from.
    @Test func applesAuthoritiesAreThePublishedOnes() throws {
        #expect(IdentityFile.appleRoot.url == "https://www.apple.com/appleca/AppleIncRootCertificate.cer")
        #expect(IdentityFile.developerRelationsG3.url == "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer")
        let root = try #require(ProvisioningProfile.appleRoots.first)
        #expect(root.map { String(format: "%02x", $0) }.joined() == IdentityFile.appleRoot.sha256)
    }
}
