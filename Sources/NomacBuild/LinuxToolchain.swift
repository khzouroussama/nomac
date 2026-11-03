import Foundation
import NomacCore

/// Puts an open-source Swift toolchain's executables where Xcode keeps its own, in the
/// `XcodeDefault` toolchain of a developer directory (docs/adr/0100-linux-toolchain.md).
///
/// The compilers locate their resource directories from their own path: run from
/// `XcodeDefault.xctoolchain/usr/bin`, `swift-frontend` takes Xcode's `usr/lib/swift` (no
/// `shims`, so the SDK's shims are used, as with Xcode's compiler) and `clang` takes Xcode's
/// Clang resource headers. Swift Build finds tools in the same directory first, so the command
/// lines it plans name the same paths as Xcode's.
public enum LinuxToolchain {
    /// Paths inside the open-source toolchain's `usr` that are copied: the executables, the
    /// shared libraries they load, and the feature lists Swift Build reads next to each compiler.
    /// Header directories of `lib/swift` (`shims`, `os`, `dispatch`, `Block`, `CoreFoundation`)
    /// are left out because they would hide the SDK's, and `lib/clang` because Xcode's is kept.
    /// Of `include`, the two files Xcode's toolchain has: C++ interoperability's `swift/bridging`
    /// and its module map, the same bytes in Xcode 27.0's and in swift.org 6.4.0's (expo-default's
    /// ExpoModulesJSI includes `<swift/bridging>`). Of those header directories, `swiftToCxx`, the
    /// headers of C++ that calls Swift (`_SwiftCxxInteroperability.h`), which Xcode 27.0's
    /// toolchain has in `usr/lib/swift` with swift.org 6.4.0's bytes (Nitro's generated headers
    /// include them: the RN holdout's rn-libs).
    public static let copiedDirectories = ["bin", "lib/swift/linux", "lib/swift/host", "lib/swift/swiftToCxx", "share/clang", "share/swift",
                                           "include/swift/bridging", "include/swift/bridging.modulemap"]

    /// The resource directory of the Swift compiles for the build machine itself (macro and other
    /// host tool packages, built for Linux): the header directories left out of `lib/swift`, and
    /// links to its `linux`, `host` and `clang`. Swift Build passes Linux targets neither `-sdk`
    /// nor `-sysroot`, so without them the compiler finds no `SwiftShims` ("missing required
    /// module 'SwiftShims'", swiftfin's swift-syntax); ``LinuxCompiler`` names this directory.
    public static let hostResourceDirectory = "lib/nomac/swift"
    static let hostHeaderDirectories = ["Block", "CoreFoundation", "_FoundationCShims", "_foundation_unicode", "apinotes", "dispatch", "os", "shims", "swiftToCxx"]
    static let hostResourceLinks = ["clang", "host", "linux"]

    /// The result of an installation.
    public struct Installation: Sendable, Equatable {
        /// The toolchain's `usr` directory inside the developer directory.
        public var destination: String
        public var filesCopied: Int
        /// Whether the LLVM tools directory's clang and libclang replaced the toolchain's (``patchedClang``).
        public var patchedClang = false
        /// Whether its swift-frontend and dependency scanner replaced the toolchain's (``patchedSwiftFrontend``).
        public var patchedSwiftFrontend = false
    }

    /// The linker tools `.github/scripts/build-llvm-tools.sh` and `build-cctools.sh` build, and the
    /// names they are installed under. `lld` replaces the toolchain's, which refuses Apple
    /// platforms; `dsymutil` runs behind nomac's (docs/adr/0102-linker.md); `ld64` makes the
    /// relocatable links, and `bitcode_strip` is the one Swift Build hands `CopySwiftLibs`
    /// (docs/adr/0104-relocatable-links.md); `libtool` makes static libraries, and `strip` is the
    /// Mach-O strip Swift Build's Strip tasks run, which otherwise find the machine's GNU strip
    /// (docs/adr/0181-static-libraries.md); `lipo`, which scripts run from the toolchain's `usr/bin`
    /// as from Xcode's (CocoaPods' frameworks script, `lipo -info`, in an archive build).
    /// The swift.org toolchain and the tools a release download keeps beside nomac
    /// (`<prefix>/bin/nomac`, `<prefix>/swift/usr`, `<prefix>/tools`; docs/INSTALL.md), each when present.
    public static func bundled(nomacExecutable: String) -> (toolchain: String?, llvmTools: String?) {
        let prefix = URL(fileURLWithPath: nomacExecutable).deletingLastPathComponent().deletingLastPathComponent().path
        let toolchain = prefix + "/swift/usr", tools = prefix + "/tools"
        return (FileSystem.isFile(toolchain + "/bin/swift-frontend") ? toolchain : nil,
                FileSystem.isFile(tools + "/lld") ? tools : nil)
    }

