import Foundation
import NomacCore

/// The HTTP/2 frames RemoteXPC uses (RFC 9113): a 9-byte header (24-bit length, type, flags,
/// 31-bit stream), then the payload. RemoteXPC's HEADERS frames carry no header block, so no
/// HPACK is needed.
public struct HTTP2Frame: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        case data = 0x0
        case headers = 0x1
        case rstStream = 0x3
        case settings = 0x4
        case ping = 0x6
        case goAway = 0x7
        case windowUpdate = 0x8
    }

    static let endHeaders: UInt8 = 0x4
    static let acknowledgement: UInt8 = 0x1
    static let preface = Array("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)
    static let headerSize = 9
    /// The largest payload either side accepts without a SETTINGS_MAX_FRAME_SIZE.
    static let maximumPayload = 16_384

    public var type: UInt8
    public var flags: UInt8
    public var stream: UInt32
    public var payload: [UInt8]

    public init(_ kind: Kind, flags: UInt8 = 0, stream: UInt32 = 0, payload: [UInt8] = []) {
        self.init(type: kind.rawValue, flags: flags, stream: stream, payload: payload)
    }

    init(type: UInt8, flags: UInt8, stream: UInt32, payload: [UInt8]) {
        self.type = type
        self.flags = flags
        self.stream = stream
        self.payload = payload
    }

    public var kind: Kind? { Kind(rawValue: type) }

    public static func settings(_ values: [(identifier: UInt16, value: UInt32)]) -> HTTP2Frame {
        HTTP2Frame(.settings, payload: values.flatMap { bigEndian($0.identifier) + bigEndian($0.value) })
    }

    public static func windowUpdate(stream: UInt32, increment: UInt32) -> HTTP2Frame {
        HTTP2Frame(.windowUpdate, stream: stream, payload: bigEndian(increment))
    }

    public func encoded() -> [UInt8] {
        Array(Self.bigEndian(UInt32(payload.count)).dropFirst()) + [type, flags] + Self.bigEndian(stream & 0x7fff_ffff) + payload
    }

    public static func read(from stream: ByteStream) throws -> HTTP2Frame {
        let header = try stream.read(headerSize)
        let length = Int(header[0]) << 16 | Int(header[1]) << 8 | Int(header[2])
        let identifier = header[5...8].reduce(UInt32(0)) { $0 << 8 | UInt32($1) } & 0x7fff_ffff
        return HTTP2Frame(type: header[3], flags: header[4], stream: identifier, payload: try stream.read(length))
    }

    /// A SETTINGS frame's values, by identifier.
    var settingsValues: [UInt16: UInt32] {
        Dictionary(stride(from: 0, to: payload.count - 5, by: 6).map { offset in
            (UInt16(payload[offset]) << 8 | UInt16(payload[offset + 1]),
             payload[offset + 2..<offset + 6].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        }) { _, last in last }
    }

    static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
}

/// A RemoteXPC connection, as RemoteServiceDiscovery and the CoreDevice services speak it
/// (docs/formats/remotexpc.md): HTTP/2 with requests on stream 1 and replies on stream 3, each
/// DATA payload a sequence of XPC messages. The handshake's frames are in the order
/// pymobiledevice3 records devicectl sending them.
public final class RemoteXPCConnection {
    static let rootStream: UInt32 = 1
    static let replyStream: UInt32 = 3
    static let initialWindow: UInt32 = 16 * 1024 * 1024
    static let defaultWindow = 65_535

    private let stream: ByteStream
    private var nextMessageID: UInt64 = 0
    private var buffers: [UInt32: [UInt8]] = [:]
    private var unacknowledged = 0
    /// The bytes the device lets nomac send: on the connection, and on stream 1.
    private var connectionWindow = defaultWindow
    private var streamWindow = defaultWindow
    private var initialStreamWindow = defaultWindow

    public init(stream: ByteStream) throws {
        self.stream = stream
        try stream.write(HTTP2Frame.preface)
        try send(.settings([(identifier: 3, value: 100), (identifier: 4, value: Self.initialWindow)]))
        try send(.windowUpdate(stream: 0, increment: Self.initialWindow - UInt32(Self.defaultWindow)))
        try send(HTTP2Frame(.headers, flags: HTTP2Frame.endHeaders, stream: Self.rootStream))
        try send(.dictionary([]), wantingReply: false)
        try send(HTTP2Frame(.headers, flags: HTTP2Frame.endHeaders, stream: Self.replyStream))
        try send(HTTP2Frame(.data, stream: Self.rootStream,
                            payload: XPCMessage(flags: XPCMessage.Flags(rawValue: 0x0201)).encoded()))
        try send(HTTP2Frame(.data, stream: Self.replyStream,
                            payload: XPCMessage(flags: [.alwaysSet, .initHandshake]).encoded()))
        while true {
            let frame = try HTTP2Frame.read(from: stream)
            if frame.kind == .settings, frame.flags & HTTP2Frame.acknowledgement == 0 {
                apply(frame)
                break
            }
            try handleControl(frame)
        }
        try send(HTTP2Frame(.settings, flags: HTTP2Frame.acknowledgement))
    }

    /// Sends `payload` as the next message on stream 1.
    public func send(_ payload: XPCObject, wantingReply: Bool) throws {
        var flags: XPCMessage.Flags = .alwaysSet
        if case .dictionary(let entries) = payload, !entries.isEmpty { flags.insert(.dataPresent) }
        if wantingReply { flags.insert(.wantingReply) }
        let message = XPCMessage(flags: flags, messageID: nextMessageID, payload: payload).encoded()
        let window = min(connectionWindow, streamWindow)
        guard message.count <= window else {
            throw NomacError("a RemoteXPC message of \(message.count) bytes exceeds the device's window of \(window)")
        }
        for start in stride(from: 0, to: message.count, by: HTTP2Frame.maximumPayload) {
            try send(HTTP2Frame(.data, stream: Self.rootStream, payload: Array(message[start..<min(start + HTTP2Frame.maximumPayload, message.count)])))
        }
        connectionWindow -= message.count
        streamWindow -= message.count
        nextMessageID = (nextMessageID + 1) | 1
    }

    /// The next message with a non-empty dictionary, on either stream; others are skipped, as
    /// pymobiledevice3's `receive_response` does.
    public func receive() throws -> XPCMessage {
        while true {
            for (identifier, buffer) in buffers {
                guard let size = try XPCMessage.size(buffer[...]), buffer.count >= size else { continue }
                buffers[identifier] = Array(buffer.dropFirst(size))
                let message = try XPCMessage.decode(Array(buffer.prefix(size)))
                if case .dictionary(let entries)? = message.payload, !entries.isEmpty { return message }
            }
            let frame = try HTTP2Frame.read(from: stream)
            guard frame.kind == .data else {
                try handleControl(frame)
                continue
            }
            buffers[frame.stream, default: []] += frame.payload
            unacknowledged += frame.payload.count
            if unacknowledged >= Int(Self.initialWindow / 2) {
                try send(.windowUpdate(stream: 0, increment: UInt32(unacknowledged)))
                try send(.windowUpdate(stream: frame.stream, increment: UInt32(unacknowledged)))
                unacknowledged = 0
            }
        }
    }

    private func handleControl(_ frame: HTTP2Frame) throws {
        switch frame.kind {
        case .settings where frame.flags & HTTP2Frame.acknowledgement == 0:
            apply(frame)
            try send(HTTP2Frame(.settings, flags: HTTP2Frame.acknowledgement))
        case .windowUpdate:
            let increment = Int(frame.payload.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } & 0x7fff_ffff)
            if frame.stream == 0 { connectionWindow += increment }
            if frame.stream == Self.rootStream { streamWindow += increment }
        case .ping where frame.flags & HTTP2Frame.acknowledgement == 0:
            try send(HTTP2Frame(.ping, flags: HTTP2Frame.acknowledgement, payload: frame.payload))
        case .goAway:
            throw NomacError("the device closed the RemoteXPC connection (GOAWAY)")
        case .rstStream:
            throw NomacError("the device reset RemoteXPC stream \(frame.stream)")
        default:
            break
        }
    }

    /// A new initial window moves stream 1's window by the difference (RFC 9113, 6.9.2).
    private func apply(_ settings: HTTP2Frame) {
        guard let window = settings.settingsValues[4] else { return }
        streamWindow += Int(window) - initialStreamWindow
        initialStreamWindow = Int(window)
    }

    private func send(_ frame: HTTP2Frame) throws { try stream.write(frame.encoded()) }
}
