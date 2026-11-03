import NomacLZFSE
import Testing

/// What libcompression's `compression_stream` (macOS 27) writes for inputs of `Inputs` given to
/// it at once: LZVN below 4,096 bytes, one window, several windows, and output-buffer stops
/// (random bytes).
@Suite struct LZFSEStreamTests {
    static let references: [(name: String, input: @Sendable () -> [UInt8], length: Int, sha256: String)] = [
        ("small biased", { Inputs.biased(2_000, seed: 7, alphabet: 4) }, 1_028, "8bfa9851922b1b46faf0329a9b4541328aa1801da3e6cf4d89a638c3209ea1c8"),
        ("one window of text", { Inputs.text(100_000, seed: 3) }, 21_880, "08eadb2a6951ef950b45d4b562650a07caeed636f66dacee42d285a02c02a7c3"),
        ("random over windows", { Inputs.random(2_000_000, seed: 11) }, 2_020_031, "7acc77eef32f0feca4cdda1bf81ca747c5a66f2aecda7678809824eb5cb1aae9"),
        ("biased over windows", { Inputs.biased(3_000_000, seed: 5, alphabet: 4) }, 925_909, "0d00bfc7afa2ec62c8ee8ee1c6b09d908551722e5a3cc445ec64d2c82d6c7c1e"),
        ("text over windows", { Inputs.text(1_500_000, seed: 2) }, 320_083, "399dd399e3a4020181890d65d5b0856ccd77426451db945596621ad1cc41a48b"),
    ]

    @Test(arguments: references.indices)
    func streamMatchesLibcompression(_ index: Int) {
        let reference = Self.references[index]
        let stream = LZFSE.encodeStream(reference.input())
        #expect(stream.count == reference.length, "\(reference.name)")
        #expect(LZFSETests.sha256(stream) == reference.sha256, "\(reference.name)")
    }
}
