import Foundation
import NomacCore
import NomacSigning
import SwiftBuild

/// The identity and profiles a build signs with: a PEM file holding the private key and the
/// certificates (`--keychain`, as `nomac codesign` takes it) and the folders of
/// `.mobileprovision` files (`--provisioning-profiles`, else Xcode's folders).
public struct SigningMaterial: Sendable {
    public let keychain: String
    public let profileFolders: [String]
    /// The roots a profile's signature must chain to (Apple's; tests sign with their own).
    public let profileRoots: Set<[UInt8]>

    public init(keychain: String, profileFolders: [String], profileRoots: Set<[UInt8]> = ProvisioningProfile.appleRoots) {
        self.keychain = keychain
        self.profileFolders = profileFolders
        self.profileRoots = profileRoots
    }
}

/// Swift Build's provisioning question answered for manual signing with a development identity
/// and profile, as Xcode 27.0 answers it (observed privately for B-302, docs/formats/ipa.md
/// "Signing with an identity and a profile"): a product that takes a profile is signed with the
/// identity's SHA-1, the profile embedded, and the entitlements `application-identifier`,
/// `com.apple.developer.team-identifier` and `get-task-allow`, with those of the project's
/// entitlements file the profile allows (an entitlement it lacks fails the target); a framework
/// with the identity alone. The PEM file reaches codesign as its keychain (`CODE_SIGN_KEYCHAIN`).
enum ManualSigning {
    struct Source {
        var targetName: String
        var signingIdentity: String
        var style: SWBProvisioningStyle
        var profileSupport: SWBProvisioningProfileSupport
        var profileSpecifier: String
        var profileUUID: String
        var teamID: String?
        var bundleIdentifier: String
        var projectEntitlements: [String: SWBPropertyListItem]?
        var productTypeEntitlements: [String: SWBPropertyListItem]
    }

    /// A refusal as Swift Build takes it: the first note is the recovery suggestion, which it
    /// prints after the description.
    static func refusal(_ error: NomacError) -> [String: String] {
        ["description": error.message, "recoverySuggestion": error.notes.first].compactMapValues { $0 }
    }

    static func provisioning(_ source: Source, material: SigningMaterial) -> SWBProvisioningTaskInputs {
        do {
            return try answer(source, material: material)
        } catch let error as NomacError {
            return SWBProvisioningTaskInputs(errors: ([error] + error.following).map(refusal))
        } catch {
            return SWBProvisioningTaskInputs(errors: [["description": "\(error)"]])
        }
    }

