import Foundation
import NomacCore

/// The Apple File Conduit (`com.apple.afc`), the service that writes files into the device's
/// media folder, where installation_proxy reads packages from (docs/formats/afc.md). Each
/// packet is a 40-byte little-endian header (`CFA6LPAA`, the entire length, the length of the
/// header and its operands, the packet number, the operation), the operands, then the data.
public enum AFC {
    public static let serviceName = "com.apple.afc"
    static let magic = Array("CFA6LPAA".utf8)
    static let headerSize = 40
    static let writeChunkSize = 1 << 20

    public enum Operation: UInt64, Sendable {
        case status = 0x01
        case data = 0x02
        case readDirectory = 0x03
        case removePath = 0x08
        case makeDirectory = 0x09
        case fileInfo = 0x0a
        case fileOpen = 0x0d
        case read = 0x0f
        case write = 0x10
        case fileClose = 0x14
    }

    /// `w`: write only, created, truncated.
    static let writeOnlyMode: UInt64 = 3
    /// `r`: read only.
    static let readOnlyMode: UInt64 = 1
    static let readChunkSize = 1 << 20

    /// The strings of a reply's data, each ended by a zero byte.
    static func strings(_ bytes: [UInt8]) -> [String] {
        bytes.split(separator: 0, omittingEmptySubsequences: false).dropLast().map { String(decoding: $0, as: UTF8.self) }
    }

    public struct Header: Equatable, Sendable {
        public let entireLength: UInt64
        public let thisLength: UInt64
        public let packetNumber: UInt64
        public let operation: UInt64
    }

    public static func packet(_ operation: Operation, number: UInt64, operands: [UInt8], data: [UInt8] = []) -> [UInt8] {
        let thisLength = UInt64(headerSize + operands.count)
        return magic + [thisLength + UInt64(data.count), thisLength, number, operation.rawValue].flatMap(littleEndian) + operands + data
    }

    public static func header(_ bytes: [UInt8]) throws -> Header {
        guard bytes.count == headerSize, bytes.starts(with: magic) else { throw NomacError("AFC packet without the CFA6LPAA header") }
        let fields = (0..<4).map { index in integer(bytes[8 + index * 8..<16 + index * 8]) }
        guard fields[0] >= UInt64(headerSize), fields[1] >= UInt64(headerSize), fields[1] <= fields[0] else {
            throw NomacError("AFC packet with lengths \(fields[0]) and \(fields[1])")
        }
        return Header(entireLength: fields[0], thisLength: fields[1], packetNumber: fields[2], operation: fields[3])
    }

    /// A path operand: the path's UTF-8 bytes and a NUL.
    static func path(_ path: String) -> [UInt8] { Array(path.utf8) + [0] }

    static func littleEndian(_ value: UInt64) -> [UInt8] { withUnsafeBytes(of: value.littleEndian, Array.init) }

    static func integer(_ bytes: ArraySlice<UInt8>) -> UInt64 { bytes.reversed().reduce(0) { $0 << 8 | UInt64($1) } }

    /// The names of AFC's status codes (pymobiledevice3's `AfcError`).
    static func describe(status: UInt64) -> String {
        switch status {
        case 7: "invalid argument"
        case 8: "object not found"
        case 9: "object is a directory"
        case 10: "permission denied"
        case 16: "object exists"
        case 18: "no space left"
        default: "status \(status)"
        }
    }
}

/// A client of `com.apple.afc` over its service connection.
public final class AFCClient {
    private let stream: ByteStream
    private var packetNumber: UInt64 = 0

    public init(stream: ByteStream) { self.stream = stream }

    /// Creates `path` and the folders above it.
    public func makeDirectory(_ path: String) throws {
        _ = try perform(.makeDirectory, operands: AFC.path(path), about: path)
    }

    public func upload(_ bytes: [UInt8], to path: String) throws {
        let reply = try perform(.fileOpen, operands: AFC.littleEndian(AFC.writeOnlyMode) + AFC.path(path), about: path)
        guard reply.count >= 8 else { throw NomacError("AFC's open reply for \(path) has no handle") }
        let handle = AFC.littleEndian(AFC.integer(reply[reply.startIndex..<reply.startIndex + 8]))
        for start in stride(from: 0, to: bytes.count, by: AFC.writeChunkSize) {
            _ = try perform(.write, operands: handle, data: Array(bytes[start..<min(start + AFC.writeChunkSize, bytes.count)]), about: path)
        }
        _ = try perform(.fileClose, operands: handle, about: path)
    }

    /// The names in the folder at `path`, without `.` and `..`.
    public func list(_ path: String) throws -> [String] {
        AFC.strings(try perform(.readDirectory, operands: AFC.path(path), about: path)).filter { $0 != "." && $0 != ".." }
    }

    /// The file's information: `st_size`, `st_ifmt` (`S_IFREG`, `S_IFDIR`), `st_mtime` (in
    /// nanoseconds) and others, as AFC names them.
    public func info(_ path: String) throws -> [String: String] {
        let strings = AFC.strings(try perform(.fileInfo, operands: AFC.path(path), about: path))
        return Dictionary(stride(from: 0, to: strings.count - 1, by: 2).map { (strings[$0], strings[$0 + 1]) }, uniquingKeysWith: { $1 })
    }

    public func download(_ path: String) throws -> [UInt8] {
        let reply = try perform(.fileOpen, operands: AFC.littleEndian(AFC.readOnlyMode) + AFC.path(path), about: path)
        guard reply.count >= 8 else { throw NomacError("AFC's open reply for \(path) has no handle") }
        let handle = AFC.littleEndian(AFC.integer(reply[reply.startIndex..<reply.startIndex + 8]))
        var bytes: [UInt8] = []
        while true {
            let chunk = try perform(.read, operands: handle + AFC.littleEndian(UInt64(AFC.readChunkSize)), about: path)
            bytes += chunk
            if chunk.count < AFC.readChunkSize { break }
        }
        _ = try perform(.fileClose, operands: handle, about: path)
        return bytes
    }

    public func remove(_ path: String) throws {
        _ = try perform(.removePath, operands: AFC.path(path), about: path)
    }

    /// The reply's bytes after its header, or AFC's error.
    private func perform(_ operation: AFC.Operation, operands: [UInt8], data: [UInt8] = [], about path: String) throws -> [UInt8] {
        let number = packetNumber
        packetNumber += 1
        try stream.write(AFC.packet(operation, number: number, operands: operands, data: data))
        let header = try AFC.header(try stream.read(AFC.headerSize))
        let reply = try stream.read(Int(header.entireLength) - AFC.headerSize)
        guard header.packetNumber == number else { throw NomacError("AFC answered packet \(header.packetNumber) for \(number)") }
        if header.operation == AFC.Operation.status.rawValue {
            let status = reply.count == 8 ? AFC.integer(reply[...]) : UInt64.max
            guard status == 0 else { throw NomacError("AFC refused \(operation) for \(path): \(AFC.describe(status: status))") }
        }
        return reply
    }
}
