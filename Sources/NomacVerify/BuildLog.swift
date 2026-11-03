import Foundation

/// The tasks of an xcodebuild log (`build/build.log` of a reference capture), as xcodebuild prints
/// them: a header line naming the rule, then indented `cd`, `export` and command lines, then the
/// task's own output until a blank line.
public struct BuildLog: Sendable, Equatable {
    public struct Task: Sendable, Equatable {
        /// The header line, for example `CompileStoryboard <path> (in target 'App' from project 'App')`.
        public var header: String
        /// The directory the command runs in.
        public var directory: String
        /// The `export` lines' variables.
        public var environment: [String: String]
        /// The command line, unquoted.
        public var command: [String]
        /// The lines the task printed.
        public var output: [String]

        /// The rule, the header's first word (`CompileStoryboard`).
        public var rule: String { String(header.prefix { $0 != " " }) }

        /// The target the header names.
        public var target: String? {
            guard let range = header.range(of: " (in target '", options: .backwards), header.hasSuffix(")") else { return nil }
            let rest = header[range.upperBound...]
            return rest.range(of: "' from project '").map { String(rest[..<$0.lowerBound]) }
        }

        /// The header's words after the rule, unquoted, without the target.
        public var headerArguments: [String] {
            var text = header
            if let range = header.range(of: " (in target '", options: .backwards) { text = String(header[..<range.lowerBound]) }
            return Array(BuildLog.words(text).dropFirst())
        }
    }

    public var tasks: [Task]
    /// The headers xcodebuild lists under "The following build commands failed:".
    public var failed: Set<String>

    public init(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        var tasks: [Task] = []
        var failed = Set<String>()
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line == "The following build commands failed:" {
                index += 1
                while index < lines.count, lines[index].hasPrefix("\t") {
                    failed.insert(String(lines[index].dropFirst()))
                    index += 1
                }
                continue
            }
            guard !line.isEmpty, !line.hasPrefix(" "), index + 2 < lines.count, lines[index + 1].hasPrefix("    cd ") else {
                index += 1
                continue
            }
            let directory = Self.words(String(lines[index + 1].dropFirst(4))).dropFirst().first ?? ""
            var environment: [String: String] = [:]
            var next = index + 2
            while next < lines.count, lines[next].hasPrefix("    export ") {
                if let assignment = Self.words(String(lines[next].dropFirst(4))).dropFirst().first, let equals = assignment.firstIndex(of: "=") {
                    environment[String(assignment[..<equals])] = String(assignment[assignment.index(after: equals)...])
                }
                next += 1
            }
            guard next < lines.count, lines[next].hasPrefix("    ") else {
                index = next
                continue
            }
            let command = Self.words(String(lines[next].dropFirst(4)))
            next += 1
            var output: [String] = []
            while next < lines.count, !lines[next].isEmpty {
                output.append(lines[next])
                next += 1
            }
            tasks.append(Task(header: line, directory: directory, environment: environment, command: command, output: output))
            index = next
        }
        self.tasks = tasks
        self.failed = failed
    }

    /// Splits a command line as a shell does: words separated by unquoted spaces, with backslash
    /// escapes (xcodebuild's quoting: `NetNewsWire\ iOS`, `-fmodules-prune-interval\=86400`) and
    /// single and double quotes.
    public static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
            } else if let open = quote {
                if character == open {
                    quote = nil
                } else if character == "\\" && open == "\"" {
                    escaped = true
                } else {
                    current.append(character)
                }
            } else if character == "\\" {
                escaped = true
                inWord = true
            } else if character == "'" || character == "\"" {
                quote = character
                inWord = true
            } else if character == " " {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(character)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}
