import Foundation
import NomacCore
import NomacSigning

/// A CoreDevice service's invocation, as pymobiledevice3's `core_device_service.py` sends it
/// (docs/formats/remotexpc.md): the feature, its input, CoreDevice's version and fresh
/// identifiers; the reply has `CoreDevice.output`, or `CoreDevice.error`.
public enum CoreDeviceService {
    /// The CoreDevice version pymobiledevice3 announces.
    static let version = "629.3"

    public static func request(feature: String, input: XPCObject, deviceIdentifier: String = UUID().uuidString,
                               invocationIdentifier: String = UUID().uuidString) -> XPCObject {
        let components = version.split(separator: ".").compactMap { UInt64($0) }
        return .dictionary([
            .init("CoreDevice.CoreDeviceDDIProtocolVersion", .int64(2)),
            .init("CoreDevice.coreDeviceVersion", .dictionary([
                .init("components", .array(components.map { .uint64($0) })),
                .init("originalComponentsCount", .int64(Int64(components.count))),
                .init("stringValue", .string(version)),
            ])),
            .init("CoreDevice.deviceIdentifier", .string(deviceIdentifier)),
            .init("CoreDevice.input", input),
            .init("CoreDevice.invocationIdentifier", .string(invocationIdentifier)),
            .init("CoreDevice.featureIdentifier", .string(feature)),
            .init("CoreDevice.action", .dictionary([])),
        ])
    }

    public static func output(_ reply: XPCObject, of feature: String) throws -> XPCObject {
        if let output = reply["CoreDevice.output"] { return output }
        if case .string(let description)? = reply["CoreDevice.error"]?["userInfo"]?["NSLocalizedDescription"] {
            let code = if case .int64(let value)? = reply["CoreDevice.error"]?["code"] { " (code \(value))" } else { "" }
            throw NomacError("the device refused \(feature): \(description)\(code)")
        }
        throw NomacError("the device answered \(feature) without CoreDevice.output")
    }

    public static func invoke(_ feature: String, input: XPCObject, on connection: RemoteXPCConnection) throws -> XPCObject {
        try connection.send(request(feature: feature, input: input), wantingReply: true)
        return try output(try connection.receive().payload ?? .null, of: feature)
    }
}

/// `com.apple.coredevice.appservice`, which launches apps.
public enum AppService {
    public static let serviceName = "com.apple.coredevice.appservice"
    public static let launchFeature = "com.apple.coredevice.feature.launchapplication"

    /// The launch input pymobiledevice3's `launch_application` sends: the bundle identifier,
    /// arguments and environment, an existing process terminated, as the user `mobile`.
    /// The service whose connection carries a launched process's standard input and output: it
    /// sends a 16-byte identifier first, which the launch names for all three streams.
    public static let standardIOServiceName = "com.apple.coredevice.openstdiosocket"

    public static func launchInput(bundleIdentifier: String, arguments: [String] = [], environment: [String: String] = [:],
                                   standardIO: [UInt8]? = nil) -> XPCObject {
        .dictionary([
            .init("applicationSpecifier", .dictionary([.init("bundleIdentifier", .dictionary([.init("_0", .string(bundleIdentifier))]))])),
            .init("options", .dictionary([
                .init("arguments", .array(arguments.map { .string($0) })),
                .init("environmentVariables", .dictionary(environment.keys.sorted().map { .init($0, .string(environment[$0]!)) })),
                .init("standardIOUsesPseudoterminals", .bool(true)),
                .init("startStopped", .bool(false)),
                .init("terminateExisting", .bool(true)),
                .init("user", .dictionary([.init("shortName", .string("mobile"))])),
                .init("platformSpecificOptions", .data(PropertyListValue.xmlDocument(.dictionary([:])))),
            ])),
            .init("standardIOIdentifiers", .dictionary(standardIO.map { identifier in
                ["standardInput", "standardOutput", "standardError"].map { XPCObject.Entry($0, .uuid(identifier)) }
            } ?? [])),
        ])
    }

    public static let listProcessesFeature = "com.apple.coredevice.feature.listprocesses"
    public static let sendSignalFeature = "com.apple.coredevice.feature.sendsignaltoprocess"

    /// The processes `listprocesses` lists (`processTokens`): identifier and executable path
    /// (`executableURL.relative`, a `file://` URL).
    public static func processes(_ output: XPCObject) -> [(identifier: Int64, executable: String)] {
        guard case .array(let tokens)? = output["processTokens"] else { return [] }
        return tokens.compactMap { token in
            let identifier: Int64? = switch token["processIdentifier"] {
            case .int64(let value)?: value
            case .uint64(let value)?: Int64(exactly: value)
            default: nil
            }
            let url: String? = switch token["executableURL"] {
            case .string(let text)?: text
            case .dictionary?: if case .string(let text)? = token["executableURL"]?["relative"] { text } else { nil }
            default: nil
            }
            guard let identifier, let url else { return nil }
            return (identifier, url.hasPrefix("file://") ? (URL(string: url)?.path ?? String(url.dropFirst(7))) : url)
        }
    }

    /// `sendsignaltoprocess`'s input: the process and the signal number.
    public static func signalInput(process: Int64, signal: Int32) -> XPCObject {
        .dictionary([
            .init("process", .dictionary([.init("processIdentifier", .int64(process))])),
            .init("signal", .int64(Int64(signal))),
        ])
    }

    /// The launched process's identifier, from the launch output's `processToken`.
    public static func processIdentifier(_ output: XPCObject) -> Int64? {
        switch output["processToken"]?["processIdentifier"] {
        case .int64(let value)?: value
        case .uint64(let value)?: Int64(exactly: value)
        default: nil
        }
    }
}
