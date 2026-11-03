import ArgumentParser
import Foundation
import NomacBuild
import NomacCore

/// Xcode's tools nomac reimplements, run by the launchers `nomac toolchain install` writes at
/// their Xcode paths (docs/adr/0102-linker.md). Each takes the tool's own command line.
struct TAPICommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tapi", abstract: "Xcode's 'tapi stubify' (the .tbd of a dynamic library).", shouldDisplay: false)

    @Argument(parsing: .captureForPassthrough, help: "tapi's arguments.")
    var arguments: [String] = []

    func run() throws {
        try TAPITool.run(arguments)
    }
}

struct DsymutilCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "dsymutil", abstract: "LLVM's dsymutil, with the dSYM Info.plist dsymutil writes on macOS.", shouldDisplay: false)

    @Argument(parsing: .captureForPassthrough, help: "dsymutil's arguments.")
    var arguments: [String] = []

    func run() throws {
        guard let directory = ProcessInfo.processInfo.environment["NOMAC_TOOL_DIRECTORY"] else {
            throw NomacError("nomac dsymutil runs from the launcher 'nomac toolchain install' writes (NOMAC_TOOL_DIRECTORY is not set)")
        }
        let status = try DsymutilTool.run(arguments, llvmDsymutil: directory + "/llvm-dsymutil")
        if status != 0 { throw ExitCode(status) }
    }
}

struct AppIntentsMetadataProcessorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "appintentsmetadataprocessor", abstract: "Xcode's App Intents metadata extraction.", shouldDisplay: false)

    @Argument(parsing: .captureForPassthrough, help: "appintentsmetadataprocessor's arguments.")
    var arguments: [String] = []

    func run() throws {
        try AppIntentsTools.extractMetadata(arguments)
    }
}

struct AppIntentsNLTrainingProcessorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "appintentsnltrainingprocessor", abstract: "Xcode's App Shortcuts training.", shouldDisplay: false)

    @Argument(parsing: .captureForPassthrough, help: "appintentsnltrainingprocessor's arguments.")
    var arguments: [String] = []

    func run() throws {
        let environment = ProcessInfo.processInfo.environment
        let developer = environment["NOMAC_TOOL_DIRECTORY"].map { (($0 as NSString).appendingPathComponent("../../../..") as NSString).standardizingPath } ?? environment["DEVELOPER_DIR"]
        try AppIntentsTools.trainShortcuts(arguments, developerDirectory: developer)
    }
}