    public static let llvmTools = ["lld": "lld", "dsymutil": "llvm-dsymutil", "ld64": "ld64", "bitcode_strip": "bitcode_strip", "libtool": "libtool",
                                   "strip": "strip", "lipo": "lipo"]

    /// clang and libclang built with the patches in `.github/clang` (`build-llvm-tools.sh` with
    /// `CLANG=1`; ADR 0170), by the toolchain path each replaces, optional: when the LLVM tools
    /// directory has them, each replaces the file the toolchain's path links to, so `clang++`, `cc`
    /// and `c++` run the patched clang too. They go together: Swift Build's dependency scan runs
    /// clang's driver from libclang, and the command lines it plans are the ones the compiles run.
    static let patchedClang = ["clang": "bin/clang", "libclang.so": "lib/libclang.so"]

    /// swift-frontend and its dependency scanner built with the patches in `.github/swift` against
    /// the LLVM and Clang of `.github/clang` (`build-swift-frontend.sh`; ADR 0106), by the toolchain
    /// path each replaces, optional as ``patchedClang`` is. They go together: the driver passes the
    /// frontend only the options the scanner lists (`-stack-check`).
    static let patchedSwiftFrontend = ["swift-frontend": "bin/swift-frontend", "lib_InternalSwiftScan.so": "lib/swift/host/lib_InternalSwiftScan.so"]

    /// The SHA-256 of `.github/swift`'s patches, which `build-swift-frontend.sh` writes next to the
    /// frontend it builds: a frontend built with other patches is refused, as ``builtPatches`` are.
    static let swiftFrontendPatches = ("swift-frontend.patches.sha256", "abbe5674830fb382ee365c57c62d18a9d45722c24af7d224fc9041887a5efdeb")

    /// The SHA-256 of `.github/lld`'s and `.github/cctools`' patches, concatenated in name order, as
    /// `build-llvm-tools.sh` and `build-cctools.sh` write them next to the tools they build: tools
    /// built with other patches link and strip otherwise than this nomac's rules (an lld from before
    /// the seventh patch left package frameworks' dSYMs empty), so the installation refuses them.
    static let builtPatches = ["lld.patches.sha256": "3f6ced3d46f2181746af2d6b98561b7de733df36e529ce75d4086bf7b8ded314",
                               "cctools.patches.sha256": "538cc1d8ed37a00d764e61640b24ee6fb468c7914cd29b75bb937b081de5f177"]

    /// The SHA-256 of `.github/clang`'s patches, which `build-llvm-tools.sh` with `CLANG=1` writes
    /// next to the patched clang: one built with other patches compiles otherwise than this
    /// nomac's rules, so the installation refuses it.
    static let builtClangPatches = ("clang.patches.sha256", "158b56e9e3f7a7579f4ecd41a6bd07cf49329380a385208d6675fb63214ef875")

    /// Apple's license and cctools-port's notices for `ld64`, which `build-cctools.sh` writes next
    /// to it and the toolchain keeps in `share/ld64` (docs/adr/0104-relocatable-links.md).
    static let ld64Licenses = "ld64-licenses"

    /// `ld64.lld`, which clang runs for every link (`-fuse-ld=lld`): relocatable links go to
    /// `ld64`, since lld writes no relocatable Mach-O file (docs/adr/0104-relocatable-links.md),
    /// and every other link to lld, merging categories into their classes as Xcode's `ld` does by
    /// default; a `-no_objc_category_merging` among the link's arguments comes later and wins
    /// (docs/adr/0102-linker.md item 10).
    static let linkerDispatcher = """
        #!/bin/sh
        # Written by 'nomac toolchain install' (docs/adr/0104-relocatable-links.md, 0102-linker.md).
        directory=$(dirname "$0")
        for argument in "$@"; do
          [ "$argument" = -r ] && exec "$directory/ld64" "$@"
        done
        exec "$directory/lld" -flavor darwin -objc_category_merging "$@"

        """

