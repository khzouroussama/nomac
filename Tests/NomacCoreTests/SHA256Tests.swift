import Foundation
import Testing
import NomacCore

@Suite struct SHA256Tests {
    /// Examples from FIPS 180-4 (NIST "SHA256.pdf" examples) and the empty message.
    @Test(arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
         "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
    ])
    func fipsExamples(input: String, expected: String) {
        #expect(SHA256.hex(input) == expected)
    }

    @Test func handlesMessagesAcrossBlockBoundaries() {
        // 55, 56 and 64 bytes exercise every padding case.
        #expect(SHA256.hex(String(repeating: "a", count: 55)) == "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318")
        #expect(SHA256.hex(String(repeating: "a", count: 56)) == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a")
        #expect(SHA256.hex(String(repeating: "a", count: 64)) == "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")
    }

    @Test func base64EncodesTheDigest() {
        #expect(SHA256.base64("abc") == "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=")
    }
}
