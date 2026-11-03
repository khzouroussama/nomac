import Foundation
import NomacCore
import NomacSigning

/// usbmuxd's protocol, which macOS's usbmuxd and libimobiledevice's speak alike
/// (docs/formats/usbmux.md): a 16-byte little-endian header (length, version, message type,
/// tag) and an XML property list.
public enum USBMux {
    public static let defaultAddress = StreamSocket.Address.unix("/var/run/usbmuxd")
    static let headerSize = 16
    static let version: UInt32 = 1
    static let propertyListMessage: UInt32 = 8

    /// The address `USBMUXD_SOCKET_ADDRESS` names, as libusbmuxd reads it (`UNIX:<path>` or
    /// `<host>:<port>`), or usbmuxd's own socket.
    public static func address(environment: [String: String]) throws -> StreamSocket.Address {
        guard let value = environment["USBMUXD_SOCKET_ADDRESS"], !value.isEmpty else { return defaultAddress }
        if value.hasPrefix("UNIX:") { return .unix(String(value.dropFirst(5))) }
        guard let colon = value.lastIndex(of: ":"), let port = UInt16(value[value.index(after: colon)...]) else {
            throw NomacError("USBMUXD_SOCKET_ADDRESS is neither UNIX:<path> nor <host>:<port>: \(value)")
        }
        return .tcp(host: String(value[..<colon]), port: port)
    }

    public struct Header: Equatable, Sendable {
        public let length: UInt32
        public let version: UInt32
        public let messageType: UInt32
        public let tag: UInt32
    }

    public struct Device: Equatable, Sendable {
        public let deviceID: Int64
        /// The device's UDID, as usbmuxd reports it.
        public let serialNumber: String
        /// `USB` or `Network`.
        public let connectionType: String
    }

    public enum Reply: Equatable, Sendable {
        case result(Int64)
        case devices([Device])
        case pairRecord([UInt8])
    }

    /// A request with the client fields libusbmuxd sends with each one.
    public static func message(_ fields: [String: PropertyListValue], tag: UInt32) -> [UInt8] {
        var request = fields
        request["ClientVersionString"] = .string("nomac")
        request["ProgName"] = .string("nomac")
        request["kLibUSBMuxVersion"] = .integer(3)
        let body = PropertyListValue.xmlDocument(.dictionary(request))
        return [UInt32(headerSize + body.count), version, propertyListMessage, tag].flatMap { withUnsafeBytes(of: $0.littleEndian, Array.init) } + body
    }

