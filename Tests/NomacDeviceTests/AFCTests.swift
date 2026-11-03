import Foundation
import NomacSigning
import Testing
@testable import NomacDevice

/// AFC's packets as libimobiledevice's `afc.c` and pymobiledevice3's `afc.py` write them
/// (docs/formats/afc.md).
@Suite struct AFCTests {
    static func status(_ number: UInt64, _ code: UInt64 = 0) -> [UInt8] {
        AFC.packet(.status, number: number, operands: AFC.littleEndian(code))
    }

    @Test func pathPacketBytes() {
        let packet = AFC.packet(.makeDirectory, number: 0, operands: AFC.path("PublicStaging"))
        #expect(Array(packet[0..<8]) == Array("CFA6LPAA".utf8))
        #expect(Array(packet[8..<40]) == AFC.littleEndian(54) + AFC.littleEndian(54) + AFC.littleEndian(0) + AFC.littleEndian(9))
        #expect(Array(packet[40...]) == Array("PublicStaging".utf8) + [0])
    }

    @Test func writeLengthsCoverTheHandleOnly() throws {
        let header = try AFC.header(Array(AFC.packet(.write, number: 2, operands: AFC.littleEndian(5), data: [1, 2, 3])[0..<40]))
        #expect(header == AFC.Header(entireLength: 51, thisLength: 48, packetNumber: 2, operation: 0x10))
    }

    @Test func uploadOpensWritesAndCloses() throws {
        let opened = [UInt8](Array("CFA6LPAA".utf8)) + AFC.littleEndian(48) + AFC.littleEndian(48) + AFC.littleEndian(0) + AFC.littleEndian(0x0e) + AFC.littleEndian(7)
        let stream = ReplayStream(bytes: opened + Self.status(1) + Self.status(2))
        try AFCClient(stream: stream).upload([9, 8], to: "PublicStaging/App.ipa")
        let expected = AFC.packet(.fileOpen, number: 0, operands: AFC.littleEndian(3) + AFC.path("PublicStaging/App.ipa"))
            + AFC.packet(.write, number: 1, operands: AFC.littleEndian(7), data: [9, 8])
            + AFC.packet(.fileClose, number: 2, operands: AFC.littleEndian(7))
        #expect(stream.written == expected)
    }

    @Test func statusErrorsNameThePath() {
        let stream = ReplayStream(bytes: Self.status(0, 8))
        #expect(throws: (any Error).self) { try AFCClient(stream: stream).remove("PublicStaging/none") }
    }
}

/// installation_proxy's commands and progress (docs/formats/lockdown.md).
@Suite struct InstallationProxyTests {
    @Test func installReportsEachStageUntilComplete() throws {
        let stream = ReplayStream(replies: [
            ["Status": .string("CreatingStagingDirectory"), "PercentComplete": .integer(5)],
            ["Status": .string("InstallingApplication"), "PercentComplete": .integer(60)],
            ["Status": .string("Complete")],
        ])
        var stages: [String] = []
        try InstallationProxyClient(stream: stream).run(InstallationProxy.install(packagePath: "PublicStaging/App.ipa")) { status, percent in
            stages.append("\(status) \(percent ?? -1)")
        }
        #expect(stages == ["CreatingStagingDirectory 5", "InstallingApplication 60"])
        #expect(try PropertyListMessages.receive(from: ReplayStream(bytes: stream.written), source: "test") == [
            "Command": .string("Install"), "PackagePath": .string("PublicStaging/App.ipa"), "ClientOptions": .dictionary([:]),
        ])
    }

    @Test func errorsCarryTheDescription() {
        let stream = ReplayStream(replies: [["Error": .string("ApplicationVerificationFailed"), "ErrorDescription": .string("No code signature found.")]])
        #expect(throws: (any Error).self) {
            try InstallationProxyClient(stream: stream).run(InstallationProxy.uninstall(bundleIdentifier: "org.nomac.app")) { _, _ in }
        }
    }
}
