import ArgumentParser
import Foundation
import NomacCore

/// The `nomac` command-line tool.
@main
struct Nomac: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nomac",
        abstract: "Build, sign and install iOS apps from Xcode projects on Linux.",
        discussion: """
        Commands take xcodebuild's flags; 'nomac <command> --help' shows each one's. The tools \
        of Xcode that builds run (actool, ibtool, momc and others) are nomac commands too, not \
        listed here.
        """,
        version: NomacVersion.full,
        subcommands: [BuildCommand.self, ArchiveCommand.self, ExportCommand.self, CodesignCommand.self, CheckCommand.self, ListCommand.self, InspectCommand.self],
        groupedSubcommands: [
            CommandGroup(name: "Devices and App Store", subcommands: [DeviceCommand.self, InstallCommand.self, UninstallCommand.self, LaunchCommand.self, StopCommand.self, RunCommand.self, TestCommand.self, AtosCommand.self, UploadCommand.self]),
            CommandGroup(name: "Setup", subcommands: [SDKCommand.self, ToolchainCommand.self, DoctorCommand.self]),
            CommandGroup(name: "Verification", subcommands: [VerifyCommand.self, ProductsCommand.self, PIFCommand.self, CorpusCommand.self]),
            CommandGroup(name: "Xcode's tools", subcommands: [XCStringsToolCommand.self, CopyStringsCommand.self, IBToolCommand.self, MomcCommand.self, MapcCommand.self, CoreMLCompilerCommand.self, WhatCommand.self, IntentBuilderCommand.self, ActoolCommand.self, CopyPNGCommand.self, TAPICommand.self, DsymutilCommand.self, AppIntentsMetadataProcessorCommand.self, AppIntentsNLTrainingProcessorCommand.self, XcrunCommand.self, DittoCommand.self, XcodebuildCommand.self, DerqCommand.self, PlistBuddyCommand.self, FileCommand.self, EmbeddedBinaryValidationCommand.self, MD5Command.self, DwarfdumpCommand.self, AssetutilCommand.self, ZipCommand.self, SymbolsCommand.self, XCArchiveCommand.self]),
        ]
    )

    /// Runs the command, printing nomac's own errors in Xcode's diagnostic format
    /// (`error: ...` / `note: ...`) and everything else the way ArgumentParser does.
    static func main() async {
        HostOperatingSystem.raiseOpenFileLimit()
        do {
            // Run through a link named `codesign`, nomac is `nomac codesign`: Swift Build's
            // CodeSign tasks take such a link as `CODESIGN`.
            let invokedAs = CommandLine.arguments.first.map { ($0 as NSString).lastPathComponent }
            var command = try parseAsRoot((invokedAs == "codesign" ? ["codesign"] : []) + CommandLine.arguments.dropFirst())
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch let error as NomacError {
            FileHandle.standardError.write(Data((error.rendered + "\n").utf8))
            Foundation.exit(error.exitStatus)
        } catch {
            exit(withError: error)
        }
    }
}
