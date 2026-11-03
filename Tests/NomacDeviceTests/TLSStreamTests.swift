import Foundation
import NIOCore
import NIOEmbedded
import NIOSSL
import NomacTestSupport
import Testing
@testable import NomacDevice

/// `TLSStream` against swift-nio-ssl's server, both with the self-made test identity: the
/// handshake with a client certificate, then data both ways.
@Suite struct TLSStreamTests {
    /// The server's end of the connection, run in an embedded channel as each write arrives.
    final class ServerPipe: ByteStream {
        let server = EmbeddedChannel()
        var toClient: [UInt8] = []
        /// The certificate the client presented.
        let clientCertificate = Box()

        final class Box: @unchecked Sendable { var value: NIOSSLCertificate? }

        init() throws {
            var configuration = TLSConfiguration.makeServerConfiguration(
                certificateChain: try NIOSSLCertificate.fromPEMBytes(Array(TestIdentities.appleShaped.utf8)).map { .certificate($0) },
                privateKey: .privateKey(try NIOSSLPrivateKey(bytes: Array(TestIdentities.appleShaped.utf8), format: .pem)))
            configuration.certificateVerification = .noHostnameVerification
            let handler = NIOSSLServerHandler(context: try NIOSSLContext(configuration: configuration)) { [received = clientCertificate] certificates, promise in
                received.value = certificates.first
                promise.succeed(.certificateVerified)
            }
            try server.pipeline.syncOperations.addHandler(handler)
            try server.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
        }

        func write(_ bytes: [UInt8]) throws {
            try server.writeInbound(server.allocator.buffer(bytes: bytes))
            drain()
        }

        func read(_ count: Int) throws -> [UInt8] {
            guard toClient.count >= count else { throw CocoaError(.fileReadCorruptFile) }
            defer { toClient.removeFirst(count) }
            return Array(toClient.prefix(count))
        }

        func received() throws -> [UInt8] {
            server.embeddedEventLoop.run()
            var bytes: [UInt8] = []
            while let buffer = try server.readInbound(as: ByteBuffer.self) { bytes += buffer.readableBytesView }
            return bytes
        }

        func send(_ bytes: [UInt8]) throws {
            try server.writeOutbound(server.allocator.buffer(bytes: bytes))
            drain()
        }

        private func drain() {
            server.embeddedEventLoop.run()
            while let buffer = try? server.readOutbound(as: ByteBuffer.self) { toClient += buffer.readableBytesView }
        }
    }

    @Test func handshakeThenDataBothWays() throws {
        let pipe = try ServerPipe()
        let identity = Array(TestIdentities.appleShaped.utf8)
        let tls = try TLSStream(over: pipe, certificate: identity, privateKey: identity)
        try tls.write(Array("QueryType".utf8))
        #expect(try pipe.received() == Array("QueryType".utf8))
        try pipe.send(Array("com.apple.mobile.lockdown".utf8))
        #expect(try tls.read(25) == Array("com.apple.mobile.lockdown".utf8))
        #expect(pipe.clientCertificate.value == (try NIOSSLCertificate.fromPEMBytes(identity)).first)
    }
}
