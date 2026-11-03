import Foundation
import NomacCore
import NomacEnvelope
import NomacNib
import NomacProject
import XcodeProj

/// `nomac check`'s `nib:` domain (ADR 0011): the xibs and storyboards iOS targets compile, each run
/// through nomac's ibtool in memory with the options a build passes it (the target's module,
/// deployment target and devices), so a document nomac refuses is reported before a build stops on
/// it, with the compiler's own message (docs/formats/check.md). Nothing is written.
struct NibDomain: FeatureDomain {
    let name = "nib"
    var envelope: Envelope { Self.envelope }

    static let envelope = Envelope(domain: "nib", entries: [], family: { feature in
        guard feature.hasPrefix("nib:refused="), let item = feature.split(separator: "=").last else { return nil }
        return item.hasPrefix("B-") ? .unverified(feature, "nomac's ibtool refuses the document", backlog: String(item))
            : .unverified(feature, "nomac's ibtool fails on the document with an error that names no BACKLOG item")
    })

    func scan(_ container: String, options: CheckOptions) throws -> DomainScan {
        let workspace = try XcodeWorkspace.load(path: FileSystem.absolute(container))
        var scan = DomainScan()
        var seen = Set<String>()
        for (document, compile) in Self.documents(of: workspace, options: options, unchecked: &scan.unchecked) {
            if options.descriptionOnly {
                scan.unchecked.append(UncheckedPart(what: "Interface Builder document contents", file: document))
                continue
            }
            guard let refusal = Self.refusal(document, compile), seen.insert(document + "\0" + refusal).inserted else { continue }
            let item = refusal.firstMatch(of: /BACKLOG (B-\d+)/).map { String($0.1) } ?? "unexplained"
            scan.uses.append(FeatureUse(feature: "nib:refused=\(item)", file: document, object: refusal))
        }
        scan.unchecked.sort()
        return scan
    }

    /// The compiler's first error on `document`, with the document's path left out; nil when it compiles.
    static func refusal(_ document: String, _ options: XIBCompiler.Options) -> String? {
        do {
            guard let data = FileManager.default.contents(atPath: document) else { return "cannot read the document" }
            if (document as NSString).pathExtension == "storyboard" {
                _ = try StoryboardCompiler.compile(data, path: document, options: options)
            } else {
                _ = try XIBCompiler.compile(data, path: document, options: options)
            }
            return nil
        } catch {
            return "\(error)".replacingOccurrences(of: document + ": ", with: "").replacingOccurrences(of: document, with: "")
        }
    }

    /// Each xib and storyboard of iOS targets' resources phases (variant groups' localizations
    /// among them) and synchronized folders, once per distinct set of options its targets'
    /// configurations give it.
    static func documents(of workspace: XcodeWorkspace, options: CheckOptions, unchecked: inout [UncheckedPart]) -> [(String, XIBCompiler.Options)] {
        var found: [(String, XIBCompiler.Options)] = []
        var seen = Set<String>()
        for project in workspace.allProjects {
            let containing = (project.path as NSString).deletingLastPathComponent
            let dirPath = project.project.projectDirPath
            let sourceRoot = dirPath.isEmpty ? containing : ((containing as NSString).appendingPathComponent(dirPath) as NSString).standardizingPath
            let projectConfigurations = project.pbxproj.rootObject?.buildConfigurationList?.buildConfigurations ?? []
            for target in project.pbxproj.nativeTargets {
                var paths: [String] = []
                for phase in target.buildPhases.compactMap({ $0 as? PBXResourcesBuildPhase }) {
                    for file in phase.files ?? [] {
                        guard let element = file.file else { continue }
                        if let variant = element as? PBXVariantGroup {
                            // A localization's path is relative to the variant group's own folder when it has a path,
                            // else to the folder of the group that holds it.
                            let folder = variant.path != nil ? (try? variant.fullPath(sourceRoot: sourceRoot)) ?? sourceRoot
                                : variant.parent.flatMap { try? $0.fullPath(sourceRoot: sourceRoot) } ?? sourceRoot
                            for child in variant.children {
                                if let relative = child.path, isDocument(relative) {
                                    paths.append(((folder as NSString).appendingPathComponent(relative) as NSString).standardizingPath)
                                }
                            }
                        } else if let path = try? element.fullPath(sourceRoot: sourceRoot), isDocument(path) {
                            paths.append((path as NSString).standardizingPath)
                        }
                    }
                }
                for group in target.fileSystemSynchronizedGroups ?? [] {
                    guard let folder = try? group.fullPath(sourceRoot: sourceRoot) else { continue }
                    if options.descriptionOnly {
                        unchecked.append(UncheckedPart(what: "Interface Builder documents in a synchronized folder", file: folder))
                    } else {
                        paths += documents(inFolder: folder)
                    }
                }
                guard !paths.isEmpty else { continue }
                for configuration in target.buildConfigurationList?.buildConfigurations ?? [] {
                    let levels = [configuration, projectConfigurations.first { $0.name == configuration.name }].compactMap { $0 }
                    func setting(_ name: String) -> String? {
                        for level in levels {
                            if case .string(let value)? = level.buildSettings[name], !value.contains("$") { return value }
                            if let base = level.baseConfiguration, let path = try? base.fullPath(sourceRoot: sourceRoot),
                               let value = XCConfigFile.assignments(at: path).last(where: { $0.name == name && $0.conditions.isEmpty })?.value,
                               !value.contains("$") {
                                return value
                            }
                        }
                        return nil
                    }
                    guard setting("SDKROOT") == "iphoneos" else { continue }
                    let families = (setting("TARGETED_DEVICE_FAMILY") ?? "1").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    let devices = families.compactMap { ["1": "iphone", "2": "ipad"][$0] }
                    let module = setting("PRODUCT_MODULE_NAME") ?? String(target.name.map { $0.isLetter || $0.isNumber ? $0 : "_" })
                    let compile = XIBCompiler.Options(module: module, minimumDeploymentTarget: setting("IPHONEOS_DEPLOYMENT_TARGET") ?? defaultDeploymentTarget,
                                                      targetDevices: devices.isEmpty ? ["iphone"] : devices)
                    for path in paths where seen.insert([path, compile.minimumDeploymentTarget, compile.targetDevices.joined(separator: ",")].joined(separator: "\0")).inserted {
                        found.append((path, compile))
                    }
                }
            }
        }
        return found
    }

    /// The deployment target a build passes when the target sets none: the iOS 27.0 SDK's default
    /// (`SDKSettings.json`, `DefaultDeploymentTarget`).
    static let defaultDeploymentTarget = "27.0"

    static func isDocument(_ path: String) -> Bool {
        ["xib", "storyboard"].contains((path as NSString).pathExtension)
    }

    static func documents(inFolder folder: String) -> [String] {
        var found: [String] = []
        let enumerator = FileManager.default.enumerator(atPath: folder)
        while let relative = enumerator?.nextObject() as? String {
            if isDocument(relative) { found.append(folder + "/" + relative) }
        }
        return found.sorted()
    }
}
