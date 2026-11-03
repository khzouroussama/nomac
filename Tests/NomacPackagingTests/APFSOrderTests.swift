import Testing
@testable import NomacPackaging

@Suite struct APFSOrderTests {
    /// The order of an exported app's top folder in Xcode's IPA and of a ditto archive of
    /// self-written files (NFC and NFD accents).
    @Test func ordersNamesAsAPFSListsThem() {
        #expect(APFSOrder.sorted(["App", "Content", "Frameworks", "Info.plist", "PkgInfo", "PlugIns", "_CodeSignature", "data.json", "en.lproj", "fr.lproj"])
            == ["_CodeSignature", "en.lproj", "App", "PlugIns", "Content", "data.json", "fr.lproj", "Frameworks", "Info.plist", "PkgInfo"])
        #expect(APFSOrder.sorted(["random.bin", "a.txt", "link", "Sub", "big.txt", "empty", "e\u{301}-nfd.txt", "\u{e9}-nfc.txt"])
            == ["\u{e9}-nfc.txt", "e\u{301}-nfd.txt", "empty", "big.txt", "Sub", "link", "a.txt", "random.bin"])
        #expect(APFSOrder.sorted(["Symbols", "Payload"]) == ["Payload", "Symbols"])
    }

    @Test func hashesTheFoldedDecomposedName() {
        #expect(APFSOrder.hash("Payload") == 1_637_645)
        #expect(APFSOrder.hash("payload") == APFSOrder.hash("PAYLOAD"))
        #expect(APFSOrder.hash("\u{e9}-nfc.txt") == 123_515)
    }
}
