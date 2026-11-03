import ArgumentParser
import Foundation
import NomacCore
import NomacCoreData

/// `nomac mapc`: Xcode's Core Data mapping model compiler, with the command line a build runs.
struct MapcCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mapc",
        abstract: "Compile Core Data mapping models, as Xcode's mapc does.",
        discussion: "Compiles a .xcmappingmodel into a .cdm (docs/formats/coredata.md \"Mapping models\").",
        shouldDisplay: false
    )

    @Option(name: .customLong("sdkroot"), help: "The SDK; the mapping model does not depend on it.")
    var sdkroot: String?

    @OptionGroup var deploymentTarget: DeploymentTargetOptions

    @OptionGroup var warningSwitches: WarningSwitches

    @Option(name: .customLong("module"), help: "Does not change the .cdm.")
    var module: String?

    @Argument(help: "The .xcmappingmodel.")
    var source: String

    @Argument(help: "The .cdm to write.")
    var destination: String

    func run() throws {
        try deploymentTarget.validate(tool: "mapc")
        try warningSwitches.validate(tool: "mapc")
        let data = try MappingCompiler.compile(FileSystem.absolute(source))
        try FileSystem.write(Data(data), to: FileSystem.absolute(destination))
    }
}
