import ArgumentParser
import Foundation
import NomacBuild
import NomacCore

/// `nomac what`: macOS's `what`, which Swift Build runs as `what -q <tool>` to read a tool's
/// version off macOS through Swift Build's patch 10 (docs/upstream/swift-build.md).
struct WhatCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "what",
        abstract: "Print the @(#) identification strings of files, as macOS's what does.",
        shouldDisplay: false
    )

    @Flag(name: .customShort("q"), help: "Print only the strings, without file names.")
    var quiet = false

    @Flag(name: .customShort("s"), help: "Stop after the first string of each file.")
    var first = false

    @Argument(help: "The files to read.")
    var files: [String]

    func run() throws {
        var found = false
        for file in files {
            let strings = WhatStrings.strings(in: try Data(contentsOf: URL(fileURLWithPath: FileSystem.absolute(file))))
            if !quiet { print("\(file):") }
            for string in first ? Array(strings.prefix(1)) : strings {
                print(quiet ? string : "\t" + string)
                found = true
            }
        }
        if !found { throw ExitCode(1) }
    }
}
