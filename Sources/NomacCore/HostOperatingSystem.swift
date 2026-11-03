import Foundation

/// The operating system nomac runs on.
public enum HostOperatingSystem {
    #if os(macOS)
    public static let isMacOS = true
    #else
    public static let isMacOS = false
    #endif

    /// macOS's build (`kern.osversion`, as `BuildMachineOSBuild` records it), or elsewhere the
    /// kernel's release.
    public static var build: String {
        #if os(macOS)
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        #else
        var name = utsname()
        uname(&name)
        return withUnsafeBytes(of: &name.release) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        #endif
    }

    /// The Mac's build that nomac presents: this Mac's, or off macOS the reference Mac's
    /// (ADR 0012, B-060).
    public static var macBuild: String {
        isMacOS ? build : XcodeProfile.current.referenceMac.operatingSystemBuild
    }
}
