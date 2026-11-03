import Crypto
import Foundation
import NomacCore
import Testing
@testable import NomacDistribution

/// Answers each request with the next scripted response, keyed by method and URL, and keeps the
/// requests; the responses are written from Apple's OpenAPI specification 4.5.1.
final class ScriptedTransport: HTTPTransport {
    var script: [(String, HTTPResponse)]
    var requests: [HTTPRequest] = []

    init(_ script: [(String, HTTPResponse)]) {
        self.script = script
    }

    func send(_ request: HTTPRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !script.isEmpty, script[0].0 == "\(request.method) \(request.url)" else {
            throw NomacError("unexpected \(request.method) \(request.url)")
        }
        return script.removeFirst().1
    }
}

func json(_ object: Any, status: Int = 200) -> HTTPResponse {
    HTTPResponse(status: status, body: try! JSONSerialization.data(withJSONObject: object))
}

func bodyObject(_ request: HTTPRequest) -> NSDictionary {
    (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? NSDictionary ?? [:]
}

/// A zip holding `entries` as `ditto -c -k` lays them out, each entry stored or as one stored
/// deflate block (method 8).
func zipFile(_ entries: [(String, [UInt8], deflated: Bool)]) -> [UInt8] {
    func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xff), UInt8(value >> 8 & 0xff)] }
    func le32(_ value: Int) -> [UInt8] { le16(value & 0xffff) + le16(value >> 16) }
    var local: [UInt8] = [], central: [UInt8] = []
    for (name, contents, deflated) in entries {
        let data = deflated ? [0x01] + le16(contents.count) + le16(~contents.count & 0xffff) + contents : contents
        let common = le16(20) + le16(0) + le16(deflated ? 8 : 0) + le32(0) + le32(0) + le32(data.count) + le32(contents.count)
            + le16(name.utf8.count) + le16(0)
        central += le32(0x0201_4b50) + le16(0x031e) + common + le16(0) + le16(0) + le16(0) + le32(0o100644 << 16) + le32(local.count) + Array(name.utf8)
        local += le32(0x0403_4b50) + common + Array(name.utf8) + data
    }
    return local + central + le32(0x0605_4b50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count)
        + le32(central.count) + le32(local.count) + le16(0)
}

func infoPlist(_ values: [String: Any]) -> [UInt8] {
    [UInt8](try! PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0))
}

var appInfo: [String: Any] { ["CFBundleIdentifier": "org.nomac.upload", "CFBundleShortVersionString": "1.2", "CFBundleVersion": "7",
                              "CFBundleSupportedPlatforms": ["iPhoneOS"]] }

func temporaryFile(_ name: String, _ bytes: [UInt8]) throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-upload-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    let path = folder + "/" + name
    try Data(bytes).write(to: URL(fileURLWithPath: path))
    return path
}

@Suite struct TokenTests {
    let privateKey = P256.Signing.PrivateKey()

    func parts(_ token: String) throws -> [Data] {
        try token.split(separator: ".").map { part in
            var base64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            return try #require(Data(base64Encoded: base64))
        }
    }

    @Test func teamKeyTokenIsSignedWithES256() throws {
        let key = try AppStoreConnectKey(keyID: "2X9R4HXF34", issuer: "57246542-96fe-1a63-e053-0824d011072a",
                                         pem: privateKey.pemRepresentation, path: "AuthKey_2X9R4HXF34.p8")
        let token = try key.token(issuedAt: Date(timeIntervalSince1970: 1_528_407_600))
        let decoded = try parts(token)
        #expect(String(decoding: decoded[0], as: UTF8.self) == #"{"alg":"ES256","kid":"2X9R4HXF34","typ":"JWT"}"#)
        #expect(String(decoding: decoded[1], as: UTF8.self)
            == #"{"aud":"appstoreconnect-v1","exp":1528408200,"iat":1528407600,"iss":"57246542-96fe-1a63-e053-0824d011072a"}"#)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: decoded[2])
        let signingInput = token.split(separator: ".").prefix(2).joined(separator: ".")
        #expect(privateKey.publicKey.isValidSignature(signature, for: Data(signingInput.utf8)))
        #expect(!token.contains("=") && !token.contains("+") && !token.contains("/"))
    }

    @Test func individualKeyTokenNamesTheUser() throws {
        let key = try AppStoreConnectKey(keyID: "ABC123", issuer: nil, pem: privateKey.pemRepresentation, path: "key.p8")
        let claims = try parts(key.token(issuedAt: Date(timeIntervalSince1970: 100)))[1]
        #expect(String(decoding: claims, as: UTF8.self) == #"{"aud":"appstoreconnect-v1","exp":700,"iat":100,"sub":"user"}"#)
    }

