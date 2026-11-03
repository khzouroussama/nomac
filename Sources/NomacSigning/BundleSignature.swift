import Foundation
import NomacCore

/// How a bundle's executable is signed: not at all, ad hoc (an empty CMS blob), or with a
/// certificate, the CMS signer's.
public enum BundleSignature: Equatable, Sendable {
    case unsigned
    case adHoc
    case certificate(sha1: String, commonName: String)

    /// The signature of the executable at `path`, read from its first slice's `LC_CODE_SIGNATURE`
    /// superblob (`<kern/cs_blobs.h>`: the CMS blob is in slot 0x10000, magic 0xfade0b01).
    public static func of(executable path: String) throws -> BundleSignature {
        guard let data = FileManager.default.contents(atPath: path), MachOContainer.isMachO([UInt8](data)),
              let image = try MachOContainer(bytes: [UInt8](data), path: path).slices.first?.image,
              let (offset, size) = image.codeSignature, offset + size <= image.bytes.count else { return .unsigned }
        let bytes = image.bytes
        func be32(_ at: Int) -> Int { at >= 0 && at + 4 <= bytes.count ? bytes[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } : 0 }
        guard be32(offset) == Int(CodeSignature.superBlobMagic) else { return .unsigned }
        for index in 0..<be32(offset + 8) {
            let blob = offset + be32(offset + 16 + index * 8)
            guard be32(offset + 12 + index * 8) == 0x10000, be32(blob) == 0xfade_0b01 else { continue }
            let length = be32(blob + 4)
            guard length > 8, blob + length <= bytes.count else { return .adHoc }
            guard let certificate = signer(cms: Array(bytes[(blob + 8)..<(blob + length)]), path: path) else { return .adHoc }
            return .certificate(sha1: certificate.sha1Hex.uppercased(), commonName: certificate.commonName ?? "")
        }
        return .adHoc
    }

    /// The signer's certificate in a CMS `ContentInfo` holding `SignedData` (RFC 5652): the one of
    /// its `[0] IMPLICIT` certificates whose issuer and serial number the first `SignerInfo` names
    /// (codesign sorts the certificates shorter first, so the leaf can be anywhere; it writes the
    /// outer elements with indefinite lengths, CMSSignature).
    static func signer(cms: [UInt8], path: String) -> X509Certificate? {
        guard let contentInfo = element(cms, at: 0),
              let explicit = children(cms, contentInfo.content).first(where: { $0.tag == 0xa0 }),
              let signedData = children(cms, explicit.content).first else { return nil }
        let fields = children(cms, signedData.content)
        guard let certificates = fields.first(where: { $0.tag == 0xa0 }), let signerInfos = fields.last(where: { $0.tag == 0x31 }),
              let signerInfo = children(cms, signerInfos.content).first,
              let issuerAndSerial = children(cms, signerInfo.content).dropFirst().first else { return nil }
        let names = Array(cms[issuerAndSerial.content])
        return children(cms, certificates.content).lazy
            .compactMap { try? X509Certificate(der: Array(cms[$0.whole]), path: path) }
            .first { $0.issuer + $0.serialNumber == names }
    }

    struct Element {
        var tag: UInt8
        var content: Range<Int>
        var whole: Range<Int>
    }

    /// The BER element at `index`: definite lengths, or indefinite ones (0x80) ended by two zero bytes.
    static func element(_ bytes: [UInt8], at index: Int) -> Element? {
        guard index + 2 <= bytes.count else { return nil }
        let first = Int(bytes[index + 1])
        if first == 0x80 {
            var next = index + 2
            while next + 2 <= bytes.count, bytes[next] != 0 || bytes[next + 1] != 0 {
                guard let child = element(bytes, at: next) else { return nil }
                next = child.whole.upperBound
            }
            guard next + 2 <= bytes.count else { return nil }
            return Element(tag: bytes[index], content: (index + 2)..<next, whole: index..<(next + 2))
        }
        var start = index + 2, length = first
        if first & 0x80 != 0 {
            let count = first & 0x7f
            guard count <= 4, start + count <= bytes.count else { return nil }
            length = bytes[start..<(start + count)].reduce(0) { $0 << 8 | Int($1) }
            start += count
        }
        guard start + length <= bytes.count else { return nil }
        return Element(tag: bytes[index], content: start..<(start + length), whole: index..<(start + length))
    }

    static func children(_ bytes: [UInt8], _ range: Range<Int>) -> [Element] {
        var result: [Element] = []
        var index = range.lowerBound
        while index < range.upperBound, let child = element(bytes, at: index) {
            result.append(child)
            index = child.whole.upperBound
        }
        return result
    }
}
