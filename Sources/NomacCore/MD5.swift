import Foundation

/// MD5 (RFC 1321).
///
/// Xcode derives PIF object identifiers from MD5 digests (docs/formats/pif.md). Swift
/// Build's own `String.md5()` is not usable for this: off Apple platforms its "insecure
/// hash" is SHA-256. MD5 is used here only to reproduce identifiers, never for security.
public enum MD5 {
    /// The lowercase hexadecimal MD5 digest of the UTF-8 bytes of `string`.
    public static func hex(_ string: String) -> String {
        hex(Array(string.utf8))
    }

    /// The lowercase hexadecimal MD5 digest of `bytes`.
    public static func hex(_ bytes: [UInt8]) -> String {
        digest(bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// The 16-byte MD5 digest of `bytes`.
    public static func digest(_ bytes: [UInt8]) -> [UInt8] {
        var message = bytes
        let bitLength = UInt64(bytes.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for i in 0..<8 {
            message.append(UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(i))))
        }

        var a0: UInt32 = 0x6745_2301
        var b0: UInt32 = 0xefcd_ab89
        var c0: UInt32 = 0x98ba_dcfe
        var d0: UInt32 = 0x1032_5476

        for chunk in stride(from: 0, to: message.count, by: 64) {
            var m = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let base = chunk + i * 4
                m[i] = UInt32(message[base]) | UInt32(message[base + 1]) << 8 | UInt32(message[base + 2]) << 16 | UInt32(message[base + 3]) << 24
            }
            var a = a0, b = b0, c = c0, d = d0
            for i in 0..<64 {
                var f: UInt32
                let g: Int
                switch i {
                case 0..<16:
                    f = (b & c) | (~b & d)
                    g = i
                case 16..<32:
                    f = (d & b) | (~d & c)
                    g = (5 * i + 1) % 16
                case 32..<48:
                    f = b ^ c ^ d
                    g = (3 * i + 5) % 16
                default:
                    f = c ^ (b | ~d)
                    g = (7 * i) % 16
                }
                f = f &+ a &+ k[i] &+ m[g]
                a = d
                d = c
                c = b
                b = b &+ ((f << s[i]) | (f >> (32 - s[i])))
            }
            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
        }

        var result: [UInt8] = []
        for word in [a0, b0, c0, d0] {
            for i in 0..<4 {
                result.append(UInt8(truncatingIfNeeded: word >> (8 * UInt32(i))))
            }
        }
        return result
    }

    private static let s: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]

    /// `floor(abs(sin(i + 1)) * 2^32)` for i in 0..<64.
    private static let k: [UInt32] = (0..<64).map { UInt32(truncatingIfNeeded: Int64(abs(sin(Double($0 + 1))) * 4_294_967_296)) }
}
