import Foundation
import NomacCore

/// How the Mac that Xcode runs on answers the host conditions of `#if` (`os`, `arch`,
/// `canImport`, ...) when it compiles a package manifest.
///
/// Xcode evaluates manifests on that Mac; nomac evaluates them on Linux, where `#if os(Linux)`
/// holds (icecubes: SQLite.swift picks its default traits that way). The answers were observed
/// with Xcode 27.0 on an Apple silicon Mac (`package-experiments`, docs/formats/pif.md "Package
/// manifests") and are kept in the Xcode profile.
public struct HostConditions: Sendable, Equatable {
    /// Answers by condition, written `name(argument)` without spaces.
    public var answers: [String: Bool]
    /// Condition kinds whose unlisted arguments are false (an `os` other than the listed ones
    /// is not the host's).
    public var closedKinds: Set<String>

    public init(answers: [String: Bool], closedKinds: Set<String>) {
        self.answers = answers
        self.closedKinds = closedKinds
    }

    /// The condition kinds that depend on the host. Every other condition (`swift(>=…)`,
    /// `compiler(>=…)`, `hasFeature(…)`, custom flags) is left to the compiler.
    public static let hostKinds: Set<String> = [
        "os", "arch", "canImport", "targetEnvironment", "_endian", "_pointerBitWidth", "_runtime",
        "_hasAtomicBitWidth", "_ptrauth",
    ]

    /// The answer for `kind(argument)`, or nil if nomac does not know it.
    public func answer(kind: String, argument: String) -> Bool? {
        if let answer = answers["\(kind)(\(argument))"] { return answer }
        return closedKinds.contains(kind) ? false : nil
    }

    /// The reference Mac of the Xcode nomac reproduces (`XcodeProfile.manifestHostConditions`).
    public static let mac = HostConditions(answers: XcodeProfile.current.manifestHostConditions.answers,
                                           closedKinds: Set(XcodeProfile.current.manifestHostConditions.closedKinds))
}

/// Rewrites the host conditions in a manifest's `#if` and `#elseif` lines to `true` or
/// `false`, so that the compiler on Linux takes the branches the Mac takes.
///
/// Only conditions of ``HostConditions/hostKinds`` that the host table answers are replaced;
/// the directive structure, every other condition and all other text stay byte for byte, so
/// diagnostics keep their line numbers. Comments and string literals (including raw,
/// multi-line and interpolated ones) are skipped, so `#if` inside them is not a directive.
///
/// The Mac's branches import its C library as `Darwin`, which Linux does not have
/// (kickstarter: facebook-ios-sdk's manifest takes `#if os(Linux) import Glibc #else import
/// Darwin.C #endif` for `getenv`). Off Darwin, an `import` of `Darwin` or one of its submodules
/// at the start of a line names the C library of the machine instead (``hostCLibrary``).
public enum ManifestConditions {
    public struct Result: Equatable, Sendable {
        /// The rewritten source.
        public var source: String
        /// Host conditions the table has no answer for, left to the compiler (`canImport(X)`).
        public var unanswered: [String]
    }

    /// The module of the C library where nomac compiles manifests, or nil on Darwin.
    #if canImport(Darwin)
    public static let hostCLibrary: String? = nil
    #elseif canImport(Glibc)
    public static let hostCLibrary: String? = "Glibc"
    #elseif canImport(Musl)
    public static let hostCLibrary: String? = "Musl"
    #else
    public static let hostCLibrary: String? = nil
    #endif

    /// - Parameter cLibrary: the module `Darwin` imports become, or nil to keep them.
    public static func rewrite(_ source: String, host: HostConditions = .mac, cLibrary: String? = hostCLibrary) -> Result {
        var scanner = Scanner(bytes: Array(source.utf8), host: host, cLibrary: cLibrary)
        scanner.run()
        return Result(source: String(decoding: scanner.output, as: UTF8.self), unanswered: scanner.unanswered)
    }

    private struct Scanner {
        let bytes: [UInt8]
        let host: HostConditions
        let cLibrary: String?
        var index = 0
        var output: [UInt8] = []
        var unanswered: [String] = []

        init(bytes: [UInt8], host: HostConditions, cLibrary: String?) {
            self.bytes = bytes
            self.host = host
            self.cLibrary = cLibrary
            output.reserveCapacity(bytes.count)
        }

