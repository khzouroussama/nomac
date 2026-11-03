import Foundation

/// The result of comparing nomac's `-showBuildSettings` output with Xcode's.
public struct SettingsComparison: Sendable, Equatable {
    /// A single difference.
    public enum Difference: Sendable, Equatable, CustomStringConvertible {
        case missingBlock(target: String)
        case extraBlock(target: String)
        case blockOrder(expected: [String], actual: [String])
        case missing(target: String, key: String, expected: String)
        case extra(target: String, key: String, actual: String)
        case value(target: String, key: String, expected: String, actual: String)

        public var description: String {
            switch self {
            case .missingBlock(let target): return "target \(target): block missing from nomac's output"
            case .extraBlock(let target): return "target \(target): block present only in nomac's output"
            case .blockOrder(let expected, let actual): return "target order differs: Xcode \(expected), nomac \(actual)"
            case .missing(let target, let key, let expected): return "target \(target): missing \(key) = \(expected)"
            case .extra(let target, let key, let actual): return "target \(target): extra \(key) = \(actual)"
            case .value(let target, let key, let expected, let actual): return "target \(target): \(key)\n    Xcode: \(expected)\n    nomac: \(actual)"
            }
        }
    }

    /// `true` when the normalized texts are identical byte for byte.
    public var identical: Bool
    /// Every difference between the two outputs, in target and key order.
    public var differences: [Difference]
    /// The number of settings compared (in Xcode's output).
    public var settingCount: Int

    /// Compares two `-showBuildSettings` outputs after normalizing both with `normalizer`.
    public static func compare(expected: String, actual: String, normalizer: PathNormalizer) -> SettingsComparison {
        let normalizedExpected = normalizer.normalize(expected)
        let normalizedActual = normalizer.normalize(actual)
        let expectedBlocks = ShowBuildSettings.parse(normalizedExpected)
        let actualBlocks = ShowBuildSettings.parse(normalizedActual)
        // Compare only the blocks: a preamble outside them (e.g. "Command line invocation")
        // describes the command, not the settings. No block on either side is a match:
        // xcodebuild prints none for a scheme that builds only package products.
        let identical = ShowBuildSettings.render(expectedBlocks) == ShowBuildSettings.render(actualBlocks)
        var differences: [Difference] = []
        let actualByTarget = Dictionary(actualBlocks.map { ($0.target, $0) }, uniquingKeysWith: { first, _ in first })
        let expectedTargets = Set(expectedBlocks.map(\.target))
        for block in expectedBlocks {
            guard let other = actualByTarget[block.target] else {
                differences.append(.missingBlock(target: block.target))
                continue
            }
            let actualSettings = other.dictionary
            let expectedSettings = block.dictionary
            for (key, value) in block.settings {
                if let actualValue = actualSettings[key] {
                    if actualValue != value {
                        differences.append(.value(target: block.target, key: key, expected: value, actual: actualValue))
                    }
                } else {
                    differences.append(.missing(target: block.target, key: key, expected: value))
                }
            }
            for (key, value) in other.settings where expectedSettings[key] == nil {
                differences.append(.extra(target: block.target, key: key, actual: value))
            }
        }
        for block in actualBlocks where !expectedTargets.contains(block.target) {
            differences.append(.extraBlock(target: block.target))
        }
        if differences.isEmpty, expectedBlocks.map(\.target) != actualBlocks.map(\.target) {
            differences.append(.blockOrder(expected: expectedBlocks.map(\.target), actual: actualBlocks.map(\.target)))
        }
        return SettingsComparison(identical: identical, differences: differences, settingCount: expectedBlocks.reduce(0) { $0 + $1.settings.count })
    }
}
