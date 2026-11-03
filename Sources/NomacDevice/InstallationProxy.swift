import Foundation
import NomacCore
import NomacSigning

/// installation_proxy (`com.apple.mobile.installation_proxy`), the service that installs a
/// package AFC put in the media folder and removes apps (docs/formats/lockdown.md). Requests
/// have `Command` and `ClientOptions`; the service answers with progress messages (`Status`,
/// `PercentComplete`) until `Status` is `Complete`, or with `Error` and `ErrorDescription`.
public enum InstallationProxy {
    public static let serviceName = "com.apple.mobile.installation_proxy"
    /// The media folder's staging folder, where packages are uploaded for installation.
    public static let stagingFolder = "PublicStaging"

    public static func install(packagePath: String) -> [String: PropertyListValue] {
        ["Command": .string("Install"), "PackagePath": .string(packagePath), "ClientOptions": .dictionary([:])]
    }

    public static func uninstall(bundleIdentifier: String) -> [String: PropertyListValue] {
        ["Command": .string("Uninstall"), "ApplicationIdentifier": .string(bundleIdentifier), "ClientOptions": .dictionary([:])]
    }

    /// `Lookup` of one app's install path.
    public static func lookup(bundleIdentifier: String) -> [String: PropertyListValue] {
        ["Command": .string("Lookup"), "ClientOptions": .dictionary([
            "BundleIDs": .array([.string(bundleIdentifier)]), "ReturnAttributes": .array([.string("CFBundleIdentifier"), .string("Path")]),
        ])]
    }

    /// The status a progress message reports, `Complete` last, or the service's error.
    public static func status(_ reply: [String: PropertyListValue]) throws -> (status: String, percent: Int64?) {
        if case .string(let error)? = reply["Error"] {
            let description = if case .string(let text)? = reply["ErrorDescription"] { ": \(text)" } else { "" }
            throw NomacError("installation_proxy failed: \(error)\(description)")
        }
        guard case .string(let status)? = reply["Status"] else { throw NomacError("installation_proxy sent a message without Status or Error") }
        let percent: Int64? = if case .integer(let value)? = reply["PercentComplete"] { value } else { nil }
        return (status, percent)
    }
}

/// A client of installation_proxy over its service connection.
public final class InstallationProxyClient {
    private let stream: ByteStream

    public init(stream: ByteStream) { self.stream = stream }

    /// The path where the app with `bundleIdentifier` is installed (`LookupResult`), nil when it
    /// is not installed.
    public func path(of bundleIdentifier: String) throws -> String? {
        try PropertyListMessages.send(InstallationProxy.lookup(bundleIdentifier: bundleIdentifier), on: stream)
        var path: String?
        while true {
            let reply = try PropertyListMessages.receive(from: stream, source: "installation_proxy")
            if case .dictionary(let result)? = reply["LookupResult"], case .dictionary(let app)? = result[bundleIdentifier],
               case .string(let found)? = app["Path"] {
                path = found
            }
            if try InstallationProxy.status(reply).status == "Complete" { return path }
        }
    }

    /// Sends `command` and reads its progress until `Complete`, passing each status on.
    public func run(_ command: [String: PropertyListValue], progress: (String, Int64?) -> Void) throws {
        try PropertyListMessages.send(command, on: stream)
        while true {
            let (status, percent) = try InstallationProxy.status(try PropertyListMessages.receive(from: stream, source: "installation_proxy"))
            if status == "Complete" { return }
            progress(status, percent)
        }
    }
}
