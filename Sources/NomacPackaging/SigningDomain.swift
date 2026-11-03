import Foundation
import NomacCore
import NomacEnvelope
import NomacProject
import XcodeProj

/// `nomac check`'s `signing:` domain (ADR 0011): what each native target asks of code signing,
/// archiving and export, read from the project files for the configuration archives use
/// (docs/formats/check.md).
public struct SigningDomain: FeatureDomain {
    public let name = "signing"
    public var envelope: Envelope { SigningEnvelope.envelope }

    public init() {}

    public func scan(_ container: String, options: CheckOptions) throws -> DomainScan {
        let workspace = try XcodeWorkspace.load(path: FileSystem.absolute(container))
        var uses: [FeatureUse] = []
        for project in workspace.allProjects {
            let file = project.path + "/project.pbxproj"
            for target in project.pbxproj.nativeTargets {
                guard let configuration = Self.archiveConfiguration(of: target) else { continue }
                let settings = WrittenSettings(project: project, target: target, configuration: configuration)
                for feature in Self.features(of: target, settings: settings) {
                    uses.append(FeatureUse(feature: feature, file: file, object: "\(target.name) (\(configuration.name))"))
                }
            }
        }
        return DomainScan(uses: uses)
    }

    /// The configuration an archive builds: `Release` when the target has it, else its default.
    static func archiveConfiguration(of target: PBXNativeTarget) -> XCBuildConfiguration? {
        let configurations = target.buildConfigurationList?.buildConfigurations ?? []
        let fallback = target.buildConfigurationList?.defaultConfigurationName
        return configurations.first { $0.name == "Release" } ?? configurations.first { $0.name == fallback } ?? configurations.first
    }

    static func features(of target: PBXNativeTarget, settings: WrittenSettings) -> [String] {
        var features: [String] = []
        let platform = settings.platform
        let productType = target.productType?.rawValue ?? "none"
        features.append("signing:product=" + productType + (platform == "iphoneos" ? "" : "@" + platform))

        switch settings.value("CODE_SIGNING_ALLOWED") {
        case .written("NO"): features.append("signing:allowed=NO")
        default: break
        }
        features.append("signing:identity=" + Self.identity(settings.value("CODE_SIGN_IDENTITY")))
        features.append("signing:style=" + Self.classify(settings.value("CODE_SIGN_STYLE")) { $0 == "Manual" ? "manual" : $0 == "Automatic" ? "automatic" : "other" })
        if case .written(let path) = settings.value("CODE_SIGN_ENTITLEMENTS"), !path.isEmpty { features.append("signing:entitlements") }
        for name in ["PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE"] {
            if case .written(let value) = settings.value(name), !value.isEmpty { features.append("signing:profile") }
        }
        if case .written("dwarf") = settings.value("DEBUG_INFORMATION_FORMAT") { features.append("signing:dsym=none") }
        if case .written("YES") = settings.value("ENABLE_ON_DEMAND_RESOURCES"), Self.hasAssetTags(target) {
            features.append("signing:on-demand-resources")
        }
        features += Self.deploymentFeatures(settings, platform: platform)
        features += Self.embedded(target)
        return Array(Set(features)).sorted()
    }

    /// `CODE_SIGN_IDENTITY` as written: `-` (ad hoc), the kinds of Apple certificates, empty,
    /// unset (`default`: Xcode's Apple Development for devices), or other names.
    static func identity(_ value: WrittenSettings.Value) -> String {
        classify(value) { text in
            switch text {
            case "-": "ad-hoc"
            case "": "empty"
            case _ where text.hasPrefix("Apple Development"): "apple-development"
            case _ where text.hasPrefix("iPhone Developer"): "iphone-developer"
            case _ where text.hasPrefix("Apple Distribution"), _ where text.hasPrefix("iPhone Distribution"): "distribution"
            default: "other"
            }
        }
    }

    static func classify(_ value: WrittenSettings.Value, _ written: (String) -> String) -> String {
        switch value {
        case .unset: "default"
        case .conditional: "conditional"
        case .written(let text): text.contains("$(") || text.contains("${") ? "expression" : written(text)
        }
    }

