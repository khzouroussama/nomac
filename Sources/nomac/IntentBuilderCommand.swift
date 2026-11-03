import ArgumentParser
import Foundation
import NomacCore
import NomacIntents

/// `nomac intentbuilderc`: Xcode's intent definition compiler, with the command lines Swift
/// Build's IntentDefinitionCodegen and IntentDefinitionCompile tasks run (docs/formats/intents.md).
struct IntentBuilderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "intentbuilderc",
        abstract: "Generate classes for intent definitions, as Xcode's intentbuilderc does.",
        shouldDisplay: false,
        subcommands: [Generate.self, Compile.self]
    )

    /// `intentbuilderc generate`: the classes of an intent definition, or with `-dryRun` the
    /// paths of the files it would write, one per line, which Swift Build plans with.
    struct Generate: ParsableCommand {
        @Option(name: .customLong("input", withSingleDash: true), help: "The intent definition file.")
        var input: String

        @Option(name: .customLong("output", withSingleDash: true), help: "The output directory.")
        var output: String

        @Option(name: .customLong("language", withSingleDash: true), help: "Swift or Objective-C.")
        var language: String

        @Option(name: .customLong("classPrefix", withSingleDash: true), help: "The class prefix of generated classes.")
        var classPrefix = ""

        @Option(name: .customLong("swiftVersion", withSingleDash: true), help: "The Swift version of generated classes (no effect).")
        var swiftVersion: String?

        @Option(name: .customLong("visibility", withSingleDash: true), help: "public, private or project.")
        var visibility = "public"

        @Option(name: .customLong("moduleName", withSingleDash: true), help: "The module that contains the generated classes (no effect).")
        var moduleName: String?

        @Flag(name: .customLong("dryRun", withSingleDash: true), help: "Print the files generation would write.")
        var dryRun = false

        func run() throws {
            guard let language = IntentCodeGenerator.Language(rawValue: language) else {
                throw NomacError("intentbuilderc generates Swift and Objective-C; \(language) is not one of them")
            }
            let definition = try IntentDefinition.read(at: FileSystem.absolute(input))
            let generator = IntentCodeGenerator(definition: definition, language: language, classPrefix: classPrefix, visibility: visibility)
            let files = try generator.files()
            // File names are decomposed, as macOS's file system representation writes them
            // (intents-experiments `names`: `ünïcodeIntent.swift`).
            for file in files {
                let path = (output as NSString).appendingPathComponent(file.name.decomposedStringWithCanonicalMapping)
                if dryRun {
                    print(path)
                } else {
                    try FileSystem.write(Data(file.contents.utf8), to: path)
                }
            }
        }
    }

    /// `intentbuilderc compile`, which writes the definition into the product with each intent's
    /// `INIntentHash`; that hash is not identified yet.
    struct Compile: ParsableCommand {
        @Option(name: .customLong("input", withSingleDash: true), help: "The intent definition file.")
        var input: String

        @Option(name: .customLong("output", withSingleDash: true), help: "The output directory.")
        var output: String

        @Option(name: .customLong("classPrefix", withSingleDash: true), help: "The project's class prefix.")
        var classPrefix = ""

        func run() throws {
            throw NomacError("intentbuilderc compile is not reproduced yet: each intent's INIntentHash is a hash nomac has not identified (BACKLOG B-232)",
                             path: FileSystem.absolute(input))
        }
    }
}
