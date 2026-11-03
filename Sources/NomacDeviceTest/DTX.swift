import Foundation
import NomacCore
import NomacDevice

/// An argument of a DTX message's auxiliary dictionary (docs/formats/dtx.md "Auxiliary").
public enum DTXArgument: Equatable, Sendable {
    case null
    case string(String)
    /// A keyed archive, or empty for `nil`.
    case buffer([UInt8])
    case int32(Int32)
    case int64(Int64)
    case double(Double)

    public static func object(_ value: Archived) -> DTXArgument {
        value == .null ? .buffer([]) : .buffer(KeyedArchive.encode(value))
    }

    /// The argument as a value: buffers unarchived, `nil` for an empty one.
    public func archived() throws -> Archived {
        switch self {
        case .null: .null
        case .string(let text): .string(text)
        case .buffer(let bytes): bytes.isEmpty ? .null : try KeyedArchive.decode(bytes)
        case .int32(let number): .integer(Int(number))
        case .int64(let number): .integer(Int(number))
        case .double(let number): .real(number)
        }
    }
}

/// One DTX message (docs/formats/dtx.md), as pymobiledevice3's `dtx` package and go-ios's
/// `dtx_codec` lay it out: a 32-byte fragment header, a 16-byte message header, the auxiliary
/// dictionary and the payload (a keyed archive: a dispatch's selector, a reply's value).
public struct DTXMessage: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        case ok = 0, data = 1, dispatch = 2, object = 3, error = 4, barrier = 5, primitive = 6, compressed = 7
    }

    public static let magic: UInt32 = 0x1F3D_5B79
    public static let headerSize = 32
    public static let messageHeaderSize = 16
    /// The largest fragment body pymobiledevice3 sends or reads (128 KiB).
    public static let maximumFragmentSize = 128 * 1024

    public var kind: Kind
    public var identifier: UInt32
    public var conversation: UInt32
    /// The channel code as written on the wire.
    public var channel: Int32
    public var expectsReply: Bool
    public var arguments: [DTXArgument]
    public var payload: [UInt8]

    public init(kind: Kind, identifier: UInt32, conversation: UInt32 = 0, channel: Int32, expectsReply: Bool = false,
                arguments: [DTXArgument] = [], payload: [UInt8] = []) {
        self.kind = kind
        self.identifier = identifier
        self.conversation = conversation
        self.channel = channel
        self.expectsReply = expectsReply
        self.arguments = arguments
        self.payload = payload
    }

    /// A dispatch's selector, the payload's archived string.
    public var selector: String? {
        guard kind == .dispatch, case .string(let name)? = try? KeyedArchive.decode(payload) else { return nil }
        return name
    }

    public func payloadValue() throws -> Archived {
        payload.isEmpty ? .null : try KeyedArchive.decode(payload)
    }

    /// The message's fragments as they go on the wire: one when it fits, else a header-only
    /// first fragment with the whole size and body fragments of at most 128 KiB.
    public func encoded() -> [UInt8] {
        let auxiliary = Self.encode(arguments)
        var body = [kind.rawValue, 0, 0, 0]
        body += Self.little(UInt32(auxiliary.count))
        body += Self.little(UInt64(auxiliary.count + payload.count))
        body += auxiliary + payload
        let flags: UInt32 = expectsReply ? 1 : 0
        func header(index: UInt16, count: UInt16, size: Int) -> [UInt8] {
            Self.little(Self.magic) + Self.little(UInt32(Self.headerSize)) + Self.little(index) + Self.little(count)
                + Self.little(UInt32(size)) + Self.little(identifier) + Self.little(conversation) + Self.little(channel) + Self.little(flags)
        }
        guard body.count > Self.maximumFragmentSize else { return header(index: 0, count: 1, size: body.count) + body }
        let chunks = stride(from: 0, to: body.count, by: Self.maximumFragmentSize).map { body[$0..<min($0 + Self.maximumFragmentSize, body.count)] }
        var bytes = header(index: 0, count: UInt16(chunks.count + 1), size: body.count)
        for (index, chunk) in chunks.enumerated() {
            bytes += header(index: UInt16(index + 1), count: UInt16(chunks.count + 1), size: chunk.count) + chunk
        }
        return bytes
    }

    /// The auxiliary dictionary: `0x1F0`, a zero, the body's length, then each argument after a
    /// null key; nothing when there are no arguments.
    static func encode(_ arguments: [DTXArgument]) -> [UInt8] {
        guard !arguments.isEmpty else { return [] }
        var body: [UInt8] = []
        for argument in arguments {
            body += little(UInt32(10))
            switch argument {
            case .null: body += little(UInt32(10))
            case .string(let text): body += little(UInt32(1)) + little(UInt32(text.utf8.count)) + Array(text.utf8)
            case .buffer(let bytes): body += little(UInt32(2)) + little(UInt32(bytes.count)) + bytes
            case .int32(let number): body += little(UInt32(3)) + little(number)
            case .int64(let number): body += little(UInt32(6)) + little(number)
            case .double(let number): body += little(UInt32(9)) + little(number.bitPattern)
            }
        }
        return little(UInt32(0x1F0)) + little(UInt32(0)) + little(UInt64(body.count)) + body
    }

    /// The message of a reassembled body: the message header, the auxiliary dictionary and the payload.
    static func decode(body: [UInt8], identifier: UInt32, conversation: UInt32, channel: Int32, flags: UInt32) throws -> DTXMessage {
        guard body.count >= messageHeaderSize, let kind = Kind(rawValue: body[0]) else { throw NomacError("malformed DTX message") }
        let auxiliarySize = Int(integer(body, 4) as UInt32)
        let totalSize = Int(integer(body, 8) as UInt64)
        guard totalSize == body.count - messageHeaderSize, auxiliarySize <= totalSize else { throw NomacError("malformed DTX message sizes") }
        let auxiliary = Array(body[messageHeaderSize..<(messageHeaderSize + auxiliarySize)])
        return DTXMessage(kind: kind, identifier: identifier, conversation: conversation, channel: channel, expectsReply: flags & 1 != 0,
                          arguments: try decode(auxiliary: auxiliary), payload: Array(body[(messageHeaderSize + auxiliarySize)...]))
    }

    static func decode(auxiliary bytes: [UInt8]) throws -> [DTXArgument] {
        guard !bytes.isEmpty else { return [] }
        let malformed = NomacError("malformed DTX auxiliary dictionary")
        guard bytes.count >= 16, (integer(bytes, 0) as UInt32) & 0xFF == 0xF0 else { throw malformed }
        let end = 16 + Int(integer(bytes, 8) as UInt64)
        guard end <= bytes.count else { throw malformed }
        var offset = 16
        var arguments: [DTXArgument] = []
        func next() throws -> DTXArgument {
            guard offset + 4 <= end else { throw malformed }
            let type = integer(bytes, offset) as UInt32
            offset += 4
            func take(_ count: Int) throws -> [UInt8] {
                guard count >= 0, offset + count <= end else { throw malformed }
                defer { offset += count }
                return Array(bytes[offset..<(offset + count)])
            }
            switch type & 0xFF {
            case 10: return .null
            case 1, 2:
                let length = Int(integer(try take(4), 0) as UInt32)
                let content = try take(length)
                return type & 0xFF == 1 ? .string(String(decoding: content, as: UTF8.self)) : .buffer(content)
            case 3: return .int32(integer(try take(4), 0))
            case 4: return .int32(Int32(bitPattern: integer(try take(4), 0)))
            case 5: return .int64(Int64(integer(try take(4), 0) as Int32))
            case 6: return .int64(integer(try take(8), 0))
            case 9: return .double(Double(bitPattern: integer(try take(8), 0)))
            default: throw NomacError("unknown DTX argument type \(type)")
            }
        }
        while offset < end {
            _ = try next()
            arguments.append(try next())
        }
        return arguments
    }

    static func little<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian, Array.init) }

    static func integer<T: FixedWidthInteger>(_ bytes: [UInt8], _ offset: Int) -> T {
        (0..<MemoryLayout<T>.size).reversed().reduce(T.zero) { $0 << 8 | T(truncatingIfNeeded: bytes[offset + $1]) }
    }
}