    /// What the deployment target changes in signatures: 4 KB code pages below iOS 16.0, a SHA-1
    /// code directory beside the SHA-256 one below watchOS 12.0 (docs/formats/code-signature.md).
    static func deploymentFeatures(_ settings: WrittenSettings, platform: String) -> [String] {
        let (name, limit, feature) = platform == "watchos"
            ? ("WATCHOS_DEPLOYMENT_TARGET", 12.0, "signing:code-directory=sha1") : ("IPHONEOS_DEPLOYMENT_TARGET", 16.0, "signing:pages=4k")
        switch settings.value(name) {
        case .unset: return []
        case .conditional: return ["signing:deployment=conditional"]
        case .written(let text):
            guard let version = Double(text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))) else { return ["signing:deployment=expression"] }
            return version < limit ? [feature] : []
        }
    }

    /// Where the target's copy-files phases put the products of other targets: `frameworks` (10),
    /// `plugins` (13), and in the products folder (16) `watch`, `app-clips`, `extensionkit`,
    /// `xpc-services` or `products-directory`; frameworks copied without code signing on copy
    /// are `frameworks-without-code-sign-on-copy`.
    static func embedded(_ target: PBXNativeTarget) -> [String] {
        var features: [String] = []
        for phase in target.buildPhases.compactMap({ $0 as? PBXCopyFilesBuildPhase }) {
            let products = (phase.files ?? []).filter { $0.file?.sourceTree == .buildProductsDir }
            guard !products.isEmpty else { continue }
            let path = phase.dstPath ?? ""
            switch phase.dstSubfolderSpec {
            case .frameworks?:
                let signed = products.allSatisfy { file in
                    if case .array(let attributes)? = file.settings?["ATTRIBUTES"] { attributes.contains("CodeSignOnCopy") } else { false }
                }
                features.append(signed ? "signing:embed=frameworks" : "signing:embed=frameworks-without-code-sign-on-copy")
            case .plugins?: features.append("signing:embed=plugins")
            case .productsDirectory?:
                let destination = path.contains("/Watch") ? "watch" : path.contains("/AppClips") ? "app-clips"
                    : path.contains("EXTENSIONS_FOLDER_PATH") || path.contains("/Extensions") ? "extensionkit"
                    : path.contains("XPCServices") ? "xpc-services" : "products-directory"
                features.append("signing:embed=" + destination)
            default:
                features.append("signing:embed=other")
            }
        }
        return features
    }

    static func hasAssetTags(_ target: PBXNativeTarget) -> Bool {
        target.buildPhases.compactMap { $0 as? PBXResourcesBuildPhase }.contains { phase in
            (phase.files ?? []).contains { $0.settings?["ASSET_TAGS"] != nil }
        }
    }
}

/// A target's settings as written for one configuration: the target's configuration, its base
/// xcconfig, the project's configuration of the same name and its base xcconfig, in that order.
/// An `sdk` condition counts when it matches the target's platform (`iphoneos`, `watchos`);
/// other conditions make the setting `conditional`.
struct WrittenSettings {
    enum Value: Equatable {
        case unset
        case written(String)
        case conditional
    }

    let levels: [[XCConfigFile.Assignment]]
    let platform: String

    init(project: XcodeProject, target: PBXNativeTarget, configuration: XCBuildConfiguration) {
        let projectConfiguration = project.pbxproj.rootObject?.buildConfigurationList?.buildConfigurations.first { $0.name == configuration.name }
        var levels: [[XCConfigFile.Assignment]] = []
        for level in [configuration, projectConfiguration].compactMap({ $0 }) {
            levels.append(level.buildSettings.compactMap { key, value in
                guard case .string(let text) = value, let (name, conditions) = XCConfigFile.key(key) else { return nil }
                return XCConfigFile.Assignment(name: name, conditions: conditions, value: text)
            })
            let directory = (project.path as NSString).deletingLastPathComponent
            if let base = level.baseConfiguration, let path = try? base.fullPath(sourceRoot: directory) {
                levels.append(XCConfigFile.assignments(at: path))
            }
        }
        self.levels = levels
        var sdk = "iphoneos"
        for assignments in levels {
            if let value = assignments.last(where: { $0.name == "SDKROOT" && $0.conditions.isEmpty })?.value {
                sdk = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                break
            }
        }
        platform = sdk.hasPrefix("watch") ? "watchos" : sdk.hasPrefix("iphone") ? "iphoneos" : sdk
    }

    func value(_ name: String) -> Value {
        for assignments in levels {
            let matching = assignments.filter { $0.name == name }
            guard !matching.isEmpty else { continue }
            if matching.contains(where: { !$0.conditions.isEmpty && Set($0.conditions.keys) != ["sdk"] }) { return .conditional }
            let forSDK = matching.last { assignment in
                assignment.conditions["sdk"].map { fnmatch($0, platform, 0) == 0 } ?? false
            }
            if let value = (forSDK ?? matching.last { $0.conditions.isEmpty })?.value {
                return .written(value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            }
        }
        return .unset
    }
}
