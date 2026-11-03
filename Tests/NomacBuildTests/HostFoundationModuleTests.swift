import Foundation
import Testing
@testable import NomacBuild
import NomacCore
import NomacTestSupport

/// The module that loads Foundation into the build machine's compiles as a Mac's swift-syntax
/// does (B-125): Foundation's members become visible, its names do not.
@Suite struct HostFoundationModuleTests {
    /// The `usr` directory of the toolchain running the tests: the selected Xcode's on a Mac,
    /// else the one of the `swiftc` on `PATH`.
    static func hostToolchain() throws -> String {
        #if os(macOS)
        let developer = try ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
            ?? Subprocess.run("/usr/bin/xcode-select", ["-p"]).outputString.trimmingCharacters(in: .whitespacesAndNewlines)
        return developer + "/Toolchains/XcodeDefault.xctoolchain/usr"
        #else
        guard let swiftc = Subprocess.locate("swiftc") else { throw NomacError("no swiftc on PATH") }
        return ((FileSystem.resolvingSymbolicLinks(swiftc) as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        #endif
    }

    @Test func loadsFoundationWithoutImportingItsNames() throws {
        let tmp = try TemporaryDirectory()
        let toolchain = try Self.hostToolchain()
        let module = try HostFoundationModule.build(toolchain: toolchain, into: tmp.path + "/modules")
        #expect(module == tmp.path + "/modules/NomacHostFoundation.swiftmodule")
        func typecheck(_ source: String, swiftVersion: String = "5", helper: Bool = true) throws -> Int32 {
            let file = tmp.path + "/Client\(UUID().uuidString.prefix(8)).swift"
            try FileSystem.write(Data(source.utf8), to: file)
            let helperArguments = helper ? ["-I", tmp.path + "/modules", "-Xfrontend", "-import-module", "-Xfrontend", HostFoundationModule.name] : []
            return try Subprocess.run(toolchain + "/bin/swiftc", ["-typecheck", "-swift-version", swiftVersion, file] + helperArguments,
                                      currentDirectory: tmp.path).exitStatus
        }
        let member = "let trimmed = \" x \".trimmingCharacters(in: .whitespaces)\n"
        #expect(try typecheck(member) == 0)
        #expect(try typecheck(member, helper: false) != 0)
        #expect(try typecheck("let url: URL? = nil\n") != 0)
        #expect(try typecheck("@preconcurrency import Foundation\nfunc report() { fputs(\"x\\n\", stderr) }\n", swiftVersion: "6") == 0)
    }
}
