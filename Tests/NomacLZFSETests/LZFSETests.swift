import NomacCore
import NomacLZFSE
import Testing

/// What the reference encoder (github.com/lzfse/lzfse at commit e634ca58, built from source)
/// writes for the inputs of `Inputs`: `lzfse -encode` for LZFSE (for the empty input, which
/// the CLI never finishes, `lzfse_encode_buffer` into 64 bytes), and `lzvn_encode_buffer` into
/// a destination of twice the input's size plus 1024 bytes for LZVN.
@Suite struct LZFSETests {
    struct Reference: Sendable, CustomTestStringConvertible {
        let name: String
        let input: @Sendable () -> [UInt8]
        let lzfse: (length: Int, sha256: String)
        let lzvn: (length: Int, sha256: String)

        init(_ name: String, _ input: @escaping @Sendable () -> [UInt8], lzfse: (Int, String), lzvn: (Int, String)) {
            self.name = name
            self.input = input
            self.lzfse = lzfse
            self.lzvn = lzvn
        }

        var testDescription: String { name }
    }

    static let references: [Reference] = [
        Reference(
            "empty", { [] },
            lzfse: (12, "9502b7226136d6e97cbe78c04ac9ea572595fc7b25ae1394759d45a1796b86ff"),
            lzvn: (8, "23d7f42b1cdc1f0d492ebd756ed0fe8003995dda554d99418d47a81813650207")
        ),
        Reference(
            "1 byte", { [0x61] },
            lzfse: (13, "b54ff73a3b9c7cb5a49478fe94a0d583080f03ee57b9b2995863855b85376faf"),
            lzvn: (10, "24171fd32631042fb9ecfb962a96758372b67409ffbf72b8220ef08c100ce2cd")
        ),
        Reference(
            "7 bytes", { Array("abcdefg".utf8) },
            lzfse: (19, "6aaf7ff8a691192bf02dcad8da704895c65a6fc259d8edf036efb9186ff16701"),
            lzvn: (16, "1371a3ac08c6b38f190539c72c01985eb36bc32c8bba675788419680ee8ed7f0")
        ),
        Reference(
            "8 zeros", { [UInt8](repeating: 0, count: 8) },
            lzfse: (20, "597d5f73936e384cdbbe4ae90681ec8123a6fdba9184731d53bd5be15c2bfdca"),
            lzvn: (17, "8feec23d0d601270510660b60d47025e7ca6159423b0cf28111f1af43f7ecbd6")
        ),
        Reference(
            "abcde", { Array("abcde".utf8) },
            lzfse: (17, "4c2db17fda8871819a1cfc7dad37d0eb9e3dc62f141137886a465ec968e86ebd"),
            lzvn: (14, "9769ee0d258540df4c6e8fc633b1ba23372359045d7af81c6f4bd55bf248c512")
        ),
        Reference(
            "text, 100 bytes", { Inputs.text(100, seed: 1) },
            lzfse: (113, "1d69cf65c430b5c0841dfb4d1bbe0c1edf0f2eb41cd996d4495663c7d79dbe2b"),
            lzvn: (97, "0c4c6cf6f41bf818f2931a902883d1b987508a8ae78829da5589f2cf55539d37")
        ),
        Reference(
            "random, 100 bytes", { Inputs.random(100, seed: 2) },
            lzfse: (112, "9fa36c9558800775ac6519262055581b97caf9ddc4d5c27357ec9c17629b93d7"),
            lzvn: (110, "93065b0c42134e90de30085d2d4c56a062acaa4ccba1119863949a71e45d980e")
        ),
        Reference(
            "random, 2000 bytes", { Inputs.random(2000, seed: 11) },
            lzfse: (2012, "5a9e09f32ef2a31dd674769e7bbf419f1f965f4e1b21a495a0f5d57f58f166a2"),
            lzvn: (2024, "ffd2740b997703783143263774a55f34a2f81b50af7a287abdcd64137770e862")
        ),
        Reference(
            "text, 4000 bytes", { Inputs.text(4000, seed: 10) },
            lzfse: (1305, "194d5b1efd5f60f1240581ad1fc2b611a35ac7b54a939850fe7dfe458ec95b69"),
            lzvn: (1289, "9140fd523b07175b95d276c52302e49b1579b07c04c723259cab49004a88dde1")
        ),
        Reference(
            "text, 4095 bytes", { Inputs.text(4095, seed: 3) },
            lzfse: (1374, "9ae7de70b50a1087faab25b0d2fd0023bfb46c497e6f4ea7858e05102ed8f755"),
            lzvn: (1358, "361bdb71fb05bfdf92c2aeb565f2807904bc6795f0a691d01970d364d2b3c769")
        ),
        Reference(
            "text, 4096 bytes", { Inputs.text(4096, seed: 3) },
            lzfse: (1174, "f2bdb17fe30e92bb5edc33a6b40406a7953e8d032aa0417c44bd9a1c1dec42b7"),
            lzvn: (1359, "0a489a51d0ae2bb95ebfa469f785a1483276fba070bd9bfc75d741a63fbcc9a5")
        ),
        Reference(
            "random, 4097 bytes", { Inputs.random(4097, seed: 4) },
            lzfse: (4352, "2242b99e55b611596ad3ae45889e092bfbe30e8bbce6be20541285ba9f8b9ef1"),
            lzvn: (4138, "a2fb5dc1a3201db243959986519ad1ae33f2a31d0df83117a8f2a6409d9e0a61")
        ),
        Reference(
            "zeros, 65536 bytes", { [UInt8](repeating: 0, count: 65536) },
            lzfse: (184, "1c83761309d187e42d9c7fb0ebb3ec731ae5da18283ceec734c98c7ff432eca6"),
            lzvn: (498, "4aa54b54b33d313f1397615e2a3a26cd7f0e074975bdfaeda441b74571e1cfec")
        ),
        Reference(
            "3 values, 70000 bytes", { Inputs.biased(70000, seed: 12, alphabet: 3) },
            lzfse: (18160, "39d5d50263e39a617a18c5fe5b5bf83274295ccd9e6eb5bdeb51751fcca3e0d5"),
            lzvn: (30301, "805b4e43fd26bb572855544ba4aca2652ff42dbbddd385ab5b5f37a844586cb3")
        ),
        Reference(
            "3000-byte pattern, 70000 bytes", { Inputs.repeating(Inputs.random(3000, seed: 8), count: 70000) },
            lzfse: (3280, "743227dc0f27849b928fa147074d4af7894bb421971df7958237a21a87390784"),
            lzvn: (3535, "239c47e27fd7814866b8d93779708df66bb4c2abce78814ffe243f4d0c184cb9")
        ),
        Reference(
            "4 values, 100000 bytes", { Inputs.biased(100_000, seed: 5, alphabet: 4) },
            lzfse: (31147, "6a99378234592cd11eb1aa0fe3fd8bb2a07391b74cc65e94381d9792ca372dbb"),
            lzvn: (47587, "7b0474e02f35815199ea9fd59b43ecd60df19a35c61db02ee52fe1a7f85311dd")
        ),
        Reference(
            "text, 200000 bytes", { Inputs.text(200_000, seed: 9) },
            lzfse: (43191, "b0e9a5a8e6704257b45fe65099c388256ab945f98995b2e2fc42d7363be7d045"),
            lzvn: (58492, "9d2ca325c8493295601d15c87bd34e3cfac0db9b51b35719287692b3efeca7c8")
        ),
        Reference(
            "random, 300000 bytes", { Inputs.random(300_000, seed: 7) },
            lzfse: (303105, "edce8e02a7ff08cc09a1fa18858eaed1a251d77dee2b7fef5952c50c07cbb4bb"),
            lzvn: (303007, "280d8c933cb4d9ea8e661fa6885e71a9d941d42b7f777bff35c12aa42d8e4e82")
        ),
        Reference(
            "planar image, 420208 bytes", { Inputs.planarImage(seed: 6) },
            lzfse: (129138, "b6c4a48f08da2fe9261eedaebba98bb138957a6de9698031d8ccfe2ce60ab9fc"),
            lzvn: (168674, "5138e02604d6220c22adffe176cb559ba12cf40491595fc3be134c0368a140bd")
        ),
        Reference(
            "zeros, 600000 bytes", { [UInt8](repeating: 0, count: 600_000) },
            lzfse: (496, "65ad21cd797be31fb746083f9b333e8efa2c811c81c47dd24d52b35eba977a35"),
            lzvn: (4442, "71feb611325b5c88fe0066dff97706999da30a8ee7eda8a46876be9299256d3e")
        ),
    ]

