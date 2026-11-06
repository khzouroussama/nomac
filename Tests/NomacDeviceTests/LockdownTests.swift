import Foundation
import NomacPlist
import NomacSigning
import Testing
@testable import NomacDevice

/// lockdownd's messages as libimobiledevice's `property_list_service` and pymobiledevice3
/// frame them (docs/formats/lockdown.md), exchanged with a stream that replays a device's
/// replies.
@Suite struct LockdownTests {
    @Test func framingIsABigEndianLengthAndXML() throws {
        let frame = PropertyListMessages.frame(Lockdown.request("QueryType"))
        let length = Int(frame[0]) << 24 | Int(frame[1]) << 16 | Int(frame[2]) << 8 | Int(frame[3])
        #expect(length == frame.count - 4)
        #expect(try PropertyListMessages.dictionary(Array(frame[4...]), source: "test")
            == ["Label": .string("nomac"), "Request": .string("QueryType")])
    }

    @Test func binaryRepliesAreRead() throws {
        let binary = [UInt8](BinaryPropertyList.swiftBuildData(.dictionary(["Request": .string("QueryType"), "Type": .string("com.apple.mobile.lockdown")])))
        #expect(try PropertyListMessages.dictionary(binary, source: "test")
            == ["Request": .string("QueryType"), "Type": .string("com.apple.mobile.lockdown")])
    }

    @Test func queryTypeAndValues() throws {
        let stream = ReplayStream(replies: [
            ["Request": .string("QueryType"), "Type": .string("com.apple.mobile.lockdown")],
            ["Request": .string("GetValue"), "Key": .string("ProductVersion"), "Value": .string("27.0.1")],
        ])
        let lockdown = LockdownClient(stream: stream)
        #expect(try lockdown.queryType() == "com.apple.mobile.lockdown")
        #expect(try lockdown.value(key: "ProductVersion") == .string("27.0.1"))
        let sent = ReplayStream(bytes: stream.written)
        #expect(try PropertyListMessages.receive(from: sent, source: "test") == Lockdown.request("QueryType"))
        #expect(try PropertyListMessages.receive(from: sent, source: "test")
            == ["Label": .string("nomac"), "Request": .string("GetValue"), "Key": .string("ProductVersion")])
    }

    @Test func errorsNameTheRequest() {
        let stream = ReplayStream(replies: [["Request": .string("StartService"), "Error": .string("InvalidService")]])
        #expect(throws: (any Error).self) { try LockdownClient(stream: stream).startService("com.apple.nothing") }
    }

    @Test func sessionSwitchesToTLSWhenAsked() throws {
        let stream = ReplayStream(replies: [
            ["Request": .string("StartSession"), "SessionID": .string("S"), "EnableSessionSSL": .boolean(true)],
        ])
        let lockdown = LockdownClient(stream: stream)
        let secured = ReplayStream(replies: [
            ["Request": .string("GetValue"), "Key": .string("ProductVersion"), "Value": .string("27.0.1")],
            ["Request": .string("StartService"), "Service": .string("com.apple.afc"), "Port": .integer(49_152)],
        ])
        try lockdown.startSession(hostID: "H", systemBUID: "B") { _ in secured }
        #expect(try lockdown.startService("com.apple.afc") == Lockdown.Service(port: 49_152, usesTLS: false))
    }

    @Test func pairRecordFields() throws {
        let record = [UInt8](BinaryPropertyList.swiftBuildData(.dictionary([
            "HostID": .string("H"), "SystemBUID": .string("B"),
            "HostCertificate": .data(Array("cert".utf8)), "HostPrivateKey": .data(Array("key".utf8)),
        ])))
        let pair = try PairRecord(bytes: record)
        #expect(pair.hostID == "H" && pair.systemBUID == "B" && pair.hostCertificate == Array("cert".utf8))
    }

    /// macOS's and libimobiledevice's usbmuxd both hand the record over as an XML property list.
    @Test func pairRecordInXML() throws {
        let record = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>DeviceCertificate</key>
        \t<data>ZGV2aWNl</data>
        \t<key>HostCertificate</key>
        \t<data>Y2VydA==</data>
        \t<key>HostID</key>
        \t<string>H</string>
        \t<key>HostPrivateKey</key>
        \t<data>a2V5</data>
        \t<key>RootCertificate</key>
        \t<data>cm9vdA==</data>
        \t<key>SystemBUID</key>
        \t<string>B</string>
        </dict>
        </plist>
        """
        let pair = try PairRecord(bytes: Array(record.utf8))
        #expect(pair.hostID == "H" && pair.systemBUID == "B" && pair.hostCertificate == Array("cert".utf8) && pair.hostPrivateKey == Array("key".utf8))
    }
}

/// mobile_image_mounter's queries as pymobiledevice3 sends them.
@Suite struct MobileImageMounterTests {
    @Test func copyDevicesEntries() throws {
        let stream = ReplayStream(replies: [["EntryList": .array([.dictionary(["DiskImageType": .string("Personalized"), "IsMounted": .boolean(true)])]),
                                             "Status": .string("Complete")]])
        #expect(try MobileImageMounter.mountedImageTypes(on: stream) == ["Personalized"])
        #expect(try PropertyListMessages.receive(from: ReplayStream(bytes: stream.written), source: "test") == ["Command": .string("CopyDevices")])
    }

    @Test func storedManifestIsAskedForByTheImagesSHA384() throws {
        let stream = ReplayStream(replies: [["ImageSignature": .data([1, 2, 3])]])
        #expect(try MobileImageMounter.storedManifest(forImage: Array("abc".utf8), on: stream) == [1, 2, 3])
        let request = try PropertyListMessages.receive(from: ReplayStream(bytes: stream.written), source: "test")
        // SHA-384 of "abc", FIPS 180-2's example.
        let digest = "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"
        #expect(request["ImageSignature"] == .data(stride(from: 0, to: digest.count, by: 2).map {
            UInt8(digest[digest.index(digest.startIndex, offsetBy: $0)..<digest.index(digest.startIndex, offsetBy: $0 + 2)], radix: 16)!
        }))
        #expect(request["PersonalizedImageType"] == .string("DeveloperDiskImage") && request["Command"] == .string("QueryPersonalizationManifest"))
        #expect(try MobileImageMounter.storedManifest(forImage: [], on: ReplayStream(replies: [["Error": .string("MissingManifest")]])) == nil)
    }
}
