import struct PackageGraph.ResolvedProduct
import struct PackageLoading.FileRuleDescription

// Written for nomac; not part of SwiftPM. What nomac needs from the builder's internals.
extension PackagePIFBuilder {
    /// The file rules the builder applies to files that build tool plugins generate: Xcode's
    /// own rules (xibs, asset catalogs, string catalogs, Core Data, Metal), `.docc` catalogs,
    /// Core ML models and RealityKit assets. Xcode loads packages with these rules, so nomac
    /// passes them to `WorkspaceConfiguration.additionalFileRules`.
    public static var xcodeFileRules: [FileRuleDescription] {
        PackagePIFProjectBuilder.additionalFileRules
    }

    /// The GUID of the PIF target the builder makes for `product`, which targets that use the
    /// product reference (`PACKAGE-PRODUCT:<package>_<product>.<product>`).
    public static func targetGUID(of product: ResolvedProduct) -> String {
        product.pifTargetGUID.value
    }
}
