import Foundation
import NomacPackages

/// The loader's envelope (docs/adr/0011-feature-envelope.md, docs/formats/check.md): features
/// the corpus apps and the envelope-experiments cases identical to Xcode use (``corpus``,
/// ``experimentCases``, generated), features the experiments documented in docs/formats observe,
/// and the features known to be unverified, which win over all of them.
enum LoaderEnvelope {
    static let envelope = Envelope(
        domain: "loader",
        entries: corpus.map { EnvelopeEntry.verified($0.feature, "corpus:" + $0.app) }
            + experimentCases.map { EnvelopeEntry.verified($0.feature, "envelope-experiments:" + $0.experiment) } + experiments + unverified,
        family: { hostCondition($0) ?? copyFilesDestination($0) })

    // MARK: Experiments

    static let experiments: [EnvelopeEntry] = fileTypes + buildRules + productTypes + targets + references + schemes + settings
        + synchronized + packages + names + survey

    /// One file reference of each type: its `fileTextEncoding`, its language and its code generation
    /// (loader-experiments `file-encodings`, `source-languages`, `codegen-file-types`), and the
    /// types Xcode gives again from disk, on missing paths too (`declared-types`).
    static let fileTypes: [EnvelopeEntry] = experimentFileTypes.map {
        .verified("pbxproj:PBXFileReference.fileType=\($0)", "loader-experiments:file-encodings", "loader-experiments:source-languages",
                  "loader-experiments:codegen-file-types")
    } + LoaderScan.retypedTypes.sorted().map {
        .verified("pbxproj:PBXFileReference.path=missing-\($0)", "loader-experiments:declared-types", "loader-experiments:codegen-file-types")
    }

    /// Unnamed build rules of each compiler and file type (loader-experiments `build-rules`).
    static let buildRules: [EnvelopeEntry] = experimentCompilers.map { .verified("pbxproj:PBXBuildRule.compilerSpec=\($0)", "loader-experiments:build-rules") }
        + (experimentFileTypes + ["pattern.proxy"]).map { .verified("pbxproj:PBXBuildRule.fileType=\($0)", "loader-experiments:build-rules") }
        + ["pbxproj:PBXBuildRule", "pbxproj:PBXBuildRule.compilerSpec", "pbxproj:PBXBuildRule.fileType", "pbxproj:PBXBuildRule.filePatterns",
           "pbxproj:PBXBuildRule.isEditable", "pbxproj:PBXBuildRule.isEditable=1", "pbxproj:PBXBuildRule.outputFiles", "pbxproj:PBXBuildRule.script",
           "pbxproj:PBXBuildRule.inputFiles", "pbxproj:PBXBuildRule.name", "pbxproj:PBXNativeTarget.buildRules"]
        .map { .verified($0, "loader-experiments:build-rules", "loader-experiments:targets") }
        + ["pbxproj:PBXBuildRule.runOncePerArchitecture", "pbxproj:PBXBuildRule.runOncePerArchitecture=0", "pbxproj:PBXBuildRule.runOncePerArchitecture=1",
           "pbxproj:PBXBuildRule.outputFilesCompilerFlags", "pbxproj:PBXBuildRule.dependencyFile", "pbxproj:PBXBuildRule.isEditable=0",
           "pbxproj:PBXBuildRule.inputFileListPaths", "pbxproj:PBXBuildRule.outputFileListPaths"]
        .map { .verified($0, "loader-experiments:build-rule-keys") }

    /// One target of each product type, for the schemes Xcode autocreates (loader-experiments
    /// `product-types`) and the product's name, on every platform (`product-types-sdks`); the PIF
    /// copies the type. nomac cannot read a kernel extension's type (B-071).
    static let productTypes: [EnvelopeEntry] = [
        "application", "framework", "library.static", "library.dynamic", "bundle", "tool", "application.on-demand-install-capable",
        "app-extension", "extensionkit-extension", "app-extension.messages-sticker-pack", "application.watchapp2-container",
        "application.watchapp2", "watchkit2-extension", "xpc-service", "system-extension", "xcode-extension", "driver-extension",
        "instruments-package", "metal-library", "bundle.unit-test", "bundle.ui-testing", "application.watchapp", "watchkit-extension",
        "application.messages", "app-extension.messages", "tv-app-extension", "framework.static",
    ].map { .verified("pbxproj:PBXNativeTarget.productType=com.apple.product-type.\($0)", "loader-experiments:product-types", "loader-experiments:product-types-sdks") }
        + [EnvelopeEntry.verified("pbxproj:PBXProject.attributes.CLASSPREFIX", "loader-experiments:class-prefix"),
           .verified("pbxproj:PBXNativeTarget.productType=com.apple.product-type.bundle.ocunit-test", "loader-experiments:product-types-other",
                     "envelope-experiments:survey-shapes-3")]

