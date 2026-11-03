import Foundation
import NomacCore
import NomacProject
import XcodeProj

/// Generates the PIF Xcode generates for a workspace (`xcodebuild -dumpPIF`).
///
/// Every rule in this file was established by comparing nomac's output with Xcode's on the
/// corpus. The format is documented in docs/formats/pif.md; each rule there names the
/// corpus app that exercises it.
public struct PIFGenerator {
    public let workspace: XcodeWorkspace
    /// Diagnostics for project content nomac could not represent exactly.
    public private(set) var warnings: [String] = []
    /// File types for synchronized folders (default: Swift Build's specifications installed
    /// next to nomac, read when a project needs them).
    public private(set) var fileTypes: FileTypeRegistry?
    /// The workspace's Swift packages (NomacPackages), listed after the workspace's projects.
    public let packages: PackageProjects
    /// Evaluated build settings of the target configurations that set `INFOPLIST_FILE`,
    /// `GENERATE_INFOPLIST_FILE`, `CODE_SIGN_STYLE`, a provisioning profile or the product's name
    /// with macros or SDK conditions, and of every configuration of the targets whose own
    /// provisioning style decides one, for their signing identities (a previous generation's
    /// ``unevaluatedSettings``, evaluated by Swift Build), with the values of its
    /// ``unevaluatedExpressions`` under their own text.
    public let evaluatedSettings: [TargetSettingsQuery: [String: String]]
    /// The target configurations of those that are not in ``evaluatedSettings``: their
    /// `provisioningSourceData` and product names are not Xcode's until the document is generated
    /// again with their settings.
    public private(set) var unevaluatedSettings: Set<TargetSettingsQuery> = []
    /// Values with macros of the `CODE_SIGN_STYLE` assignments of those configurations, which
    /// Swift Build evaluates for the target besides its settings.
    public private(set) var unevaluatedExpressions: [TargetSettingsQuery: Set<String>] = [:]
    /// The file references whose build files Xcode gives GUIDs drawn at random: variant group
    /// children it lifts out of their group (envelope-experiments `variant-groups`); `nomac verify`
    /// replaces those GUIDs with stand-ins.
    public private(set) var randomBuildFileReferences: Set<String> = []
    /// The absolute paths Xcode hashes for the GUIDs of build files whose reference proxy's product
    /// is not found, by GUID (``ProjectGenerator/hashedBuildFilePaths()``).
    public private(set) var hashedBuildFilePaths: [String: String] = [:]

    public init(workspace: XcodeWorkspace, fileTypes: FileTypeRegistry? = nil, packages: PackageProjects = PackageProjects(),
                evaluatedSettings: [TargetSettingsQuery: [String: String]] = [:]) {
        self.workspace = workspace
        self.fileTypes = fileTypes
        self.packages = packages
        self.evaluatedSettings = evaluatedSettings
    }

    /// Generates the document: the workspace object, then each project object followed by
    /// its targets, the workspace's projects first and then the package projects (Xcode
    /// writes each project followed by its targets, netnewswire).
    public mutating func generate() throws -> PIFDocument {
        let context = WorkspaceContext(workspace: workspace, packageProducts: packages.products)
        var projectSignatures: [String] = []
        var projectObjects: [PIFDocument.Object] = []
        // In path order, whatever order the workspace lists them in, the projects they reference
        // among them (loader-experiments `workspace-order`, `project-references`).
        for project in workspace.allProjects.sorted(by: { $0.path < $1.path }) {
            var generator = ProjectGenerator(project: project, context: context, fileTypes: fileTypes)
            generator.evaluatedSettings = evaluatedSettings
            let (projectObject, targets) = try generator.generate()
            warnings += generator.warnings
            fileTypes = generator.fileTypes
            unevaluatedSettings.formUnion(generator.unevaluatedSettings())
            unevaluatedExpressions.merge(generator.unevaluatedExpressions()) { $0.union($1) }
            randomBuildFileReferences.formUnion(generator.liftedChildGUIDs())
            hashedBuildFilePaths.merge(generator.hashedBuildFilePaths()) { first, _ in first }
            projectSignatures.append(projectObject.signature)
            projectObjects.append(projectObject)
            projectObjects += targets
        }
        for package in packages.projects {
            let targets = package.targets.map { PIFDocument.Object(type: "target", signature: PIFIdentifiers.signature(prefix: "TARGET", contents: $0), contents: $0) }
            var contents = package.contents.objectValue ?? [:]
            contents["targets"] = .array(targets.map { .string($0.signature) })
            let value = PIFValue.object(contents)
            let projectObject = PIFDocument.Object(type: "project", signature: PIFIdentifiers.signature(prefix: "PROJECT", contents: value), contents: value)
            projectSignatures.append(projectObject.signature)
            projectObjects.append(projectObject)
            projectObjects += package.documentOrder.map { targets[$0] }
        }
        let contents = PIFValue.object([
            "guid": .string(PIFIdentifiers.workspaceGUID(name: workspace.name)),
            "name": .string(workspace.name),
            "path": .string(workspace.path),
            "projects": .array(projectSignatures.map(PIFValue.string)),
        ])
        let signature = "WORKSPACE@v11_hash=(null)_subobjects=\(PIFIdentifiers.md5(projectSignatures.joined(separator: ",")))"
        let workspaceObject = PIFDocument.Object(type: "workspace", signature: signature, contents: contents)
        return PIFDocument(objects: [workspaceObject] + projectObjects)
    }
}

/// Cross-project lookups (targets and product references are referenced by GUID across
/// the whole workspace).
final class WorkspaceContext {
    let workspace: XcodeWorkspace
    /// Target GUID by target object identity, for every target in the workspace.
    private(set) var targetGUIDs: [ObjectIdentifier: String] = [:]
    /// Package products by the object ID of the `XCSwiftPackageProductDependency` naming them.
    let packageProducts: [String: PackageProjects.Product]
    /// Target GUIDs by standardized project path and target object ID, for dependencies on
    /// targets of other projects.
    private(set) var targetGUIDByProjectAndID: [String: [String: String]] = [:]
    /// Target GUIDs by standardized project path and the object ID of the target's product
    /// reference.
    private(set) var targetGUIDByProjectAndProductID: [String: [String: String]] = [:]
    /// Target GUIDs by standardized project path and target name, the first target of a name,
    /// for proxies whose remote ID names nothing (``ProjectGenerator/dependencyTarget(_:)``).
    private(set) var targetGUIDByProjectAndName: [String: [String: String]] = [:]

    init(workspace: XcodeWorkspace, packageProducts: [String: PackageProjects.Product] = [:]) {
        self.workspace = workspace
        self.packageProducts = packageProducts
        for project in workspace.allProjects {
            let projectGUID = PIFIdentifiers.projectGUID(projectPath: project.path, workspace: workspace)
            let path = (project.path as NSString).standardizingPath
            for target in project.project.targets {
                let guid = PIFIdentifiers.objectGUID(projectGUID: projectGUID, objectID: target.uuid)
                targetGUIDs[ObjectIdentifier(target)] = guid
                targetGUIDByProjectAndID[path, default: [:]][target.uuid] = guid
                if targetGUIDByProjectAndName[path]?[target.name] == nil { targetGUIDByProjectAndName[path, default: [:]][target.name] = guid }
                if let product = target.product {
                    targetGUIDByProjectAndProductID[path, default: [:]][product.uuid] = guid
                }
            }
        }
    }

    func guid(of target: PBXTarget) -> String? {
        targetGUIDs[ObjectIdentifier(target)]
    }
}
