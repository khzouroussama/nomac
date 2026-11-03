import Foundation
import Testing
import NomacCore

@Suite struct SubprocessTests {
    static func openDescriptors() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    }

    /// Each run closes its pipes: firefox's `nomac verify` ran out of descriptors after about a
    /// thousand tool runs.
    @Test func runsLeaveNoDescriptorsOpen() throws {
        let before = try Self.openDescriptors()
        for _ in 0..<200 {
            let result = try Subprocess.run("/bin/sh", ["-c", "echo out; echo err >&2"])
            #expect(result.exitStatus == 0)
            #expect(result.standardOutput == Data("out\n".utf8))
            #expect(result.standardError == Data("err\n".utf8))
        }
        #expect(try Self.openDescriptors() - before < 20)
    }
}
