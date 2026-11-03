import Foundation
import NomacCore
import NomacEnvelope
import NomacProject
import XcodeProj

/// `nomac check`'s `coredata:` domain (ADR 0011): the Core Data models targets compile, each run
/// through nomac's momc as a build runs it, so a model nomac refuses is reported before a build
/// stops on it (docs/formats/check.md).
public struct CoreDataDomain: FeatureDomain {
    public let name = "coredata"
    public var envelope: Envelope { Self.modelEnvelope }

    public init() {}

    static let modelEnvelope = Envelope(domain: "coredata", entries: [
        .verified("coredata:model", "coredata-experiments:renaming-all", "corpus:uncloudnotes"),
        .verified("coredata:model=versioned", "coredata-experiments:omo-renaming", "corpus:moonlight"),
    ], family: { feature in
        guard feature.hasPrefix("coredata:refused="), let item = feature.split(separator: "=").last, item.hasPrefix("B-") else { return nil }
        return .unverified(feature, "nomac's momc refuses the model", backlog: String(item))
    })

    public func scan(_ container: String, options: CheckOptions) throws -> DomainScan {
        let workspace = try XcodeWorkspace.load(path: FileSystem.absolute(container))
        var scan = DomainScan()
        for model in Self.models(of: workspace, options: options, unchecked: &scan.unchecked) {
            if options.descriptionOnly {
                scan.unchecked.append(UncheckedPart(what: "Core Data model contents", file: model))
                continue
            }
            let name = (model as NSString).lastPathComponent
            let versioned = (model as NSString).pathExtension == "xcdatamodeld"
            scan.uses.append(FeatureUse(feature: versioned ? "coredata:model=versioned" : "coredata:model", file: model, object: name))
            if let refusal = Self.refusal(model) {
                let item = refusal.firstMatch(of: /BACKLOG (B-\d+)/).map { String($0.1) } ?? "unexplained"
                scan.uses.append(FeatureUse(feature: "coredata:refused=\(item)", file: model, object: refusal))
            }
        }
        scan.unchecked.sort()
        return scan
    }

    /// The first error of what a build runs on the model: the compile, the dry run that plans
    /// code generation, and code generation for Swift 5.
    static func refusal(_ model: String) -> String? {
        do {
            _ = try ModelCompiler.compile(model, module: "T")
            _ = try ModelCompiler.generatedFiles(model, destination: "/")
            _ = try CodeGenerator.files(model, swiftVersion: "5.0", author: CodeGenerator.Author(name: "", date: Date(timeIntervalSince1970: 0)))
            return nil
        } catch {
            return "\(error)".replacingOccurrences(of: model + "/", with: "")
        }
    }

    /// The models of targets' sources and resources phases, and those inside their synchronized
    /// folders.
    static func models(of workspace: XcodeWorkspace, options: CheckOptions, unchecked: inout [UncheckedPart]) -> [String] {
        var found: [String] = []
        for project in workspace.allProjects {
            let containing = (project.path as NSString).deletingLastPathComponent
            let dirPath = project.project.projectDirPath
            let sourceRoot = dirPath.isEmpty ? containing : ((containing as NSString).appendingPathComponent(dirPath) as NSString).standardizingPath
            for target in project.pbxproj.nativeTargets {
                for phase in target.buildPhases where phase is PBXSourcesBuildPhase || phase is PBXResourcesBuildPhase {
                    for file in phase.files ?? [] {
                        guard let element = file.file, let path = try? element.fullPath(sourceRoot: sourceRoot),
                              ["xcdatamodel", "xcdatamodeld"].contains((path as NSString).pathExtension) else { continue }
                        found.append((path as NSString).standardizingPath)
                    }
                }
                for group in target.fileSystemSynchronizedGroups ?? [] {
                    guard let folder = try? group.fullPath(sourceRoot: sourceRoot) else { continue }
                    if options.descriptionOnly {
                        unchecked.append(UncheckedPart(what: "Core Data models in a synchronized folder", file: folder))
                    } else {
                        found += models(inFolder: folder)
                    }
                }
            }
        }
        var seen: Set<String> = []
        return found.filter { seen.insert($0).inserted }
    }

    static func models(inFolder folder: String) -> [String] {
        guard let entries = try? FileSystem.sortedContents(of: folder) else { return [] }
        var found: [String] = []
        for entry in entries where !entry.hasPrefix(".") {
            let path = folder + "/" + entry
            guard FileSystem.isDirectory(path) else { continue }
            if ["xcdatamodel", "xcdatamodeld"].contains((entry as NSString).pathExtension) {
                found.append(path)
            } else {
                found += models(inFolder: path)
            }
        }
        return found
    }
}
