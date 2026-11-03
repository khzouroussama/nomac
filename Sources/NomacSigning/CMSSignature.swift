import Foundation

/// The signature blob codesign writes when signing with a certificate: a detached CMS
/// SignedData (RFC 5652) over the code directory.
///
/// What Security's `signer.cpp` asks of its CMS encoder (`libsecurity_smime`, Apple's
/// open-source release): SHA-256, detached content, the chain up to the root, signed attributes
/// for the signing time and Apple's two code-signing hash-agility attributes. How that encoder
/// writes it, observed in codesign's output (docs/formats/code-signature.md "Signing with a
/// certificate"): the outer ContentInfo, its `[0]`, the SignedData and the empty encapsulated
/// content in indefinite-length form, everything else in DER; certificates and signed attributes
/// sorted shorter first, then bytewise (`SecCmsUtilDERCompare`); RSA PKCS #1 v1.5 over the DER
/// SET of the signed attributes.
enum CMSSignature {
    static let signedData: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02]
    static let data: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01]
    static let sha256: [UInt8] = [0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
    static let sha1: [UInt8] = [0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a]
    static let sha256WithRSA: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b]
    static let contentType: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x03]
    static let messageDigest: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x04]
    static let signingTime: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x05]
    /// 1.2.840.113635.100.9.1 and .2: Apple's code-signing hash agility attributes.
    static let hashAgility: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x09, 0x01]
    static let hashAgilityV2: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x09, 0x02]

    /// The CMS signature of the code directories of one file (in super blob order, each with its
    /// hash type) by `identity` at `time`: the content is the first; the hash-agility
    /// attributes name each by its own hash, `cdhashes` cut to 20 bytes (observed with a watchOS
    /// file's SHA-1 and SHA-256 directories).
    static func sign(codeDirectories: [(hashType: CodeSignature.HashType, blob: [UInt8])], identity: SigningIdentity, time: Date) throws -> [UInt8] {
        let hashes = codeDirectories.map { $0.hashType.hash($0.blob) }
        let cdHashes = PropertyListValue.xmlDocument(.dictionary(["cdhashes": .array(hashes.map { .data(Array($0.prefix(20))) })]))
        let agility = zip(codeDirectories, hashes).map { DER.element(0x30, ($0.hashType == .sha1 ? sha1 : sha256) + DER.element(0x04, $1)) }
        let attributes = sorted([
            DER.element(0x30, contentType + DER.element(0x31, data)),
            DER.element(0x30, signingTime + DER.element(0x31, DER.element(0x17, Array(utcTime(time).utf8)))),
            DER.element(0x30, messageDigest + DER.element(0x31, DER.element(0x04, CodeSignature.sha256(codeDirectories[0].blob)))),
            DER.element(0x30, hashAgilityV2 + DER.element(0x31, agility.flatMap { $0 })),
            DER.element(0x30, hashAgility + DER.element(0x31, DER.element(0x04, cdHashes))),
        ]).flatMap { $0 }
        let algorithm = DER.element(0x30, sha256 + [0x05, 0x00])
        let signature: [UInt8] = try identity.sign(DER.element(0x31, attributes))
        let signerInfoParts: [[UInt8]] = [
            DER.element(0x02, [1]),
            DER.element(0x30, identity.leaf.issuer + identity.leaf.serialNumber),
            algorithm,
            DER.element(0xa0, attributes),
            DER.element(0x30, sha256WithRSA + [0x05, 0x00]),
            DER.element(0x04, signature),
        ]
        let signerInfo = DER.element(0x30, signerInfoParts.flatMap { $0 })
        let contentParts: [[UInt8]] = [
            DER.element(0x02, [1]),
            DER.element(0x31, algorithm),
            [0x30, 0x80] + data + [0x00, 0x00],
            DER.element(0xa0, sorted(identity.chain.map(\.der)).flatMap { $0 }),
            DER.element(0x31, signerInfo),
        ]
        let parts: [[UInt8]] = [[0x30, 0x80], signedData, [0xa0, 0x80, 0x30, 0x80], contentParts.flatMap { $0 }, [UInt8](repeating: 0, count: 6)]
        return parts.flatMap { $0 }
    }

    /// Shorter encodings first, then bytewise: the order of a DER SET OF as Security's CMS
    /// encoder sorts it.
    static func sorted(_ encodings: [[UInt8]]) -> [[UInt8]] {
        encodings.sorted { $0.count != $1.count ? $0.count < $1.count : $0.lexicographicallyPrecedes($1) }
    }

    /// `YYMMDDhhmmssZ` in UTC.
    static func utcTime(_ time: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
        return String(format: "%02d%02d%02d%02d%02d%02dZ", parts.year! % 100, parts.month!, parts.day!, parts.hour!, parts.minute!, parts.second!)
    }
}
