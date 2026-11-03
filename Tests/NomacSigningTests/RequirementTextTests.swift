import Testing
@testable import NomacSigning

/// Requirement programs printed as `codesign -r- --display` prints them (observed with an
/// Apple Development signature and Swift's back-deployment library; the names here are made up).
@Suite struct RequirementTextTests {
    static func word(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * (3 - UInt32($0)))) } }

    static func data(_ bytes: [UInt8]) -> [UInt8] {
        word(UInt32(bytes.count)) + bytes + [UInt8](repeating: 0, count: (4 - bytes.count % 4) % 4)
    }

    static func requirement(_ expression: [UInt8]) -> [UInt8] {
        word(0xfade_0c00) + word(UInt32(12 + expression.count)) + word(1) + expression
    }

    /// The designated requirement of an iOS development signature: identifier, Apple's generic
    /// anchor, the leaf's common name and the intermediate's marker 1.2.840.113635.100.6.2.1.
    @Test func printsAnAppleDevelopmentRequirement() throws {
        let expression = Self.word(6) + Self.word(2) + Self.data(Array("tool".utf8)) + Self.word(6) + Self.word(15) + Self.word(6)
            + Self.word(11) + Self.word(0) + Self.data(Array("subject.CN".utf8)) + Self.word(1) + Self.data(Array("Apple Development: nomac Test (ABCDE12345)".utf8))
            + Self.word(14) + Self.word(1) + Self.data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x02, 0x01]) + Self.word(0)
        #expect(try RequirementText.text(Self.requirement(expression), path: "tool") == "identifier tool and anchor apple generic and "
            + "certificate leaf[subject.CN] = \"Apple Development: nomac Test (ABCDE12345)\" and "
            + "certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */")
    }

    @Test func printsHashesNegationsAndQuotedIdentifiers() throws {
        let expression = Self.word(7) + Self.word(8) + Self.data([0xab, 0xcd]) + Self.word(9) + Self.word(2) + Self.data(Array("com.example".utf8))
        #expect(try RequirementText.text(Self.requirement(expression), path: "x") == "cdhash H\"abcd\" or ! identifier \"com.example\"")
    }
}