    @Test(arguments: references)
    func lzfseMatchesTheReference(_ reference: Reference) {
        let output = LZFSE.encode(reference.input())
        #expect(output.count == reference.lzfse.length)
        #expect(Self.sha256(output) == reference.lzfse.sha256)
    }

    @Test(arguments: references)
    func lzvnMatchesTheReference(_ reference: Reference) {
        let output = LZVN.encode(reference.input())
        #expect(output.count == reference.lzvn.length)
        #expect(Self.sha256(output) == reference.lzvn.sha256)
    }

    @Test func inputsUnder8BytesAreStoredRaw() {
        #expect(LZFSE.encode([]) == Array("bvx-".utf8) + [0, 0, 0, 0] + Array("bvx$".utf8))
        #expect(LZFSE.encode([0x61]) == Array("bvx-".utf8) + [1, 0, 0, 0, 0x61] + Array("bvx$".utf8))
    }

    @Test func lzvnStreamsEndWithTheEndOfStreamOpcode() {
        let endOfStream: [UInt8] = [0x06, 0, 0, 0, 0, 0, 0, 0]
        #expect(LZVN.encode([]) == endOfStream)
        #expect(LZVN.encode(Array("abcde".utf8)) == [0xE5] + Array("abcde".utf8) + endOfStream)
    }

