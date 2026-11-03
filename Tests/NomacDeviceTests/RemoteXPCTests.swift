import Foundation
import Testing
@testable import NomacDevice

/// RemoteXPC's encodings as pymobiledevice3's `xpc_message.py` and `remotexpc.py` write them
/// (docs/formats/remotexpc.md).
@Suite struct RemoteXPCTests {
    @Test func dictionaryBytes() {
        let object = XPCObject.dictionary([.init("a", .bool(true)), .init("bc", .string("xyz"))])
        let entries: [UInt8] = [2, 0, 0, 0]
            + Array("a".utf8) + [0, 0, 0] + [0x00, 0x20, 0, 0, 1, 0, 0, 0]
            + Array("bc".utf8) + [0, 0] + [0x00, 0x90, 0, 0, 4, 0, 0, 0] + Array("xyz".utf8) + [0]
        #expect(object.encoded() == [0x00, 0xf0, 0, 0] + [UInt8(entries.count), 0, 0, 0] + entries)
    }

    @Test func everyKindRoundTrips() throws {
        let object = XPCObject.dictionary([
            .init("null", .null), .init("int", .int64(-2)), .init("uint", .uint64(1 << 40)), .init("double", .double(0.5)),
            .init("date", .date(1_700_000_000_000_000_000)), .init("data", .data([1, 2, 3, 4, 5])),
            .init("uuid", .uuid(Array(0..<16))), .init("array", .array([.string("é"), .bool(false)])),
        ])
        #expect(try XPCObject.decode(object.encoded()) == object)
    }

    @Test func messageFrame() throws {
        let message = XPCMessage(flags: [.alwaysSet, .dataPresent, .wantingReply], messageID: 5, payload: .dictionary([.init("k", .uint64(1))]))
        let bytes = message.encoded()
        #expect(Array(bytes[0..<8]) == [0x92, 0x0b, 0xb0, 0x29, 0x01, 0x01, 0x01, 0x00])
        #expect(Array(bytes[24..<32]) == [0x42, 0x37, 0x13, 0x42, 5, 0, 0, 0])
        #expect(try XPCMessage.size(bytes[...]) == bytes.count)
        #expect(try XPCMessage.decode(bytes) == message)
        #expect(XPCMessage(flags: [.alwaysSet, .initHandshake]).encoded().count == 24)
    }

    @Test func http2FrameHeader() throws {
        let frame = HTTP2Frame.windowUpdate(stream: 0, increment: 16 * 1024 * 1024 - 65_535)
        #expect(frame.encoded() == [0, 0, 4, 8, 0, 0, 0, 0, 0, 0, 0xff, 0, 0x01])
        #expect(try HTTP2Frame.read(from: ReplayStream(bytes: frame.encoded())) == frame)
        #expect(HTTP2Frame.settings([(identifier: 3, value: 100), (identifier: 4, value: 16_777_216)]).settingsValues == [3: 100, 4: 16_777_216])
    }

    @Test func handshakeFramesAndFirstMessage() throws {
        let handshake = XPCObject.dictionary([
            .init("MessageType", .string("Handshake")),
            .init("Services", .dictionary([.init("com.apple.coredevice.appservice", .dictionary([.init("Port", .string("49152"))]))])),
        ])
        let message = XPCMessage(flags: [.alwaysSet, .dataPresent], messageID: 0, payload: handshake).encoded()
        let device = HTTP2Frame.settings([(identifier: 4, value: 1_048_576)]).encoded()
            + HTTP2Frame(.data, stream: 1, payload: Array(message.prefix(30))).encoded()
            + HTTP2Frame(.data, stream: 1, payload: Array(message.dropFirst(30))).encoded()
        let stream = ReplayStream(bytes: device)
        let connection = try RemoteXPCConnection(stream: stream)
        #expect(stream.written.starts(with: Array("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))
        let sent = ReplayStream(bytes: Array(stream.written.dropFirst(24)))
        let kinds = try (0..<8).map { _ in try HTTP2Frame.read(from: sent) }.map { "\($0.kind!)#\($0.stream)" }
        #expect(kinds == ["settings#0", "windowUpdate#0", "headers#1", "data#1", "headers#3", "data#1", "data#3", "settings#0"])
        let received = try connection.receive()
        #expect(try RemoteServiceDiscovery.servicePorts(received.payload!) == ["com.apple.coredevice.appservice": 49152])
    }

    @Test func coreDeviceTunnelHandshake() throws {
        #expect(CoreDeviceTunnel.handshakeRequest() == Array("CDTunnel".utf8) + [0, 48] + Array("{\"type\": \"clientHandshakeRequest\", \"mtu\": 16000}".utf8))
        let reply = Array("""
        {"type": "serverHandshakeResponse", "clientParameters": {"address": "fd00::2", "netmask": "ffff:ffff:ffff:ffff::", "mtu": 16000}, \
        "serverAddress": "fd00::1", "serverRSDPort": 58783}
        """.utf8)
        let parameters = try CoreDeviceTunnel.handshake(on: ReplayStream(bytes: CoreDeviceTunnel.packet(reply)))
        #expect(parameters == CoreDeviceTunnel.Parameters(clientAddress: "fd00::2", mtu: 16000, serverAddress: "fd00::1", serverRSDPort: 58783))
    }
}

/// CoreDevice's invocation and the app service's launch, as pymobiledevice3 sends them.
@Suite struct CoreDeviceServiceTests {
    @Test func launchRequest() throws {
        let request = CoreDeviceService.request(feature: AppService.launchFeature, input: AppService.launchInput(bundleIdentifier: "org.nomac.signing"),
                                                deviceIdentifier: "D", invocationIdentifier: "I")
        #expect(request["CoreDevice.coreDeviceVersion"]?["components"] == .array([.uint64(629), .uint64(3)]))
        #expect(request["CoreDevice.input"]?["applicationSpecifier"]?["bundleIdentifier"]?["_0"] == .string("org.nomac.signing"))
        let platformOptions = request["CoreDevice.input"]?["options"]?["platformSpecificOptions"]
        #expect(platformOptions == .data(Array("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict/>
        </plist>

        """.utf8)))
        #expect(try XPCObject.decode(request.encoded()) == request)
    }

    /// With a console, the identifier openstdiosocket sent names all three standard streams.
    @Test func launchRequestWithAConsole() throws {
        let identifier = [UInt8](0..<16)
        let input = AppService.launchInput(bundleIdentifier: "org.nomac.signing", standardIO: identifier)
        for stream in ["standardInput", "standardOutput", "standardError"] {
            #expect(input["standardIOIdentifiers"]?[stream] == .uuid(identifier))
        }
        #expect(AppService.launchInput(bundleIdentifier: "org.nomac.signing")["standardIOIdentifiers"] == .dictionary([]))
        #expect(try XPCObject.decode(input.encoded()) == input)
    }

    @Test func outputAndErrors() throws {
        let reply = XPCObject.dictionary([.init("CoreDevice.output", .dictionary([.init("processToken", .dictionary([.init("processIdentifier", .int64(812))]))]))])
        #expect(AppService.processIdentifier(try CoreDeviceService.output(reply, of: AppService.launchFeature)) == 812)
        let refusal = XPCObject.dictionary([.init("CoreDevice.error", .dictionary([
            .init("code", .int64(1)), .init("userInfo", .dictionary([.init("NSLocalizedDescription", .string("The app is not installed."))])),
        ]))])
        #expect(throws: (any Error).self) { try CoreDeviceService.output(refusal, of: AppService.launchFeature) }
    }
}
