import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NomacCore
import NomacSigning

/// Personalizing the Developer Disk Image for one device: the build identity of the image's
/// `BuildManifest.plist` that matches the device's board and chip, the request to Apple's TSS
/// server that signs it for the device's ECID and nonce, and the ticket (an IM4M) the server
/// returns (ADR 0403, docs/formats/ddi.md).
public enum Personalization {
    /// Apple's TSS server. Over TLS it presents a chain ending at a private root, which a Linux trust
    /// store refuses ("self-signed certificate in certificate chain": Ubuntu 24.04, 2026-11-07), so
    /// off macOS the request goes over plain HTTP, which answers the same and which libimobiledevice's
    /// and pymobiledevice3's requests use. The ticket is signed and the device checks it; the
    /// request's device identifiers (the ECID) cross the network in the clear (ADR 0403).
    public static let server: URL = {
        #if os(macOS)
        URL(string: "https://gs.apple.com/TSS/controller?action=2")!
        #else
        URL(string: "http://gs.apple.com/TSS/controller?action=2")!
        #endif
    }()

    /// The build identity for the device whose `QueryPersonalizationIdentifiers` reply is
    /// `identifiers`: `ApBoardID` and `ApChipID` (hexadecimal strings) equal to its `BoardId` and
    /// `ChipID`, with a `PersonalizedDMG`.
    public static func buildIdentity(manifest: [String: PropertyListValue], identifiers: [String: PropertyListValue]) throws -> [String: PropertyListValue] {
        guard case .integer(let board)? = identifiers["BoardId"], case .integer(let chip)? = identifiers["ChipID"] else {
            throw NomacError("the device's personalization identifiers lack BoardId or ChipID")
        }
        guard case .array(let identities)? = manifest["BuildIdentities"] else { throw NomacError("the build manifest has no BuildIdentities") }
        for case .dictionary(let identity) in identities {
            guard hexadecimal(identity["ApBoardID"]) == board, hexadecimal(identity["ApChipID"]) == chip,
                  case .dictionary(let components)? = identity["Manifest"], components["PersonalizedDMG"] != nil else { continue }
            return identity
        }
        throw NomacError(String(format: "the Developer Disk Image has no personalized disk image for board 0x%02X and chip 0x%04X", board, chip), notes: [
            "an Xcode newer than this device may list it; a device too new for any such image takes only the cryptex image, which nomac cannot install yet (BACKLOG B-403)",
            "--no-launch installs the app without launching it",
        ])
    }

    /// The image and trust cache paths, relative to the build manifest's folder.
    public static func paths(identity: [String: PropertyListValue]) throws -> (image: String, trustCache: String) {
        func path(_ component: String) throws -> String {
            guard case .dictionary(let components)? = identity["Manifest"], case .dictionary(let entry)? = components[component],
                  case .dictionary(let info)? = entry["Info"], case .string(let path)? = info["Path"] else {
                throw NomacError("the build identity has no \(component) path")
            }
            return path
        }
        return (try path("PersonalizedDMG"), try path("LoadableTrustCache"))
    }

    /// The TSS request: the host's tags, the device's `Ap,` identifiers, board, chip, ECID and
    /// nonce in production and secure mode, and every trusted component of the identity without
    /// its `Info`, with the trust cache's restore request rules applied (`EPRO`, `ESEC`).
    public static func request(identity: [String: PropertyListValue], identifiers: [String: PropertyListValue], nonce: [UInt8],
                               uuid: UUID = UUID()) throws -> [String: PropertyListValue] {
        guard case .integer(let board)? = identifiers["BoardId"], case .integer(let chip)? = identifiers["ChipID"],
              case .integer(let ecid)? = identifiers["UniqueChipID"] else {
            throw NomacError("the device's personalization identifiers lack BoardId, ChipID or UniqueChipID")
        }
        var request: [String: PropertyListValue] = [
            "@ApImg4Ticket": .boolean(true), "@BBTicket": .boolean(true), "@HostPlatformInfo": .string("mac"),
            "@UUID": .string(uuid.uuidString), "@VersionInfo": .string("libauthinstall-1033.0.2"),
            "ApBoardID": .integer(board), "ApChipID": .integer(chip), "ApECID": .integer(ecid), "ApNonce": .data(nonce),
            "ApProductionMode": .boolean(true), "ApSecurityDomain": .integer(1), "ApSecurityMode": .boolean(true),
            "SepNonce": .data([UInt8](repeating: 0, count: 20)), "UID_MODE": .boolean(false),
        ]
        for (key, value) in identifiers where key.hasPrefix("Ap,") { request[key] = value }
        guard case .dictionary(let components)? = identity["Manifest"] else { throw NomacError("the build identity has no Manifest") }
        let rules: [PropertyListValue]
        if case .dictionary(let trustCache)? = components["LoadableTrustCache"], case .dictionary(let info)? = trustCache["Info"],
           case .array(let found)? = info["RestoreRequestRules"] {
            rules = found
        } else {
            rules = []
        }
        let parameters: [String: PropertyListValue] = ["ApProductionMode": .boolean(true), "ApSecurityMode": .boolean(true), "ApSupportsImg4": .boolean(true)]
        for (name, component) in components {
            guard case .dictionary(var entry) = component, entry["Info"] != nil, entry["Trusted"] == .boolean(true) else { continue }
            entry["Info"] = nil
            apply(rules, parameters: parameters, to: &entry)
            if entry["Digest"] == nil { entry["Digest"] = .data([]) }
            request[name] = .dictionary(entry)
        }
        return request
    }

