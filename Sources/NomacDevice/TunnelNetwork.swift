#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import NomacCore

/// A TCP segment (RFC 9293) in an IPv6 packet (RFC 8200), as the CoreDevice tunnel carries
/// them: one packet per write, back to back, each read by its header's payload length.
public struct TCPSegment: Equatable, Sendable {
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let fin = Flags(rawValue: 0x01)
        public static let syn = Flags(rawValue: 0x02)
        public static let rst = Flags(rawValue: 0x04)
        public static let psh = Flags(rawValue: 0x08)
        public static let ack = Flags(rawValue: 0x10)
    }

    static let ipv6HeaderSize = 40
    static let tcpProtocol: UInt8 = 6

    public var sourcePort: UInt16
    public var destinationPort: UInt16
    public var sequence: UInt32
    public var acknowledgement: UInt32
    public var flags: Flags
    public var window: UInt16
    /// The maximum segment size option, sent with SYN.
    public var maximumSegmentSize: UInt16?
    public var payload: [UInt8]

    public init(sourcePort: UInt16, destinationPort: UInt16, sequence: UInt32, acknowledgement: UInt32, flags: Flags,
                window: UInt16, maximumSegmentSize: UInt16? = nil, payload: [UInt8] = []) {
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.sequence = sequence
        self.acknowledgement = acknowledgement
        self.flags = flags
        self.window = window
        self.maximumSegmentSize = maximumSegmentSize
        self.payload = payload
    }

    /// The IPv6 packet from `source` to `destination` (16 bytes each) carrying the segment.
    public func packet(from source: [UInt8], to destination: [UInt8]) -> [UInt8] {
        let options: [UInt8] = maximumSegmentSize.map { [2, 4] + Self.bigEndian($0) } ?? []
        var segment = Self.bigEndian(sourcePort) + Self.bigEndian(destinationPort) + Self.bigEndian(sequence)
            + Self.bigEndian(acknowledgement) + [UInt8((20 + options.count) / 4) << 4, flags.rawValue] + Self.bigEndian(window)
            + [0, 0, 0, 0] + options + payload
        let checksum = Self.checksum(segment, from: source, to: destination)
        segment[16] = UInt8(checksum >> 8)
        segment[17] = UInt8(checksum & 0xff)
        return [0x60, 0, 0, 0] + Self.bigEndian(UInt16(segment.count)) + [Self.tcpProtocol, 64] + source + destination + segment
    }

    /// The segment of an IPv6 packet with its source and destination, or nil for a packet that
    /// is not TCP or whose checksum is wrong.
    public static func parse(_ packet: [UInt8]) -> (source: [UInt8], destination: [UInt8], segment: TCPSegment)? {
        guard packet.count >= ipv6HeaderSize + 20, packet[0] >> 4 == 6, packet[6] == tcpProtocol else { return nil }
        let source = Array(packet[8..<24]), destination = Array(packet[24..<40])
        let segment = Array(packet[ipv6HeaderSize...])
        let headerLength = Int(segment[12] >> 4) * 4
        guard headerLength >= 20, headerLength <= segment.count, checksum(segment, from: source, to: destination) == 0 else { return nil }
        var maximumSegmentSize: UInt16?
        var offset = 20
        while offset < headerLength {
            let kind = segment[offset]
            if kind == 0 { break }
            if kind == 1 { offset += 1; continue }
            guard offset + 1 < headerLength else { break }
            let length = Int(segment[offset + 1])
            if kind == 2, length == 4, offset + 4 <= headerLength { maximumSegmentSize = UInt16(segment[offset + 2]) << 8 | UInt16(segment[offset + 3]) }
            offset += max(length, 2)
        }
        return (source, destination, TCPSegment(
            sourcePort: integer(segment[0..<2]), destinationPort: integer(segment[2..<4]), sequence: integer(segment[4..<8]),
            acknowledgement: integer(segment[8..<12]), flags: Flags(rawValue: segment[13] & 0x3f), window: integer(segment[14..<16]),
            maximumSegmentSize: maximumSegmentSize, payload: Array(segment[headerLength...])))
    }

    /// The Internet checksum (RFC 1071) of the segment and IPv6's pseudo-header; 0 when
    /// computed over a segment that carries its checksum.
    static func checksum(_ segment: [UInt8], from source: [UInt8], to destination: [UInt8]) -> UInt16 {
        let pseudoHeader = source + destination + bigEndian(UInt32(segment.count)) + [0, 0, 0, tcpProtocol]
        var sum: UInt32 = 0
        for bytes in [pseudoHeader, segment] {
            for index in stride(from: 0, to: bytes.count, by: 2) {
                sum += UInt32(bytes[index]) << 8 | UInt32(index + 1 < bytes.count ? bytes[index + 1] : 0)
            }
        }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum)
    }

    static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }

    static func integer<T: FixedWidthInteger>(_ bytes: ArraySlice<UInt8>) -> T { bytes.reduce(T.zero) { $0 << 8 | T($1) } }

    /// The 16 bytes of an IPv6 address in text.
    public static func address(_ text: String) throws -> [UInt8] {
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { throw NomacError("not an IPv6 address: \(text)") }
        return withUnsafeBytes(of: &address) { Array($0) }
    }
}