/// A byte stream whose buffered bytes can be counted, so several connections can be read
/// without blocking on one of them (the CoreDevice tunnel's TCP connections).
public protocol PollableStream: ByteStream {
    var availableCount: Int { get }
}

/// A DTX connection (docs/formats/dtx.md "Channels"): channel 0 is the connection's own;
/// `_requestChannelWithCode:identifier:` opens others. A channel this side opens has a positive
/// code, one the peer opens is stored negated; a message is sent with the channel's code when it
/// starts a conversation and with its negation when it replies, and read the other way round.
public final class DTXConnection {
    private let stream: PollableStream
    private var nextIdentifier: UInt32 = 1
    private var nextChannel: Int32 = 1
    private var pendingHeader: (index: UInt16, count: UInt16, size: Int, identifier: UInt32, conversation: UInt32, channel: Int32, flags: UInt32)?
    private var assembling: [UInt32: (count: UInt16, received: UInt16, body: [UInt8])] = [:]
    /// Channels by code: the identifiers this side and the peer opened.
    public private(set) var channels: [Int32: String] = [0: ""]

    public init(stream: PollableStream) {
        self.stream = stream
    }

    /// Sends a dispatch of `selector` with `arguments` on `channel`; returns its identifier.
    @discardableResult
    public func send(_ selector: String, _ arguments: [DTXArgument] = [], channel: Int32, expectsReply: Bool = true) throws -> UInt32 {
        let identifier = nextIdentifier
        nextIdentifier += 1
        try stream.write(DTXMessage(kind: .dispatch, identifier: identifier, channel: channel, expectsReply: expectsReply,
                                    arguments: arguments, payload: KeyedArchive.encode(.string(selector))).encoded())
        return identifier
    }

