import Foundation
import NomacCore
import NomacProject
import XcodeProj

/// The name of a target's product in `productReference` (docs/formats/pif.md, "Product names").
///
/// Xcode writes the target's `FULL_PRODUCT_NAME`, evaluated in its Debug configuration (its
/// first when it has none), with Unicode decomposed, whatever the product reference's own path
/// says: `.app` for an app without `PRODUCT_NAME`, `Dynamic.dylib` for a dynamic library whose
/// reference is `libDynamic.dylib` (loader-experiments `product-names`,
/// `product-names-configurations`, `product-names-order`). A name that would be empty, a tool's
/// without `PRODUCT_NAME`, is the target's name (`product-names-empty`: not the reference's path
/// nor `productName`). A product type that does not exist for the target's platform keeps the
/// reference's path as written (`product-types-sdks`, `product-types-restricted`,
/// `product-types-other`, `product-names-no-sdk`).
extension ProjectGenerator {
    /// The prefix and suffix `FULL_PRODUCT_NAME` adds to `PRODUCT_NAME`, by product type, when
    /// no setting changes them (each product type with `PRODUCT_NAME` set and nothing else), for
    /// the types the project reader knows (BACKLOG B-071).
    static let productNameForms: [String: (prefix: String, suffix: String)] = [
        "com.apple.product-type.app-extension": ("", ".appex"),
        "com.apple.product-type.app-extension.intents-service": ("", ".appex"),
        "com.apple.product-type.app-extension.messages": ("", ".appex"),
        "com.apple.product-type.app-extension.messages-sticker-pack": ("", ".appex"),
        "com.apple.product-type.application": ("", ".app"),
        "com.apple.product-type.application.messages": ("", ".app"),
        "com.apple.product-type.application.on-demand-install-capable": ("", ".app"),
        "com.apple.product-type.application.watchapp2": ("", ".app"),
        "com.apple.product-type.application.watchapp2-container": ("", ".app"),
        "com.apple.product-type.bundle": ("", ".bundle"),
        "com.apple.product-type.bundle.ocunit-test": ("", ".octest"),
        "com.apple.product-type.bundle.ui-testing": ("", ".xctest"),
        "com.apple.product-type.bundle.unit-test": ("", ".xctest"),
        "com.apple.product-type.driver-extension": ("", ".dext"),
        "com.apple.product-type.extensionkit-extension": ("", ".appex"),
        "com.apple.product-type.framework": ("", ".framework"),
        "com.apple.product-type.framework.static": ("", ".framework"),
        "com.apple.product-type.instruments-package": ("", ".instrdst"),
        "com.apple.product-type.library.dynamic": ("", ".dylib"),
        "com.apple.product-type.library.static": ("lib", ".a"),
        "com.apple.product-type.metal-library": ("", ".metallib"),
        "com.apple.product-type.system-extension": ("", ".systemextension"),
        "com.apple.product-type.tool": ("", ""),
        "com.apple.product-type.tool.host-build": ("", ""),
        "com.apple.product-type.tv-app-extension": ("", ".appex"),
        "com.apple.product-type.watchkit2-extension": ("", ".appex"),
        "com.apple.product-type.xcode-extension": ("", ".appex"),
        "com.apple.product-type.xpc-service": ("", ".xpc"),
    ]

    /// The platforms of the product types that exist on some only, named by their device SDK:
    /// `application.watchapp` and `watchkit-extension` exist on none, every other type of
    /// ``productNameForms`` on all.
    static let productTypePlatforms: [String: Set<String>] = [
        "com.apple.product-type.app-extension.intents-service": ["watchos"],
        "com.apple.product-type.application.watchapp": [],
        "com.apple.product-type.application.watchapp2": ["watchos"],
        "com.apple.product-type.tv-app-extension": ["appletvos"],
        "com.apple.product-type.watchkit-extension": [],
        "com.apple.product-type.watchkit2-extension": ["watchos"],
        "com.apple.product-type.xcode-extension": ["macosx"],
    ]

    /// The settings besides `PRODUCT_NAME` that change `FULL_PRODUCT_NAME`; when a level sets one,
    /// Swift Build evaluates the name.
    static let productNameSettings = [
        "FULL_PRODUCT_NAME", "WRAPPER_NAME", "WRAPPER_EXTENSION", "WRAPPER_SUFFIX", "EXECUTABLE_NAME", "EXECUTABLE_PREFIX",
        "EXECUTABLE_SUFFIX", "EXECUTABLE_EXTENSION", "EXECUTABLE_VARIANT_SUFFIX", "DYNAMIC_LIBRARY_EXTENSION",
    ]

