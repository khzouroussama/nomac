import Foundation
import NomacCore
import NomacCoreML
import NomacEnvelope
import NomacProject

/// `nomac check`'s `metal:` domain (ADR 0011): the Metal shaders targets compile. Xcode compiles
/// them with its Metal toolchain (`metal`, `metallib`), which runs only on macOS, and nomac has
/// no replacement (docs/adr/0240-core-ml-and-metal-on-linux.md), so a project with shaders is
/// reported before a Linux build stops at its first `CompileMetalFile`.
struct MetalDomain: FeatureDomain {
    let name = "metal"
    var envelope: Envelope { Self.envelope }

    static let shader = "metal:shader"

    static let envelope = Envelope(domain: "metal", entries: [
        .unverified(shader, "Xcode compiles Metal shaders into default.metallib with its Metal toolchain, which runs only on macOS; nomac has no Metal compiler yet (docs/adr/0240-core-ml-and-metal-on-linux.md): build on a Mac", backlog: "B-241"),
    ])

    func scan(_ container: String, options: CheckOptions) throws -> DomainScan {
        let workspace = try XcodeWorkspace.load(path: FileSystem.absolute(container))
        var scan = DomainScan()
        for shader in ProjectFiles.files(of: workspace, extensions: ["metal"], kind: "Metal shaders", options: options, unchecked: &scan.unchecked) {
            scan.uses.append(FeatureUse(feature: Self.shader, file: shader, object: (shader as NSString).lastPathComponent))
        }
        scan.unchecked.sort()
        return scan
    }
}
