import ArgumentParser
import Foundation
import NomacCore
import NomacPackaging

/// `nomac zip`: archive a folder as ditto does for Xcode's IPAs.
struct ZipCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zip",
        abstract: "Archive a folder's contents as 'ditto -c -k --norsrc' does (Xcode's IPA format).",
        discussion: "See docs/formats/ipa.md for the entry order, compression and attributes.",
        shouldDisplay: false
    )

    @Argument(help: "The folder whose contents go into the archive.")
    var directory: String

    @Argument(help: "The archive to write.")
    var archive: String

    func run() throws {
        try DittoArchive.create(from: FileSystem.absolute(directory), to: FileSystem.absolute(archive))
    }
}
