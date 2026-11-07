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
        guard !options.isEmpty else {
            try FileSystem.write(data, to: FileSystem.absolute(files[1]))
            return
        }
        if let reason = unreadable([UInt8](data)) {
            // pngcrush's words, with no file and status 0 (`copypng` damaged cases).
            FileHandle.standardOutput.write(Data("\nWhile reading \(files[0]) pngcrush caught libpng error:\n   \(reason)\n\nCould not find file: \(files[1])\n".utf8))
            return
        }
        if let warning = PNGImage.copiedAsIs([UInt8](data)) {
            // Other depths and APNGs are copied, saying so on standard error (`copypng` forms).
            FileHandle.standardError.write(Data("libpng warning: \(warning)\n".utf8))
            try FileSystem.write(data, to: FileSystem.absolute(files[1]))
            return
        }
        guard let output = try compressed([UInt8](data), stripText: options.contains("-strip-PNG-text"), path: files[0]) else {
            FileHandle.standardOutput.write(Data("\nWhile reading \(files[0]) pngcrush caught libpng error:\n   \n\nCould not find file: \(files[1])\n".utf8))
            return
        }
        try FileSystem.write(Data(output), to: FileSystem.absolute(files[1]))
    }

    /// Why libpng does not read a file: too short, cut before `IEND`, or not a PNG.
    static func unreadable(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 8 else { return "Read Error" }
        guard bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { return "Not a PNG file.." }
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            if bytes[offset + 4..<offset + 8].elementsEqual(Array("IEND".utf8)) { return nil }
            offset += 12 + length
        }
        return "Read Error"
    }

    static func compressed(_ data: [UInt8], stripText: Bool, path: String) throws -> [UInt8]? {
        var image = try PNGImage(data: data, path: path, colorManaged: false)
        if image.iconIsUnwritable { return nil }
        if stripText { image.ancillaryChunks.removeAll { ["tEXt", "iTXt", "zTXt"].contains($0.type) } }
        return try IconPNG.data(image, path: path, smallestWindow: true)
    }
}
