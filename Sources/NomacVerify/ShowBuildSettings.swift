import Foundation

/// The text format of `xcodebuild -showBuildSettings`.
///
/// ```
/// Build settings for action build and target Rampage:
///     ACTION = build
///     AD_HOC_CODE_SIGNING_ALLOWED = NO
///     ...
///
/// ```
///
/// One block per target: a header line, one `    KEY = value` line per exported setting
/// in ascending byte order of the key, then an empty line. Values are printed verbatim,
/// with no quoting or escaping; target names are quoted when they contain characters other
/// than letters, digits and `-._+,=/` (``headerName(_:)``). The format is documented in
/// docs/formats/show-build-settings.md.
public enum ShowBuildSettings {
    /// One target's block.
    public struct Block: Equatable, Sendable {
        public var action: String
        public var target: String
        public var settings: [(key: String, value: String)]

        public init(action: String, target: String, settings: [String: String]) {
            self.action = action
            self.target = target
            self.settings = settings.sorted { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }.map { (key: $0.key, value: $0.value) }
        }

        init(action: String, target: String, orderedSettings: [(key: String, value: String)]) {
            self.action = action
            self.target = target
            self.settings = orderedSettings
        }

        public static func == (lhs: Block, rhs: Block) -> Bool {
            lhs.action == rhs.action && lhs.target == rhs.target
                && lhs.settings.map(\.key) == rhs.settings.map(\.key)
                && lhs.settings.map(\.value) == rhs.settings.map(\.value)
        }

        /// The settings as a dictionary.
        public var dictionary: [String: String] {
            Dictionary(settings.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        }
    }

    /// Renders blocks exactly as `xcodebuild -showBuildSettings` prints them on standard output.
    public static func render(_ blocks: [Block]) -> String {
        var out = ""
        for block in blocks {
            out += "Build settings for action \(block.action) and target \(headerName(block.target)):\n"
            for setting in block.settings {
                out += "    \(setting.key) = \(setting.value)\n"
            }
            out += "\n"
        }
        return out
    }

    /// Renders blocks as `xcodebuild -showBuildSettings -json` prints them: Foundation's
    /// JSON writer with sorted keys (case-insensitive, numeric and locale-aware, so
    /// `GCC_C_LANGUAGE_STANDARD` before `GCC3_VERSION`), pretty printed, slashes not escaped, and
    /// a final newline. Checked against all 276 successful `-json` captures of the corpus
    /// references at hand, byte for byte.
    public static func renderJSON(_ blocks: [Block]) throws -> String {
        let objects: [[String: Any]] = blocks.map { block in
            ["action": block.action, "buildSettings": block.dictionary, "target": block.target]
        }
        let data = try JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// A target name as a block header spells it (observed with every ASCII punctuation
    /// character: loader-experiments `target-names`): as is when it is made of ASCII letters and
    /// digits, non-ASCII characters and `-._+,=/`; otherwise in double quotes, with `"` and `\`
    /// escaped by a backslash (`"With Space"`, `"Double\"Name"`).
    public static func headerName(_ name: String) -> String {
        let plain = !name.isEmpty && name.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", ".", "_", "+", ",", "=", "/": return true
            default: return !scalar.isASCII
            }
        }
        if plain { return name }
        return "\"" + name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The target name a block header spells with ``headerName(_:)``.
    static func targetName(header: String) -> String {
        guard header.count >= 2, header.hasPrefix("\""), header.hasSuffix("\"") else { return header }
        var name = ""
        var escaped = false
        for character in header.dropFirst().dropLast() {
            if escaped || character != "\\" {
                name.append(character)
                escaped = false
            } else {
                escaped = true
            }
        }
        return name
    }

    /// The lines xcodebuild prints before the blocks when the workspace uses Swift packages, one
    /// listing per package (`Name: URL @ 1.2.3`). xcodebuild's own package order varies from
    /// one run to the next; nothing is printed for a workspace without packages.
    public static func renderResolvedPackages(_ listings: [String]) -> String {
        guard !listings.isEmpty else { return "" }
        return "Resolve Package Graph\n\n\nResolved source packages:\n" + listings.map { "  \($0)\n" }.joined() + "\n"
    }

    /// Parses `xcodebuild -showBuildSettings` output. Lines outside blocks (for example the
    /// "Command line invocation" preamble some Xcode versions print) are ignored.
    public static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var current: (action: String, target: String, settings: [(key: String, value: String)])?
        let headerPrefix = "Build settings for action "
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(headerPrefix), line.hasSuffix(":") {
                if let current {
                    blocks.append(Block(action: current.action, target: current.target, orderedSettings: current.settings))
                }
                let body = line.dropFirst(headerPrefix.count).dropLast()
                if let range = body.range(of: " and target ") {
                    current = (String(body[..<range.lowerBound]), targetName(header: String(body[range.upperBound...])), [])
                } else {
                    current = (String(body), "", [])
                }
                continue
            }
            guard current != nil, line.hasPrefix("    ") else { continue }
            let content = line.dropFirst(4)
            if let separator = content.range(of: " = ") {
                current!.settings.append((key: String(content[..<separator.lowerBound]), value: String(content[separator.upperBound...])))
            } else if content.hasSuffix(" =") {
                current!.settings.append((key: String(content.dropLast(2)), value: ""))
            }
        }
        if let current {
            blocks.append(Block(action: current.action, target: current.target, orderedSettings: current.settings))
        }
        return blocks
    }
}
