import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacPackaging

/// A crash report shaped as iOS 27.0.1 writes one (`.ips`: the header line, then the report),
/// its app frames symbolicated from `SyntheticDSYM` as `SymbolicatorTests` observed atos do.
@Suite struct CrashReportTests {
    @Test func symbolicatesTheAppsFramesFromTheirDSYM() throws {
        let tmp = try TemporaryDirectory()
        try FileSystem.write(Data(SyntheticDSYM.dwarfFile(seed: 1)), to: tmp.path + "/Synthetic")
        let symbolicator = try #require(try Symbolicator.slices(dwarfFile: tmp.path + "/Synthetic", demangle: { SymbolicatorTests.swiftNames[$0] ?? $0 }).first)
        let header = #"{"app_name":"App","bundleID":"org.nomac.app","bug_type":"309","os_version":"iPhone OS 27.0.1 (24A446)"}"#
        let body: [String: Any] = [
            "procName": "App", "pid": 77,
            "exception": ["type": "EXC_CRASH", "signal": "SIGABRT"],
            "termination": ["namespace": "SIGNAL", "code": 6, "indicator": "Abort trap: 6"],
            "asi": ["libsystem_c.dylib": ["abort() called"]],
            "usedImages": [["name": "CoreFoundation", "uuid": "0000"], ["name": "App", "uuid": symbolicator.uuid.lowercased()]],
            "lastExceptionBacktrace": [["imageIndex": 0, "imageOffset": 0x98190, "symbol": "__exceptionPreprocess", "symbolLocation": 164],
                                       // A Mac's crash reporter names a simulator app's frames: the dSYM's lines win.
                                       ["imageIndex": 1, "imageOffset": 0x4008, "symbol": "foo()", "symbolLocation": 8]],
            "faultingThread": 0,
            "threads": [["queue": "com.apple.main-thread", "frames": [["imageIndex": 1, "imageOffset": 0x4024], ["imageIndex": 1, "imageOffset": 0x100]]]],
        ]
        let bytes = Array(header.utf8) + [0x0a] + [UInt8](try JSONSerialization.data(withJSONObject: body))
        let report = try CrashReport(bytes: bytes, path: "App.ips")
        #expect(report.imageUUIDs.contains(symbolicator.uuid))
        let text = report.render(symbolicators: [symbolicator.uuid: symbolicator])
        let pad = { (index: Int, image: String) in "\(index)".padding(toLength: 4, withPad: " ", startingAt: 0) + image.padding(toLength: 30, withPad: " ", startingAt: 0) + " " }
        #expect(text == """
            Process: App [77]
            Identifier: org.nomac.app
            OS Version: iPhone OS 27.0.1 (24A446)
            Exception: EXC_CRASH (SIGABRT)
            Termination: SIGNAL 6, Abort trap: 6
            Application Specific Information (libsystem_c.dylib): abort() called

            Last Exception Backtrace:
            \(pad(0, "CoreFoundation"))__exceptionPreprocess + 164
            \(pad(1, "App"))helper() (in App) (Inline.h:3)
            \(String(repeating: " ", count: 35))foo() (in App) (Inline.h:3)

            Thread 0 Crashed (com.apple.main-thread):
            \(pad(0, "App"))add (in App) (Inline.h:4)
            \(String(repeating: " ", count: 35))bar (in App) (/<compiler-generated>:7)
            \(pad(1, "App"))0x100

            """)
        #expect(throws: NomacError.self) { try CrashReport(bytes: Array("not json".utf8), path: "x.ips") }
    }
}