    /// Xcode's tools nomac reimplements, by their path in the developer directory, where Xcode keeps
    /// them; each gets a launcher there that runs the nomac command of the same name. `xcrun` and
    /// `file`, which macOS keeps in `/usr/bin`, and `md5`, in `/sbin`, go in the developer
    /// directory's `usr/bin`, which script phases' `PATH` lists before those, as does `xcodebuild`,
    /// which Xcode keeps there; `ditto`,
    /// `derq` and `what`, also in macOS's `/usr/bin`, in the toolchain's `usr/bin`, which it lists
    /// first and where Swift Build finds `derq` and `what` off macOS (docs/upstream/swift-build.md
    /// sections 5 and 10);
    /// `PlistBuddy`, which macOS keeps in `/usr/libexec`, in the developer directory's
    /// `usr/libexec`, where the exec interposer sends scripts that run it by that path.
    public static let nomacTools = [
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor",
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsnltrainingprocessor",
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign",
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/coremlc",
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/derq",
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/ditto",
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil",
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/dwarfdump",
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/tapi",
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/what",
        "usr/bin/actool",
        "usr/bin/copypng",
        "usr/bin/embeddedBinaryValidationUtility",
        "usr/bin/file",
        "usr/bin/ibtool",
        "usr/bin/intentbuilderc",
        "usr/bin/mapc",
        "usr/bin/md5",
        "usr/bin/momc",
        "usr/bin/xcrun",
        "usr/bin/xcodebuild",
        "usr/bin/xcstringstool",
        "usr/libexec/PlistBuddy",
    ]

    /// SwiftPM's commands, which a script phase runs to build a package's tool for the build machine
    /// and run it (home-assistant's `env -u SDKROOT swift run`, `script_swiftpm_experiments.py`).
    /// The toolchain's copies would compile manifests and sources with its `lib/swift`, which lacks
    /// the headers the build machine's compiles need ("missing required module 'SwiftShims'"), so
    /// they run the commands of the swift.org toolchain nomac was installed from, as Xcode's run
    /// its own for the Mac.
    public static let swiftPMCommands = ["swift-build", "swift-experimental-sdk", "swift-package", "swift-package-collection",
                                         "swift-package-registry", "swift-run", "swift-sdk", "swift-test"]

    /// Links Xcode 27.0's toolchain has in `usr/bin` and swift.org's does not. Swift Build runs
    /// `cc` by name (the Info.plist's `Preprocess` task, tofu), and finds it in the toolchain.
    public static let compilerLinks = ["c++": "clang", "cc": "clang"]

    /// `clang.cfg` and `clang++.cfg`, Clang's default configuration files: `clang` links with the
    /// installed `ld64.lld`, and passes it `-platform_version` as it does for lld. Without them
    /// it runs `ld` with the arguments of an ld64 of unknown version (`-iphoneos_version_min`),
    /// which `ld64.lld` rejects. Every compile follows Xcode's C++ ABI (``LinuxCompiler/clangABI``)
    /// and gets the defaults Xcode's driver adds (``LinuxCompiler/appleDriverDefaults``), script
    /// phases' too. A configuration file's options come before the command line's, so a project's
    /// `-fno-common` (`GCC_NO_COMMON_BLOCKS`) still wins; they also reach Linux targets, which
    /// Xcode's driver gives neither. They draw no unused-argument warning when clang only links,
    /// assembles or preprocesses.
    static let clangConfiguration = (["-fuse-ld=lld", LinuxCompiler.clangABI] + LinuxCompiler.appleDriverDefaults).joined(separator: "\n") + "\n"

    /// `ld`, for Swift Build's linker probe: it runs `ld64.lld`, which identifies itself
    /// (`--version`: `LLD 21.1.6`), so a GNU `ld` elsewhere on the machine is never taken for it.
    static let ldLauncher = """
        #!/bin/sh
        # Written by 'nomac toolchain install' (docs/adr/0102-linker.md).
        exec "$(dirname "$0")/ld64.lld" "$@"

        """