    /// A restore request rule's actions apply when each of its conditions equals the parameter
    /// it names; an action of 255 is left out.
    static func apply(_ rules: [PropertyListValue], parameters: [String: PropertyListValue], to entry: inout [String: PropertyListValue]) {
        let names = ["ApRawProductionMode": "ApProductionMode", "ApCurrentProductionMode": "ApProductionMode",
                     "ApRawSecurityMode": "ApSecurityMode", "ApRequiresImage4": "ApSupportsImg4",
                     "ApDemotionPolicyOverride": "DemotionPolicy", "ApInRomDFU": "ApInRomDFU"]
        for case .dictionary(let rule) in rules {
            guard case .dictionary(let conditions)? = rule["Conditions"], case .dictionary(let actions)? = rule["Actions"],
                  conditions.allSatisfy({ key, value in names[key].flatMap { parameters[$0] } == value }) else { continue }
            for (key, value) in actions where value != .integer(255) { entry[key] = value }
        }
    }

    /// The ticket of the server's reply, `STATUS=0&MESSAGE=SUCCESS&REQUEST_STRING=<plist>`; a
    /// refusal is `STATUS=<n>&MESSAGE=<text>`.
    public static func ticket(reply: String) throws -> [UInt8] {
        guard reply.hasPrefix("STATUS=0&"), let range = reply.range(of: "&REQUEST_STRING=") else {
            let message = reply.components(separatedBy: "&").first { $0.hasPrefix("MESSAGE=") }.map { String($0.dropFirst("MESSAGE=".count)) } ?? reply
            throw NomacError("Apple's TSS server refused to personalize the Developer Disk Image: \(message)")
        }
        let fields = try PropertyListMessages.dictionary(Array(reply[range.upperBound...].utf8), source: "the TSS reply")
        guard case .data(let ticket)? = fields["ApImg4Ticket"] else { throw NomacError("the TSS reply has no ApImg4Ticket") }
        return ticket
    }

    /// Sends `request` to Apple's TSS server and returns the ticket.
    public static func fetchTicket(_ request: [String: PropertyListValue]) throws -> [UInt8] {
        var urlRequest = URLRequest(url: server, timeoutInterval: 60)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("InetURL/1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        urlRequest.httpBody = Data(PropertyListValue.xmlDocument(.dictionary(request)))
        let box = ReplyBox()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: urlRequest) { data, _, error in
            box.data = data
            box.error = error
            done.signal()
        }.resume()
        done.wait()
        if let error = box.error { throw NomacError("cannot reach Apple's TSS server: \(error.localizedDescription)", notes: ["mounting the Developer Disk Image needs gs.apple.com once per device and image"]) }
        return try ticket(reply: String(decoding: box.data ?? Data(), as: UTF8.self))
    }

    private final class ReplyBox: @unchecked Sendable {
        var data: Data?
        var error: Error?
    }

    static func hexadecimal(_ value: PropertyListValue?) -> Int64? {
        switch value {
        case .string(let text)?: Int64(text.hasPrefix("0x") ? String(text.dropFirst(2)) : text, radix: 16)
        case .integer(let number)?: number
        default: nil
        }
    }
}
