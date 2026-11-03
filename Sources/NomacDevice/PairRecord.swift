import Foundation
import NomacCore
import NomacSigning

/// The host's side of a pairing with a device, as usbmuxd keeps it (a property list): the
/// identifiers lockdownd's sessions name, and the host's certificate and key in PEM for their
/// TLS. Held in memory only.
public struct PairRecord: Sendable {
    public let hostID: String
    public let systemBUID: String
    public let hostCertificate: [UInt8]
    public let hostPrivateKey: [UInt8]

    public init(bytes: [UInt8]) throws {
        let fields = try PropertyListMessages.dictionary(bytes, source: "the pair record")
        guard case .string(let hostID)? = fields["HostID"], case .string(let systemBUID)? = fields["SystemBUID"],
              case .data(let certificate)? = fields["HostCertificate"], case .data(let key)? = fields["HostPrivateKey"] else {
            throw NomacError("the pair record lacks HostID, SystemBUID, HostCertificate or HostPrivateKey")
        }
        self.hostID = hostID
        self.systemBUID = systemBUID
        hostCertificate = certificate
        hostPrivateKey = key
    }
}
