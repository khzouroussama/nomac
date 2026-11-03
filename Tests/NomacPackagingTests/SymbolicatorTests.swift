import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacPackaging

/// `nomac atos` against `atos -i` (Xcode 27.0) on the self-authored `SyntheticDSYM`, image
/// loaded at its `__TEXT` address: every 4 bytes of `__text` and two of `__const`, as atos
/// printed them (`symbolicate_experiments.py` checks real builds the same way).
@Suite struct SymbolicatorTests {
    static let observed: [UInt64: [String]] = [
        0x4000: ["foo() (in Synthetic) (Test.swift:1)"],
        0x4008: ["helper() (in Synthetic) (Inline.h:3)", "foo() (in Synthetic) (Inline.h:3)"],
        0x4010: ["foo() (in Synthetic) (/<compiler-generated>:0)"],
        0x4020: ["bar (in Synthetic) (Test.swift:10)"],
        0x4024: ["add (in Synthetic) (Inline.h:4)", "bar (in Synthetic) (/<compiler-generated>:7)"],
        0x4028: ["bar (in Synthetic) (Test.swift:11)"],
        0x4034: ["-[Foo bar] (in Synthetic) + 4"],
        0x4038: ["helper (in Synthetic) + 0"],
        0x4044: ["helper (in Synthetic) + 4"],
        0x4048: ["<deduplicated_symbol> (in Synthetic) + 0"],
        0x4054: ["ZedLike (in Synthetic) + 4"],
        0x405c: ["<deduplicated_symbol> (in Synthetic) + 4"],
        0x4064: ["lonely() (in Synthetic) (Test.swift:20)"],
        0x406c: ["solo (in Synthetic) (Test.swift:21)"],
        0x4070: [],
        0x407c: [],
        0x4084: ["data (in Synthetic) + 4"],
    ]

    static let swiftNames = ["$s4Test3fooyyF": "foo()", "$s4Test6helperyyF": "helper()", "$s4Test6lonelyyyF": "lonely()"]

    @Test func printsWhatAtosPrints() throws {
        let tmp = try TemporaryDirectory()
        try FileSystem.write(Data(SyntheticDSYM.dwarfFile(seed: 1)), to: tmp.path + "/Synthetic")
        let symbolicator = try #require(try Symbolicator.slices(dwarfFile: tmp.path + "/Synthetic", demangle: { Self.swiftNames[$0] ?? $0 }).first)
        #expect(symbolicator.architecture == "arm64")
        for (offset, lines) in Self.observed.sorted(by: { $0.key < $1.key }) {
            #expect(symbolicator.frames(offset: offset).map { $0.formatted(image: "Synthetic") } == lines, "offset 0x\(String(offset, radix: 16))")
        }
        // The Mach-O header, before the first section: nothing.
        #expect(symbolicator.frames(offset: 0x100).isEmpty)
    }

    @Test func demanglesAsAtos() throws {
        let toolchain = ProcessInfo.processInfo.environment["DEVELOPER_DIR"].map { $0 + "/Toolchains/XcodeDefault.xctoolchain/usr" }
        let demangle = Demangler(toolchain: toolchain)
        // Names atos printed for Retro Rampage's Engine (2026-11-03).
        if demangle.canDemangleSwift {
            #expect(demangle("$s6Engine6PlayerV6isDeadSbvg") == "Player.isDead.getter")
            #expect(demangle("$s6Engine7MonsterVWOh") == "outlined destroy of Monster")
        }
        #expect(demangle("_ZN8worklets12_GLOBAL__N_114downloadScriptEP5NSURL") == "worklets::(anonymous namespace)::downloadScript(NSURL*)")
        #expect(demangle("___ZN8worklets12_GLOBAL__N_114downloadScriptEP5NSURL_block_invoke")
            == "invocation function for block in worklets::(anonymous namespace)::downloadScript(NSURL*)")
        #expect(demangle("-[Foo bar]") == "-[Foo bar]")
    }
}
