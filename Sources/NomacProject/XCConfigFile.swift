import Foundation
import NomacCore

/// The settings of an xcconfig file and the files it includes.
///
/// Used where Xcode itself reads an xcconfig while generating the PIF (the `INFOPLIST_FILE`
/// behind `bundleIdentifierFromInfoPlist`, the `CODE_SIGN_STYLE` behind `provisioningStyle`).
/// Swift Build evaluates xcconfig files on its own for build settings; this reader does not
/// replace that. Lines are `KEY = value` or `KEY[condition=pattern,…] = value`, with `//`
/// comments, and `#include "path"` / `#include? "path"` resolved against the including file's
/// folder. A later assignment replaces an earlier one, including one from an included file.
public enum XCConfigFile {
    /// One assignment: the setting's name, its conditions (`["sdk": "iphoneos*"]`, empty when it
    /// has none) and its value as written.
    public struct Assignment: Equatable, Sendable {
        public var name: String
        public var conditions: [String: String]
        public var value: String

        public init(name: String, conditions: [String: String], value: String) {
            self.name = name
            self.conditions = conditions
            self.value = value
        }
    }

    /// The unconditional settings.
    public static func settings(at path: String) -> [String: String] {
        var settings: [String: String] = [:]
        for assignment in assignments(at: path) where assignment.conditions.isEmpty {
            settings[assignment.name] = assignment.value
        }
        return settings
    }

    /// The names of the settings the file or its includes assign with a condition.
    public static func conditionalSettingNames(at path: String) -> Set<String> {
        Set(assignments(at: path).filter { !$0.conditions.isEmpty }.map(\.name))
    }

    /// Every assignment of the file, those of its includes in their place.
    public static func assignments(at path: String) -> [Assignment] {
        var assignments: [Assignment] = []
        var visited: Set<String> = []
        read(path, into: &assignments, visited: &visited)
        return assignments
    }

    private static func read(_ path: String, into assignments: inout [Assignment], visited: inout Set<String>) {
        let path = (path as NSString).standardizingPath
        guard visited.insert(path).inserted, let data = FileSystem.contents(atPath: path) else { return }
        let directory = (path as NSString).deletingLastPathComponent
        for rawLine in String(decoding: data, as: UTF8.self).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = String(rawLine)
            if let comment = line.range(of: "//") { line = String(line[..<comment.lowerBound]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#include") {
                guard let open = line.firstIndex(of: "\""), let close = line.lastIndex(of: "\""), open < close else { continue }
                let included = String(line[line.index(after: open)..<close])
                read(included.hasPrefix("/") ? included : directory + "/" + included, into: &assignments, visited: &visited)
                continue
            }
            var depth = 0
            guard let equals = line.firstIndex(where: { character in
                if character == "[" { depth += 1 } else if character == "]" { depth -= 1 }
                return character == "=" && depth == 0
            }), let (name, conditions) = key(line[..<equals].trimmingCharacters(in: .whitespaces)) else { continue }
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasSuffix(";") { value.removeLast() }
            assignments.append(Assignment(name: name, conditions: conditions, value: value))
        }
    }

    /// The setting name and conditions of an assignment's key, as an xcconfig or a project's
    /// `buildSettings` writes it (`NAME`, `NAME[sdk=iphoneos*]`, `NAME[sdk=iphoneos*][arch=arm64]`,
    /// `NAME[sdk=iphoneos*,arch=arm64]`); `nil` when the name is not a setting name.
    public static func key(_ text: String) -> (name: String, conditions: [String: String])? {
        var name = Substring(text)
        var conditions: [String: String] = [:]
        if let bracket = text.firstIndex(of: "["), bracket > text.startIndex {
            for condition in text[bracket...].split(whereSeparator: { "[],".contains($0) }) {
                let parts = condition.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { conditions[parts[0]] = parts[1] }
            }
            name = text[..<bracket]
        }
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return (String(name), conditions)
    }
}
