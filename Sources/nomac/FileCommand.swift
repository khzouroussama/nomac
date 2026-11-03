import ArgumentParser
import Foundation
import NomacCore

/// `nomac file`: macOS's `file` for the files build scripts ask about (CocoaPods' frameworks script
/// matches `*"dynamically linked shared library"*` and `*"Mach-O "*"dSYM companion"*`), behind the
/// launcher `nomac toolchain install` writes. Mach-O files, thin and universal, `ar` archives, empty
/// files and folders are described as macOS's `file` describes them, symbolic links followed
/// (`.github/scripts/file_experiments.py`); other files are passed to the machine's `file`.
struct FileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file",
        abstract: "Describe files as macOS's file does for build scripts.",
        discussion: "Takes file paths (.github/scripts/file_experiments.py).",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "The files to describe.")
    var arguments: [String] = []

    func run() throws {
        let brief = arguments.contains("-b")
        let paths = arguments.filter { $0 != "-b" && $0 != "-L" }
        guard !paths.isEmpty, !paths.contains(where: { $0.hasPrefix("-") }) else {
            throw NomacError("nomac file takes file paths, -b and -L, not 'file \(arguments.joined(separator: " "))'")
        }
        // Several files' descriptions are aligned past the longest name and its colon.
        let width = paths.map { $0.count + 1 }.max() ?? 0
        for path in paths {
            let lines = try Self.describe(path)
            let name = path + ":"
            print(brief ? lines[0] : name + String(repeating: " ", count: width - name.count) + " " + lines[0])
            for line in lines.dropFirst() { print(line) }
        }
    }

    /// What macOS's `file` prints for `path`: its description, then, for a universal file, one line
    /// for each architecture, which keeps the file's name with `-b` too.
    static func describe(_ path: String) throws -> [String] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else {
            return ["cannot open `\(path)' (No such file or directory)"]
        }
        if isFolder.boolValue { return ["directory"] }
        let bytes = [UInt8](FileManager.default.contents(atPath: path) ?? Data())
        if bytes.isEmpty { return ["empty"] }
        if let thin = machO(bytes, at: 0) { return [thin] }
        if let slices = universal(bytes) {
            let entries = slices.map { "[\($0.arch):\($0.description)]" }.joined(separator: " ")
            return ["Mach-O universal binary with \(slices.count) architectures: \(entries)"]
                + slices.map { "\(path) (for architecture \($0.arch)):\t\($0.description)" }
        }
        if bytes.starts(with: Array("!<arch>\n".utf8)) {
            // The first member's name, which BSD ar writes after the header as `#1/<length>`.
            var member = bytes.count >= 24 ? String(decoding: bytes[8..<24], as: UTF8.self) : ""
            if member.hasPrefix("#1/"), let length = Int(member.dropFirst(3).trimmingCharacters(in: .whitespaces)), bytes.count >= 68 + length {
                member = String(decoding: bytes[68..<68 + length], as: UTF8.self)
            }
            return ["current ar archive" + (member.hasPrefix("__.SYMDEF") ? " random library" : "")]
        }
        guard let system = ["/usr/bin/file", "/bin/file"].first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return ["data"]
        }
        return [try Subprocess.run(system, ["-b", "-L", path]).outputString.trimmingCharacters(in: .newlines)]
    }

    /// A thin Mach-O file's description, as macOS's `file` words it: `Mach-O 64-bit <type> <arch>`.
    static func machO(_ bytes: [UInt8], at offset: Int) -> String? {
        func u32(_ at: Int) -> UInt32? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return (0..<4).reduce(0) { $0 | UInt32(bytes[at + $1]) << (8 * UInt32($1)) }
        }
        guard let magic = u32(offset), magic == 0xfeed_facf || magic == 0xfeed_face,
              let cpu = u32(offset + 4), let subtype = u32(offset + 8), let type = u32(offset + 12),
              let arch = architecture(cpu: cpu, subtype: subtype), let kind = kinds[type] else { return nil }
        return (magic == 0xfeed_facf ? "Mach-O 64-bit " : "Mach-O ") + kind + " " + arch
    }

    static let kinds: [UInt32: String] = [1: "object", 2: "executable", 6: "dynamically linked shared library", 8: "bundle", 10: "dSYM companion file"]

    /// The slices of a universal file, each with its architecture and description.
    static func universal(_ bytes: [UInt8]) -> [(arch: String, description: String)]? {
        func be32(_ at: Int) -> UInt32? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return (0..<4).reduce(0) { $0 << 8 | UInt32(bytes[at + $1]) }
        }
        guard be32(0) == 0xcafe_babe, let count = be32(4), count > 0, count < 20 else { return nil }
        var slices: [(String, String)] = []
        for index in 0..<Int(count) {
            let entry = 8 + index * 20
            guard let cpu = be32(entry), let subtype = be32(entry + 4), let offset = be32(entry + 8),
                  let arch = architecture(cpu: cpu, subtype: subtype), let description = machO(bytes, at: Int(offset)) else { return nil }
            slices.append((arch, description))
        }
        return slices
    }

    /// macOS's names of the architectures Apple platforms build for.
    static func architecture(cpu: UInt32, subtype: UInt32) -> String? {
        switch (cpu, subtype & 0x00ff_ffff) {
        case (0x0100_000c, 0): "arm64"
        case (0x0100_000c, 2): "arm64e"
        case (0x0200_000c, 1): "arm64_32_v8"
        case (0x0100_0007, 3): "x86_64"
        default: nil
        }
    }
}
