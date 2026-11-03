import Foundation
import Testing
@testable import NomacDevice

/// nomac's userspace TCP in the CoreDevice tunnel (ADR 0402), against a scripted device.
@Suite struct TunnelNetworkTests {
    static let parameters = CoreDeviceTunnel.Parameters(clientAddress: "fd00::2", mtu: 16_000, serverAddress: "fd00::1", serverRSDPort: 58_783)

    @Test func synPacketBytes() throws {
        let syn = TCPSegment(sourcePort: 49_152, destinationPort: 58_783, sequence: 1, acknowledgement: 0, flags: .syn,
                             window: 65_535, maximumSegmentSize: 15_940)
        let packet = syn.packet(from: try TCPSegment.address("fd00::2"), to: try TCPSegment.address("fd00::1"))
        #expect(Array(packet[0..<8]) == [0x60, 0, 0, 0, 0, 24, 6, 64])
        // RFC 1071's checksum, computed separately with Python's struct.
        #expect(Array(packet[56..<58]) == [0xbf, 0xf0])
        #expect(TCPSegment.parse(packet)?.segment == syn)
    }

    @Test func corruptedPacketsAreDropped() throws {
        var packet = TCPSegment(sourcePort: 1, destinationPort: 2, sequence: 3, acknowledgement: 4, flags: .ack, window: 5, payload: [6])
            .packet(from: try TCPSegment.address("fd00::1"), to: try TCPSegment.address("fd00::2"))
        packet[packet.count - 1] ^= 1
        #expect(TCPSegment.parse(packet) == nil)
    }

    /// The device's side of one connection: answers the SYN, acknowledges data, sends a reply.
    final class Device: ByteStream {
        let local = try! TCPSegment.address("fd00::1"), remote = try! TCPSegment.address("fd00::2")
        var toHost: [UInt8] = []
        var receivedData: [UInt8] = []
        var sequence: UInt32 = 1000
        var pending: [UInt8] = []
        let reply: [UInt8]

        init(reply: [UInt8]) { self.reply = reply }

        func write(_ bytes: [UInt8]) throws {
            guard let (_, _, segment) = TCPSegment.parse(bytes) else { throw CocoaError(.fileReadCorruptFile) }
            if segment.flags.contains(.syn) {
                send(TCPSegment(sourcePort: segment.destinationPort, destinationPort: segment.sourcePort, sequence: sequence,
                                acknowledgement: segment.sequence &+ 1, flags: [.syn, .ack], window: 8, maximumSegmentSize: 4))
                sequence &+= 1
            } else if !segment.payload.isEmpty {
                receivedData += segment.payload
                send(TCPSegment(sourcePort: segment.destinationPort, destinationPort: segment.sourcePort, sequence: sequence,
                                acknowledgement: segment.sequence &+ UInt32(segment.payload.count), flags: .ack, window: 8,
                                payload: receivedData.count == 10 ? reply : []))
                if receivedData.count == 10 { sequence &+= UInt32(reply.count) }
            }
        }

        func read(_ count: Int) throws -> [UInt8] {
            guard toHost.count >= count else { throw CocoaError(.fileReadCorruptFile) }
            defer { toHost.removeFirst(count) }
            return Array(toHost.prefix(count))
        }

        private func send(_ segment: TCPSegment) { toHost += segment.packet(from: local, to: remote) }
    }

    @Test func connectWriteWithinTheWindowAndRead() throws {
        let device = Device(reply: Array("reply".utf8))
        let network = try TunnelNetwork(tunnel: device, parameters: Self.parameters, initialSequence: { 7 })
        let connection = try network.connect(port: 58_783)
        try connection.write(Array("0123456789".utf8))
        #expect(device.receivedData == Array("0123456789".utf8))
        #expect(try connection.read(5) == Array("reply".utf8))
    }

    /// A device that answers the SYN, sends output, then closes: a launched app's console.
    final class Talker: ByteStream {
        let local = try! TCPSegment.address("fd00::1"), remote = try! TCPSegment.address("fd00::2")
        var toHost: [UInt8] = []

        func write(_ bytes: [UInt8]) throws {
            guard let (_, _, segment) = TCPSegment.parse(bytes), segment.flags.contains(.syn) else { return }
            func send(_ sequence: UInt32, _ flags: TCPSegment.Flags, _ payload: [UInt8] = []) {
                toHost += TCPSegment(sourcePort: segment.destinationPort, destinationPort: segment.sourcePort, sequence: sequence,
                                     acknowledgement: segment.sequence &+ 1, flags: flags, window: 64, maximumSegmentSize: 1000,
                                     payload: payload).packet(from: local, to: remote)
            }
            send(1000, [.syn, .ack])
            send(1001, [.ack, .psh], Array("*** Terminating app\n".utf8))
            send(1021, [.ack, .fin])
        }

        func read(_ count: Int) throws -> [UInt8] {
            guard toHost.count >= count else { throw CocoaError(.fileReadCorruptFile) }
            defer { toHost.removeFirst(count) }
            return Array(toHost.prefix(count))
        }
    }

    @Test func readAvailableUntilTheDeviceCloses() throws {
        let network = try TunnelNetwork(tunnel: Talker(), parameters: Self.parameters, initialSequence: { 7 })
        let connection = try network.connect(port: 50_000)
        #expect(try connection.readAvailable() == Array("*** Terminating app\n".utf8))
        #expect(try connection.readAvailable() == nil)
    }

    /// After the handshake the device sends a keepalive probe (no data, one before the next
    /// byte, as the iPhone does every 10 seconds on an idle connection), then output, then FIN.
    final class Prober: ByteStream {
        let local = try! TCPSegment.address("fd00::1"), remote = try! TCPSegment.address("fd00::2")
        var toHost: [UInt8] = []
        var fromHost: [TCPSegment] = []

        func write(_ bytes: [UInt8]) throws {
            guard let (_, _, segment) = TCPSegment.parse(bytes) else { return }
            fromHost.append(segment)
            guard segment.flags.contains(.syn) else { return }
            func send(_ sequence: UInt32, _ flags: TCPSegment.Flags, _ payload: [UInt8] = []) {
                toHost += TCPSegment(sourcePort: segment.destinationPort, destinationPort: segment.sourcePort, sequence: sequence,
                                     acknowledgement: segment.sequence &+ 1, flags: flags, window: 64, maximumSegmentSize: 1000,
                                     payload: payload).packet(from: local, to: remote)
            }
            send(1000, [.syn, .ack])
            send(1000, .ack)
            send(1001, [.ack, .psh], Array("x".utf8))
            send(1002, [.ack, .fin])
        }

        func read(_ count: Int) throws -> [UInt8] {
            guard toHost.count >= count else { throw CocoaError(.fileReadCorruptFile) }
            defer { toHost.removeFirst(count) }
            return Array(toHost.prefix(count))
        }
    }

    @Test func keepaliveProbesAreAcknowledged() throws {
        let device = Prober()
        let network = try TunnelNetwork(tunnel: device, parameters: Self.parameters, initialSequence: { 7 })
        let connection = try network.connect(port: 50_000)
        #expect(try connection.readAvailable() == Array("x".utf8))
        // The handshake's ACK, then the probe's: both acknowledge 1001, without data.
        let acknowledgements = device.fromHost.filter { !$0.flags.contains(.syn) && $0.payload.isEmpty && $0.acknowledgement == 1001 }
        #expect(acknowledgements.count == 2)
    }
}