    /// Aggregate and legacy targets and version groups (loader-experiments `targets`, `version-group`).
    static let targets: [EnvelopeEntry] = [
        "pbxproj:PBXAggregateTarget", "pbxproj:PBXAggregateTarget.buildConfigurationList", "pbxproj:PBXAggregateTarget.buildPhases",
        "pbxproj:PBXAggregateTarget.dependencies", "pbxproj:PBXAggregateTarget.name", "pbxproj:PBXAggregateTarget.productName",
        "pbxproj:PBXLegacyTarget", "pbxproj:PBXLegacyTarget.buildArgumentsString", "pbxproj:PBXLegacyTarget.buildConfigurationList",
        "pbxproj:PBXLegacyTarget.buildPhases", "pbxproj:PBXLegacyTarget.buildToolPath", "pbxproj:PBXLegacyTarget.buildWorkingDirectory",
        "pbxproj:PBXLegacyTarget.dependencies", "pbxproj:PBXLegacyTarget.name", "pbxproj:PBXLegacyTarget.passBuildSettingsInEnvironment",
        "pbxproj:PBXLegacyTarget.passBuildSettingsInEnvironment=0", "pbxproj:PBXLegacyTarget.passBuildSettingsInEnvironment=1",
        "pbxproj:PBXLegacyTarget.productName",
    ].map { .verified($0, "loader-experiments:targets") } + [
        "pbxproj:XCVersionGroup", "pbxproj:XCVersionGroup.children", "pbxproj:XCVersionGroup.currentVersion", "pbxproj:XCVersionGroup.path",
        "pbxproj:XCVersionGroup.sourceTree", "pbxproj:XCVersionGroup.sourceTree=<group>", "pbxproj:XCVersionGroup.versionGroupType",
        "pbxproj:XCVersionGroup.versionGroupType=wrapper.xcdatamodel",
    ].map { .verified($0, "loader-experiments:version-group") }

    /// Projects that reference projects, missing or stale ones included, and workspaces of several
    /// projects (loader-experiments `project-references*`, `workspace`, `workspace-order`, `workspace-twins`).
    static let references: [EnvelopeEntry] = [
        "pbxproj:PBXProject.projectReferences=missing-project", "pbxproj:PBXTargetDependency.targetProxy=unresolved",
        "pbxproj:PBXTargetDependency.targetProxy=other-project", "pbxproj:PBXReferenceProxy", "pbxproj:PBXReferenceProxy.fileType",
        "pbxproj:PBXReferenceProxy.path", "pbxproj:PBXReferenceProxy.remoteRef", "pbxproj:PBXReferenceProxy.sourceTree",
        "pbxproj:PBXReferenceProxy.sourceTree=BUILT_PRODUCTS_DIR", "pbxproj:PBXContainerItemProxy.proxyType=2",
        "pbxproj:PBXProject.projectReferences", "pbxproj:PBXProject.projectReferences.ProductGroup", "pbxproj:PBXProject.projectReferences.ProjectRef",
    ].map { .verified($0, "loader-experiments:project-references") } + [
        "pbxproj:PBXTargetDependency.targetProxy=unresolved-in-project", "pbxproj:PBXTargetDependency.target=dangling",
    ].map { .verified($0, "loader-experiments:dependency-proxies") } + [
        "workspace:Workspace", "workspace:Workspace@version", "workspace:Workspace@version=1.0", "workspace:Workspace/FileRef",
        "workspace:FileRef@location", "workspace:FileRef@location=group", "workspace:FileRef=project", "workspace:Workspace/Group",
        "workspace:Group/FileRef", "workspace:Group@location", "workspace:Group@location=group", "workspace:Group@name",
    ].map { .verified($0, "loader-experiments:workspace", "loader-experiments:workspace-order") }

