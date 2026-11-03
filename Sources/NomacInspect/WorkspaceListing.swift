import Foundation
import NomacCore
import NomacProject

/// What `xcodebuild -list` reports for a project or a workspace (loader-experiments `schemes`
/// and `workspace`; docs/formats/list.md).
public struct WorkspaceListing: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case project, workspace
    }

    public var kind: Kind
    public var name: String
    /// A project's targets, in project order; a workspace lists none.
    public var targets: [String]
    /// A project's build configurations, in the order of its configuration list.
    public var configurations: [String]
    /// The configuration xcodebuild uses with neither `-configuration` nor `-scheme`.
    public var defaultConfiguration: String
    /// Every scheme by its listed name, in xcodebuild's order.
    public var schemes: [String]

    /// Lists `workspace` with `schemes`, as ``XcodeWorkspace/schemes(packages:settings:userName:)`` finds them.
    public init(workspace: XcodeWorkspace, schemes: [XcodeScheme]) {
        let project = workspace.isImplicit ? workspace.projects.first : nil
        kind = project == nil ? .workspace : .project
        name = workspace.name
        targets = project?.project.targets.map(\.name) ?? []
        let configurationList = project?.project.buildConfigurationList
        configurations = configurationList?.buildConfigurations.map(\.name) ?? []
        defaultConfiguration = configurationList?.defaultConfigurationName ?? configurations.last ?? ""
        self.schemes = Self.ordered(schemes.map(\.listedName))
    }

    /// `names` in the order of `-list`: Unicode collation in English, so case, accents and
    /// ligatures only break ties, lowercase first, and digits are not read as numbers
    /// (loader-experiments `scheme-order`: `10lives` before `9lives`, `u`, `U`, `Ü`, `Uber`,
    /// `über`; `unicode-list-order`: decomposed and composed names, `Æ`, `ß`, the Angstrom and Ohm
    /// signs; the same on Linux). Canonically equivalent names compare equal and keep their order.
    static func ordered(_ names: [String]) -> [String] {
        let english = Locale(identifier: "en")
        return names.enumerated().sorted { first, second in
            switch first.element.compare(second.element, options: [], range: nil, locale: english) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return first.offset < second.offset
            }
        }.map(\.element)
    }

    /// The text `xcodebuild -list` prints after its command-line and package preambles.
    public var text: String {
        func list(_ names: [String]) -> String { names.map { "        \($0)\n" }.joined() }
        switch kind {
        case .project:
            return """
            Information about project "\(name)":
                Targets:
            \(list(targets))
                Build Configurations:
            \(list(configurations))
                If no build configuration is specified and -scheme is not passed then "\(defaultConfiguration)" is used.

                Schemes:
            \(list(schemes))

            """
        case .workspace:
            return "Information about workspace \"\(name)\":\n    Schemes:\n\(list(schemes))\n"
        }
    }

    /// What `xcodebuild -list -json` prints: keys in order, two-space indentation, ` : `
    /// between a key and its value, `/` not escaped.
    public var json: String {
        var fields: [(String, String)] = []
        if kind == .project {
            fields.append(("configurations", Self.json(configurations, indent: 4)))
        }
        fields.append(("name", Self.json(name)))
        fields.append(("schemes", Self.json(schemes, indent: 4)))
        if kind == .project {
            fields.append(("targets", Self.json(targets, indent: 4)))
        }
        let body = fields.map { "    \(Self.json($0.0)) : \($0.1)" }.joined(separator: ",\n")
        return "{\n  \(Self.json(kind.rawValue)) : {\n\(body)\n  }\n}\n"
    }

    private static func json(_ strings: [String], indent: Int) -> String {
        let padding = String(repeating: " ", count: indent)
        guard !strings.isEmpty else { return "[\n\n\(padding)]" }
        return "[\n" + strings.map { "\(padding)  \(json($0))" }.joined(separator: ",\n") + "\n\(padding)]"
    }

    private static func json(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
