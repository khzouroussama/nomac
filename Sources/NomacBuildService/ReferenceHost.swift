import Foundation
import NomacCore

/// The host description written by the reference capture (`host.json`, see
/// corpus/scripts/capture_reference.py), and its conversion to a ``HostIdentity``.
public struct ReferenceHost: Codable, Sendable, Equatable {
    public var xcodeVersion: String
    public var xcodeBuild: String
    public var developerDirectory: String
    public var operatingSystemVersion: String
    public var operatingSystemBuild: String
    public var nativeArchitecture: String
    public var userName: String
    public var groupName: String
    public var uid: Int
    public var gid: Int
    public var homeDirectory: String
    public var environment: [String: String]
    /// `getconf DARWIN_USER_CACHE_DIR` on the reference Mac (absent in older captures).
    public var userCacheDirectory: String?

    /// Reads a `host.json` file.
    public static func load(path: String) throws -> ReferenceHost {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw NomacError("could not read the host description", path: path)
        }
        do {
            return try JSONDecoder().decode(ReferenceHost.self, from: data)
        } catch {
            throw NomacError("malformed host description: \(error)", path: path)
        }
    }

    /// The identity to present to Swift Build so it evaluates settings as it did on the
    /// reference host. `DEVELOPER_DIR` in the environment is replaced by the developer
    /// directory nomac actually uses.
    public func identity(developerDirectory: String) -> HostIdentity {
        var environment = self.environment
        if environment["DEVELOPER_DIR"] != nil {
            environment["DEVELOPER_DIR"] = developerDirectory
        }
        let version = operatingSystemVersion.split(separator: ".").map { Int($0) ?? 0 }
        return HostIdentity(
            userName: userName,
            groupName: groupName,
            uid: uid,
            gid: gid,
            homeDirectory: homeDirectory,
            operatingSystemVersion: version,
            operatingSystemBuild: operatingSystemBuild,
            nativeArchitecture: nativeArchitecture,
            isMacOS: true,
            environment: environment)
    }
}
