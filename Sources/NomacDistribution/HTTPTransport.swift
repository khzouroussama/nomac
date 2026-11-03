import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NomacCore

public struct HTTPRequest {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

/// Sends HTTP requests: URLSession for App Store Connect, a recording in tests and for
/// `nomac upload --dry-run`.
public protocol HTTPTransport {
    func send(_ request: HTTPRequest) throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: HTTPRequest) throws -> HTTPResponse {
        guard let url = URL(string: request.url) else { throw NomacError("invalid URL \(request.url)") }
        var urlRequest = URLRequest(url: url, timeoutInterval: 300)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body
        let box = ReplyBox()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            box.data = data
            box.status = (response as? HTTPURLResponse)?.statusCode
            box.error = error
            done.signal()
        }.resume()
        done.wait()
        if let error = box.error { throw NomacError("cannot reach \(url.host ?? request.url): \(error.localizedDescription)") }
        return HTTPResponse(status: box.status ?? 0, body: box.data ?? Data())
    }

    private final class ReplyBox: @unchecked Sendable {
        var data: Data?
        var status: Int?
        var error: Error?
    }
}

/// JSON as the API's requests are written: keys sorted, slashes not escaped.
enum JSON {
    static func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func object(_ data: Data, source: String) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NomacError("\(source) is not a JSON object")
        }
        return object
    }
}
