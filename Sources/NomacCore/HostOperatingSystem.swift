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

    /// Off macOS, raises this process's soft limit on open files to its hard limit, for the tools
    /// a build runs too. A user's shell on Ubuntu starts at 1024 and llbuild raises that only to
    /// 2048, which a fresh Expo app's archive runs out of on arm64 ("Too many open files").
    public static func raiseOpenFileLimit() {
        #if !os(macOS)
        let resource = __rlimit_resource_t(RLIMIT_NOFILE.rawValue)
        var limit = rlimit()
        guard getrlimit(resource, &limit) == 0, limit.rlim_cur < limit.rlim_max else { return }
        limit.rlim_cur = limit.rlim_max
        setrlimit(resource, &limit)
        #endif
    }
}
