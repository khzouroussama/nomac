import ArgumentParser
import Crypto
import Foundation
import NomacCore

/// `nomac md5`: macOS's BSD `md5` (`/sbin/md5`) for build scripts, behind the launcher `nomac
/// toolchain install` writes (Bugsnag's source map name, `$(md5 -qs "$CONFIGURATION_BUILD_DIR")`).
/// As Xcode 27.0's macOS's (`.github/scripts/md5_experiments.py`): `-s` prints the last string's
/// digest alone, whatever the other options and files; files are `MD5 (<file>) = <digest>`, the
/// digest alone with `-q` and `<digest> <file>` with `-r`; standard input without files.
struct MD5Command: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "md5",
        abstract: "Compute MD5 digests as macOS's md5 does.",
        discussion: "Takes [-qr] [-s string] [files ...] (.github/scripts/md5_experiments.py).",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "[-qr] [-s string] [files ...]")
    var arguments: [String] = []

    static let usage = "usage: md5 [-pqrtx] [-c string] [-s string] [files ...]\n"

    func run() throws {
        let (status, output, errors) = try Self.run(arguments, standardInput: { FileHandle.standardInput.readDataToEndOfFile() })
        FileHandle.standardOutput.write(Data(output.utf8))
        FileHandle.standardError.write(Data(errors.utf8))
        if status != 0 { throw ExitCode(status) }
    }

    /// The exit status, standard output and standard error.
    static func run(_ arguments: [String], standardInput: () -> Data) throws -> (Int32, String, String) {
        var quiet = false, reverse = false
        var string: String?
        var index = 0
        options: while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { index += 1; break }
            guard argument.hasPrefix("-"), argument.count > 1 else { break }
            var letters = Substring(argument.dropFirst())
            while let letter = letters.popFirst() {
                switch letter {
                case "q": quiet = true
                case "r": reverse = true
                case "s":
                    if !letters.isEmpty {
                        string = String(letters)
                    } else if index + 1 < arguments.count {
                        index += 1
                        string = arguments[index]
                    } else {
                        return (1, "", "md5: option requires an argument -- s\n" + usage)
                    }
                    index += 1
                    continue options
                case "p", "t", "x", "c":
                    throw NomacError("nomac md5 provides -q, -r and -s, not -\(letter)")
                default:
                    return (1, "", "md5: invalid option -- \(letter)\n" + usage)
                }
            }
            index += 1
        }
        func digest(_ data: Data) -> String { Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        if let string { return (0, digest(Data(string.utf8)) + "\n", "") }
        let files = arguments[index...]
        if files.isEmpty { return (0, digest(standardInput()) + "\n", "") }
        var status: Int32 = 0, output = "", errors = ""
        for file in files {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file, isDirectory: &isFolder) else {
                status = 1
                errors += "md5: \(file): No such file or directory\n"
                continue
            }
            guard !isFolder.boolValue else {
                status = 1
                errors += "md5: \(file): Is a directory\n"
                continue
            }
            guard let data = FileManager.default.contents(atPath: file) else { throw NomacError("cannot read the file", path: file) }
            output += quiet ? digest(data) + "\n" : reverse ? "\(digest(data)) \(file)\n" : "MD5 (\(file)) = \(digest(data))\n"
        }
        return (status, output, errors)
    }
}
