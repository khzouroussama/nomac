import NomacCore
@testable import NomacBuildService
import Testing

/// Off macOS, nomac presents the profile's reference Mac unless `--host-identity` names another
/// (B-060, docs/adr/0012-one-xcode-per-release.md).
@Suite struct HostIdentityTests {
    let linux = HostIdentity(userName: "u", groupName: "g", uid: 1000, gid: 1000, homeDirectory: "/home/u",
                             operatingSystemVersion: [6, 8, 0], operatingSystemBuild: "6.8.0-45-generic",
                             nativeArchitecture: "x86_64", isMacOS: false, environment: ["HOME": "/home/u"])

    @Test func aLinuxMachinePresentsTheReferenceMac() {
        var mac = XcodeProfile.current.referenceMac
        mac.operatingSystemVersion = "27.0.1"
        mac.operatingSystemBuild = "26A434"
        mac.nativeArchitecture = "arm64"
        let host = linux.presenting(mac)
        #expect(host.isMacOS)
        #expect(host.operatingSystemVersion == [27, 0, 1])
        #expect(host.operatingSystemBuild == "26A434")
        #expect(host.nativeArchitecture == "arm64")
        #expect(host.userName == "u" && host.homeDirectory == "/home/u" && host.environment == ["HOME": "/home/u"])
    }

    @Test func aMacStaysItself() {
        var mac = linux
        mac.isMacOS = true
        #expect(mac.presenting(XcodeProfile.current.referenceMac) == mac)
    }

    @Test func theDefaultIsAMac() {
        let host = HostIdentity.default()
        #expect(host.isMacOS)
        #expect(host.userName == HostIdentity.current().userName)
        #if !os(macOS)
        #expect(host.operatingSystemBuild == XcodeProfile.current.referenceMac.operatingSystemBuild)
        #endif
    }
}
