import ArgumentParser
import Foundation
import NomacCore
import NomacCoreData

/// `nomac momc`: Xcode's Core Data model compiler, with the command line a build runs.
struct MomcCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "momc",
        abstract: "Compile Core Data models, as Xcode's momc does.",
        discussion: "Compiles .xcdatamodel and .xcdatamodeld into .mom and .momd (docs/formats/coredata.md); code generation is BACKLOG B-258.",
        shouldDisplay: false
    )

    @Option(name: .customLong("sdkroot"), help: "The SDK; the compiled model does not depend on it.")
    var sdkroot: String?

    @OptionGroup var deploymentTarget: DeploymentTargetOptions

    @OptionGroup var warningSwitches: WarningSwitches

    @Option(name: .customLong("module"), help: "The module of entity classes written \".Name\".")
    var module: String?

    @Option(name: .customLong("action"), help: "compile, the default, or generate (with --dry-run, the files it would write).")
    var action = "compile"

    @Option(name: .customLong("swift-version"), help: "The Swift version of generated classes.")
    var swiftVersion: String?

    @Flag(name: .customLong("dry-run"), help: "Print the files --action generate would write.")
    var dryRun = false

    @Argument(help: "The .xcdatamodel or .xcdatamodeld.")
    var source: String

    @Argument(help: "The directory the .mom or .momd goes to.")
    var destination: String

    func run() throws {
        try deploymentTarget.validate(tool: "momc")
        try warningSwitches.validate(tool: "momc")
        if action == "generate", dryRun {
            for file in try ModelCompiler.generatedFiles(FileSystem.absolute(source), destination: destination) {
                print(file)
            }
            return
        }
        if action == "generate" {
            let root = FileSystem.absolute(destination)
            for file in try CodeGenerator.files(FileSystem.absolute(source), swiftVersion: swiftVersion, author: .current) {
                try FileSystem.write(Data(file.contents.utf8), to: (root as NSString).appendingPathComponent(file.name))
            }
            return
        }
        guard action == "compile", !dryRun else {
            throw NomacError("momc --action \(action)\(dryRun ? " --dry-run" : "") is not reproduced yet (BACKLOG B-258)")
        }
        let output = try ModelCompiler.compile(FileSystem.absolute(source), module: module)
        let root = FileSystem.absolute(destination)
        for file in output.files {
            try FileSystem.write(Data(file.contents), to: (root as NSString).appendingPathComponent(file.path))
        }
        for diagnostic in output.diagnostics {
            FileHandle.standardError.write(Data((diagnostic + "\n").utf8))
        }
    }
}