/// TCP connections to the device inside the CoreDevice tunnel, run by nomac in userspace
/// (ADR 0402): the tunnel's carrier is a reliable ordered stream, so nomac neither retransmits
/// nor reorders; it sends within the device's window and acknowledges every segment.
public final class TunnelNetwork {
    private let tunnel: ByteStream
    private let local: [UInt8]
    private let remote: [UInt8]
    let maximumSegmentSize: Int
    private var connections: [UInt16: TunnelTCPConnection] = [:]
    private var nextPort: UInt16 = 49_152
    private let initialSequence: () -> UInt32

    public init(tunnel: ByteStream, parameters: CoreDeviceTunnel.Parameters,
                initialSequence: @escaping () -> UInt32 = { UInt32.random(in: .min ... .max) }) throws {
        self.tunnel = tunnel
        local = try TCPSegment.address(parameters.clientAddress)
        remote = try TCPSegment.address(parameters.serverAddress)
        maximumSegmentSize = parameters.mtu - TCPSegment.ipv6HeaderSize - 20
        self.initialSequence = initialSequence
    }

    /// A connection to TCP `port` of the device's tunnel address.
    public func connect(port: UInt16) throws -> TunnelTCPConnection {
        let localPort = nextPort
        nextPort = nextPort == .max ? 49_152 : nextPort + 1
        let connection = TunnelTCPConnection(network: self, localPort: localPort, remotePort: port, initialSequence: initialSequence())
        connections[localPort] = connection
        try connection.open()
        return connection
    }

    func send(_ segment: TCPSegment) throws {
        try tunnel.write(segment.packet(from: local, to: remote))
    }

    /// Reads one packet from the tunnel and hands a TCP segment to its connection: waiting on
    /// several connections at once is reading packets until one of them has bytes.
    public func receivePacket() throws {
        let header = try tunnel.read(TCPSegment.ipv6HeaderSize)
        let packet = header + (try tunnel.read(Int(header[4]) << 8 | Int(header[5])))
        guard let (source, destination, segment) = TCPSegment.parse(packet), source == remote, destination == local,
              let connection = connections[segment.destinationPort], segment.sourcePort == connection.remotePort else { return }
        try connection.handle(segment)
    }
}

/// One TCP connection in the tunnel, a stream for lockdown-style services and RemoteXPC.
public final class TunnelTCPConnection: ByteStream {
    static let advertisedWindow: UInt16 = 65_535

    private unowned let network: TunnelNetwork
    let localPort: UInt16
    let remotePort: UInt16
    private var sendNext: UInt32
    private var sendUnacknowledged: UInt32
    private var receiveNext: UInt32 = 0
    private var peerWindow = 0
    private var peerSegmentSize = 536
    private var received: [UInt8] = []
    private var established = false
    private var finished = false
    private var reset = false