    /// Copies the toolchain whose `usr` directory is `toolchain`, and the LLVM tools in
    /// `llvmTools`, into `developerDirectory`, with launchers for ``nomacTools`` that run
    /// `nomacExecutable`.
    ///
    /// The developer directory must have no Swift compiler yet (a `nomac sdk` subset): Swift
    /// Build reads the feature lists next to the compilers, so they must be the installed
    /// compilers' own. No file of the developer directory is ever replaced.
    public static func install(toolchain: String, llvmTools: String, nomacExecutable: String, developerDirectory: String) throws -> Installation {
        let source = FileSystem.absolute(toolchain)
        guard FileSystem.isFile(source + "/bin/swift-frontend") else {
            throw NomacError("not the usr directory of a Swift toolchain (no bin/swift-frontend)", path: source)
        }
        let tools = FileSystem.absolute(llvmTools)
        for tool in Self.llvmTools.keys.sorted() where !FileSystem.isFile(tools + "/" + tool) {
            throw NomacError("no \(tool) in the LLVM tools directory (build them with .github/scripts/build-llvm-tools.sh and build-cctools.sh)", path: tools)
        }
        guard FileSystem.isDirectory(tools + "/" + Self.ld64Licenses) else {
            throw NomacError("no \(Self.ld64Licenses) next to ld64 (build-cctools.sh writes them)", path: tools)
        }
        for (file, sha256) in Self.builtPatches.sorted(by: { $0.key < $1.key }) {
            let built = builtStamp(file, in: tools)
            guard built == sha256 else {
                throw NomacError("the LLVM tools were built with other patches than this nomac's (\(file) \(built.map { "is " + $0 } ?? "missing")): build them again with .github/scripts/build-llvm-tools.sh and build-cctools.sh", path: tools)
            }
        }
        let toolchainDirectory = FileSystem.absolute(developerDirectory) + "/Toolchains/XcodeDefault.xctoolchain"
        let destination = toolchainDirectory + "/usr"
        guard FileSystem.isFile(toolchainDirectory + "/ToolchainInfo.plist") else {
            throw NomacError("the developer directory has no XcodeDefault toolchain", path: developerDirectory)
        }
        guard !FileManager.default.fileExists(atPath: destination + "/bin/swift-frontend") else {
            throw NomacError("the developer directory already has a Swift compiler; install into a fresh 'nomac sdk install'", path: developerDirectory)
        }
        var installation = Installation(destination: destination, filesCopied: 0)
        var relativePaths = copiedDirectories
        relativePaths += try FileSystem.sortedContents(of: source + "/lib").filter { $0.contains(".so") }.map { "lib/" + $0 }
        let toolchainPrefix = "Toolchains/XcodeDefault.xctoolchain/usr/"
        let clangFiles = try replacements(Self.patchedClang, in: tools, source: source, writtenBy: "build-llvm-tools.sh with CLANG=1")
        let frontendFiles = try replacements(Self.patchedSwiftFrontend, in: tools, source: source, writtenBy: "build-swift-frontend.sh")
        if !frontendFiles.isEmpty {
            let (file, sha256) = Self.swiftFrontendPatches
            let built = builtStamp(file, in: tools)
            guard built == sha256 else {
                throw NomacError("the swift-frontend was built with other patches than this nomac's (\(file) \(built.map { "is " + $0 } ?? "missing")): build it again with .github/scripts/build-swift-frontend.sh", path: tools)
            }
        }
        if !clangFiles.isEmpty {
            let (file, sha256) = Self.builtClangPatches
            let built = builtStamp(file, in: tools)
            guard built == sha256 else {
                throw NomacError("the LLVM tools' clang was built with other patches than this nomac's (\(file) \(built.map { "is " + $0 } ?? "missing")): build it again with .github/scripts/build-llvm-tools.sh and CLANG=1", path: tools)
            }
        }
        installation.patchedClang = !clangFiles.isEmpty
        installation.patchedSwiftFrontend = !frontendFiles.isEmpty
        let patchedFiles = clangFiles.merging(frontendFiles) { $1 }
        let replaced = Set(Self.llvmTools.values.map { "bin/" + $0 } + ["bin/ld64.lld"] + patchedFiles.values
            + Self.nomacTools.filter { $0.hasPrefix(toolchainPrefix) }.map { String($0.dropFirst(toolchainPrefix.count)) }
            + Self.swiftPMCommands.map { "bin/" + $0 })
        for relative in relativePaths {
            try copy(relative, from: source, to: destination, skipping: replaced, into: &installation)
        }
        let hostResources = destination + "/" + hostResourceDirectory
        for directory in hostHeaderDirectories where FileSystem.isDirectory(source + "/lib/swift/" + directory) {
            try copy("lib/swift/" + directory, from: source, to: destination, skipping: [], into: &installation, as: hostResourceDirectory + "/" + directory)
        }
        for link in hostResourceLinks {
            try FileManager.default.createDirectory(atPath: hostResources, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: hostResources + "/" + link, withDestinationPath: "../../swift/" + link)
            installation.filesCopied += 1
        }
        for (tool, name) in Self.llvmTools.sorted(by: { $0.key < $1.key }) {
            try copy(tools + "/" + tool, to: destination + "/bin/" + name, into: &installation)
        }
        for (tool, file) in patchedFiles.sorted(by: { $0.key < $1.key }) {
            try copy(tools + "/" + tool, to: destination + "/" + file, into: &installation)
        }
        for license in try FileSystem.sortedContents(of: tools + "/" + Self.ld64Licenses) {
            try copy(tools + "/" + Self.ld64Licenses + "/" + license, to: destination + "/share/ld64/" + license, into: &installation)
        }
        for (link, target) in Self.compilerLinks.sorted(by: { $0.key < $1.key }) {
            let path = destination + "/bin/" + link
            guard !FileSystem.exists(path) else { throw NomacError("the toolchain already has this tool", path: path) }
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
            installation.filesCopied += 1
        }
        let developer = FileSystem.absolute(developerDirectory)
        var written = [("clang.cfg", clangConfiguration, 0o644), ("clang++.cfg", clangConfiguration, 0o644), ("ld", ldLauncher, 0o755),
                       ("ld64.lld", linkerDispatcher, 0o755)]
            .map { (toolchainPrefix + "bin/" + $0.0, $0.1, $0.2) }
        written += Self.nomacTools.map { ($0, launcher(command: ($0 as NSString).lastPathComponent, nomacExecutable: nomacExecutable), 0o755) }
        written += Self.swiftPMCommands.map { (toolchainPrefix + "bin/" + $0, sourceLauncher(source + "/bin/" + $0), 0o755) }
        written.append((ScriptShell.relativePath, ScriptShell.contents, 0o755))
        written.append((Self.commandPath, Self.commandScript, 0o755))
        written += [(InstallAttributes.chownPath, InstallAttributes.chown, 0o755), (InstallAttributes.chmodPath, InstallAttributes.chmod, 0o755)]
        for (relative, contents, permissions) in written {
            let path = developer + "/" + relative
            guard !FileManager.default.fileExists(atPath: path) else {
                throw NomacError("the developer directory already has this tool", path: path)
            }
            try FileSystem.write(Data(contents.utf8), to: path)
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
            installation.filesCopied += 1
        }
        return installation
    }

