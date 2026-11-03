import Foundation
import PackageGraph
import PackageModel

/// Facts about the modules of a graph that SwiftPM records with `package` access, so a copy of
/// the PIF builder outside SwiftPM cannot read them: each module's package identity, and whether
/// a test module is a test-support module (one that another test module of its package depends
/// on, SwiftPM's `ModulesGraph+Loading.swift`). Both are derived here from public API.
///
/// Written for nomac; not part of SwiftPM. Register a graph before building its packages.
public enum ModuleGraphFacts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var identities: [ResolvedModule.ID: PackageIdentity] = [:]
    nonisolated(unsafe) private static var testSupportModules: Set<ResolvedModule.ID> = []

    public static func register(_ graph: ModulesGraph) {
        lock.lock()
        defer { lock.unlock() }
        for package in graph.packages {
            for module in package.modules {
                identities[module.id] = package.identity
                guard module.type == .test else { continue }
                for case .module(let dependency, _) in module.dependencies where dependency.type == .test {
                    testSupportModules.insert(dependency.id)
                }
            }
        }
    }

    static func identity(of module: ResolvedModule) -> PackageIdentity {
        lock.lock()
        defer { lock.unlock() }
        guard let identity = identities[module.id] else {
            preconditionFailure("module \(module.name) was not registered with ModuleGraphFacts")
        }
        return identity
    }

    static func isTestSupportModule(_ module: ResolvedModule) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return testSupportModules.contains(module.id)
    }
}
