import Foundation
import Testing
import NomacCore

@Suite struct FoundationStringHashTests {
    /// The values `NSString.hash` reports on macOS 27.0.1, from ASCII, non-ASCII (decomposed,
    /// Greek, CJK, groups of four units whose weighted sum passes 32 bits) and a name longer than
    /// 96 UTF-16 units.
    @Test(arguments: [
        ("a", 0x426),
        ("b01.swift", 0x341a_9506_3474_7727),
        ("Info.plist", 0x5030_678a_d306_bbf0),
        ("Ünïcödé.swift", 0x0745_26b4_7a08_9c47),
        ("U\u{308}ni\u{308}.swift", 16_695_673_817_055_951_522),
        ("\u{395}\u{3BB}\u{3BB}\u{3B7}\u{3BD}\u{3B9}\u{3BA}\u{3AC}", 1_634_145_297_463_926_438),
        ("A\u{30A}ngstro\u{308}m.swift", 2_684_597_246_633_498_824),
        ("\u{65E5}\u{672C}\u{8A9E}.txt", 5_751_864_054_378_416_196),
        ("\u{FF}\u{FF}\u{FF}\u{FF}", 5_448_068_608),
        (String(repeating: "LongName", count: 15) + ".swift", 0xe206_cf7d_7c3f_a666),
    ] as [(String, UInt64)])
    func matchesNSString(string: String, expected: UInt64) {
        #expect(FoundationStringHash.hash(string) == expected)
    }
}