    /// Throws when the developer directory's `clang.cfg` is not the one this nomac installs. One an
    /// earlier nomac installed compiles with another C++ ABI than the Swift compiles ask for, and
    /// neither then loads the other's modules ("version of Clang that we should attempt to be
    /// ABI-compatible with differs in precompiled file").
    public static func checkClangConfiguration(developerDirectory: String) throws {
        let path = developerDirectory + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang.cfg"
        guard let contents = FileManager.default.contents(atPath: path), contents != Data(clangConfiguration.utf8) else { return }
        throw NomacError("the toolchain's clang.cfg is not the one this nomac installs; install the toolchain again into a fresh 'nomac sdk install'", path: path)
    }

    /// The SHA-256 of the patches a build script wrote to `file` in the LLVM tools directory.
    static func builtStamp(_ file: String, in tools: String) -> String? {
        FileSystem.contents(atPath: tools + "/" + file).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// The toolchain files the LLVM tools directory's files of `group` replace, by name: all of them,
    /// or none when it has none of them.
    static func replacements(_ group: [String: String], in tools: String, source: String, writtenBy script: String) throws -> [String: String] {
        let present = group.keys.filter { FileSystem.isFile(tools + "/" + $0) }.sorted()
        let missing = group.keys.filter { !present.contains($0) }.sorted()
        guard present.isEmpty || missing.isEmpty else {
            throw NomacError("the LLVM tools directory has \(present.joined(separator: " and ")) but not \(missing.joined(separator: " and ")); \(script) writes both", path: tools)
        }
        return present.isEmpty ? [:] : try group.mapValues { try linkTarget(of: $0, in: source) }
    }

    /// The file `relative`, a path inside the toolchain's `usr`, ends at through its symbolic links.
    static func linkTarget(of relative: String, in usr: String) throws -> String {
        var path = relative
        for _ in 0..<8 {
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: usr + "/" + path) else { return path }
            path = (path as NSString).deletingLastPathComponent + "/" + target
        }
        throw NomacError("too many symbolic links", path: usr + "/" + relative)
    }

