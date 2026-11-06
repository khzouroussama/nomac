import Crypto
import Foundation
import NomacCore

/// The identity file `--keychain` reads, made from the certificate developer.apple.com issues for
/// a certificate signing request and that request's key: the key, the certificate, the
/// intermediate and the root, the order of the identity that installed on an iPhone
/// (docs/INSTALL-ON-IPHONE.md).
public enum IdentityFile {
    /// One of Apple's certificate authorities at its public address, with the SHA-256 of its
    /// certificate as published on 2026-11-06, so a download is checked rather than trusted.
    public struct Authority: Equatable, Sendable {
        public let name: String
        public let url: String
        public let sha256: String
    }

    public static let appleRoot = Authority(
        name: "Apple Root CA", url: "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
        sha256: "b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024")

    public static let developerRelationsG3 = Authority(
        name: "Apple Worldwide Developer Relations Certification Authority (G3)", url: "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer",
        sha256: "dcf21878c77f4198e4b4614f03d696d89c66c66008d4244e1b99161aac91601f")

    /// A certificate as Apple's download gives it (DER), or in PEM.
    public static func certificate(_ bytes: [UInt8], path: String) throws -> [UInt8] {
        if let block = PEM.blocks(in: String(decoding: bytes, as: UTF8.self)).first(where: { $0.label == "CERTIFICATE" }) { return block.der }
        _ = try X509Certificate(der: bytes, path: path)
        return bytes
    }

    /// The authorities above an Apple-issued certificate, in chain order. Only G3 is observed
    /// issuing Apple Development certificates; another issuer stops here.
    public static func authorities(above certificate: [UInt8], path: String) throws -> [Authority] {
        let leaf = try X509Certificate(der: certificate, path: path)
        guard leaf.issuerCommonName == "Apple Worldwide Developer Relations Certification Authority", leaf.issuerOrganizationalUnit == "G3" else {
            throw NomacError("the certificate's issuer is \"\(leaf.issuerCommonName ?? "unknown")\" (\(leaf.issuerOrganizationalUnit ?? "no unit")), which nomac has not seen", path: path, notes: [
                "pass its issuer and root with --chain, from https://www.apple.com/certificateauthority/",
            ])
        }
        return [developerRelationsG3, appleRoot]
    }

    /// `bytes` as the certificate of `authority`, or an error when they are not what Apple published.
    public static func verified(_ bytes: [UInt8], as authority: Authority) throws -> [UInt8] {
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard digest == authority.sha256 else {
            throw NomacError("the certificate downloaded for \(authority.name) is not the one Apple published (SHA-256 \(digest))", notes: [
                "download it from \(authority.url) yourself and pass it with --chain",
            ])
        }
        return bytes
    }

    /// The identity file's text and the identity it holds, checked as a signing identity: the key
    /// is the certificate's, the certificate is in force, and the chain ends at a root of `roots`.
    public static func make(certificate: [UInt8], chain: [[UInt8]], privateKey: String, keyPath: String, certificatePath: String,
                            at date: Date, roots: Set<String> = SigningIdentity.appleRootFingerprints) throws -> (text: String, identity: SigningIdentity) {
        let leaf = try X509Certificate(der: certificate, path: certificatePath)
        let key = try PEM.rsaPrivateKey(in: privateKey, path: keyPath)
        guard [UInt8](key.publicKey.derRepresentation) == leaf.subjectPublicKeyInfo else {
            throw NomacError("this is not the key of the certificate", path: keyPath, notes: [
                "the certificate \"\(leaf.commonName ?? certificatePath)\" came from a certificate signing request made with another key",
                "use that request's key, or make a new request with 'nomac signing request' and a new certificate from it",
            ])
        }
        if let expiration = leaf.notAfter, expiration <= date {
            throw NomacError("the certificate expired on \(ISO8601DateFormatter().string(from: expiration))", path: certificatePath, notes: ["make a new one from the same request at developer.apple.com"])
        }
        let text = privateKey + ([certificate] + chain).map { PEM.text(label: "CERTIFICATE", der: $0) }.joined()
        let identity = try SigningIdentity(named: leaf.sha1Hex, pem: text, path: certificatePath, appleRoots: roots)
        guard identity.isApple else {
            throw NomacError("the certificate's chain does not end at Apple Root CA", path: certificatePath, notes: ["a device accepts only Apple's chain; pass Apple's certificates with --chain"])
        }
        return (text, identity)
    }
}
