import ArgumentParser
import Foundation
import NomacCore
import NomacPackaging

/// `nomac ditto`: macOS's ditto for the forms build scripts use, behind the launcher
/// `nomac toolchain install` writes (docs/formats/build.md "ditto").
struct DittoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ditto",
        abstract: "Copy a file or folder, or archive a folder's contents, as macOS's ditto does for build scripts.",
        discussion: "Takes '<source> <destination>' (a copy: docs/formats/build.md \"ditto\") and '-c -k --norsrc <folder> <archive>' (docs/formats/ipa.md).",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "ditto's arguments.")
    var arguments: [String] = []

    func run() throws {
        if arguments.count == 2, !arguments.contains(where: { $0.hasPrefix("-") }) {
            try DittoCopy.copy(FileSystem.absolute(arguments[0]), to: FileSystem.absolute(arguments[1]))
        } else if arguments.count == 5, Array(arguments.prefix(3)) == ["-c", "-k", "--norsrc"] {
            try DittoArchive.create(from: FileSystem.absolute(arguments[3]), to: FileSystem.absolute(arguments[4]))
        } else {
            throw NomacError("nomac ditto takes '<source> <destination>' or '-c -k --norsrc <folder> <archive>', not 'ditto \(arguments.joined(separator: " "))'")
        }
    }
}
