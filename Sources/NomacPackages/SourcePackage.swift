import Foundation
import NomacCore
import NomacProject

/// A package of the resolved graph, as `xcodebuild` lists it under "Resolved source packages:".
///
/// ```
///   SQLite.swift: https://github.com/stephencelis/SQLite.swift.git @ 0.16.0
///   EmojiText: https://github.com/Dimillian/EmojiText @ fix-ios26 (3b11459)
///   Zip: https://github.com/marmelroy/Zip.git @ bca30f6
///   Account: /Users/me/IceCubes/Packages/Account
///   Dep: /Users/me/App/Deps/Dep @ local
/// ```
public struct SourcePackage: Sendable, Equatable {
    /// The manifest's name (`RevenueCat` for purchases-ios-spm).
    public var name: String
    /// SwiftPM's identity of the package (`purchases-ios-spm`), which its PIF GUIDs contain.
    public var identity: String
    /// A remote package's URL as `Package.resolved` records it, or a local package's path.
    public var location: String
    /// What a remote package is pinned to: a version, `branch (revision)` or a revision, the
    /// revision shortened to 7 characters; `local` for a local dependency
    /// (`XCLocalSwiftPackageReference`); `nil` for a root package.
    public var pin: String?
    /// Its directory, products and targets, for scheme discovery.
    public var contents: SwiftPackageContents

    public init(name: String, identity: String, location: String, pin: String?, contents: SwiftPackageContents) {
        self.name = name
        self.identity = identity
        self.location = location
        self.pin = pin
        self.contents = contents
    }

    /// The package's line in xcodebuild's list, without its two-space indent.
    public var listing: String {
        "\(name): \(location)" + (pin.map { " @ \($0)" } ?? "")
    }

    /// A pin of `Package.resolved`.
    struct Pin: Equatable {
        var location: String
        var version: String?
        var branch: String?
        var revision: String?

        var description: String? {
            let revision = revision.map { String($0.prefix(7)) }
            if let version { return version }
            if let branch { return revision.map { "\(branch) (\($0))" } ?? branch }
            return revision
        }
    }

    /// The pins of a `Package.resolved` file by package identity: formats 2 and 3 record the
    /// identity, format 1 only the URL, from which `identity` computes it.
    static func pins(resolvedFile: String, identity: (String) -> String) -> [String: Pin] {
        guard let data = FileManager.default.contents(atPath: resolvedFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        let entries = (root["pins"] as? [[String: Any]]) ?? ((root["object"] as? [String: Any])?["pins"] as? [[String: Any]]) ?? []
        var pins: [String: Pin] = [:]
        for entry in entries {
            guard let location = (entry["location"] ?? entry["repositoryURL"]) as? String else { continue }
            let state = entry["state"] as? [String: Any] ?? [:]
            let key = (entry["identity"] as? String) ?? identity(location)
            pins[key] = Pin(location: location, version: state["version"] as? String, branch: state["branch"] as? String, revision: state["revision"] as? String)
        }
        return pins
    }
}
