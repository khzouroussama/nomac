import _CryptoExtras
import Crypto
import Foundation
import NomacCore

/// A signing identity: a certificate chain and the RSA signing of its leaf's private key, read
/// from a PEM file that holds the key and the certificates (nomac's stand-in for a keychain,
/// `--keychain`).
public struct SigningIdentity {
    let leaf: X509Certificate
    /// The leaf, its issuers and the self-signed root, in that order.
    let chain: [X509Certificate]
    /// RSA PKCS #1 v1.5 with SHA-256 of the given bytes, by the leaf's key.
    let sign: ([UInt8]) throws -> [UInt8]
    /// The SHA-1 fingerprints of the roots taken as Apple's.
    let appleRoots: Set<String>

    init(chain: [X509Certificate], appleRoots: Set<String> = Self.appleRootFingerprints, sign: @escaping ([UInt8]) throws -> [UInt8]) {
        leaf = chain[0]
        self.chain = chain
        self.appleRoots = appleRoots
        self.sign = sign
    }

    /// The identity in `pem` that `name` designates, as codesign finds one in a keychain
    /// (observed with self-made identities, `CertificateSigningTests`): the certificate whose
    /// SHA-1 is `name` (hex, whole, any case), else the one whose common name is `name`, else the
    /// only one whose common name contains it, both ignoring case; when several contain it,
    /// codesign names the second and the first in keychain order (here, the file's order).
    ///
    /// codesign signs with the chain up to a self-signed root and fails without one
    /// (`kCMSCertificateChainWithRootOrFail` in Security's `signer.cpp`; observed: "unable to build
    /// chain to self-signed root for signer …", errSecInternalComponent).
    public init(named name: String, pem: String, path: String) throws {
        let blocks = PEM.blocks(in: pem)
        let certificates = try blocks.filter { $0.label == "CERTIFICATE" }.map { try X509Certificate(der: $0.der, path: path) }
        guard let keyBlock = blocks.first(where: { $0.label == "PRIVATE KEY" || $0.label == "RSA PRIVATE KEY" }) else {
            throw NomacError("no RSA private key in the identity file", path: path)
        }
        let key: _RSA.Signing.PrivateKey
        do {
            key = try _RSA.Signing.PrivateKey(pemRepresentation: keyBlock.text)
        } catch {
            throw NomacError("unreadable RSA private key: \(error)", path: path)
        }
        let publicKey = [UInt8](key.publicKey.derRepresentation)
        let identities = certificates.filter { $0.subjectPublicKeyInfo == publicKey }
        let leaf: X509Certificate
        if let match = identities.first(where: { $0.sha1Hex.caseInsensitiveCompare(name) == .orderedSame })
            ?? identities.first(where: { $0.commonName?.caseInsensitiveCompare(name) == .orderedSame }) {
            leaf = match
        } else {
            let partial = identities.filter { $0.commonName?.range(of: name, options: .caseInsensitive) != nil }
            guard partial.count < 2 else {
                throw NomacError("ambiguous (matches \"\(partial[1].commonName!)\" and \"\(partial[0].commonName!)\" in \(path))", path: name)
            }
            guard let match = partial.first else { throw NomacError("no identity found", path: name) }
            leaf = match
        }
        var chain = [leaf]
        while chain.last!.issuer != chain.last!.subject {
            guard let issuer = certificates.first(where: { $0.subject == chain.last!.issuer }), !chain.contains(where: { $0.der == issuer.der }) else {
                throw NomacError("unable to build chain to self-signed root for signer \"\(leaf.commonName ?? name)\"", notes: ["errSecInternalComponent"])
            }
            chain.append(issuer)
        }
        self.init(chain: chain) { bytes in
            [UInt8](try key.signature(for: Crypto.SHA256.hash(data: bytes), padding: .insecurePKCS1v1_5).rawRepresentation)
        }
    }

    /// SHA-1 fingerprints of Apple's root certificates: Apple Root CA, the root of the Apple
    /// Development chain observed.
    static let appleRootFingerprints: Set<String> = ["611e5b662c593a08ff58d14ae22452d198df6c60"]

    /// The leaf certificate's SHA-1, upper-case hex, as Xcode names an identity.
    public var certificateSHA1: String { leaf.sha1Hex.uppercased() }

    /// The leaf certificate's common name.
    public var commonName: String { leaf.commonName ?? "" }

    /// The leaf certificate's DER bytes.
    public var certificate: [UInt8] { leaf.der }

    /// When the leaf certificate expires (`notAfter`).
    public var expirationDate: Date? { leaf.notAfter }

    /// Whether the chain ends at an Apple root, as Security's `isAppleCA` decides.
    var isApple: Bool { appleRoots.contains(chain.last!.sha1Hex) }

    /// Apple's marker on the intermediate of iOS development and distribution certificates
    /// (1.2.840.113635.100.6.2.1, `adcSdkMarkerOID` in Security's `drmaker.cpp`), DER contents.
    static let iOSIntermediateMarker: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x02, 0x01]

    /// A leaf, one intermediate with the iOS marker, and the root (`DRMaker::isIOSSignature`).
    var isIOSChain: Bool { chain.count == 3 && chain[1].hasExtension(Self.iOSIntermediateMarker) }
}

