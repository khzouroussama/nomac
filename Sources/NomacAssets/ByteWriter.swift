/// An append-only byte buffer with the fixed-width encodings the BOM container (big-endian)
/// and the CAR structures inside it (little-endian) use.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    var count: Int { bytes.count }

    mutating func append(_ other: [UInt8]) {
        bytes.append(contentsOf: other)
    }

    mutating func appendBE(_ value: UInt32) {
        bytes.append(contentsOf: [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func appendBE(_ value: UInt16) {
        bytes.append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    mutating func appendLE(_ value: UInt32) {
        bytes.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)])
    }

    mutating func appendLE(_ value: UInt16) {
        bytes.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func appendLE(_ value: Double) {
        var bits = value.bitPattern
        for _ in 0..<8 {
            bytes.append(UInt8(bits & 0xFF))
            bits >>= 8
        }
    }

    /// Appends `string` as UTF-8 in a field of exactly `width` bytes, padded with zeros.
    mutating func appendFixed(_ string: String, width: Int) {
        let utf8 = Array(string.utf8.prefix(width))
        bytes.append(contentsOf: utf8)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: width - utf8.count))
    }

    mutating func appendZeros(_ count: Int) {
        bytes.append(contentsOf: [UInt8](repeating: 0, count: count))
    }

    mutating func align(to alignment: Int) {
        let remainder = bytes.count % alignment
        if remainder != 0 { appendZeros(alignment - remainder) }
    }
}
