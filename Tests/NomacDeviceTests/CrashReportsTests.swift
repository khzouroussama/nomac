import Foundation
import NomacSigning
import Testing
@testable import NomacDevice

/// Reading crash reports: crashreportmover's `ping`, then AFC's directory listing, file
/// information and reads over crashreportcopymobile (docs/formats/crash-report.md).
@Suite struct CrashReportsTests {
    static func data(_ number: UInt64, _ bytes: [UInt8]) -> [UInt8] { AFC.packet(.data, number: number, operands: [], data: bytes) }
    static func strings(_ values: [String]) -> [UInt8] { values.flatMap { Array($0.utf8) + [0] } }

    @Test func moverAnswersPing() throws {
        try CrashReports.waitForMover(ReplayStream(bytes: Array("ping".utf8)))
        #expect(throws: (any Error).self) { try CrashReports.waitForMover(ReplayStream(bytes: Array("nope".utf8))) }
    }

    @Test func listsReportsDepthFirst() throws {
        let stream = ReplayStream(bytes: Self.data(0, Self.strings([".", "..", "App-2026-11-03-152414.ips", "Retired", "log.txt"]))
            + Self.data(1, Self.strings(["st_size", "24576", "st_ifmt", "S_IFREG", "st_mtime", "1762183454000000000"]))
            + Self.data(2, Self.strings(["st_size", "64", "st_ifmt", "S_IFDIR"]))
            + Self.data(3, Self.strings(["App-2026-11-02-143701.ips"]))
            + Self.data(4, Self.strings(["st_size", "100", "st_ifmt", "S_IFREG", "st_mtime", "1762090621000000000"]))
            + Self.data(5, Self.strings(["st_size", "3", "st_ifmt", "S_IFREG"])))
        let reports = try CrashReports.reports(afc: AFCClient(stream: stream))
        #expect(reports == [
            CrashReports.Report(path: "/App-2026-11-03-152414.ips", size: 24576, modified: 1_762_183_454),
            CrashReports.Report(path: "/Retired/App-2026-11-02-143701.ips", size: 100, modified: 1_762_090_621),
        ])
        let written = ReplayStream(bytes: stream.written)
        #expect(try AFC.header(written.read(40)).operation == AFC.Operation.readDirectory.rawValue)
    }

    @Test func downloadsInChunksUntilAShortRead() throws {
        let fileOpenResult = [UInt8](Array("CFA6LPAA".utf8)) + AFC.littleEndian(48) + AFC.littleEndian(48) + AFC.littleEndian(0) + AFC.littleEndian(0x0e) + AFC.littleEndian(9)
        let stream = ReplayStream(bytes: fileOpenResult + Self.data(1, Array("{\"bug_type\"".utf8)) + AFC.packet(.status, number: 2, operands: AFC.littleEndian(0)))
        #expect(try AFCClient(stream: stream).download("/App.ips") == Array("{\"bug_type\"".utf8))
        let expected = AFC.packet(.fileOpen, number: 0, operands: AFC.littleEndian(1) + AFC.path("/App.ips"))
            + AFC.packet(.read, number: 1, operands: AFC.littleEndian(9) + AFC.littleEndian(1 << 20))
            + AFC.packet(.fileClose, number: 2, operands: AFC.littleEndian(9))
        #expect(stream.written == expected)
    }
}
