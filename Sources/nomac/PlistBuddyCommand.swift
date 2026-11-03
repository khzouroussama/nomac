import ArgumentParser
import Foundation
import NomacCore
import NomacPlist

/// `nomac PlistBuddy`: macOS's `/usr/libexec/PlistBuddy` for the commands build scripts run,
/// behind the launcher `nomac toolchain install` writes and the path scripts call it by.
struct PlistBuddyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "PlistBuddy",
        abstract: "Read and change a property list as macOS's PlistBuddy does for build scripts.",
        discussion: "Takes '-c <command> ... <file>' with the commands Print, Add, Set and Delete (.github/scripts/plistbuddy_experiments.py).",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "PlistBuddy's arguments.")
    var arguments: [String] = []

    func run() throws {
        var commands: [String] = []
        var file: String?
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            if argument == "-c", let command = rest.popFirst() {
                commands.append(command)
            } else if !argument.hasPrefix("-"), file == nil {
                file = argument
            } else {
                throw NomacError("nomac PlistBuddy takes '-c <command> ... <file>', not 'PlistBuddy \(arguments.joined(separator: " "))'")
            }
        }
        guard let file else { throw NomacError("nomac PlistBuddy takes '-c <command> ... <file>'") }
        var buddy = try PlistBuddy(path: file)
        let outcome = try buddy.run(commands)
        FileHandle.standardOutput.write(Data(outcome.standardOutput.utf8))
        FileHandle.standardError.write(Data(outcome.standardError.utf8))
        if outcome.failed { throw ExitCode(1) }
    }
}
