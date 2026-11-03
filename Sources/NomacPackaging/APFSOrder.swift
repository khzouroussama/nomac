import Foundation

/// The order in which a directory on a case-insensitive APFS volume (the default on macOS) lists
/// its entries, which is the order ditto, and so Xcode's IPA, writes them in.
///
/// APFS keys directory entries by a 22-bit hash of the name (Apple File System Reference,
/// `j_drec_hashed_key_t`). Observed in every folder of the IPAs `xcodebuild -exportArchive` and
/// `ditto -c -k` wrote (docs/formats/ipa.md): the hash is the CRC-32C, started at 0xffffffff and
/// not inverted, of the name's canonical decomposition (NFD), case-folded, as UTF-32
/// little-endian, keeping the low 22 bits; entries go in increasing hash order.
enum APFSOrder {
    static func hash(_ name: String) -> UInt32 {
        let folded = name.decomposedStringWithCanonicalMapping.lowercased()
        var crc: UInt32 = 0xffff_ffff
        for scalar in folded.unicodeScalars {
            for shift in stride(from: 0, to: 32, by: 8) {
                crc = table[Int((crc ^ (scalar.value >> UInt32(shift))) & 0xff)] ^ (crc >> 8)
            }
        }
        return crc & 0x3f_ffff
    }

    /// `names` in directory order: by hash, then by length in UTF-8 bytes (the rest of APFS's
    /// key), then by bytes.
    static func sorted(_ names: [String]) -> [String] {
        names.map { (name: $0, hash: hash($0), bytes: Array($0.utf8)) }
            .sorted { lhs, rhs in
                if lhs.hash != rhs.hash { return lhs.hash < rhs.hash }
                if lhs.bytes.count != rhs.bytes.count { return lhs.bytes.count < rhs.bytes.count }
                return lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
            }
            .map(\.name)
    }

    /// CRC-32C (Castagnoli, reflected polynomial 0x82f63b78).
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? (value >> 1) ^ 0x82f6_3b78 : value >> 1
        }
        return value
    }
}
