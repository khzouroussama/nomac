import Foundation
import NIOCore
import NIOEmbedded
import NIOSSL
import NIOTLS
import NomacCore

/// TLS as the client of a lockdownd session or service, over another stream: the host's
/// certificate and key from the pair record, the device's certificate not verified (it is
/// self-issued at pairing), TLS 1.2 to 1.3, as pymobiledevice3's `create_ssl_context` offers
/// (docs/adr/0401-device-tls.md). BoringSSL runs in an embedded channel fed one TLS record at
/// a time, so nothing past the handshake is read from the stream before it is needed.
public final class TLSStream: ByteStream {
    private let underlying: ByteStream
    private let channel: EmbeddedChannel
    private var plaintext: [UInt8] = []

    public init(over underlying: ByteStream, certificate: [UInt8], privateKey: [UInt8]) throws {
        self.underlying = underlying
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.minimumTLSVersion = .tlsv12
        configuration.certificateVerification = .noHostnameVerification
        configuration.certificateChain = try NIOSSLCertificate.fromPEMBytes(certificate).map { .certificate($0) }
        configuration.privateKey = .privateKey(try NIOSSLPrivateKey(bytes: privateKey, format: .pem))
        let handshake = HandshakeObserver()
        channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandlers([
            // Accepting every certificate in a verification callback: with `.none`, swift-nio-ssl's
            // client does not finish its handshake in an embedded channel.
            try NIOSSLClientHandler(context: try NIOSSLContext(configuration: configuration), serverHostname: nil) { _, promise in
                promise.succeed(.certificateVerified)
            },
            handshake,
        ])
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
        try flush()
        while !handshake.completed {
            try receiveRecord()
            try flush()
        }
    }

    public func write(_ bytes: [UInt8]) throws {
        try channel.writeOutbound(channel.allocator.buffer(bytes: bytes))
        try flush()
    }

    public func read(_ count: Int) throws -> [UInt8] {
        while plaintext.count < count { try receiveRecord() }
        defer { plaintext.removeFirst(count) }
        return Array(plaintext.prefix(count))
    }

    /// Passes one TLS record from the stream to BoringSSL and keeps the plaintext it gives.
    private func receiveRecord() throws {
        let header = try underlying.read(5)
        guard (20...23).contains(header[0]), header[1] == 3 else {
            throw NomacError("the device answered TLS with bytes that are not a TLS record")
        }
        let body = try underlying.read(Int(header[3]) << 8 | Int(header[4]))
        try channel.writeInbound(channel.allocator.buffer(bytes: header + body))
        while let buffer = try channel.readInbound(as: ByteBuffer.self) {
            plaintext += buffer.readableBytesView
        }
        try flush()
    }

    /// Sends what BoringSSL wrote to the stream.
    private func flush() throws {
        channel.embeddedEventLoop.run()
        while let buffer = try channel.readOutbound(as: ByteBuffer.self) {
            try underlying.write(Array(buffer.readableBytesView))
        }
    }

    private final class HandshakeObserver: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = ByteBuffer
        typealias InboundOut = ByteBuffer
        var completed = false

        func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
            if let event = event as? TLSUserEvent, case .handshakeCompleted = event { completed = true }
            context.fireUserInboundEventTriggered(event)
        }
    }
}
