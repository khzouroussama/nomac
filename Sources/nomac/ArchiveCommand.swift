import ArgumentParser
import Foundation

/// `nomac archive`: archive a scheme, as `xcodebuild archive` does.
struct ArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive a scheme, as 'xcodebuild archive'.",
        discussion: """
        Builds what the scheme builds for archiving, in its archive configuration, as Swift \
        Build's install build into ArchiveIntermediates/<scheme> under the derived data, then \
        assembles the .xcarchive from it ('nomac xcarchive'). Takes the options of 'nomac build' \
        and -archivePath; a trailing 'archive' action is accepted.

        Example:
          nomac archive -project App.xcodeproj -scheme App -destination generic/platform=iOS \\
              -archivePath App.xcarchive CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES
        """
    )

    @OptionGroup var options: BuildOptions

    @Option(name: [.customLong("archivePath", withSingleDash: true)], help: "The .xcarchive to write.")
    var archivePath: String

    func run() async throws {
        guard options.scheme != nil else {
            throw ValidationError("archiving needs a scheme (-scheme)")
        }
        try await options.run(archivePath: archivePath)
    }
}
