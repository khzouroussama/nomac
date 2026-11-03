import ArgumentParser
import Crypto
import Foundation
import NomacCore
import NomacDistribution

/// `nomac upload`: uploads an IPA to App Store Connect (TestFlight) through the App Store Connect
/// API's build uploads, authenticated with an API key (ADR 0460).
struct UploadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload an IPA to App Store Connect.",
        discussion: """
        Creates a build upload for the app's version, build and platform, sends the IPA in the \
        parts App Store Connect reserves and commits it (docs/formats/app-store-connect-upload.md). \
        The key is found as altool finds it: --p8-file-path, or AuthKey_<key ID>.p8 in ./private_keys, \
        ~/private_keys, ~/.private_keys, ~/.appstoreconnect/private_keys or $API_PRIVATE_KEYS_DIR. \
        Without --api-issuer the key is an individual key. --dry-run prints the requests without \
        sending any.
        """
    )

    @Argument(help: "The IPA, as nomac export writes it for app-store-connect.")
    var ipa: String

    @Option(name: .customLong("api-key"), help: "The API key's key ID.")
    var apiKey: String?

    @Option(name: .customLong("api-issuer"), help: "The issuer ID of a team key.")
    var apiIssuer: String?

    @Option(name: .customLong("p8-file-path"), help: "The key's AuthKey_<key ID>.p8 file.")
    var p8FilePath: String?

    @Option(name: .customLong("apple-id"), help: "The app's Apple ID in App Store Connect (default: looked up by its bundle ID).")
    var appleID: String?

    @Flag(help: "Wait until App Store Connect has processed the build.")
    var wait = false

    @Flag(name: .customLong("dry-run"), help: "Print the requests instead of sending them (a throwaway key without --api-key).")
    var dryRun = false

    func run() throws {
        let path = FileSystem.absolute(ipa)
        let info = try IPAInfo(path: path)
        let key: AppStoreConnectKey
        if let apiKey {
            let folders = AppStoreConnectKey.searchFolders(current: FileManager.default.currentDirectoryPath, home: NSHomeDirectory(),
                                                           environment: ProcessInfo.processInfo.environment)
            key = try AppStoreConnectKey.load(keyID: apiKey, issuer: apiIssuer, p8Path: p8FilePath.map(FileSystem.absolute), folders: folders)
        } else if dryRun {
            key = try AppStoreConnectKey(keyID: "<key-id>", issuer: apiIssuer ?? "<issuer-id>", pem: P256.Signing.PrivateKey().pemRepresentation,
                                         path: "throwaway key")
        } else {
            throw ValidationError("--api-key is required (or --dry-run)")
        }
        let transport: HTTPTransport = dryRun ? DryRunTransport { print($0) } : URLSessionTransport()
        let uploader = BuildUploader(client: AppStoreConnectClient(key: key, transport: transport), transport: transport) { print($0) }
        let result = try uploader.upload(ipa: path, info: info, appID: appleID, wait: wait && !dryRun)
        print("Build upload \(result.buildUploadID): \(result.state)")
    }
}
