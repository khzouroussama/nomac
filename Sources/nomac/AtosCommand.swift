import ArgumentParser
import Foundation
import NomacCore
import NomacPackaging

/// `nomac atos`: the functions and source lines at addresses of a binary, from its dSYM, as
/// `atos -i` prints them.
struct AtosCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "atos",
        abstract: "Symbolicate addresses, as 'atos -i'.",
        discussion: """
        For each address, the function whose DWARF ranges hold it and the calls inlined there, \
        innermost first, each '<function> (in <image>) (<file>:<line>)', then an empty line; \
        without DWARF, '<symbol> (in <image>) + <offset>' (docs/formats/crash-report.md). Swift \
        names are demangled in simplified form with the developer directory's toolchain.
        """
    )

    @Option(name: .customShort("o"), help: "A .dSYM bundle or its DWARF file.")
    var object: String

    @Option(name: .customLong("arch", withSingleDash: true), help: "The slice's architecture (arm64, arm64_32, x86_64).")
    var arch: String = "arm64"

    @Option(name: .customShort("l"), help: "The address the image is loaded at (default: its __TEXT address).")
    var load: String?

    @Flag(name: .customShort("i"), help: "Print inlined frames (the only output nomac writes).")
    var inlined = false

    @Option(help: "An Xcode Contents/Developer directory, for its Swift demangler.")
    var developerDir: String?

    @Argument(help: "Addresses, hexadecimal with 0x.")
    var addresses: [String]

    func run() throws {
        guard inlined else { throw ValidationError("nomac atos prints inlined frames, as atos -i does: pass -i") }
        let path = FileSystem.absolute(object)
        let dwarf = FileSystem.isDirectory(path) ? try Self.dwarfFiles(dsym: path).first ?? path : path
        let developer = try DeveloperDirectory.resolveIfAvailable(option: developerDir, strictXcode: false)
        let demangle = Demangler(toolchain: developer.map { $0 + "/Toolchains/XcodeDefault.xctoolchain/usr" })
        guard let symbolicator = try Symbolicator.slices(dwarfFile: dwarf, demangle: { demangle($0) }).first(where: { $0.architecture == arch }) else {
            throw NomacError("the dSYM has no \(arch) slice", path: dwarf)
        }
        let image = (dwarf as NSString).lastPathComponent
        let base = try load.map(Self.number) ?? symbolicator.textAddress
        for text in addresses {
            let address = try Self.number(text)
            let frames = symbolicator.frames(offset: address &- base)
            // An address without a function is an empty line, before the separating one.
            for line in frames.isEmpty ? [""] : frames.map({ $0.formatted(image: image) }) { print(line) }
            print("")
        }
    }

    static func dwarfFiles(dsym: String) throws -> [String] {
        let folder = dsym + "/Contents/Resources/DWARF"
        return try FileSystem.sortedContents(of: folder).map { folder + "/" + $0 }
    }

    static func number(_ text: String) throws -> UInt64 {
        guard let value = text.lowercased().hasPrefix("0x") ? UInt64(text.dropFirst(2), radix: 16) : UInt64(text) else {
            throw ValidationError("not an address: \(text)")
        }
        return value
    }
}
