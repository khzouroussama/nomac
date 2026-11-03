import ArgumentParser
import Foundation
import NomacAssets

/// `nomac actool`: compile asset catalogs as Xcode's actool does, with its command line.
struct ActoolCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "actool",
        abstract: "Compile asset catalogs (.xcassets) as Xcode's actool does.",
        discussion: """
        Takes actool's own arguments, for example: <catalog.xcassets> --compile <dir> \
        --output-format human-readable-text --output-partial-info-plist <plist> \
        --export-dependency-info <file> --target-device iphone --minimum-deployment-target 18.0 \
        --platform iphoneos. See docs/formats/asset-catalog.md for what is supported.
        """,
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "actool's arguments.")
    var arguments: [String] = []

    func run() throws {
        let result = try Actool.run(try Actool.Options(arguments: arguments))
        FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
        if result.failed { throw ExitCode(1) }
    }
}
