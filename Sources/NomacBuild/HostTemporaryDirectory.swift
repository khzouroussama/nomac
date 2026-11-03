import Foundation
import NomacBuildService
import NomacCore

/// The reference Mac's `TMPDIR` on the machine that builds (docs/formats/build.md "The reference Mac's TMPDIR").
///
/// A build with a host identity gives Swift Build that Mac's environment, so every task runs with
/// its `TMPDIR` (`/var/folders/…/T/`), where the compilers and linkers write their temporary files;
/// the path stays the Mac's so that settings and outputs that name it do. Off macOS that folder does
/// not exist, and links failed in it, so the build creates it.
public enum HostTemporaryDirectory {
    public static func prepare(_ host: HostIdentity) throws {
        guard let directory = host.environment["TMPDIR"], !directory.isEmpty, !FileSystem.isDirectory(directory) else { return }
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            throw NomacError("could not create the reference Mac's TMPDIR, which the build's tasks use: \(error.localizedDescription)", path: directory)
        }
    }
}
