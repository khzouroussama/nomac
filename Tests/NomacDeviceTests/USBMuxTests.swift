import Foundation
import NomacSigning
import Testing
@testable import NomacDevice

/// usbmuxd's framing as libusbmuxd writes it, and the replies observed from macOS 27.0.1's
/// usbmuxd with no device attached (docs/formats/usbmux.md).
@Suite struct USBMuxTests {
    @Test func requestHasTheLittleEndianHeaderAndTheClientFields() throws {
        let message = USBMux.message(USBMux.listDevices, tag: 7)
        #expect(Array(message[4..<16]) == [1, 0, 0, 0, 8, 0, 0, 0, 7, 0, 0, 0])
        let header = try USBMux.header(Array(message[0..<16]))
        #expect(Int(header.length) == message.count)
        #expect(try PropertyListValue.parseXML(Data(message[16...]), path: "request") == .dictionary([
            "MessageType": .string("ListDevices"),
            "ClientVersionString": .string("nomac"),
            "ProgName": .string("nomac"),
            "kLibUSBMuxVersion": .integer(3),
        ]))
    }

    @Test func headerOfAnotherVersionIsRefused() {
        #expect(throws: (any Error).self) { try USBMux.header([16, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 1, 0, 0, 0]) }
    }

    @Test func connectGivesThePortInNetworkByteOrder() {
        #expect(USBMux.connect(deviceID: 3, port: 62078)["PortNumber"] == .integer(32498))
    }

    @Test func pairRecordReply() throws {
        #expect(try USBMux.reply(Array(plist("<key>PairRecordData</key><data>YnBsaXN0</data>").utf8)) == .pairRecord(Array("bplist".utf8)))
    }

    /// Both usbmuxds answer a UDID without a record with a `Result`: 22 on macOS, 2 on Linux.
    @Test func missingPairRecord() {
        for number: Int64 in [22, 2] {
            let error = USBMux.pairRecordFailure(.result(number), udid: "U")
            #expect(error.message == "usbmuxd holds no pair record for U (result \(number))")
            #expect(error.notes.first?.hasPrefix("this host is not paired with the device") == true)
        }
    }

    @Test func unknownMessageIsABadCommand() throws {
        let reply = try USBMux.reply(Array(plist("<key>MessageType</key><string>Result</string><key>Number</key><integer>1</integer>").utf8))
        #expect(reply == .result(1))
        #expect(USBMux.describe(result: 1) == "bad command")
    }

    @Test func emptyDeviceList() throws {
        #expect(try USBMux.reply(Array(plist("<key>DeviceList</key><array/>").utf8)) == .devices([]))
    }

    @Test func deviceListEntries() throws {
        let entry = """
        <dict><key>DeviceID</key><integer>4</integer><key>MessageType</key><string>Attached</string>
        <key>Properties</key><dict><key>ConnectionType</key><string>USB</string><key>DeviceID</key><integer>4</integer>
        <key>SerialNumber</key><string>00008140-0001234567890ABC</string></dict></dict>
        """
        #expect(try USBMux.reply(Array(plist("<key>DeviceList</key><array>\(entry)</array>").utf8))
            == .devices([USBMux.Device(deviceID: 4, serialNumber: "00008140-0001234567890ABC", connectionType: "USB")]))
    }

    @Test func socketAddressFromTheEnvironment() throws {
        #expect(try USBMux.address(environment: [:]) == .unix("/var/run/usbmuxd"))
        #expect(try USBMux.address(environment: ["USBMUXD_SOCKET_ADDRESS": "UNIX:/tmp/mux"]) == .unix("/tmp/mux"))
        #expect(try USBMux.address(environment: ["USBMUXD_SOCKET_ADDRESS": "host.docker.internal:27015"])
            == .tcp(host: "host.docker.internal", port: 27015))
        #expect(throws: (any Error).self) { try USBMux.address(environment: ["USBMUXD_SOCKET_ADDRESS": "nowhere"]) }
    }

    private func plist(_ entries: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>\(entries)</dict></plist>
        """
    }
}
