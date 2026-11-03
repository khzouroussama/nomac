import Foundation
import NomacCore

/// A module of nomac's that imports Foundation, which the Linux compiles for the build machine
/// import (``LinuxCompiler``) so that Foundation is loaded as on a Mac, without its names (B-125).
///
/// On a Mac swift-syntax's `SwiftSyntaxBuilder` imports OSLog (`#if canImport(OSLog)`), which
/// loads Foundation, so Foundation's members are visible to every macro target that uses it;
/// swiftfin's StatefulMacro calls `String.trimmingCharacters(in:)` importing only swift-syntax.
/// Importing Foundation itself into those compiles also imports its names, which breaks packages
/// that import it `@preconcurrency` on Linux (xctest-dynamic-overlay's `IssueReporting`).
public enum HostFoundationModule {
    public static let name = "NomacHostFoundation"
    /// Where the module is, in the toolchain's `usr`.
    public static let relativeDirectory = "lib/nomac/modules"

    /// Compiles the module with the `swiftc` of the toolchain whose `usr` is `toolchain`, for the
    /// machine it runs on, into `directory`; returns the module's path.
    @discardableResult
    public static func build(toolchain: String, into directory: String) throws -> String {
        let swiftc = toolchain + "/bin/swiftc"
        guard FileManager.default.isExecutableFile(atPath: swiftc) else {
            throw NomacError("not the usr directory of a Swift toolchain (no bin/swiftc)", path: toolchain)
        }
        let scratch = FileManager.default.temporaryDirectory.path + "/nomac-host-foundation-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        try FileSystem.write(Data("import Foundation\n".utf8), to: scratch + "/\(name).swift")
        try FileSystem.createDirectory(directory)
        let module = directory + "/\(name).swiftmodule"
        let result = try Subprocess.run(swiftc, ["-emit-module", "-parse-as-library", "-module-name", name, "-emit-module-path", module,
                                                 scratch + "/\(name).swift"], currentDirectory: scratch)
        guard result.exitStatus == 0 else {
            throw NomacError("could not compile the \(name) module:\n" + result.errorString + result.outputString, path: swiftc)
        }
        return module
    }

    /// Builds the module into the `XcodeDefault` toolchain of `developerDirectory`.
    @discardableResult
    public static func install(toolchain: String, developerDirectory: String) throws -> String {
        try build(toolchain: FileSystem.absolute(toolchain),
                  into: FileSystem.absolute(developerDirectory) + "/Toolchains/XcodeDefault.xctoolchain/usr/" + relativeDirectory)
    }
}
