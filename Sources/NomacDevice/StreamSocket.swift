#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import NomacCore

/// A blocking stream socket to a Unix domain socket or a TCP port.
public final class StreamSocket {
    public enum Address: Equatable, Sendable {
        case unix(String)
        case tcp(host: String, port: UInt16)
    }

    private let descriptor: Int32
    public let address: Address

    public init(connectingTo address: Address) throws {
        self.address = address
        switch address {
        case .unix(let path):
            descriptor = try Self.connectUnix(path)
        case .tcp(let host, let port):
            descriptor = try Self.connectTCP(host: host, port: port)
        }
    }

    deinit { close(descriptor) }

    public func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { send(descriptor, $0.baseAddress, $0.count, Self.sendFlags) }
            guard written > 0 else { throw failure("cannot write to") }
            offset += written
        }
    }

    /// Exactly `count` bytes, or an error if the peer closes the connection first.
    public func read(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let received = bytes[offset...].withUnsafeMutableBytes { recv(descriptor, $0.baseAddress, $0.count, 0) }
            guard received > 0 else {
                if received < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    throw NomacError("no reply from \(Self.describe(address)) in \(Self.readTimeout) seconds")
                }
                throw failure(received == 0 ? "connection closed by" : "cannot read from")
            }
            offset += received
        }
        return bytes
    }

    private func failure(_ what: String) -> NomacError {
        NomacError("\(what) \(Self.describe(address))\(errno == 0 ? "" : ": " + String(cString: strerror(errno)))")
    }

    public static func describe(_ address: Address) -> String {
        switch address {
        case .unix(let path): path
        case .tcp(let host, let port): "\(host):\(port)"
        }
    }

    #if canImport(Glibc)
    private static let streamType = Int32(SOCK_STREAM.rawValue)
    private static let sendFlags = Int32(MSG_NOSIGNAL)
    #else
    private static let streamType = SOCK_STREAM
    private static let sendFlags: Int32 = 0
    #endif

    /// How long a read waits for the peer before failing.
    static let readTimeout = 120

    /// A read fails after `readTimeout` seconds without data, and a write to a closed peer fails
    /// with `EPIPE` instead of killing nomac (Linux passes `MSG_NOSIGNAL` to each `send`).
    private static func configure(_ descriptor: Int32) {
        var timeout = timeval(tv_sec: readTimeout, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        #if canImport(Darwin)
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    private static func connectUnix(_ path: String) throws -> Int32 {
        let descriptor = socket(AF_UNIX, streamType, 0)
        guard descriptor >= 0 else { throw NomacError("cannot create a socket: \(String(cString: strerror(errno)))") }
        configure(descriptor)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else {
            close(descriptor)
            throw NomacError("socket path too long", path: path)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            let message = String(cString: strerror(errno))
            close(descriptor)
            throw NomacError("cannot connect to \(path): \(message)")
        }
        return descriptor
    }

    private static func connectTCP(host: String, port: UInt16) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = streamType
        var results: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &results)
        guard status == 0, let first = results else {
            throw NomacError("cannot resolve \(host): \(String(cString: gai_strerror(status)))")
        }
        defer { freeaddrinfo(first) }
        var lastError = ""
        var candidate: UnsafeMutablePointer<addrinfo>? = first
        while let info = candidate {
            let descriptor = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if descriptor >= 0 {
                configure(descriptor)
                if connect(descriptor, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 { return descriptor }
                lastError = String(cString: strerror(errno))
                close(descriptor)
            }
            candidate = info.pointee.ai_next
        }
        throw NomacError("cannot connect to \(host):\(port): \(lastError)")
    }
}
