import Foundation
import PackageGraph
import PackageModel
import SwiftBuild
import VendoredPackagePIFBuilder

/// The answers Xcode gives SwiftPM's package PIF builder, as observed in Xcode 27.0's PIF
/// (netnewswire, icecubes, `package-experiments`). SwiftPM's own delegate for `swift build`
/// differs: it gives no device families, aligns no platform versions and adds symbol-graph
/// settings.
final class XcodeBuildDelegate: PackagePIFBuilder.BuildDelegate {
    private let package: ResolvedPackage
    private let alignment: PlatformAlignment
    private let skipsMacroValidation: Bool
    let isBranchOrRevisionBased: Bool
    /// Whether the workspace is a package folder's (``XcodeWorkspace/package(folder:name:)``).
    let isPackageWorkspace: Bool

    init(package: ResolvedPackage, alignment: PlatformAlignment, isBranchOrRevisionBased: Bool, skipsMacroValidation: Bool, isPackageWorkspace: Bool = false) {
        self.package = package
        self.alignment = alignment
        self.isBranchOrRevisionBased = isBranchOrRevisionBased
        self.skipsMacroValidation = skipsMacroValidation
        self.isPackageWorkspace = isPackageWorkspace
    }

    var isRootPackage: Bool { package.manifest.packageKind.isRoot }
    var isRemote: Bool { package.manifest.packageKind.isRemote }
    var hostsOnlyPackages: Bool { false }
    /// Local packages are the user's own; remote ones are managed by package resolution.
    var isUserManaged: Bool { !package.manifest.packageKind.isRemote }

    func customProductType(forExecutable product: PackageModel.Product) -> ProjectModel.Target.ProductType? { nil }

    /// `TARGETED_DEVICE_FAMILY = 1,2,3,4,6,7` in every package project.
    func deviceFamilyIDs() -> Set<Int> { [1, 2, 3, 4, 6, 7] }

    func shouldPackagesBuildForARM64e(platform: PackageModel.Platform) -> Bool { false }
    var isPluginExecutionSandboxingDisabled: Bool { false }
    func configureProjectBuildSettings(_ buildSettings: inout ProjectModel.BuildSettings) {}
    func configureSourceModuleBuildSettings(sourceModule: ResolvedModule, settings: inout ProjectModel.BuildSettings) {}
    func customInstallPath(product: PackageModel.Product) -> String? { nil }
    func customProductName(forFramework product: PackageModel.Product) -> String? { nil }
    func customBundleIdentifierPrefix(forFramework product: PackageModel.Product) -> String? { nil }
    func customLibraryType(product: PackageModel.Product) -> PackageModel.ProductType.LibraryType? { nil }
    func customSDKOptions(forPlatform: PackageModel.Platform) -> [String] { [] }
    func addCustomTargets(pifProject: inout ProjectModel.Project) throws -> [PackagePIFBuilder.ModuleOrProduct] { [] }
    func shouldSuppressProductDependency(product: PackageModel.Product, buildSettings: inout ProjectModel.BuildSettings) -> Bool { false }
    /// In a package folder's workspace, the root package's dynamic products are installed:
    /// `SKIP_INSTALL = NO`, `INSTALL_PATH = /usr/local/lib` (expo-default's ExpoModulesJSI,
    /// Xcode 27.0's `-dumpPIF`); in a project's or workspace's, none is.
    func shouldSetInstallPathForDynamicLib(productName: String) -> Bool { isPackageWorkspace && isRootPackage }
    func configureLibraryProduct(
        product: PackageModel.Product,
        project: inout ProjectModel.Project,
        target: WritableKeyPath<ProjectModel.Project, ProjectModel.Target>,
        additionalFiles: WritableKeyPath<ProjectModel.Group, ProjectModel.Group>
    ) {}

    /// The deployment target of a platform the package does not declare, from its iOS one.
    func suggestAlignedPlatformVersionGiveniOSVersion(platform: PackageModel.Platform, iOSVersion: PlatformVersion) -> String? {
        alignment.version(of: platform, alignedWith: iOSVersion)
    }

    /// Xcode approves the macros of local packages; a remote package's macro is approved only
    /// once its user trusts it in Xcode, which a fresh Mac has not (`approvedByUser` false:
    /// swiftfin, loader-experiments `macros`), or with `-skipMacroValidation` (swiftfin's
    /// `-dumpPIF`: all four remote macros true).
    func validateMacroFingerprint(for macroModule: ResolvedModule) -> Bool { skipsMacroValidation || !isRemote }
}
