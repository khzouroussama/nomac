import CZlib
import Foundation
import NomacCore

/// What a build upload needs from an IPA: the app's `Info.plist` (`Payload/<name>.app/Info.plist`)
/// read from the zip without extracting it, and the file's name and size.
public struct IPAInfo {
    public var fileName: String
    public var fileSize: Int64
    public var bundleIdentifier: String
    public var shortVersion: String
    public var version: String
    /// The API's `Platform`, from the app's `CFBundleSupportedPlatforms`.
    public var platform: String

    /// The API's platforms of an IPA's app by its `CFBundleSupportedPlatforms` name, lowercased (`iPhoneOS`,
    /// `AppleTVOS`, `XROS`); macOS apps are uploaded
    /// as packages, not IPAs.
    static let platforms = ["iphoneos": "IOS", "appletvos": "TV_OS", "xros": "VISION_OS"]

    public init(path: String) throws {
        guard let handle = FileHandle(forReadingAtPath: path) else { throw NomacError("cannot read the IPA", path: path) }
        defer { try? handle.close() }
        let size = Int64(try handle.seekToEnd())
        let plistData = try Self.appInfoPlist(handle, size: size, path: path)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw NomacError("the app's Info.plist is not a dictionary", path: path)
        }
        func string(_ key: String) throws -> String {
            guard let value = plist[key] as? String, !value.isEmpty else { throw NomacError("the app's Info.plist has no \(key)", path: path) }
            return value
        }
        let platformName = (plist["CFBundleSupportedPlatforms"] as? [String])?.first ?? ""
        guard let platform = Self.platforms[platformName.lowercased()] else {
            throw NomacError("the app's platform \"\(platformName)\" is not one App Store Connect takes as an IPA", path: path)
        }
        fileName = (path as NSString).lastPathComponent
        fileSize = size
        bundleIdentifier = try string("CFBundleIdentifier")
        shortVersion = try string("CFBundleShortVersionString")
        version = try string("CFBundleVersion")
        self.platform = platform
    }

    static func appInfoPlist(_ handle: FileHandle, size: Int64, path: String) throws -> Data {
        func read(_ offset: Int64, _ count: Int) throws -> [UInt8] {
            try handle.seek(toOffset: UInt64(offset))
            let bytes = [UInt8](try handle.read(upToCount: count) ?? Data())
            guard bytes.count == count else { throw NomacError("truncated zip archive", path: path) }
            return bytes
        }
        func u16(_ bytes: [UInt8], _ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ bytes: [UInt8], _ at: Int) -> Int { u16(bytes, at) | u16(bytes, at + 2) << 16 }

        let tailStart = max(0, size - 22 - 0xffff)
        let tail = try read(tailStart, Int(size - tailStart))
        guard tail.count >= 22, let end = (0...(tail.count - 22)).reversed().first(where: { tail[$0..<($0 + 4)].elementsEqual([0x50, 0x4b, 0x05, 0x06]) }) else {
            throw NomacError("not a zip archive", path: path)
        }
        let count = u16(tail, end + 10), directorySize = u32(tail, end + 12), directoryOffset = u32(tail, end + 16)
        guard count != 0xffff, directoryOffset != 0xffff_ffff else {
            throw NomacError("Zip64 IPAs are not supported yet (BACKLOG B-306)", path: path)
        }
        let directory = try read(Int64(directoryOffset), directorySize)
        var at = 0
        for _ in 0..<count {
            guard at + 46 <= directory.count, u32(directory, at) == 0x0201_4b50 else { throw NomacError("malformed central directory", path: path) }
            let method = u16(directory, at + 10), compressedSize = u32(directory, at + 20), uncompressedSize = u32(directory, at + 24)
            let nameLength = u16(directory, at + 28), extraLength = u16(directory, at + 30), commentLength = u16(directory, at + 32)
            let local = u32(directory, at + 42)
            let name = String(decoding: directory[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
            at += 46 + nameLength + extraLength + commentLength
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 3, components[0] == "Payload", components[1].hasSuffix(".app"), components[2] == "Info.plist" else { continue }
            let header = try read(Int64(local), 30)
            let start = Int64(local) + 30 + Int64(u16(header, 26)) + Int64(u16(header, 28))
            let stored = try read(start, compressedSize)
            switch method {
            case 0: return Data(stored)
            case 8: return Data(try inflate(stored, size: uncompressedSize, path: path))
            default: throw NomacError("\(name) uses compression method \(method)", path: path)
            }
        }
        throw NomacError("the IPA has no Payload/<name>.app/Info.plist", path: path)
    }

    /// Raw deflate data, as zip entries hold it.
    static func inflate(_ input: [UInt8], size: Int, path: String) throws -> [UInt8] {
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw NomacError("cannot start zlib", path: path)
        }
        defer { inflateEnd(&stream) }
        var input = input
        var output = [UInt8](repeating: 0, count: size)
        let status = input.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                stream.next_in = inputBuffer.baseAddress
                stream.avail_in = UInt32(inputBuffer.count)
                stream.next_out = outputBuffer.baseAddress
                stream.avail_out = UInt32(outputBuffer.count)
                return CZlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, Int(stream.total_out) == size else { throw NomacError("corrupt deflate data in the IPA", path: path) }
        return output
    }
}
