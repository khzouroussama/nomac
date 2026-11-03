import Foundation

/// The baseline JPEG inside actool's `jpeg-lzfse` payloads (`heic` experiment alpha cases):
/// JFIF 1.1 with a 72:72 pixel aspect ratio, an Exif segment naming the color space and the pixel size, an empty
/// Photoshop IPTC record and its digest, 8-bit YCbCr without subsampling, the standard Huffman
/// tables (ITU T.81 Annex K.3), the quantization tables below, and a restart marker after every
/// row of blocks. AppleJPEG's coefficients differ from these (ADR 0204): its transform and its
/// padding of partial blocks are not known.
enum JPEGEncoder {
    /// The quantization tables actool's JPEGs carry, in zigzag order.
    static let luminance: [Int] = [1, 1, 1, 1, 1, 1, 2, 1, 1, 2, 3, 2, 2, 2, 3, 4, 3, 3, 3, 3, 4, 5, 4, 4, 4, 4, 4, 5, 6, 5, 5, 5,
                                   5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9]
    static let chrominance: [Int] = [1, 1, 1, 2, 2, 2, 4, 2, 2, 4, 9, 6, 5, 6, 9] + [Int](repeating: 9, count: 49)

    static let zigzag: [Int] = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
                                35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]

    struct HuffmanTable {
        let bits: [UInt8]
        let values: [UInt8]

        /// Each value's code and length, as T.81 Annex C assigns them.
        var codes: [(code: Int, length: Int)] {
            var codes = [(code: Int, length: Int)](repeating: (0, 0), count: 256)
            var code = 0, index = 0
            for (offset, count) in bits.enumerated() {
                for _ in 0..<count {
                    codes[Int(values[index])] = (code, offset + 1)
                    code += 1
                    index += 1
                }
                code <<= 1
            }
            return codes
        }
    }

    static let dcLuminance = HuffmanTable(bits: [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0], values: Array(0...11))
    static let dcChrominance = HuffmanTable(bits: [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0], values: Array(0...11))
    static let acLuminance = HuffmanTable(bits: [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D], values: [
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
        0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA,
    ])
    static let acChrominance = HuffmanTable(bits: [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77], values: [
        0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
        0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
        0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
        0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4,
        0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA,
        0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA,
    ])

    /// The segments before the scan.
    static func header(width: Int, height: Int) -> [UInt8] {
        var out: [UInt8] = [0xFF, 0xD8]
        func segment(_ marker: UInt8, _ data: [UInt8]) {
            out += [0xFF, marker] + be16(data.count + 2) + data
        }
        segment(0xE0, Array("JFIF".utf8) + [0, 1, 1, 0, 0, 0x48, 0, 0x48, 0, 0])
        var exif: [UInt8] = Array("Exif".utf8) + [0, 0] + Array("MM".utf8) + [0, 42] + be32(8)
        exif += be16(1) + be16(0x8769) + be16(4) + be32(1) + be32(26) + be32(0)
        exif += be16(3) + be16(0xA001) + be16(3) + be32(1) + be16(1) + be16(0)
        exif += be16(0xA002) + be16(4) + be32(1) + be32(width)
        exif += be16(0xA003) + be16(4) + be32(1) + be32(height) + be32(0)
        segment(0xE1, exif)
        let emptyDigest: [UInt8] = [0xD4, 0x1D, 0x8C, 0xD9, 0x8F, 0x00, 0xB2, 0x04, 0xE9, 0x80, 0x09, 0x98, 0xEC, 0xF8, 0x42, 0x7E]
        segment(0xED, Array("Photoshop 3.0".utf8) + [0] + Array("8BIM".utf8) + [4, 4, 0, 0] + be32(0)
            + Array("8BIM".utf8) + [4, 0x25, 0, 0] + be32(16) + emptyDigest)
        segment(0xC0, [8] + be16(height) + be16(width) + [3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1])
        for (index, table) in [(0x00, dcLuminance), (0x10, acLuminance), (0x01, dcChrominance), (0x11, acChrominance)] {
            segment(0xC4, [UInt8(index)] + table.bits + table.values)
        }
        segment(0xDB, [0] + luminance.map(UInt8.init))
        segment(0xDB, [1] + chrominance.map(UInt8.init))
        segment(0xDD, be16((width + 7) / 8))
        segment(0xDA, [3, 1, 0x00, 2, 0x11, 3, 0x11, 0, 63, 0])
        return out
    }

    /// The JPEG of 8-bit RGB pixels, rows from the top.
    static func encode(rgb: [UInt8], width: Int, height: Int) -> [UInt8] {
        var out = header(width: width, height: height)
        var writer = BitWriter()
        let tables = [(dcLuminance.codes, acLuminance.codes, luminance), (dcChrominance.codes, acChrominance.codes, chrominance),
                      (dcChrominance.codes, acChrominance.codes, chrominance)]
        let cosines: [[Double]] = (0..<8).map { x in
            (0..<8).map { u -> Double in
                let scale: Double = u == 0 ? 1 / 2.squareRoot() : 1
                return cos(Double((2 * x + 1) * u) * Double.pi / 16) * scale
            }
        }
        let columns = (width + 7) / 8, rows = (height + 7) / 8
        var block = [[Double]](repeating: [Double](repeating: 0, count: 64), count: 3)
        for row in 0..<rows {
            if row > 0 {
                writer.flush()
                writer.bytes += [0xFF, 0xD0 + UInt8((row - 1) % 8)]
            }
            var predictions = [0, 0, 0]
            for column in 0..<columns {
                for y in 0..<8 {
                    for x in 0..<8 {
                        let index = (min(row * 8 + y, height - 1) * width + min(column * 8 + x, width - 1)) * 3
                        let r = Double(rgb[index]), g = Double(rgb[index + 1]), b = Double(rgb[index + 2])
                        block[0][y * 8 + x] = 0.299 * r + 0.587 * g + 0.114 * b - 128
                        block[1][y * 8 + x] = -0.168736 * r - 0.331264 * g + 0.5 * b
                        block[2][y * 8 + x] = 0.5 * r - 0.418688 * g - 0.081312 * b
                    }
                }
                for component in 0..<3 {
                    let (dc, ac, quantization) = tables[component]
                    var horizontal = [Double](repeating: 0, count: 64), coefficients = [Double](repeating: 0, count: 64)
                    for y in 0..<8 {
                        for u in 0..<8 {
                            var sum = 0.0
                            for x in 0..<8 { sum += block[component][y * 8 + x] * cosines[x][u] }
                            horizontal[y * 8 + u] = sum
                        }
                    }
                    for v in 0..<8 {
                        for u in 0..<8 {
                            var sum = 0.0
                            for y in 0..<8 { sum += horizontal[y * 8 + u] * cosines[y][v] }
                            coefficients[v * 8 + u] = sum / 4
                        }
                    }
                    let quantized = (0..<64).map { Int((coefficients[zigzag[$0]] / Double(quantization[$0])).rounded()) }
                    let difference = quantized[0] - predictions[component]
                    predictions[component] = quantized[0]
                    let size = magnitudeBits(difference)
                    writer.write(dc[size])
                    writer.write(amplitude(difference, size), size)
                    var zeros = 0
                    for value in quantized[1...] {
                        guard value != 0 else { zeros += 1; continue }
                        while zeros > 15 {
                            writer.write(ac[0xF0])
                            zeros -= 16
                        }
                        let size = magnitudeBits(value)
                        writer.write(ac[zeros << 4 | size])
                        writer.write(amplitude(value, size), size)
                        zeros = 0
                    }
                    if zeros > 0 { writer.write(ac[0]) }
                }
            }
        }
        writer.flush()
        out += writer.bytes
        return out + [0xFF, 0xD9]
    }

    static func magnitudeBits(_ value: Int) -> Int {
        var magnitude = abs(value), bits = 0
        while magnitude > 0 {
            bits += 1
            magnitude >>= 1
        }
        return bits
    }

    static func amplitude(_ value: Int, _ size: Int) -> Int {
        value >= 0 ? value : value + (1 << size) - 1
    }

    /// Entropy-coded bits, most significant first, each 0xFF byte followed by a stuffed zero.
    struct BitWriter {
        var bytes: [UInt8] = []
        var buffer = 0, count = 0

        mutating func write(_ code: (code: Int, length: Int)) { write(code.code, code.length) }

        mutating func write(_ value: Int, _ length: Int) {
            guard length > 0 else { return }
            buffer = buffer << length | (value & (1 << length - 1))
            count += length
            while count >= 8 {
                let byte = UInt8(buffer >> (count - 8) & 0xFF)
                bytes.append(byte)
                if byte == 0xFF { bytes.append(0) }
                count -= 8
            }
            buffer &= (1 << count) - 1
        }

        /// Fills the last byte with one bits.
        mutating func flush() {
            if count > 0 { write((1 << (8 - count)) - 1, 8 - count) }
        }
    }

    static func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    static func be32(_ value: Int) -> [UInt8] { be16(value >> 16) + be16(value) }
}
