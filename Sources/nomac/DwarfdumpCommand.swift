import ArgumentParser
import Foundation
import NomacCore

/// `nomac dwarfdump`: Xcode's `dwarfdump --uuid` for build scripts, behind the launcher `nomac
/// toolchain install` writes where Xcode keeps the tool (expo-modules-autolinking's
/// `resolve-dsym-sourcemaps.js` names a dSYM's `<UUID>.plist` after it). As macOS's
/// `/usr/bin/dwarfdump` (`.github/scripts/dwarfdump_experiments.py`): `UUID: <UUID> (<arch>) <path>`
/// for each slice of a Mach-O file that has an `LC_UUID`, a dSYM bundle read as the files in its
/// `Contents/Resources/DWARF`; nothing for objects and static archives, which Xcode's tools write
/// without one; an error for anything else, the exit status 1.
struct DwarfdumpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dwarfdump",
        abstract: "Print Mach-O files' and dSYMs' UUIDs as Xcode's dwarfdump --uuid does.",
        discussion: "Takes --uuid <path> ... (.github/scripts/dwarfdump_experiments.py).",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "--uuid <path> ...")
    var arguments: [String] = []

    func run() throws {
        let (status, output, errors) = try Self.run(arguments)
        FileHandle.standardOutput.write(Data(output.utf8))
        FileHandle.standardError.write(Data(errors.utf8))
        if status != 0 { throw ExitCode(status) }
    }

    /// The exit status, standard output and standard error.
    static func run(_ arguments: [String]) throws -> (Int32, String, String) {
        let options = arguments.filter { $0.hasPrefix("-") }
        if let value = options.first(where: { $0.hasPrefix("--uuid=") || $0.hasPrefix("-uuid=") })?.split(separator: "=", maxSplits: 1).last {
            return (1, "", "dwarfdump: for the --uuid option: '\(value)' is invalid value for boolean argument! Try 0 or 1\n")
        }
        guard !options.isEmpty, options.allSatisfy({ $0 == "--uuid" || $0 == "-uuid" }) else {
            throw NomacError("nomac dwarfdump provides --uuid, not 'dwarfdump \(arguments.joined(separator: " "))'")
        }
        var status: Int32 = 0, output = "", errors = ""
        for path in arguments where !path.hasPrefix("-") {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else {
                status = 1
                errors += "error: \(path): No such file or directory\n"
                continue
            }
            var files = [path]
            if isFolder.boolValue {
                let dwarf = path + "/Contents/Resources/DWARF"
                guard path.hasSuffix(".dSYM"), let names = try? FileManager.default.contentsOfDirectory(atPath: dwarf) else {
                    status = 1
                    errors += "error: \(path): Is a directory\n"
                    continue
                }
                files = names.sorted().map { dwarf + "/" + $0 }
            }
            for file in files {
                let bytes = [UInt8](FileManager.default.contents(atPath: file) ?? Data())
                if bytes.starts(with: Array("!<arch>\n".utf8)) { continue }
                guard let slices = try self.slices(bytes, path: file) else {
                    status = 1
                    errors += "error: \(file): The file was not recognized as a valid object file\n"
                    continue
                }
                for (arch, uuid) in slices {
                    output += "UUID: \(uuid) (\(arch)) \(file)\n"
                }
            }
        }
        return (status, output, errors)
    }

    /// Each slice's architecture and `LC_UUID`, slices without one left out; nil when the bytes
    /// are no Mach-O file.
    static func slices(_ bytes: [UInt8], path: String) throws -> [(String, String)]? {
        func be32(_ at: Int) -> Int? { at >= 0 && at + 4 <= bytes.count ? bytes[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } : nil }
        if be32(0) == 0xcafe_babe, let count = be32(4) {
            var found: [(String, String)] = []
            for index in 0..<count {
                guard let offset = be32(8 + index * 20 + 8), let size = be32(8 + index * 20 + 12), offset + size <= bytes.count,
                      let slice = try thin(Array(bytes[offset..<(offset + size)]), path: path) else { return nil }
                found += slice
            }
            return found
        }
        return try thin(bytes, path: path)
    }

    /// A thin Mach-O file's `LC_UUID` (0x1b, the UUID at 8; `<mach-o/loader.h>`) with its architecture.
    static func thin(_ bytes: [UInt8], path: String) throws -> [(String, String)]? {
        func u32(_ at: Int) -> Int? { at >= 0 && at + 4 <= bytes.count ? (0..<4).reduce(0) { $0 | Int(bytes[at + $1]) << (8 * $1) } : nil }
        guard let magic = u32(0), magic == 0xfeed_facf || magic == 0xfeed_face, let cpu = u32(4), let count = u32(16) else { return nil }
        var offset = magic == 0xfeed_facf ? 32 : 28
        for _ in 0..<count {
            guard let command = u32(offset), let size = u32(offset + 4), size > 0 else { return nil }
            if command == 0x1b, offset + 24 <= bytes.count {
                guard let arch = architectures[cpu] else {
                    throw NomacError("nomac dwarfdump names arm64 and x86_64 slices, not CPU type \(cpu)", path: path)
                }
                let hex = bytes[(offset + 8)..<(offset + 24)].map { String(format: "%02X", $0) }.joined()
                let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { range in
                    String(hex[hex.index(hex.startIndex, offsetBy: range.lowerBound)..<hex.index(hex.startIndex, offsetBy: range.upperBound)])
                }
                return [(arch, groups.joined(separator: "-"))]
            }
            offset += size
        }
        return []
    }

    /// The architectures the experiment observes, by CPU type.
    static let architectures = [0x0100_000c: "arm64", 0x0100_0007: "x86_64"]
}
