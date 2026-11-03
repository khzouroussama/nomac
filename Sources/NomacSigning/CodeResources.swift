import Foundation
import NomacCore

/// `_CodeSignature/CodeResources`: the seal over a bundle's files other than its main
/// executable, as codesign writes it for iOS-style (shallow) bundles.
///
/// Observed in Xcode 27.0's codesign output (docs/formats/code-signature.md): `files` holds the
/// SHA-1 of every regular file under the version 1 rules (symbolic links are left out), `files2`
/// the SHA-256 (`hash2`) of every regular file and the target of every symbolic link
/// (`symlink`) under the version 2 rules. A file matches the rule of highest weight among
/// those whose pattern it matches; `omit` rules leave it out, `optional` rules mark it. Nested
/// code (frameworks, extensions) is sealed file by file like any other content.
enum CodeResources {
    struct Rule {
        var pattern: String
        var omit = false
        var optional = false
        var weight: Double?
        /// The rule as written in the `rules` or `rules2` dictionary.
        var value: PropertyListValue {
            var entries: [String: PropertyListValue] = [:]
            if omit { entries["omit"] = .boolean(true) }
            if optional { entries["optional"] = .boolean(true) }
            if let weight { entries["weight"] = .real(weight) }
            return entries.isEmpty ? .boolean(true) : .dictionary(entries)
        }
    }

    static let rules: [Rule] = [
        Rule(pattern: "^.*"),
        Rule(pattern: "^.*\\.lproj/", optional: true, weight: 1000),
        Rule(pattern: "^.*\\.lproj/locversion.plist$", omit: true, weight: 1100),
        Rule(pattern: "^Base\\.lproj/", weight: 1010),
        Rule(pattern: "^version.plist$"),
    ]

    static let rules2: [Rule] = [
        Rule(pattern: ".*\\.dSYM($|/)", weight: 11),
        Rule(pattern: "^(.*/)?\\.DS_Store$", omit: true, weight: 2000),
        Rule(pattern: "^.*"),
        Rule(pattern: "^.*\\.lproj/", optional: true, weight: 1000),
        Rule(pattern: "^.*\\.lproj/locversion.plist$", omit: true, weight: 1100),
        Rule(pattern: "^Base\\.lproj/", weight: 1010),
        Rule(pattern: "^Info\\.plist$", omit: true, weight: 20),
        Rule(pattern: "^PkgInfo$", omit: true, weight: 20),
        Rule(pattern: "^embedded\\.provisionprofile$", weight: 20),
        Rule(pattern: "^version\\.plist$", weight: 20),
    ]

    /// The CodeResources file of the bundle at `bundle`, whose main executable is at the
    /// bundle-relative path `executable`. With `withSHA1` (a bundle whose code needs a SHA-1 code
    /// directory) each file of `files2` has its SHA-1 `hash` beside `hash2` (a watch app for
    /// watchOS 11.0 with an asset catalog, `distribution_experiments.py` `thinning` `watch-catalog`).
    static func document(bundle: String, executable: String?, withSHA1: Bool = false) throws -> [UInt8] {
        let matchers1 = try rules.map(Matcher.init)
        let matchers2 = try rules2.map(Matcher.init)
        var files: [String: PropertyListValue] = [:]
        var files2: [String: PropertyListValue] = [:]
        for entry in try BundleWalker.entries(of: bundle) where entry.path != executable && !entry.path.hasPrefix("_CodeSignature/") {
            let full = bundle + "/" + entry.path
            if let target = entry.symbolicLinkTarget {
                if let rule = winner(matchers2, entry.path), !rule.omit {
                    files2[entry.path] = .dictionary(["symlink": .string(target)])
                }
                continue
            }
            guard let contents = FileManager.default.contents(atPath: full) else {
                throw NomacError("could not read file", path: full)
            }
            let bytes = [UInt8](contents)
            if let rule = winner(matchers1, entry.path), !rule.omit {
                let hash = PropertyListValue.data(CodeSignature.sha1(bytes))
                files[entry.path] = rule.optional ? .dictionary(["hash": hash, "optional": .boolean(true)]) : hash
            }
            if let rule = winner(matchers2, entry.path), !rule.omit {
                var value: [String: PropertyListValue] = ["hash2": .data(CodeSignature.sha256(bytes))]
                if withSHA1 { value["hash"] = .data(CodeSignature.sha1(bytes)) }
                if rule.optional { value["optional"] = .boolean(true) }
                files2[entry.path] = .dictionary(value)
            }
        }
        return PropertyListValue.xmlDocument(.dictionary([
            "files": .dictionary(files),
            "files2": .dictionary(files2),
            "rules": .dictionary(Dictionary(uniqueKeysWithValues: rules.map { ($0.pattern, $0.value) })),
            "rules2": .dictionary(Dictionary(uniqueKeysWithValues: rules2.map { ($0.pattern, $0.value) })),
        ]))
    }

    private struct Matcher {
        var rule: Rule
        var expression: NSRegularExpression

        init(_ rule: Rule) throws {
            self.rule = rule
            expression = try NSRegularExpression(pattern: rule.pattern)
        }
    }

    /// The matching rule of highest weight (a rule without a weight weighs 1).
    private static func winner(_ matchers: [Matcher], _ path: String) -> Rule? {
        let range = NSRange(path.startIndex..., in: path)
        return matchers.filter { $0.expression.firstMatch(in: path, range: range) != nil }
            .max { ($0.rule.weight ?? 1) < ($1.rule.weight ?? 1) }?.rule
    }
}

/// The files and symbolic links under a directory, without following links.
enum BundleWalker {
    struct Entry {
        /// The path relative to the walked directory.
        var path: String
        var symbolicLinkTarget: String?
    }

    static func entries(of root: String) throws -> [Entry] {
        var result: [Entry] = []
        try walk(root, relative: "", into: &result)
        return result
    }

    private static func walk(_ root: String, relative: String, into result: inout [Entry]) throws {
        let directory = relative.isEmpty ? root : root + "/" + relative
        for name in try FileSystem.sortedContents(of: directory) {
            let path = relative.isEmpty ? name : relative + "/" + name
            let full = root + "/" + path
            var info = stat()
            guard lstat(full, &info) == 0 else { throw NomacError("could not read file information", path: full) }
            // The file type bits of `st_mode` (`S_IFMT`): 0o040000 for a directory, 0o120000 for a link.
            switch UInt32(info.st_mode) & 0o170000 {
            case 0o040000:
                try walk(root, relative: path, into: &result)
            case 0o120000:
                result.append(Entry(path: path, symbolicLinkTarget: try FileManager.default.destinationOfSymbolicLink(atPath: full)))
            default:
                result.append(Entry(path: path))
            }
        }
    }
}