    /// Scheme actions and runnables whose rules docs/formats/show-build-settings.md "Schemes" records.
    static let schemes: [EnvelopeEntry] = [
        "scheme:LaunchAction/RemoteRunnable", "scheme:RemoteRunnable@BundleIdentifier", "scheme:RemoteRunnable@RemotePath",
        "scheme:RemoteRunnable@runnableDebuggingMode", "scheme:RemoteRunnable/BuildableReference", "scheme:LaunchAction/PathRunnable",
        "scheme:PathRunnable@FilePath", "scheme:PathRunnable@runnableDebuggingMode", "scheme:LaunchAction/MacroExpansion",
        "scheme:MacroExpansion/BuildableReference", "scheme:ProfileAction/BuildableProductRunnable",
        "scheme:BuildActionEntry@buildForAnalyzing=NO", "scheme:BuildActionEntry@buildForArchiving=NO", "scheme:BuildActionEntry@buildForProfiling=NO",
        "scheme:BuildActionEntry@buildForRunning=NO", "scheme:BuildActionEntry@buildForTesting=NO",
    ].map { .verified($0, "loader-experiments:scheme-coverage") } + [
        "scheme:TestAction/TestPlans", "scheme:TestPlans/TestPlanReference", "scheme:TestPlanReference@reference",
        "scheme:TestPlanReference@reference=container:xctestplan", "scheme:TestPlanReference@default", "scheme:TestPlanReference@default=YES",
        "scheme:TestAction@codeCoverageEnabled=NO", "scheme:TestAction@codeCoverageEnabled=YES", "scheme:TestAction@onlyGenerateCoverageForSpecifiedTargets",
        "scheme:TestAction@onlyGenerateCoverageForSpecifiedTargets=YES", "scheme:TestAction/CodeCoverageTargets",
        "testplan:file", "testplan:file=missing", "testplan:configurations.id=not-uuid", "testplan:defaultOptions.codeCoverage",
        "testplan:defaultOptions.codeCoverage=false", "testplan:defaultOptions.codeCoverage=true", "testplan:defaultOptions.codeCoverage=targets",
    ].map { .verified($0, "loader-experiments:coverage") } + [
        "workspace-settings:IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded",
        "workspace-settings:IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded=false",
        "workspace-settings:IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded=true", "workspace-settings:user",
    ].map { .verified($0, "loader-experiments:autocreate-contexts") } + [
        // Build action entries that build a test plan (docs/formats/show-build-settings.md "Schemes").
        "scheme:BuildActionEntry/TestPlanReference", "scheme:Scheme@version=2.1",
    ].map { .verified($0, "loader-experiments:test-plan-entries") } + [
        // A reference names its target by BlueprintIdentifier alone (docs/formats/show-build-settings.md).
        EnvelopeEntry.verified("scheme:BuildableReference@BlueprintName=missing", "loader-experiments:blueprint-names"),
        .verified("scheme:TestAction@shouldAutocreateTestPlan", "loader-experiments:coverage-autocreated-plan"),
        .verified("scheme:TestAction@shouldAutocreateTestPlan=YES", "loader-experiments:coverage-autocreated-plan"),
    ] + [
        "scheme:location=user", "scheme:management=user",
    ].map { .verified($0, "loader-experiments:user-schemes", "loader-experiments:user-schemes-workspace") }

