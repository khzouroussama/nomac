import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacBuild

/// `scheme_action_experiments.py`: how xcodebuild runs a scheme's shell script actions.
@Suite struct SchemeActionsTests {
    func actions(temporary: String) -> SchemeActions {
        SchemeActions(developerDirectory: "/Dev", schemeName: "App", containerPath: "/w/P.xcodeproj",
                      workspacePath: "/w/P.xcodeproj/project.xcworkspace", destination: SchemeActions.destinationEnvironment("generic/platform=iOS"),
                      shell: "/bin/sh", environment: ["PATH": "/usr/bin:/bin", "TMPDIR": temporary])
    }

    /// The log's exports: bare values of letters, digits and `+,-./=_`, others in double quotes.
    @Test func exportsAreQuotedAsXcodebuildLogsThem() {
        #expect(SchemeActions.quoted("/Applications/Xcode_27.app/Contents/Developer") == "/Applications/Xcode_27.app/Contents/Developer")
        #expect(SchemeActions.quoted("") == "")
        #expect(SchemeActions.quoted("en_US.UTF-8") == "en_US.UTF-8")
        #expect(SchemeActions.quoted("Any iOS Device") == "\"Any iOS Device\"")
        #expect(SchemeActions.quoted("/a:/b") == "\"/a:/b\"")
        #expect(SchemeActions.quoted("\"@(#)PROGRAM:App  PROJECT:P-\"") == "\"\\\"@(#)PROGRAM:App  PROJECT:P-\\\"\"")
    }

    /// The failure summary's second line: the scheme's project as a base64 blueprint provider.
    @Test func failedActionsNameTheirProject() throws {
        let line = actions(temporary: "/tmp").blueprintProvider
        let json = String(decoding: try #require(Data(base64Encoded: line)), as: UTF8.self)
        #expect(json == #"{"blueprintProvider_providerFilePathString":"\/w\/P.xcodeproj","type":{"blueprintProvider":{}}}"#)
    }

    /// Every action runs, a failed one too, from TMPDIR, with the scheme's variables and the
    /// developer directory's `usr/bin` first on PATH.
    @Test func actionsRunInOrderWithTheirEnvironment() throws {
        let tmp = try TemporaryDirectory()
        var log = ""
        let scripts = [
            SchemeActions.Script(title: "Fails", text: "exit 3\n", settings: nil),
            SchemeActions.Script(title: "Run Script", text: "echo \"$SCHEME_NAME $SCHEME_ACTION_NAME $DEVICE_NAME $PROJECT_DIR $(pwd)\" > \(tmp.path)/out\necho $PATH >> \(tmp.path)/out\n",
                                 settings: ["PROJECT_DIR": "/w"]),
        ]
        let failures = try actions(temporary: tmp.path).run(scripts, heading: "Run pre-actions", log: { log += $0 })
        #expect(failures.first == "Run custom shell script 'Fails'")
        #expect(failures.count == 2)
        let lines = String(decoding: try #require(FileManager.default.contents(atPath: tmp.path + "/out")), as: UTF8.self).split(separator: "\n")
        #expect(lines.first.map(String.init) == "App Run Script Any iOS Device /w \(FileSystem.resolvingSymbolicLinks(tmp.path))")
        #expect(lines.last == "/Dev/usr/bin:/usr/bin:/bin")
        #expect(log.hasPrefix("Run pre-actions\n\nSchemeAction Fails \(tmp.path)/SchemeScriptAction-"))
        #expect(log.contains("SchemeAction Run\\ Script "))
        #expect(log.contains("    export DEVICE_NAME=\"Any iOS Device\"\n"))
    }
}
