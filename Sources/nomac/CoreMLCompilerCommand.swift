import ArgumentParser
import Foundation
import NomacCore
import NomacCoreML

/// `nomac coremlc`: Xcode's Core ML model compiler, with the command
/// lines Swift Build's CoreMLModelCompile and CoreMLModelCodegen tasks run (docs/formats/coreml.md).
struct CoreMLCompilerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coremlc",
        abstract: "Compile Core ML models, as Xcode's coremlc does.",
        shouldDisplay: false,
        subcommands: [Compile.self, Generate.self]
    )

    /// The options Swift Build passes to both commands; none changes the outputs observed.
    struct BuildOptions: ParsableArguments {
        @Option(name: .customLong("deployment-target"), help: "The deployment target (no effect).")
        var deploymentTarget: String?

        @Option(name: .customLong("sdkroot"), help: "The SDK (no effect).")
        var sdkroot: String?

        @Option(name: .customLong("platform"), help: "The platform (no effect).")
        var platform: String?

        @Option(name: .customLong("output-partial-info-plist"), help: "Where compile writes the Info.plist entries.")
        var partialInfoPlist: String?

        @Option(name: .customLong("container"), help: "bundle-resources (no effect).")
        var container: String?
    }

    /// `coremlc compile <model> <directory>`: `<directory>/<Name>.mlmodelc` and the partial Info.plist.
    struct Compile: ParsableCommand {
        @Argument(help: "The .mlmodel or .mlpackage.")
        var input: String

        @Argument(help: "The directory the .mlmodelc goes to.")
        var output: String

        @OptionGroup var options: BuildOptions

        func run() throws {
            _ = try CoreMLModelCompiler.write(FileSystem.absolute(input), to: FileSystem.absolute(output),
                                              partialInfoPlist: options.partialInfoPlist.map(FileSystem.absolute))
        }
    }

    /// `coremlc generate <model> <directory>`: the model's classes, or with `--dry-run yes` the
    /// paths of the files it would write, one per line, which Swift Build plans with.
    struct Generate: ParsableCommand {
        @Argument(help: "The .mlmodel or .mlpackage.")
        var input: String

        @Argument(help: "The directory the classes go to.")
        var output: String

        @Option(name: .customLong("dry-run"), help: "yes: print the files generation would write.")
        var dryRun: String?

        @OptionGroup var options: BuildOptions

        @Option(name: .customLong("language"), help: "Swift or Objective-C.")
        var language: String

        @Option(name: .customLong("swift-version"), help: "The Swift version of the classes.")
        var swiftVersion = "5.0"

        @Flag(name: .customLong("public-access"), help: "Declare the classes public.")
        var publicAccess = false

        @Flag(name: .customLong("globalmodule"), help: "Classes that inherit NSObject.")
        var globalModule = false

        func run() throws {
            guard language == "Swift" else {
                throw NomacError("coremlc generate --language \(language) is not reproduced yet (BACKLOG B-240)")
            }
            guard !globalModule else {
                throw NomacError("coremlc generate --globalmodule is not reproduced yet (BACKLOG B-240)")
            }
            let generator = try SwiftClassGenerator(path: FileSystem.absolute(input), swiftVersion: swiftVersion, publicAccess: publicAccess)
            let file = generator.file
            let path = (output as NSString).appendingPathComponent(file.name)
            if dryRun == "yes" {
                print(path)
            } else {
                try FileSystem.write(Data(file.contents.utf8), to: FileSystem.absolute(path))
            }
        }
    }
}
