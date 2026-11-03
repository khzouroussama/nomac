import Foundation
import NomacCore

/// A provisioning profile (`.mobileprovision`): a CMS SignedData whose content is an XML property
/// list (an Apple profile is DER with definite lengths, the property list an OCTET STRING in
/// the encapsulated content). Only a profile signed by Apple counts as installed
/// (`ProfileSignature`).
public struct ProvisioningProfile {
    /// The file's bytes, which an app embeds as `embedded.mobileprovision`.
    public let bytes: [UInt8]
    /// The file the profile was read from.
    public let path: String
    public let uuid: String
    public let name: String
    public let expirationDate: Date?
    /// The profile's entitlements, as a property list value.
    public let entitlements: PropertyListValue
    /// The certificates the profile lets sign, DER.
    public let developerCertificates: [[UInt8]]
    /// The UDIDs of the devices the profile lets an app run on (`ProvisionedDevices`).
    public let provisionedDevices: [String]
    /// Whether the profile lets an app run on any device (`ProvisionsAllDevices`, enterprise).
    public let provisionsAllDevices: Bool

    /// The SignedData's contents and the signed content, for `isSigned(byRootIn:)`.
    let signedData: [UInt8]
    let content: [UInt8]

    /// The SHA-256 of Apple Root CA's certificate (B0B1730E…01F024), the root of the chain that
    /// signs Apple's profiles.
    public static let appleRoots: Set<[UInt8]> = [[
        0xb0, 0xb1, 0x73, 0x0e, 0xcb, 0xc7, 0xff, 0x45, 0x05, 0x14, 0x2c, 0x49, 0xf1, 0x29, 0x5e, 0x6e,
        0xda, 0x6b, 0xca, 0xed, 0x7e, 0x2c, 0x68, 0xc5, 0xbe, 0x91, 0xb5, 0xa1, 0x10, 0x01, 0xf0, 0x24,
    ]]

    public init(bytes: [UInt8], path: String) throws {
        guard let contentInfo = DERReader.elements(bytes).first, contentInfo.tag == 0x30,
              let wrapper = DERReader.elements(contentInfo.content).first(where: { $0.tag == 0xa0 }),
              let signedData = DERReader.elements(wrapper.content).first, signedData.tag == 0x30,
              let encapsulated = DERReader.elements(signedData.content).first(where: { $0.tag == 0x30 }),
              let explicit = DERReader.elements(encapsulated.content).first(where: { $0.tag == 0xa0 }),
              let content = DERReader.elements(explicit.content).first, content.tag == 0x04,
              case .dictionary(let plist) = try PropertyListValue.parseXML(Data(content.content), path: path) else {
            throw NomacError("malformed provisioning profile", path: path)
        }
        guard case .string(let uuid)? = plist["UUID"], case .string(let name)? = plist["Name"] else {
            throw NomacError("provisioning profile without UUID or Name", path: path)
        }
        self.bytes = bytes
        self.path = path
        self.signedData = signedData.content
        self.content = content.content
        self.uuid = uuid
        self.name = name
        if case .date(let text)? = plist["ExpirationDate"] {
            expirationDate = ISO8601DateFormatter().date(from: text)
        } else {
            expirationDate = nil
        }
        entitlements = plist["Entitlements"] ?? .dictionary([:])
        if case .array(let certificates)? = plist["DeveloperCertificates"] {
            developerCertificates = certificates.compactMap { if case .data(let der) = $0 { der } else { nil } }
        } else {
            developerCertificates = []
        }
        if case .array(let devices)? = plist["ProvisionedDevices"] {
            provisionedDevices = devices.compactMap { if case .string(let udid) = $0 { udid } else { nil } }
        } else {
            provisionedDevices = []
        }
        if case .boolean(let all)? = plist["ProvisionsAllDevices"] { provisionsAllDevices = all } else { provisionsAllDevices = false }
    }

    /// The `application-identifier` entitlement: the team identifier, a dot and a bundle
    /// identifier, or a prefix of one ending in `*` for a wildcard profile.
    public var applicationIdentifier: String? {
        if case .dictionary(let entries) = entitlements, case .string(let identifier)? = entries["application-identifier"] { identifier } else { nil }
    }

