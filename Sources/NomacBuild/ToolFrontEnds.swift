import Foundation
import NomacCore

/// `tapi stubify`, as Swift Build's `GenerateTAPI` runs it: `tapi stubify -isysroot <sdk>
/// -F<dir> -L<dir> [-iframework <dir>] [--inline-private-frameworks] <dylib> -o <tbd>`. The search
/// paths and `--inline-private-frameworks` did not change tapi's output for the libraries
/// observed (`tapi_experiments.py` `swift-build-options`), which re-export nothing.
public enum TAPITool {
    public static func run(_ arguments: [String]) throws {
        guard arguments.first == "stubify" else {
            throw NomacError("nomac's tapi has only 'tapi stubify' (B-106)")
        }
        var input: String?
        var output: String?
        var index = 1
        func value(_ option: String) throws -> String {
            guard index + 1 < arguments.count else { throw NomacError("\(option) needs a value") }
            index += 2
            return arguments[index - 1]
        }
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-o" {
                output = try value(argument)
            } else if ["-isysroot", "-F", "-L", "-iframework"].contains(argument) {
                _ = try value(argument)
            } else if argument == "--inline-private-frameworks" {
                index += 1
            } else if argument.hasPrefix("-F") || argument.hasPrefix("-L") {
                index += 1
            } else if argument.hasPrefix("-") {
                throw NomacError("nomac's tapi stubify does not take '\(argument)' (B-106)")
            } else {
                guard input == nil else { throw NomacError("tapi stubify takes one library") }
                input = argument
                index += 1
            }
        }
        guard let input, let output else { throw NomacError("usage: tapi stubify <library> -o <tbd>") }
        let stub = try TAPIStub.stubify(MachODylib(path: input), path: input)
        try FileSystem.write(Data(stub.utf8), to: output)
    }
}

/// `dsymutil`: LLVM's, then the dSYM's Info.plist as dsymutil writes it on macOS
/// (``DSYMInfoPlist``).
public enum DsymutilTool {
    /// dsymutil's options that take a separate value (`tools/dsymutil/Options.td`).
    static let separateValueOptions: Set<String> = [
        "-o", "--o", "-out", "--out", "--oso-prepend-path", "--object-prefix-map", "--arch", "--accelerator",
        "--toolchain", "--num-threads", "-num-threads", "-j", "--reproducer", "--use-reproducer",
        "--remarks-prepend-path", "--remarks-output-format", "--linker", "--build-variant-suffix",
        "--embed-resource", "-D", "--D", "-cas", "--cas", "--cas-plugin-path", "--cas-plugin-option", "--verify-dwarf",
    ]

    /// Runs `llvmDsymutil` with `arguments` and returns its exit status.
    public static func run(_ arguments: [String], llvmDsymutil: String) throws -> Int32 {
        let status = try Subprocess.run(llvmDsymutil, arguments, passthrough: true).exitStatus
        guard status == 0, let plist = infoPlist(arguments),
              FileManager.default.fileExists(atPath: plist.bundleRoot + "/Contents/Info.plist") else { return status }
        try DSYMInfoPlist.rewrite(bundleRoot: plist.bundleRoot, executable: plist.executable, toolchain: plist.toolchain)
        return status
    }

    /// The dSYM whose Info.plist dsymutil wrote for `arguments`: the output (`-o`, `--out`, `-o=`,
    /// or the input with `.dSYM`), its one input and `--toolchain`. None for a flat output, which
    /// has no Info.plist, or for several inputs or none, which Swift Build does not run.
    static func infoPlist(_ arguments: [String]) -> (bundleRoot: String, executable: String, toolchain: String?)? {
        var inputs: [String] = []
        var output: String?
        var toolchain: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if separateValueOptions.contains(argument), index + 1 < arguments.count {
                let value = arguments[index + 1]
                if ["-o", "--o", "-out", "--out"].contains(argument) { output = value }
                if argument == "--toolchain" { toolchain = value }
                index += 2
                continue
            }
            for prefix in ["-o=", "--o=", "-out=", "--out="] where argument.hasPrefix(prefix) {
                output = String(argument.dropFirst(prefix.count))
            }
            if argument.hasPrefix("--toolchain=") { toolchain = String(argument.dropFirst("--toolchain=".count)) }
            if argument == "--flat" || argument == "-f" { return nil }
            if !argument.hasPrefix("-") { inputs.append(argument) }
            index += 1
        }
        guard inputs.count == 1 else { return nil }
        return (output ?? inputs[0] + ".dSYM", inputs[0], toolchain)
    }
}
