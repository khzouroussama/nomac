import Foundation
import NomacCore
import NomacProject
import XcodeProj

extension ProjectGenerator {
    // MARK: Targets

    mutating func targetContents(_ target: PBXTarget) throws -> PIFValue {
        var contents: [String: PIFValue] = [
            "guid": .string(guid(target)),
            "name": .string(target.name),
            "buildConfigurations": .array(try buildConfigurations(target.buildConfigurationList, searchPaths: synchronizedSearchPaths(of: target))),
            "dependencies": .array(dependencies(target)),
        ]
        switch target {
        case let legacy as PBXLegacyTarget:
            contents["type"] = .string("external")
            contents["toolPath"] = .string(legacy.buildToolPath ?? "")
            contents["arguments"] = .string(legacy.buildArgumentsString ?? "")
            contents["workingDirectory"] = .string(legacy.buildWorkingDirectory ?? "")
            contents["passBuildSettingsInEnvironment"] = .bool(legacy.passBuildSettingsInEnvironment)
            return .object(contents)
        case is PBXAggregateTarget:
            // Like a native target, without a product (`loader-experiments`).
            contents["type"] = .string("aggregate")
            contents["buildPhases"] = .array(try target.buildPhases.compactMap { try buildPhase($0, target: target) })
            contents["buildRules"] = .array(target.buildRules.map(buildRule))
            contents["provisioningSourceData"] = .array(provisioningSourceData(target))
            contents["classPrefix"] = classPrefix.map(PIFValue.string)
            return .object(contents)
        default:
            contents["type"] = .string("standard")
        }

        contents["buildPhases"] = .array(try target.buildPhases.compactMap { try buildPhase($0, target: target) })
        contents["buildRules"] = .array(target.buildRules.map(buildRule))
        contents["classPrefix"] = classPrefix.map(PIFValue.string)
        contents["productTypeIdentifier"] = .string(target.productType?.rawValue ?? "")
        let productName = productName(target, path: target.product.flatMap { $0.path ?? $0.name } ?? "")
        if let product = target.product {
            contents["productReference"] = .object(["guid": .string(guid(product)), "name": .string(productName), "type": .string("product")])
        }
        if let language = predominantSourceCodeLanguage(target) {
            contents["predominantSourceCodeLanguage"] = .string(language)
        }
        contents["provisioningSourceData"] = .array(provisioningSourceData(target))
        // A test bundle names its performance-test baseline location, whether or not it exists
        // (tofu, retro-rampage), when its product's extension is `xctest`, whatever its type
        // (envelope-experiments `survey-shapes-3`: an OCUnit bundle has none unless its
        // WRAPPER_EXTENSION is `xctest`, a unit test bundle whose WRAPPER_EXTENSION is `octest` none).
        if Self.testBundleProductTypes.contains(target.productType?.rawValue ?? ""), (productName as NSString).pathExtension == "xctest" {
            contents["performanceTestsBaselinesPath"] = .string(project.path + "/xcshareddata/xcbaselines/\(target.uuid).xcbaseline")
        }
        return .object(contents)
    }

    static let testBundleProductTypes: Set<String> = [
        "com.apple.product-type.bundle.unit-test",
        "com.apple.product-type.bundle.ui-testing",
        "com.apple.product-type.bundle.ocunit-test",
    ]

    /// The project's `CLASSPREFIX`, which native and aggregate targets carry too, empty or not;
    /// legacy targets never do (loader-experiments `class-prefix`, `-empty`, `-unset`).
    var classPrefix: String? {
        Self.stringAttribute(project.project.attributes["CLASSPREFIX"])
    }

