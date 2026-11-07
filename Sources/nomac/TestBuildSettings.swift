import Foundation
import NomacBuildService
import NomacCore
import NomacDeviceTest
import NomacInspect
import NomacPIF
import NomacProject

/// What a `build-for-testing` built, from the targets' build settings, for the `.xctestrun`.
enum TestBuildSettings {
    /// A UI test target's build copies the platform's `XCTRunner.app`, which an SDK that an older
    /// nomac installed lacks; Swift Build's own error ("not a directory") names no next step.
    static func checkRunner(targets: [WorkspaceTarget], inspector: BuildSettingsInspector, request: SettingsRequest) async throws {
        for target in targets where try await inspector.session.evaluate("$(PRODUCT_TYPE)", targetGUID: target.guid, request: request) == "com.apple.product-type.bundle.ui-testing" {
            let runner = try await inspector.session.evaluate("$(PLATFORM_DIR)", targetGUID: target.guid, request: request) + "/Developer/Library/Xcode/Agents/XCTRunner.app"
            guard FileSystem.isDirectory(runner) else {
                throw NomacError("the installed SDK has no UI test runner, which the UI test target \(target.name) needs", path: runner, notes: [
                    "an older nomac left it out: run 'nomac sdk install <Xcode.xip or Xcode.app>' again, then 'nomac toolchain install'",
                ])
            }
            return
        }
    }

