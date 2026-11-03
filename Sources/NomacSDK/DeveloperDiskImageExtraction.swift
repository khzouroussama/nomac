import Foundation
import NomacCore

/// The iOS Developer Disk Image of a user's Xcode, extracted from
/// `Contents/Resources/Packages/XcodeSystemResources.pkg` into an `iOS_DDI` folder like the one
/// Xcode installs on a Mac (docs/formats/ddi.md, ADR 0403): 7-Zip reads the package (xar), the
/// payload's cpio archive and the UDIF image of an HFS+ volume; the payload is pbzx, whose xz
/// chunks `xz` expands and whose other chunks are stored.
public enum DeveloperDiskImageExtraction {
    public static let package = "Contents/Resources/Packages/XcodeSystemResources.pkg"
    static let image = "iOS_DDI.dmg"

    /// Extracts the image of the Xcode at `app` into `destination`.
    public static func extract(app: String, to destination: String, sevenZip: String, xz: String) throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-ddi-\(UUID().uuidString)").path
        try FileSystem.createDirectory(work)
        defer { try? FileManager.default.removeItem(atPath: work) }
        try run(sevenZip, ["x", "-txar", "-y", "-o" + work, app + "/" + package, "Payload"])
        try pbzx(work + "/Payload", to: work + "/payload.cpio", xz: xz, work: work)
        try run(sevenZip, ["x", "-tcpio", "-y", "-o" + work + "/cpio", work + "/payload.cpio", "-ir!" + image])
        guard let dmg = FileManager.default.enumerator(atPath: work + "/cpio")?.compactMap({ $0 as? String }).first(where: { $0.hasSuffix("/" + image) }) else {
            throw NomacError("Xcode's \(package) holds no \(image)", path: app)
        }
        try run(sevenZip, ["x", "-y", "-o" + work + "/volume", work + "/cpio/" + dmg])
        guard let volume = try FileSystem.sortedContents(of: work + "/volume").first(where: { FileSystem.exists(work + "/volume/" + $0 + "/Restore/BuildManifest.plist") }) else {
            throw NomacError("the \(image) of Xcode's \(package) has no Restore/BuildManifest.plist", path: app)
        }
        try FileSystem.createDirectory(destination)
        for name in ["Restore", "version.plist"] {
            try FileManager.default.moveItem(atPath: work + "/volume/" + volume + "/" + name, toPath: destination + "/" + name)
        }
    }

    /// pbzx: `pbzx`, an 8-byte chunk size, then chunks of an 8-byte uncompressed and an 8-byte
    /// stored length (big-endian) and the stored bytes: an xz stream, or the bytes themselves
    /// (Xcode 27.0's package has both).
    static func pbzx(_ path: String, to output: String, xz: String, work: String) throws {
        guard let data = FileManager.default.contents(atPath: path), data.starts(with: Array("pbzx".utf8)) else {
            throw NomacError("not a pbzx stream", path: path)
        }
        let bytes = [UInt8](data)
        guard FileManager.default.createFile(atPath: output, contents: nil), let handle = FileHandle(forWritingAtPath: output) else {
            throw NomacError("cannot write", path: output)
        }
        defer { try? handle.close() }
        func number(_ offset: Int) -> Int { bytes[offset..<offset + 8].reduce(0) { $0 << 8 | Int($1) } }
        var offset = 12
        while offset + 16 <= bytes.count {
            let uncompressed = number(offset), stored = number(offset + 8)
            offset += 16
            guard offset + stored <= bytes.count else { throw NomacError("a pbzx chunk runs past the end", path: path) }
            let chunk = Array(bytes[offset..<offset + stored])
            offset += stored
            if !chunk.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
                try handle.write(contentsOf: chunk)
                continue
            }
            try FileSystem.write(Data(chunk), to: work + "/chunk.xz")
            let result = try Subprocess.run(xz, ["-dc", work + "/chunk.xz"])
            guard result.exitStatus == 0, result.standardOutput.count == uncompressed else {
                throw NomacError("xz could not expand a pbzx chunk", path: path, notes: [result.errorString])
            }
            try handle.write(contentsOf: result.standardOutput)
        }
    }

    static func run(_ tool: String, _ arguments: [String]) throws {
        let result = try Subprocess.run(tool, arguments)
        guard result.exitStatus == 0 else {
            throw NomacError("\((tool as NSString).lastPathComponent) failed with exit status \(result.exitStatus)", notes: [result.errorString + result.outputString].filter { !$0.isEmpty })
        }
    }
}
