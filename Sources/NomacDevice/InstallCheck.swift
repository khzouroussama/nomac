import Foundation
import NomacCore
import NomacSigning

/// What a signed app needs before a device accepts it, by the rules Apple documents for
/// provisioning profiles (TN3125, "Inside Code Signing: Provisioning Profiles"): an embedded
/// profile, unexpired, whose App ID covers the app's bundle identifier and whose devices
/// include the device, and whose entitlements authorize those the app's signature claims.
public enum InstallCheck {
    /// What would stop the app after it installs, without a device refusing it: an app built with
    /// the iOS 27 SDK or later and no `UIApplicationSceneManifest` does not launch, as TN3187
    /// ("Migrating to the UIKit scene-based life cycle") announces for the release after iOS 26;
    /// observed on iOS 27.0.1 as UIKit's `_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`
    /// trap at launch. An app delegate may still supply scenes in code, so this is a warning.
    public static func warnings(app: String) throws -> [String] {
        let info = try PropertyLists.readDictionary(at: app + "/Info.plist")
        guard info["UIApplicationSceneManifest"] == nil, let version = info["DTPlatformVersion"] as? String,
              let major = Int(version.prefix { $0 != "." }), major >= 27 else { return [] }
        return ["the app has no UIApplicationSceneManifest and is built with the iOS \(version) SDK: unless its app delegate configures scenes in code, it stops at launch (TN3187)"]
    }

    public static func problems(app: String, device udid: String?, at date: Date) throws -> [String] {
        let info = try PropertyLists.readDictionary(at: app + "/Info.plist")
        guard let bundleIdentifier = info["CFBundleIdentifier"] as? String else {
            return ["the app's Info.plist has no CFBundleIdentifier"]
        }
        let profilePath = app + "/embedded.mobileprovision"
        guard let bytes = FileSystem.contents(atPath: profilePath) else {
            return ["the app has no embedded.mobileprovision: an app signed ad hoc installs on no device; sign it with a development identity and profile"]
        }
        let profile = try ProvisioningProfile(bytes: [UInt8](bytes), path: profilePath)
        var problems = problems(profile: profile, bundleIdentifier: bundleIdentifier, device: udid, at: date)
        if let signed = try CodeSigner.entitlements(of: app),
           case .dictionary(let claimed) = try PropertyListValue.parseXML(Data(signed), path: app),
           case .dictionary(let allowed) = profile.entitlements {
            problems += ProvisioningProfile.unauthorized(claimed, allowed).map { "the profile \"\(profile.name)\" does not allow the entitlement \($0)" }
        }
        return problems
    }

    /// What keeps `profile` from signing with `identity` for a build of nomac's manual signing: the
    /// refusals of `ManualSigning` and those of a device, before a build would meet them.
    public static func problems(profile: ProvisioningProfile, identity: SigningIdentity, bundleIdentifier: String?, device udid: String?, at date: Date,
                                roots: Set<[UInt8]> = ProvisioningProfile.appleRoots) -> [String] {
        var problems: [String] = []
        if !profile.isSigned(byRootIn: roots) { problems.append("the profile \"\(profile.name)\" is not signed by Apple") }
        if !profile.includes(identity) {
            problems.append("the profile \"\(profile.name)\" does not include the certificate \"\(identity.commonName)\": edit the profile at developer.apple.com, select the certificate and download it again")
        }
        if case .dictionary(let entitlements) = profile.entitlements, entitlements["get-task-allow"] != .boolean(true) {
            problems.append("the profile \"\(profile.name)\" is not a development profile (no get-task-allow): installing from a host needs an iOS App Development profile")
        }
        return problems + self.problems(profile: profile, bundleIdentifier: bundleIdentifier, device: udid, at: date)
    }

    public static func problems(profile: ProvisioningProfile, bundleIdentifier: String?, device udid: String?, at date: Date) -> [String] {
        var problems: [String] = []
        if let expiration = profile.expirationDate, expiration <= date {
            problems.append("the profile \"\(profile.name)\" expired on \(ISO8601DateFormatter().string(from: expiration))")
        }
        if let pattern = profile.applicationIdentifier {
            if let bundleIdentifier, !covers(pattern, bundleIdentifier) {
                problems.append("the profile's App ID \(pattern) does not cover the bundle identifier \(bundleIdentifier)")
            }
        } else {
            problems.append("the profile \"\(profile.name)\" has no application-identifier entitlement")
        }
        if let udid, !profile.provisionsAllDevices,
           !profile.provisionedDevices.contains(where: { $0.caseInsensitiveCompare(udid) == .orderedSame }) {
            problems.append("the profile \"\(profile.name)\" does not include the device \(udid): register the device at developer.apple.com, edit the profile, select the device and download it again")
        }
        return problems
    }

    /// Whether the App ID `pattern` (team identifier, a dot, then a bundle identifier, or a
    /// prefix of one ending in `*`) covers `bundleIdentifier`.
    static func covers(_ pattern: String, _ bundleIdentifier: String) -> Bool {
        guard let dot = pattern.firstIndex(of: ".") else { return false }
        let identifier = pattern[pattern.index(after: dot)...]
        guard identifier.hasSuffix("*") else { return identifier == bundleIdentifier }
        return bundleIdentifier.hasPrefix(identifier.dropLast())
    }
}
