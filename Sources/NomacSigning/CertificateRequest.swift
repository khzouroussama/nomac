import _CryptoExtras
import Crypto
import Foundation
import NomacCore

/// A private key and the certificate signing request developer.apple.com's Certificates page
/// takes: for a given key, the bytes of `openssl req -new -key <key> -subj "/CN=<name>/C=<country>"`
/// (`first_run_experiments.py` `csr`, OpenSSL 3.0 and 3.6 alike), the form the page accepted for
/// an Apple Development certificate (docs/state/device.md).
public enum CertificateRequest {
    /// A new RSA 2048 key in PKCS #8 PEM, what OpenSSL 3's `genrsa 2048` writes.
    public static func newPrivateKey() throws -> String {
        try _RSA.Signing.PrivateKey(keySize: .bits2048).pkcs8PEMRepresentation
    }

    /// The request in PEM, for the key in `privateKey`.
    public static func pem(commonName: String, country: String = "US", privateKey: String, path: String) throws -> String {
        let key = try PEM.rsaPrivateKey(in: privateKey, path: path)
        let subject = X509Builder.name([(commonNameOID, DER.element(0x0c, Array(commonName.utf8))), (countryOID, DER.element(0x13, Array(country.utf8)))])
        let information = DER.element(0x30, DER.element(0x02, [0]) + subject + [UInt8](key.publicKey.derRepresentation) + DER.element(0xa0, []))
        return PEM.text(label: "CERTIFICATE REQUEST", der: try X509Builder.signed(information, by: key))
    }

    private static let commonNameOID: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]
    private static let countryOID: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x06]
}

/// The parts of certificates and certificate requests nomac writes.
enum X509Builder {
    static let sha256WithRSA = DER.element(0x30, CMSSignature.sha256WithRSA + [0x05, 0x00])

    /// A distinguished name: one attribute in each relative name, in order.
    static func name(_ attributes: [(oid: [UInt8], value: [UInt8])]) -> [UInt8] {
        DER.element(0x30, attributes.flatMap { DER.element(0x31, DER.element(0x30, $0.oid + $0.value)) })
    }

    /// `content` with its algorithm and the RSA PKCS #1 v1.5 SHA-256 signature by `key`.
    static func signed(_ content: [UInt8], by key: _RSA.Signing.PrivateKey) throws -> [UInt8] {
        let signature = try key.signature(for: SHA256.hash(data: content), padding: .insecurePKCS1v1_5)
        return DER.element(0x30, content + sha256WithRSA + DER.element(0x03, [0] + [UInt8](signature.rawRepresentation)))
    }
}

extension PEM {
    /// The RSA private key in `text`, PKCS #1 or PKCS #8.
    static func rsaPrivateKey(in text: String, path: String) throws -> _RSA.Signing.PrivateKey {
        guard let block = blocks(in: text).first(where: { $0.label == "PRIVATE KEY" || $0.label == "RSA PRIVATE KEY" }) else {
            throw NomacError("no RSA private key in the file", path: path)
        }
        do {
            return try _RSA.Signing.PrivateKey(pemRepresentation: block.text)
        } catch {
            throw NomacError("unreadable RSA private key: \(error)", path: path)
        }
    }

    /// `der` in PEM, 64 columns as OpenSSL writes it.
    static func text(label: String, der: [UInt8]) -> String {
        let base64 = Array(Data(der).base64EncodedString().utf8)
        let lines = stride(from: 0, to: base64.count, by: 64).map { String(decoding: base64[$0..<min($0 + 64, base64.count)], as: UTF8.self) }
        return (["-----BEGIN \(label)-----"] + lines + ["-----END \(label)-----"]).joined(separator: "\n") + "\n"
    }
}
