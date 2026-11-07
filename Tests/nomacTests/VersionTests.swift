import NomacCore
import Testing
@testable import nomac

/// `nomac --version` names the release and the one Xcode it reproduces.
@Suite struct VersionTests {
    @Test func versionLineNamesTheXcode() {
        #expect(Nomac.configuration.version == NomacVersion.full)
    }

    /// `nomac --help` recommends this form; codesign's arguments pass through, so it comes to `run`.
    /// `-h` stays codesign's own option.
    @Test func codesignAnswersHelp() throws {
        var command = try Nomac.parseAsRoot(["codesign", "--help"])
        #expect {
            try command.run()
        } throws: {
            Nomac.exitCode(for: $0) == .success && Nomac.fullMessage(for: $0).contains("Sign bundles and Mach-O files")
        }
    }

    @Test func strictXcodeIsAcceptedWhereverAnXcodeIsChosen() throws {
        for arguments in [["sdk", "install", "Xcode.app", "--strict-xcode"], ["sdk", "link", "Xcode.app", "--strict-xcode"],
                          ["inspect", "-project", "A.xcodeproj", "--strict-xcode"], ["list", "-project", "A.xcodeproj", "--strict-xcode"],
                          ["pif", "A.xcodeproj", "--strict-xcode"], ["verify", "ref", "--strict-xcode"],
                          ["build", "-project", "A.xcodeproj", "--strict-xcode"], ["toolchain", "install", "usr", "--llvm-tools", "llvm", "--strict-xcode"]] {
            #expect(throws: Never.self, "\(arguments)") { try Nomac.parseAsRoot(arguments) }
        }
    }
}
