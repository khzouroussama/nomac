#if os(Linux)
import Foundation
import Testing
@testable import NomacBuild
import NomacCore
import NomacTestSupport

/// nomac's shell with the exec interposer, on self-written scripts shaped as CocoaPods' `[CP]`
/// phases: a phase runs a `#!/bin/sh` script by path (docs/adr/0180-scripts-run-by-path.md).
@Suite struct ExecInterposerTests {
    private func developerDirectory(interposer: Bool) throws -> (TemporaryDirectory, String) {
        let tmp = try TemporaryDirectory()
        let shell = tmp.path + "/" + ScriptShell.relativePath
        try FileSystem.write(Data(ScriptShell.contents.utf8), to: shell)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell)
        if interposer {
            let clang = try #require(Subprocess.locate("clang"))
            #expect(try ExecInterposer.install(clang: clang, developerDirectory: tmp.path) == tmp.path + "/" + ExecInterposer.relativePath)
        }
        return (tmp, shell)
    }

    private func script(_ text: String, at path: String) throws {
        try FileSystem.write(Data(text.utf8), to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    /// The phase's output. A script written just before can be busy when the phase's shell runs
    /// it, while a child another test starts holds its descriptor (ETXTBSY, 64e86e3);
    /// `Subprocess.run` starts again only when it launches the file itself, so the phase is
    /// started again too.
    private func phase(_ shell: String, _ command: String) throws -> String {
        var attempt = 0
        while true {
            attempt += 1
            let result = try Subprocess.run(shell, ["-c", command], environment: ["PATH": "/usr/bin:/bin"])
            if !result.errorString.contains("Text file busy") || attempt == 20 { return result.outputString }
            Thread.sleep(forTimeInterval: 0.025 * Double(attempt))
        }
    }

    @Test func scriptsOfBinShRunUnderNomacsShell() throws {
        let (tmp, shell) = try developerDirectory(interposer: true)
        try script("#!/bin/sh\nset -e\nset -u\nset -o pipefail\narray=(a b)\n[[ ${array[1]} == b ]] && echo \"nested ${BASH_VERSION:+bash} $0 $1\"\n",
                   at: tmp.path + "/frameworks.sh")
        #expect(try phase(shell, "\"\(tmp.path)/frameworks.sh\" one") == "nested bash \(tmp.path)/frameworks.sh one\n")
        try script("#!/bin/sh\n\"\(tmp.path)/frameworks.sh\" two\n", at: tmp.path + "/outer.sh")
        #expect(try phase(shell, "\"\(tmp.path)/outer.sh\"") == "nested bash \(tmp.path)/frameworks.sh two\n")
    }

    @Test func theShebangsArgumentAndShOnThePathToo() throws {
        let (tmp, shell) = try developerDirectory(interposer: true)
        try script("#!/bin/sh -e\nfalse\necho not reached\n", at: tmp.path + "/stops.sh")
        #expect(try phase(shell, "\"\(tmp.path)/stops.sh\"; echo $?") == "1\n")
        #expect(try phase(shell, "env sh -c 'echo ${BASH_VERSION:+bash}'") == "bash\n")
        #expect(try phase(shell, "/bin/sh -c 'echo ${BASH_VERSION:+bash}'") == "bash\n")
    }

    /// React Native 0.81's codegen phase runs `/bin/cp -R -X`, BSD's copy without extended
    /// attributes, which GNU cp refuses: the machine's cp runs without the `X`, by its path or
    /// found on `PATH`, and an operand after `--` stays as it is (docs/adr/0183).
    @Test func cpRunsWithoutBSDsXOption() throws {
        let (tmp, shell) = try developerDirectory(interposer: true)
        try FileSystem.write(Data("spec\n".utf8), to: tmp.path + "/src/a/b.h")
        try FileSystem.write(Data("minus\n".utf8), to: tmp.path + "/-X")
        let root = "cd \"\(tmp.path)\" && "
        #expect(try phase(shell, root + "/bin/cp -R -X src/. one && cat one/a/b.h") == "spec\n")
        #expect(try phase(shell, root + "cp -aX src/. two && cat two/a/b.h") == "spec\n")
        #expect(try phase(shell, root + "cp -X -R src/. three && cat three/a/b.h") == "spec\n")
        #expect(try phase(shell, root + "cp -- -X copy && cat copy") == "minus\n")
    }

    /// CocoaPods' frameworks script signs with `/usr/bin/codesign`, which the machine lacks: the
    /// developer directory's runs, with the same arguments.
    @Test func macOSPathsOfDeveloperToolsRunTheDeveloperDirectorys() throws {
        let (tmp, shell) = try developerDirectory(interposer: true)
        try script("#!/bin/sh\necho \"nomac codesign $*\"\n", at: tmp.path + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign")
        #expect(try phase(shell, "/usr/bin/codesign --force --sign - App.framework") == "nomac codesign --force --sign - App.framework\n")
        // React Native's asset-catalog.sh reads Info.plist with /usr/libexec/PlistBuddy.
        try script("#!/bin/sh\necho \"nomac PlistBuddy $*\"\n", at: tmp.path + "/usr/libexec/PlistBuddy")
        #expect(try phase(shell, "echo \"$(/usr/libexec/PlistBuddy -c 'Print :RCTUseAssetCatalog' Info.plist)\"")
            == "nomac PlistBuddy -c Print :RCTUseAssetCatalog Info.plist\n")
    }

    @Test func otherInterpretersAreLeftAlone() throws {
        let (tmp, shell) = try developerDirectory(interposer: true)
        try script("#!/usr/bin/env python3\nimport os\nprint(os.environ['LD_PRELOAD'].endswith('libnomac-exec.so'))\n", at: tmp.path + "/tool.py")
        #expect(try phase(shell, "\"\(tmp.path)/tool.py\"") == "True\n")
    }

    @Test func withoutTheInterposerTheMachinesShRunsThem() throws {
        let (tmp, shell) = try developerDirectory(interposer: false)
        try script("#!/bin/sh\necho \"${BASH_VERSION:+bash}\"\n", at: tmp.path + "/frameworks.sh")
        let machine = try Subprocess.run("/bin/sh", ["-c", "echo ${BASH_VERSION:+bash}"]).outputString
        #expect(try phase(shell, "\"\(tmp.path)/frameworks.sh\"") == machine)
    }
}
#endif
