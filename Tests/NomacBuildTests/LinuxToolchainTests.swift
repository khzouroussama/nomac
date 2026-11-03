import Foundation
import Testing
@testable import NomacBuild
import NomacCore
import NomacTestSupport

@Suite struct LinuxToolchainTests {
    /// A release download's layout: the toolchain and the tools beside `bin/nomac`, each found
    /// only when it is there.
    @Test func findsTheToolchainAndToolsOfARelease() throws {
        let tmp = try TemporaryDirectory()
        let nomac = tmp.path + "/bin/nomac"
        let none = LinuxToolchain.bundled(nomacExecutable: nomac)
        #expect(none.toolchain == nil && none.llvmTools == nil)
        for file in ["bin/nomac", "swift/usr/bin/swift-frontend", "tools/lld"] {
            try FileSystem.write(Data(), to: tmp.path + "/" + file)
        }
        let found = LinuxToolchain.bundled(nomacExecutable: nomac)
        #expect(found.toolchain == URL(fileURLWithPath: tmp.path).path + "/swift/usr")
        #expect(found.llvmTools == URL(fileURLWithPath: tmp.path).path + "/tools")
    }

    /// A swift.org-shaped toolchain `usr` with files that must and must not be copied.
    private func makeToolchain(at usr: String) throws {
        for file in ["bin/swift-frontend", "bin/clang-21", "bin/lld", "lib/libclang.so.21.0.0", "lib/swift/linux/libswiftCore.so",
                     "lib/swift/host/libSwiftSyntax.so", "share/swift/features.json", "share/clang/features.json",
                     "lib/swift/shims/module.modulemap", "lib/swift/os/object.h", "lib/swift/dispatch/dispatch.h",
                     "lib/clang/21/include/stdarg.h", "lib/swift/linux/aarch64/glibc.modulemap",
                     "include/swift/bridging", "include/swift/bridging.modulemap", "include/swift/ExecutorImpl.h",
                     "lib/swift/swiftToCxx/_SwiftCxxInteroperability.h"] {
            try FileSystem.write(Data(file.utf8), to: usr + "/" + file)
        }
        try FileManager.default.createSymbolicLink(atPath: usr + "/bin/swiftc", withDestinationPath: "swift-frontend")
        try FileManager.default.createSymbolicLink(atPath: usr + "/bin/clang", withDestinationPath: "clang-21")
        try FileManager.default.createSymbolicLink(atPath: usr + "/bin/ld64.lld", withDestinationPath: "lld")
        try FileManager.default.createSymbolicLink(atPath: usr + "/lib/libclang.so", withDestinationPath: "libclang.so.21.0.0")
    }

    /// The directory `build-llvm-tools.sh` writes.
    private func makeLLVMTools(at path: String) throws {
        for tool in LinuxToolchain.llvmTools.keys {
            try FileSystem.write(Data("built \(tool)".utf8), to: path + "/" + tool)
        }
        try FileSystem.write(Data("APSL".utf8), to: path + "/ld64-licenses/APPLE_LICENSE")
        for (file, sha256) in LinuxToolchain.builtPatches {
            try FileSystem.write(Data((sha256 + "\n").utf8), to: path + "/" + file)
        }
    }

    /// The clang and libclang `build-llvm-tools.sh` writes with `CLANG=1`, and their patches' SHA-256.
    private func writePatchedClang(at path: String, patches: String? = LinuxToolchain.builtClangPatches.1) throws {
        try FileSystem.write(Data("patched clang".utf8), to: path + "/clang")
        try FileSystem.write(Data("patched libclang".utf8), to: path + "/libclang.so")
        if let patches {
            try FileSystem.write(Data((patches + "\n").utf8), to: path + "/" + LinuxToolchain.builtClangPatches.0)
        }
    }

