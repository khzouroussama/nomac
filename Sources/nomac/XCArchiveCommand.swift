import ArgumentParser
import Foundation
import NomacCore
import NomacPackaging

/// `nomac xcarchive`: the archive `xcodebuild archive` assembles after its build.
struct XCArchiveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcarchive",
        abstract: "Assemble an .xcarchive from an archive build, as 'xcodebuild archive' does after building.",
        discussion: """
        Moves the build's InstallationBuildProductsLocation to Products, copies every dSYM of \
        BuildProductsPath and its SwiftSupport, and writes Info.plist (docs/formats/xcarchive.md).
        """,
        shouldDisplay: false
    )

    @Option(name: .customLong("intermediates"), help: "The scheme's folder of ArchiveIntermediates.")
    var intermediates: String

    @Option(name: [.customLong("archivePath", withSingleDash: true)], help: "The .xcarchive to write.")
    var archivePath: String

    @Option(name: [.customLong("scheme", withSingleDash: true)], help: "The scheme archived.")
    var scheme: String

    func run() throws {
        try XCArchive.assemble(intermediates: FileSystem.absolute(intermediates), archivePath: FileSystem.absolute(archivePath),
                               schemeName: scheme, creationDate: Date())
    }
}
