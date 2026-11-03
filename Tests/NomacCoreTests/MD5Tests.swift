import Foundation
import Testing
import NomacCore

@Suite struct MD5Tests {
    /// The test suite from RFC 1321, appendix A.5.
    @Test(arguments: [
        ("", "d41d8cd98f00b204e9800998ecf8427e"),
        ("a", "0cc175b9c0f1b6a831c399e269772661"),
        ("abc", "900150983cd24fb0d6963f7d28e17f72"),
        ("message digest", "f96b697d7cb7938d525a2f31aaf161d0"),
        ("abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b"),
        ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", "d174ab98d277d9f5a5611c2c9f419d9f"),
        ("12345678901234567890123456789012345678901234567890123456789012345678901234567890", "57edf4a22be3c955ac49da2e2107b67a"),
    ])
    func rfc1321TestSuite(input: String, expected: String) {
        #expect(MD5.hex(input) == expected)
    }

    /// Identifiers observed in Xcode's PIF for the corpus app retro-rampage.
    @Test func reproducesXcodePIFIdentifiers() {
        #expect(MD5.hex("Rampage") == "a9744fc5b0ca952b17ef07c0aa99602e")
        #expect(MD5.hex("Rampage.xcodeproj") == "dfb26fd5fb1a9217e6667a819fd9d9f8")
        #expect(MD5.hex("016E41BF228E9A5E00ACF137") == "19876192b11e271bb738737170024fa7")
    }

    @Test func handlesMessagesAcrossBlockBoundaries() {
        // 55, 56 and 64 bytes exercise every padding case.
        #expect(MD5.hex(String(repeating: "a", count: 55)) == "ef1772b6dff9a122358552954ad0df65")
        #expect(MD5.hex(String(repeating: "a", count: 56)) == "3b0c8ac703f828b04c6c197006d17218")
        #expect(MD5.hex(String(repeating: "a", count: 64)) == "014842d480b571495a4a0363793f7367")
    }
}
