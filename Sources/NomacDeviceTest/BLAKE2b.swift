/// BLAKE2b with a 64-byte digest and no key (RFC 7693), which names a result bundle's stored objects
/// (docs/formats/xcresult.md).
enum BLAKE2b {
    private static let initial: [UInt64] = [
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
    ]
    private static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
    ]

    static func hash(_ bytes: [UInt8]) -> [UInt8] {
        var state = initial
        state[0] ^= 0x0101_0040
        var offset = 0
        repeat {
            let end = min(offset + 128, bytes.count)
            var block = Array(bytes[offset..<end])
            let isLast = end == bytes.count
            block += [UInt8](repeating: 0, count: 128 - block.count)
            compress(&state, block, counter: UInt64(end), isLast: isLast)
            offset = end
        } while offset < bytes.count
        return state.flatMap { word in (0..<8).map { UInt8(truncatingIfNeeded: word >> (8 * UInt64($0))) } }
    }

    private static func compress(_ state: inout [UInt64], _ block: [UInt8], counter: UInt64, isLast: Bool) {
        let message = (0..<16).map { word in (0..<8).reduce(UInt64(0)) { $0 | UInt64(block[word * 8 + $1]) << (8 * UInt64($1)) } }
        var v = state + initial
        v[12] ^= counter
        if isLast { v[14] = ~v[14] }
        func rotate(_ value: UInt64, _ count: UInt64) -> UInt64 { value >> count | value << (64 - count) }
        func mix(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
            v[a] = v[a] &+ v[b] &+ x
            v[d] = rotate(v[d] ^ v[a], 32)
            v[c] = v[c] &+ v[d]
            v[b] = rotate(v[b] ^ v[c], 24)
            v[a] = v[a] &+ v[b] &+ y
            v[d] = rotate(v[d] ^ v[a], 16)
            v[c] = v[c] &+ v[d]
            v[b] = rotate(v[b] ^ v[c], 63)
        }
        for round in 0..<12 {
            let order = sigma[round % 10]
            mix(0, 4, 8, 12, message[order[0]], message[order[1]])
            mix(1, 5, 9, 13, message[order[2]], message[order[3]])
            mix(2, 6, 10, 14, message[order[4]], message[order[5]])
            mix(3, 7, 11, 15, message[order[6]], message[order[7]])
            mix(0, 5, 10, 15, message[order[8]], message[order[9]])
            mix(1, 6, 11, 12, message[order[10]], message[order[11]])
            mix(2, 7, 8, 13, message[order[12]], message[order[13]])
            mix(3, 4, 9, 14, message[order[14]], message[order[15]])
        }
        for index in 0..<8 { state[index] ^= v[index] ^ v[index + 8] }
    }
}
