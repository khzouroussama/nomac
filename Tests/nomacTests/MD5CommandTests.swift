import Foundation
import Testing
@testable import nomac

/// `nomac md5`: macOS's BSD md5 output (md5_experiments.py).
@Suite struct MD5CommandTests {
    @Test func printsDigestsAsMacOS() throws {
        let folder = NSTemporaryDirectory() + "md5-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let file = folder + "/a.txt"
        try Data("hello\n".utf8).write(to: URL(fileURLWithPath: file))
        let input = { Data("hello\n".utf8) }
        let digest = "b1946ac92492d2347c6235b4d2611184"

        #expect(try MD5Command.run(["-qs", "abc"], standardInput: input) == (0, "900150983cd24fb0d6963f7d28e17f72\n", ""))
        #expect(try MD5Command.run(["-s", "abc", "-s", "def", file], standardInput: input) == (0, "4ed9407630eb1000c0f6b63842defa7d\n", ""))
        #expect(try MD5Command.run([file], standardInput: input) == (0, "MD5 (\(file)) = \(digest)\n", ""))
        #expect(try MD5Command.run(["-r", file], standardInput: input) == (0, "\(digest) \(file)\n", ""))
        #expect(try MD5Command.run(["-rq", file, folder], standardInput: input) == (1, "\(digest)\n", "md5: \(folder): Is a directory\n"))
        #expect(try MD5Command.run([], standardInput: input) == (0, "\(digest)\n", ""))
        #expect(try MD5Command.run(["-n"], standardInput: input) == (1, "", "md5: invalid option -- n\n" + MD5Command.usage))
    }
}
