import Foundation
import Testing
@testable import NomacPIF

@Suite struct PIFValueTests {
    @Test func serializesInXcodeDumpPIFFormat() {
        let value = PIFValue.array([
            .object([
                "type": .string("workspace"),
                "contents": .object(["empty": .object([:]), "list": .array([]), "path": .string("/a/b")]),
            ]),
        ])
        #expect(value.serialized() == """
        [
          {
            "contents" : {
              "empty" : {

              },
              "list" : [

              ],
              "path" : "/a/b"
            },
            "type" : "workspace"
          }
        ]
        """)
    }

    @Test func escapesLikeFoundationWithoutEscapingSlashes() {
        #expect(PIFValue.string("a\"b\\c\nd\te/f\u{01}é").serialized() == "\"a\\\"b\\\\c\\nd\\te/f\\u0001é\"")
    }

    @Test func sortsKeysLikeJSONSerializationSortedKeys() {
        // Observed in Xcode's PIF for retro-rampage: "__" sorts before "_B".
        #expect(PIFValue.keyOrder("CLANG_WARN__DUPLICATE_METHOD_MATCH", "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING"))
        #expect(PIFValue.keyOrder("a2", "a10"))
        #expect(PIFValue.keyOrder("ab", "AC"))
        #expect(PIFValue.keyOrder("A", "a"))
        #expect(!PIFValue.keyOrder("a", "A"))
        #expect(PIFValue.keyOrder("guid", "name"))
        #expect(PIFValue.keyOrder("x", "x1"))
    }

    /// Property: every serialized document parses back, with JSONSerialization, to the same value.
    @Test func serializationRoundTripsThroughJSONSerialization() throws {
        var generator = SeededGenerator(seed: 0x6E6F6D6163)
        for _ in 0..<300 {
            let value = randomValue(depth: 0, using: &generator)
            let text = value.serialized()
            let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
            #expect(PIFValue(json: parsed) == value, "round trip failed for \(text)")
        }
    }

    private func randomValue(depth: Int, using generator: inout SeededGenerator) -> PIFValue {
        let choice = depth > 3 ? 0 : Int.random(in: 0..<4, using: &generator)
        switch choice {
        case 0: return .string(randomString(using: &generator))
        case 1: return .int(Int.random(in: -1000...1000, using: &generator))
        case 2: return .array((0..<Int.random(in: 0..<4, using: &generator)).map { _ in randomValue(depth: depth + 1, using: &generator) })
        default:
            var members: [String: PIFValue] = [:]
            for _ in 0..<Int.random(in: 0..<4, using: &generator) {
                members[randomString(using: &generator)] = randomValue(depth: depth + 1, using: &generator)
            }
            return .object(members)
        }
    }

    private func randomString(using generator: inout SeededGenerator) -> String {
        let alphabet = Array("abcXYZ_09 /\\\"\n\té$()")
        return String((0..<Int.random(in: 0..<8, using: &generator)).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
    }
}

/// A deterministic random number generator (SplitMix64) for property tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension PIFValue {
    /// Converts a `JSONSerialization` result back to a PIF value (tests only).
    init?(json: Any) {
        switch json {
        case let string as String: self = .string(string)
        case let number as NSNumber: self = .int(number.intValue)
        case let array as [Any]:
            var elements: [PIFValue] = []
            for element in array {
                guard let value = PIFValue(json: element) else { return nil }
                elements.append(value)
            }
            self = .array(elements)
        case let dict as [String: Any]:
            var members: [String: PIFValue] = [:]
            for (key, element) in dict {
                guard let value = PIFValue(json: element) else { return nil }
                members[key] = value
            }
            self = .object(members)
        default: return nil
        }
    }
}