    private static func answer(_ source: Source, material: SigningMaterial) throws -> SWBProvisioningTaskInputs {
        guard source.style == .manual else {
            throw NomacError("automatic signing asks Apple's services, which nomac does not: sign with CODE_SIGN_STYLE=Manual and a profile (BACKLOG B-302)")
        }
        guard let pem = FileSystem.contents(atPath: material.keychain) else { throw NomacError("cannot read the identity file", path: material.keychain) }
        let identity = try SigningIdentity(named: source.signingIdentity, pem: String(decoding: pem, as: UTF8.self), path: material.keychain)
        guard source.profileSupport != .unsupported else {
            // A framework given PROVISIONING_PROFILE_SPECIFIER (`distribution_experiments.py`
            // `apple-profile`, the build with the setting for every target).
            guard source.profileSpecifier.isEmpty else {
                throw NomacError("\(source.targetName) does not support provisioning profiles.", notes: [
                    "\(source.targetName) does not support provisioning profiles, but provisioning profile \(source.profileSpecifier) has been manually specified. Set the provisioning profile value to \"Automatic\" in the build settings editor.",
                ])
            }
            return SWBProvisioningTaskInputs(identityHash: identity.certificateSHA1, identityName: identity.commonName, keychainPath: material.keychain)
        }
        let specifier = source.profileSpecifier.isEmpty ? source.profileUUID : source.profileSpecifier
        guard !specifier.isEmpty else {
            throw NomacError("manual signing of \(source.bundleIdentifier) needs a profile: set PROVISIONING_PROFILE_SPECIFIER")
        }
        // Only a profile Apple signed is installed; the profile must cover the bundle identifier
        // and include the identity's certificate, both reported (`distribution_experiments.py`
        // `apple-profile`, builds with manual signing).
        let team = source.teamID ?? ""
        guard let profile = try ProvisioningProfile.installed(specifier, in: material.profileFolders, roots: material.profileRoots) else {
            throw NomacError("No profile for team '\(team)' matching '\(specifier)' found", notes: [
                "Xcode couldn't find any provisioning profiles matching '\(team)/\(specifier)'. Install the profile (by dragging and dropping it onto Xcode's dock item) or select a different one in the Signing & Capabilities tab of the target editor.",
            ])
        }
        let problems = (profile.covers(bundleIdentifier: source.bundleIdentifier) ? [] : [
            NomacError("Provisioning profile \"\(profile.name)\" has app ID \"\(profile.appID ?? "")\", which does not match the bundle ID \"\(source.bundleIdentifier)\"."),
        ]) + (profile.includes(identity) ? [] : [
            NomacError("Provisioning profile \"\(profile.name)\" doesn't include signing certificate \"\(identity.commonName)\"."),
        ])
        if var first = problems.first {
            first.following = Array(problems.dropFirst())
            throw first
        }
        guard case .dictionary(let profileEntitlements) = profile.entitlements, profileEntitlements["get-task-allow"] == .boolean(true),
              let applicationIdentifier = profile.applicationIdentifier, let dot = applicationIdentifier.firstIndex(of: ".") else {
            throw NomacError("only development profiles are observed (\"\(profile.name)\" lacks get-task-allow; BACKLOG B-302)")
        }
        let profileTeam = String(applicationIdentifier[..<dot])
        if !team.isEmpty, team != profileTeam {
            throw NomacError("the profile \"\(profile.name)\" is for team \(profileTeam), not DEVELOPMENT_TEAM \(team)")
        }
        // The entitlements file's own, settings expanded, each one the profile must allow; then the
        // three development ones. A product type's entitlements (an App Clip's) the profile lacks
        // fail the target first; ones it allows are not observed.
        let missingProductTypeKeys = source.productTypeEntitlements.keys.filter { profileEntitlements[$0] == nil }.sorted()
        guard missingProductTypeKeys.count == source.productTypeEntitlements.count else {
            throw NomacError("how Xcode merges a product type's entitlements with a profile that allows them is not observed yet (BACKLOG B-302)")
        }
        var signed: [String: SWBPropertyListItem] = [:]
        var unauthorized: [String] = []
        for (key, value) in source.projectEntitlements ?? [:] {
            let expanded = try expand(value, prefix: "\(profileTeam).", bundleIdentifier: source.bundleIdentifier)
            guard let allowed = profileEntitlements[key], let claimed = Self.value(expanded), ProvisioningProfile.authorizes(allowed, claimed) else {
                unauthorized.append(key)
                continue
            }
            signed[key] = expanded
        }
        guard unauthorized.isEmpty, missingProductTypeKeys.isEmpty else {
            let refused = unauthorized.sorted()
            let notFound = missingProductTypeKeys.map {
                "Entitlement \($0) not found and could not be included in profile. This likely is not a valid entitlement and should be removed from your entitlements file."
            }
            let capabilities = (missingProductTypeKeys + refused).compactMap { key in
                Self.capabilities[key].map { "Provisioning profile \"\(profile.name)\" doesn't include the \($0) capability." }
            }
            let entitlements = refused.map { "Provisioning profile \"\(profile.name)\" doesn't include the \($0) entitlement." }
            return SWBProvisioningTaskInputs(errors: (capabilities + notFound + entitlements).map { ["description": $0] })
        }
        signed["application-identifier"] = .plString("\(profileTeam).\(source.bundleIdentifier)")
        signed["com.apple.developer.team-identifier"] = .plString(profileTeam)
        signed["get-task-allow"] = .plBool(true)
        return SWBProvisioningTaskInputs(
            identityHash: identity.certificateSHA1, identityName: identity.commonName, profileName: profile.name, profileUUID: profile.uuid,
            profilePath: profile.path, signedEntitlements: signed,
            appIdentifierPrefix: "\(profileTeam).", teamIdentifierPrefix: "\(profileTeam).", keychainPath: material.keychain)
    }

    /// The capability Xcode names beside an entitlement a profile lacks (observed: app groups, and
    /// an App Clip's product type entitlement). Xcode lists the capabilities first, then the
    /// product type's missing entitlements, then the file's.
    static let capabilities = ["com.apple.security.application-groups": "App Groups", "com.apple.developer.on-demand-install-capable": "App Clip"]

    /// `value` with `$(AppIdentifierPrefix)` and `$(TeamIdentifierPrefix)` replaced by the team's
    /// prefix and `$(PRODUCT_BUNDLE_IDENTIFIER)` by the bundle's identifier, as Xcode's answer has
    /// them (observed: a keychain group of both); other build settings are not available here.
    static func expand(_ value: SWBPropertyListItem, prefix: String, bundleIdentifier: String) throws -> SWBPropertyListItem {
        switch value {
        case .plString(let text):
            let expanded = text.replacingOccurrences(of: "$(AppIdentifierPrefix)", with: prefix)
                .replacingOccurrences(of: "$(TeamIdentifierPrefix)", with: prefix)
                .replacingOccurrences(of: "$(PRODUCT_BUNDLE_IDENTIFIER)", with: bundleIdentifier)
            guard !expanded.contains("$(") else {
                throw NomacError("build settings other than the identifier prefixes and PRODUCT_BUNDLE_IDENTIFIER in an entitlements file are not observed yet (BACKLOG B-302): \(text)")
            }
            return .plString(expanded)
        case .plArray(let elements):
            return .plArray(try elements.map { try expand($0, prefix: prefix, bundleIdentifier: bundleIdentifier) })
        case .plDict(let entries):
            return .plDict(try entries.mapValues { try expand($0, prefix: prefix, bundleIdentifier: bundleIdentifier) })
        default:
            return value
        }
    }

    /// An entitlement's value as NomacSigning compares them; nil for kinds entitlements do not use.
    static func value(_ item: SWBPropertyListItem) -> PropertyListValue? {
        switch item {
        case .plString(let text): .string(text)
        case .plBool(let flag): .boolean(flag)
        case .plInt(let number): .integer(Int64(number))
        case .plArray(let elements): elements.allSatisfy { value($0) != nil } ? .array(elements.compactMap(value)) : nil
        case .plDict(let entries): entries.values.allSatisfy { value($0) != nil } ? .dictionary(entries.compactMapValues(value)) : nil
        default: nil
        }
    }
}