    /// The settings nomac reads itself, written each way the experiments wrote them.
    static let settings: [EnvelopeEntry] = [
        EnvelopeEntry.verified("settings:value=list", "loader-experiments:settings"),
        .verified("settings:condition=sdk", "loader-experiments:infoplist-macros"),
        .verified("settings:SDKROOT=simulator", "loader-experiments:simulator-sdks"),
        .verified("settings:SDKROOT=condition", "loader-experiments:simulator-sdks", "loader-experiments:simulator-sdk-conditions"),
        .verified("pbxproj:PBXBuildFile.fileRef=dangling-beside-synchronized-members", "loader-experiments:dangling-synchronized"),
        .verified("workspace:target-name=in-several-projects", "envelope-experiments:same-name-targets"),
        .verified("pbxproj:XCSwiftPackageProductDependency.productName=plugin", "loader-experiments:build-tool-plugin"),
        .verified("settings:SYMROOT", "loader-experiments:symroot-targets", "envelope-experiments:unresolved-proxies", "envelope-experiments:symroot-locations"),
        .verified("settings:INFOPLIST_FILE=macro", "loader-experiments:infoplist-macros"),
        .verified("settings:INFOPLIST_FILE=condition", "loader-experiments:infoplist-macros"),
        .verified("settings:INFOPLIST_FILE=xcconfig", "loader-experiments:infoplist-macros"),
        .verified("settings:CODE_SIGN_STYLE=macro", "loader-experiments:provisioning-fallback"),
        .verified("settings:CODE_SIGN_STYLE=condition", "loader-experiments:provisioning-fallback"),
        .verified("settings:CODE_SIGN_STYLE=xcconfig", "loader-experiments:provisioning-style"),
        .verified("settings:PROVISIONING_PROFILE_SPECIFIER=macro", "loader-experiments:provisioning-profile"),
        .verified("settings:PROVISIONING_PROFILE_SPECIFIER=condition", "loader-experiments:provisioning-profile"),
        .verified("settings:PROVISIONING_PROFILE_SPECIFIER=xcconfig", "loader-experiments:provisioning-profile"),
        .verified("settings:PROVISIONING_PROFILE=macro", "loader-experiments:provisioning-profile"),
        .verified("settings:PROVISIONING_PROFILE=xcconfig", "loader-experiments:provisioning-profile"),
        .verified("pbxproj:PBXProject.attributes.TargetAttributes.ProvisioningStyle=Manual", "loader-experiments:provisioning-style"),
        .verified("pbxproj:PBXProject.attributes.TargetAttributes.ProvisioningStyle=Automatic", "loader-experiments:provisioning-style"),
        .verified("xcconfig:include", "loader-experiments:provisioning-conditions"),
        .verified("settings:CODE_SIGN_STYLE=condition-and-plain", "loader-experiments:provisioning-conditions"),
        .verified("settings:CODE_SIGN_STYLE=condition-and-plain-in-xcconfig", "loader-experiments:provisioning-conditions"),
        .verified("settings:CODE_SIGN_IDENTITY=macro", "loader-experiments:provisioning-defaults"),
        .verified("settings:CODE_SIGN_IDENTITY=condition", "loader-experiments:provisioning-defaults", "envelope-experiments:identity-conditions"),
        // The SDK's conditional assignment wins at one level, as Swift Build evaluates it.
        .verified("settings:CODE_SIGN_IDENTITY=xcconfig", "envelope-experiments:identity-conditions"),
        .verified("settings:CODE_SIGN_IDENTITY=condition-and-plain", "envelope-experiments:identity-conditions"),
        .verified("settings:CODE_SIGN_IDENTITY=condition-and-plain-in-xcconfig", "envelope-experiments:identity-conditions"),
        .verified("settings:GENERATE_INFOPLIST_FILE=macro", "loader-experiments:info-plist-conditions"),
        .verified("settings:GENERATE_INFOPLIST_FILE=condition", "loader-experiments:info-plist-conditions"),
        .verified("settings:GENERATE_INFOPLIST_FILE=condition-and-plain-in-xcconfig", "loader-experiments:xcconfig-conditions"),
        .verified("settings:PRODUCT_NAME=macro", "loader-experiments:product-names"),
        .verified("settings:PRODUCT_NAME=condition", "loader-experiments:product-names"),
        .verified("settings:PRODUCT_NAME=xcconfig", "loader-experiments:product-names"),
        .verified("settings:PRODUCT_NAME=condition-and-plain", "loader-experiments:product-names"),
        .verified("settings:PRODUCT_NAME=condition-and-plain-in-xcconfig", "loader-experiments:xcconfig-conditions"),
    ]

    static let codegenAttributes = ["Public", "Private", "Weak", "CodeSignOnCopy", "RemoveHeadersOnCopy", "no_codegen", "codegen", "private_codegen", "project_codegen"]

