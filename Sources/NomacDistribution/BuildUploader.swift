import Crypto
import Foundation
import NomacCore

/// Uploads an IPA to App Store Connect with the API's build uploads (docs/formats/
/// app-store-connect-upload.md "The upload"): the app looked up by its bundle ID, a build upload
/// created for its versions and platform, the IPA's file reserved, sent in the parts the
/// reservation lists, committed with its MD5, and with `wait` the build upload polled until App
/// Store Connect finishes processing it.
public struct BuildUploader {
    /// How often a build upload is polled while App Store Connect processes it.
    public static let pollInterval: TimeInterval = 30
    /// How many times a part is sent before the upload stops; a part may be sent again until
    /// the file is committed ("Uploading Assets to App Store Connect").
    static let partAttempts = 3

    let client: AppStoreConnectClient
    /// Sends the upload operations, whose URLs carry their own authorization.
    let transport: HTTPTransport
    let log: (String) -> Void
    let sleep: (TimeInterval) -> Void

    public init(client: AppStoreConnectClient, transport: HTTPTransport, log: @escaping (String) -> Void,
                sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.client = client
        self.transport = transport
        self.log = log
        self.sleep = sleep
    }

    public struct Result: Equatable {
        public var buildUploadID: String
        /// The build upload's `BuildUploadState` when the uploader returned: `AWAITING_UPLOAD` or
        /// `PROCESSING` after the commit, `COMPLETE` after waiting.
        public var state: String
    }

    public func upload(ipa path: String, info: IPAInfo, appID givenAppID: String?, wait: Bool) throws -> Result {
        let appID = try givenAppID ?? self.appID(bundleIdentifier: info.bundleIdentifier)
        let created = try client.post("/v1/buildUploads", ["data": [
            "type": "buildUploads",
            "attributes": ["cfBundleShortVersionString": info.shortVersion, "cfBundleVersion": info.version, "platform": info.platform],
            "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
        ]])
        let buildUploadID = try Self.identifier(of: created, "the build upload")
        log("Created build upload \(buildUploadID) for \(info.bundleIdentifier) \(info.shortVersion) (\(info.version)), \(info.platform)")

        let reserved = try client.post("/v1/buildUploadFiles", ["data": [
            "type": "buildUploadFiles",
            "attributes": ["assetType": "ASSET", "fileName": info.fileName, "fileSize": info.fileSize, "uti": "com.apple.ipa"],
            "relationships": ["buildUpload": ["data": ["type": "buildUploads", "id": buildUploadID]]],
        ]])
        let fileID = try Self.identifier(of: reserved, "the build upload file")
        let operations = try Self.operations(of: reserved, fileSize: info.fileSize)
        log("Reserved \(info.fileName) (\(info.fileSize) bytes) in \(operations.count) part\(operations.count == 1 ? "" : "s")")
        guard let handle = FileHandle(forReadingAtPath: path) else { throw NomacError("cannot read the IPA", path: path) }
        defer { try? handle.close() }
        for (index, operation) in operations.enumerated() {
            try send(operation, from: handle, path: path)
            log("Sent part \(index + 1) of \(operations.count)")
        }

        let committed = try client.patch("/v1/buildUploadFiles/\(fileID)", ["data": [
            "type": "buildUploadFiles", "id": fileID,
            "attributes": ["uploaded": true, "sourceFileChecksums": ["file": ["algorithm": "MD5", "hash": try Self.md5(handle, path: path)]]],
        ]])
        let delivery = ((Self.attributes(of: committed)["assetDeliveryState"] as? [String: Any])?["state"] as? String) ?? "unknown"
        log("Committed \(info.fileName): \(delivery)")
        guard wait else {
            let state = try buildUploadState(buildUploadID)
            return Result(buildUploadID: buildUploadID, state: state.state)
        }
        var reported: Set<String> = []
        while true {
            let state = try buildUploadState(buildUploadID)
            for line in state.details where reported.insert(line).inserted { log(line) }
            switch state.state {
            case "COMPLETE":
                log("App Store Connect processed build upload \(buildUploadID)")
                return Result(buildUploadID: buildUploadID, state: state.state)
            case "FAILED":
                throw NomacError("App Store Connect could not process build upload \(buildUploadID)", notes: state.errors)
            default:
                log("Build upload \(buildUploadID): \(state.state)")
                sleep(Self.pollInterval)
            }
        }
    }