    /// The platform of an SDKROOT, by its device SDK: the device and simulator SDK names of
    /// each platform name it; anything else is macOS, `auto`, an empty value, no SDKROOT at all
    /// and an SDK name that no installed SDK has (`watchos26.0`) included.
    static func platform(sdk: String?) -> String {
        switch sdk {
        case "iphoneos", "iphonesimulator": return "iphoneos"
        case "watchos", "watchsimulator": return "watchos"
        case "appletvos", "appletvsimulator": return "appletvos"
        case "xros", "xrsimulator": return "xros"
        default: return "macosx"
        }
    }

    /// The configuration Xcode names the product in: Debug, else the first.
    func productConfiguration(_ target: PBXTarget) -> XCBuildConfiguration? {
        let configurations = target.buildConfigurationList?.buildConfigurations ?? []
        return configurations.first { $0.name == "Debug" } ?? configurations.first
    }

    /// The prefix and suffix of the target's product, or `nil` when its type does not exist
    /// for the target's platform.
    func productNameForm(_ target: PBXTarget) -> (prefix: String, suffix: String)? {
        let type = target.productType?.rawValue ?? ""
        guard let form = Self.productNameForms[type] else { return nil }
        if let platforms = Self.productTypePlatforms[type] {
            let sdk = productConfiguration(target).flatMap { setting("SDKROOT", $0) }
            guard platforms.contains(Self.platform(sdk: sdk)) else { return nil }
        }
        return form
    }

    /// Whether Swift Build evaluates the product's name in `configuration`: it is the product's
    /// configuration, the product type exists there, and `PRODUCT_NAME` is written with macros
    /// other than `$(TARGET_NAME)` or with conditions, or a level sets one of
    /// ``productNameSettings``.
    func productNameNeedsEvaluation(_ target: PBXTarget, _ configuration: XCBuildConfiguration) -> Bool {
        guard target.product != nil, configuration === productConfiguration(target), productNameForm(target) != nil else { return false }
        return Self.plainProductName(setting("PRODUCT_NAME", configuration), target: target) == nil
            || isConditioned("PRODUCT_NAME", configuration) || setsProductNameSetting(configuration)
    }

    func setsProductNameSetting(_ configuration: XCBuildConfiguration) -> Bool {
        Self.productNameSettings.contains { setting($0, configuration) != nil || isConditioned($0, configuration) }
    }

    /// The name a `PRODUCT_NAME` value gives without Swift Build: nothing for an unset one, the
    /// target's name for `$(TARGET_NAME)`, the value itself without macros; `nil` otherwise.
    static func plainProductName(_ written: String?, target: PBXTarget) -> String? {
        guard let written else { return "" }
        if ["$(TARGET_NAME)", "${TARGET_NAME}"].contains(written) { return target.name }
        return written.contains("$") ? nil : written
    }

    /// The product's name in `productReference`; `path` is the reference's own. A `PRODUCT_NAME`
    /// written with a condition takes Xcode's choice of assignment (``conditionedChoice(_:_:_:)``),
    /// Swift Build evaluating the rest.
    func productName(_ target: PBXTarget, path: String) -> String {
        guard let form = productNameForm(target) else { return path }
        guard let configuration = productConfiguration(target) else { return Self.named(form.prefix + form.suffix, target) }
        var name = Self.plainProductName(setting("PRODUCT_NAME", configuration), target: target)
        if productNameNeedsEvaluation(target, configuration) {
            name = setsProductNameSetting(configuration) ? nil
                : conditionedChoice("PRODUCT_NAME", target, configuration).flatMap { Self.plainProductName($0, target: target) }
            if name == nil {
                return evaluatedSettings[settingsQuery(target, configuration)]?["FULL_PRODUCT_NAME"].map { Self.named($0, target) } ?? path
            }
        }
        return Self.named(form.prefix + (name ?? "") + form.suffix, target)
    }

    /// A product's name, decomposed, or the target's when it is empty.
    static func named(_ name: String, _ target: PBXTarget) -> String {
        (name.isEmpty ? target.name : name).decomposed
    }
}
