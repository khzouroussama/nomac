import Foundation
import NomacCore

/// Xcode's `copypng`, which copies a bundle's loose PNGs (`COMPRESS_PNG_FILES`,
/// `STRIP_PNG_TEXT`): without options the file as it is; with `-compress` or `-strip-PNG-text`
/// the icon PNG actool would write (CgBI for RGB and RGBA, plain for gray), `-strip-PNG-text`
/// leaving out the text chunks; other options are ignored with a warning (experiment `copypng`).
public enum CopyPNG {
    public static func run(arguments: [String]) throws {
        var options: Set<String> = []
        var files: [String] = []
        for argument in arguments {
            if ["-compress", "-strip-PNG-text"].contains(argument) {
                options.insert(argument)
            } else if argument.hasPrefix("-") {
                // copypng's own words, on standard output without a line end.
                FileHandle.standardOutput.write(Data("WARNING: Ignoring unknown option \(argument)".utf8))
            } else {
                files.append(argument)
            }
        }
        guard files.count == 2 else { throw NomacError("usage: copypng [-compress] [-strip-PNG-text] <input> <output>") }
        guard let data = FileManager.default.contents(atPath: files[0]) else { throw NomacError("Can't find \(files[0])", path: files[0]) }
        let output = options.isEmpty ? [UInt8](data) : try compressed([UInt8](data), stripText: options.contains("-strip-PNG-text"), path: files[0])
        try FileSystem.write(Data(output), to: FileSystem.absolute(files[1]))
    }

    static func compressed(_ data: [UInt8], stripText: Bool, path: String) throws -> [UInt8] {
        var image = try PNGImage(data: data, path: path)
        if stripText { image.ancillaryChunks.removeAll { ["tEXt", "iTXt", "zTXt"].contains($0.type) } }
        return try IconPNG.data(image, path: path, smallestWindow: true)
    }
}
