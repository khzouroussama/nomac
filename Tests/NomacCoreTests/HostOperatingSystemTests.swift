import Foundation
import Testing
import NomacCore

#if !os(macOS)
@Suite struct HostOperatingSystemTests {
    /// A user's shell on Ubuntu has a soft limit of 1024 under a hard limit of 1048576, and root in
    /// Docker 1048576 for both.
    @Test func openFileLimitRisesToTheHardLimit() throws {
        let resource = __rlimit_resource_t(RLIMIT_NOFILE.rawValue)
        var limit = rlimit()
        #expect(getrlimit(resource, &limit) == 0)
        let original = limit
        defer {
            var restored = original
            setrlimit(resource, &restored)
        }
        limit.rlim_cur = min(limit.rlim_max, 4096)
        #expect(setrlimit(resource, &limit) == 0)

        HostOperatingSystem.raiseOpenFileLimit()

        #expect(getrlimit(resource, &limit) == 0)
        #expect(limit.rlim_cur == limit.rlim_max)
        #expect(limit.rlim_max == original.rlim_max)
    }
}
#endif