    /// The description of the build and the folder the `.xctestrun` goes in (`BUILD_DIR`).
    static func describe(scheme: XcodeScheme, targets: [WorkspaceTarget], inspector: BuildSettingsInspector, request: SettingsRequest,
                         workspace: XcodeWorkspace, pif: PIFDocument) async throws -> (TestBuildDescription, String)? {
        guard let first = targets.first else { return nil }
        let built = pif.withDependencies(of: targets.map(\.guid)).map { WorkspaceTarget(guid: $0, name: pif.targetName(guid: $0) ?? "") }
        func value(_ name: String, _ target: WorkspaceTarget) async throws -> String {
            try await inspector.session.evaluate("$(\(name))", targetGUID: target.guid, request: request)
        }
        let buildFolder = try await value("BUILD_DIR", first)
        func relative(_ path: String) -> String {
            path.hasPrefix(buildFolder + "/") ? String(path.dropFirst(buildFolder.count + 1)) : path
        }
        var products: [TestBuildDescription.Product] = []
        var targetNames: [String: String] = [:]
        var uiTests: [(index: Int, target: WorkspaceTarget)] = []
        for target in built where !target.guid.hasPrefix(packageTargetPrefix) {
            guard !(try await value("FULL_PRODUCT_NAME", target)).isEmpty else { continue }
            let wrapperExtension = try await value("WRAPPER_EXTENSION", target)
            let kind: TestBuildDescription.Product.Kind = switch try await value("PRODUCT_TYPE", target) {
            case "com.apple.product-type.application": .application
            case "com.apple.product-type.bundle.unit-test": .unitTest
            case "com.apple.product-type.bundle.ui-testing": .uiTest
            default: wrapperExtension.isEmpty ? .other : .wrapper
            }
            let path = relative(try await value("TARGET_BUILD_DIR", target) + "/" + (try await value("FULL_PRODUCT_NAME", target)))
            targetNames[target.name] = path
            let host = try await value("TEST_HOST", target)
            if kind == .uiTest { uiTests.append((products.count, target)) }
            products.append(TestBuildDescription.Product(
                name: target.name, moduleName: try await value("PRODUCT_MODULE_NAME", target),
                bundleIdentifier: try await value("PRODUCT_BUNDLE_IDENTIFIER", target), path: path,
                executableName: try await value("EXECUTABLE_NAME", target), kind: kind,
                hostPath: kind == .unitTest && !host.isEmpty ? relative((host as NSString).deletingLastPathComponent) : nil))
        }
        for (index, target) in uiTests {
            products[index].targetApplicationPath = targetNames[try await value("TEST_TARGET_NAME", target)]
        }
        let identifiers = targetIdentifiers(workspace)
        var plans = try scheme.testPlans.map { try XCTestPlan(path: $0.path, isDefault: $0.isDefault) }
        if plans.isEmpty, scheme.autocreatesTestPlan {
            let testables = scheme.testables.map { XCTestPlan.Target(name: $0.targetName, identifier: $0.targetID) }
            plans = [XCTestPlan(autocreatedFor: scheme.name, testables: testables, arguments: scheme.testArguments, environment: scheme.testEnvironment)]
        }
        var expandedPlans: [XCTestPlan] = []
        for plan in plans {
            expandedPlans.append(try await plan.expandingVariables { text, identifier in
                guard let target = targets.first(where: { identifiers[$0.guid] == identifier }) else { return text }
                return try await inspector.session.evaluate(text, targetGUID: target.guid, request: request)
            })
        }
        var coverage: [TestBuildDescription.CoverageProduct] = []
        if scheme.codeCoverageEnabled || plans.contains(where: { $0.coverage != .off }) {
            for target in built where !target.guid.hasPrefix(packageTargetPrefix) {
                if target.guid.hasPrefix(packageProductPrefix), target.name.hasSuffix(packageProductSuffix) {
                    // A package's library counts by its name, static, with the files of the package
                    // targets it holds and the binary of its framework form, which an app linking
                    // it statically does not build (`xctestrun-coverage-package`).
                    let name = String(target.name.dropLast(packageProductSuffix.count))
                    guard let dynamic = pif.targetGUID(named: name + "dynamic" + packageProductSuffix) else { continue }
                    let framework = WorkspaceTarget(guid: dynamic, name: name)
                    let binary = relative(try await value("TARGET_BUILD_DIR", framework) + "/" + (try await value("EXECUTABLE_PATH", framework)))
                    let held = pif.withDependencies(of: [target.guid]).filter { $0.hasPrefix(packageTargetPrefix) }
                    coverage.append(TestBuildDescription.CoverageProduct(identifier: name, name: name, binaryPath: binary, isStatic: true,
                                                                         sources: held.flatMap { pif.compileSources(targetGUID: $0) }))
                    continue
                }
                let productName = try await value("FULL_PRODUCT_NAME", target)
                guard !productName.isEmpty else { continue }
                let binary = relative(try await value("TARGET_BUILD_DIR", target) + "/" + (try await value("EXECUTABLE_PATH", target)))
                coverage.append(TestBuildDescription.CoverageProduct(identifier: identifiers[target.guid] ?? target.guid, name: productName, binaryPath: binary,
                                                                     isStatic: try await value("MACH_O_TYPE", target) == "staticlib",
                                                                     sources: pif.compileSources(targetGUID: target.guid)))
            }
        }
        let containerFolder = workspace.directory
        let projectFile = try await value("PROJECT_FILE_PATH", first)
        let description = TestBuildDescription(
            schemeName: scheme.name, containerName: workspace.name, projectName: try await value("PROJECT_NAME", first),
            projectPath: projectFile.hasPrefix(containerFolder + "/") ? String(projectFile.dropFirst(containerFolder.count + 1)) : projectFile,
            products: products, testables: (scheme.testables + scheme.testPlanTestables).map(\.targetName),
            arguments: scheme.testArguments, environment: scheme.testEnvironment,
            sdkName: try await value("SDK_NAME", first),
            architecture: (try await value("ARCHS", first)).split(separator: " ").first.map(String.init) ?? "",
            coverage: coverage, coverageReportTargets: scheme.coverageReportTargets, plans: expandedPlans)
        return (description, buildFolder)
    }

    /// A package's target, which the product holding it stands for in the `.xctestrun`.
    static let packageTargetPrefix = "PACKAGE-TARGET:"
    static let packageProductPrefix = "PACKAGE-PRODUCT:"
    static let packageProductSuffix = "-product"

    /// The identifier each target has in its project's file, by the GUID its PIF names it with.
    static func targetIdentifiers(_ workspace: XcodeWorkspace) -> [String: String] {
        var identifiers: [String: String] = [:]
        for project in workspace.projects {
            let projectGUID = PIFIdentifiers.projectGUID(projectPath: project.path, workspace: workspace)
            for target in project.project.targets {
                identifiers[PIFIdentifiers.objectGUID(projectGUID: projectGUID, objectID: target.uuid)] = target.uuid
            }
        }
        return identifiers
    }
}
