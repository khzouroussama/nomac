import Foundation

/// The color profiles nomac embeds where Quartz embeds Apple's when it writes a PDF image set
/// again: Quartz's are not published, so nomac writes its own from the public definitions
/// (IEC 61966-2-1 for sRGB, a 2.2 gamma for gray), which ADR 0204 accepts in their place.
enum PDFProfiles {
    static let sRGB: [UInt8] = {
        let curve = curv((0..<1024).map { index -> Double in
            let value = Double(index) / 1023
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        })
        return profile(colorSpace: "RGB ", description: "nomac sRGB IEC61966-2.1", tags: [
            ("wtpt", xyz(0.9642, 1.0, 0.8249)),
            ("rXYZ", xyz(0.4361, 0.2225, 0.0139)), ("gXYZ", xyz(0.3851, 0.7169, 0.0971)), ("bXYZ", xyz(0.1431, 0.0606, 0.7141)),
            ("rTRC", curve), ("gTRC", curve), ("bTRC", curve),
        ])
    }()

    static let gray: [UInt8] = profile(colorSpace: "GRAY", description: "nomac Gray Gamma 2.2", tags: [
        ("wtpt", xyz(0.9642, 1.0, 0.8249)), ("kTRC", Array("curv".utf8) + [0, 0, 0, 0] + be32(1) + [0x02, 0x33]),
    ])

    /// A version 2 display profile with a description, a copyright and `tags`.
    static func profile(colorSpace: String, description: String, tags: [(String, [UInt8])]) -> [UInt8] {
        let text = Array(description.utf8) + [0]
        let desc = Array("desc".utf8) + [0, 0, 0, 0] + be32(UInt32(text.count)) + text + [UInt8](repeating: 0, count: 4 + 4 + 2 + 1 + 67)
        let copyright = Array("text".utf8) + [0, 0, 0, 0] + Array("No copyright, use freely\0".utf8)
        let all = [("desc", desc), ("cprt", copyright)] + tags
        var table: [UInt8] = be32(UInt32(all.count))
        var body: [UInt8] = []
        var offset = 128 + 4 + 12 * all.count
        for (signature, data) in all {
            table += Array(signature.utf8) + be32(UInt32(offset)) + be32(UInt32(data.count))
            let padded = data + [UInt8](repeating: 0, count: (4 - data.count % 4) % 4)
            body += padded
            offset += padded.count
        }
        var header = be32(UInt32(128 + table.count + body.count)) + Array("none".utf8) + [0x02, 0x10, 0, 0]
        header += Array("mntr".utf8) + Array(colorSpace.utf8) + Array("XYZ ".utf8) + [UInt8](repeating: 0, count: 12)
        header += Array("acsp".utf8) + [UInt8](repeating: 0, count: 4 + 4 + 4 + 4 + 4 + 8 + 4)
        header += xyz(0.9642, 1.0, 0.8249).suffix(12)
        header += [UInt8](repeating: 0, count: 128 - header.count)
        return header + table + body
    }

    static func xyz(_ x: Double, _ y: Double, _ z: Double) -> [UInt8] {
        Array("XYZ ".utf8) + [0, 0, 0, 0] + [x, y, z].flatMap { be32(UInt32(bitPattern: Int32(($0 * 65536).rounded()))) }
    }

    static func curv(_ values: [Double]) -> [UInt8] {
        Array("curv".utf8) + [0, 0, 0, 0] + be32(UInt32(values.count)) + values.flatMap { value -> [UInt8] in
            let encoded = UInt16((min(max(value, 0), 1) * 65535).rounded())
            return [UInt8(encoded >> 8), UInt8(encoded & 0xFF)]
        }
    }

    static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
