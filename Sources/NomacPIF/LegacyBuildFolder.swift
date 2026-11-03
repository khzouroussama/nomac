import Foundation
import NomacCore
import NomacProject

/// The folder of a project's products under Xcode's legacy build location: its
/// `CONFIGURATION_BUILD_DIR` as the project's own settings give it. Xcode hashes a product's path
/// in it for the GUID of a build file whose reference proxy's product is not found (docs/formats/pif.md
/// "Build files"; envelope-experiments `unresolved-proxies`, 40 cases).
public enum LegacyBuildFolder {
    /// The settings the folder depends on.
    static let settingNames: Set<String> = ["SDKROOT", "SYMROOT", "BUILD_DIR", "CONFIGURATION_BUILD_DIR"]

    /// `EFFECTIVE_PLATFORM_NAME` for the SDKs observed; `macosx` is also the SDK of a project that
    /// sets none.
    static let platformSuffixes = ["macosx": "", "iphoneos": "-iphoneos", "iphonesimulator": "-iphonesimulator", "appletvos": "-appletvos",
                                   "watchos": "-watchos", "xros": "-xros"]

    /// The configuration whose settings count: `Debug`, else the first (`configurations`,
    /// `configurations-release-first`, `configurations-named`).
    public static func configuration(among names: [String]) -> String? {
        names.contains("Debug") ? "Debug" : names.first
    }

    /// The folder, from the project configuration ``configuration(among:)`` names: `settings`, its
    /// own (`nil` for a value that is not a string), and the path of its base xcconfig.
    public static func path(projectDirectory: String, configuration: String, settings: [String: String?], xcconfig: String?) -> String? {
        var own: [XCConfigFile.Assignment] = []
        for (key, value) in settings.sorted(by: { $0.key < $1.key }) {
            guard let (name, conditions) = XCConfigFile.key(key), settingNames.contains(name) else { continue }
            guard let value else { return nil }
            own.append(XCConfigFile.Assignment(name: name, conditions: conditions, value: value))
        }
        return path(projectDirectory: projectDirectory, configuration: configuration, levels: [own, xcconfig.map(XCConfigFile.assignments(at:)) ?? []])
    }

    /// The folder, from the assignments of each level of the project configuration, its own before
    /// its base xcconfig's, each in order. A level's last assignment of a setting wins, and the
    /// target's settings do not count. `SYMROOT` is `$(PROJECT_DIR)/build` by default, `BUILD_DIR`
    /// `$(SYMROOT)` and `CONFIGURATION_BUILD_DIR` `$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)`;
    /// a relative value is relative to the project directory, which `SRCROOT` names too, and the
    /// path is standardized and decomposed. `nil` when a setting the folder depends on is assigned
    /// with a condition or a macro of another setting, or names an SDK not observed.
    public static func path(projectDirectory: String, configuration: String, levels: [[XCConfigFile.Assignment]]) -> String? {
        var assigned: [String: String] = [:]
        for name in settingNames {
            let assignments = levels.map { $0.filter { $0.name == name } }
            guard assignments.allSatisfy({ $0.allSatisfy(\.conditions.isEmpty) }) else { return nil }
            assigned[name] = assignments.first { !$0.isEmpty }?.last?.value
        }
        guard let suffix = platformSuffixes[assigned["SDKROOT"] ?? "macosx"] else { return nil }
        var macros = ["PROJECT_DIR": projectDirectory, "SRCROOT": projectDirectory, "SOURCE_ROOT": projectDirectory,
                      "CONFIGURATION": configuration, "EFFECTIVE_PLATFORM_NAME": suffix]
        for (name, fallback) in [("SYMROOT", "$(PROJECT_DIR)/build"), ("BUILD_DIR", "$(SYMROOT)"),
                                 ("CONFIGURATION_BUILD_DIR", "$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)")] {
            guard let value = expand(assigned[name] ?? fallback, macros) else { return nil }
            let absolute = value.hasPrefix("/") ? value : (projectDirectory as NSString).appendingPathComponent(value)
            macros[name] = (absolute as NSString).standardizingPath.decomposed
        }
        return macros["CONFIGURATION_BUILD_DIR"]
    }

    /// The names `text` refers to as `$(NAME)` or `${NAME}`.
    static func references(in text: String) -> [String] {
        var names: [String] = []
        var rest = Substring(text)
        while let dollar = rest.firstIndex(of: "$") {
            let reference = rest[rest.index(after: dollar)...]
            guard let open = reference.first, open == "(" || open == "{", let end = reference.firstIndex(of: open == "(" ? ")" : "}") else {
                rest = reference
                continue
            }
            names.append(String(reference[reference.index(after: reference.startIndex)..<end]))
            rest = reference[reference.index(after: end)...]
        }
        return names
    }

    /// `text` with each `$(NAME)` and `${NAME}` replaced by its value in `macros`; `nil` for a name
    /// `macros` lacks or another use of `$`.
    static func expand(_ text: String, _ macros: [String: String]) -> String? {
        var result = ""
        var rest = Substring(text)
        while let dollar = rest.firstIndex(of: "$") {
            result += rest[..<dollar]
            let reference = rest[rest.index(after: dollar)...]
            let close: Character
            switch reference.first {
            case "(": close = ")"
            case "{": close = "}"
            default: return nil
            }
            guard let end = reference.firstIndex(of: close), let value = macros[String(reference[reference.index(after: reference.startIndex)..<end])] else {
                return nil
            }
            result += value
            rest = reference[reference.index(after: end)...]
        }
        return result + rest
    }
}
