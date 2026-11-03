import Foundation
import Testing
@testable import nomac

/// `nomac dwarfdump --uuid`: macOS's output (dwarfdump_experiments.py).
@Suite struct DwarfdumpCommandTests {
    func machO(cpu: UInt32, uuid: [UInt8]) -> [UInt8] {
        let words: [UInt32] = [0xfeed_facf, cpu, 0, 6, 1, 24, 0, 0, 0x1b, 24]
        return words.flatMap { value in (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } } + uuid
    }

    @Test func printsUUIDsAsMacOS() throws {
        let folder = NSTemporaryDirectory() + "dwarfdump-\(UUID().uuidString)"
        let dwarf = folder + "/Lib.dSYM/Contents/Resources/DWARF"
        try FileManager.default.createDirectory(atPath: dwarf, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try Data(machO(cpu: 0x0100_000c, uuid: Array(0..<16))).write(to: URL(fileURLWithPath: dwarf + "/Lib"))
        try Data("hello\n".utf8).write(to: URL(fileURLWithPath: folder + "/text.txt"))

        #expect(try DwarfdumpCommand.run(["--uuid", folder + "/Lib.dSYM"])
            == (0, "UUID: 00010203-0405-0607-0809-0A0B0C0D0E0F (arm64) \(dwarf)/Lib\n", ""))
        #expect(try DwarfdumpCommand.run(["--uuid", folder + "/text.txt", folder])
            == (1, "", "error: \(folder)/text.txt: The file was not recognized as a valid object file\nerror: \(folder): Is a directory\n"))
    }
}