    /// Synchronized-folder exception sets and attributes (loader-experiments `synchronized-headers`,
    /// `codegen-members`, `synchronized-exceptions`, `synchronized-phase-order`, -2,
    /// `synchronized-missing-order`; pif-experiments).
    static let synchronized: [EnvelopeEntry] = [
        "pbxproj:PBXFileSystemSynchronizedBuildFileExceptionSet.publicHeaders", "pbxproj:PBXFileSystemSynchronizedBuildFileExceptionSet.privateHeaders",
        "pbxproj:PBXFileSystemSynchronizedBuildFileExceptionSet.attributesByRelativePath",
        "pbxproj:PBXFileSystemSynchronizedBuildFileExceptionSet.additionalCompilerFlagsByRelativePath",
    ].map { .verified($0, "loader-experiments:synchronized-headers", "loader-experiments:codegen-members") }
        + codegenAttributes.map { .verified("pbxproj:PBXFileSystemSynchronizedBuildFileExceptionSet.attributesByRelativePath=\($0)", "loader-experiments:codegen-members") }
        + codegenAttributes.map { .verified("pbxproj:PBXBuildFile.settings.ATTRIBUTES=\($0)", "loader-experiments:intents-codegen") }
        + ["Client", "Server"].map { .verified("pbxproj:PBXBuildFile.settings.ATTRIBUTES=\($0)", "loader-experiments:mig-codegen") }
        + ["", "=ios", "=macos", "=maccatalyst", "=tvos", "=watchos"].map {
            .verified("pbxproj:PBXFileSystemSynchronizedBuildFileExceptionSet.platformFiltersByRelativePath\($0)", "loader-experiments:synchronized-exceptions")
        }
        + [
            "pbxproj:PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet",
            "pbxproj:PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet.buildPhase",
            "pbxproj:PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet.membershipExceptions",
            "pbxproj:PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet.attributesByRelativePath",
            "pbxproj:PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet.attributesByRelativePath=CodeSignOnCopy",
            "pbxproj:PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet.attributesByRelativePath=RemoveHeadersOnCopy",
        ].map { .verified($0, "loader-experiments:synchronized-exceptions", "loader-experiments:synchronized-phase-order", "loader-experiments:synchronized-phase-order-2") }
        + [EnvelopeEntry.verified("sync:excepted-path=missing", "pif-experiments:missing-excepted-listed", "loader-experiments:synchronized-exceptions-2"),
           .verified("sync:excepted-path=missing-in-subfolder", "pif-experiments:missing-excepted-listed"),
           .verified("sync:excepted-path=missing-in-existing-subfolder", "loader-experiments:synchronized-exceptions-2", "loader-experiments:synchronized-missing-order"),
           .verified("sync:variant-group=adds-a-region", "pif-experiments:regions-two-folders"),
           .verified("sync:variant-group=no-base-or-development-region", "pif-experiments:hexguid-base", "pif-experiments:hexguid-copy"),
           .verified("sync:folder=missing", "loader-experiments:synchronized-missing"),
           .verified("sync:variant-group=base-and-development-region", "pif-experiments:variants-order", "pif-experiments:base-variants"),
           .verified("sync:same-stem=header-after-other", "pif-experiments:same-stem", "pif-experiments:same-stem-2"),
           .verified("sync:member=library", "pif-experiments:libraries-archive", "pif-experiments:libraries-nested", "loader-experiments:unicode-nfc",
                     "loader-experiments:synchronized-search-paths", "loader-experiments:synchronized-search-paths-folders")]

