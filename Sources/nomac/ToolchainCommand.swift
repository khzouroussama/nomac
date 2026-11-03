import ArgumentParser
import Foundation
import NomacBuild
import NomacCore
import NomacMacros

/// `nomac toolchain`: the compilers and tools nomac builds with on Linux.
struct ToolchainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "toolchain",
        abstract: "Install the Swift toolchain nomac builds with.",
        subcommands: [Install.self]
    )

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Copy a swift.org toolchain's executables into the developer directory's XcodeDefault toolchain.",
            discussion: """
            The toolchain is the 'usr' directory of a swift.org release for this machine, of the \
            Swift version the developer directory's Xcode ships (docs/adr/0100-linux-toolchain.md), \
            into a developer directory without a Swift compiler, such as a 'nomac sdk install'. \
            nomac's macro plugins, which replace Apple's, are compiled with it into the platforms' \
            plugin directories (docs/adr/0150-macro-plugins.md).
            """
        )

        @Argument(help: "The toolchain's usr directory (for example \(XcodeProfile.current.pins.swiftToolchainTag)-ubuntu24.04-aarch64/usr; default: the one a release download keeps beside nomac).")
        var toolchain: String?

        @Option(name: .customLong("llvm-tools"), help: "The directory .github/scripts/build-llvm-tools.sh wrote lld and dsymutil to (docs/adr/0102-linker.md), and clang and libclang with CLANG=1, which then replace the toolchain's (docs/adr/0170-xcodes-clang-abi-and-a-patched-clang.md); default: the tools a release download keeps beside nomac.")
        var llvmTools: String?

        @Option(name: [.customLong("developer-dir")], help: "An Xcode Contents/Developer directory (default: $NOMAC_DEVELOPER_DIR, else the selected 'nomac sdk' install).")
        var developerDir: String?
        @Flag(name: .customLong("strict-xcode"), help: XcodeCheck.strictHelp)
        var strictXcode = false

        func run() throws {
            let nomac = FileSystem.resolvingSymbolicLinks(Bundle.main.executablePath ?? CommandLine.arguments[0])
            let bundled = LinuxToolchain.bundled(nomacExecutable: nomac)
            guard let toolchain = toolchain ?? bundled.toolchain, let llvmTools = llvmTools ?? bundled.llvmTools else {
                throw ValidationError("give the swift.org toolchain's usr directory and --llvm-tools, which nomac's release download keeps beside it (docs/INSTALL.md)")
            }
            let developer = try DeveloperDirectory.resolve(option: developerDir, strictXcode: strictXcode)
            let installation = try LinuxToolchain.install(toolchain: toolchain, llvmTools: llvmTools, nomacExecutable: nomac, developerDirectory: developer)
            let patched = (installation.patchedClang ? ["clang and libclang"] : []) + (installation.patchedSwiftFrontend ? ["swift-frontend and dependency scanner"] : [])
            print("Installed \(installation.filesCopied) files in \(installation.destination)" + (patched.isEmpty ? "" : ", with the patched " + patched.joined(separator: " and the patched ")))
            let interposer = try ExecInterposer.install(clang: installation.destination + "/bin/clang", developerDirectory: developer)
            print("Installed \(interposer)")
            print("Built \(try HostFoundationModule.install(toolchain: toolchain, developerDirectory: developer))")
            let plugins = try MacroPlugins.install(toolchain: toolchain, developerDirectory: developer)
            for directory in plugins.pluginDirectories {
                print("Installed the macro plugins \(plugins.modules.joined(separator: ", ")) in \(directory)")
            }
        }
    }
}