    /// The blocks of the reference outputs. LZVN encodes inputs under 4096 bytes, and its block
    /// is kept whenever its payload is smaller than the input (100 bytes of text give 113 bytes,
    /// a raw block would be 112). Inputs of 4096 bytes or more that do not compress get bvx2
    /// blocks larger than themselves: `lzfse -encode` retries with a destination twice the
    /// input's size, where they fit.
    static let blockCases: [(name: String, magics: [String])] = [
        ("text, 100 bytes", ["bvxn", "bvx$"]),
        ("random, 100 bytes", ["bvx-", "bvx$"]),
        ("8 zeros", ["bvx-", "bvx$"]),
        ("text, 4095 bytes", ["bvxn", "bvx$"]),
        ("text, 4096 bytes", ["bvx2", "bvx$"]),
        ("random, 4097 bytes", ["bvx2", "bvx$"]),
        ("4 values, 100000 bytes", ["bvx2", "bvx2", "bvx$"]),
        ("random, 300000 bytes", Array(repeating: "bvx2", count: 8) + ["bvx$"]),
        ("planar image, 420208 bytes", Array(repeating: "bvx2", count: 6) + ["bvx$"]),
    ]

    @Test(arguments: blockCases)
    func blocks(name: String, magics: [String]) throws {
        let reference = try #require(Self.references.first { $0.name == name })
        #expect(Self.blockMagics(LZFSE.encode(reference.input())) == magics)
    }

    static func sha256(_ bytes: [UInt8]) -> String {
        SHA256.digest(bytes).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    /// The magic of each block of an LZFSE stream, walking the block headers; "?" marks bytes
    /// that are not a block.
    static func blockMagics(_ stream: [UInt8]) -> [String] {
        func field(_ offset: Int, _ size: Int) -> Int {
            (0..<size).reduce(0) { $0 | Int(stream[offset + $1]) << (8 * $1) }
        }
        var magics: [String] = []
        var i = 0
        while i + 4 <= stream.count {
            let magic = String(decoding: stream[i..<(i + 4)], as: UTF8.self)
            magics.append(magic)
            switch magic {
            case "bvx$":
                return i + 4 == stream.count ? magics : magics + ["?"]
            case "bvx-":
                i += 8 + field(i + 4, 4)
            case "bvxn":
                i += 12 + field(i + 8, 4)
            case "bvx2":
                let literalPayload = (field(i + 8, 8) >> 20) & 0xF_FFFF
                let lmdPayload = (field(i + 16, 8) >> 40) & 0xF_FFFF
                i += field(i + 24, 4) + literalPayload + lmdPayload
            default:
                return magics + ["?"]
            }
        }
        return magics + ["?"]
    }
}
