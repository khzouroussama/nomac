import Foundation
import NomacDevice
@testable import NomacDeviceTest
import Testing

/// A stream over bytes in memory: what is written is kept, what is read comes from `incoming`.
final class MemoryStream: PollableStream {
    var incoming: [UInt8] = []
    var written: [UInt8] = []

    var availableCount: Int { incoming.count }

    func write(_ bytes: [UInt8]) throws { written += bytes }

    func read(_ count: Int) throws -> [UInt8] {
        guard incoming.count >= count else { throw TestError.endOfStream }
        defer { incoming.removeFirst(count) }
        return Array(incoming.prefix(count))
    }

    enum TestError: Error { case endOfStream }
}

@Suite struct KeyedArchiveTests {
    @Test func foundationValuesRoundTrip() throws {
        let value: Archived = .array([
            .string("a"), .integer(-7), .real(1.5), .boolean(true), .null, .data([1, 2]), .set([.string("x")]),
            .keyed([("k", .string("v")), ("n", .integer(3))]), .uuid(Array(0..<16)), .url("file:///tmp/A.xctest"), .date(10),
        ])
        #expect(try KeyedArchive.decode(KeyedArchive.encode(value)) == value)
    }

    @Test func objectsKeepScalarsInlineAndObjectsByReference() throws {
        let configuration = TestManager.configuration(session: UUID(), testBundlePath: "/private/var/App.app/PlugIns/T.xctest",
                                                      productModuleName: "T", target: nil)
        let decoded = try KeyedArchive.decode(KeyedArchive.encode(configuration))
        guard case .object(let object) = decoded else { Issue.record("not an object"); return }
        #expect(object.classes == ["XCTestConfiguration", "NSObject"])
        #expect(object["reportResultsToIDE"] == .boolean(true))
        #expect(object["testBundleURL"] == .url("file:///private/var/App.app/PlugIns/T.xctest"))
        #expect(object["initializeForUITesting"] == .boolean(false))
        #expect(object["baselineFileURL"] == .null)
    }

    @Test func foundationReadsTheArchive() throws {
        let identifier = UUID()
        let bytes = KeyedArchive.encode(.array([.string("a"), .integer(2), .keyed([("k", .uuid(TestManager.bytes(identifier)))]),
                                                .url("file:///tmp/A.xctest")]))
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: Data(bytes))
        unarchiver.requiresSecureCoding = false
        let array = try #require(unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSArray)
        #expect(array[0] as? String == "a")
        #expect((array[1] as? NSNumber)?.intValue == 2)
        #expect(((array[2] as? NSDictionary)?["k"] as? NSUUID)?.uuidString == identifier.uuidString)
        #expect((array[3] as? NSURL)?.path == "/tmp/A.xctest")
    }

    @Test func archiveLayout() throws {
        let bytes = KeyedArchive.encode(.string("_IDE_authorizeTestSessionWithProcessID:"))
        #expect(bytes.starts(with: Array("bplist00".utf8)))
        #expect(try KeyedArchive.decode(bytes) == .string("_IDE_authorizeTestSessionWithProcessID:"))
    }
}

@Suite struct DTXTests {
    @Test func messageHeaders() {
        let message = DTXMessage(kind: .dispatch, identifier: 5, channel: -1, expectsReply: true, arguments: [.int32(1)], payload: [0xAA])
        let bytes = message.encoded()
        #expect(Array(bytes[0..<4]) == [0x79, 0x5B, 0x3D, 0x1F])
        #expect(Array(bytes[4..<8]) == [32, 0, 0, 0])
        #expect(Array(bytes[8..<12]) == [0, 0, 1, 0])
        let auxiliary = DTXMessage.encode([.int32(1)])
        #expect(Array(bytes[12..<16]) == DTXMessage.little(UInt32(16 + auxiliary.count + 1)))
        #expect(Array(bytes[16..<20]) == [5, 0, 0, 0])
        #expect(Array(bytes[24..<28]) == [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(Array(bytes[28..<32]) == [1, 0, 0, 0])
        #expect(bytes[32] == 2)
        #expect(Array(bytes[36..<40]) == DTXMessage.little(UInt32(auxiliary.count)))
    }

    @Test func auxiliaryDictionary() throws {
        let arguments: [DTXArgument] = [.int32(-2), .int64(1 << 40), .double(0.25), .string("s"), .buffer([9]), .null]
        let bytes = DTXMessage.encode(arguments)
        #expect(Array(bytes[0..<8]) == [0xF0, 1, 0, 0, 0, 0, 0, 0])
        #expect(Array(bytes[16..<24]) == [10, 0, 0, 0, 3, 0, 0, 0])
        #expect(try DTXMessage.decode(auxiliary: bytes) == arguments)
        #expect(DTXMessage.encode([]).isEmpty)
    }

    @Test func fragmentedMessagesAreReassembled() throws {
        let payload = [UInt8](repeating: 7, count: DTXMessage.maximumFragmentSize * 2 + 10)
        let message = DTXMessage(kind: .data, identifier: 9, channel: 3, payload: payload)
        let stream = MemoryStream()
        stream.incoming = message.encoded()
        let connection = DTXConnection(stream: stream)
        let received = try connection.next()
        #expect(received?.payload == payload)
        #expect(received?.identifier == 9)
        #expect(stream.incoming.isEmpty)
    }

    @Test func partialMessagesWait() throws {
        let stream = MemoryStream()
        let bytes = DTXMessage(kind: .object, identifier: 1, conversation: 1, channel: 1, payload: KeyedArchive.encode(.integer(4))).encoded()
        stream.incoming = Array(bytes.prefix(40))
        let connection = DTXConnection(stream: stream)
        #expect(try connection.next() == nil)
        stream.incoming += bytes.dropFirst(40)
        #expect(try connection.next()?.payloadValue() == .integer(4))
    }

    @Test func channelCodesAndReplies() throws {
        let stream = MemoryStream()
        let connection = DTXConnection(stream: stream)
        stream.incoming = DTXMessage(kind: .dispatch, identifier: 1, channel: 0, expectsReply: true,
                                     arguments: [.int32(1), .object(.string(TestManager.driverChannel))],
                                     payload: KeyedArchive.encode(.string("_requestChannelWithCode:identifier:"))).encoded()
            + DTXMessage(kind: .dispatch, identifier: 2, channel: 1, expectsReply: true,
                         payload: KeyedArchive.encode(.string("_XCT_didBeginExecutingTestPlan"))).encoded()
        _ = try connection.next()
        #expect(connection.channels[-1] == TestManager.driverChannel)
        let acknowledgement = stream.written
        #expect(acknowledgement.count == 48)
        #expect(Array(acknowledgement[20..<24]) == [1, 0, 0, 0])
        let event = try #require(try connection.next())
        #expect(connection.key(of: event) == -1)
        stream.written = []
        try connection.reply(to: event)
        #expect(Array(stream.written[24..<28]) == [1, 0, 0, 0])
        try connection.send("_IDE_startExecutingTestPlanWithProtocolVersion:", [.object(.integer(36))], channel: -1, expectsReply: false)
        #expect(Array(stream.written[(48 + 24)..<(48 + 28)]) == [0xFF, 0xFF, 0xFF, 0xFF])
    }
}
