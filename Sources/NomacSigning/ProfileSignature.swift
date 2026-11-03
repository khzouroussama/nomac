import _CryptoExtras
import Crypto
import Foundation

/// Whether a provisioning profile's CMS signature comes from a trusted root (docs/formats/ipa.md
/// "Which installed profiles xcodebuild uses"): xcodebuild ignores a profile whose content was
/// changed after signing, one signed by a self-signed certificate and one signed by a self-made
/// chain bearing the names of Apple's (`distribution_experiments.py` `apple-profile`). Apple signs
/// with "Apple iPhone OS Provisioning Profile Signing", issued by "Apple iPhone Certification
/// Authority", issued by Apple Root CA, all three in the profile (RSA, SHA-1 digests).
enum ProfileSignature {
    static let sha1: [UInt8] = [0x2b, 0x0e, 0x03, 0x02, 0x1a]
    static let sha256: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
    static let sha1WithRSA: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x05]
    static let sha256WithRSA: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b]
    static let messageDigest: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x04]

    /// Whether `signedData` (the SignedData's contents) signs `content` with a valid signature by a
    /// certificate whose chain among the SignedData's certificates ends at a root whose SHA-256 is
    /// in `roots`. Validity dates are not checked: no expired chain has been observed.
    static func isTrusted(signedData: [UInt8], content: [UInt8], roots: Set<[UInt8]>) -> Bool {
        let fields = DERReader.elements(signedData)
        guard let certificateSet = fields.first(where: { $0.tag == 0xa0 }), let signerInfos = fields.last, signerInfos.tag == 0x31 else {
            return false
        }
        let certificates = DERReader.elements(certificateSet.content).compactMap { try? X509Certificate(der: $0.encoded, path: "") }
        return DERReader.elements(signerInfos.content).contains { signerInfo in
            guard let signer = signerCertificate(signerInfo.content, certificates: certificates),
                  signs(signerInfo.content, content: content, key: signer.subjectPublicKeyInfo) else { return false }
            return chains(signer, certificates: certificates, to: roots)
        }
    }

    /// The certificate a SignerInfo names by issuer and serial number.
    static func signerCertificate(_ signerInfo: [UInt8], certificates: [X509Certificate]) -> X509Certificate? {
        let fields = DERReader.elements(signerInfo)
        guard fields.count >= 2, fields[1].tag == 0x30 else { return nil }
        let identifier = DERReader.elements(fields[1].content)
        guard identifier.count == 2 else { return nil }
        return certificates.first { $0.issuer == identifier[0].encoded && $0.serialNumber == identifier[1].encoded }
    }

    /// A SignerInfo (version, signer, digest algorithm, signed attributes, signature algorithm,
    /// signature): the attributes' `messageDigest` is the content's digest, and the signature is
    /// the key's over the attributes as a SET.
    static func signs(_ signerInfo: [UInt8], content: [UInt8], key: [UInt8]) -> Bool {
        let fields = DERReader.elements(signerInfo)
        guard fields.count >= 6, let digestAlgorithm = DERReader.elements(fields[2].content).first?.content,
              fields[3].tag == 0xa0, fields[5].tag == 0x04 else { return false }
        let signature = fields[5]
        let attributes = DERReader.elements(fields[3].content)
        guard let digest = attributes.first(where: { DERReader.elements($0.content).first?.content == messageDigest })
            .flatMap({ DERReader.elements($0.content).last }).flatMap({ DERReader.elements($0.content).first?.content }),
              digest == hash(content, digestAlgorithm) else { return false }
        return verifies(signature.content, of: [0x31] + fields[3].encoded.dropFirst(), digestAlgorithm: digestAlgorithm, key: key)
    }

    /// From `certificate` up through issuers whose keys verify each signature, to a root of `roots`.
    static func chains(_ certificate: X509Certificate, certificates: [X509Certificate], to roots: Set<[UInt8]>) -> Bool {
        var current = certificate
        for _ in 0...certificates.count {
            if roots.contains(Array(SHA256.hash(data: current.der))) { return true }
            let parts = DERReader.elements(DERReader.elements(current.der).first?.content ?? [])
            guard parts.count == 3, parts[2].tag == 0x03, !parts[2].content.isEmpty,
                  let algorithm = DERReader.elements(parts[1].content).first?.content else { return false }
            let digestAlgorithm = algorithm == sha1WithRSA ? sha1 : algorithm == sha256WithRSA ? sha256 : []
            let signature = Array(parts[2].content.dropFirst())
            guard let issuer = certificates.first(where: {
                $0.subject == current.issuer && verifies(signature, of: parts[0].encoded, digestAlgorithm: digestAlgorithm, key: $0.subjectPublicKeyInfo)
            }) else { return false }
            current = issuer
        }
        return false
    }

    static func hash(_ data: [UInt8], _ algorithm: [UInt8]) -> [UInt8]? {
        switch algorithm {
        case sha1: Array(Insecure.SHA1.hash(data: data))
        case sha256: Array(SHA256.hash(data: data))
        default: nil
        }
    }

    /// An RSA PKCS #1 v1.5 signature of `data` by the key of a SubjectPublicKeyInfo.
    static func verifies(_ signature: [UInt8], of data: [UInt8], digestAlgorithm: [UInt8], key: [UInt8]) -> Bool {
        guard let publicKey = try? _RSA.Signing.PublicKey(derRepresentation: key) else { return false }
        let rsaSignature = _RSA.Signing.RSASignature(rawRepresentation: signature)
        switch digestAlgorithm {
        case sha1: return publicKey.isValidSignature(rsaSignature, for: Insecure.SHA1.hash(data: data), padding: .insecurePKCS1v1_5)
        case sha256: return publicKey.isValidSignature(rsaSignature, for: SHA256.hash(data: data), padding: .insecurePKCS1v1_5)
        default: return false
        }
    }
}
