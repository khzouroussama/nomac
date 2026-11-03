import ArgumentParser
import Foundation
import NomacCore
import NomacSDK

/// `nomac sdk`: manage the Xcode subsets nomac builds with.
struct SDKCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sdk",
        abstract: "Install and select your Xcode's SDKs.",
        discussion: """
        nomac never downloads Xcode. Install from your own Xcode.xip (downloaded from \
        developer.apple.com) or from an installed Xcode.app. Installed files live in \
        $NOMAC_HOME/xcode (default ~/.nomac/xcode) and are never modified.
        """,
        subcommands: [Install.self, Link.self, List.self, Select.self, Path.self, Remove.self, Profile.self]
    )

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Copy the files nomac needs from an Xcode.xip or Xcode.app.")

        @Argument(help: "An Xcode .xip archive or an Xcode .app directory.")
        var source: String

        @Option(name: .customLong("platform"), help: "A platform whose SDK to copy in full (repeatable). Platform metadata is always copied for every platform.")
        var platforms: [String] = XcodeSubset.defaultPayloadPlatforms.sorted()

        @Flag(help: "Make this the default Xcode.")
        var select = false

        @Flag(name: .customLong("strict-xcode"), help: XcodeCheck.strictHelp)
        var strictXcode = false

        func run() throws {
            let store = SDKStore.default()
            let subset = XcodeSubset(payloadPlatforms: Set(platforms))
            let accept = { (version: XcodeVersionInfo) in try XcodeCheck.version(version, at: source, strict: strictXcode) }
            let progress: (String) -> Void = { print($0) }
            let entry: SDKStore.Entry
            if FileSystem.isDirectory(source) {
                entry = try store.install(app: source, subset: subset, accept: accept, progress: progress)
            } else {
                guard let unxip = ExternalTools.unxip.locate() else {
                    throw NomacError("installing from a .xip needs the 'unxip' tool, which was not found",
                                     notes: ["install it with: \(ExternalTools.unxip.installation)",
                                             "or point \(ExternalTools.unxip.overrideVariable) at it"])
                }
                entry = try store.install(xip: source, subset: subset, unxip: unxip, accept: accept, progress: progress)
            }
            if select || store.selectedBuild() == nil {
                try store.select(build: entry.version.build)
            }
            print("Installed Xcode \(entry.version.version) (\(entry.version.build)) at \(entry.appPath)")
        }
    }

    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Use an installed Xcode.app in place, without copying it.")

        @Argument(help: "An Xcode .app directory.")
        var app: String

        @Flag(help: "Make this the default Xcode.")
        var select = false

        @Flag(name: .customLong("strict-xcode"), help: XcodeCheck.strictHelp)
        var strictXcode = false

        func run() throws {
            let store = SDKStore.default()
            let entry = try store.link(app: app) { try XcodeCheck.version($0, at: app, strict: strictXcode) }
            if select || store.selectedBuild() == nil {
                try store.select(build: entry.version.build)
            }
            print("Linked Xcode \(entry.version.version) (\(entry.version.build)) at \(entry.appPath)")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed Xcode builds.")

        func run() throws {
            let store = SDKStore.default()
            let selected = store.selectedBuild()
            let entries = try store.entries()
            if entries.isEmpty {
                print("No Xcode is installed. Run 'nomac sdk install <Xcode.xip | Xcode.app>'.")
                return
            }
            for entry in entries {
                let marker = entry.version.build == selected ? "*" : " "
                let platforms = entry.kind == "link" ? "linked: \(entry.source)" : "platforms: \(entry.payloadPlatforms.joined(separator: ", "))"
                print("\(marker) \(entry.version.build)  Xcode \(entry.version.version)  (\(platforms))")
            }
        }
    }

    struct Select: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Choose the default Xcode build.")

        @Argument(help: "A product build version from 'nomac sdk list', for example \(XcodeProfile.current.xcode.build).")
        var build: String

        func run() throws {
            try SDKStore.default().select(build: build)
            print("Selected Xcode \(build)")
        }
    }

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the developer directory of an installed Xcode.")

        @Option(help: "A product build version; default: the selected Xcode.")
        var build: String?

        func run() throws {
            print(try SDKStore.default().resolve(build: build).developerDirectory)
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete an installed Xcode build from the nomac store.")

        @Argument(help: "A product build version from 'nomac sdk list'.")
        var build: String

        func run() throws {
            try SDKStore.default().remove(build: build)
            print("Removed Xcode \(build)")
        }
    }

    struct Profile: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the Xcode this nomac reproduces and every value nomac takes from it, as JSON.",
            discussion: "The profile of docs/adr/0012-one-xcode-per-release.md, which .github/scripts/xcode_upgrade.py compares with a new Xcode.")

        func run() throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(XcodeProfile.current), as: UTF8.self))
        }
    }
}
