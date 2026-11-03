import Crypto
import Foundation
import NomacCore
import NomacSigning

/// `com.apple.mobile.mobile_image_mounter`, which reports and mounts disk images
/// (docs/formats/lockdown.md). nomac asks which images are mounted: `CopyDevices`, whose
/// `EntryList` names each image's `DiskImageType` (pymobiledevice3 found it listing a mounted
/// personalized image on iOS 27.0 where `LookupImage` gave an empty signature).
public enum MobileImageMounter {
    public static let serviceName = "com.apple.mobile.mobile_image_mounter"

    public static func mountedImageTypes(on stream: ByteStream) throws -> [String] {
        try entries(on: stream).compactMap { fields in
            guard fields["IsMounted"] != .boolean(false), case .string(let type)? = fields["DiskImageType"] else { return nil }
            return type
        }
    }

    /// `CopyDevices`' entries, one dictionary per mounted image.
    public static func entries(on stream: ByteStream) throws -> [[String: PropertyListValue]] {
        try PropertyListMessages.send(["Command": .string("CopyDevices")], on: stream)
        let reply = try PropertyListMessages.receive(from: stream, source: "mobile_image_mounter")
        if case .string(let error)? = reply["Error"] { throw NomacError("mobile_image_mounter refused CopyDevices: \(error)") }
        guard case .array(let entries)? = reply["EntryList"] else { throw NomacError("mobile_image_mounter's CopyDevices reply has no EntryList") }
        return entries.compactMap { if case .dictionary(let fields) = $0 { fields } else { nil } }
    }

    /// The personalization manifest (an IM4M) the device stores for the personalized image with
    /// these bytes, found by their SHA-384 (`QueryPersonalizationManifest`, as pymobiledevice3
    /// asks before requesting one from Apple); nil when it has none, after which the device closes
    /// the connection.
    public static func storedManifest(forImage image: [UInt8], on stream: ByteStream) throws -> [UInt8]? {
        try PropertyListMessages.send([
            "Command": .string("QueryPersonalizationManifest"),
            "PersonalizedImageType": .string("DeveloperDiskImage"),
            "ImageType": .string("DeveloperDiskImage"),
            "ImageSignature": .data(Array(SHA384.hash(data: image))),
        ], on: stream)
        let reply = try PropertyListMessages.receive(from: stream, source: "mobile_image_mounter")
        if case .data(let manifest)? = reply["ImageSignature"] { return manifest }
        return nil
    }

    /// The identifiers a personalization request names the device by
    /// (`QueryPersonalizationIdentifiers`): its board, chip, ECID and security settings.
    public static func personalizationIdentifiers(on stream: ByteStream) throws -> [String: PropertyListValue] {
        try PropertyListMessages.send([
            "Command": .string("QueryPersonalizationIdentifiers"),
            "PersonalizedImageType": .string("DeveloperDiskImage"),
        ], on: stream)
        let reply = try PropertyListMessages.receive(from: stream, source: "mobile_image_mounter")
        if case .string(let error)? = reply["Error"] { throw NomacError("mobile_image_mounter refused QueryPersonalizationIdentifiers: \(error)") }
        guard case .dictionary(let identifiers)? = reply["PersonalizationIdentifiers"] else {
            throw NomacError("mobile_image_mounter's QueryPersonalizationIdentifiers reply has no PersonalizationIdentifiers")
        }
        return identifiers
    }

    /// The nonce a personalization request signs (`QueryNonce`).
    public static func nonce(on stream: ByteStream) throws -> [UInt8] {
        let reply = try exchange(["Command": .string("QueryNonce"), "PersonalizedImageType": .string("DeveloperDiskImage")], on: stream)
        guard case .data(let nonce)? = reply["PersonalizationNonce"] else { throw NomacError("mobile_image_mounter's QueryNonce reply has no PersonalizationNonce") }
        return nonce
    }

    /// Uploads a personalized image with its ticket: `ReceiveBytes`, acknowledged with
    /// `ReceiveBytesAck`, then the image's bytes, acknowledged with `Complete`.
    public static func upload(image: [UInt8], ticket: [UInt8], on stream: ByteStream) throws {
        let reply = try exchange(["Command": .string("ReceiveBytes"), "ImageType": .string("Personalized"),
                                  "ImageSize": .integer(Int64(image.count)), "ImageSignature": .data(ticket)], on: stream)
        guard reply["Status"] == .string("ReceiveBytesAck") else { throw NomacError("mobile_image_mounter did not accept the upload: \(reply)") }
        try stream.write(image)
        let done = try PropertyListMessages.receive(from: stream, source: "mobile_image_mounter")
        guard done["Status"] == .string("Complete") else { throw failure(done, "the image upload") }
    }

    /// Mounts the uploaded personalized image with its ticket and trust cache (`MountImage`).
    public static func mount(ticket: [UInt8], trustCache: [UInt8], on stream: ByteStream) throws {
        let reply = try exchange(["Command": .string("MountImage"), "ImageType": .string("Personalized"),
                                  "ImageSignature": .data(ticket), "ImageTrustCache": .data(trustCache)], on: stream)
        guard reply["Status"] == .string("Complete") else { throw failure(reply, "MountImage") }
    }

    /// Unmounts the image mounted at `mountPath` (`UnmountImage`; the Developer Disk Image's is
    /// `/System/Developer`).
    public static func unmount(mountPath: String, on stream: ByteStream) throws {
        let reply = try exchange(["Command": .string("UnmountImage"), "MountPath": .string(mountPath)], on: stream)
        guard reply["Status"] == .string("Complete") else { throw failure(reply, "UnmountImage") }
    }

    static func exchange(_ request: [String: PropertyListValue], on stream: ByteStream) throws -> [String: PropertyListValue] {
        try PropertyListMessages.send(request, on: stream)
        let reply = try PropertyListMessages.receive(from: stream, source: "mobile_image_mounter")
        if reply["Error"] != nil {
            let command = if case .string(let name)? = request["Command"] { name } else { "a request" }
            throw failure(reply, command)
        }
        return reply
    }

    static func failure(_ reply: [String: PropertyListValue], _ request: String) -> NomacError {
        let text = { (key: String) -> String? in if case .string(let value)? = reply[key] { value } else { nil } }
        return NomacError("mobile_image_mounter refused \(request): " + ([text("Error"), text("DetailedError"), text("Status")].compactMap { $0 }.joined(separator: "; ")))
    }
}