    @Test func keyIsFoundWhereAltoolLooks() throws {
        let folders = AppStoreConnectKey.searchFolders(current: "/work", home: "/home/me", environment: ["API_PRIVATE_KEYS_DIR": "/keys"])
        #expect(folders == ["/work/private_keys", "/home/me/private_keys", "/home/me/.private_keys", "/home/me/.appstoreconnect/private_keys", "/keys"])
        let path = try temporaryFile("AuthKey_KEY1.p8", Array(privateKey.pemRepresentation.utf8))
        let folder = (path as NSString).deletingLastPathComponent
        let key = try AppStoreConnectKey.load(keyID: "KEY1", issuer: "issuer", p8Path: nil, folders: ["/missing", folder])
        #expect(key.keyID == "KEY1")
        #expect(throws: NomacError("no private key file for API key KEY2", notes: ["looked for /missing/AuthKey_KEY2.p8", "looked for \(folder)/AuthKey_KEY2.p8"])) {
            try AppStoreConnectKey.load(keyID: "KEY2", issuer: nil, p8Path: nil, folders: ["/missing", folder])
        }
        #expect(throws: NomacError("not an App Store Connect API private key (a P-256 key in PEM)", path: "bad.p8")) {
            try AppStoreConnectKey(keyID: "K", issuer: nil, pem: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n", path: "bad.p8")
        }
    }
}

@Suite struct IPAInfoTests {
    @Test func readsTheAppsInfoPlistStoredOrDeflated() throws {
        for deflated in [false, true] {
            let path = try temporaryFile("App.ipa", zipFile([
                ("Payload/", [], deflated: false),
                ("Payload/App.app/Frameworks/Kit.framework/Info.plist", infoPlist(["CFBundleIdentifier": "org.nomac.kit"]), deflated: false),
                ("Payload/App.app/Info.plist", infoPlist(appInfo), deflated: deflated),
            ]))
            let info = try IPAInfo(path: path)
            let size = try #require(FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber).int64Value
            #expect([info.fileName, info.bundleIdentifier, info.shortVersion, info.version, info.platform] == ["App.ipa", "org.nomac.upload", "1.2", "7", "IOS"])
            #expect(info.fileSize == size)
        }
    }

    @Test func refusesWhatAnUploadCannotName() throws {
        let noApp = try temporaryFile("Empty.ipa", zipFile([("Payload/", [], deflated: false)]))
        #expect(throws: NomacError("the IPA has no Payload/<name>.app/Info.plist", path: noApp)) { try IPAInfo(path: noApp) }
        var mac = appInfo
        mac["CFBundleSupportedPlatforms"] = ["MacOSX"]
        let macPath = try temporaryFile("Mac.ipa", zipFile([("Payload/Mac.app/Info.plist", infoPlist(mac), deflated: false)]))
        #expect(throws: NomacError("the app's platform \"MacOSX\" is not one App Store Connect takes as an IPA", path: macPath)) { try IPAInfo(path: macPath) }
        var unversioned = appInfo
        unversioned.removeValue(forKey: "CFBundleVersion")
        let unversionedPath = try temporaryFile("App.ipa", zipFile([("Payload/App.app/Info.plist", infoPlist(unversioned), deflated: true)]))
        #expect(throws: NomacError("the app's Info.plist has no CFBundleVersion", path: unversionedPath)) { try IPAInfo(path: unversionedPath) }
    }
}

@Suite struct BuildUploaderTests {
    let key = try! AppStoreConnectKey(keyID: "KEY1", issuer: "issuer", pem: P256.Signing.PrivateKey().pemRepresentation, path: "key.p8")
    let base = AppStoreConnectClient.base

    func ipa() throws -> (String, IPAInfo) {
        let path = try temporaryFile("App.ipa", zipFile([("Payload/App.app/Info.plist", infoPlist(appInfo), deflated: true), ("Payload/App.app/App", Array(repeating: 7, count: 300), deflated: false)]))
        return (path, try IPAInfo(path: path))
    }

    func reservation(_ size: Int64) -> HTTPResponse {
        json(["data": ["type": "buildUploadFiles", "id": "file-1", "attributes": [
            "assetType": "ASSET", "fileName": "App.ipa", "fileSize": size, "uti": "com.apple.ipa",
            "uploadOperations": [
                ["method": "PUT", "url": "https://upload.example/part1", "offset": 0, "length": 200, "partNumber": 1,
                 "requestHeaders": [["name": "Content-Type", "value": "application/octet-stream"]]],
                ["method": "PUT", "url": "https://upload.example/part2", "offset": 200, "length": size - 200, "partNumber": 2,
                 "requestHeaders": [["name": "Content-Type", "value": "application/octet-stream"]]],
            ],
        ]]], status: 201)
    }

