import ArgumentParser
import Foundation
import NomacAssets
import NomacBuild
import NomacCore
import NomacCoreData
import NomacCoreML
import NomacEnvelope
import NomacPackaging

/// `nomac check`: the features a project uses, and those outside nomac's envelope.
struct CheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "List what a project uses that nomac has not verified.",
        discussion: """
        Lists every feature of the project or workspace that decides nomac's outputs and reports \
        each one outside the envelope, the features whose handling a comparison with Xcode has \
        confirmed, with where it is used (docs/formats/check.md, docs/adr/0011-feature-envelope.md). \
        Exits with 1 when any feature is outside.

        Examples:
          nomac check App.xcodeproj
          nomac check App.xcworkspace --json
          nomac check --envelope
        """
    )

    @Argument(help: "The .xcodeproj or .xcworkspace to check.")
    var container: String?

    @Flag(help: "Print JSON.")
    var json = false

    @Flag(help: "List every feature, not only those outside the envelope.")
    var all = false

    @Flag(help: "The checkout holds only project-description files; features in other files are reported as not checked.")
    var descriptionOnly = false

    @Option(help: "A SourcePackages folder holding the checkouts of the workspace's remote packages.")
    var sourcePackages: String?

    @Flag(help: "Print the envelope: every feature nomac knows, verified or not, with its evidence.")
    var envelope = false

    static let domains: [any FeatureDomain] = [LoaderDomain(), AssetsDomain(), CoreDataDomain(), NibDomain(), CoreMLDomain(), MetalDomain(), SigningDomain(), BuildDomain()]

    func validate() throws {
        if !envelope && container == nil { throw ValidationError("Give a project or workspace, or --envelope.") }
    }

    func run() throws {
        if envelope {
            print(CheckReport.envelopeText(Self.domains), terminator: "")
            return
        }
        let options = CheckOptions(descriptionOnly: descriptionOnly, sourcePackages: sourcePackages.map(FileSystem.absolute))
        let report = CheckReport.make(container: FileSystem.absolute(container!), domains: Self.domains, options: options)
        print(json ? try report.json() : report.text(all: all), terminator: "")
        if !report.outside.isEmpty { throw ExitCode(1) }
    }
}
