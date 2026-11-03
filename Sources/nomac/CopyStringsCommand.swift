import ArgumentParser
import Foundation
import NomacCore
import NomacStrings

/// `nomac builtin-copyStrings`: Swift Build's `builtin-copyStrings` task with the bytes it writes
/// on a Mac (ADR 0250), and its command line.
struct CopyStringsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "builtin-copyStrings",
        abstract: "Copy .strings and .stringsdict files as Xcode's builds copy them.",
        shouldDisplay: false
    )

    @Flag(name: .customLong("validate"), help: "Validate the property list contents when copied.")
    var validate = false

    @Option(name: .customLong("inputencoding"), help: "The input file is in the given encoding.")
    var inputEncoding: String?

    @Option(name: .customLong("outputencoding"), help: "binary, UTF-16 or UTF-8.")
    var outputEncoding = "UTF-16"

    @Option(name: .customLong("outdir"), help: "The output directory to copy to.")
    var outputDirectory: String

    @Option(name: .customLong("outfilename"), help: "The output file name.")
    var outputFileName: String?

    @Argument(parsing: .postTerminator, help: "The input files.")
    var inputs: [String]

    func run() throws {
        let encoding = try StringsFileCopy.OutputEncoding(outputEncoding)
        for input in inputs {
            guard let bytes = FileManager.default.contents(atPath: input) else {
                throw NomacError("unable to read input file", path: input)
            }
            let result: StringsFileCopy.Result
            do {
                result = try StringsFileCopy.copy(Array(bytes), inputEncoding: inputEncoding, outputEncoding: encoding, validate: validate)
            } catch var error as NomacError {
                error.path = input
                throw error
            }
            for note in result.notes {
                FileHandle.standardError.write(Data("\(input): note: \(note)\n".utf8))
            }
            let name = outputFileName ?? (input as NSString).lastPathComponent
            try FileSystem.write(result.contents, to: (outputDirectory as NSString).appendingPathComponent(name))
        }
    }
}