    func state(_ name: String, errors: [[String: String]] = [], warnings: [[String: String]] = []) -> HTTPResponse {
        json(["data": ["type": "buildUploads", "id": "upload-1", "attributes": ["state": ["state": name, "errors": errors, "warnings": warnings, "infos": []]]]])
    }

    @Test func uploadsCommitsAndWaits() throws {
        let (path, info) = try ipa()
        let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
        let transport = ScriptedTransport([
            ("GET \(base)/v1/apps?filter%5BbundleId%5D=org.nomac.upload&fields%5Bapps%5D=bundleId", json(["data": [
                ["type": "apps", "id": "111", "attributes": ["bundleId": "org.nomac.upload.widget"]],
                ["type": "apps", "id": "222", "attributes": ["bundleId": "org.nomac.upload"]],
            ]])),
            ("POST \(base)/v1/buildUploads", json(["data": ["type": "buildUploads", "id": "upload-1"]], status: 201)),
            ("POST \(base)/v1/buildUploadFiles", reservation(info.fileSize)),
            ("PUT https://upload.example/part1", HTTPResponse(status: 500)),
            ("PUT https://upload.example/part1", HTTPResponse(status: 200)),
            ("PUT https://upload.example/part2", HTTPResponse(status: 200)),
            ("PATCH \(base)/v1/buildUploadFiles/file-1", json(["data": ["type": "buildUploadFiles", "id": "file-1", "attributes": ["assetDeliveryState": ["state": "UPLOAD_COMPLETE"]]]])),
            ("GET \(base)/v1/buildUploads/upload-1?fields%5BbuildUploads%5D=state", state("PROCESSING")),
            ("GET \(base)/v1/buildUploads/upload-1?fields%5BbuildUploads%5D=state", state("COMPLETE", warnings: [["code": "90000", "description": "a warning"]])),
        ])
        var lines: [String] = [], sleeps: [TimeInterval] = []
        let uploader = BuildUploader(client: AppStoreConnectClient(key: key, transport: transport), transport: transport,
                                     log: { lines.append($0) }, sleep: { sleeps.append($0) })
        let result = try uploader.upload(ipa: path, info: info, appID: nil, wait: true)
        #expect(result == BuildUploader.Result(buildUploadID: "upload-1", state: "COMPLETE"))
        #expect(transport.script.isEmpty)
        #expect(sleeps == [30])

        let requests = transport.requests
        #expect(bodyObject(requests[1]) == ["data": ["type": "buildUploads",
            "attributes": ["cfBundleShortVersionString": "1.2", "cfBundleVersion": "7", "platform": "IOS"],
            "relationships": ["app": ["data": ["type": "apps", "id": "222"]]]]] as NSDictionary)
        #expect(bodyObject(requests[2]) == ["data": ["type": "buildUploadFiles",
            "attributes": ["assetType": "ASSET", "fileName": "App.ipa", "fileSize": info.fileSize, "uti": "com.apple.ipa"],
            "relationships": ["buildUpload": ["data": ["type": "buildUploads", "id": "upload-1"]]]]] as NSDictionary)
        #expect(requests[4].body == Data(bytes[0..<200]) && requests[5].body == Data(bytes[200...]))
        #expect(requests[5].headers == ["Content-Type": "application/octet-stream"])
        #expect(bodyObject(requests[6]) == ["data": ["type": "buildUploadFiles", "id": "file-1", "attributes": ["uploaded": true,
            "sourceFileChecksums": ["file": ["algorithm": "MD5", "hash": Insecure.MD5.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]]]]] as NSDictionary)
        for request in requests where request.url.hasPrefix(base) {
            #expect(request.headers["Authorization"]?.hasPrefix("Bearer ey") == true)
        }
        #expect(requests.filter { !$0.url.hasPrefix(base) }.allSatisfy { $0.headers["Authorization"] == nil })
        #expect(lines.contains("warning: 90000: a warning") && lines.last == "App Store Connect processed build upload upload-1")
    }

    @Test func reportsTheErrorsOfAFailedUpload() throws {
        let (path, info) = try ipa()
        let transport = ScriptedTransport([
            ("POST \(base)/v1/buildUploads", json(["data": ["type": "buildUploads", "id": "upload-1"]], status: 201)),
            ("POST \(base)/v1/buildUploadFiles", json(["data": ["type": "buildUploadFiles", "id": "file-1", "attributes": ["uploadOperations": [Any]()]]], status: 201)),
            ("PATCH \(base)/v1/buildUploadFiles/file-1", json(["data": ["type": "buildUploadFiles", "id": "file-1"]])),
            ("GET \(base)/v1/buildUploads/upload-1?fields%5BbuildUploads%5D=state", state("FAILED", errors: [["code": "90062", "description": "This bundle is invalid."]])),
        ])
        let uploader = BuildUploader(client: AppStoreConnectClient(key: key, transport: transport), transport: transport, log: { _ in }, sleep: { _ in })
        #expect(throws: NomacError("App Store Connect could not process build upload upload-1", notes: ["error: 90062: This bundle is invalid."])) {
            try uploader.upload(ipa: path, info: info, appID: "222", wait: true)
        }
    }

    @Test func rendersTheAPIsErrorResponse() throws {
        let (path, info) = try ipa()
        let transport = ScriptedTransport([
            ("POST \(base)/v1/buildUploads", json(["errors": [["id": "x", "status": "409", "code": "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE",
                                                              "title": "The provided entity includes an attribute with a value that has already been used",
                                                              "detail": "The bundle version must be higher than the previously uploaded version."]]], status: 409)),
        ])
        let uploader = BuildUploader(client: AppStoreConnectClient(key: key, transport: transport), transport: transport, log: { _ in }, sleep: { _ in })
        #expect(throws: NomacError("App Store Connect refused POST \(base)/v1/buildUploads (HTTP 409)", notes: [
            "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE: The provided entity includes an attribute with a value that has already been used: The bundle version must be higher than the previously uploaded version.",
        ])) {
            try uploader.upload(ipa: path, info: info, appID: "222", wait: false)
        }
    }

    @Test func stopsAfterAPartFailsThreeTimes() throws {
        let (path, info) = try ipa()
        let failure = ("PUT https://upload.example/part1", HTTPResponse(status: 503))
        let transport = ScriptedTransport([
            ("POST \(base)/v1/buildUploads", json(["data": ["type": "buildUploads", "id": "upload-1"]], status: 201)),
            ("POST \(base)/v1/buildUploadFiles", reservation(info.fileSize)),
            failure, failure, failure,
        ])
        let uploader = BuildUploader(client: AppStoreConnectClient(key: key, transport: transport), transport: transport, log: { _ in }, sleep: { _ in })
        #expect(throws: NomacError("App Store Connect did not take the part at offset 0 (HTTP 503)", path: path)) {
            try uploader.upload(ipa: path, info: info, appID: "222", wait: false)
        }
        #expect(transport.script.isEmpty)
    }

    @Test func refusesOperationsOutsideTheFile() throws {
        let document: [String: Any] = ["data": ["attributes": ["uploadOperations": [["method": "PUT", "url": "u", "offset": 10, "length": 100]]]]]
        #expect(throws: NomacError("App Store Connect's reservation has an upload operation nomac cannot follow")) {
            try BuildUploader.operations(of: document, fileSize: 50)
        }
    }

    @Test func dryRunPrintsEveryRequestAndNoToken() throws {
        let (path, info) = try ipa()
        var printed: [String] = []
        let transport = DryRunTransport { printed.append($0) }
        let uploader = BuildUploader(client: AppStoreConnectClient(key: key, transport: transport, now: { Date(timeIntervalSince1970: 1000) }),
                                     transport: transport, log: { _ in }, sleep: { _ in })
        let result = try uploader.upload(ipa: path, info: info, appID: nil, wait: false)
        #expect(result == BuildUploader.Result(buildUploadID: "<build-upload-id>", state: "PROCESSING"))
        let requests = printed.filter { !$0.hasPrefix("  token ") }
        #expect(requests.map { $0.split(separator: " ").prefix(2).joined(separator: " ") } == [
            "GET \(base)/v1/apps?filter%5BbundleId%5D=org.nomac.upload&fields%5Bapps%5D=bundleId",
            "POST \(base)/v1/buildUploads",
            "POST \(base)/v1/buildUploadFiles",
            "PUT https://<upload-url>",
            "PATCH \(base)/v1/buildUploadFiles/<build-upload-file-id>",
            "GET \(base)/v1/buildUploads/<build-upload-id>?fields%5BbuildUploads%5D=state",
        ])
        #expect(requests[1].hasSuffix(#" {"data":{"attributes":{"cfBundleShortVersionString":"1.2","cfBundleVersion":"7","platform":"IOS"},"relationships":{"app":{"data":{"id":"<app-id>","type":"apps"}}},"type":"buildUploads"}}"#))
        #expect(requests[3] == "PUT https://<upload-url> (\(info.fileSize) bytes)")
        #expect(printed[1] == #"  token {"alg":"ES256","kid":"KEY1","typ":"JWT"} {"aud":"appstoreconnect-v1","exp":1600,"iat":1000,"iss":"issuer"}"#)
    }
}
