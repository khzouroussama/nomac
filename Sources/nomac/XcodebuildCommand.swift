import ArgumentParser
import Foundation
import NomacCore

/// `nomac xcodebuild`: xcodebuild for the scripts of a build's script phases, behind the launcher
/// `nomac toolchain install` writes in the developer directory's `usr/bin` (B-181).
struct XcodebuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcodebuild",
        abstract: "Answer -version, or build, as xcodebuild does for build scripts.",
        discussion: "Takes 'xcodebuild -version' and the options and settings of 'nomac build' with the action 'build' (docs/formats/build.md \"xcodebuild\"). The developer directory is $DEVELOPER_DIR, else the one whose launcher ran nomac.",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "xcodebuild's arguments.")
    var arguments: [String] = []

    func run() async throws {
        if arguments == ["-version"] {
            print("Xcode \(XcodeProfile.current.xcode.version)\nBuild version \(XcodeProfile.current.xcode.build)")
            return
        }
        guard arguments.contains("build") else {
            throw NomacError("nomac xcodebuild takes '-version' and builds ('... build'), not 'xcodebuild \(arguments.joined(separator: " "))'")
        }
        let environment = ProcessInfo.processInfo.environment
        let developer = environment["DEVELOPER_DIR"]
            ?? environment["NOMAC_TOOL_DIRECTORY"].map { (($0 as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent }
        var build = try BuildCommand.parse(arguments + (developer.map { ["--developer-dir", $0] } ?? []))
        try await build.run()
    }
}
