import ArgumentParser
import Foundation
import NomacCore
import NomacPackaging

/// `nomac symbols`: the `Symbols/<UUID>.symbols` files of an app-store-connect export.
struct SymbolsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "symbols",
        abstract: "Write the .symbols file 'xcodebuild -exportArchive' writes for each DWARF file of a dSYM.",
        discussion: """
        Writes <output>/<UUID>.symbols for every file in the dSYM's Contents/Resources/DWARF, one \
        per slice of a universal file, as an app-store-connect export does \
        (docs/formats/symbols.md). The file records the DWARF file's absolute path and \
        modification time.
        """,
        shouldDisplay: false
    )

    @Argument(help: "A .dSYM bundle, or one DWARF file.")
    var dsym: String

    @Option(name: .shortAndLong, help: "The folder to write the .symbols files to.")
    var output: String

    func run() throws {
        // The file records the path as given, made absolute but not standardized (`/private/tmp`
        // stays as it is), as the export records the archive's.
        let path = dsym.hasPrefix("/") ? dsym : FileManager.default.currentDirectoryPath + "/" + dsym
        let dwarfFolder = path + "/Contents/Resources/DWARF"
        let files = FileSystem.isDirectory(path) ? try FileSystem.sortedContents(of: dwarfFolder).map { dwarfFolder + "/" + $0 } : [path]
        let destination = FileSystem.absolute(output)
        try FileSystem.createDirectory(destination)
        for file in files {
            for symbols in try SymbolsFile.files(dwarfFile: file) {
                try FileSystem.write(Data(symbols.bytes), to: destination + "/" + symbols.name)
            }
        }
    }
}
