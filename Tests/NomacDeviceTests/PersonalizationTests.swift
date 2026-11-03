import Foundation
import NomacSigning
import Testing
@testable import NomacDevice

/// The personalization of the Developer Disk Image (ADR 0403), on a build identity shaped as
/// Xcode 27.0's `BuildManifest.plist` has them and the identifiers an iPhone answers with.
@Suite struct PersonalizationTests {
    static let identifiers: [String: PropertyListValue] = [
        "BoardId": .integer(14), "ChipID": .integer(0x8140), "UniqueChipID": .integer(1234), "Ap,SikaFuse": .integer(0),
        "SecurityDomain": .integer(1), "CertificateProductionStatus": .boolean(true),
    ]

    static func identity(board: String, chip: String) -> PropertyListValue {
        let rules: PropertyListValue = .array([
            .dictionary(["Actions": .dictionary(["EPRO": .boolean(false)]),
                         "Conditions": .dictionary(["ApCurrentProductionMode": .boolean(false), "ApRequiresImage4": .boolean(true)])]),
            .dictionary(["Actions": .dictionary(["EPRO": .boolean(true)]),
                         "Conditions": .dictionary(["ApCurrentProductionMode": .boolean(true), "ApRequiresImage4": .boolean(true)])]),
            .dictionary(["Actions": .dictionary(["ESEC": .boolean(true)]),
                         "Conditions": .dictionary(["ApRawSecurityMode": .boolean(true), "ApRequiresImage4": .boolean(true)])]),
            .dictionary(["Actions": .dictionary(["EPRO": .boolean(false)]),
                         "Conditions": .dictionary(["ApCurrentProductionMode": .boolean(true), "ApDemotionPolicyOverride": .string("Demote"),
                                                    "ApInRomDFU": .boolean(true), "ApRequiresImage4": .boolean(true)])]),
        ])
        return .dictionary([
            "ApBoardID": .string(board), "ApChipID": .string(chip),
            "Manifest": .dictionary([
                "LoadableTrustCache": .dictionary(["Digest": .data([1]), "Trusted": .boolean(true),
                                                   "Info": .dictionary(["Path": .string("Firmware/image.dmg.trustcache"), "RestoreRequestRules": rules])]),
                "PersonalizedDMG": .dictionary(["Digest": .data([2]), "Name": .string("DeveloperDiskImage"), "Trusted": .boolean(true),
                                                "Info": .dictionary(["Path": .string("image.dmg")])]),
            ]),
        ])
    }

    static let manifest: [String: PropertyListValue] = ["BuildIdentities": .array([identity(board: "0x0C", chip: "0x8140"), identity(board: "0x0E", chip: "0x8140")])]

    @Test func picksTheIdentityOfTheDevicesBoardAndChip() throws {
        let identity = try Personalization.buildIdentity(manifest: Self.manifest, identifiers: Self.identifiers)
        #expect(identity["ApBoardID"] == .string("0x0E"))
        #expect(try Personalization.paths(identity: identity) == (image: "image.dmg", trustCache: "Firmware/image.dmg.trustcache"))
        #expect(throws: (any Error).self) { try Personalization.buildIdentity(manifest: Self.manifest, identifiers: ["BoardId": .integer(1), "ChipID": .integer(2)]) }
    }

    @Test func requestNamesTheDeviceAndTheTrustedComponents() throws {
        let identity = try Personalization.buildIdentity(manifest: Self.manifest, identifiers: Self.identifiers)
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let request = try Personalization.request(identity: identity, identifiers: Self.identifiers, nonce: [9, 9], uuid: uuid)
        #expect(request["ApBoardID"] == .integer(14) && request["ApChipID"] == .integer(0x8140) && request["ApECID"] == .integer(1234))
        #expect(request["ApNonce"] == .data([9, 9]) && request["SepNonce"] == .data([UInt8](repeating: 0, count: 20)))
        #expect(request["Ap,SikaFuse"] == .integer(0) && request["SecurityDomain"] == nil)
        #expect(request["@ApImg4Ticket"] == .boolean(true) && request["@UUID"] == .string(uuid.uuidString))
        #expect(request["LoadableTrustCache"] == .dictionary(["Digest": .data([1]), "Trusted": .boolean(true), "EPRO": .boolean(true), "ESEC": .boolean(true)]))
        #expect(request["PersonalizedDMG"] == .dictionary(["Digest": .data([2]), "Name": .string("DeveloperDiskImage"), "Trusted": .boolean(true),
                                                            "EPRO": .boolean(true), "ESEC": .boolean(true)]))
    }

    @Test func ticketOfTheServersReply() throws {
        let plist = String(decoding: PropertyListValue.xmlDocument(.dictionary(["ApImg4Ticket": .data([0x30, 0x82])])), as: UTF8.self)
        #expect(try Personalization.ticket(reply: "STATUS=0&MESSAGE=SUCCESS&REQUEST_STRING=" + plist) == [0x30, 0x82])
        // gs.apple.com's answer to a request without a device (2026-11-02).
        #expect(throws: (any Error).self) { try Personalization.ticket(reply: "STATUS=94&MESSAGE=This device isn't eligible for the requested build.") }
    }

    @Test func uploadsAndMountsWithTheTicket() throws {
        let stream = ReplayStream(replies: [["Status": .string("ReceiveBytesAck")], ["Status": .string("Complete")]])
        try MobileImageMounter.upload(image: [7, 7, 7], ticket: [1], on: stream)
        let written = ReplayStream(bytes: stream.written)
        #expect(try PropertyListMessages.receive(from: written, source: "test") == [
            "Command": .string("ReceiveBytes"), "ImageType": .string("Personalized"), "ImageSize": .integer(3), "ImageSignature": .data([1]),
        ])
        #expect(try written.read(3) == [7, 7, 7])

        let mount = ReplayStream(replies: [["Status": .string("Complete")]])
        try MobileImageMounter.mount(ticket: [1], trustCache: [2], on: mount)
        #expect(try PropertyListMessages.receive(from: ReplayStream(bytes: mount.written), source: "test") == [
            "Command": .string("MountImage"), "ImageType": .string("Personalized"), "ImageSignature": .data([1]), "ImageTrustCache": .data([2]),
        ])
        #expect(throws: (any Error).self) {
            try MobileImageMounter.mount(ticket: [], trustCache: [], on: ReplayStream(replies: [["Error": .string("ImageMountFailed")]]))
        }
    }
}