        mutating func run() {
            var atLineStart = true
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\n") {
                    copy(to: index + 1)
                    atLineStart = true
                } else if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r") {
                    copy(to: index + 1)
                } else if byte == UInt8(ascii: "/"), at(index + 1) == UInt8(ascii: "/") {
                    copy(to: endOfLineComment(index))
                } else if byte == UInt8(ascii: "/"), at(index + 1) == UInt8(ascii: "*") {
                    copy(to: endOfBlockComment(index))
                    atLineStart = false
                } else if byte == UInt8(ascii: "#"), atLineStart, let keywordEnd = conditionalDirective(index) {
                    copy(to: keywordEnd)
                    rewriteCondition(from: keywordEnd)
                    atLineStart = false
                } else if byte == UInt8(ascii: "i"), atLineStart, let cLibrary, let module = darwinImport(index) {
                    copy(to: module.lowerBound)
                    output.append(contentsOf: Array(cLibrary.utf8))
                    index = module.upperBound
                    atLineStart = false
                } else if isStringStart(index) {
                    copy(to: endOfString(index))
                    atLineStart = false
                } else {
                    copy(to: index + 1)
                    atLineStart = false
                }
            }
        }

        private func at(_ position: Int) -> UInt8? {
            position < bytes.count ? bytes[position] : nil
        }

        private mutating func copy(to end: Int) {
            output.append(contentsOf: bytes[index..<end])
            index = end
        }

        // MARK: Comments and literals

        private func endOfLineComment(_ start: Int) -> Int {
            var position = start
            while position < bytes.count, bytes[position] != UInt8(ascii: "\n") { position += 1 }
            return position
        }

        private func endOfBlockComment(_ start: Int) -> Int {
            var depth = 0
            var position = start
            while position < bytes.count {
                if bytes[position] == UInt8(ascii: "/"), at(position + 1) == UInt8(ascii: "*") {
                    depth += 1
                    position += 2
                } else if bytes[position] == UInt8(ascii: "*"), at(position + 1) == UInt8(ascii: "/") {
                    depth -= 1
                    position += 2
                    if depth == 0 { return position }
                } else {
                    position += 1
                }
            }
            return position
        }

        /// A string literal starts with `"`, or with one or more `#` followed by `"`.
        private func isStringStart(_ position: Int) -> Bool {
            var cursor = position
            while at(cursor) == UInt8(ascii: "#") { cursor += 1 }
            return at(cursor) == UInt8(ascii: "\"")
        }

        private func endOfString(_ start: Int) -> Int {
            var position = start
            var hashes = 0
            while at(position) == UInt8(ascii: "#") {
                hashes += 1
                position += 1
            }
            let multiline = at(position + 1) == UInt8(ascii: "\"") && at(position + 2) == UInt8(ascii: "\"")
            position += multiline ? 3 : 1
            func hashesFollow(_ cursor: Int) -> Bool {
                (0..<hashes).allSatisfy { at(cursor + $0) == UInt8(ascii: "#") }
            }
            while position < bytes.count {
                let byte = bytes[position]
                if byte == UInt8(ascii: "\\"), hashesFollow(position + 1) {
                    let escaped = position + 1 + hashes
                    position = at(escaped) == UInt8(ascii: "(") ? endOfInterpolation(escaped) : escaped + 1
                } else if byte == UInt8(ascii: "\"") {
                    if multiline {
                        if at(position + 1) == UInt8(ascii: "\""), at(position + 2) == UInt8(ascii: "\""), hashesFollow(position + 3) {
                            return position + 3 + hashes
                        }
                    } else if hashesFollow(position + 1) {
                        return position + 1 + hashes
                    }
                    position += 1
                } else if byte == UInt8(ascii: "\n"), !multiline {
                    return position
                } else {
                    position += 1
                }
            }
            return position
        }

        /// The end of `\( … )` in a string, starting at its `(`.
        private func endOfInterpolation(_ open: Int) -> Int {
            var depth = 0
            var position = open
            while position < bytes.count {
                let byte = bytes[position]
                if byte == UInt8(ascii: "(") {
                    depth += 1
                    position += 1
                } else if byte == UInt8(ascii: ")") {
                    depth -= 1
                    position += 1
                    if depth == 0 { return position }
                } else if isStringStart(position) {
                    position = endOfString(position)
                } else {
                    position += 1
                }
            }
            return position
        }

        // MARK: Imports

        /// The module path of `import Darwin` or `import Darwin.<submodule>…` at `position`.
        private func darwinImport(_ position: Int) -> Range<Int>? {
            let keyword = Array("import".utf8)
            guard position + keyword.count < bytes.count, Array(bytes[position..<(position + keyword.count)]) == keyword else { return nil }
            var start = position + keyword.count
            guard bytes[start] == UInt8(ascii: " ") || bytes[start] == UInt8(ascii: "\t") else { return nil }
            while at(start) == UInt8(ascii: " ") || at(start) == UInt8(ascii: "\t") { start += 1 }
            let darwin = Array("Darwin".utf8)
            guard start + darwin.count <= bytes.count, Array(bytes[start..<(start + darwin.count)]) == darwin else { return nil }
            var end = start + darwin.count
            if let next = at(end), Self.isIdentifierByte(next) { return nil }
            while at(end) == UInt8(ascii: "."), let next = at(end + 1), Self.isIdentifierStart(next) {
                end += 1
                while let byte = at(end), Self.isIdentifierByte(byte) { end += 1 }
            }
            return start..<end
        }

        // MARK: Directives

        /// The end of `#if` or `#elseif` at `position`, if a conditional directive starts there.
        private func conditionalDirective(_ position: Int) -> Int? {
            var end = position + 1
            while let byte = at(end), Self.isIdentifierByte(byte) { end += 1 }
            let keyword = String(decoding: bytes[(position + 1)..<end], as: UTF8.self)
            return keyword == "if" || keyword == "elseif" ? end : nil
        }

        /// Rewrites the condition that follows a directive keyword: to the end of the line, or
        /// further while parentheses are open, stopping at a comment.
        private mutating func rewriteCondition(from start: Int) {
            var position = start
            var depth = 0
            while position < bytes.count {
                let byte = bytes[position]
                if byte == UInt8(ascii: "\n"), depth == 0 { break }
                if byte == UInt8(ascii: "/"), at(position + 1) == UInt8(ascii: "/") || at(position + 1) == UInt8(ascii: "*") { break }
                if byte == UInt8(ascii: "(") { depth += 1 }
                if byte == UInt8(ascii: ")") { depth -= 1 }
                position += 1
            }
            var cursor = start
            while cursor < position {
                let byte = bytes[cursor]
                guard Self.isIdentifierStart(byte), cursor == start || !Self.isIdentifierByte(bytes[cursor - 1]) else {
                    output.append(byte)
                    cursor += 1
                    continue
                }
                var nameEnd = cursor
                while nameEnd < position, Self.isIdentifierByte(bytes[nameEnd]) { nameEnd += 1 }
                let name = String(decoding: bytes[cursor..<nameEnd], as: UTF8.self)
                var open = nameEnd
                while open < position, bytes[open] == UInt8(ascii: " ") || bytes[open] == UInt8(ascii: "\t") { open += 1 }
                guard HostConditions.hostKinds.contains(name), open < position, bytes[open] == UInt8(ascii: "("),
                      let close = closingParenthesis(open, limit: position) else {
                    output.append(contentsOf: bytes[cursor..<nameEnd])
                    cursor = nameEnd
                    continue
                }
                let argument = String(decoding: bytes[(open + 1)..<close], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !argument.contains(","), let answer = host.answer(kind: name, argument: argument) {
                    output.append(contentsOf: Array((answer ? "true" : "false").utf8))
                } else if name == "canImport", let module = argument.split(separator: ",").first,
                          host.answer(kind: name, argument: module.trimmingCharacters(in: .whitespaces)) == false {
                    // A module the Mac does not have fails a version check too.
                    output.append(contentsOf: Array("false".utf8))
                } else {
                    unanswered.append("\(name)(\(argument))")
                    output.append(contentsOf: bytes[cursor...close])
                }
                cursor = close + 1
            }
            index = position
        }

        private func closingParenthesis(_ open: Int, limit: Int) -> Int? {
            var depth = 0
            for position in open..<limit {
                if bytes[position] == UInt8(ascii: "(") { depth += 1 }
                if bytes[position] == UInt8(ascii: ")") {
                    depth -= 1
                    if depth == 0 { return position }
                }
            }
            return nil
        }

        private static func isIdentifierStart(_ byte: UInt8) -> Bool {
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) || byte == UInt8(ascii: "_")
        }

        private static func isIdentifierByte(_ byte: UInt8) -> Bool {
            isIdentifierStart(byte) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
        }
    }
}