    /// The App Store Connect ID of the app with exactly this bundle ID.
    func appID(bundleIdentifier: String) throws -> String {
        let found = try client.get("/v1/apps", query: [("filter[bundleId]", bundleIdentifier), ("fields[apps]", "bundleId")])
        let apps = found["data"] as? [[String: Any]] ?? []
        guard let app = apps.first(where: { Self.attributes(of: ["data": $0])["bundleId"] as? String == bundleIdentifier }),
              let id = app["id"] as? String else {
            throw NomacError("App Store Connect has no app with the bundle ID \(bundleIdentifier)",
                             notes: ["create the app in App Store Connect, or give its Apple ID with --apple-id"])
        }
        return id
    }

    struct State {
        var state: String
        var errors: [String]
        var details: [String]
    }

    func buildUploadState(_ id: String) throws -> State {
        let document = try client.get("/v1/buildUploads/\(id)", query: [("fields[buildUploads]", "state")])
        let state = Self.attributes(of: document)["state"] as? [String: Any] ?? [:]
        func lines(_ key: String, _ label: String) -> [String] {
            (state[key] as? [[String: Any]] ?? []).map { detail in
                label + ": " + [detail["code"], detail["description"]].compactMap { $0 as? String }.joined(separator: ": ")
            }
        }
        let errors = lines("errors", "error")
        return State(state: state["state"] as? String ?? "unknown", errors: errors,
                     details: errors + lines("warnings", "warning") + lines("infos", "info"))
    }

    struct Operation {
        var method: String
        var url: String
        var offset: Int64
        var length: Int
        var headers: [String: String]
    }

    /// A reservation's `uploadOperations`, which must lie inside the file.
    static func operations(of document: [String: Any], fileSize: Int64) throws -> [Operation] {
        try (attributes(of: document)["uploadOperations"] as? [[String: Any]] ?? []).map { entry in
            guard let method = entry["method"] as? String, let url = entry["url"] as? String,
                  let offset = (entry["offset"] as? NSNumber)?.int64Value, let length = (entry["length"] as? NSNumber)?.intValue,
                  offset >= 0, length > 0, offset + Int64(length) <= fileSize else {
                throw NomacError("App Store Connect's reservation has an upload operation nomac cannot follow")
            }
            var headers: [String: String] = [:]
            for header in entry["requestHeaders"] as? [[String: Any]] ?? [] {
                if let name = header["name"] as? String, let value = header["value"] as? String { headers[name] = value }
            }
            return Operation(method: method, url: url, offset: offset, length: length, headers: headers)
        }
    }

    func send(_ operation: Operation, from handle: FileHandle, path: String) throws {
        try handle.seek(toOffset: UInt64(operation.offset))
        guard let body = try handle.read(upToCount: operation.length), body.count == operation.length else {
            throw NomacError("the IPA changed during the upload", path: path)
        }
        let request = HTTPRequest(method: operation.method, url: operation.url, headers: operation.headers, body: body)
        var failure = ""
        for _ in 0..<Self.partAttempts {
            do {
                let response = try transport.send(request)
                if (200..<300).contains(response.status) { return }
                failure = "HTTP \(response.status)"
            } catch let error as NomacError {
                failure = error.message
            }
        }
        throw NomacError("App Store Connect did not take the part at offset \(operation.offset) (\(failure))", path: path)
    }

    static func md5(_ handle: FileHandle, path: String) throws -> String {
        try handle.seek(toOffset: 0)
        var hash = Insecure.MD5()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func identifier(of document: [String: Any], _ what: String) throws -> String {
        guard let id = (document["data"] as? [String: Any])?["id"] as? String else {
            throw NomacError("App Store Connect's answer has no ID for \(what)")
        }
        return id
    }

    static func attributes(of document: [String: Any]) -> [String: Any] {
        (document["data"] as? [String: Any])?["attributes"] as? [String: Any] ?? [:]
    }
}
