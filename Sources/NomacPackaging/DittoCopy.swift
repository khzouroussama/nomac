import Foundation
import NomacCore

/// `ditto <source> <destination>`: a copy as macOS's ditto makes it (`.github/scripts/ditto_experiments.py`,
/// docs/formats/build.md "ditto"). Script phases call it; CocoaPods' "Copy generated compatibility
/// header" phases copy a pod's `-Swift.h` and module map with it.
///
/// - Missing folders above the destination are created.
/// - A file is copied onto the destination path, replacing a file there, or into the destination
///   when it is a folder; its permission bits and modification time are kept.
/// - A folder's contents are merged into the destination folder, created when missing; symbolic
///   links inside it are copied as links.
/// - A source that is a symbolic link is followed.
/// - Names keep their bytes: a precomposed name stays precomposed, as with macOS's ditto, where
///   Foundation on macOS would decompose the names of what it creates.
public enum DittoCopy {
    public static func copy(_ source: String, to destination: String) throws {
        let source = FileSystem.resolvingSymbolicLinks(source)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source, isDirectory: &isDirectory) else {
            throw NomacError("no such file or directory", path: source)
        }
        if isDirectory.boolValue {
            try copyFolder(source, to: destination)
        } else {
            var target = destination
            var destinationIsDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: destination, isDirectory: &destinationIsDirectory), destinationIsDirectory.boolValue {
                target = destination + "/" + (source as NSString).lastPathComponent
            }
            try copyFile(source, to: target)
        }
    }

    private static func copyFolder(_ source: String, to destination: String) throws {
        try FileSystem.createDirectory((destination as NSString).deletingLastPathComponent)
        try FileSystem.createDirectoryExactly(destination)
        try keepAttributes(of: source, on: destination, modificationDate: false)
        for name in try FileSystem.sortedContents(of: source) {
            let item = source + "/" + name
            let target = destination + "/" + name
            let attributes = try FileManager.default.attributesOfItem(atPath: item)
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink:
                if FileManager.default.fileExists(atPath: target) || (try? FileManager.default.destinationOfSymbolicLink(atPath: target)) != nil {
                    try FileManager.default.removeItem(atPath: target)
                }
                try FileSystem.createSymbolicLinkExactly(target, to: FileManager.default.destinationOfSymbolicLink(atPath: item))
            case .typeDirectory:
                try copyFolder(item, to: target)
            default:
                try copyFile(item, to: target)
            }
        }
    }

    private static func copyFile(_ source: String, to destination: String) throws {
        try FileManager.default.createDirectory(atPath: (destination as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination) {
            try FileManager.default.removeItem(atPath: destination)
        }
        guard let data = FileManager.default.contents(atPath: source) else { throw NomacError("could not read file", path: source) }
        try FileSystem.writeExactly([UInt8](data), to: destination)
        try keepAttributes(of: source, on: destination, modificationDate: true)
    }

    private static func keepAttributes(of source: String, on destination: String, modificationDate: Bool) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: source)
        var kept: [FileAttributeKey: Any] = [:]
        if let permissions = attributes[.posixPermissions] as? NSNumber {
            kept[.posixPermissions] = NSNumber(value: permissions.intValue & 0o7777)
        }
        if modificationDate, let date = attributes[.modificationDate] {
            kept[.modificationDate] = date
        }
        try FileManager.default.setAttributes(kept, ofItemAtPath: destination)
    }
}