    /// The patches' SHA-256 the installation expects are those of the repository's `.github/lld`,
    /// `.github/cctools`, `.github/clang` and `.github/swift`, as the build scripts compute them.
    @Test func expectsTheRepositorysPatches() throws {
        let github = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".github").path
        let expected = LinuxToolchain.builtPatches.merging([LinuxToolchain.builtClangPatches]) { first, _ in first }
        for (directory, file) in [("lld", "lld.patches.sha256"), ("cctools", "cctools.patches.sha256"), ("clang", "clang.patches.sha256")] {
            let names = try FileSystem.contentsOfDirectory(github + "/" + directory).filter { $0.hasSuffix(".patch") }.sorted()
            let bytes = try names.flatMap { [UInt8](try #require(FileSystem.contents(atPath: github + "/" + directory + "/" + $0))) }
            #expect(expected[file] == SHA256.digest(bytes).map { String(format: "%02x", $0) }.joined())
        }
        let names = try FileSystem.contentsOfDirectory(github + "/swift").filter { $0.hasSuffix(".patch") }.sorted()
        let bytes = try names.flatMap { [UInt8](try #require(FileSystem.contents(atPath: github + "/swift/" + $0))) }
        #expect(LinuxToolchain.swiftFrontendPatches.1 == SHA256.digest(bytes).map { String(format: "%02x", $0) }.joined())
    }

    /// Tools built with other patches, or before the scripts recorded them, are refused.
    @Test func refusesToolsBuiltWithOtherPatches() throws {
        for content in ["0000\n", nil] {
            let tmp = try TemporaryDirectory()
            try makeToolchain(at: tmp.path + "/swift/usr")
            try makeLLVMTools(at: tmp.path + "/llvm")
            if let content {
                try FileSystem.write(Data(content.utf8), to: tmp.path + "/llvm/lld.patches.sha256")
            } else {
                try FileManager.default.removeItem(atPath: tmp.path + "/llvm/cctools.patches.sha256")
            }
            let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
            #expect(throws: NomacError.self) {
                try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
            }
        }
    }

    @Test func copiesTheToolchainAndTheLLVMToolsIntoXcodeDefault() throws {
        let tmp = try TemporaryDirectory()
        try makeToolchain(at: tmp.path + "/swift/usr")
        try makeLLVMTools(at: tmp.path + "/llvm")
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let usr = developer + "/Toolchains/XcodeDefault.xctoolchain/usr"

        let installation = try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)

        #expect(installation.destination == usr)
        #expect(FileManager.default.contents(atPath: usr + "/bin/swift-frontend") == Data("bin/swift-frontend".utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/bin/swiftc") == "swift-frontend")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/bin/cc") == "clang")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/bin/c++") == "clang")
        #expect(FileManager.default.contents(atPath: usr + "/bin/ld64") == Data("built ld64".utf8))
        #expect(FileManager.default.contents(atPath: usr + "/bin/bitcode_strip") == Data("built bitcode_strip".utf8))
        #expect(FileManager.default.contents(atPath: usr + "/bin/libtool") == Data("built libtool".utf8))
        #expect(FileManager.default.contents(atPath: usr + "/bin/strip") == Data("built strip".utf8))
        #expect(FileManager.default.contents(atPath: usr + "/include/swift/bridging") == Data("include/swift/bridging".utf8))
        #expect(FileManager.default.contents(atPath: usr + "/include/swift/bridging.modulemap") == Data("include/swift/bridging.modulemap".utf8))
        let swiftToCxx = "lib/swift/swiftToCxx/_SwiftCxxInteroperability.h"
        #expect(FileManager.default.contents(atPath: usr + "/" + swiftToCxx) == Data(swiftToCxx.utf8))
        #expect(!FileManager.default.fileExists(atPath: usr + "/include/swift/ExecutorImpl.h"))
        #expect(FileManager.default.contents(atPath: usr + "/share/ld64/APPLE_LICENSE") == Data("APSL".utf8))
        #expect(FileManager.default.contents(atPath: usr + "/bin/ld64.lld") == Data(LinuxToolchain.linkerDispatcher.utf8))
        // SwiftPM's commands run the swift.org toolchain's, which builds for the build machine.
        for command in LinuxToolchain.swiftPMCommands {
            let text = String(decoding: FileManager.default.contents(atPath: usr + "/bin/" + command) ?? Data(), as: UTF8.self)
            #expect(text.hasSuffix("exec '\(FileSystem.absolute(tmp.path + "/swift/usr"))/bin/\(command)' \"$@\"\n"), "\(command)")
            #expect(FileManager.default.isExecutableFile(atPath: usr + "/bin/" + command))
        }
        let shell = developer + "/usr/libexec/nomac/sh"
        #expect(FileManager.default.contents(atPath: shell) == Data(ScriptShell.contents.utf8))
        #expect(FileManager.default.isExecutableFile(atPath: shell))
        for (path, contents) in [(InstallAttributes.chownPath, InstallAttributes.chown), (InstallAttributes.chmodPath, InstallAttributes.chmod),
                                 (LinuxToolchain.commandPath, LinuxToolchain.commandScript)] {
            #expect(FileManager.default.contents(atPath: developer + "/" + path) == Data(contents.utf8))
            #expect(FileManager.default.isExecutableFile(atPath: developer + "/" + path))
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/lib/libclang.so") == "libclang.so.21.0.0")
        #expect(FileSystem.isFile(usr + "/lib/swift/linux/libswiftCore.so"))
        #expect(FileSystem.isFile(usr + "/lib/swift/linux/aarch64/glibc.modulemap"))
        #expect(FileSystem.isFile(usr + "/lib/swift/host/libSwiftSyntax.so"))
        #expect(FileManager.default.contents(atPath: usr + "/share/clang/features.json") == Data("share/clang/features.json".utf8))
        #expect(FileManager.default.contents(atPath: usr + "/share/swift/features.json") == Data("share/swift/features.json".utf8))
        // The built LLVM tools replace the toolchain's lld; ld64.lld sends relocatable links to ld64.
        #expect(FileManager.default.contents(atPath: usr + "/bin/lld") == Data("built lld".utf8))
        #expect(FileManager.default.contents(atPath: usr + "/bin/llvm-dsymutil") == Data("built dsymutil".utf8))
        for name in ["clang.cfg", "clang++.cfg"] {
            #expect(FileManager.default.contents(atPath: usr + "/bin/" + name) == Data("-fuse-ld=lld\n-fclang-abi-compat=4.0\n-fcommon\n-fno-strict-return\n-mlinker-version=1166.2\n-fno-assume-unique-vtables\n-Wno-elaborated-enum-base\n".utf8))
        }
        let launcher = String(decoding: FileManager.default.contents(atPath: usr + "/bin/ld") ?? Data(), as: UTF8.self)
        #expect(launcher.hasPrefix("#!/bin/sh\n"))
        #expect(launcher.hasSuffix("exec \"$(dirname \"$0\")/ld64.lld\" \"$@\"\n"))
        #expect(try FileManager.default.attributesOfItem(atPath: usr + "/bin/ld")[.posixPermissions] as? Int == 0o755)
        // Xcode's tools nomac reimplements run nomac from their Xcode paths.
        for path in ["appintentsmetadataprocessor", "appintentsnltrainingprocessor", "codesign", "coremlc", "derq", "dsymutil", "tapi", "what"].map({ usr + "/bin/" + $0 })
            + ["actool", "ibtool", "intentbuilderc", "mapc", "momc", "xcrun", "xcstringstool"].map({ developer + "/usr/bin/" + $0 }) {
            let tool = (path as NSString).lastPathComponent
            let text = String(decoding: FileManager.default.contents(atPath: path) ?? Data(), as: UTF8.self)
            #expect(text.hasSuffix("export NOMAC_TOOL_DIRECTORY\nexec '/opt/no mac/nomac' \(tool) \"$@\"\n"), "\(tool)")
        }
        // Headers that would hide the SDK's or Xcode's are not copied into lib/swift, only into the
        // resource directory of the compiles for the build machine, with links to the rest.
        for absent in ["lib/swift/shims", "lib/swift/os", "lib/swift/dispatch", "lib/clang/21"] {
            #expect(!FileManager.default.fileExists(atPath: usr + "/" + absent), "\(absent) was copied")
        }
        for header in ["shims/module.modulemap", "os/object.h", "dispatch/dispatch.h"] {
            #expect(FileSystem.isFile(usr + "/lib/nomac/swift/" + header), "\(header)")
        }
        for link in ["clang", "host", "linux"] {
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/lib/nomac/swift/" + link) == "../../swift/" + link)
        }
        // Swift Build reads coremlc's version with what -q (B-243).
        let coremlc = String(decoding: FileManager.default.contents(atPath: usr + "/bin/coremlc") ?? Data(), as: UTF8.self)
        #expect(WhatStrings.strings(in: Data(coremlc.utf8)) == ["PROGRAM:coremlcompiler  PROJECT:CoreML-3600.25.1"])
        #expect(installation.filesCopied == 70)
    }

    /// The clang and libclang `build-llvm-tools.sh` built with `.github/clang` replace the files the
    /// toolchain's `clang` and `libclang.so` link to, which the other names keep reaching (ADR 0170).
    @Test func installsThePatchedClangOverTheToolchainsWhenBuilt() throws {
        var filesCopied: [Int] = []
        for built in [false, true] {
            let tmp = try TemporaryDirectory()
            try makeToolchain(at: tmp.path + "/swift/usr")
            try makeLLVMTools(at: tmp.path + "/llvm")
            if built {
                try writePatchedClang(at: tmp.path + "/llvm")
            }
            let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
            let usr = developer + "/Toolchains/XcodeDefault.xctoolchain/usr"
            let installation = try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
            #expect(installation.patchedClang == built)
            filesCopied.append(installation.filesCopied)
            #expect(FileManager.default.contents(atPath: usr + "/bin/clang-21") == Data((built ? "patched clang" : "bin/clang-21").utf8))
            #expect(FileManager.default.contents(atPath: usr + "/lib/libclang.so.21.0.0") == Data((built ? "patched libclang" : "lib/libclang.so.21.0.0").utf8))
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/bin/clang") == "clang-21")
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/bin/c++") == "clang")
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/lib/libclang.so") == "libclang.so.21.0.0")
        }
        // The patched files take the place of the toolchain's; none is added.
        #expect(filesCopied[0] == filesCopied[1])
    }

    /// The swift-frontend and dependency scanner `build-swift-frontend.sh` built replace the files
    /// the toolchain's `swift-frontend` and `lib/swift/host/lib_InternalSwiftScan.so` are (ADR 0106).
    @Test func installsThePatchedSwiftFrontendOverTheToolchainsWhenBuilt() throws {
        var filesCopied: [Int] = []
        for built in [false, true] {
            let tmp = try TemporaryDirectory()
            try makeToolchain(at: tmp.path + "/swift/usr")
            try makeScanner(at: tmp.path + "/swift/usr")
            try makeLLVMTools(at: tmp.path + "/llvm")
            if built {
                try makeSwiftFrontend(at: tmp.path + "/llvm", patches: LinuxToolchain.swiftFrontendPatches.1)
            }
            let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
            let usr = developer + "/Toolchains/XcodeDefault.xctoolchain/usr"
            let installation = try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
            #expect(installation.patchedSwiftFrontend == built)
            filesCopied.append(installation.filesCopied)
            #expect(FileManager.default.contents(atPath: usr + "/bin/swift-frontend") == Data((built ? "patched swift-frontend" : "bin/swift-frontend").utf8))
            #expect(FileManager.default.contents(atPath: usr + "/lib/swift/host/compiler/lib_InternalSwiftScan.so")
                == Data((built ? "patched scanner" : "lib/swift/host/compiler/lib_InternalSwiftScan.so").utf8))
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/lib/swift/host/lib_InternalSwiftScan.so") == "compiler/lib_InternalSwiftScan.so")
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: usr + "/bin/swiftc") == "swift-frontend")
        }
        #expect(filesCopied[0] == filesCopied[1])
    }

    /// A frontend without its scanner, or built with other patches, is refused.
    @Test func refusesAPatchedSwiftFrontendWithoutItsScannerOrPatches() throws {
        for (scanner, patches) in [(false, LinuxToolchain.swiftFrontendPatches.1), (true, "0000"), (true, nil)] {
            let tmp = try TemporaryDirectory()
            try makeToolchain(at: tmp.path + "/swift/usr")
            try makeScanner(at: tmp.path + "/swift/usr")
            try makeLLVMTools(at: tmp.path + "/llvm")
            try makeSwiftFrontend(at: tmp.path + "/llvm", patches: patches)
            if !scanner {
                try FileManager.default.removeItem(atPath: tmp.path + "/llvm/lib_InternalSwiftScan.so")
            }
            let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
            #expect(throws: NomacError.self) {
                try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
            }
        }
    }

    /// The dependency scanner of a swift.org toolchain: `lib/swift/host`'s links to `compiler`'s.
    private func makeScanner(at usr: String) throws {
        try FileSystem.write(Data("lib/swift/host/compiler/lib_InternalSwiftScan.so".utf8), to: usr + "/lib/swift/host/compiler/lib_InternalSwiftScan.so")
        try FileManager.default.createSymbolicLink(atPath: usr + "/lib/swift/host/lib_InternalSwiftScan.so", withDestinationPath: "compiler/lib_InternalSwiftScan.so")
    }

    /// What `build-swift-frontend.sh` writes, with `patches` as its patches' SHA-256.
    private func makeSwiftFrontend(at path: String, patches: String?) throws {
        try FileSystem.write(Data("patched swift-frontend".utf8), to: path + "/swift-frontend")
        try FileSystem.write(Data("patched scanner".utf8), to: path + "/lib_InternalSwiftScan.so")
        if let patches {
            try FileSystem.write(Data((patches + "\n").utf8), to: path + "/" + LinuxToolchain.swiftFrontendPatches.0)
        }
    }

    /// A patched clang without its libclang would compile what Swift Build's scan of the
    /// unpatched libclang plans, so the installation refuses one without the other.
    @Test func refusesThePatchedClangWithoutItsLibclang() throws {
        let tmp = try TemporaryDirectory()
        try makeToolchain(at: tmp.path + "/swift/usr")
        try makeLLVMTools(at: tmp.path + "/llvm")
        try FileSystem.write(Data("patched clang".utf8), to: tmp.path + "/llvm/clang")
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        #expect(throws: NomacError.self) {
            try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
        }
    }

    /// A patched clang built with other patches, or before the script recorded them, is refused.
    @Test func refusesAPatchedClangBuiltWithOtherPatches() throws {
        for patches in ["0000", nil] {
            let tmp = try TemporaryDirectory()
            try makeToolchain(at: tmp.path + "/swift/usr")
            try makeLLVMTools(at: tmp.path + "/llvm")
            try writePatchedClang(at: tmp.path + "/llvm", patches: patches)
            let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
            #expect(throws: NomacError.self) {
                try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
            }
        }
    }

    @Test func refusesADeveloperDirectoryThatHasACompiler() throws {
        let tmp = try TemporaryDirectory()
        try makeToolchain(at: tmp.path + "/swift/usr")
        try makeLLVMTools(at: tmp.path + "/llvm")
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        try FileSystem.write(Data("xcode".utf8), to: developer + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend")
        #expect(throws: NomacError.self) {
            try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
        }
    }

    @Test func refusesMissingLLVMTools() throws {
        let tmp = try TemporaryDirectory()
        try makeToolchain(at: tmp.path + "/swift/usr")
        try FileSystem.write(Data("built lld".utf8), to: tmp.path + "/llvm/lld")
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        #expect(throws: NomacError.self) {
            try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
        }
    }

    /// Relocatable links reach ld64 as they are; every other link reaches lld merging categories
    /// first, so that the link's own `-no_objc_category_merging` comes later and wins
    /// (objc_link_experiments.py: Xcode's `ld` merges by default).
    @Test func dispatchesLinksAsXcodesLinkerWouldMergeCategories() throws {
        let tmp = try TemporaryDirectory()
        let bin = tmp.path + "/bin"
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        for (name, contents) in [("ld64.lld", LinuxToolchain.linkerDispatcher), ("lld", "#!/bin/sh\necho lld \"$@\"\n"), ("ld64", "#!/bin/sh\necho ld64 \"$@\"\n")] {
            try FileSystem.write(Data(contents.utf8), to: bin + "/" + name)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin + "/" + name)
        }
        let link = try Subprocess.run(bin + "/ld64.lld", ["-o", "a.out", "a.o", "-no_objc_category_merging"])
        #expect(link.outputString == "lld -flavor darwin -objc_category_merging -o a.out a.o -no_objc_category_merging\n")
        let relocatable = try Subprocess.run(bin + "/ld64.lld", ["-r", "-o", "a.o", "b.o"])
        #expect(relocatable.outputString == "ld64 -r -o a.o b.o\n")
    }

    /// A toolchain installed before Clang 4's ABI would build modules the Swift compiles
    /// cannot load; a build refuses it, and accepts the one this nomac installs.
    @Test func refusesAClangConfigurationOfAnEarlierInstall() throws {
        let tmp = try TemporaryDirectory()
        try makeToolchain(at: tmp.path + "/swift/usr")
        try makeLLVMTools(at: tmp.path + "/llvm")
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        try LinuxToolchain.checkClangConfiguration(developerDirectory: developer)
        _ = try LinuxToolchain.install(toolchain: tmp.path + "/swift/usr", llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
        try LinuxToolchain.checkClangConfiguration(developerDirectory: developer)
        try FileSystem.write(Data("-fuse-ld=lld\n".utf8), to: developer + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang.cfg")
        #expect(throws: NomacError.self) {
            try LinuxToolchain.checkClangConfiguration(developerDirectory: developer)
        }
    }

    @Test func refusesWhatIsNotAToolchain() throws {
        let tmp = try TemporaryDirectory()
        try makeLLVMTools(at: tmp.path + "/llvm")
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        #expect(throws: NomacError.self) {
            try LinuxToolchain.install(toolchain: tmp.path, llvmTools: tmp.path + "/llvm", nomacExecutable: "/opt/no mac/nomac", developerDirectory: developer)
        }
    }
}