/// The fields of an X.509 certificate (RFC 5280) that signing needs, as their DER bytes.
struct X509Certificate {
    let der: [UInt8]
    /// `serialNumber`, `issuer`, `subject` and `subjectPublicKeyInfo`, each a whole TLV.
    let serialNumber: [UInt8]
    let issuer: [UInt8]
    let subject: [UInt8]
    let subjectPublicKeyInfo: [UInt8]
    /// The end of the validity (`UTCTime` or `GeneralizedTime`).
    let notAfter: Date?

    init(der: [UInt8], path: String) throws {
        guard let certificate = DERReader.elements(der).first, certificate.tag == 0x30,
              let tbs = DERReader.elements(certificate.content).first, tbs.tag == 0x30 else {
            throw NomacError("malformed certificate", path: path)
        }
        var fields = DERReader.elements(tbs.content)
        if fields.first?.tag == 0xa0 { fields.removeFirst() }
        guard fields.count >= 6 else { throw NomacError("malformed certificate", path: path) }
        self.der = der
        serialNumber = fields[0].encoded
        issuer = fields[2].encoded
        subject = fields[4].encoded
        subjectPublicKeyInfo = fields[5].encoded
        notAfter = DERReader.elements(fields[3].content).last.flatMap(Self.time)
    }

    /// A `UTCTime` (`YYMMDDhhmmssZ`, years 1950 to 2049) or `GeneralizedTime` (`YYYYMMDDhhmmssZ`).
    static func time(_ element: DERReader.Element) -> Date? {
        var text = String(decoding: element.content, as: UTF8.self)
        if element.tag == 0x17 { text = (Int(text.prefix(2)).map { $0 < 50 ? "20" : "19" } ?? "") + text }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return formatter.date(from: text)
    }

    var sha1Hex: String { CodeSignature.sha1(der).map { String(format: "%02x", $0) }.joined() }

    /// The subject's common name (OID 2.5.4.3).
    var commonName: String? { attribute([0x55, 0x04, 0x03], of: subject) }

    /// The subject's organization (OID 2.5.4.10).
    var organization: String? { attribute([0x55, 0x04, 0x0a], of: subject) }

    /// The subject's organizational unit (OID 2.5.4.11): the team of Apple-issued certificates.
    var organizationalUnit: String? { attribute([0x55, 0x04, 0x0b], of: subject) }

    /// Whether the certificate has an extension of this object identifier (its DER contents).
    func hasExtension(_ oid: [UInt8]) -> Bool {
        guard let certificate = DERReader.elements(der).first, let tbs = DERReader.elements(certificate.content).first,
              let wrapper = DERReader.elements(tbs.content).first(where: { $0.tag == 0xa3 }),
              let extensions = DERReader.elements(wrapper.content).first else { return false }
        return DERReader.elements(extensions.content).contains { DERReader.elements($0.content).first?.content == oid }
    }

    private func attribute(_ oid: [UInt8], of name: [UInt8]) -> String? {
        for relativeName in DERReader.elements(DERReader.elements(name).first?.content ?? []) {
            for pair in DERReader.elements(relativeName.content) {
                let parts = DERReader.elements(pair.content)
                if parts.count == 2, parts[0].tag == 0x06, parts[0].content == oid {
                    return String(decoding: parts[1].content, as: UTF8.self)
                }
            }
        }
        return nil
    }
}

/// Reads definite-length DER elements with single-byte tags, enough for certificates.
enum DERReader {
    struct Element {
        var tag: UInt8
        var content: [UInt8]
        var encoded: [UInt8]
    }

    static func elements(_ bytes: [UInt8]) -> [Element] {
        var result: [Element] = []
        var index = 0
        while index + 2 <= bytes.count {
            let start = index
            let tag = bytes[index]
            var length = Int(bytes[index + 1])
            index += 2
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard count <= 4, index + count <= bytes.count else { return result }
                length = bytes[index..<(index + count)].reduce(0) { $0 << 8 | Int($1) }
                index += count
            }
            guard index + length <= bytes.count else { return result }
            result.append(Element(tag: tag, content: Array(bytes[index..<(index + length)]), encoded: Array(bytes[start..<(index + length)])))
            index += length
        }
        return result
    }
}

/// PEM blocks (RFC 7468).
enum PEM {
    struct Block {
        var label: String
        var der: [UInt8]
        /// The block as written, armor included.
        var text: String
    }

    static func blocks(in text: String) -> [Block] {
        var result: [Block] = []
        var label: String?
        var lines: [String] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("-----BEGIN "), line.hasSuffix("-----") {
                label = String(line.dropFirst(11).dropLast(5))
                lines = [line]
            } else if let current = label, line == "-----END \(current)-----" {
                lines.append(line)
                let body = lines.dropFirst().dropLast().joined()
                if let der = Data(base64Encoded: body) {
                    result.append(Block(label: current, der: [UInt8](der), text: lines.joined(separator: "\n") + "\n"))
                }
                label = nil
            } else if label != nil {
                lines.append(line)
            }
        }
        return result
    }
}