    /// Whether `identity`'s certificate is one the profile lets sign.
    public func includes(_ identity: SigningIdentity) -> Bool { developerCertificates.contains(identity.certificate) }

    /// Whether the profile is signed by a chain ending at a root whose SHA-256 is in `roots`.
    public func isSigned(byRootIn roots: Set<[UInt8]>) -> Bool {
        ProfileSignature.isTrusted(signedData: signedData, content: content, roots: roots)
    }

    /// The application identifier without its team: what Xcode names the profile's app ID
    /// (`<prefix>.*` for a wildcard profile; docs/formats/ipa.md).
    public var appID: String? {
        applicationIdentifier.map { identifier in identifier.firstIndex(of: ".").map { String(identifier[identifier.index(after: $0)...]) } ?? identifier }
    }

    /// Whether the profile's app ID covers `bundleIdentifier`: the same, or a wildcard whose
    /// prefix begins it.
    public func covers(bundleIdentifier: String) -> Bool {
        appID.map { Self.authorizes(.string($0), .string(bundleIdentifier)) } ?? false
    }

    /// The folders Xcode keeps installed profiles in, under the home folder.
    public static var installedFolders: [String] {
        let home = NSHomeDirectory()
        return [home + "/Library/Developer/Xcode/UserData/Provisioning Profiles", home + "/Library/MobileDevice/Provisioning Profiles"]
    }

    /// The profile `specifier` names, by UUID or by name (the values of `provisioningProfiles` in
    /// export options, `PROVISIONING_PROFILE_SPECIFIER`), among the `.mobileprovision` files of
    /// `folders` signed by a root of `roots`; nil when there is none, as xcodebuild finds no
    /// profile whose signature is not Apple's.
    public static func installed(_ specifier: String, in folders: [String], roots: Set<[UInt8]> = appleRoots) throws -> ProvisioningProfile? {
        var matches: [ProvisioningProfile] = []
        for folder in folders where FileSystem.isDirectory(folder) {
            for file in try FileSystem.sortedContents(of: folder) where file.hasSuffix(".mobileprovision") {
                guard let data = FileManager.default.contents(atPath: folder + "/" + file) else { continue }
                let profile = try ProvisioningProfile(bytes: [UInt8](data), path: folder + "/" + file)
                if profile.uuid.caseInsensitiveCompare(specifier) == .orderedSame || profile.name == specifier, profile.isSigned(byRootIn: roots) {
                    matches.append(profile)
                }
            }
        }
        guard matches.count <= 1 else {
            throw NomacError("several provisioning profiles named \"\(specifier)\"", path: folders.joined(separator: ", "), exitStatus: 70)
        }
        return matches.first
    }

    /// The keys of `claimed` (a signature's entitlements) that `allowed` (a profile's) does not
    /// authorize, sorted.
    public static func unauthorized(_ claimed: [String: PropertyListValue], _ allowed: [String: PropertyListValue]) -> [String] {
        claimed.keys.sorted().filter { key in !(allowed[key].map { authorizes($0, claimed[key]!) } ?? false) }
    }

    /// Whether a profile's value authorizes a claimed one: a string ending in `*` authorizes
    /// the strings it begins, an array each value one of its elements authorizes, `true` any
    /// boolean; other values only themselves (TN3125).
    public static func authorizes(_ allowed: PropertyListValue, _ claimed: PropertyListValue) -> Bool {
        switch (allowed, claimed) {
        case (.string(let pattern), .string(let value)) where pattern.hasSuffix("*"):
            value.hasPrefix(pattern.dropLast())
        case (_, .array(let values)):
            values.allSatisfy { value in
                if case .array(let patterns) = allowed { patterns.contains { authorizes($0, value) } } else { authorizes(allowed, value) }
            }
        case (.array(let patterns), _):
            patterns.contains { authorizes($0, claimed) }
        case (.boolean(true), .boolean):
            true
        default:
            allowed == claimed
        }
    }
}
