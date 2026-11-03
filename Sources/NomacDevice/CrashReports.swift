import Foundation
import NomacCore

/// The device's crash reports (`.ips`): `com.apple.crashreportmover` moves the reports written
/// since it last ran into the folder `com.apple.crashreportcopymobile` serves over AFC, and
/// answers `ping` when it is done (docs/formats/crash-report.md).
public enum CrashReports {
    public static let moverServiceName = "com.apple.crashreportmover"
    public static let copyServiceName = "com.apple.crashreportcopymobile"

    public struct Report: Equatable, Sendable {
        public var path: String
        public var size: UInt64
        /// Seconds since 1970.
        public var modified: Double
    }

    /// Waits for the mover's `ping`.
    public static func waitForMover(_ stream: ByteStream) throws {
        let reply = try stream.read(4)
        guard reply == Array("ping".utf8) else { throw NomacError("crashreportmover answered \(reply) instead of ping") }
    }

    /// The reports under `folder` (`/` for every one), depth first in AFC's order.
    public static func reports(in folder: String = "/", afc: AFCClient) throws -> [Report] {
        var found: [Report] = []
        for name in try afc.list(folder) {
            let path = folder == "/" ? "/" + name : folder + "/" + name
            let info = try afc.info(path)
            if info["st_ifmt"] == "S_IFDIR" {
                found += try reports(in: path, afc: afc)
            } else if name.hasSuffix(".ips") {
                found.append(Report(path: path, size: UInt64(info["st_size"] ?? "") ?? 0,
                                    modified: (Double(info["st_mtime"] ?? "") ?? 0) / 1_000_000_000))
            }
        }
        return found
    }
}
