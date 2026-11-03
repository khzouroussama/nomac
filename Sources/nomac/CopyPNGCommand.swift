import ArgumentParser
import NomacAssets

/// `nomac copypng`: copy a PNG into a bundle as Xcode's copypng does.
struct CopyPNGCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copypng",
        abstract: "Copy a PNG as Xcode's copypng does.",
        discussion: "Takes copypng's own arguments: [-compress] [-strip-PNG-text] <input> <output>.",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "copypng's arguments.")
    var arguments: [String] = []

    func run() throws {
        try CopyPNG.run(arguments: arguments)
    }
}