/// Install builds' owner, group and mode off macOS (docs/formats/build.md "Owner, group and mode").
@Suite struct InstallAttributesTests {
    /// Written through `FileSystem.write`, whose descriptor no child started meanwhile keeps open,
    /// so running the script right after cannot fail with ETXTBSY under the parallel suite.
    static func script(_ contents: String, in directory: String) throws -> String {
        let path = directory + "/script"
        try FileSystem.write(Data(contents.utf8), to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test func buildsNameTheScripts() {
        #expect(InstallAttributes.overrides(developerDirectory: "/X/Contents/Developer")
                == ["CHOWN": "/X/Contents/Developer/usr/libexec/nomac/chown", "CHMOD": "/X/Contents/Developer/usr/libexec/nomac/chmod"])
    }

    /// Swift Build's `chmod -RH u+w,go-w,a+rX`, as BSD chmod applies it, with GNU chmod.
    @Test func chmodTakesBSDsFlags() throws {
        let tmp = try TemporaryDirectory()
        let chmod = try Self.script(InstallAttributes.chmod, in: tmp.path)
        try FileManager.default.createDirectory(atPath: tmp.path + "/Kit.framework", withIntermediateDirectories: true)
        try FileSystem.write(Data(), to: tmp.path + "/Kit.framework/Kit")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path + "/Kit.framework/Kit")
        #expect(try Subprocess.run(chmod, ["-RH", "u+w,go-w,a+rX", tmp.path + "/Kit.framework"]).exitStatus == 0)
        #expect(try FileManager.default.attributesOfItem(atPath: tmp.path + "/Kit.framework/Kit")[.posixPermissions] as? Int == 0o644)
    }

    #if os(Linux)
    /// The reference Mac's user and group, which this machine lacks, leave the files as they are;
    /// the machine's own are applied.
    @Test func chownLeavesOutWhatTheMachineLacks() throws {
        let tmp = try TemporaryDirectory()
        let chown = try Self.script(InstallAttributes.chown, in: tmp.path)
        try FileSystem.write(Data(), to: tmp.path + "/file")
        #expect(try Subprocess.run(chown, ["-RH", "nomac-no-such-user:nomac-no-such-group", tmp.path + "/file"]).exitStatus == 0)
        let user = try Subprocess.run("/usr/bin/id", ["-un"]).outputString.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = try Subprocess.run("/usr/bin/id", ["-gn"]).outputString.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(try Subprocess.run(chown, ["-RH", user + ":nomac-no-such-group", tmp.path + "/file"]).exitStatus == 0)
        #expect(try Subprocess.run(chown, ["-RH", user + ":" + group, tmp.path + "/file"]).exitStatus == 0)
    }
    #endif
}
