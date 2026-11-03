import Foundation
import NomacCore

/// `nomac upload --dry-run`: prints each request instead of sending it (method, URL and the JSON
/// body on one line, a part's size; the bearer token's header and claims, never the token) and
/// answers as App Store Connect would with placeholder IDs and one part for the whole file, where
/// a real reservation may list several.
public final class DryRunTransport: HTTPTransport {
    let print: (String) -> Void

    public init(print: @escaping (String) -> Void) {
        self.print = print
    }

    public func send(_ request: HTTPRequest) throws -> HTTPResponse {
        let isJSON = request.headers["Content-Type"] == "application/json"
        let body = request.body.map { isJSON ? " " + String(decoding: $0, as: UTF8.self) : " (\($0.count) bytes)" } ?? ""
        print("\(request.method) \(request.url)\(body)")
        if let authorization = request.headers["Authorization"], let token = authorization.split(separator: " ").last {
            let parts = token.split(separator: ".").prefix(2).map { Self.decodeBase64URL(String($0)) }
            print("  token " + parts.joined(separator: " "))
        }
        let path = String(request.url.dropFirst(AppStoreConnectClient.base.count)).split(separator: "?").first.map(String.init) ?? ""
        let answer: [String: Any]
        switch (request.method, path) {
        case ("GET", "/v1/apps"):
            let bundleID = URLComponents(string: request.url)?.queryItems?.first { $0.name == "filter[bundleId]" }?.value ?? ""
            answer = ["data": [["type": "apps", "id": "<app-id>", "attributes": ["bundleId": bundleID]]]]
        case ("POST", "/v1/buildUploads"):
            answer = ["data": ["type": "buildUploads", "id": "<build-upload-id>"]]
        case ("POST", "/v1/buildUploadFiles"):
            let attributes = ((try? JSON.object(request.body ?? Data(), source: ""))?["data"] as? [String: Any])?["attributes"] as? [String: Any]
            let size = attributes?["fileSize"] as? Int ?? 0
            answer = ["data": ["type": "buildUploadFiles", "id": "<build-upload-file-id>", "attributes": ["uploadOperations": [
                ["method": "PUT", "url": "https://<upload-url>", "offset": 0, "length": size, "partNumber": 1, "requestHeaders": [[String: String]]()],
            ]]]]
        case ("PUT", _):
            return HTTPResponse(status: 200)
        case ("PATCH", _):
            answer = ["data": ["type": "buildUploadFiles", "id": "<build-upload-file-id>", "attributes": ["assetDeliveryState": ["state": "UPLOAD_COMPLETE"]]]]
        default:
            answer = ["data": ["type": "buildUploads", "id": "<build-upload-id>", "attributes": ["state": ["state": "PROCESSING"]]]]
        }
        return HTTPResponse(status: 200, body: try JSON.data(answer))
    }

    static func decodeBase64URL(_ text: String) -> String {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64).map { String(decoding: $0, as: UTF8.self) } ?? text
    }
}
