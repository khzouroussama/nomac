import ArgumentParser
import Foundation
import NomacCore
import NomacNib
import NomacPlist

/// `nomac ibtool`: the subset of Xcode's `ibtool` that builds run, with its command line.
struct IBToolCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ibtool",
        abstract: "Compile iOS Interface Builder documents, as Xcode's ibtool does.",
        discussion: "Compiles .xib files into .nib files and .storyboard files into .storyboardc directories, and links those (docs/formats/nib.md).",
        shouldDisplay: false
    )

    @Flag(name: .customLong("errors")) var errors = false
    @Flag(name: .customLong("warnings")) var warnings = false
    @Flag(name: .customLong("notices")) var notices = false
    @Flag(name: .customLong("auto-activate-custom-fonts")) var autoActivateCustomFonts = false

    @Option(name: .customLong("module"), help: "The module of custom classes whose customModuleProvider is the target.")
    var module: String?

    @Option(name: .customLong("output-partial-info-plist"), help: "Where to write the Info.plist entries the document adds.")
    var partialInfoPlist: String?

    @Option(name: .customLong("target-device"), help: "iphone or ipad, once per device.")
    var targetDevices: [String] = []

    @Option(name: .customLong("minimum-deployment-target"), help: "Required to compile; Swift Build's --version probe has none.")
    var minimumDeploymentTarget: String?

    @Option(name: .customLong("output-format"), help: "human-readable-text, as builds use; xml1 with --version.")
    var outputFormat = "human-readable-text"

    @Flag(name: .customLong("version"), help: "Print the version of Xcode's ibtool nomac reproduces (Swift Build's probe, docs/adr/0102-linker.md).")
    var version = false

    @Option(name: .customLong("compile"), help: "The .nib to write.")
    var output: String?

    @Option(name: .customLong("compilation-directory"), help: "Where to write the .storyboardc of a storyboard.")
    var compilationDirectory: String?

    @Option(name: .customLong("link"), help: "Where to copy compiled .storyboardc directories.")
    var link: String?

    @Argument(help: "The .xib or .storyboard to compile, or the .storyboardc directories to link.")
    var inputs: [String] = []

    func run() throws {
        if version {
            guard outputFormat == "xml1" else {
                throw NomacError("--version is supported with --output-format xml1, as Swift Build asks (BACKLOG B-260)")
            }
            print(IBToolVersion.report, terminator: "")
            return
        }
        guard !inputs.isEmpty, [output, compilationDirectory, link].compactMap({ $0 }).count == 1, link != nil || inputs.count == 1 else {
            throw ValidationError("ibtool compiles a document: --compile <nib> <xib>, <storyboard> --compilation-directory <dir>, or --link <dir> <storyboardc>...")
        }
        guard outputFormat == "human-readable-text" else {
            throw NomacError("--output-format \(outputFormat) is not supported; builds use human-readable-text (BACKLOG B-263)")
        }
        let path = FileSystem.absolute(inputs[0])
        do {
            if let link {
                for input in inputs {
                    try Self.link(FileSystem.absolute(input), into: FileSystem.absolute(link))
                }
                return
            }
            guard let minimumDeploymentTarget else {
                throw NomacError("nomac does not compile nibs without --minimum-deployment-target yet (BACKLOG B-263)", path: path)
            }
            guard let data = FileManager.default.contents(atPath: path) else {
                throw NomacError("Interface Builder could not open the document \((path as NSString).lastPathComponent)\" because it does not exist.", path: path)
            }
            let options = XIBCompiler.Options(module: module, minimumDeploymentTarget: minimumDeploymentTarget, targetDevices: targetDevices)
            if let compilationDirectory {
                let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension + ".storyboardc"
                let directory = (FileSystem.absolute(compilationDirectory) as NSString).appendingPathComponent(name)
                let compiled = try StoryboardCompiler.compileReportingWarnings(data, path: path, options: options)
                for (file, contents) in compiled.files {
                    try FileSystem.write(contents, to: (directory as NSString).appendingPathComponent(file))
                }
                if !compiled.warnings.isEmpty {
                    print("/* com.apple.ibtool.document.warnings */")
                    compiled.warnings.forEach { print($0) }
                }
            } else if let output {
                try FileSystem.write(try XIBCompiler.compile(data, path: path, options: options), to: FileSystem.absolute(output))
            }
            if let partialInfoPlist {
                let fonts = try XIBCompiler.customFontFiles(data, path: path)
                let entries: [String: PropertyListValue] = fonts.isEmpty ? [:] : ["UIAppFonts": .array(fonts.map(PropertyListValue.string))]
                try FileSystem.write(XMLPropertyList.data(.dictionary(entries)), to: FileSystem.absolute(partialInfoPlist))
            }
        } catch let error as NomacError {
            print("/* com.apple.ibtool.errors */")
            print("\(error.path ?? path): error: \(error.message)")
            throw ExitCode.failure
        }
    }

    /// `--link`: each compiled storyboard copied as it is (nib-experiments `storyboard`, `sb-*`),
    /// into the directory's folder of the same name when it is in an `.lproj` folder, else into the
    /// directory (Xcode's ibtool linking retro-rampage's storyboards from `Base.lproj`, `fr.lproj`
    /// and a plain folder in one call, as LinkStoryboards links all of a target's).
    static func link(_ storyboard: String, into directory: String) throws {
        let parent = (storyboard as NSString).deletingLastPathComponent
        let folder = (parent as NSString).pathExtension == "lproj" ? (directory as NSString).appendingPathComponent((parent as NSString).lastPathComponent) : directory
        let destination = (folder as NSString).appendingPathComponent((storyboard as NSString).lastPathComponent)
        let manager = FileManager.default
        guard manager.fileExists(atPath: storyboard) else {
            throw NomacError("nomac does not reproduce ibtool's message for linking a storyboard that does not exist (BACKLOG B-261)", path: storyboard)
        }
        try manager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination) {
            try manager.removeItem(atPath: destination)
        }
        try manager.copyItem(atPath: storyboard, toPath: destination)
    }
}
