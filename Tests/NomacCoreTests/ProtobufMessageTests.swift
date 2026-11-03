import Testing
@testable import NomacCore

@Suite struct ProtobufMessageTests {
    /// A message read and written again keeps every field, known or not, in its order.
    @Test func roundTripsEveryWireType() throws {
        let bytes: [UInt8] = [0x08, 0x96, 0x01, 0x11, 1, 2, 3, 4, 5, 6, 7, 8, 0x1A, 0x02, 0x68, 0x69, 0x25, 9, 9, 9, 9, 0x08, 0x01]
        let message = try ProtobufMessage(bytes: bytes)
        #expect(message.bytes == bytes)
        #expect(try message.integer(1) == 1)
        #expect(message.string(3) == "hi")
        #expect(try message.integers(1) == [150, 1])
    }

    /// A message field set where it is missing goes after the fields of lower numbers.
    @Test func setsAMessageFieldInNumberOrder() throws {
        var message = try ProtobufMessage(bytes: [0x0A, 0x00, 0xE2, 0x12, 0x00])
        message.set(100, message: ProtobufMessage())
        #expect(message.fields.map(\.number) == [1, 100, 300])
        #expect(message.bytes == [0x0A, 0x00, 0xA2, 0x06, 0x00, 0xE2, 0x12, 0x00])
    }

    @Test func refusesTruncatedFields() {
        #expect(throws: (any Error).self) { try ProtobufMessage(bytes: [0x0A, 0x05, 0x01]) }
        #expect(throws: (any Error).self) { try ProtobufMessage(bytes: [0x08, 0x96]) }
    }
}