    public static func header(_ bytes: [UInt8]) throws -> Header {
        guard bytes.count == headerSize else { throw NomacError("usbmuxd header of \(bytes.count) bytes") }
        let fields = (0..<4).map { index in bytes[index * 4..<index * 4 + 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
        let header = Header(length: fields[0], version: fields[1], messageType: fields[2], tag: fields[3])
        guard header.version == version, header.messageType == propertyListMessage, header.length >= UInt32(headerSize),
              header.length <= 1 << 24 else {
            throw NomacError("unexpected usbmuxd header: length \(header.length), version \(header.version), type \(header.messageType)")
        }
        return header
    }

    public static func reply(_ body: [UInt8]) throws -> Reply {
        let fields = try PropertyListMessages.dictionary(body, source: "usbmuxd")
        if case .data(let record)? = fields["PairRecordData"] { return .pairRecord(record) }
        if case .array(let entries)? = fields["DeviceList"] {
            return .devices(entries.compactMap(device))
        }
        guard case .string("Result")? = fields["MessageType"], case .integer(let number)? = fields["Number"] else {
            throw NomacError("unexpected usbmuxd reply: \(fields.keys.sorted().joined(separator: ", "))")
        }
        return .result(number)
    }

    private static func device(_ entry: PropertyListValue) -> Device? {
        guard case .dictionary(let fields) = entry, case .dictionary(let properties)? = fields["Properties"],
              case .integer(let deviceID)? = fields["DeviceID"], case .string(let serialNumber)? = properties["SerialNumber"],
              case .string(let connectionType)? = properties["ConnectionType"] else { return nil }
        return Device(deviceID: deviceID, serialNumber: serialNumber, connectionType: connectionType)
    }

    public static let listDevices: [String: PropertyListValue] = ["MessageType": .string("ListDevices")]

    /// A connection to TCP `port` on the device. usbmuxd reads `PortNumber` in network byte
    /// order, the integer libusbmuxd's `htons` gives on the little-endian hosts usbmuxd runs on.
    public static func connect(deviceID: Int64, port: UInt16) -> [String: PropertyListValue] {
        ["MessageType": .string("Connect"), "DeviceID": .integer(deviceID), "PortNumber": .integer(Int64(port.byteSwapped))]
    }

    /// The pair record usbmuxd keeps for the device `udid` (the host's side of the pairing).
    public static func readPairRecord(udid: String) -> [String: PropertyListValue] {
        ["MessageType": .string("ReadPairRecord"), "PairRecordID": .string(udid)]
    }

    /// The meaning of a `Result` number (libusbmuxd's `usbmuxd-proto.h`).
    /// `ReadPairRecord` without a record: `Result` 22 from macOS's usbmuxd, 2 from
    /// libimobiledevice's on Linux (`device_experiments.py`, 2026-11-02).
    public static func pairRecordFailure(_ reply: Reply, udid: String) -> NomacError {
        let message = if case .result(let number) = reply {
            "usbmuxd holds no pair record for \(udid) (result \(number))"
        } else {
            "unexpected usbmuxd reply to ReadPairRecord for \(udid)"
        }
        return NomacError(message, notes: ["this host is not paired with the device: unlock it, plug it in by USB and tap Trust on the device"])
    }

    public static func describe(result number: Int64) -> String {
        switch number {
        case 0: "success"
        case 1: "bad command"
        case 2: "bad device"
        case 3: "connection refused"
        case 6: "bad version"
        default: "result \(number)"
        }
    }
}

/// A client of usbmuxd: each request on its own connection, as libusbmuxd does.
public struct USBMuxClient {
    public let address: StreamSocket.Address

    public init(address: StreamSocket.Address) { self.address = address }

    public func devices() throws -> [USBMux.Device] {
        let socket = try open()
        let reply = try exchange(socket, USBMux.listDevices)
        guard case .devices(let devices) = reply else { throw failure(reply, "ListDevices") }
        return devices
    }

    /// A stream to TCP `port` on the device: after usbmuxd's success, the socket carries the
    /// port's bytes.
    public func connect(deviceID: Int64, port: UInt16) throws -> StreamSocket {
        let socket = try open()
        let reply = try exchange(socket, USBMux.connect(deviceID: deviceID, port: port))
        guard reply == .result(0) else { throw failure(reply, "Connect to port \(port) of device \(deviceID)") }
        return socket
    }

    public func pairRecord(udid: String) throws -> PairRecord {
        let socket = try open()
        let reply = try exchange(socket, USBMux.readPairRecord(udid: udid))
        guard case .pairRecord(let bytes) = reply else { throw USBMux.pairRecordFailure(reply, udid: udid) }
        return try PairRecord(bytes: bytes)
    }

    /// The device usbmuxd lists with the UDID `udid`, by USB before the network.
    public func device(udid: String) throws -> USBMux.Device {
        let matches = try devices().filter { $0.serialNumber.caseInsensitiveCompare(udid) == .orderedSame }
        guard let device = matches.first(where: { $0.connectionType == "USB" }) ?? matches.first else {
            let seen = try devices().map { "\($0.serialNumber) (\($0.connectionType))" }
            throw NomacError("usbmuxd sees no device \(udid)", notes: [
                seen.isEmpty ? "usbmuxd sees no device at all" : "usbmuxd sees \(seen.joined(separator: ", "))",
                "connect the device by USB and unlock it",
            ])
        }
        return device
    }

    private func open() throws -> StreamSocket {
        do {
            return try StreamSocket(connectingTo: address)
        } catch var error as NomacError {
            switch address {
            case .unix: error.notes.append("usbmuxd is not running: on Linux, start libimobiledevice's usbmuxd")
            case .tcp: error.notes.append("nothing answers at USBMUXD_SOCKET_ADDRESS: start the forward of the Mac's usbmuxd (docs/formats/usbmux.md)")
            }
            throw error
        }
    }

    private func failure(_ reply: USBMux.Reply, _ request: String) -> NomacError {
        if case .result(let number) = reply { return NomacError("usbmuxd refused \(request): \(USBMux.describe(result: number))") }
        return NomacError("unexpected usbmuxd reply to \(request)")
    }

    private func exchange(_ socket: StreamSocket, _ request: [String: PropertyListValue]) throws -> USBMux.Reply {
        try socket.write(USBMux.message(request, tag: 1))
        let header = try USBMux.header(try socket.read(USBMux.headerSize))
        return try USBMux.reply(try socket.read(Int(header.length) - USBMux.headerSize))
    }
}
