/// Base64 (RFC 4648, with padding), which `@State`'s expansions use to pass a name and source text
/// to the macros of their own expansions.
enum Base64 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

    static func encode(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var output: [UInt8] = []
        for start in stride(from: 0, to: bytes.count, by: 3) {
            let chunk = bytes[start..<min(start + 3, bytes.count)]
            let value = chunk.enumerated().reduce(0) { $0 | Int($1.element) << (16 - 8 * $1.offset) }
            for index in 0..<4 {
                output.append(index <= chunk.count ? alphabet[(value >> (18 - 6 * index)) & 63] : UInt8(ascii: "="))
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    static func decode(_ text: String) -> String? {
        var value = 0
        var bits = 0
        var output: [UInt8] = []
        for character in text.utf8 where character != UInt8(ascii: "=") {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            value = value << 6 | index
            bits += 6
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((value >> bits) & 255))
            }
        }
        return String(validating: output, as: UTF8.self)
    }
}
