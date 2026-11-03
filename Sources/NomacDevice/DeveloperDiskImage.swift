import Foundation
import NomacCore
import NomacSigning

/// An `iOS_DDI` folder of the user's Xcode: `Restore/BuildManifest.plist`, the personalized disk
/// images and their trust caches (docs/formats/ddi.md).
public struct DeveloperDiskImage {
    public let directory: String
    public let manifest: [String: PropertyListValue]

    public static let optionHelp = "The iOS_DDI folder of your Xcode (default: the one 'nomac sdk install' extracted, else \(macOSDirectory) on a Mac)."

    /// The folder on a Mac where Xcode installs the image.
    public static let macOSDirectory = "/Library/Developer/DeveloperDiskImages/iOS_DDI"

    /// The image in `directory` when given, else the one Xcode installed on this Mac.
    public static func locate(_ directory: String?) throws -> DeveloperDiskImage {
        if let directory { return try DeveloperDiskImage(directory: directory) }
        guard FileSystem.exists(macOSDirectory + "/Restore/BuildManifest.plist") else {
            throw NomacError("no Developer Disk Image to mount", notes: [
                "'nomac sdk install' extracts it from your Xcode when 7z and xz are installed (docs/formats/ddi.md)",
                "or pass --ddi with the iOS_DDI folder of your Xcode",
            ])
        }
        return try DeveloperDiskImage(directory: macOSDirectory)
    }

    public init(directory: String) throws {
        let path = directory + "/Restore/BuildManifest.plist"
        guard let data = FileSystem.contents(atPath: path) else {
            throw NomacError("no Developer Disk Image here", path: directory, notes: ["an iOS_DDI folder holds Restore/BuildManifest.plist"])
        }
        guard case .dictionary(let manifest) = try PropertyListValue.parseXML(data, path: path) else { throw NomacError("the build manifest is not a dictionary", path: path) }
        self.directory = directory
        self.manifest = manifest
    }

    /// The image and trust cache a build identity names.
    public func files(identity: [String: PropertyListValue]) throws -> (image: [UInt8], trustCache: [UInt8]) {
        let paths = try Personalization.paths(identity: identity)
        func read(_ relative: String) throws -> [UInt8] {
            let path = directory + "/Restore/" + relative
            guard let data = FileSystem.contents(atPath: path) else { throw NomacError("cannot read the Developer Disk Image's file", path: path) }
            return [UInt8](data)
        }
        return (try read(paths.image), try read(paths.trustCache))
    }
}