    /// Package references of every kind (loader-experiments `local-packages`, `unlinked-products`),
    /// the Package.resolved that pins them (`package-pins-*`), target dependencies on products
    /// (`product-target-dependencies`), and products and targets a target names several times or
    /// outside its first Frameworks phase (`product-duplicates`).
    static let packages: [EnvelopeEntry] = [
        "pbxproj:XCLocalSwiftPackageReference", "pbxproj:XCLocalSwiftPackageReference.relativePath", "pbxproj:PBXProject.packageReferences",
        "pbxproj:XCSwiftPackageProductDependency", "pbxproj:XCSwiftPackageProductDependency.package", "pbxproj:XCSwiftPackageProductDependency.productName",
        "pbxproj:PBXNativeTarget.packageProductDependencies", "pbxproj:PBXBuildFile.productRef", "package:kind=local-dependency",
    ].map { .verified($0, "loader-experiments:local-packages", "loader-experiments:unlinked-products") } + [
        EnvelopeEntry.verified("package:resolved=missing", "loader-experiments:package-pins-remote", "loader-experiments:package-pins-root",
                               "loader-experiments:package-pins-two-roots", "loader-experiments:package-pins-unpinned"),
        .verified("pbxproj:PBXTargetDependency.productRef", "loader-experiments:product-target-dependencies"),
    ] + [
        "pbxproj:XCSwiftPackageProductDependency.linked=second-frameworks-phase", "pbxproj:PBXBuildFile.productRef=outside-first-frameworks-phase",
        "pbxproj:PBXNativeTarget.dependencies=product-several-times", "pbxproj:PBXNativeTarget.dependencies=target-several-times",
    ].map { .verified($0, "loader-experiments:product-duplicates") }

    /// Names outside ASCII in either normalization form, container names DerivedData folder
    /// names rewrite, and a `projectDirPath` (docs/formats/pif.md "Unicode"; loader-experiments
    /// `unicode-nfc`, `unicode-nfd`, `unicode-order`, `derived-data-names`, `derived-data-packages`,
    /// `unicode-project-dir`, `unicode-project-dir-nfd`).
    static let names: [EnvelopeEntry] = [
        "names:container=non-ascii", "names:pbxproj=non-ascii", "names:sync-key=precomposed", "names:sync-key=decomposed",
        "names:sync-explicit-folder=non-ascii", "names:scheme=non-ascii", "names:scheme-container=non-ascii",
    ].map { .verified($0, "loader-experiments:unicode-nfc", "loader-experiments:unicode-nfd") } + [
        EnvelopeEntry.verified("names:sync-item=non-ascii", "loader-experiments:unicode-nfc", "loader-experiments:unicode-nfd", "loader-experiments:unicode-order"),
        .verified("names:container=whitespace", "loader-experiments:derived-data-names", "loader-experiments:derived-data-packages"),
        .verified("pbxproj:PBXProject.projectDirPath=set", "loader-experiments:unicode-project-dir", "loader-experiments:unicode-project-dir-nfd"),
    ]

    /// A manifest's host conditions: those a Mac with Xcode 27.0 was observed to answer
    /// (``HostConditions/mac``, package-experiments `conditions`), and those left to the compiler,
    /// which answers as Xcode's does.
    @Sendable static func hostCondition(_ feature: String) -> EnvelopeEntry? {
        let prefix = "package:condition="
        guard feature.hasPrefix(prefix) else { return nil }
        let condition = feature.dropFirst(prefix.count)
        if ["swift", "compiler", "flag"].contains(condition) { return .verified(feature, "package-experiments:conditions") }
        guard let open = condition.firstIndex(of: "("), condition.hasSuffix(")") else { return nil }
        let kind = String(condition[..<open])
        let argument = String(condition[condition.index(after: open)..<condition.index(before: condition.endIndex)])
        guard HostConditions.hostKinds.contains(kind) else { return nil }
        if HostConditions.mac.answer(kind: kind, argument: argument) != nil { return .verified(feature, "package-experiments:conditions") }
        return .unverified(feature, "nomac does not know how a Mac answers it, so Linux answers it (docs/formats/pif.md \"Swift packages\")")
    }

    // MARK: Known to be unverified

