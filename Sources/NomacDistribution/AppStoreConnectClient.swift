import Foundation
import NomacCore

/// Requests to the App Store Connect API (Apple's OpenAPI specification 4.5.1), each with a
/// fresh bearer token of `key`; documents in and out are JSON:API objects.
public struct AppStoreConnectClient {
    public static let base = "https://api.appstoreconnect.apple.com"

    let key: AppStoreConnectKey
    let transport: HTTPTransport
    let now: () -> Date

    public init(key: AppStoreConnectKey, transport: HTTPTransport, now: @escaping () -> Date = Date.init) {
        self.key = key
        self.transport = transport
        self.now = now
    }

    /// `path` with its query, the brackets of `filter[...]` and `fields[...]` percent-encoded.
    static func url(_ path: String, query: [(String, String)] = []) -> String {
        guard !query.isEmpty else { return base + path }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "[]&=+")
        func encoded(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text }
        return base + path + "?" + query.map { encoded($0.0) + "=" + encoded($0.1) }.joined(separator: "&")
    }

    func get(_ path: String, query: [(String, String)] = []) throws -> [String: Any] {
        try send("GET", Self.url(path, query: query), body: nil)
    }

    func post(_ path: String, _ document: [String: Any]) throws -> [String: Any] {
        try send("POST", Self.url(path), body: document)
    }

    func patch(_ path: String, _ document: [String: Any]) throws -> [String: Any] {
        try send("PATCH", Self.url(path), body: document)
    }

    private func send(_ method: String, _ url: String, body: [String: Any]?) throws -> [String: Any] {
        var headers = ["Authorization": "Bearer " + (try key.token(issuedAt: now()))]
        if body != nil { headers["Content-Type"] = "application/json" }
        let response = try transport.send(HTTPRequest(method: method, url: url, headers: headers, body: try body.map(JSON.data)))
        guard (200..<300).contains(response.status) else { throw Self.error(response, method: method, url: url) }
        return response.body.isEmpty ? [:] : try JSON.object(response.body, source: "App Store Connect's answer to \(method) \(url)")
    }

    /// An `ErrorResponse`'s errors (`status`, `code`, `title`, `detail`) as one error.
    static func error(_ response: HTTPResponse, method: String, url: String) -> NomacError {
        let errors = (try? JSON.object(response.body, source: ""))?["errors"] as? [[String: Any]] ?? []
        let lines = errors.map { error in
            [error["code"], error["title"], error["detail"]].compactMap { $0 as? String }.joined(separator: ": ")
        }
        return NomacError("App Store Connect refused \(method) \(url) (HTTP \(response.status))", notes: lines)
    }
}
