import Foundation
import NomacSigning
import Testing
@testable import NomacDevice

/// Stopping an app: installation_proxy's `Lookup` for its path, then the app service's
/// `listprocesses` and `sendsignaltoprocess` (docs/formats/remotexpc.md).
@Suite struct StopTests {
    static let path = "/private/var/containers/Bundle/Application/0A1B2C3D-0000-0000-0000-000000000000/App.app"

    @Test func lookupGivesTheInstallPath() throws {
        let stream = ReplayStream(replies: [
            ["LookupResult": .dictionary(["org.nomac.app": .dictionary(["CFBundleIdentifier": .string("org.nomac.app"), "Path": .string(Self.path)])]),
             "Status": .string("Complete")],
        ])
        #expect(try InstallationProxyClient(stream: stream).path(of: "org.nomac.app") == Self.path)
        let request = try PropertyListMessages.receive(from: ReplayStream(bytes: stream.written), source: "test")
        #expect(request["Command"] == .string("Lookup"))
        guard case .dictionary(let options)? = request["ClientOptions"] else { Issue.record("no ClientOptions"); return }
        #expect(options["BundleIDs"] == .array([.string("org.nomac.app")]))
        #expect(try InstallationProxyClient(stream: ReplayStream(replies: [["LookupResult": .dictionary([:]), "Status": .string("Complete")]]))
            .path(of: "org.nomac.app") == nil)
    }

    @Test func processesAndTheirExecutables() {
        let output = XPCObject.dictionary([.init("processTokens", .array([
            .dictionary([.init("processIdentifier", .int64(3575)),
                         .init("executableURL", .dictionary([.init("relative", .string("file://" + Self.path + "/App"))]))]),
            .dictionary([.init("processIdentifier", .int64(1)), .init("executableURL", .string("file:///sbin/launchd"))]),
            .dictionary([.init("processIdentifier", .int64(2))]),
        ]))])
        let processes = AppService.processes(output)
        #expect(processes.map(\.identifier) == [3575, 1])
        #expect(processes.map(\.executable) == [Self.path + "/App", "/sbin/launchd"])
        #expect(DeviceSession.within(Self.path + "/App", Self.path))
        #expect(DeviceSession.within("/var/containers/Bundle/Application/0A1B2C3D-0000-0000-0000-000000000000/App.app/App", Self.path))
        #expect(!DeviceSession.within(Self.path + "Clip/App", Self.path))
    }

    @Test func signalRequest() throws {
        let input = AppService.signalInput(process: 3575, signal: 15)
        #expect(input["process"]?["processIdentifier"] == .int64(3575))
        #expect(input["signal"] == .int64(15))
        let request = CoreDeviceService.request(feature: AppService.sendSignalFeature, input: input, deviceIdentifier: "D", invocationIdentifier: "I")
        #expect(try XPCObject.decode(request.encoded()) == request)
    }
}