    init(network: TunnelNetwork, localPort: UInt16, remotePort: UInt16, initialSequence: UInt32) {
        self.network = network
        self.localPort = localPort
        self.remotePort = remotePort
        sendNext = initialSequence
        sendUnacknowledged = initialSequence
    }

    func open() throws {
        try network.send(segment(sequence: sendNext, flags: .syn, maximumSegmentSize: UInt16(clamping: network.maximumSegmentSize)))
        sendNext &+= 1
        while !established {
            if reset { throw NomacError("the device refused TCP port \(remotePort) in the tunnel") }
            try network.receivePacket()
        }
    }

    public func write(_ bytes: [UInt8]) throws {
        let size = min(network.maximumSegmentSize, peerSegmentSize)
        for start in stride(from: 0, to: bytes.count, by: size) {
            let chunk = Array(bytes[start..<min(start + size, bytes.count)])
            while Int(sendNext &- sendUnacknowledged) + chunk.count > peerWindow {
                try check()
                try network.receivePacket()
            }
            try check()
            try network.send(segment(sequence: sendNext, flags: [.ack, .psh], payload: chunk))
            sendNext &+= UInt32(chunk.count)
        }
    }

    /// The bytes received and not yet read.
    public var availableCount: Int { received.count }

    /// Whether the device closed or reset the connection.
    public var isClosed: Bool { finished || reset }

    public func read(_ count: Int) throws -> [UInt8] {
        while received.count < count {
            try check()
            if finished { throw NomacError("the device closed TCP port \(remotePort) in the tunnel") }
            try network.receivePacket()
        }
        defer { received.removeFirst(count) }
        return Array(received.prefix(count))
    }

    /// The bytes received so far, waiting for at least one; nil once the device closed the
    /// connection and every byte was read.
    public func readAvailable() throws -> [UInt8]? {
        while received.isEmpty {
            try check()
            if finished { return nil }
            try network.receivePacket()
        }
        defer { received.removeAll() }
        return received
    }

    func handle(_ incoming: TCPSegment) throws {
        if incoming.flags.contains(.rst) {
            reset = true
            return
        }
        if !established {
            guard incoming.flags.contains([.syn, .ack]), incoming.acknowledgement == sendNext else { return }
            established = true
            receiveNext = incoming.sequence &+ 1
            sendUnacknowledged = incoming.acknowledgement
            peerWindow = Int(incoming.window)
            peerSegmentSize = Int(incoming.maximumSegmentSize ?? 536)
            try network.send(segment(sequence: sendNext, flags: .ack))
            return
        }
        if incoming.flags.contains(.ack), Int32(bitPattern: incoming.acknowledgement &- sendUnacknowledged) > 0 {
            sendUnacknowledged = incoming.acknowledgement
        }
        peerWindow = Int(incoming.window)
        let length = incoming.payload.count + (incoming.flags.contains(.fin) ? 1 : 0)
        guard length > 0 else {
            // A keepalive probe (RFC 1122 4.2.3.6): no data, one before the next byte. The device
            // probes an idle connection every 10 seconds and resets it after three unanswered.
            if incoming.sequence != receiveNext { try network.send(segment(sequence: sendNext, flags: .ack)) }
            return
        }
        if incoming.sequence == receiveNext {
            received += incoming.payload
            receiveNext &+= UInt32(length)
            if incoming.flags.contains(.fin) { finished = true }
        }
        try network.send(segment(sequence: sendNext, flags: .ack))
    }

    private func check() throws {
        if reset { throw NomacError("the device reset TCP port \(remotePort) in the tunnel") }
    }

    private func segment(sequence: UInt32, flags: TCPSegment.Flags, maximumSegmentSize: UInt16? = nil, payload: [UInt8] = []) -> TCPSegment {
        TCPSegment(sourcePort: localPort, destinationPort: remotePort, sequence: sequence,
                   acknowledgement: flags.contains(.syn) ? 0 : receiveNext, flags: flags.contains(.syn) ? flags : flags.union(.ack),
                   window: Self.advertisedWindow, maximumSegmentSize: maximumSegmentSize, payload: payload)
    }
}
