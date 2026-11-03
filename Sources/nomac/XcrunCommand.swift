import ArgumentParser
import Foundation
import NomacBuild
import NomacCore
#if canImport(Glibc)
import Glibc
#endif

/// `nomac xcrun`: the `xcrun` of a developer directory off macOS, which build scripts call
/// (docs/formats/build.md "xcrun").
struct XcrunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcrun",
        abstract: "Find or run a developer tool, or answer an SDK query, as Xcode's xcrun does for build scripts.",
        discussion: "The developer directory is $DEVELOPER_DIR, else the one whose launcher ran nomac.",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "xcrun's options, then the tool and its arguments.")
    var arguments: [String] = []

    func run() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let developer = environment["DEVELOPER_DIR"]
                ?? environment["NOMAC_TOOL_DIRECTORY"].map({ (($0 as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent }) else {
            throw NomacError("nomac xcrun needs DEVELOPER_DIR, or to run from the xcrun launcher of a developer directory")
        }
        do {
            let xcrun = try Xcrun.parse(arguments)
            let sdk = try xcrun.resolveSDK(developerDirectory: developer, environment: environment)
            switch xcrun.action {
            case .find(let tool):
                print(try Xcrun.find(tool, sdk: sdk, developerDirectory: developer, environment: environment))
            case .show(let query):
                print(try Xcrun.answer(query, sdk: sdk))
            case .run(let tool, let toolArguments):
                let path = try Xcrun.find(tool, sdk: sdk, developerDirectory: developer, environment: environment)
                #if os(macOS)
                let hostIsMac = true
                #else
                let hostIsMac = false
                #endif
                try Self.execute(path, [path] + Xcrun.arguments(for: tool, toolArguments, sdk: sdk, developerDirectory: developer, hostIsMac: hostIsMac,
                                                                 environment: environment),
                                 environment: xcrun.environment(for: sdk, developerDirectory: developer, inherited: environment, hostIsMac: hostIsMac))
            }
        } catch let failure as Xcrun.Failure {
            FileHandle.standardError.write(Data(failure.message.utf8))
            throw ExitCode(failure.exitStatus)
        }
    }

    /// Replaces nomac with the tool, which then owns the standard streams and the exit status.
    private static func execute(_ path: String, _ arguments: [String], environment: [String: String]) throws {
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        execve(path, argv, envp)
        throw NomacError("cannot run \(path): \(String(cString: strerror(errno)))")
    }
}
