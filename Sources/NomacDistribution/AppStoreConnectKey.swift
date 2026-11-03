import Crypto
import Foundation
import NomacCore

/// An App Store Connect API key (docs/formats/app-store-connect-upload.md "Authentication"): its
/// key ID, the issuer ID of a team key (nil for an individual key) and the P-256 private key of
/// its `AuthKey_<key ID>.p8` file, which signs the JSON Web Token of every API request.
public struct AppStoreConnectKey {
    public let keyID: String
    public let issuer: String?
    let privateKey: P256.Signing.PrivateKey

    /// How long a token is valid: App Store Connect refuses tokens that expire more than 20
    /// minutes after they are issued ("Generating Tokens for API Requests"); each request gets
    /// its own.
    static let lifetime: TimeInterval = 600

    public init(keyID: String, issuer: String?, pem: String, path: String) throws {
        do {
            privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw NomacError("not an App Store Connect API private key (a P-256 key in PEM)", path: path)
        }
        self.keyID = keyID
        self.issuer = issuer
    }

    /// The folders altool searches for `AuthKey_<key ID>.p8` when given only `--api-key`, in its
    /// order (`altool --help`, Xcode 27.0): `./private_keys`, `~/private_keys`, `~/.private_keys`,
    /// `~/.appstoreconnect/private_keys`, then `$API_PRIVATE_KEYS_DIR`.
    public static func searchFolders(current: String, home: String, environment: [String: String]) -> [String] {
        [current + "/private_keys", home + "/private_keys", home + "/.private_keys", home + "/.appstoreconnect/private_keys"]
            + (environment["API_PRIVATE_KEYS_DIR"].map { [$0] } ?? [])
    }

    /// The key `keyID` names, read from `p8Path` or else from the first `AuthKey_<key ID>.p8` of
    /// `folders`.
    public static func load(keyID: String, issuer: String?, p8Path: String?, folders: [String]) throws -> AppStoreConnectKey {
        let candidates = p8Path.map { [$0] } ?? folders.map { $0 + "/AuthKey_\(keyID).p8" }
        guard let path = candidates.first(where: FileSystem.isFile), let data = FileManager.default.contents(atPath: path) else {
            throw NomacError("no private key file for API key \(keyID)", notes: candidates.map { "looked for \($0)" })
        }
        return try AppStoreConnectKey(keyID: keyID, issuer: issuer, pem: String(decoding: data, as: UTF8.self), path: path)
    }

    /// The token's header and claims, as App Store Connect documents them: a team key names its
    /// issuer (`iss`), an individual key the subject `user` instead.
    func header() -> [String: Any] { ["alg": "ES256", "kid": keyID, "typ": "JWT"] }

    func claims(issuedAt: Date) -> [String: Any] {
        let issued = Int(issuedAt.timeIntervalSince1970)
        var claims: [String: Any] = ["aud": "appstoreconnect-v1", "iat": issued, "exp": issued + Int(Self.lifetime)]
        if let issuer { claims["iss"] = issuer } else { claims["sub"] = "user" }
        return claims
    }

    /// The signed token (RFC 7519): base64url header and claims, and the ES256 signature as the
    /// 64 bytes of `r` and `s` (RFC 7518, section 3.4).
    public func token(issuedAt: Date) throws -> String {
        let signingInput = try Self.base64URL(JSON.data(header())) + "." + Self.base64URL(JSON.data(claims(issuedAt: issuedAt)))
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return signingInput + "." + Self.base64URL(signature.rawRepresentation)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
