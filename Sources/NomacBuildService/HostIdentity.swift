import Foundation
import NomacCore

/// The identity of the machine and user a build is evaluated for.
///
/// Swift Build exposes these values as build settings (`USER`, `UID`, `HOME`,
/// `MAC_OS_X_VERSION_ACTUAL`, `NATIVE_ARCH`, ...). By default nomac reports the
/// real values of the current machine, on a Mac, and elsewhere the profile's reference Mac
/// (``default(profile:)``). Verification against a reference capture
/// substitutes the identity recorded on the reference Mac so that settings derived
/// from it are comparable byte for byte.
public struct HostIdentity: Codable, Sendable, Equatable {
    public var userName: String
    public var groupName: String
    public var uid: Int
    public var gid: Int
    public var homeDirectory: String
    /// The host operating system version reported to Swift Build (`major.minor.patch`).
    public var operatingSystemVersion: [Int]
    /// The host operating system build number (for macOS, `sw_vers -buildVersion`).
    public var operatingSystemBuild: String
    /// The host architecture name in Apple's spelling (`arm64`, `x86_64`).
    public var nativeArchitecture: String
    /// Whether the identity is a Mac's: a reference host, or the current machine on macOS. Only
    /// a Mac's operating system version becomes the `MAC_OS_X_*` settings.
    public var isMacOS: Bool
    /// The process environment visible to the build.
    public var environment: [String: String]

    public init(userName: String, groupName: String, uid: Int, gid: Int, homeDirectory: String, operatingSystemVersion: [Int], operatingSystemBuild: String, nativeArchitecture: String, isMacOS: Bool, environment: [String: String]) {
        self.userName = userName
        self.groupName = groupName
        self.uid = uid
        self.gid = gid
        self.homeDirectory = homeDirectory
        self.operatingSystemVersion = operatingSystemVersion
        self.operatingSystemBuild = operatingSystemBuild
        self.nativeArchitecture = nativeArchitecture
        self.isMacOS = isMacOS
        self.environment = environment
    }

    /// The identity of the current process and machine.
    public static func current() -> HostIdentity {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        return HostIdentity(
            userName: currentUserName(),
            groupName: currentGroupName(),
            uid: Int(getuid()),
            gid: Int(getgid()),
            homeDirectory: NSHomeDirectory(),
            operatingSystemVersion: [version.majorVersion, version.minorVersion, version.patchVersion],
            operatingSystemBuild: HostOperatingSystem.build,
            nativeArchitecture: currentArchitecture(),
            isMacOS: HostOperatingSystem.isMacOS,
            environment: info.environment
        )
    }

    /// The identity nomac presents unless `--host-identity` names another: the current one, with,
    /// off macOS, `profile`'s reference Mac as the machine (B-060, docs/adr/0012-one-xcode-per-release.md).
    public static func `default`(profile: XcodeProfile = .current) -> HostIdentity {
        current().presenting(profile.referenceMac)
    }

    /// This identity, or for one that is not a Mac's, this user and environment on `mac`.
    func presenting(_ mac: XcodeProfile.ReferenceMac) -> HostIdentity {
        guard !isMacOS else { return self }
        var host = self
        host.operatingSystemVersion = mac.operatingSystemVersion.split(separator: ".").map { Int($0) ?? 0 }
        host.operatingSystemBuild = mac.operatingSystemBuild
        host.nativeArchitecture = mac.nativeArchitecture
        host.isMacOS = true
        return host
    }

    private static func currentUserName() -> String {
        if let pw = getpwuid(getuid()), let name = pw.pointee.pw_name {
            return String(cString: name)
        }
        return ProcessInfo.processInfo.environment["USER"] ?? "unknown"
    }

    private static func currentGroupName() -> String {
        if let gr = getgrgid(getgid()), let name = gr.pointee.gr_name {
            return String(cString: name)
        }
        return "unknown"
    }

    private static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

}
