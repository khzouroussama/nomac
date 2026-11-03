import ArgumentParser
import Foundation
import NomacCore
import NomacPlist
import NomacStrings

/// `nomac xcstringstool`: the subset of Xcode's `xcstringstool` that builds run.
struct XCStringsToolCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcstringstool",
        abstract: "Work with .xcstrings files, as Xcode's xcstringstool does.",
        shouldDisplay: false,
        subcommands: [Compile.self, GenerateSymbols.self]
    )

    /// `xcstringstool compile`, with the arguments Swift Build's XCStrings compiler passes.
    struct Compile: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Produces build products for an .xcstrings file.",
            discussion: """
            Writes <language>.lproj/<name>.strings and .stringsdict as XML property lists, the \
            files xcstringstool compile writes (docs/formats/strings.md).
            """
        )

        @Argument(help: "The path to the .xcstrings file to compile.")
        var inputFile: String

        @Option(name: [.short, .customLong("output-directory")], help: "The directory to place output files.")
        var outputDirectory: String

        @Option(name: [.short, .customLong("format")], help: "stringsAndStringsdict or stringsdictOnly.")
        var format: String = StringCatalogCompiler.Format.stringsAndStringsdict.rawValue

        @Option(name: [.short, .customLong("language")], help: "Compile only these languages.")
        var language: [String] = []

        @Option(name: .customLong("serialization-format"), help: "text (the only format Xcode's builds use).")
        var serializationFormat: String = "text"

        @Flag(name: .customLong("dry-run"), help: "Print the output paths a compilation would produce.")
        var dryRun = false

        func run() throws {
            guard let format = StringCatalogCompiler.Format(rawValue: format) else {
                throw ValidationError("unknown --format '\(format)'")
            }
            guard serializationFormat == "text" else {
                throw NomacError("--serialization-format \(serializationFormat) is not supported; Xcode's builds use text (BACKLOG B-250)")
            }
            let path = FileSystem.resolvingSymbolicLinks(FileSystem.absolute(inputFile))
            let catalog = try StringCatalog.read(at: path)
            let compiler = StringCatalogCompiler(catalog: catalog, languages: language.isEmpty ? nil : language, format: format)
            let (outputs, diagnostics) = try compiler.compile()
            let name = ((inputFile as NSString).lastPathComponent as NSString).deletingPathExtension
            if dryRun {
                for output in outputs {
                    print("\(outputDirectory)/\(output.relativePath(catalogName: name))")
                }
                return
            }
            // Warnings go to standard output, errors to standard error (strings-experiments `diagnostic-*`).
            for diagnostic in diagnostics {
                let stream = diagnostic.severity == .error ? FileHandle.standardError : FileHandle.standardOutput
                stream.write(Data((diagnostic.rendered(path: path) + "\n").utf8))
            }
            if diagnostics.contains(where: { $0.severity == .error }) {
                throw ExitCode.failure
            }
            for output in outputs {
                let data = XMLPropertyList.data(.dictionary(output.table), keyOrder: output.keyOrder)
                try FileSystem.write(data, to: "\(outputDirectory)/\(output.relativePath(catalogName: name))")
            }
        }
    }

    /// `xcstringstool generate-symbols`, as the GenerateStringSymbols task runs it.
    struct GenerateSymbols: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "generate-symbols",
            abstract: "Generates symbols for manually-defined strings.",
            discussion: """
            Writes GeneratedStringSymbols_<name>.swift, or SCGeneratedStringSymbols_<name>.h and .m, \
            empty when the catalog has no manually added strings, as xcstringstool does \
            (docs/formats/strings.md "Generated symbols").
            """
        )

        @Argument(help: "The path to the .xcstrings file to generate symbols for.")
        var inputFile: String

        @Option(name: [.short, .customLong("output-directory")], help: "The directory to place output files.")
        var outputDirectory: String

        @Option(name: [.short, .customLong("language")], help: "Languages to generate symbols in (swift, objc).")
        var language: [StringSymbols.Language]

        func run() throws {
            let path = FileSystem.resolvingSymbolicLinks(FileSystem.absolute(inputFile))
            let catalog = try StringCatalog.read(at: path)
            let name = ((inputFile as NSString).lastPathComponent as NSString).deletingPathExtension
            let swift = language.contains(.swift) ? StringSymbolGenerator(catalog: catalog, tableName: name).generate() : nil
            let diagnostics = swift?.diagnostics ?? []
            // Warnings go to standard output, errors to standard error (strings-experiments `generate-symbols`).
            for diagnostic in diagnostics {
                let stream = diagnostic.severity == .error ? FileHandle.standardError : FileHandle.standardOutput
                stream.write(Data((diagnostic.rendered(path: path) + "\n").utf8))
            }
            if let failure = swift?.failure {
                throw Failure(description: failure)
            }
            for language in language {
                for file in StringSymbols.fileNames(catalogName: name, language: language) {
                    guard FileSystem.isDirectory(outputDirectory) else {
                        throw NomacError("The folder \u{201C}\(file)\u{201D} doesn\u{2019}t exist.")
                    }
                    let contents = language == .swift ? swift?.source ?? "" : ""
                    try FileSystem.write(Data(contents.utf8), to: outputDirectory + "/" + file)
                }
            }
            if diagnostics.contains(where: { $0.severity == .error }) {
                throw ExitCode.failure
            }
        }

        /// An error xcstringstool prints as `Error: <description>`, as for a table name Swift
        /// cannot have.
        struct Failure: Error, CustomStringConvertible {
            var description: String
        }
    }
}

extension StringSymbols.Language: ExpressibleByArgument {}
