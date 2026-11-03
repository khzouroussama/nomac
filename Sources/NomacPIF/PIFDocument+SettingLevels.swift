import Foundation
import NomacCore
import NomacProject

extension PIFDocument {
    /// The assignments of one level of a target configuration's settings: those the target's or
    /// the project's configuration writes, or those of its base xcconfig file and its includes.
    public struct SettingLevel: Sendable, Equatable {
        public var assignments: [XCConfigFile.Assignment]
        public var isXCConfig: Bool

        public init(assignments: [XCConfigFile.Assignment], isXCConfig: Bool) {
            self.assignments = assignments
            self.isXCConfig = isXCConfig
        }
    }

    /// The levels of the configuration `name` of the target `guid`, the highest first: the
    /// target's configuration (its settings in key order), its base xcconfig, the project's
    /// configuration of that name and its base xcconfig.
    public func settingLevels(target guid: String, configuration name: String) -> [SettingLevel] {
        guard let target = objects.first(where: { $0.type == "target" && $0.contents.objectValue?["guid"]?.stringValue == guid }),
              let project = objects.first(where: { object in
                  object.type == "project" && (object.contents.objectValue?["targets"]?.arrayValue ?? []).contains(.string(target.signature))
              })?.contents.objectValue,
              let directory = project["projectDirectory"]?.stringValue else { return [] }
        var files: [String: String] = [:]
        if let tree = project["groupTree"] { Self.collectFiles(tree, directory: directory, projectDirectory: directory, into: &files) }
        return [target.contents, .object(project)].flatMap { owner -> [SettingLevel] in
            guard let configuration = owner.objectValue?["buildConfigurations"]?.arrayValue?.compactMap(\.objectValue)
                .first(where: { $0["name"]?.stringValue == name }) else { return [] }
            let settings = configuration["buildSettings"]?.objectValue ?? [:]
            let own = settings.keys.sorted().compactMap { key -> XCConfigFile.Assignment? in
                guard let value = settings[key]?.stringValue, let (setting, conditions) = XCConfigFile.key(key) else { return nil }
                return XCConfigFile.Assignment(name: setting, conditions: conditions, value: value)
            }
            let base = configuration["baseConfigurationFileReference"]?.stringValue.flatMap { files[$0] }.map(XCConfigFile.assignments(at:)) ?? []
            return [SettingLevel(assignments: own, isXCConfig: false), SettingLevel(assignments: base, isXCConfig: true)]
        }
    }
}

extension [PIFDocument.SettingLevel] {
    /// The value of `name` as Xcode's destination check reads it from these levels, not as Swift
    /// Build evaluates it: the highest level with an assignment that applies decides, with its
    /// last conditional assignment whose conditions all apply before its last plain one, whatever
    /// their order. A `[sdk=…]` pattern applies to `sdk`, the target's own SDK (`SDK_NAME`); a
    /// `[config=…]` pattern in an xcconfig to `configuration`, the scheme's launch configuration;
    /// any other pattern, `[config=…]` in a project file included, only when it is `*`. Each
    /// `$(NAME)` in the value is read the same way, or, when no level assigns `NAME`, taken from
    /// `evaluated`. `nil` when no level assigns `name`, and for `$(inherited)` or another use of
    /// `$` (loader-experiments `simulator-sdks`, `simulator-sdk-conditions` and its `-project`
    /// variants: every case's exit status as Xcode's; BACKLOG B-089).
    public func xcodeValue(_ name: String, sdk: String, configuration: String, evaluated: [String: String], depth: Int = 0) -> String? {
        func applies(_ assignment: XCConfigFile.Assignment, inXCConfig: Bool) -> Bool {
            assignment.conditions.allSatisfy { parameter, pattern in
                switch parameter {
                case "sdk": ProjectGenerator.matches(sdk, pattern: pattern)
                case "config" where inXCConfig: ProjectGenerator.matches(configuration, pattern: pattern)
                default: pattern == "*"
                }
            }
        }
        let chosen = lazy.compactMap { level -> String? in
            let assignments = level.assignments.filter { $0.name == name }
            return (assignments.last { !$0.conditions.isEmpty && applies($0, inXCConfig: level.isXCConfig) } ?? assignments.last { $0.conditions.isEmpty })?.value
        }.first
        guard let chosen, depth < 8 else { return nil }
        var macros: [String: String] = [:]
        for reference in LegacyBuildFolder.references(in: chosen) where reference != "inherited" {
            macros[reference] = xcodeValue(reference, sdk: sdk, configuration: configuration, evaluated: evaluated, depth: depth + 1) ?? evaluated[reference]
        }
        return LegacyBuildFolder.expand(chosen, macros)
    }
}
