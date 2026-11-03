/// Deterministic inputs for the encoder tests.
enum Inputs {
    /// A 64-bit linear congruential generator (Knuth's MMIX constants), one byte per step.
    struct Generator {
        var state: UInt64

        mutating func next() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 56)
        }
    }

    static func random(_ count: Int, seed: UInt64) -> [UInt8] {
        var generator = Generator(state: seed)
        return (0..<count).map { _ in generator.next() }
    }

    /// Bytes drawn from the `alphabet` lowest values: many short matches.
    static func biased(_ count: Int, seed: UInt64, alphabet: Int) -> [UInt8] {
        var generator = Generator(state: seed)
        return (0..<count).map { _ in UInt8(Int(generator.next()) % alphabet) }
    }

    /// Words from a small vocabulary, separated by spaces and newlines.
    static func text(_ count: Int, seed: UInt64) -> [UInt8] {
        let words = [
            "asset", "catalog", "image", "color", "set", "the", "of", "rendition", "key", "name",
            "Contents", "json", "idiom", "universal", "scale", "2x", "3x",
        ]
        var generator = Generator(state: seed)
        var bytes: [UInt8] = []
        while bytes.count < count {
            bytes += Array(words[Int(generator.next()) % words.count].utf8)
            bytes.append(generator.next() < 32 ? 0x0A : 0x20)
        }
        return Array(bytes.prefix(count))
    }

    static func repeating(_ pattern: [UInt8], count: Int) -> [UInt8] {
        (0..<count).map { pattern[$0 % pattern.count] }
    }

    /// 420208 bytes in four planes of 105052: an opaque alpha plane (one run of 0xFF), then
    /// three planes of small values in gradients with noise.
    static func planarImage(seed: UInt64) -> [UInt8] {
        let planeSize = 105_052
        var generator = Generator(state: seed)
        var bytes = [UInt8](repeating: 0xFF, count: planeSize)
        for plane in 1...3 {
            for i in 0..<planeSize {
                let noise = Int(generator.next() & 3)
                bytes.append(UInt8((i % 256 / 24 + i / 256 / 40 + plane * 5 + noise) & 0x3F))
            }
        }
        return bytes
    }
}