    /// Replies to `message`: with an archived value, or a bare acknowledgement.
    public func reply(to message: DTXMessage, with value: Archived? = nil) throws {
        let channel = -key(of: message)
        let reply = if let value {
            DTXMessage(kind: .object, identifier: message.identifier, conversation: message.conversation + 1, channel: channel,
                       payload: KeyedArchive.encode(value))
        } else {
            DTXMessage(kind: .ok, identifier: message.identifier, conversation: message.conversation + 1, channel: channel)
        }
        try stream.write(reply.encoded())
    }

    /// The channel `message` belongs to, by this side's code.
    public func key(of message: DTXMessage) -> Int32 {
        message.conversation % 2 == 0 ? -message.channel : message.channel
    }

    /// Opens a channel to the peer's service `identifier`, waiting for the peer's answer.
    public func openChannel(_ identifier: String, wait: () throws -> Void) throws -> Int32 {
        let code = nextChannel
        nextChannel += 1
        let request = try send("_requestChannelWithCode:identifier:", [.int32(code), .object(.string(identifier))], channel: 0)
        _ = try reply(to: request, wait: wait)
        channels[code] = identifier
        return code
    }

    /// Waits for the reply to the message `identifier`, handing other messages to `handle`.
    public func reply(to identifier: UInt32, wait: () throws -> Void, handle: ((DTXMessage) throws -> Void)? = nil) throws -> DTXMessage {
        while true {
            guard let message = try next() else {
                try wait()
                continue
            }
            if message.conversation % 2 == 1, message.identifier == identifier {
                if message.kind == .error {
                    throw NomacError("the device refused a DTX request: \(Self.describe(try? message.payloadValue()))")
                }
                return message
            }
            try handle?(message)
        }
    }

    /// The next complete message if its bytes have arrived. A peer's channel request is
    /// recorded and acknowledged here; the message is still returned.
    public func next() throws -> DTXMessage? {
        while true {
            if pendingHeader == nil {
                guard stream.availableCount >= DTXMessage.headerSize else { return nil }
                let header = try stream.read(DTXMessage.headerSize)
                guard DTXMessage.integer(header, 0) as UInt32 == DTXMessage.magic else { throw NomacError("not a DTX fragment") }
                let headerSize = Int(DTXMessage.integer(header, 4) as UInt32)
                if headerSize > DTXMessage.headerSize { _ = try stream.read(headerSize - DTXMessage.headerSize) }
                pendingHeader = (DTXMessage.integer(header, 8), DTXMessage.integer(header, 10), Int(DTXMessage.integer(header, 12) as UInt32),
                                 DTXMessage.integer(header, 16), DTXMessage.integer(header, 20), DTXMessage.integer(header, 24),
                                 DTXMessage.integer(header, 28))
            }
            guard let header = pendingHeader else { return nil }
            if header.index == 0 && header.count > 1 {
                assembling[header.identifier] = (header.count, 1, [])
                pendingHeader = nil
                continue
            }
            guard stream.availableCount >= header.size else { return nil }
            let body = try stream.read(header.size)
            pendingHeader = nil
            var complete = body
            if header.count > 1 {
                guard var partial = assembling[header.identifier] else { throw NomacError("a DTX fragment of an unknown message") }
                partial.body += body
                partial.received += 1
                guard partial.received == partial.count else {
                    assembling[header.identifier] = partial
                    continue
                }
                assembling[header.identifier] = nil
                complete = partial.body
            }
            let message = try DTXMessage.decode(body: complete, identifier: header.identifier, conversation: header.conversation,
                                                channel: header.channel, flags: header.flags)
            if message.channel == 0, message.selector == "_requestChannelWithCode:identifier:", message.arguments.count == 2,
               case .int32(let code) = message.arguments[0], case .string(let identifier) = try message.arguments[1].archived() {
                channels[-code] = identifier
                if message.expectsReply { try reply(to: message) }
            }
            return message
        }
    }

    static func describe(_ value: Archived?) -> String {
        guard let value else { return "an unreadable error" }
        if case .object(let error) = value, let description = error["NSUserInfo"]?["NSLocalizedDescription"]?.string {
            return description
        }
        return "\(value)"
    }
}
