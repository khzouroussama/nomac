import ArgumentParser
import Foundation
import NomacCore
import NomacSigning

/// `nomac codesign`: sign as Apple's codesign does, for the invocations Xcode makes.
struct CodesignCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codesign",
        abstract: "Sign bundles and Mach-O files, as 'codesign'.",
        discussion: """
        Takes codesign's own options, as Swift Build's CodeSign tasks and Xcode's archive export \
        pass them: --force, --sign, --entitlements, --preserve-metadata, --identifier, \
        --generate-entitlement-der, --strip-disallowed-xattrs, --timestamp=none and --verbose. \
        With a certificate (--sign <SHA-1 or common name>), --keychain names a PEM file holding \
        the RSA private key and the certificate chain; without it, $CODE_SIGN_KEYCHAIN does (set \
        in script phases of builds signed with --keychain). The signatures are byte for byte those \
        Xcode 27.0's codesign writes (docs/formats/code-signature.md).
        """
    )

    @Argument(parsing: .captureForPassthrough, help: "codesign options and the paths to sign.")
    var arguments: [String] = []

    func run() throws {
        if arguments.contains("--help") { throw CleanExit.helpRequest(self) }
        if let paths = try CodesignArguments.displayedPaths(arguments) {
            for path in paths {
                do {
                    let (output, error) = try CodeSigner.designatedRequirement(of: path)
                    FileHandle.standardError.write(Data(error.utf8))
                    FileHandle.standardOutput.write(Data(output.utf8))
                } catch let error as NomacError {
                    FileHandle.standardError.write(Data("\(error.path ?? path): \(error.message)\n".utf8))
                    throw ExitCode(1)
                }
            }
            return
        }
        for request in try CodesignArguments.parse(arguments, environment: ProcessInfo.processInfo.environment) {
            do {
                for line in try CodeSigner.sign(request) {
                    FileHandle.standardError.write(Data((line + "\n").utf8))
                }
            } catch let error as NomacError {
                // codesign reports failures as `<path>: <message>` and exits with status 1.
                FileHandle.standardError.write(Data("\(error.path ?? request.path): \(error.message)\n".utf8))
                throw ExitCode(1)
            }
        }
    }
}

/// A link named `codesign` to this executable, which then runs as `nomac codesign`.
enum CodesignLink {
    static func create(in folder: String) throws -> String {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
            throw NomacError("cannot find nomac's own executable to link codesign to")
        }
        let link = folder + "/codesign"
        try FileSystem.createDirectory(folder)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != executable {
            try? FileManager.default.removeItem(atPath: link)
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: executable)
        }
        return link
    }
}