    static let unverified: [EnvelopeEntry] = [
        .unverified("package:unsafe-flags=local-dependency", "USES_SWIFTPM_UNSAFE_FLAGS depends on answers no comparison has checked", backlog: "B-010"),
        .unverified("package:unsafe-flags=branch-or-revision", "USES_SWIFTPM_UNSAFE_FLAGS depends on answers no comparison has checked", backlog: "B-010"),
        .unverified("pbxproj:PBXNativeTarget.productReference=absent", "Xcode synthesizes a product reference whose GUID is not known", backlog: "B-012"),
        .unverified("pbxproj:XCConfigurationList.defaultConfigurationName=differs-from-project", "autocreated schemes not observed for it", backlog: "B-014"),
        .unverified("pbxproj:PBXNativeTarget.testBundle=package-products-only", "autocreated schemes not observed for it", backlog: "B-014"),
        .unverified("pbxproj:PBXNativeTarget.testBundle=depends-on-other-project", "autocreated schemes not observed for it", backlog: "B-014"),
        .unverified("pbxproj:PBXTargetDependency.targetProxy=other-project-extension", "Xcode's scheme of the extension also builds the app", backlog: "B-014"),
        .unverified("pbxproj:PBXNativeTarget.extension=several-host-apps", "xcodebuild's order of the host apps changes from run to run", backlog: "B-015"),
        .unverified("sync:variant-group=adds-several-regions", "Xcode's order of the regions it adds changes from run to run", backlog: "B-017"),
        .unverified("settings:INFOPLIST_FILE=condition-and-plain", "not observed; B-026's rule may apply", backlog: "B-026"),
        .unverified("settings:INFOPLIST_FILE=condition-and-plain-in-xcconfig", "not observed; B-026's rule may apply", backlog: "B-026"),
        .unverified("settings:PROVISIONING_PROFILE_SPECIFIER=condition-and-plain-in-xcconfig", "not observed; B-026's rule may apply", backlog: "B-026"),
        .unverified("settings:PROVISIONING_PROFILE=condition-and-plain-in-xcconfig", "not observed; B-026's rule may apply", backlog: "B-026"),
        .unverified("sync:member=libraries-in-several-folders", "Xcode's order of a folder's search paths changes from run to run", backlog: "B-031"),
        .unverified("pbxproj:PBXNativeTarget.productType=com.apple.product-type.kernel-extension", "XcodeProj cannot read the type", backlog: "B-071"),
        .unverified("pbxproj:PBXReferenceProxy.remoteRef=unresolved-other-build-folder", "nomac computes the build folder Xcode hashes from plain settings and the SDKs observed only", backlog: "B-036"),
        .unverified("pbxproj:PBXVariantGroup.children=regions-from-several-groups", "Xcode's order of the regions they add changes from run to run", backlog: "B-030"),
        .unverified("settings:SDKROOT=condition-other", "Xcode's destination check reads SDKROOT under conditions other than sdk, config and arch in a way not observed"),
        .unverified("xcconfig:include=spelled-otherwise-on-disk", "Swift Build opens the include by its bytes, which a Linux file system does not find", backlog: "B-075"),
        .unverified("names:package=non-ascii", "Xcode's spelling of the package's paths is not observed", backlog: "B-076"),
        .unverified("pbxproj:PBXFileReference.path=case-mismatch", "a build on a case-sensitive file system uses the disk's spelling, which debug paths then record, unless nomac build --case-aliases", backlog: "B-062"),
        .unverified("pbxproj:format=xcproj", "Xcode 27's JSON project format: no comparison yet", backlog: "B-083"),
        .unverified("pbxproj:PBXFileReference.fileEncoding=undefined", "Xcode writes a number that changes from dump to dump"),
        .unverified("pbxproj:PBXRezBuildPhase", "nomac writes com.apple.buildphase.rez; not observed"),
        .unverified("pbxproj:PBXShellScriptBuildPhase.dependencyFile", "nomac writes a makefile dependency file; not observed"),
    ]

    /// A copy-files phase's destination: every `dstSubfolderSpec` from 0 to 17, and none, in a macOS
    /// tool and an iOS app (loader-experiments `copy-files`), xcodebuild stopping on the others
    /// (`copy-files-18`). The `dstSubfolder` names are envelope-experiments `dst-subfolders` cases.
    @Sendable static func copyFilesDestination(_ feature: String) -> EnvelopeEntry? {
        let prefix = "pbxproj:PBXCopyFilesBuildPhase.dstSubfolderSpec="
        guard feature.hasPrefix(prefix) else { return nil }
        let value = feature.dropFirst(prefix.count)
        if value == "none" { return .verified(feature, "loader-experiments:copy-files") }
        guard let spec = Int(value) else { return nil }
        if (0...17).contains(spec) { return .verified(feature, "loader-experiments:copy-files") }
        return .unverified(feature, "xcodebuild stops with SIGTRAP on a dstSubfolderSpec above 17", backlog: "B-040")
    }
}
