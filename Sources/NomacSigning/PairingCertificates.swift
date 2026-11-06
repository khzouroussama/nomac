import _CryptoExtras
import Crypto
import Foundation
import NomacCore

/// The certificates of a pairing between a host and a device, in PEM: a self-signed root, the
/// host's certificate and the device's, each with an empty name, valid ten years, signed by the
/// root with SHA-256. The fields are what libimobiledevice's `userpref.c` and pymobiledevice3's
/// `ca.py` write (docs/formats/lockdown.md "Pairing"); where they differ this follows
/// pymobiledevice3: serial number 1, and valid from a minute ago, for a device clock behind the host's.
public struct PairingCertificates {
    public let rootCertificate: [UInt8]
    public let rootPrivateKey: [UInt8]
    public let hostCertificate: [UInt8]
    public let hostPrivateKey: [UInt8]
    public let deviceCertificate: [UInt8]

    /// A new chain for the device whose public key is `devicePublicKey` (the PEM lockdownd's
    /// `DevicePublicKey` value holds), with keys of its own.
    public init(devicePublicKey: [UInt8], at date: Date) throws {
        let root = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let host = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        func issue(_ subjectKey: [UInt8], _ extensions: [[UInt8]]) throws -> [UInt8] {
            let body = DER.element(0xa0, DER.element(0x02, [2])) + DER.element(0x02, [1]) + X509Builder.sha256WithRSA + Self.emptyName
                + DER.element(0x30, Self.time(date.addingTimeInterval(-60)) + Self.time(date.addingTimeInterval(Self.validity))) + Self.emptyName + subjectKey
                + DER.element(0xa3, DER.element(0x30, extensions.flatMap { $0 }))
            return Array(PEM.text(label: "CERTIFICATE", der: try X509Builder.signed(DER.element(0x30, body), by: root)).utf8)
        }
        let deviceKey = try Self.subjectPublicKeyInfo(devicePublicKey)
        rootCertificate = try issue([UInt8](root.publicKey.derRepresentation), [Self.extensionField(Self.basicConstraints, critical: true, DER.element(0x30, DER.element(0x01, [0xff])))])
        hostCertificate = try issue([UInt8](host.publicKey.derRepresentation), [Self.notAuthority, Self.keyUsage])
        deviceCertificate = try issue(deviceKey, [Self.notAuthority, Self.extensionField(Self.subjectKeyIdentifier, critical: false, DER.element(0x04, Self.keyIdentifier(deviceKey))), Self.keyUsage])
        rootPrivateKey = Array(root.pkcs8PEMRepresentation.utf8)
        hostPrivateKey = Array(host.pkcs8PEMRepresentation.utf8)
    }

    static let validity: TimeInterval = 60 * 60 * 24 * 365 * 10
    private static let start2050: TimeInterval = 2_524_608_000
    private static let emptyName: [UInt8] = [0x30, 0x00]
    private static let basicConstraints: [UInt8] = [0x06, 0x03, 0x55, 0x1d, 0x13]
    private static let keyUsageOID: [UInt8] = [0x06, 0x03, 0x55, 0x1d, 0x0f]
    private static let subjectKeyIdentifier: [UInt8] = [0x06, 0x03, 0x55, 0x1d, 0x0e]
    private static let rsaEncryption = DER.element(0x30, [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
    private static let notAuthority = extensionField(basicConstraints, critical: true, [0x30, 0x00])
    /// digitalSignature and keyEncipherment.
    private static let keyUsage = extensionField(keyUsageOID, critical: true, [0x03, 0x02, 0x05, 0xa0])

    private static func extensionField(_ oid: [UInt8], critical: Bool, _ value: [UInt8]) -> [UInt8] {
        DER.element(0x30, oid + (critical ? [0x01, 0x01, 0xff] : []) + DER.element(0x04, value))
    }

    /// A `UTCTime` through 2049, then a `GeneralizedTime` (RFC 5280).
    private static func time(_ date: Date) -> [UInt8] {
        let text = CMSSignature.utcTime(date)
        return date.timeIntervalSince1970 < start2050 ? DER.element(0x17, Array(text.utf8)) : DER.element(0x18, Array("20\(text)".utf8))
    }

    /// The SHA-1 of the key's bits, RFC 5280's first method and OpenSSL's `hash`.
    private static func keyIdentifier(_ subjectPublicKeyInfo: [UInt8]) -> [UInt8] {
        guard let info = DERReader.elements(subjectPublicKeyInfo).first, let bits = DERReader.elements(info.content).last, bits.tag == 0x03 else { return [] }
        return CodeSignature.sha1(Array(bits.content.dropFirst()))
    }

    /// A public key in PEM as a `SubjectPublicKeyInfo`: libimobiledevice and pymobiledevice3 read
    /// the device's as either `RSA PUBLIC KEY` (PKCS #1) or `PUBLIC KEY`.
    static func subjectPublicKeyInfo(_ pem: [UInt8]) throws -> [UInt8] {
        let blocks = PEM.blocks(in: String(decoding: pem, as: UTF8.self))
        if let block = blocks.first(where: { $0.label == "PUBLIC KEY" }) { return block.der }
        guard let block = blocks.first(where: { $0.label == "RSA PUBLIC KEY" }) else {
            throw NomacError("the device's public key is neither an RSA PUBLIC KEY nor a PUBLIC KEY in PEM")
        }
        return DER.element(0x30, rsaEncryption + DER.element(0x03, [0] + block.der))
    }
}
