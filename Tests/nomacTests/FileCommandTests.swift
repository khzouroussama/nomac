import Foundation
import Testing
@testable import nomac

/// `nomac file`: macOS's wording for the files CocoaPods' scripts ask about (file_experiments.py).
@Suite struct FileCommandTests {
    func header(magic: UInt32 = 0xfeed_facf, cpu: UInt32, subtype: UInt32, type: UInt32) -> [UInt8] {
        [magic, cpu, subtype, type, 0, 0, 0, 0].flatMap { value in (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
    }

    func write(_ bytes: [UInt8], _ name: String, in folder: String) throws -> String {
        let path = folder + "/" + name
        try Data(bytes).write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test func wordsMachOFilesArchivesAndFoldersAsMacOS() throws {
        let folder = NSTemporaryDirectory() + "file-command-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let dylib = header(cpu: 0x0100_000c, subtype: 0, type: 6)
        let simulator = header(cpu: 0x0100_0007, subtype: 3, type: 6)

        #expect(try FileCommand.describe(write(dylib, "dylib", in: folder)) == ["Mach-O 64-bit dynamically linked shared library arm64"])
        #expect(try FileCommand.describe(write(header(cpu: 0x0100_000c, subtype: 0, type: 10), "dsym", in: folder)) == ["Mach-O 64-bit dSYM companion file arm64"])
        #expect(try FileCommand.describe(write(header(cpu: 0x0100_000c, subtype: 0x8000_0002, type: 2), "e", in: folder)) == ["Mach-O 64-bit executable arm64e"])
        #expect(try FileCommand.describe(write(header(magic: 0xfeed_face, cpu: 0x0200_000c, subtype: 1, type: 6), "w", in: folder))
            == ["Mach-O dynamically linked shared library arm64_32_v8"])

        let fat = [0xcafe_babe, 2, 0x0100_0007, 3, 64, UInt32(simulator.count), 0, 0x0100_000c, 0, 128, UInt32(dylib.count), 0]
            .flatMap { value in (0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
        let universal = fat + [UInt8](repeating: 0, count: 64 - fat.count) + simulator + [UInt8](repeating: 0, count: 64 - simulator.count) + dylib
        let path = try write(universal, "universal", in: folder)
        #expect(try FileCommand.describe(path) == [
            "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit dynamically linked shared library x86_64] [arm64:Mach-O 64-bit dynamically linked shared library arm64]",
            "\(path) (for architecture x86_64):\tMach-O 64-bit dynamically linked shared library x86_64",
            "\(path) (for architecture arm64):\tMach-O 64-bit dynamically linked shared library arm64",
        ])

        let member = Array("#1/20           0           0     0     644     28        `\n__.SYMDEF SORTED\0\0\0\0".utf8)
        #expect(try FileCommand.describe(write(Array("!<arch>\n".utf8) + member, "static.a", in: folder)) == ["current ar archive random library"])
        #expect(try FileCommand.describe(write(Array("!<arch>\nobject.o/       ".utf8), "plain.a", in: folder)) == ["current ar archive"])
        #expect(try FileCommand.describe(write([], "empty", in: folder)) == ["empty"])
        #expect(try FileCommand.describe(folder) == ["directory"])
        #expect(try FileCommand.describe(folder + "/missing") == ["cannot open `\(folder)/missing' (No such file or directory)"])
    }
}