    /// Target dependencies, those that name a package product (`productRef`) included in place
    /// (firefox's `RustMozillaAppServices` and `Glean`), then one entry per build file of the
    /// target's first Frameworks phase that names a package product, the products Xcode adds to
    /// that phase included, each with its own platform filters (netnewswire, icecubes). Nothing
    /// is merged: a target or product named twice is listed twice, even through one object
    /// (swiftfin: 56 entries, eleven of them `StatefulMacros`; loader-experiments
    /// `product-target-dependencies`, `product-duplicates`). Other phases name none, so a
    /// product only a copy-files phase embeds is not listed (home-assistant's `WatchApp`:
    /// `PromiseKitDynamic` once).
    func dependencies(_ target: PBXTarget) -> [PIFValue] {
        var result: [PIFValue] = target.dependencies.compactMap { dependency in
            let named: (String?, String?)?
            if let product = dependency.product {
                named = context.packageProducts[product.uuid].map { ($0.guid, $0.name) }
            } else {
                named = dependencyTarget(dependency)
            }
            guard let (guid, name) = named else { return nil }
            var contents: [String: PIFValue] = [:]
            if let name { contents["name"] = .string(name) }
            if let guid { contents["guid"] = .string(guid) }
            if let filters = Self.platformFilters(Self.filterNames(dependency.platformFilters, dependency.platformFilter)) {
                contents["platformFilters"] = filters
            }
            return .object(contents)
        }
        guard let frameworks = target.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase }) else { return result }
        let products = unlinkedProducts(in: frameworks, of: target).map { ($0, nil as [String]?) }
            + (frameworks.files ?? []).compactMap { file in file.product.map { ($0, Self.filterNames(file.platformFilters, file.platformFilter)) } }
        for (product, filters) in products {
            guard let package = context.packageProducts[product.uuid] else { continue }
            var contents: [String: PIFValue] = ["guid": .string(package.guid), "name": .string(package.name)]
            if let filters = Self.platformFilters(filters) { contents["platformFilters"] = filters }
            result.append(.object(contents))
        }
        return result
    }

    /// The `packageProductDependencies` Xcode adds to `phase` when it is the target's first
    /// Frameworks phase: those no build file of the phase links, each inserted at the start in
    /// list order, so they end up reversed. A target without a Frameworks phase links none of
    /// them (loader-experiments `unlinked-products`).
    func unlinkedProducts(in phase: PBXBuildPhase, of target: PBXTarget) -> [XCSwiftPackageProductDependency] {
        guard phase === target.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase }) else { return [] }
        let linked = Set((phase.files ?? []).compactMap { $0.product?.uuid })
        return (target.packageProductDependencies ?? []).filter { !linked.contains($0.uuid) }.reversed()
    }

    /// The GUID and name of the target a dependency names: a target of this project, or one of
    /// another project of the workspace through a project reference, named
    /// `<target> (from <Project>.xcodeproj)` (`loader-experiments`), with no GUID when that
    /// target does not resolve: its project is not on disk (`project-references-missing`) or has
    /// no object with its ID (`project-references-stale`). A proxy into this project resolves by
    /// its remote ID, the dependency's `target` missing or naming no object; one that names no
    /// target keeps its place, named by its `remoteInfo`, else the dependency's `name`, else not
    /// at all (loader-experiments `dependency-proxies`; session's `SessionUtil`). A remote ID that
    /// names no target, in this project or another, resolves by `remoteInfo` as a target name
    /// (`dependency-proxies`: StaleLib; `project-references-renamed`; delta's Harmony).
    func dependencyTarget(_ dependency: PBXTargetDependency) -> (String?, String?)? {
        if let dependent = dependency.target {
            return context.guid(of: dependent).map { ($0, dependent.name) }
        }
        guard let proxy = dependency.targetProxy, proxy.proxyType == .nativeTarget else { return nil }
        if case .project = proxy.containerPortal {
            let remoteID: String?
            switch proxy.remoteGlobalID {
            case .string(let id)?: remoteID = id
            case .object(let object)?: remoteID = object.uuid
            case nil: remoteID = nil
            }
            let targets = project.project.targets
            if let dependent = targets.first(where: { $0.uuid == remoteID }) ?? targets.first(where: { $0.name == proxy.remoteInfo }) {
                return context.guid(of: dependent).map { ($0, dependent.name) }
            }
            return (nil, proxy.remoteInfo ?? dependency.name)
        }
        guard let (path, remoteID) = remoteObject(proxy) else { return nil }
        let name = proxy.remoteInfo ?? dependency.name ?? ""
        let guid = context.targetGUIDByProjectAndID[path]?[remoteID] ?? proxy.remoteInfo.flatMap { context.targetGUIDByProjectAndName[path]?[$0] }
        return (guid, "\(name) (from \((path as NSString).lastPathComponent))")
    }

    /// The standardized path of the project a container item proxy points into, and the object
    /// ID it names there.
    func remoteObject(_ proxy: PBXContainerItemProxy) -> (String, String)? {
        guard case .fileReference(let reference) = proxy.containerPortal,
              let path = try? reference.fullPath(sourceRoot: project.projectDirectory) else { return nil }
        switch proxy.remoteGlobalID {
        case .string(let id)?: return ((path as NSString).standardizingPath, id)
        case .object(let object)?: return ((path as NSString).standardizingPath, object.uuid)
        case nil: return nil
        }
    }

    /// The filters of a build file or a target dependency: its `platformFilters`, else its singular
    /// `platformFilter`, which Xcode reads for `ios` and `maccatalyst` only (gomap,
    /// envelope-experiments `survey-shapes-2`; `survey-shapes-4`: `macos`, `tvos`, `watchos`,
    /// `xros` and `driverkit` give none).
    static func filterNames(_ plural: [String]?, _ singular: String?) -> [String]? {
        plural ?? singular.flatMap { ["ios", "maccatalyst"].contains($0) ? [$0] : nil }
    }

    /// The PIF form of an Xcode platform filter list: each name is a platform, except Mac
    /// Catalyst, the iOS platform in the `maccatalyst` environment (icecubes:
    /// `(ios, maccatalyst)` becomes `[{platform: ios}, {environment: maccatalyst, platform: ios}]`).
    static func platformFilters(_ names: [String]?) -> PIFValue? {
        guard let names, !names.isEmpty else { return nil }
        return .array(names.map { name in
            name == "maccatalyst"
                ? .object(["platform": .string("ios"), "environment": .string("maccatalyst")])
                : .object(["platform": .string(name)])
        })
    }

    /// Xcode records the language of the file type with the most files among the target's build
    /// files, in every phase, synchronized members a phase of the target receives included (the
    /// differential fuzzer's targets without a Sources phase), counting each type apart: three
    /// `.swift` files beat two `.h` and two `.mm` files, both Objective-C++ (loader-experiments
    /// `language-types`; `language-bisect`: one file of each of 37 types gives AppleScript). A tie
    /// goes to the language that comes first in ``languageOrder`` (`language-pairs`, every pair of
    /// 42 types; one `.swift` source and one `.js` resource give JavaScript in icecubes). Seven
    /// types count for languages the PIF does not name: when one of them wins, the target has no
    /// language (`language-weights`: two `sourcecode.ada` files and one Objective-C file;
    /// codegen-file-types, where `sourcecode.ada` ties with every other type). When no build file
    /// counts for a language, the target's synchronized candidates decide, the items its
    /// exception sets remove included (`language-fallback`: an app whose only Swift file is
    /// excluded is Swift; an assembly member that wins leaves the key out, with no fallback).
    func predominantSourceCodeLanguage(_ target: PBXTarget) -> String? {
        var types: [String] = []
        for phase in target.buildPhases {
            for file in phase.files ?? [] {
                for case let reference as PBXFileReference in file.file.map(listedElements) ?? [] {
                    types.append(fileType(of: reference))
                }
            }
        }
        let kinds = Set(target.buildPhases.compactMap(Self.memberPhase(of:)))
        types += synchronizedMembers(of: target).filter { memberPhase($0).map(kinds.contains) ?? false }.compactMap(\.fileType)
        types += phaseMemberFileTypes(of: target)
        var counts: [String: Int] = [:]
        for type in types where Self.languageRank(fileType: type) != nil {
            counts[type, default: 0] += 1
        }
        if counts.isEmpty {
            for type in synchronizedCandidates(of: target).compactMap(\.member.fileType) where Self.languageRank(fileType: type) != nil {
                counts[type, default: 0] += 1
            }
        }
        let winner = counts.min { a, b in a.value != b.value ? a.value > b.value : Self.languageRank(fileType: a.key)! < Self.languageRank(fileType: b.key)! }
        return winner.flatMap { Self.sourceCodeLanguage(fileType: $0.key) }
    }

    /// The items of the target's synchronized folders that a phase of the target could take:
    /// every item of the phase's kind in a folder the target lists, excluded ones included, and
    /// those the exception sets of the other folders name for the target.
    func synchronizedCandidates(of target: PBXTarget) -> [(root: SynchronizedRoot, member: SynchronizedFolder.Member)] {
        let kinds = Set(target.buildPhases.compactMap(Self.memberPhase(of:)))
        let listed = target.fileSystemSynchronizedGroups ?? []
        return synchronizedRoots.flatMap { root in
            let isListed = listed.contains { $0 === root.group }
            let named = Self.exactPaths((root.group.exceptions ?? []).compactMap { $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet }
                .filter { $0.target === target }.flatMap { $0.membershipExceptions ?? [] })
            return root.folder.members
                .filter { member in memberPhase(member).map(kinds.contains) == true && (isListed || named.contains(Array(member.key.utf8))) }
                .map { (root, $0) }
        }
    }

    /// The language each file type counts for in `predominantSourceCodeLanguage`; other types
    /// count for none (loader-experiments `source-languages`: a target of one file of each of
    /// 211 types; headers count for Objective-C++ or C++ in any phase, as in cwa's CWASQLite).
    static let sourceCodeLanguages: [String: String] = [
        "file.swiftpm-manifest": "Swift",
        "net.daringfireball.markdown": "Markdown",
        "sourcecode.applescript": "AppleScript",
        "sourcecode.asm.llvm": "LLVM",
        "sourcecode.c": "C",
        "sourcecode.c.c": "C",
        "sourcecode.c.c.preprocessed": "C",
        "sourcecode.c.h": "Objective-C-Plus-Plus",
        "sourcecode.c.objc": "Objective-C",
        "sourcecode.c.objc.preprocessed": "Objective-C",
        "sourcecode.clips": "Clips",
        "sourcecode.cpp": "C-Plus-Plus",
        "sourcecode.cpp.cpp": "C-Plus-Plus",
        "sourcecode.cpp.cpp.preprocessed": "C-Plus-Plus",
        "sourcecode.cpp.h": "C-Plus-Plus",
        "sourcecode.cpp.objcpp": "Objective-C-Plus-Plus",
        "sourcecode.cpp.objcpp.preprocessed": "Objective-C-Plus-Plus",
        "sourcecode.dtrace": "DTrace",
        "sourcecode.fortran": "Fortran",
        "sourcecode.fortran.f77": "Fortran",
        "sourcecode.fortran.f90": "Fortran90",
        "sourcecode.glsl": "GLSL",
        "sourcecode.iig": "Objective-C-Plus-Plus",
        "sourcecode.java": "Java",
        "sourcecode.javascript": "JavaScript",
        "sourcecode.lex": "Objective-C-Plus-Plus",
        "sourcecode.make": "Makefile",
        "sourcecode.metal": "Metal",
        "sourcecode.module-map": "ModuleMap",
        "sourcecode.nasm": "Intel-Assembly",
        "sourcecode.opencl": "OpenCL",
        "sourcecode.protobuf": "Protobuf",
        "sourcecode.swift": "Swift",
        "sourcecode.typescript": "JavaScript",
        "sourcecode.yacc": "Objective-C-Plus-Plus",
    ]

    /// The order of ties (`language-pairs`): the languages of ``sourceCodeLanguages`` and, by their
    /// file types, the types that count for a language the PIF does not name.
    static let languageOrder = [
        "sourcecode.ada", "AppleScript", "Intel-Assembly", "sourcecode.asm", "sourcecode.asm.asm", "C", "Clips", "C-Plus-Plus", "DTrace",
        "sourcecode.dylan", "Fortran", "Fortran90", "GLSL", "Java", "JavaScript", "LLVM", "Makefile", "Markdown", "Metal", "ModuleMap",
        "sourcecode.nqc", "Objective-C", "Objective-C-Plus-Plus", "OpenCL", "sourcecode.pascal", "Protobuf", "sourcecode.rez", "Swift",
    ]

    static func languageRank(fileType: String) -> Int? {
        languageOrder.firstIndex(of: sourceCodeLanguages[fileType] ?? fileType)
    }

    static func sourceCodeLanguage(fileType: String) -> String? {
        sourceCodeLanguages[fileType].map { "Xcode.SourceCodeLanguage." + $0 }
    }

    /// One entry per build configuration: the provisioning style and the raw `CFBundleIdentifier`
    /// of the target's Info.plist. The style is 1 when the configuration's `CODE_SIGN_STYLE`,
    /// wherever it is set and evaluated, is `Manual` (case-sensitive), and 0 when it is anything
    /// else that is not empty. When no level sets it, or it evaluates to nothing, the target's
    /// style decides: its `ProvisioningStyle` attribute, else 1 when any of its configurations
    /// names a provisioning profile (``namesProvisioningProfile(_:)``) or signs without an
    /// identity (``signsWithoutIdentity(_:)``), else 0 (loader-experiments `provisioning-style`,
    /// `provisioning-fallback`, `provisioning-profile` and their project variants,
    /// `provisioning-defaults`; cwa, netnewswire; mastodon, whose `Profile` and
    /// `Release Snapshot` set no style and whose `Release` names a profile for `iphoneos*`).
    func provisioningSourceData(_ target: PBXTarget) -> [PIFValue] {
        let attributes = project.project.targetAttributes[target] ?? [:]
        let targetStyle = Self.stringAttribute(attributes["ProvisioningStyle"]).map { $0 == "Manual" }
            ?? (namesProvisioningProfile(target) || signsWithoutIdentity(target))
        return (target.buildConfigurationList?.buildConfigurations ?? []).map { configuration in
            let style = codeSignStyle(target, configuration).flatMap { $0.isEmpty ? nil : $0 }
            return .object([
                "bundleIdentifierFromInfoPlist": .string(bundleIdentifierFromInfoPlist(target, configuration) ?? ""),
                "configurationName": .string(configuration.name),
                "provisioningStyle": .int((style.map { $0 == "Manual" } ?? targetStyle) ? 1 : 0),
            ])
        }
    }

    /// Whether any configuration of the target sets `PROVISIONING_PROFILE_SPECIFIER` or
    /// `PROVISIONING_PROFILE` to a value that is not empty once evaluated for the target: a blank
    /// counts; a macro that evaluates to nothing, a condition for another SDK, or a signing
    /// identity or team alone do not (loader-experiments `provisioning-profile`).
    func namesProvisioningProfile(_ target: PBXTarget) -> Bool {
        (target.buildConfigurationList?.buildConfigurations ?? []).contains { configuration in
            Self.provisioningProfileSettingNames.contains { !(value($0, target, configuration) ?? "").isEmpty }
        }
    }

    static let provisioningProfileSettingNames = ["PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE"]

    /// Whether any configuration of the target evaluates `CODE_SIGN_IDENTITY` to `-`, the macOS
    /// default without a `DEVELOPMENT_TEAM`, or to nothing; any other identity, distribution and
    /// Developer ID ones included, does not count (loader-experiments `provisioning-defaults`:
    /// nine product types and aggregates on iOS, `0`, and on macOS, `1`; `-` in one configuration
    /// only, one that sets a style included, gives `1` to every configuration that sets none).
    func signsWithoutIdentity(_ target: PBXTarget) -> Bool {
        (target.buildConfigurationList?.buildConfigurations ?? []).contains { configuration in
            evaluatedSettings[settingsQuery(target, configuration)].map { ["", "-"].contains($0["CODE_SIGN_IDENTITY"] ?? "") } ?? false
        }
    }

    /// Settings the PIF reads from every configuration, which Swift Build evaluates when a level
    /// writes them with macros or with a condition; provisioning profiles are read too, for
    /// targets whose style they can decide.
    static let evaluatedSettingNames = ["INFOPLIST_FILE", "CODE_SIGN_STYLE", "GENERATE_INFOPLIST_FILE"]

    /// A setting as written, or as Swift Build evaluates it for the target when a level writes it
    /// with macros or a condition (loader-experiments `infoplist-macros`, `provisioning-fallback`:
    /// `[sdk=iphoneos*]` counts for an iOS target, `[sdk=macosx*]` does not); `nil` when no level
    /// sets it (or it is not evaluated yet).
    func value(_ name: String, _ target: PBXTarget, _ configuration: XCBuildConfiguration) -> String? {
        needsEvaluation(name, configuration) ? evaluatedSettings[settingsQuery(target, configuration)]?[name] : setting(name, configuration)
    }

    /// The `CODE_SIGN_STYLE` behind a configuration's provisioning style: as written when no
    /// level writes it with macros or a condition. Otherwise Xcode reads each level (the target
    /// configuration, its xcconfig with its includes, the project configuration, its xcconfig) as
    /// a dictionary: the highest level that assigns the setting decides, with its assignment whose
    /// `[sdk=…]` condition matches the target's SDK before its plain one, whatever their order,
    /// and Swift Build evaluates the chosen value for the target, where `-showBuildSettings` takes
    /// a level's last assignment (loader-experiments `provisioning-conditions`: IncludeThenPlain,
    /// ConditionThenPlain, ManualConditionThenPlain and MacroDefault take the condition,
    /// MacosxConditionThenPlain and TargetPlainXcconfigCondition the plain value; home-assistant's
    /// Release xcconfig, whose `Manual` follows an `[sdk=iphoneos*]` value evaluating to
    /// `Automatic`). A chosen value with `$(inherited)` is left to Swift Build.
    func codeSignStyle(_ target: PBXTarget, _ configuration: XCBuildConfiguration) -> String? {
        let name = "CODE_SIGN_STYLE"
        guard needsEvaluation(name, configuration) else { return setting(name, configuration) }
        guard let settings = evaluatedSettings[settingsQuery(target, configuration)] else { return nil }
        let sdk = settings["SDK_NAME"] ?? ""
        guard let chosen = levelAssignments(name, configuration).lazy.compactMap({ Self.choose($0, sdk: sdk) }).first else { return nil }
        if chosen.contains("inherited") { return settings[name] }
        return chosen.contains("$") ? settings[chosen] : chosen
    }

    /// Each level's assignments of `name`, the highest level first: a configuration's own (in key
    /// order), then its base xcconfig's, for the target and then the project.
    func levelAssignments(_ name: String, _ configuration: XCBuildConfiguration) -> [[XCConfigFile.Assignment]] {
        levels(of: configuration).flatMap { level -> [[XCConfigFile.Assignment]] in
            let own = level.buildSettings.keys.sorted().compactMap { key -> XCConfigFile.Assignment? in
                guard case .string(let value)? = level.buildSettings[key], let (setting, conditions) = XCConfigFile.key(key), setting == name else { return nil }
                return XCConfigFile.Assignment(name: setting, conditions: conditions, value: value)
            }
            let base = baseConfigurationPath(level).map { XCConfigFile.assignments(at: $0).filter { $0.name == name } } ?? []
            return [own, base]
        }
    }

    /// A level's value: its last assignment whose conditions are all `sdk` patterns matching
    /// `sdk`, else its last plain one.
    static func choose(_ assignments: [XCConfigFile.Assignment], sdk: String) -> String? {
        let matching = assignments.last { assignment in
            !assignment.conditions.isEmpty && assignment.conditions.allSatisfy { $0.key == "sdk" && Self.matches(sdk, pattern: $0.value) }
        }
        return (matching ?? assignments.last { $0.conditions.isEmpty })?.value
    }

    /// Whether `text` matches a condition pattern, in which `*` stands for any characters.
    static func matches(_ text: String, pattern: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return text == pattern }
        guard text.hasPrefix(parts[0]), text.dropFirst(parts[0].count).hasSuffix(parts[parts.count - 1]),
              text.count >= parts[0].count + parts[parts.count - 1].count else { return false }
        var rest = Substring(text.dropFirst(parts[0].count).dropLast(parts[parts.count - 1].count))
        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard let range = rest.range(of: part) else { return false }
            rest = rest[range.upperBound...]
        }
        return true
    }

    /// The values with macros that ``codeSignStyle(_:_:)`` may choose, for each target
    /// configuration with no evaluated settings yet, for Swift Build to evaluate.
    func unevaluatedExpressions() -> [TargetSettingsQuery: Set<String>] {
        var result: [TargetSettingsQuery: Set<String>] = [:]
        for target in project.project.targets {
            for configuration in target.buildConfigurationList?.buildConfigurations ?? [] where needsEvaluation("CODE_SIGN_STYLE", configuration) {
                let query = settingsQuery(target, configuration)
                let expressions = levelAssignments("CODE_SIGN_STYLE", configuration).joined().map(\.value).filter { $0.contains("$") && !$0.contains("inherited") }
                if evaluatedSettings[query] == nil, !expressions.isEmpty { result[query] = Set(expressions) }
            }
        }
        return result
    }

    /// Whether the value a configuration takes for `name` is written with macros, or a level
    /// (the target configuration, the project configuration of the same name, or their base
    /// xcconfigs) writes `name` with a condition.
    func needsEvaluation(_ name: String, _ configuration: XCBuildConfiguration) -> Bool {
        setting(name, configuration)?.contains("$") == true || isConditioned(name, configuration)
    }

    /// Whether a level writes `name` with a condition.
    func isConditioned(_ name: String, _ configuration: XCBuildConfiguration) -> Bool {
        levels(of: configuration).contains { candidate in
            candidate.buildSettings.keys.contains { $0.hasPrefix(name + "[") }
                || baseConfigurationPath(candidate).map { XCConfigFile.conditionalSettingNames(at: $0).contains(name) } == true
        }
    }

    /// Whether the target's own style can decide one of its configurations' styles: it has no
    /// `ProvisioningStyle` attribute, and some configuration sets `CODE_SIGN_STYLE` nowhere,
    /// empty, or in a way Swift Build evaluates.
    func mayInferProvisioningStyle(_ target: PBXTarget) -> Bool {
        guard Self.stringAttribute((project.project.targetAttributes[target] ?? [:])["ProvisioningStyle"]) == nil else { return false }
        return (target.buildConfigurationList?.buildConfigurations ?? []).contains { configuration in
            (setting("CODE_SIGN_STYLE", configuration) ?? "").isEmpty || needsEvaluation("CODE_SIGN_STYLE", configuration)
        }
    }

    /// The raw `CFBundleIdentifier` of the Info.plist named by the configuration's
    /// `INFOPLIST_FILE` (``readValue(_:_:_:)``), resolved against the project directory: the
    /// setting as written, or as evaluated when it has macros or conditions (loader-experiments
    /// `infoplist-macros`: `$(SRCROOT)`, `${SRCROOT}`, `$(TARGET_NAME)`, custom and nested
    /// macros all evaluated; flappy-fly-bird; `info-plist-conditions`: `[sdk=iphoneos*]`). When
    /// that file does not set it (or there is none) and `GENERATE_INFOPLIST_FILE` is true, the
    /// generated Info.plist's `$(PRODUCT_BUNDLE_IDENTIFIER)` (observed: netnewswire's test
    /// targets, icecubes).
    func bundleIdentifierFromInfoPlist(_ target: PBXTarget, _ configuration: XCBuildConfiguration) -> String? {
        if let infoPlist = readValue("INFOPLIST_FILE", target, configuration), !infoPlist.isEmpty {
            let path = infoPlist.hasPrefix("/") ? infoPlist : (project.projectDirectory as NSString).appendingPathComponent(infoPlist)
            if let identifier = (try? PropertyLists.readDictionary(at: path))?["CFBundleIdentifier"] as? String {
                return identifier
            }
        }
        return generatesInfoPlist(target, configuration) ? "$(PRODUCT_BUNDLE_IDENTIFIER)" : nil
    }

    /// `GENERATE_INFOPLIST_FILE` read as a boolean, as `NSString.boolValue` reads one (`yes`,
    /// `true`, `7` and ` YES` are true, `on` and `+YES` are not), and true by default only for a
    /// watch app's iOS container (loader-experiments `info-plist-conditions`: one target of each
    /// product type without the setting). Written with a condition, Xcode's choice of assignment
    /// counts (``readValue(_:_:_:)``).
    func generatesInfoPlist(_ target: PBXTarget, _ configuration: XCBuildConfiguration) -> Bool {
        guard let written = readValue("GENERATE_INFOPLIST_FILE", target, configuration) else {
            return target.productType?.rawValue == "com.apple.product-type.application.watchapp2-container"
        }
        return Self.boolValue(written)
    }

    /// A setting nomac reads itself: with a condition at some level, Xcode's choice of assignment
    /// (``conditionedChoice(_:_:_:)``), evaluated by Swift Build when it has macros; otherwise as
    /// ``value(_:_:_:)`` gives it.
    func readValue(_ name: String, _ target: PBXTarget, _ configuration: XCBuildConfiguration) -> String? {
        guard let choice = conditionedChoice(name, target, configuration) else { return value(name, target, configuration) }
        return choice.flatMap { $0.contains("$") ? value(name, target, configuration) : $0 }
    }

    /// A setting written with a condition at some level, as Xcode reads it: the highest level
    /// that assigns it decides, with its assignment whose conditions are all `[sdk=…]` patterns
    /// matching the target's SDK before its plain one, whatever their order, as for
    /// `CODE_SIGN_STYLE` (loader-experiments `xcconfig-conditions`: PRODUCT_NAME and
    /// GENERATE_INFOPLIST_FILE in one xcconfig, both orders; `info-plist-conditions` and
    /// `product-names`: `[arch=…]` and `[config=…]` assignments never apply). `nil` without a
    /// condition or before Swift Build has evaluated the configuration; `.some(nil)` when no
    /// assignment applies.
    func conditionedChoice(_ name: String, _ target: PBXTarget, _ configuration: XCBuildConfiguration) -> String?? {
        guard isConditioned(name, configuration), let settings = evaluatedSettings[settingsQuery(target, configuration)] else { return nil }
        return .some(levelAssignments(name, configuration).lazy.compactMap { Self.choose($0, sdk: settings["SDK_NAME"] ?? "") }.first)
    }

    /// `NSString.boolValue`: after spaces and tabs, a sign or leading zeros must be followed by
    /// a digit from 1 to 9; otherwise `Y`, `y`, `T`, `t` or such a digit (loader-experiments
    /// `info-plist-conditions`: `+1`, `-1`, `007` true; `-0`, `00`, `0Y`, `+YES`, a leading
    /// newline false).
    static func boolValue(_ text: String) -> Bool {
        var characters = text.drop { $0 == " " || $0 == "\t" }
        var numeric = false
        if let sign = characters.first, sign == "+" || sign == "-" {
            numeric = true
            characters = characters.dropFirst()
        }
        while characters.first == "0" {
            numeric = true
            characters = characters.dropFirst()
        }
        guard let first = characters.first else { return false }
        return ("1"..."9").contains(first) || (!numeric && "YyTt".contains(first))
    }

    func settingsQuery(_ target: PBXTarget, _ configuration: XCBuildConfiguration) -> TargetSettingsQuery {
        TargetSettingsQuery(projectPath: project.path, targetID: target.uuid, configuration: configuration.name)
    }

    /// The target configurations that need one of ``evaluatedSettingNames`` or the product's name
    /// evaluated and have no evaluated settings yet, and every configuration of the targets whose
    /// own style can decide one (``mayInferProvisioningStyle(_:)``) and that name no provisioning
    /// profile as written, for their profiles and signing identities; projects that set a style
    /// everywhere start no Swift Build session for them.
    func unevaluatedSettings() -> [TargetSettingsQuery] {
        project.project.targets.flatMap { target in
            let configurations = target.buildConfigurationList?.buildConfigurations ?? []
            let namesProfileAsWritten = configurations.contains { configuration in
                Self.provisioningProfileSettingNames.contains { !needsEvaluation($0, configuration) && !(setting($0, configuration) ?? "").isEmpty }
            }
            let infers = !(target is PBXLegacyTarget) && mayInferProvisioningStyle(target) && !namesProfileAsWritten
            return configurations
                .filter { configuration in
                    infers || Self.evaluatedSettingNames.contains { needsEvaluation($0, configuration) } || productNameNeedsEvaluation(target, configuration)
                }
                .map { settingsQuery(target, $0) }
                .filter { evaluatedSettings[$0] == nil }
        }
    }

    /// A setting's unevaluated value, looked up in the target configuration, its base xcconfig,
    /// the project configuration of the same name and its base xcconfig, in that order
    /// (observed: netnewswire and icecubes set `INFOPLIST_FILE` in xcconfig files).
    func setting(_ name: String, _ configuration: XCBuildConfiguration) -> String? {
        for candidate in levels(of: configuration) {
            if case .string(let value)? = candidate.buildSettings[name] { return value }
            if let xcconfig = baseConfigurationPath(candidate), let value = XCConfigFile.settings(at: xcconfig)[name] { return value }
        }
        return nil
    }

    /// The target configuration and the project configuration of the same name.
    func levels(of configuration: XCBuildConfiguration) -> [XCBuildConfiguration] {
        let projectConfiguration = project.project.buildConfigurationList?.buildConfigurations.first { $0.name == configuration.name }
        return [configuration, projectConfiguration].compactMap { $0 }
    }

    /// The path of a configuration's base xcconfig file, named by a file reference or by a
    /// synchronized folder and a path in it.
    func baseConfigurationPath(_ configuration: XCBuildConfiguration) -> String? {
        if let base = configuration.baseConfiguration {
            return try? base.fullPath(sourceRoot: project.projectDirectory)
        }
        if let anchor = configuration.baseConfigurationAnchor, let path = configuration.baseConfigurationReferenceRelativePath,
           path.isIdentical(to: path.decomposed), let root = synchronizedRoot(anchor) {
            return root.folder.directory + "/" + path
        }
        return nil
    }

    // MARK: Build phases

    mutating func buildPhase(_ phase: PBXBuildPhase, target: PBXTarget) throws -> PIFValue? {
        var contents: [String: PIFValue] = ["guid": .string(guid(phase))]
        switch phase {
        case is PBXSourcesBuildPhase: contents["type"] = .string("com.apple.buildphase.sources")
        case is PBXHeadersBuildPhase: contents["type"] = .string("com.apple.buildphase.headers")
        case is PBXFrameworksBuildPhase: contents["type"] = .string("com.apple.buildphase.frameworks")
        case is PBXResourcesBuildPhase: contents["type"] = .string("com.apple.buildphase.resources")
        case is PBXRezBuildPhase: contents["type"] = .string("com.apple.buildphase.rez")
        case let copy as PBXCopyFilesBuildPhase:
            contents["type"] = .string("com.apple.buildphase.copy-files")
            contents["destinationSubfolder"] = .string(try destinationSubfolder(copy))
            contents["destinationSubpath"] = .string(copy.dstPath ?? "")
        case let script as PBXShellScriptBuildPhase:
            contents["type"] = .string("com.apple.buildphase.shell-script")
            contents["name"] = .string(script.name ?? "Run Script")
            contents["shellPath"] = .string(script.shellPath ?? "/bin/sh")
            contents["scriptContents"] = .string(script.shellScript ?? "")
            contents["inputFilePaths"] = .array(script.inputPaths.map(PIFValue.string))
            contents["outputFilePaths"] = .array(script.outputPaths.map(PIFValue.string))
            contents["inputFileListPaths"] = .array((script.inputFileListPaths ?? []).map(PIFValue.string))
            contents["outputFileListPaths"] = .array((script.outputFileListPaths ?? []).map(PIFValue.string))
            contents["emitEnvironment"] = .bool(script.showEnvVarsInLog)
            contents["alwaysOutOfDate"] = .bool(script.alwaysOutOfDate)
            contents["alwaysRunForInstallHdrs"] = .bool(false)
            contents["sandboxingOverride"] = .string("basedOnBuildSetting")
            contents["originalObjectID"] = .string(script.uuid)
            if let dependencyFile = script.dependencyFile {
                contents["dependencyFileFormat"] = .string("makefile")
                contents["dependencyFilePaths"] = .array([.string(dependencyFile)])
            }
        default:
            warnings.append("\(project.fileName): unsupported build phase \(type(of: phase)) (\(phase.uuid)) was skipped")
            return nil
        }
        if phase.runOnlyForDeploymentPostprocessing {
            contents["runOnlyForDeploymentPostprocessing"] = .bool(true)
        }
        // A build file whose reference is missing writes nothing, yet counts where synchronized
        // members go (``buildFiles(of:phaseGUID:target:own:)``).
        let own: [PIFValue?] = unlinkedProducts(in: phase, of: target).compactMap { productBuildFile($0).map(PIFValue.object) }
            + (phase.files ?? []).flatMap { file -> [PIFValue?] in file.file == nil && file.product == nil ? [nil] : buildFiles(file, in: phase) }
        contents["buildFiles"] = .array(buildFiles(of: phase, phaseGUID: guid(phase), target: target, own: own))
        return .object(contents)
    }

    /// `destinationSubfolder` by `dstSubfolderSpec`, whatever the phase's `dstPath` and target
    /// (loader-experiments `copy-files`; wikipedia's man pages, spec 0).
    static let destinationSubfolders = [
        "", "$(WRAPPER_NAME)", "$(INFOPLIST_PATH)", "$(PKGINFO_PATH)", "$(EXECUTABLE_PATH)", "$(CONTENTS_FOLDER_PATH)",
        "$(EXECUTABLE_FOLDER_PATH)", "$(UNLOCALIZED_RESOURCES_FOLDER_PATH)", "$(PUBLIC_HEADERS_FOLDER_PATH)",
        "$(PRIVATE_HEADERS_FOLDER_PATH)", "$(FRAMEWORKS_FOLDER_PATH)", "$(SHARED_FRAMEWORKS_FOLDER_PATH)",
        "$(SHARED_SUPPORT_FOLDER_PATH)", "$(PLUGINS_FOLDER_PATH)", "$(SCRIPTS_FOLDER_PATH)", "$(JAVA_FOLDER_PATH)",
        "<builtProductsDir>", "$(EXECUTABLE_PATH)",
    ]

    /// A phase without `dstSubfolderSpec` is spec 0. xcodebuild stops with SIGTRAP on a spec
    /// above 17 when it generates the PIF, as for `-dumpPIF` and `-showBuildSettings`
    /// (`copy-files-18`), so nomac fails with the status a shell reports for that.
    func destinationSubfolder(_ phase: PBXCopyFilesBuildPhase) throws -> String {
        if phase.dstSubfolderSpec == nil, project.unmodeledDestinationSubfolderSpecs[phase.uuid] == nil, let name = phase.dstSubfolder?.rawValue {
            guard let destination = CopyFilesDestination.byName[name] else {
                throw NomacError("xcodebuild aborts on the copy-files phase \(phase.uuid): its dstSubfolder, \(name), is not one Xcode knows",
                                 path: project.path, exitStatus: 134)
            }
            return destination
        }
        let spec = phase.dstSubfolderSpec.map { Int($0.rawValue) } ?? project.unmodeledDestinationSubfolderSpecs[phase.uuid] ?? 0
        guard Self.destinationSubfolders.indices.contains(spec) else {
            throw NomacError("xcodebuild stops on the copy-files phase \(phase.uuid): its dstSubfolderSpec, \(spec), is not one Xcode knows", path: project.path,
                             exitStatus: 133)
        }
        return Self.destinationSubfolders[spec]
    }

    // MARK: Build files

    /// The build files of a phase's `PBXBuildFile`: one, or for a variant group, one per element
    /// the PIF lists for it (``listedElements(_:)``): loader-experiments `variant-build-files`,
    /// `variant-regions`; envelope-experiments `variant-groups`). Xcode draws the GUIDs of the
    /// children's build files at random; nomac derives them from the build file's and the child's
    /// object IDs and `nomac verify` replaces them with stand-ins (docs/adr/0009).
    func buildFiles(_ file: PBXBuildFile, in phase: PBXBuildPhase) -> [PIFValue] {
        guard let group = file.file as? PBXVariantGroup else { return buildFile(file, in: phase, element: file.file, identifier: guid(file)).map { [$0] } ?? [] }
        return listedElements(group).compactMap { element in
            let identifier = element === group ? guid(file) : PIFIdentifiers.objectGUID(projectGUID: projectGUID, objectID: file.uuid + element.uuid)
            return buildFile(file, in: phase, element: element, identifier: identifier)
        }
    }

    private func buildFile(_ file: PBXBuildFile, in phase: PBXBuildPhase, element: PBXFileElement?, identifier: String) -> PIFValue? {
        var contents: [String: PIFValue] = ["guid": .string(identifier)]
        if let proxy = file.file as? PBXReferenceProxy {
            // The product of another project's target, through a project reference (moonlight's
            // libmoonlight-common.a); its file type and name when that product does not resolve,
            // its project not on disk or without it (`project-references-missing`, `-stale`).
            if let targetGUID = productTarget(proxy) {
                contents["targetReference"] = .string(targetGUID)
            } else {
                contents["fileType"] = .string(proxy.fileType ?? "")
                contents["name"] = .string(proxy.path ?? proxy.name ?? "")
                if let path = unresolvedProductPath(proxy) {
                    contents["guid"] = .string(PIFIdentifiers.objectGUID(projectGUID: projectGUID, objectID: path))
                }
            }
        } else if let element {
            if let targetGUID = context.targetGUIDByProjectAndProductID[(project.path as NSString).standardizingPath]?[element.uuid] {
                contents["targetReference"] = .string(targetGUID)
            } else {
                contents["fileReference"] = .string(guid(element))
            }
        } else if let product = file.product.flatMap(productBuildFile) {
            contents = product
        } else {
            return nil
        }
        if let filters = Self.platformFilters(Self.filterNames(file.platformFilters, file.platformFilter)) {
            contents["platformFilters"] = filters
        }
        let attributes = file.attributes ?? []
        if attributes.contains("CodeSignOnCopy") { contents["codeSignOnCopy"] = .bool(true) }
        if attributes.contains("RemoveHeadersOnCopy") { contents["removeHeadersOnCopy"] = .bool(true) }
        if attributes.contains("Weak") { contents["shouldLinkWeakly"] = .bool(true) }
        if let visibility = Self.headerVisibility(attributes: attributes) { contents["headerVisibility"] = .string(visibility) }
        if let mig = Self.migCodegenFiles(attributes: attributes) { contents["migCodegenFiles"] = .string(mig) }
        if let flags = file.compilerFlags, !flags.isEmpty {
            contents["additionalCompilerOptions"] = .string(flags)
        }
        // On-demand resource tags, sorted, in any phase (envelope-experiments `survey-shapes`:
        // `(Zeta, Alpha)` is `[Alpha, Zeta]`; a tagged source too; none for an empty list).
        if case .array(let tags)? = file.settings?["ASSET_TAGS"], !tags.isEmpty {
            contents["assetTags"] = .array(tags.sorted().map { .string($0) })
        }
        if phase is PBXSourcesBuildPhase, let element,
           let visibility = Self.intentsCodegenVisibility(fileType: codegenFileType(element), attributes: attributes) {
            contents["intentsCodegenVisibility"] = .string(visibility)
        }
        return .object(contents)
    }

    /// The GUID of the target of another project whose product a reference proxy names, when
    /// that project is in the workspace and has the product, else the target its container
    /// proxy's `remoteInfo` names there (loader-experiments `project-references-renamed`).
    func productTarget(_ proxy: PBXReferenceProxy) -> String? {
        guard let remote = proxy.remote, let (path, productID) = remoteObject(remote) else { return nil }
        return context.targetGUIDByProjectAndProductID[path]?[productID] ?? remote.remoteInfo.flatMap { context.targetGUIDByProjectAndName[path]?[$0] }
    }

    /// The path whose MD5 Xcode puts after the project GUID for the build file of a reference
    /// proxy whose product is not found, its project not on disk or without the product: the
    /// proxy's path in the ``LegacyBuildFolder`` (envelope-experiments `unresolved-proxies`). A
    /// proxy that is not relative to the products folder, or a folder nomac cannot compute, keeps
    /// the GUID of the build file's ID.
    func unresolvedProductPath(_ proxy: PBXReferenceProxy) -> String? {
        guard proxy.sourceTree == .buildProductsDir, let path = proxy.path, let folder = legacyBuildFolder else { return nil }
        return (folder + "/" + path).decomposed
    }

    /// The paths behind the GUIDs ``unresolvedProductPath(_:)`` gives, by GUID: `nomac verify`
    /// hashes them again under the reference's source root.
    func hashedBuildFilePaths() -> [String: String] {
        var paths: [String: String] = [:]
        for target in project.project.targets {
            for file in target.buildPhases.flatMap({ $0.files ?? [] }) {
                guard let proxy = file.file as? PBXReferenceProxy, productTarget(proxy) == nil, let path = unresolvedProductPath(proxy) else { continue }
                paths[PIFIdentifiers.objectGUID(projectGUID: projectGUID, objectID: path)] = path
            }
        }
        return paths
    }

    /// The project's ``LegacyBuildFolder``, from its `Debug` configuration, else its first.
    func readLegacyBuildFolder() -> String? {
        let configurations = project.project.buildConfigurationList?.buildConfigurations ?? []
        guard let name = LegacyBuildFolder.configuration(among: configurations.map(\.name)),
              let configuration = configurations.first(where: { $0.name == name }) else { return nil }
        let settings = configuration.buildSettings.mapValues { value -> String? in
            if case .string(let text) = value { return text }
            return nil
        }
        return LegacyBuildFolder.path(projectDirectory: project.projectDirectory, configuration: name, settings: settings,
                                      xcconfig: baseConfigurationPath(configuration))
    }

    /// The MiG files a build file's `Client` and `Server` attributes ask for, matched with case,
    /// on any build file of any phase (loader-experiments `mig-codegen`; ish's `mach_exc.defs`).
    static func migCodegenFiles(attributes: [String]) -> String? {
        switch (attributes.contains("Client"), attributes.contains("Server")) {
        case (true, true): return "both"
        case (true, false): return "client"
        case (false, true): return "server"
        case (false, false): return nil
        }
    }

    /// `Public` wins over `Private` (loader-experiments `intents-codegen`: `(Public, Private)`).
    static func headerVisibility(attributes: [String]) -> String? {
        attributes.contains("Public") ? "public" : attributes.contains("Private") ? "private" : nil
    }

    /// The type that decides a reference's code generation: a file reference's own, or a variant
    /// group's `Base` variant's, else its development region's variant's, else none, whatever the
    /// group's name and its other variants (loader-experiments `intents-codegen`, `intents-codegen-fr`:
    /// `[Base: text, en: intent]` has none, `[en: strings, Base: intent]` is an intent definition,
    /// `[fr: strings, en: intent]` is one only with development region `en`; nextcloud's
    /// `Intent.intentdefinition`, a Base intent definition with 50 `.strings` variants).
    func codegenFileType(_ element: PBXFileElement) -> String? {
        if let file = element as? PBXFileReference { return fileType(of: file) }
        guard let group = element as? PBXVariantGroup else { return nil }
        let variants = group.children.compactMap { $0 as? PBXFileReference }
        let primary = variants.first { region(of: $0) == "Base" }
            ?? project.project.developmentRegion.flatMap { region in variants.first { self.region(of: $0) == region } }
        return primary.map(fileType(of:))
    }

    /// The `intentsCodegenVisibility` of a Sources build file of `fileType` with `attributes`, by
    /// type, not extension: intent definitions are `public` and Core ML models `project` unless
    /// the attributes say `no_codegen`, `codegen` (`public`), `private_codegen` or
    /// `project_codegen`, which take precedence in that order whatever their order in the list.
    /// With `Weak`, `Public` or `Private` there is none, and with only other attributes
    /// (`CodeSignOnCopy`, `Project`, `public_codegen`, ...) none either, though they do not stop
    /// a code generation attribute (loader-experiments `intents-codegen`, 130 build files;
    /// `codegen-file-types`: no other of 212 types; `codegen-members`; mastodon's `(codegen)`).
    static func intentsCodegenVisibility(fileType: String?, attributes: [String]) -> String? {
        guard let fileType, let standard = codegenDefaults[fileType], !attributes.contains(where: ["Weak", "Public", "Private"].contains) else { return nil }
        if let (_, visibility) = codegenAttributes.first(where: { attributes.contains($0.0) }) { return visibility }
        return attributes.isEmpty ? standard : nil
    }

    static let codegenDefaults = ["file.intentdefinition": "public", "file.mlmodel": "project", "folder.mlpackage": "project"]
    static let codegenAttributes = [("no_codegen", "no_codegen"), ("codegen", "public"), ("private_codegen", "private"), ("project_codegen", "project")]

    /// A package product's build file: its GUID is the MD5 of the
    /// `XCSwiftPackageProductDependency`'s object ID, so every phase that links or copies the
    /// product shares it (netnewswire), the build files Xcode adds for unlinked products too.
    func productBuildFile(_ product: XCSwiftPackageProductDependency) -> [String: PIFValue]? {
        guard let package = context.packageProducts[product.uuid] else { return nil }
        return ["guid": .string(PIFIdentifiers.md5(product.uuid)), "targetReference": .string(package.guid)]
    }

    // MARK: Build rules

    /// A build rule as Xcode 27.0 writes it (loader-experiments `build-rule-keys`): file patterns
    /// for a `pattern.proxy` rule only, empty when it has none; the script for a script rule
    /// only, empty when it has none; `runOncePerArchitecture` true unless the rule says 0; each
    /// output's compiler flags split into words as a shell splits them; input and output file
    /// lists always empty.
    func buildRule(_ rule: PBXBuildRule) -> PIFValue {
        var contents: [String: PIFValue] = [
            "guid": .string(guid(rule)),
            "name": .string(rule.name ?? Self.buildRuleName(compiler: rule.compilerSpec, fileType: rule.fileType, filePatterns: rule.filePatterns)),
            "compilerSpecificationIdentifier": .string(rule.compilerSpec),
            "fileTypeIdentifier": .string(rule.fileType),
            "inputFilePaths": .array((rule.inputFiles ?? []).map(PIFValue.string)),
            "outputFilePaths": .array(rule.outputFiles.map(PIFValue.string)),
            "inputFileListPaths": .array([]),
            "outputFileListPaths": .array([]),
            "runOncePerArchitecture": .bool(rule.runOncePerArchitecture ?? true),
        ]
        if rule.fileType == "pattern.proxy" { contents["filePatterns"] = .string(rule.filePatterns ?? "") }
        if rule.compilerSpec == "com.apple.compilers.proxy.script" { contents["scriptContents"] = .string(rule.script ?? "") }
        if let flags = rule.outputFilesCompilerFlags, !flags.isEmpty {
            contents["outputFilesCompilerFlags"] = .array(flags.map { .array(Self.shellWords($0).map(PIFValue.string)) })
        }
        if let dependencyFile = rule.dependencyFile {
            contents["dependencyFileFormat"] = .string("makefile")
            contents["dependencyFilePaths"] = .array([.string(dependencyFile)])
        }
        return .object(contents)
    }

    /// `text` split at unquoted spaces and tabs, with quotes and backslashes removed:
    /// `-DA="x y" -DB='p q' -DC\ D` gives `-DA=x y`, `-DB=p q`, `-DC D` (`build-rule-keys`).
    static func shellWords(_ text: String) -> [String] {
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped {
                word.append(character)
                escaped = false
            } else if character == "\\", quote != "'" {
                escaped = true
                inWord = true
            } else if let open = quote {
                if character == open { quote = nil } else { word.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                inWord = true
            } else if character == " " || character == "\t" {
                if inWord { words.append(word) }
                word = ""
                inWord = false
            } else {
                word.append(character)
                inWord = true
            }
        }
        if inWord { words.append(word) }
        return words
    }
}
