import Foundation
import Testing
@testable import nomac

/// `nomac ibtool` parsed from the command lines Swift Build runs through the ibtool launcher.
@Suite struct IBToolCommandTests {
    /// Swift Build's probe (SWBApplePlatform `InterfaceBuilderShared.swift`), which has no
    /// `--minimum-deployment-target`: it reaches ibtool's own `--version`, not nomac's.
    @Test func swiftBuildVersionProbe() throws {
        let command = try Nomac.parseAsRoot(["ibtool", "--version", "--output-format", "xml1"])
        let ibtool = try #require(command as? IBToolCommand)
        #expect(ibtool.version)
        #expect(ibtool.outputFormat == "xml1")
    }

    /// nib-experiments' compile command line, as a build's CompileXIB task runs it.
    @Test func compileCommandLine() throws {
        let command = try Nomac.parseAsRoot([
            "ibtool", "--errors", "--warnings", "--notices", "--module", "T", "--output-partial-info-plist", "/tmp/View-PartialInfo.plist",
            "--auto-activate-custom-fonts", "--target-device", "iphone", "--minimum-deployment-target", "27.0",
            "--output-format", "human-readable-text", "--compile", "/tmp/View.nib", "/tmp/View.xib",
        ])
        let ibtool = try #require(command as? IBToolCommand)
        #expect(!ibtool.version)
        #expect(ibtool.minimumDeploymentTarget == "27.0")
        #expect(ibtool.inputs == ["/tmp/View.xib"])
    }

    /// nib-experiments `build`: Swift Build's CompileStoryboard and LinkStoryboards command lines.
    @Test func storyboardCommandLines() throws {
        let compile = try #require(try Nomac.parseAsRoot([
            "ibtool", "--errors", "--warnings", "--notices", "--module", "T", "--output-partial-info-plist", "/tmp/Base.lproj/Main-SBPartialInfo.plist",
            "--auto-activate-custom-fonts", "--target-device", "iphone", "--minimum-deployment-target", "27.0",
            "--output-format", "human-readable-text", "/tmp/Src/Base.lproj/Main.storyboard", "--compilation-directory", "/tmp/Base.lproj",
        ]) as? IBToolCommand)
        #expect(compile.compilationDirectory == "/tmp/Base.lproj")
        #expect(compile.inputs == ["/tmp/Src/Base.lproj/Main.storyboard"])
        let link = try #require(try Nomac.parseAsRoot([
            "ibtool", "--errors", "--warnings", "--notices", "--module", "T", "--target-device", "iphone", "--minimum-deployment-target", "27.0",
            "--output-format", "human-readable-text", "--link", "/tmp/T.app", "/tmp/Base.lproj/Main.storyboardc", "/tmp/Base.lproj/LaunchScreen.storyboardc",
        ]) as? IBToolCommand)
        #expect(link.link == "/tmp/T.app")
        #expect(link.inputs == ["/tmp/Base.lproj/Main.storyboardc", "/tmp/Base.lproj/LaunchScreen.storyboardc"])
    }

    /// Xcode's ibtool links each storyboard into the folder named as its `.lproj` folder, or into
    /// the directory itself (retro-rampage's compiled storyboards from `Base.lproj`, `fr.lproj` and
    /// a plain folder, linked in one call).
    @Test func linksStoryboardsIntoTheirLocalizationFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-link-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        for storyboard in ["in/Base.lproj/Main.storyboardc", "in/fr.lproj/Main.storyboardc", "in/plain/LaunchScreen.storyboardc"] {
            try FileManager.default.createDirectory(atPath: root + "/" + storyboard, withIntermediateDirectories: true)
            #expect(FileManager.default.createFile(atPath: root + "/" + storyboard + "/Info.plist", contents: Data(storyboard.utf8)))
        }
        let link = try #require(try Nomac.parseAsRoot([
            "ibtool", "--link", root + "/T.app", root + "/in/Base.lproj/Main.storyboardc", root + "/in/fr.lproj/Main.storyboardc", root + "/in/plain/LaunchScreen.storyboardc",
        ]) as? IBToolCommand)
        try link.run()
        #expect(FileManager.default.contents(atPath: root + "/T.app/Base.lproj/Main.storyboardc/Info.plist") == Data("in/Base.lproj/Main.storyboardc".utf8))
        #expect(FileManager.default.contents(atPath: root + "/T.app/fr.lproj/Main.storyboardc/Info.plist") == Data("in/fr.lproj/Main.storyboardc".utf8))
        #expect(FileManager.default.contents(atPath: root + "/T.app/LaunchScreen.storyboardc/Info.plist") == Data("in/plain/LaunchScreen.storyboardc".utf8))
    }
}
