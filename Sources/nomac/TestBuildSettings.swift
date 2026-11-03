import Foundation
import NomacBuildService
import NomacCore
import NomacDeviceTest
import NomacInspect
import NomacProject

/// What a `build-for-testing` built, from the targets' build settings, for the `.xctestrun`.
enum TestBuildSettings {
    /// Refuses the schemes whose `.xctestrun` nomac does not write yet: code coverage's
    /// `CodeCoverageBuildableInfos` (B-433) and test plans' format 2 (B-434).
    static func check(_ scheme: XcodeScheme) throws {
        if !scheme.testPlanTestables.isEmpty {
            throw NomacError("nomac does not write the .xctestrun of a scheme with a test plan yet (B-434)")
        }
        if scheme.codeCoverageEnabled {
            throw NomacError("nomac does not write the .xctestrun of a scheme that gathers code coverage yet (B-433)")
        }
    }

    /// The description of the build and the folder the `.xctestrun` goes in (`BUILD_DIR`).
    static func describe(scheme: XcodeScheme, targets: [WorkspaceTarget], inspector: BuildSettingsInspector, request: SettingsRequest,
                         workspace: XcodeWorkspace) async throws -> (TestBuildDescription, String)? {
        guard let first = targets.first else { return nil }
        func value(_ name: String, _ target: WorkspaceTarget) async throws -> String {
            try await inspector.session.evaluate("$(\(name))", targetGUID: target.guid, request: request)
        }
        let buildFolder = try await value("BUILD_DIR", first)
        func relative(_ path: String) -> String {
            path.hasPrefix(buildFolder + "/") ? String(path.dropFirst(buildFolder.count + 1)) : path
        }
        var products: [TestBuildDescription.Product] = []
        var targetNames: [String: String] = [:]
        for target in targets {
            let kind: TestBuildDescription.Product.Kind = switch try await value("PRODUCT_TYPE", target) {
            case "com.apple.product-type.application": .application
            case "com.apple.product-type.bundle.unit-test": .unitTest
            case "com.apple.product-type.bundle.ui-testing": .uiTest
            default: .other
            }
            let path = relative(try await value("TARGET_BUILD_DIR", target) + "/" + (try await value("FULL_PRODUCT_NAME", target)))
            targetNames[target.name] = path
            let host = try await value("TEST_HOST", target)
            products.append(TestBuildDescription.Product(
                name: target.name, moduleName: try await value("PRODUCT_MODULE_NAME", target),
                bundleIdentifier: try await value("PRODUCT_BUNDLE_IDENTIFIER", target), path: path,
                executableName: try await value("EXECUTABLE_NAME", target), kind: kind,
                hostPath: kind == .unitTest && !host.isEmpty ? relative((host as NSString).deletingLastPathComponent) : nil))
        }
        for index in products.indices where products[index].kind == .uiTest {
            let name = try await value("TEST_TARGET_NAME", targets[index])
            products[index].targetApplicationPath = targetNames[name]
        }
        let containerFolder = workspace.directory
        let projectFile = try await value("PROJECT_FILE_PATH", first)
        let description = TestBuildDescription(
            schemeName: scheme.name, containerName: workspace.name, projectName: try await value("PROJECT_NAME", first),
            projectPath: projectFile.hasPrefix(containerFolder + "/") ? String(projectFile.dropFirst(containerFolder.count + 1)) : projectFile,
            products: products, testables: (scheme.testables + scheme.testPlanTestables).map(\.targetName),
            arguments: scheme.testArguments, environment: scheme.testEnvironment,
            sdkName: try await value("SDK_NAME", first),
            architecture: (try await value("ARCHS", first)).split(separator: " ").first.map(String.init) ?? "")
        return (description, buildFolder)
    }
}
