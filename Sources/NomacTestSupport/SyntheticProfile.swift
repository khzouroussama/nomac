import _CryptoExtras
import Crypto
import Foundation

/// A self-written provisioning profile: an XML property list with the keys nomac reads, as the
/// content of a CMS SignedData in DER with definite lengths (the envelope of Apple's profiles),
/// signed with SHA-256 by `TestIdentities.appleShaped`'s certificate, its chain included, whose
/// root is `root` (in place of Apple Root CA). `otherKeys` is XML for further keys, each line
/// ending in a newline.
public enum SyntheticProfile {
    /// The SHA-256 of the signing chain's root certificate, the root tests trust profiles from.
    public static var roots: Set<[UInt8]> { [Array(SHA256.hash(data: certificates.last!))] }

    static var certificates: [[UInt8]] { blocks.filter { $0.0 == "CERTIFICATE" }.map(\.1) }

    static var blocks: [(String, [UInt8])] {
        TestIdentities.appleShaped.components(separatedBy: "-----BEGIN ").dropFirst().map { block in
            let label = String(block.prefix { $0 != "-" })
            let body = block.components(separatedBy: "-----").dropFirst().first ?? ""
            return (label, [UInt8](Data(base64Encoded: body.filter { !$0.isWhitespace }) ?? Data()))
        }
    }

    public static func profile(uuid: String, name: String, expiration: String, entitlements: String, certificates: [[UInt8]], otherKeys: String = "") -> [UInt8] {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>DeveloperCertificates</key>
        \t<array>
        \(certificates.map { "\t\t<data>\(Data($0).base64EncodedString())</data>" }.joined(separator: "\n"))
        \t</array>
        \t<key>Entitlements</key>
        \(entitlements)
        \t<key>ExpirationDate</key>
        \t<date>\(expiration)</date>
        \t<key>Name</key>
        \t<string>\(name)</string>
        \t<key>UUID</key>
        \t<string>\(uuid)</string>
        \(otherKeys)</dict>
        </plist>

        """
        return signed(Array(plist.utf8))
    }

    /// `content` in a SignedData signed by the leaf of `TestIdentities.appleShaped`.
    public static func signed(_ content: [UInt8]) -> [UInt8] {
        let data: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01]
        let signedDataType: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02]
        let sha256: [UInt8] = element(0x30, [0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00])
        let rsa: [UInt8] = element(0x30, [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
        let contentType: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x03]
        let messageDigest: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x04]
        let attributes = element(0x30, contentType + element(0x31, data))
            + element(0x30, messageDigest + element(0x31, element(0x04, Array(SHA256.hash(data: content)))))
        let pem = TestIdentities.appleShaped.components(separatedBy: "-----END PRIVATE KEY-----")[0] + "-----END PRIVATE KEY-----"
        let key = try! _RSA.Signing.PrivateKey(pemRepresentation: pem)
        let signature = try! key.signature(for: SHA256.hash(data: element(0x31, attributes)), padding: .insecurePKCS1v1_5)
        let leaf = fields(certificates[0])
        let signerInfo = element(0x30, element(0x02, [1]) + element(0x30, leaf.issuer + leaf.serialNumber) + sha256
            + element(0xa0, attributes) + rsa + element(0x04, Array(signature.rawRepresentation)))
        let encapsulated = element(0x30, data + element(0xa0, element(0x04, content)))
        let signed = element(0x30, element(0x02, [1]) + element(0x31, sha256) + encapsulated + element(0xa0, certificates.flatMap { $0 })
            + element(0x31, signerInfo))
        return element(0x30, signedDataType + element(0xa0, signed))
    }

    /// A certificate's serial number and issuer, each a whole TLV.
    static func fields(_ certificate: [UInt8]) -> (serialNumber: [UInt8], issuer: [UInt8]) {
        var tbs = elements(elements(elements(certificate)[0].content)[0].content)
        if tbs[0].tag == 0xa0 { tbs.removeFirst() }
        return (tbs[0].encoded, tbs[2].encoded)
    }

    static func elements(_ bytes: [UInt8]) -> [(tag: UInt8, content: [UInt8], encoded: [UInt8])] {
        var result: [(tag: UInt8, content: [UInt8], encoded: [UInt8])] = []
        var index = 0
        while index + 2 <= bytes.count {
            let start = index
            var length = Int(bytes[index + 1])
            index += 2
            if length & 0x80 != 0 {
                let count = length & 0x7f
                length = bytes[index..<(index + count)].reduce(0) { $0 << 8 | Int($1) }
                index += count
            }
            result.append((bytes[start], Array(bytes[index..<(index + length)]), Array(bytes[start..<(index + length)])))
            index += length
        }
        return result
    }

    private static func element(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        let count = content.count
        if count < 0x80 { return [tag, UInt8(count)] + content }
        let length = withUnsafeBytes(of: UInt32(count).bigEndian, Array.init).drop { $0 == 0 }
        return [tag, 0x80 | UInt8(length.count)] + length + content
    }
}
