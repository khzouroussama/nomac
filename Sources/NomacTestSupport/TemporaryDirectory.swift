import Foundation

/// A uniquely named directory under the system temporary directory, removed on `deinit`.
public final class TemporaryDirectory {
    public let path: String

    public init(prefix: String = "nomac-test") throws {
        let base = NSTemporaryDirectory()
        path = (base as NSString).appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    /// Writes `contents` at `relativePath`, creating its folders, with the names' bytes as
    /// given: Foundation decomposes the names of the files it creates on a Mac.
    public func writeExactly(_ contents: String, to relativePath: String) throws {
        var current = path
        let components = relativePath.split(separator: "/").map(String.init)
        for component in components.dropLast() {
            current += "/" + component
            guard mkdir(current, 0o755) == 0 || errno == EEXIST else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: current])
            }
        }
        current += "/" + (components.last ?? "")
        guard let file = fopen(current, "w") else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: current])
        }
        defer { fclose(file) }
        fputs(contents, file)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }
}