    /// A launcher that runs `executable` of the toolchain nomac was installed from.
    static func sourceLauncher(_ executable: String) -> String {
        let quoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "#!/bin/sh\n# Written by 'nomac toolchain install' (docs/formats/build.md \"SwiftPM in script phases\").\nexec \(quoted) \"$@\"\n"
    }

    /// The identification strings of Xcode's tools whose version Swift Build reads with
    /// `what -q`, which their launchers carry (docs/upstream/swift-build.md section 10).
    public static let whatIdentities = ["coremlc": XcodeProfile.current.coremlc.what]

    /// macOS's `/usr/bin/command`, the shell's built-in for programs that run it without a shell,
    /// which Ubuntu does not have: React Native's Podfile runs `` `command -v ccache` `` from Ruby
    /// ("No such file or directory - command" in `pod install`). It goes in the developer
    /// directory's `usr/bin`, with the launchers tools outside a build find on `PATH`.
    static let commandPath = "usr/bin/command"
    static let commandScript = """
        #!/bin/sh
        # Written by 'nomac toolchain install': macOS's /usr/bin/command, the shell's built-in.
        command "$@"

        """

    /// A launcher that runs `nomac <command>`, telling it the directory it was run from.
    static func launcher(command: String, nomacExecutable: String) -> String {
        let quoted = "'" + nomacExecutable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let identity = whatIdentities[command].map { "# @(#)\($0)\n" } ?? ""
        return """
            #!/bin/sh
            # Written by 'nomac toolchain install' (docs/adr/0102-linker.md).
            \(identity)NOMAC_TOOL_DIRECTORY=$(dirname "$0")
            export NOMAC_TOOL_DIRECTORY
            exec \(quoted) \(command) "$@"

            """
    }

    /// Copies `relative` from `source` into `destination`, under `target` when given.
    private static func copy(_ relative: String, from source: String, to destination: String, skipping skipped: Set<String>,
                             into installation: inout Installation, as target: String? = nil) throws {
        guard !skipped.contains(relative) else { return }
        let manager = FileManager.default
        let sourcePath = source + "/" + relative
        let destinationPath = destination + "/" + (target ?? relative)
        guard let attributes = try? manager.attributesOfItem(atPath: sourcePath) else { return }
        let type = attributes[.type] as? FileAttributeType
        if type == .typeDirectory {
            for name in try FileSystem.sortedContents(of: sourcePath) {
                try copy(relative + "/" + name, from: source, to: destination, skipping: skipped, into: &installation, as: target.map { $0 + "/" + name })
            }
            return
        }
        if type == .typeSymbolicLink {
            try FileSystem.createDirectory((destinationPath as NSString).deletingLastPathComponent)
            do {
                try manager.createSymbolicLink(atPath: destinationPath, withDestinationPath: manager.destinationOfSymbolicLink(atPath: sourcePath))
            } catch {
                throw NomacError("could not copy the toolchain file: \(error.localizedDescription)", path: sourcePath)
            }
            installation.filesCopied += 1
        } else {
            try copy(sourcePath, to: destinationPath, into: &installation)
        }
    }

    private static func copy(_ sourcePath: String, to destinationPath: String, into installation: inout Installation) throws {
        try FileSystem.createDirectory((destinationPath as NSString).deletingLastPathComponent)
        do {
            try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
        } catch {
            throw NomacError("could not copy the toolchain file: \(error.localizedDescription)", path: sourcePath)
        }
        installation.filesCopied += 1
    }
}
