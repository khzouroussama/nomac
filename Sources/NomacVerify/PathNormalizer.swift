import Foundation

/// Rewrites machine-specific absolute path roots to symbolic names, so that output
/// produced on two machines can be compared byte for byte.
///
/// This is the only normalization nomac's comparisons perform
/// (docs/adr/0004-reference-artifacts.md). Roots are replaced longest first, so a
/// root nested inside another (a checkout inside the home directory) wins.
public struct PathNormalizer: Sendable, Equatable {
    /// A root to replace and the symbol that replaces it.
    public struct Root: Sendable, Equatable {
        public var path: String
        public var symbol: String

        public init(path: String, symbol: String) {
            self.path = path
            self.symbol = symbol
        }
    }

    public private(set) var roots: [Root]

    public init(roots: [Root]) {
        // Drop empty paths and trailing slashes, then order longest first.
        self.roots = roots
            .map { Root(path: $0.path.count > 1 && $0.path.hasSuffix("/") ? String($0.path.dropLast()) : $0.path, symbol: $0.symbol) }
            .filter { !$0.path.isEmpty && $0.path != "/" }
            .sorted { $0.path.count != $1.path.count ? $0.path.count > $1.path.count : $0.path < $1.path }
    }

    /// Replaces every occurrence of each root that is followed by `/`, a non-path
    /// character, or the end of the text.
    public func normalize(_ text: String) -> String {
        var result = text
        for root in roots {
            result = Self.replace(root.path, with: root.symbol, in: result)
        }
        return result
    }

    private static func replace(_ needle: String, with replacement: String, in haystack: String) -> String {
        var output = ""
        var rest = haystack[...]
        while let range = rest.range(of: needle) {
            let after = range.upperBound < rest.endIndex ? rest[range.upperBound] : nil
            let isBoundary = after == nil || !(after!.isLetter || after!.isNumber || after! == "_" || after! == "-" || after! == ".")
            output += String(rest[..<range.lowerBound])
            output += isBoundary ? replacement : String(rest[range])
            rest = rest[range.upperBound...]
        }
        output += String(rest)
        return output
    }
}
