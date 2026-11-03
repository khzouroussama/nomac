import Foundation
import Testing
@testable import NomacBuild
import NomacCore
@testable import NomacPIF
import NomacTestSupport

/// docs/adr/0103-script-phase-shell.md.
@Suite struct ScriptShellTests {
    @Test func acceptsOnlyAShellThatPrintsWhatMacOSShPrints() throws {
        let tmp = try TemporaryDirectory()
        let macOSLike = tmp.path + "/macos-sh"
        try FileSystem.write(Data("#!/bin/sh\nprintf '1-2\\na\\nb\\nposix\\n'\n".utf8), to: macOSLike)
        let other = tmp.path + "/other-sh"
        try FileSystem.write(Data("#!/bin/sh\nprintf '1-2\\na\\\\nb\\nposix\\n'\n".utf8), to: other)
        for path in [macOSLike, other] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
        #expect(ScriptShell.warning(shell: macOSLike) == nil)
        #expect(ScriptShell.warning(shell: other)?.hasPrefix(other + " does not run scripts as macOS's sh does") == true)
        #expect(ScriptShell.warning(shell: tmp.path + "/missing") != nil)
    }

    @Test func buildsRunScriptPhasesOfBinShUnderTheInstalledShell() {
        func phase(_ shell: String) -> PIFValue {
            .object(["type": .string("com.apple.buildphase.shell-script"), "shellPath": .string(shell), "scriptContents": .string("echo")])
        }
        let sources = PIFValue.object(["type": .string("com.apple.buildphase.sources")])
        let document = PIFDocument(objects: [
            .init(type: "workspace", signature: "WORKSPACE@w", contents: .object(["projects": .array([.string("PROJECT@a"), .string("PROJECT@b")])])),
            .init(type: "project", signature: "PROJECT@a", contents: .object(["targets": .array([.string("TARGET@1"), .string("TARGET@2")])])),
            .init(type: "target", signature: "TARGET@1", contents: .object(["buildPhases": .array([sources, phase("/bin/sh"), phase("/bin/bash")])])),
            .init(type: "target", signature: "TARGET@2", contents: .object(["buildPhases": .array([sources])])),
            .init(type: "project", signature: "PROJECT@b", contents: .object(["targets": .array([.string("TARGET@3")])])),
            .init(type: "target", signature: "TARGET@3", contents: .object(["buildPhases": .array([phase("/bin/bash")])])),
        ])
        let redirected = ScriptShell.redirecting(document, to: "/dev/usr/libexec/nomac/sh")
        #expect(redirected.objects.map(\.signature) == ["WORKSPACE@w_nomac-script-shell", "PROJECT@a_nomac-script-shell", "TARGET@1_nomac-script-shell",
                                                         "TARGET@2", "PROJECT@b", "TARGET@3"])
        #expect(redirected.objects[0].contents == .object(["projects": .array([.string("PROJECT@a_nomac-script-shell"), .string("PROJECT@b")])]))
        #expect(redirected.objects[1].contents == .object(["targets": .array([.string("TARGET@1_nomac-script-shell"), .string("TARGET@2")])]))
        #expect(redirected.objects[2].contents == .object(["buildPhases": .array([sources, phase("/dev/usr/libexec/nomac/sh"), phase("/bin/bash")])]))
        #expect(Array(redirected.objects[3...]) == Array(document.objects[3...]))
    }

    @Test func usesOnlyAnInstalledShellWhosePathCanFollowTheShebang() throws {
        let tmp = try TemporaryDirectory()
        #expect(ScriptShell.installed(developerDirectory: tmp.path) == nil)
        try FileSystem.write(Data(ScriptShell.contents.utf8), to: tmp.path + "/Dev/" + ScriptShell.relativePath)
        #expect(ScriptShell.installed(developerDirectory: tmp.path + "/Dev") == tmp.path + "/Dev/usr/libexec/nomac/sh")
        try FileSystem.write(Data(ScriptShell.contents.utf8), to: tmp.path + "/My Dev/" + ScriptShell.relativePath)
        #expect(ScriptShell.installed(developerDirectory: tmp.path + "/My Dev") == nil)
    }

    #if os(macOS)
    @Test func macOSShIsTheReference() {
        #expect(ScriptShell.warning() == nil)
    }
    #endif
}
