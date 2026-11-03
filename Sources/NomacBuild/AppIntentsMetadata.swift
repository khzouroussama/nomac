import Foundation
import NomacCore

/// `Metadata.appintents` as Xcode 27.0's `appintentsmetadataprocessor --compile-time-extraction`
/// writes it, from the Swift compiler's constant values of the target's App Intents types, which
/// swift.org's compiler emits as Xcode's does (docs/formats/app-intents.md,
/// `.github/scripts/app_intents_experiments.py`). Every form no experiment has shown is refused
/// with its name (B-107), never written in a guessed form.
struct AppIntentsMetadata {
    let types: [ConstType]
    let moduleName: String

    /// The entities and enums of the bundles the target depends on (their `extract.actionsdata`,
    /// `--metadata-file-list`), by fully qualified type name (`dependency`).
    var dependencyEntities: [String: [String: Any]] = [:]
    var dependencyEnums: [String: [String: Any]] = [:]

    init(constValueFiles: [String], moduleName: String, dependencies: [[String: Any]] = []) throws {
        for data in dependencies {
            for entity in (data["entities"] as? [String: [String: Any]] ?? [:]).values {
                if let name = entity["fullyQualifiedTypeName"] as? String { dependencyEntities[name] = entity }
            }
            for enumeration in data["enums"] as? [[String: Any]] ?? [] {
                if let name = enumeration["fullyQualifiedTypeName"] as? String { dependencyEnums[name] = enumeration }
            }
        }
        var types: [ConstType] = []
        for file in constValueFiles {
            guard let data = FileManager.default.contents(atPath: file) else { throw NomacError("cannot read the Swift compiler's constant values", path: file) }
            guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NomacError("the Swift compiler's constant values are not a list of types", path: file)
            }
            types += try list.map(ConstType.init)
        }
        // Each architecture's constant values list the same types (`watch`).
        var seen = Set<String>()
        self.types = types.filter { seen.insert($0.typeName).inserted }
        self.moduleName = moduleName
    }

    var usesAppIntents: Bool { types.contains { $0.role != nil } }

    /// `extract.actionsdata`.
    func actionsData(xcodeVersion: String) throws -> FoundationJSON {
        var actions: [String: FoundationJSON] = [:]
        var entities: [String: FoundationJSON] = [:]
        var queries: [String: FoundationJSON] = [:]
        var enums: [(name: String, json: FoundationJSON)] = []
        var shortcuts: [FoundationJSON] = []
        var provider: String?
        for type in types {
            switch type.role {
            case .intent: actions[type.actionIdentifier] = try intent(type)
            case .entity: entities[type.name] = try entity(type)
            case .query: queries[type.name] = try query(type)
            case .enumeration: enums.append((type.name, try enumeration(type)))
            case .shortcuts:
                provider = type.mangledName
                shortcuts = try appShortcuts(type).map(\.json)
            case nil: break
            }
        }
        var data: [String: FoundationJSON] = [
            "actions": .object(actions), "assistantEntities": .array([]), "assistantIntentNegativePhrases": .array([]), "assistantIntents": .array([]),
            "autoShortcuts": .array(shortcuts), "entities": .object(entities), "enums": .array(enums.sorted { $0.name < $1.name }.map(\.json)),
            "generator": .object(["name": .string("xcode-tools"), "version": .string(xcodeVersion)]), "negativePhrases": .array([]),
            "queries": .object(queries), "shortcutTileColor": .int(try tileColor()), "version": .int(1),
        ]
        // Enums by name, whatever their source order (`results`, three builds). Without an App
        // Shortcuts provider the key is left out (`queries`).
        data["autoShortcutProviderMangledName"] = provider.map(FoundationJSON.string)
        return .object(data)
    }

    /// `extract.packagedata`, for a target that declares an `AppIntentsPackage`: the mangled names
    /// of the packages it includes (`package`). Xcode writes its two keys in dictionary order,
    /// which changes from build to build; nomac sorted.
    func packageData() throws -> FoundationJSON? {
        let packages = types.filter { $0.conformances.contains("AppIntents.AppIntentsPackage") }
        guard let package = packages.first else { return nil }
        guard packages.count == 1, types.contains(where: { $0.role != nil }) else {
            throw package.refusal("App Intents packages other than one beside App Intents types")
        }
        try package.refuseUnknownProperties(["includedPackages"])
        let included = try (package.property("includedPackages")?.value.elements ?? []).map { element -> FoundationJSON in
            guard element.kind == "Type", let name = (element.value as? [String: Any])?["mangledName"] as? String else {
                throw package.refusal("an included package other than `Package.self`")
            }
            return .string(name)
        }
        return .object(["includes": .array(included), "version": .int(1)])
    }

    /// `shortcutTileColor`: 14 by default, the provider's `.blue` 7 (`sweep`).
    private func tileColor() throws -> Int {
        guard let provider = types.first(where: { $0.role == .shortcuts }), let color = provider.property("shortcutTileColor") else { return 14 }
        guard let name = color.value.enumName, let value = ["blue": 7][name] else { throw provider.refusal("a `shortcutTileColor` no experiment has shown") }
        return value
    }

    /// Writes `Metadata.appintents` into the bundle at `output` and the strings data; its
    /// `root.ssu.yaml` is the training's (``AppShortcutsTraining``).
    func write(output: String, stringsData: String, xcodeVersion: String) throws {
        let directory = output + "/Metadata.appintents"
        try FileSystem.createDirectory(directory)
        try FileSystem.write(Data(try actionsData(xcodeVersion: xcodeVersion).compact.utf8), to: directory + "/extract.actionsdata")
        try FileSystem.write(Data(FoundationJSON.object(["toolsVersion": .string(xcodeVersion), "version": .string("3.0")]).pretty.utf8), to: directory + "/version.json")
        if let packageData = try packageData() { try FileSystem.write(Data(packageData.compact.utf8), to: directory + "/extract.packagedata") }
        let provider = types.first { $0.role == .shortcuts }
        let shortcuts = try provider.map(appShortcuts) ?? []
        try FileSystem.write(Data(try self.stringsData(provider: provider, shortcuts: shortcuts).pretty.utf8), to: stringsData)
    }

    /// The strings data: each App Shortcut's phrases, keyed by its first (`training`), with its
    /// intent's parameters, and the parameter summaries' format strings (`Localizable`).
    func stringsData(provider: ConstType?, shortcuts: [AppShortcut]) throws -> FoundationJSON {
        var tables: [String: FoundationJSON] = [:]
        if let provider, !shortcuts.isEmpty {
            let line = provider.property("appShortcuts")?.line ?? 0
            tables["AppShortcuts"] = .array(try shortcuts.enumerated().map { index, shortcut in
                let (types, representations) = try parameterVocabulary(shortcut.intent)
                let title = shortcut.intent.property("title")?.value.localizedText()?.key ?? ""
                return .object([
                    "appShortcutMetadata": .array([.object([
                        "actionIdentifier": .string(shortcut.intent.name), "index": .int(index),
                        "parameterDisplayRepresentations": .object(representations.mapValues { .array($0.map(FoundationJSON.string)) }),
                        "parameterTypes": .object(types.mapValues(FoundationJSON.string)), "title": .string(title),
                    ])]),
                    "key": .string(shortcut.phrases.first ?? ""), "location": .object(["startingColumn": .int(0), "startingLine": .int(line)]),
                    "values": .array(shortcut.phrases.map(FoundationJSON.string)),
                ])
            })
        }
        let summaries = try types.filter { $0.role == .intent }.flatMap { type in
            try type.property("parameterSummary").map { try Self.summaryFormats($0.value) } ?? []
        }
        if !summaries.isEmpty { tables["Localizable"] = .array(summaries.map { .object(["key": .string($0)]) }) }
        return .object(["source": .string(shortcuts.isEmpty ? "ExtractedAppShortcutsMetadata" : provider?.file ?? ""), "tables": .object(tables), "version": .int(2)])
    }

    /// An intent's enum and entity parameters: each one's type, and each type's display strings
    /// (an enum's case titles, an entity's type name as displayed).
    private func parameterVocabulary(_ intent: ConstType) throws -> (types: [String: String], representations: [String: [String]]) {
        var parameterTypes: [String: String] = [:]
        var representations: [String: [String]] = [:]
        for property in intent.properties where property.isParameter {
            let type = property.type.dropFirst("AppIntents.IntentParameter<".count).dropLast()
            let wrapped = type.hasPrefix("Swift.Optional<") ? String(type.dropFirst("Swift.Optional<".count).dropLast()) : String(type)
            guard let parameterType = types.first(where: { $0.typeName == wrapped }) else { continue }
            switch parameterType.role {
            case .enumeration:
                let titles = try parameterType.caseDisplayRepresentations()
                representations[parameterType.name] = try parameterType.cases.map { name in
                    guard case .object(let representation)? = titles[name], case .object(let title)? = representation["title"], case .string(let key)? = title["key"] else {
                        throw parameterType.refusal("the case `\(name)` without a constant title")
                    }
                    return key
                }
            case .entity:
                representations[parameterType.name] = [try parameterType.property("typeDisplayRepresentation")?.localizedString() ?? parameterType.name]
            default:
                continue
            }
            parameterTypes[String(property.label.dropFirst())] = parameterType.name
        }
        return (parameterTypes, representations)
    }

    /// Whether two of `Metadata.appintents`' files differ only in what Xcode writes in set order:
    /// `extract.actionsdata`'s `resolvableInputTypes` and `typeSpecificMetadata` pairs, and
    /// `root.ssu.yaml`'s parameter variables and locales (three builds of `basic` and of `types`,
    /// `localized`, docs/formats/app-intents.md).
    static func sameButForSetOrder(_ name: String, _ reference: String, _ other: String) -> Bool {
        switch name {
        case "extract.actionsdata", "extract.packagedata":
            guard let a = try? JSONSerialization.jsonObject(with: Data(reference.utf8)), let b = try? JSONSerialization.jsonObject(with: Data(other.utf8)) else { return false }
            return canonical(a) == canonical(b)
        case "root.ssu.yaml":
            return canonicalSSU(reference) == canonicalSSU(other)
        default:
            return false
        }
    }

    /// `root.ssu.yaml`'s lines with the sibling list items Xcode writes in set order sorted: the
    /// locales of each corpus and definition list (`localized`), and the variables.
    static func canonicalSSU(_ text: String) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last?.isEmpty == true { lines.removeLast() }
        func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }
        func isItem(_ line: String) -> Bool { line.dropFirst(indent(line)).hasPrefix("- ") }
        func canonical(_ lines: ArraySlice<String>) -> [String] {
            var result: [String] = []
            var index = lines.startIndex
            while index < lines.endIndex {
                guard isItem(lines[index]) else {
                    result.append(lines[index])
                    index += 1
                    continue
                }
                let depth = indent(lines[index])
                var items: [[String]] = []
                while index < lines.endIndex, indent(lines[index]) == depth, isItem(lines[index]) {
                    var end = index + 1
                    while end < lines.endIndex, indent(lines[end]) > depth { end += 1 }
                    items.append([lines[index]] + canonical(lines[(index + 1)..<end]))
                    index = end
                }
                let heads = items.map { $0[0].dropFirst(depth) }
                if heads.allSatisfy({ $0.hasPrefix("- locale: ") }) || (depth == 0 && heads.allSatisfy { $0.hasPrefix("- name: ") }) {
                    items.sort { $0.joined(separator: "\n") < $1.joined(separator: "\n") }
                }
                result += items.joined()
            }
            return result
        }
        return canonical(lines[...])
    }

    /// A JSON value as text with its keys sorted and its `resolvableInputTypes` arrays in one order.
    private static func canonical(_ value: Any, key: String = "") -> String {
        if let object = value as? [String: Any] {
            return "{" + object.keys.sorted().map { "\($0):" + canonical(object[$0]!, key: $0) }.joined(separator: ",") + "}"
        }
        if let array = value as? [Any] {
            var elements = array.map { canonical($0) }
            if key == "resolvableInputTypes" { elements.sort() }
            if key == "typeSpecificMetadata", elements.count % 2 == 0 {
                elements = stride(from: 0, to: elements.count, by: 2).map { elements[$0] + "=" + elements[$0 + 1] }.sorted()
            }
            return "[" + elements.joined(separator: ",") + "]"
        }
        return "\(value)"
    }

    // MARK: Intents

    private func intent(_ type: ConstType) throws -> FoundationJSON {
        try type.refuseUnknownProperties(["title", "description", "openAppWhenRun", "parameterSummary", "intentClassName", "isDiscoverable", "displayRepresentation"],
                                         parameters: true)
        if type.conformances.contains("AppIntents.CustomIntentMigratedAppIntent"), type.property("intentClassName")?.value.raw == nil {
            throw type.refusal("a migrated intent without a constant `intentClassName`")
        }
        let parameters = try type.properties.filter(\.isParameter).map { try parameter($0, in: type) }
        var object: [String: FoundationJSON] = [
            "assistantDefinedSchemaTraits": .array([]), "assistantDefinedSchemas": .array([]), "authenticationPolicy": .int(0),
            "availabilityAnnotations": try Self.availability(type), "effectiveBundleIdentifiers": .array([]),
            "fullyQualifiedTypeName": .string(type.typeName), "identifier": .string(type.actionIdentifier), "isAuthPolExplicit": .bool(false),
            "isDiscoverable": .bool(true), "mangledTypeName": .string(type.mangledName), "mangledTypeNameByBundleIdentifier": .object([:]),
            "mangledTypeNameByBundleIdentifierV2": .object([:]), "mangledTypeNameV2": .string(type.mangledName),
            "outputFlags": .int(0), "parameters": .array(parameters), "presentationStyle": .int(0), "requiredCapabilities": .array([]),
            "systemProtocolMetadata": .array([]), "systemProtocolMetadataV2": .array([]), "systemProtocols": .array([]),
            "typeSpecificMetadata": .array([]), "visibilityMetadata": Self.visible,
        ]
        guard let title = type.property("title")?.value.localizedText() else { throw type.refusal("an intent without a constant `title`") }
        object["title"] = Self.string(title)
        if let property = type.property("description") {
            guard let description = property.value.localizedText() else { throw type.refusal("a `description` other than a string or a string resource") }
            object["descriptionMetadata"] = .object(["descriptionText": Self.string(description), "searchKeywords": .array([])])
        }
        let systemProtocols = Self.systemProtocols.filter { type.conformances.contains($0.0) }.map(\.1)
        if systemProtocols.contains(where: \.configuresWidget) {
            object["isDiscoverable"] = .bool(false)
            object["outputFlags"] = .int(8)
        }
        let names = systemProtocols.map { FoundationJSON.string("com.apple.link.systemProtocol." + $0.name) }
        object["systemProtocols"] = .array(names)
        object["systemProtocolMetadata"] = .array(names.flatMap { [$0, .object(["empty": .object([:])])] })
        object["systemProtocolMetadataV2"] = object["systemProtocolMetadata"]
        // An intent that says it is not discoverable is not, in its visibility too (`sessions`).
        if let discoverable = try type.property("isDiscoverable")?.bool() {
            guard !discoverable else { throw type.refusal("`isDiscoverable` true") }
            object["isDiscoverable"] = .bool(false)
            object["visibilityMetadata"] = .object(["assistantOnly": .bool(false), "isDiscoverable": .bool(false)])
        }
        // An open intent names the entity its `target` opens, a delete intent the entities its
        // `entities` delete, with the entity's metadata (`entities`, `more`).
        for (conformance, label) in [("AppIntents.OpenIntent", "_target"), ("AppIntents.DeleteIntent", "_entities")] where type.conformances.contains(conformance) {
            var target = String(type.property(label)?.type.dropFirst("AppIntents.IntentParameter<".count).dropLast() ?? "")
            if label == "_entities", target.hasPrefix("Swift.Array<") { target = String(target.dropFirst("Swift.Array<".count).dropLast()) }
            guard let entity = types.first(where: { $0.typeName == target && $0.role == .entity }) else {
                throw type.refusal("a `\(label.dropFirst())` parameter that is no entity")
            }
            object["typeSpecificMetadata"] = .array([.string("LNActionTypeMetadataKeyEntityMetadata"), .object(["entityMetadata": .object(["wrapper": try self.entity(entity)])]),
                                                     .string("LNActionTypeMetadataKeyEntityType"), .object(["string": .object(["wrapper": .string(entity.name)])])])
        }
        // A migrated SiriKit intent goes by its class name (`controls`).
        if type.conformances.contains("AppIntents.CustomIntentMigratedAppIntent") {
            object["customIntentClassName"] = .string(type.actionIdentifier)
        }
        // An open intent opens the app unless it says otherwise (`entities`).
        let opensApp = try type.property("openAppWhenRun")?.bool() ?? type.conformances.contains("AppIntents.OpenIntent")
        object["openAppWhenRun"] = .bool(opensApp)
        object["supportedModes"] = .int(opensApp ? 2 : 1)
        if let summary = type.property("parameterSummary") {
            object["actionConfiguration"] = try configuration(summary.value, in: type)
        }
        let output = try output(type)
        if output.flags != 0 { object["outputFlags"] = .int((object["outputFlags"].flatMap { if case .int(let flags) = $0 { flags } else { nil } } ?? 0) | output.flags) }
        object["outputType"] = output.type
        return .object(object)
    }

    /// The format strings of a parameter summary's `Summary`s, nested in `When` and `Switch` too,
    /// in their order (`summaries`).
    static func summaryFormats(_ value: ConstValue) throws -> [String] {
        if value.callType?.hasPrefix("AppIntents.IntentParameterSummary<") == true {
            guard let first = value.arguments?.first, first.value.kind != "Builder" else { return [] }
            return try first.value.summaryFormat().map { [$0.text] } ?? []
        }
        return try (value.arguments ?? []).flatMap { argument -> [String] in
            if argument.value.kind == "Builder" { return try (argument.value.builderMembers ?? []).flatMap { try summaryFormats($0.value) } }
            if argument.value.kind == "InitCall" { return try summaryFormats(argument.value) }
            return []
        }
    }

    /// A parameter summary as `actionConfiguration` writes it (`summaries`): a `Summary` as
    /// `actionSummary` (its format string, and the parameters it lists after it as
    /// `otherParameterIdentifiers`), `When(\.$p, .equalTo, value) { … } otherwise: { … }` as
    /// `whenClause`, `Switch(\.$p) { Case(.c) { … } … DefaultCase { … } }` as `switchStatement`.
    private func configuration(_ value: ConstValue, in type: ConstType) throws -> FoundationJSON {
        let refusal = type.refusal("a parameter summary other than `Summary`, `When` and `Switch` as observed")
        guard value.kind == "InitCall", let callType = value.callType, let arguments = value.arguments else { throw refusal }
        func parameter(_ value: ConstValue) throws -> String {
            guard value.kind == "KeyPath", let path = (value.value as? [String: Any])?["path"] as? String, path.hasPrefix("$") else { throw refusal }
            return String(path.dropFirst())
        }
        func nested(_ value: ConstValue) throws -> FoundationJSON {
            guard let members = value.builderMembers, members.count == 1, members[0].kind == "buildExpression" else { throw refusal }
            return try configuration(members[0].value, in: type)
        }
        if callType.hasPrefix("AppIntents.IntentParameterSummary<") {
            var wrapper: [String: FoundationJSON] = ["otherParameterIdentifiers": .array([])]
            var rest = arguments[...]
            if let first = rest.first, first.label == "", first.value.kind != "Builder" {
                guard rest.count >= 2, rest[rest.startIndex + 1].label == "table", rest[rest.startIndex + 1].value.kind == "NilLiteral",
                      let format = try first.value.summaryFormat() else { throw refusal }
                wrapper["summaryString"] = .object(["formatString": .string(format.text), "parameterIdentifiers": .array(format.parameters.map(FoundationJSON.string))])
                rest = rest.dropFirst(2)
            }
            if let list = rest.first {
                guard rest.count == 1, list.label == "", let members = list.value.builderMembers else { throw refusal }
                wrapper["otherParameterIdentifiers"] = .array(try members.map { member in
                    guard member.kind == "buildExpression" else { throw refusal }
                    return .string(try parameter(member.value))
                })
            }
            return .object(["actionSummary": .object(["wrapper": .object(wrapper)])])
        }
        if callType.hasPrefix("AppIntents.ParameterSummaryWhenCondition<") {
            guard arguments.map({ $0.label ?? "" }) == ["", "", "", "", "otherwise"], arguments[1].value.enumName == "equalTo",
                  arguments[2].value.kind == "RawLiteral", let raw = arguments[2].value.raw, raw == "true" || raw == "false" else { throw refusal }
            return .object(["whenClause": .object(["wrapper": .object([
                "condition": .object(["comparisonOperator": .int(2), "parameterIdentifier": .string(try parameter(arguments[0].value)),
                                      "value": .object(["bool": .object(["value": .bool(raw == "true")])])]),
                "when": try nested(arguments[3].value), "otherwise": try nested(arguments[4].value),
            ])])])
        }
        if callType.hasPrefix("AppIntents.ParameterSummarySwitchCondition<") {
            guard arguments.count == 2, let members = arguments[1].value.builderMembers else { throw refusal }
            let switched = try parameter(arguments[0].value)
            guard let enumType = type.property("_" + switched)?.type.dropFirst("AppIntents.IntentParameter<".count).dropLast(),
                  let enumeration = types.first(where: { $0.typeName == enumType && $0.role == .enumeration }) else { throw refusal }
            let cases = try members.map { member -> FoundationJSON in
                guard member.kind == "buildExpression", let condition = member.value.callType, let caseArguments = member.value.arguments else { throw refusal }
                if condition.hasPrefix("AppIntents.ParameterSummaryDefaultCaseCondition<") {
                    guard caseArguments.count == 1 else { throw refusal }
                    return .object(["configuration": try nested(caseArguments[0].value), "isDefaultCase": .bool(true)])
                }
                guard condition.hasPrefix("AppIntents.ParameterSummaryCaseCondition<"), caseArguments.count == 2,
                      let name = caseArguments[0].value.enumName else { throw refusal }
                let identifier = FoundationJSON.string(enumeration.name)
                return .object(["configuration": try nested(caseArguments[1].value), "isDefaultCase": .bool(false),
                                "value": .object(["array": .object([
                                    "valueType": .object(["linkEnumeration": .object(["wrapper": .object(["identifier": identifier])])]),
                                    "values": .array([.object(["enumeration": .object(["identifier": identifier, "value": .string(name)])])]),
                                ])])])
            }
            return .object(["switchStatement": .object(["wrapper": .object(["cases": .array(cases), "parameterIdentifier": .string(switched)])])])
        }
        throw refusal
    }

    /// The system protocols of intents, by the conformance that gives them, in the order Xcode lists
    /// them (`sessions`: a focus filter that is a live activity intent too); a widget's or a
    /// control's configuration is not discoverable and has `outputFlags` 8 (`widget`, `controls`).
    static let systemProtocols: [(String, (name: String, configuresWidget: Bool))] = [
        ("AppIntents.WidgetConfigurationIntent", ("WidgetConfiguration", true)),
        ("AppIntents.ControlConfigurationIntent", ("ControlConfiguration", true)),
        ("AppIntents.SetValueIntent", ("SetValue", false)),
        ("AppIntents.OpenIntent", ("OpenEntity", false)),
        ("AppIntents.DeleteIntent", ("DeleteEntity", false)),
        ("AppIntents.SetFocusFilterIntent", ("FocusConfiguration", false)),
        ("AppIntents.LiveActivityIntent", ("SessionStarting", false)),
    ]

    /// `outputFlags` by the protocol of the result that sets it (`results`).
    static let outputFlags = ["AppIntents.OpensIntent": 1, "AppIntents.ShowsSnippetView": 2, "AppIntents.ProvidesDialog": 4]

    /// The result's `outputFlags`, the sum of its protocols' (``outputFlags``), and its value's
    /// type for `ReturnsValue` (`results`: the compiler lists the protocols but `IntentResult`).
    private func output(_ type: ConstType) throws -> (flags: Int, type: FoundationJSON?) {
        guard let result = type.associatedTypes.first(where: { $0["typeAliasName"] as? String == "PerformResult" }) else { return (0, nil) }
        // A widget configuration intent has no `perform`: `Never`, no output type (`widget`).
        if result["substitutedTypeName"] as? String == "Swift.Never" { return (0, nil) }
        let requirements = result["opaqueTypeProtocolRequirements"] as? [String] ?? []
        let sameTypes = result["opaqueTypeSameTypeRequirements"] as? [[String: Any]] ?? []
        var flags = 0
        var output: FoundationJSON?
        for requirement in requirements {
            if let flag = Self.outputFlags[requirement] {
                flags |= flag
            } else if requirement == "AppIntents.ReturnsValue" {
                guard sameTypes.count == 1, sameTypes[0]["typeAliasName"] as? String == "AppIntents.IntentResult.Value",
                      let value = sameTypes[0]["substitutedTypeName"] as? String, let valueType = try? valueType(of: value, in: type) else {
                    throw type.refusal("a result value of a type no experiment has shown")
                }
                output = valueType.json
            } else if requirement != "AppIntents.IntentResult" {
                throw type.refusal("a result of `\((result["substitutedTypeName"] as? String) ?? "")`")
            }
        }
        guard output != nil || sameTypes.isEmpty else { throw type.refusal("a result of `\((result["substitutedTypeName"] as? String) ?? "")`") }
        return (flags, output)
    }

    // MARK: Parameters

    /// A value type and what Xcode writes for a parameter of it.
    struct ValueType {
        var json: FoundationJSON
        var resolvable: [FoundationJSON]
        var dynamicOptions: Int
    }

    /// The primitive types observed, by Swift type: their type identifier and the types they
    /// resolve from (`basic`, `dialogs`).
    static let primitives: [String: (identifier: Int, resolvable: [FoundationJSON])] = [
        "Swift.String": (0, [.object(["kindValue": .int(0), "valueType": array(of: primitive(2), capabilities: 3)]), resolvable(0), resolvable(2)]),
        "Swift.Bool": (1, [resolvable(1)]),
        "Swift.Int": (2, [resolvable(7), resolvable(0), resolvable(2)]),
        "Swift.Double": (7, [resolvable(0), resolvable(2), resolvable(7)]),
        "Foundation.Date": (8, [resolvable(8)]),
        "CoreLocation.CLPlacemark": (10, [resolvable(10)]),
        "Foundation.URL": (11, [resolvable(11), resolvable(0)]),
    ]

    /// The measurement units observed, by their unit type (`more`: `UnitLength` 1).
    static let measurementUnits = ["Foundation.UnitLength": 1]

    /// The `intents` value types observed: `IntentFile` (`dialogs`).
    static let intentsTypes = ["AppIntents.IntentFile": 12]

    /// The identifiers of the `UTType` members observed in `supportedContentTypes` (`dialogs`).
    static let contentTypes = ["image": "public.image", "jpeg": "public.jpeg", "png": "public.png", "gif": "com.compuserve.gif", "heic": "public.heic"]

    private func valueType(of swiftType: String, in owner: ConstType) throws -> ValueType {
        if let primitive = Self.primitives[swiftType] {
            return ValueType(json: Self.primitive(primitive.identifier), resolvable: primitive.resolvable, dynamicOptions: 0)
        }
        // A measurement of an observed unit, with its unit type (`more`).
        if swiftType.hasPrefix("Foundation.Measurement<"), let unit = Self.measurementUnits[String(swiftType.dropFirst("Foundation.Measurement<".count).dropLast())] {
            let json = FoundationJSON.object(["measurement": .object(["wrapper": .object(["unitType": .int(unit)])])])
            return ValueType(json: json, resolvable: [.object(["kindValue": .int(0), "valueType": json])], dynamicOptions: 0)
        }
        if let identifier = Self.intentsTypes[swiftType] {
            return ValueType(json: .object(["intents": .object(["wrapper": .object(["typeIdentifier": .int(identifier)])])]), resolvable: [], dynamicOptions: 0)
        }
        if swiftType.hasPrefix("Swift.Array<"), swiftType.hasSuffix(">") {
            let member = try valueType(of: String(swiftType.dropFirst("Swift.Array<".count).dropLast()), in: owner)
            return ValueType(json: Self.array(of: member.json, capabilities: 3), resolvable: [], dynamicOptions: member.dynamicOptions)
        }
        if let type = types.first(where: { $0.typeName == swiftType }) {
            switch type.role {
            case .enumeration:
                return ValueType(json: .object(["linkEnumeration": .object(["wrapper": .object(["identifier": .string(type.name)])])]), resolvable: [], dynamicOptions: 0)
            case .entity:
                if type.conformances.contains("AppIntents.TransientAppEntity") { return ValueType(json: Self.entityType(type.name), resolvable: [], dynamicOptions: 0) }
                guard let query = try defaultQuery(of: type) else { throw owner.refusal("an entity without a constant `defaultQuery`") }
                return ValueType(json: Self.entityType(type.name), resolvable: [], dynamicOptions: query.queryKind.dynamicOptions)
            default: break
            }
        }
        // A dependency's entity or enum, by the name its own metadata gives it; an entity's
        // options are not dynamic here (`dependency`).
        if let entity = dependencyEntities[swiftType], let name = entity["typeName"] as? String {
            return ValueType(json: Self.entityType(name), resolvable: [], dynamicOptions: 0)
        }
        if let enumeration = dependencyEnums[swiftType], let name = enumeration["identifier"] as? String {
            return ValueType(json: .object(["linkEnumeration": .object(["wrapper": .object(["identifier": .string(name)])])]), resolvable: [], dynamicOptions: 0)
        }
        throw owner.refusal("a value of type `\(swiftType)`")
    }

    private func parameter(_ property: ConstProperty, in owner: ConstType) throws -> FoundationJSON {
        guard property.value.kind == "InitCall", let call = property.value.callType, call.hasPrefix("AppIntents.IntentParameter<"), call.hasSuffix(">"),
              let arguments = property.value.arguments else {
            throw owner.refusal("the parameter `\(property.label)` written other than `@Parameter(title:…)`")
        }
        var wrapped = String(call.dropFirst("AppIntents.IntentParameter<".count).dropLast())
        let optional = wrapped.hasPrefix("Swift.Optional<")
        if optional { wrapped = String(wrapped.dropFirst("Swift.Optional<".count).dropLast()) }
        if types.contains(where: { $0.typeName == wrapped && $0.conformances.contains("AppIntents.TransientAppEntity") }) {
            throw owner.refusal("a parameter of a transient entity, `\(property.label)`")
        }
        let type = try valueType(of: wrapped, in: owner)
        var title: LocalizedText?
        var description: LocalizedText?
        var defaultValue: FoundationJSON?
        var contentTypes: [String]?
        var range: [FoundationJSON] = []
        var inputOptions: [FoundationJSON] = []
        var dateFormat: [FoundationJSON] = []
        var collectionSizes: [FoundationJSON] = []
        var providesOptions = false
        var connection = 0
        for argument in arguments {
            switch (argument.label, argument.value.kind) {
            case ("title", _):
                title = argument.value.localizedText()
            case ("description", "RawLiteral"), ("description", "InitCall"):
                guard let text = argument.value.localizedText() else { throw owner.refusal("the description of `\(property.label)`") }
                description = text
            case ("default", _) where argument.value.kind != "NilLiteral":
                // An enum's default is its case's name (`summaries`).
                // An enum's default is its case's name, a dependency's enum's its case's title
                // (`summaries`, `dependency`).
                let enumDefault = try argument.value.enumName.flatMap { name -> FoundationJSON? in
                    if types.contains(where: { $0.typeName == wrapped && $0.role == .enumeration }) { return .object(["string": .object(["wrapper": .string(name)])]) }
                    guard let enumeration = dependencyEnums[wrapped] else { return nil }
                    guard let title = ((enumeration["cases"] as? [[String: Any]])?.first(where: { $0["identifier"] as? String == name })?["displayRepresentation"] as? [String: Any])
                        .flatMap({ ($0["title"] as? [String: Any])?["key"] as? String }) else { throw owner.refusal("the default of `\(property.label)`") }
                    return .object(["string": .object(["wrapper": .string(title)])])
                }
                guard let value = enumDefault ?? Self.defaultValue(argument.value, of: wrapped) else { throw owner.refusal("the default of `\(property.label)`") }
                defaultValue = value
            case ("supportedContentTypes", "Array"):
                contentTypes = try (argument.value.elements ?? []).map { element in
                    guard element.kind == "MemberReference", let member = element.member, member.base == "UniformTypeIdentifiers.UTType",
                          let identifier = Self.contentTypes[member.label] else { throw owner.refusal("a content type of `\(property.label)`") }
                    return identifier
                }
            case ("inputConnectionBehavior", "Enum") where argument.value.enumName == "connectToPreviousIntentResult":
                connection = 2
            // An Int's range is written as a Double's (`more`).
            case ("inclusiveRange", "Tuple") where wrapped == "Swift.Double" || wrapped == "Swift.Int":
                guard let bounds = argument.value.tupleElements, bounds.count == 2, let lower = bounds[0].raw.flatMap(Double.init),
                      let upper = bounds[1].raw.flatMap(Double.init) else { throw owner.refusal("the range of `\(property.label)`") }
                range = [.string("LNValueTypeMetadataKeyNumberRangeType"), .object(["int": .object(["wrapper": .int(0)])]),
                         .string("LNValueTypeMetadataKeyNumberLowerBound"), .object(["double": .object(["wrapper": .double(lower)])]),
                         .string("LNValueTypeMetadataKeyNumberUpperBound"), .object(["double": .object(["wrapper": .double(upper)])])]
            case ("inputOptions", "InitCall") where argument.value.callType == "Swift.String.IntentInputOptions":
                inputOptions = try Self.inputOptions(argument.value, of: property, in: owner)
            // An options provider (`DynamicOptionsProvider`): capabilities 8, dynamic options 1 (`types`).
            case ("optionsProvider", "InitCall"):
                providesOptions = true
            // A date's kind: `.date` 0, `.dateTime` 2 (`sessions`).
            case ("kind", "Enum") where wrapped == "Foundation.Date":
                guard let format = ["date": 0, "dateTime": 2][argument.value.enumName ?? ""] else { throw owner.refusal("the date kind of `\(property.label)`") }
                dateFormat = [.string("LNValueTypeMetadataKeyDateFormat"), .object(["int": .object(["wrapper": .int(format)])])]
            // A widget configuration's array sized per widget family (`sessions`).
            case ("size", "Dictionary"):
                var sizes: [String: FoundationJSON] = [:]
                for (family, count) in argument.value.dictionaryEntries ?? [] {
                    guard let name = family.enumName, let value = count.raw.flatMap(Int.init) else { throw owner.refusal("the size of `\(property.label)`") }
                    sizes[name] = .object(["max": .int(value), "min": .int(value)])
                }
                collectionSizes = [.string("LNValueTypeMetadataKeyCollectionSizes"), .object(["collectionSizes": .object(["sizes": .object(sizes)])])]
            // A request dialog is not part of the metadata (`dialogs`).
            case ("requestValueDialog", "RawLiteral"):
                continue
            case (_, "NilLiteral"), ("controlStyle", "Runtime"), ("inputConnectionBehavior", "Runtime"), ("supportedValues", "Runtime"),
                 ("kind", "Runtime"), ("displayStyle", "Runtime"), ("defaultUnitAdjustForLocale", "Runtime"), ("supportsNegativeNumbers", "Runtime"):
                continue
            default:
                throw owner.refusal("the parameter argument `\(argument.label ?? "")` of `\(property.label)`")
            }
        }
        guard let title else { throw owner.refusal("the parameter `\(property.label)` without a constant title") }
        // Xcode writes these key and value pairs in set order (three builds of `types`).
        var metadata = range + inputOptions + dateFormat + collectionSizes
        if case .object(let kind) = type.json, case .object(let measurement)? = kind["measurement"], case .object(let wrapper)? = measurement["wrapper"], let unit = wrapper["unitType"] {
            metadata += [.string("LNValueTypeMetadataKeyMeasurementUnitAdjustsForLocale"), .object(["int": .object(["wrapper": .int(0)])]),
                         .string("LNValueTypeMetadataKeyMeasurementUnitType"), .object(["int": .object(["wrapper": unit])])]
        }
        if let defaultValue { metadata += [.string("LNValueTypeSpecificMetadataKeyDefaultValue"), defaultValue] }
        if let contentTypes {
            guard metadata.isEmpty else { throw owner.refusal("content types with other metadata on `\(property.label)`") }
            metadata += [.string("LNValueTypeMetadataKeyFileSupportedTypes"), .object(["array": .object(["elements": .array(contentTypes.map { .object(["string": .object(["wrapper": .string($0)])]) })])])]
        }
        var object: [String: FoundationJSON] = [
            "capabilities": .int((defaultValue == nil ? 0 : 1) | (providesOptions ? 8 : 0)), "dynamicOptionsSupport": .int(providesOptions ? 1 : type.dynamicOptions), "inputConnectionBehavior": .int(connection),
            "isInput": .bool(connection != 0), "isOptional": .bool(optional), "name": .string(String(property.label.dropFirst())),
            "resolvableInputTypes": .array(type.resolvable), "title": Self.string(title), "typeSpecificMetadata": .array(metadata), "valueType": type.json,
        ]
        if let description { object["parameterDescription"] = Self.string(description) }
        return .object(object)
    }

    /// `String.IntentInputOptions(capitalizationType:multiline:autocorrect:smartQuotes:smartDashes:)`
    /// as integers (`types`).
    static func inputOptions(_ value: ConstValue, of property: ConstProperty, in owner: ConstType) throws -> [FoundationJSON] {
        let keys = ["multiline": "LNValueTypeMetadataKeyStringMultiline", "autocorrect": "LNValueTypeMetadataKeyStringAutocorrect",
                    "smartQuotes": "LNValueTypeMetadataKeyStringSmartQuotes", "smartDashes": "LNValueTypeMetadataKeyStringSmartDashes"]
        let capitalization = ["none": 0]
        var entries: [FoundationJSON] = []
        for argument in value.arguments ?? [] {
            if argument.label == "keyboardType", argument.value.kind == "Runtime" { continue }
            if argument.label == "capitalizationType", let name = argument.value.enumName, let number = capitalization[name] {
                entries += [.string("LNValueTypeMetadataKeyStringCapitalizationType"), .object(["int": .object(["wrapper": .int(number)])])]
            } else if let label = argument.label, let key = keys[label], let raw = argument.value.raw, ["true", "false"].contains(raw) {
                entries += [.string(key), .object(["int": .object(["wrapper": .int(raw == "true" ? 1 : 0)])])]
            } else {
                throw owner.refusal("the input option `\(argument.label ?? "")` of `\(property.label)`")
            }
        }
        return entries
    }

    /// A parameter's default as written: an integer, a double, a Boolean (as 1 or 0), a string or an
    /// empty array (`basic`, `widget`, `dialogs`, `types`).
    static func defaultValue(_ value: ConstValue, of type: String) -> FoundationJSON? {
        switch (type, value.kind) {
        case ("Swift.Double", "RawLiteral"): return value.raw.flatMap(Double.init).map { .object(["double": .object(["wrapper": .double($0)])]) }
        case ("Swift.Bool", "RawLiteral") where value.raw == "true" || value.raw == "false":
            return .object(["int": .object(["wrapper": .int(value.raw == "true" ? 1 : 0)])])
        case ("Swift.Int", "RawLiteral"): return value.raw.flatMap(Int.init).map { .object(["int": .object(["wrapper": .int($0)])]) }
        case ("Swift.String", "RawLiteral"): return value.raw.map { .object(["string": .object(["wrapper": .string($0)])]) }
        case (_, "Array") where type.hasPrefix("Swift.Array<") && value.elements?.isEmpty == true: return .object(["array": .object(["elements": .array([])])])
        default: return nil
        }
    }

    // MARK: Entities, queries, enums

    private func defaultQuery(of entity: ConstType) throws -> ConstType? {
        guard let property = entity.property("defaultQuery"), property.value.kind == "InitCall", let call = property.value.callType else { return nil }
        return types.first { $0.typeName == call && $0.role == .query }
    }

    /// An entity's display name: a string, or `TypeDisplayRepresentation(name:)` of a string
    /// resource (`entities`).
    private func displayTypeName(_ type: ConstType) throws -> LocalizedText {
        guard let value = type.property("typeDisplayRepresentation")?.value else { throw type.refusal("an entity without a constant `typeDisplayRepresentation`") }
        if let text = value.raw.map({ LocalizedText(key: $0) }) { return text }
        guard value.callType == "AppIntents.TypeDisplayRepresentation", let arguments = value.arguments,
              arguments.map({ $0.label ?? "" }) == ["name", "numericFormat"], arguments[1].value.kind == "NilLiteral",
              let name = arguments[0].value.localizedText() else {
            throw type.refusal("a `typeDisplayRepresentation` other than a string or `TypeDisplayRepresentation(name:)`")
        }
        return name
    }

    /// An entity: a transient one has no default query (`entities`); an `IndexedEntity` the system
    /// protocol `com.apple.appintents.entity.Indexed`; a property is `@Property(title:)` with a
    /// string or a string resource.
    func entity(_ type: ConstType) throws -> FoundationJSON {
        try type.refuseUnknownProperties(["typeDisplayRepresentation", "defaultQuery", "id", "displayRepresentation"], entityProperties: true)
        let display = try displayTypeName(type)
        let transient = type.conformances.contains("AppIntents.TransientAppEntity")
        let query = try defaultQuery(of: type)
        guard transient || query != nil else { throw type.refusal("an entity without a constant `defaultQuery`") }
        let properties = try type.properties.filter(\.isEntityProperty).map { property -> FoundationJSON in
            guard let arguments = property.value.arguments, property.value.callType?.hasPrefix("AppIntents.EntityProperty<") == true,
                  let titleArgument = arguments.first(where: { $0.label == "title" }), let title = titleArgument.value.localizedText(),
                  arguments.allSatisfy({ $0.label == "title" || $0.value.kind == "NilLiteral" }) else {
                throw type.refusal("the entity property `\(property.label)` written other than `@Property(title:)`")
            }
            var wrapped = String(property.value.callType!.dropFirst("AppIntents.EntityProperty<".count).dropLast())
            let optional = wrapped.hasPrefix("Swift.Optional<")
            if optional { wrapped = String(wrapped.dropFirst("Swift.Optional<".count).dropLast()) }
            let valueType = try self.valueType(of: wrapped, in: type).json
            return .object(["capabilities": .int(0), "identifier": .string(String(property.label.dropFirst())), "isOptional": .bool(optional),
                            "title": Self.string(title), "valueType": valueType])
        }
        let indexed: [FoundationJSON] = type.conformances.contains("AppIntents.IndexedEntity")
            ? [.string("com.apple.appintents.entity.Indexed"), .object(["empty": .object([:])])] : []
        return .object([
            "assistantDefinedSchemas": .array([]), "availabilityAnnotations": try Self.availability(type), "defaultQueryIdentifier": query.map { .string($0.typeName) },
            "displayTypeName": Self.string(display), "effectiveBundleIdentifiers": .array([]), "entitySyncMetadata": .object(["entitySyncType": .int(0)]),
            "fullyQualifiedTypeName": .string(type.typeName), "mangledTypeName": .string(type.mangledName), "mangledTypeNameByBundleIdentifier": .object([:]),
            "properties": .array(properties), "requiredCapabilities": .array([]), "systemProtocolMetadata": .array(indexed), "systemProtocolMetadataV2": .array(indexed),
            "transient": .bool(transient), "typeName": .string(type.name), "typeSpecificMetadata": .array([]), "visibilityMetadata": Self.visible,
        ].compactMapValues { $0 })
    }

    private func query(_ type: ConstType) throws -> FoundationJSON {
        // A query's dependencies on an intent's parameters add nothing (`widget`).
        let dependencies = type.properties.filter { $0.label.hasPrefix("_") && $0.type.hasPrefix("AppIntents.IntentParameterDependency<") }.map { String($0.label.dropFirst()) }
        if let other = type.properties.first(where: { property in
            !(property.label.hasPrefix("_") && dependencies.contains(String(property.label.dropFirst()))) && !dependencies.contains(property.label) && property.value.kind != "Runtime"
        }) {
            throw type.refusal("the query property `\(other.label)`")
        }
        guard let entity = types.first(where: { entity in entity.role == .entity && (try? defaultQuery(of: entity))??.typeName == type.typeName }) else {
            throw type.refusal("a query that is no entity's `defaultQuery`")
        }
        return .object([
            "availabilityAnnotations": try Self.availability(type), "capabilities": .int(type.queryKind.capabilities), "defaultQueryForEntity": .bool(true),
            "effectiveBundleIdentifiers": .array([]), "entityType": .string(entity.name), "fullyQualifiedIdentifier": .string(type.typeName),
            "identifier": .string(type.name), "mangledTypeName": .string(type.mangledName), "mangledTypeNameByBundleIdentifier": .object([:]),
            "parameters": .array([]), "queryType": .string(type.name), "resultValueType": Self.entityType(entity.name), "sortingOptions": .array([]),
            "visibilityMetadata": Self.visible,
        ])
    }

    private func enumeration(_ type: ConstType) throws -> FoundationJSON {
        try type.refuseUnknownProperties(["typeDisplayRepresentation", "caseDisplayRepresentations", "allCases", "rawValue"])
        guard let display = try type.property("typeDisplayRepresentation")?.localizedString() else {
            throw type.refusal("an enum without a constant `typeDisplayRepresentation`")
        }
        let representations = try type.caseDisplayRepresentations()
        let cases = try type.cases.map { name -> FoundationJSON in
            guard let representation = representations[name] else { throw type.refusal("the case `\(name)` without a constant display representation") }
            return .object(["displayRepresentation": representation, "identifier": .string(name)])
        }
        return .object([
            "assistantDefinedSchemas": .array([]), "availabilityAnnotations": try Self.availability(type), "cases": .array(cases), "displayTypeName": Self.string(display),
            "effectiveBundleIdentifiers": .array([]), "fullyQualifiedTypeName": .string(type.typeName), "identifier": .string(type.name), "isSystem": .bool(false),
            "mangledTypeName": .string(type.mangledName), "mangledTypeNameByBundleIdentifier": .object([:]), "systemProtocolMetadata": .array([]),
            "visibilityMetadata": Self.visible,
        ])
    }

    // MARK: App Shortcuts

    struct AppShortcut {
        var intent: ConstType
        var phrases: [String]
        var shortTitle: LocalizedText
        var systemImageName: String
        /// The provider's `availabilityAnnotations` (`sweep`).
        var availability: FoundationJSON
        var json: FoundationJSON {
            .object(["actionIdentifier": .string(intent.actionIdentifier), "availabilityAnnotations": availability,
                     "phraseTemplates": .array(phrases.map(AppIntentsMetadata.string)), "shortTitle": AppIntentsMetadata.string(shortTitle),
                     "systemImageName": .string(systemImageName)])
        }
    }

    func appShortcuts(_ type: ConstType) throws -> [AppShortcut] {
        guard let property = type.property("appShortcuts"), type.properties.allSatisfy({ ["appShortcuts", "shortcutTileColor"].contains($0.label) }),
              property.value.kind == "Builder", let members = property.value.builderMembers else { throw type.refusal("App Shortcuts other than one `appShortcuts` builder") }
        let availability = try Self.availability(type)
        // Xcode leaves out the App Shortcuts behind `if #available` (`sweep`: a computed property
        // returning arrays, which the compiler gives as a builder).
        return try members.filter { $0.kind != "buildLimitedAvailability" }.map { member in
            guard member.kind == "buildExpression", member.value.kind == "InitCall", member.value.callType == "AppIntents.AppShortcut",
                  let arguments = member.value.arguments, arguments.map({ $0.label ?? "" }) == ["intent", "phrases", "shortTitle", "systemImageName"],
                  arguments[0].value.kind == "InitCall", arguments[0].value.arguments?.isEmpty == true,
                  let intent = types.first(where: { $0.typeName == arguments[0].value.callType && $0.role == .intent }),
                  let phrases = arguments[1].value.elements, let shortTitle = arguments[2].value.localizedText(),
                  let image = arguments[3].value.raw else {
                throw type.refusal("an App Shortcut other than `AppShortcut(intent:phrases:shortTitle:systemImageName:)`")
            }
            return AppShortcut(intent: intent, phrases: try phrases.map { phrase in
                guard let text = try phrase.phraseTemplate() else { throw type.refusal("a phrase other than text, `\\(.applicationName)` and parameters") }
                return text
            }, shortTitle: shortTitle, systemImageName: image, availability: availability)
        }
    }

    // MARK: Shared values

    /// `availabilityAnnotations` by the platform names of `@available` (`controls`, `sweep`).
    static let platformNames = ["iOS": "LNPlatformNameIOS", "macOS": "LNPlatformNameMACOS", "watchOS": "LNPlatformNameWATCHOS", "visionOS": "LNPlatformNameVISIONOS"]

    /// A type's `availabilityAnnotations`: each platform `@available` names with its version as
    /// written (`18`, `17.0`), and the wildcard (`controls`).
    static func availability(_ type: ConstType) throws -> FoundationJSON {
        var annotations: [String: FoundationJSON] = ["LNPlatformNameWildcard": .object(["introducedVersion": .string("*")])]
        for attribute in type.availability {
            guard let platform = attribute["platform"] as? String, let name = platformNames[platform], let version = attribute["introducedVersion"] as? String,
                  attribute["isUnavailable"] as? Bool == false, attribute["isDeprecated"] as? Bool == false else {
                throw type.refusal("an `@available` attribute no experiment has shown")
            }
            annotations[name] = .object(["introducedVersion": .string(version)])
        }
        return .object(annotations)
    }
    static let visible: FoundationJSON = .object(["assistantOnly": .bool(false), "isDiscoverable": .bool(true)])

    static func string(_ key: String) -> FoundationJSON { .object(["alternatives": .array([]), "key": .string(key)]) }
    static func string(_ text: LocalizedText) -> FoundationJSON {
        .object(["alternatives": .array([]), "key": .string(text.key), "defaultValue": text.defaultValue.map(FoundationJSON.string),
                 "table": text.table.map(FoundationJSON.string)].compactMapValues { $0 })
    }
    static func primitive(_ identifier: Int) -> FoundationJSON { .object(["primitive": .object(["wrapper": .object(["typeIdentifier": .int(identifier)])])]) }
    static func resolvable(_ identifier: Int) -> FoundationJSON { .object(["kindValue": .int(0), "valueType": primitive(identifier)]) }
    static func array(of member: FoundationJSON, capabilities: Int) -> FoundationJSON {
        .object(["array": .object(["wrapper": .object(["capabilities": .int(capabilities), "memberValueType": member])])])
    }
    static func entityType(_ name: String) -> FoundationJSON { .object(["entity": .object(["wrapper": .object(["typeName": .string(name)])])]) }
}

// MARK: The compiler's constant values

/// A type of the Swift compiler's constant values (`-emit-const-values`).
struct ConstType {
    enum Role { case intent, entity, query, enumeration, shortcuts }
    enum QueryKind {
        case entity, string
        /// Observed (`queries`): an `EntityQuery` 66, an `EntityStringQuery` 70.
        var capabilities: Int { self == .string ? 70 : 66 }
        /// A parameter of the query's entity: 1 for an `EntityQuery`, 2 for an `EntityStringQuery`.
        var dynamicOptions: Int { self == .string ? 2 : 1 }
    }

    let typeName: String
    let mangledName: String
    let file: String
    let line: Int
    let conformances: [String]
    let associatedTypes: [[String: Any]]
    let properties: [ConstProperty]
    let cases: [String]
    /// Its `@available` attributes (`platform`, `introducedVersion`, `isUnavailable`, `isDeprecated`).
    let availability: [[String: Any]]

    init(_ object: [String: Any]) throws {
        guard let typeName = object["typeName"] as? String, let mangled = object["mangledTypeName"] as? String else {
            throw NomacError("a type of the Swift compiler's constant values without a name")
        }
        self.typeName = typeName
        mangledName = mangled
        file = object["file"] as? String ?? ""
        line = object["line"] as? Int ?? 0
        conformances = object["conformances"] as? [String] ?? []
        associatedTypes = object["associatedTypeAliases"] as? [[String: Any]] ?? []
        cases = (object["cases"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        properties = try (object["properties"] as? [[String: Any]] ?? []).map(ConstProperty.init)
        availability = object["availabilityAttributes"] as? [[String: Any]] ?? []
    }

    /// The name without its module (`App.AddNote` is `AddNote`).
    var name: String { typeName.split(separator: ".").dropFirst().joined(separator: ".") }

    /// An intent's identifier: its name, or a migrated SiriKit intent's `intentClassName`
    /// (`controls`).
    var actionIdentifier: String {
        guard conformances.contains("AppIntents.CustomIntentMigratedAppIntent") else { return name }
        return property("intentClassName")?.value.raw ?? name
    }

    /// The App Intents protocols nomac knows; another one of those Swift Build gathers is refused.
    var role: Role? {
        if conformances.contains("AppIntents.AppIntent") { return .intent }
        if conformances.contains("AppIntents.AppEntity") { return .entity }
        if conformances.contains("AppIntents.EntityQuery") { return .query }
        if conformances.contains("AppIntents.AppEnum") { return .enumeration }
        if conformances.contains("AppIntents.AppShortcutsProvider") { return .shortcuts }
        return nil
    }

    var queryKind: QueryKind { conformances.contains("AppIntents.EntityStringQuery") ? .string : .entity }

    /// The App Intents conformances of a type nomac has not observed.
    var unknownAppIntentsConformances: [String] {
        let known: Set<String> = ["AppIntents.AppIntent", "AppIntents.AppEntity", "AppIntents.EntityQuery", "AppIntents.EntityStringQuery",
                                  "AppIntents.AppEnum", "AppIntents.AppShortcutsProvider", "AppIntents.PersistentlyIdentifiable",
                                  "AppIntents._SupportsAppDependencies", "AppIntents.AppValue", "AppIntents.DisplayRepresentable",
                                  "AppIntents.DynamicOptionsProvider", "AppIntents.InstanceDisplayRepresentable", "AppIntents.TypeDisplayRepresentable",
                                  "AppIntents.CaseDisplayRepresentable", "AppIntents.StaticDisplayRepresentable", "AppIntents._IntentValue",
                                  "AppIntents.EntityIdentifierConvertible", "AppIntents.AppIntentsPackageInternalProtocol",
                                  "AppIntents.WidgetConfigurationIntent", "AppIntents.ControlConfigurationIntent", "AppIntents.SetValueIntent",
                                  "AppIntents.CustomIntentMigratedAppIntent", "AppIntents.TransientAppEntity", "AppIntents.IndexedEntity",
                                  "AppIntents.OpenIntent", "AppIntents.SystemIntent", "AppIntents.SetFocusFilterIntent", "AppIntents.LiveActivityIntent",
                                  "AppIntents.DeleteIntent", "AppIntents.AppIntentsPackage"]
        return conformances.filter { $0.hasPrefix("AppIntents.") && !known.contains($0) }
    }

    func property(_ label: String) -> ConstProperty? { properties.first { $0.label == label } }

    func refusal(_ what: String) -> NomacError {
        NomacError("\(typeName) uses \(what), whose App Intents metadata nomac does not write yet (B-107)", path: file)
    }

    /// The App Intents protocols' requirements a type can set (the SDK's `AppIntent`, `AppEntity`,
    /// `EntityQuery`, `PersistentlyIdentifiable` and the display protocols).
    static let requirements: Set<String> = ["title", "description", "openAppWhenRun", "parameterSummary", "allowedExecutionTargets", "authenticationPolicy",
                                            "isDiscoverable", "supportedModes", "persistentIdentifier", "defaultQuery", "typeDisplayRepresentation",
                                            "caseDisplayRepresentations", "displayRepresentation", "intentClassName", "includedPackages"]

    /// Refuses a requirement nomac does not write (any not in `known`), and a property whose type is
    /// App Intents' other than the parameters (`_name: IntentParameter<…>`) and entity properties
    /// (`_name: EntityProperty<…>`) allowed, with their wrapped (`name`) and projected (`$name`)
    /// properties. The type's other properties are its own, which Xcode's tool does not read
    /// (`widget`'s `preview`), as are values left to run time (icecubes' `previewAccount`).
    func refuseUnknownProperties(_ known: Set<String>, parameters: Bool = false, entityProperties: Bool = false) throws {
        let wrappers = properties.filter { (parameters && $0.isParameter) || (entityProperties && $0.isEntityProperty) }.map { String($0.label.dropFirst()) }
        let allowed = known.union(wrappers).union(wrappers.map { "$" + $0 })
        for property in properties where !allowed.contains(property.label) && !(parameters && property.isParameter) && !(entityProperties && property.isEntityProperty) {
            if Self.requirements.contains(property.label) || (property.type.hasPrefix("AppIntents.") && property.value.kind != "Runtime") {
                throw refusal("the property `\(property.label)`")
            }
        }
        if let unknown = unknownAppIntentsConformances.first { throw refusal("the conformance to `\(unknown)`") }
    }

    /// `caseDisplayRepresentations` as written: a dictionary of each case to a string literal or a
    /// `DisplayRepresentation(title:subtitle:)`.
    func caseDisplayRepresentations() throws -> [String: FoundationJSON] {
        guard let property = property("caseDisplayRepresentations"), property.value.kind == "Dictionary", let entries = property.value.dictionaryEntries else {
            throw refusal("`caseDisplayRepresentations` other than a dictionary literal")
        }
        var result: [String: FoundationJSON] = [:]
        for (key, value) in entries {
            guard key.kind == "Enum", let name = key.enumName else { throw refusal("a case display representation keyed other than by `.case`") }
            if let title = try value.localizedString() {
                result[name] = .object(["title": AppIntentsMetadata.string(title)])
            } else if value.kind == "InitCall", value.callType == "AppIntents.DisplayRepresentation", let arguments = value.arguments {
                var representation: [String: FoundationJSON] = [:]
                for argument in arguments {
                    switch argument.label {
                    case "title", "subtitle" where argument.value.kind != "NilLiteral":
                        guard let text = try argument.value.localizedString() else { throw refusal("a display representation's `\(argument.label ?? "")`") }
                        representation[argument.label!] = AppIntentsMetadata.string(text)
                    default:
                        guard argument.value.kind == "NilLiteral" else { throw refusal("a display representation's `\(argument.label ?? "")`") }
                    }
                }
                result[name] = .object(representation)
            } else {
                throw refusal("a case display representation other than a string or `DisplayRepresentation(title:subtitle:)`")
            }
        }
        return result
    }
}

struct ConstProperty {
    let label: String
    let type: String
    let isStatic: Bool
    let line: Int
    let value: ConstValue
    init(_ object: [String: Any]) throws {
        label = object["label"] as? String ?? ""
        type = object["type"] as? String ?? ""
        isStatic = object["isStatic"] as? String == "true"
        line = object["line"] as? Int ?? 0
        value = ConstValue(kind: object["valueKind"] as? String ?? "", value: object["value"])
    }

    var isParameter: Bool { !isStatic && label.hasPrefix("_") && type.hasPrefix("AppIntents.IntentParameter<") }
    var isEntityProperty: Bool { !isStatic && label.hasPrefix("_") && type.hasPrefix("AppIntents.EntityProperty<") }

    func localizedString() throws -> String? { try value.localizedString() }
    func bool() throws -> Bool? { value.kind == "RawLiteral" ? value.raw == "true" : nil }
}

/// A value of the compiler's constant values: its kind (`RawLiteral`, `InitCall`, `Array`,
/// `Dictionary`, `Enum`, `InterpolatedStringLiteral`, `KeyPath`, `Builder`, `NilLiteral`, `Runtime`)
/// and its contents.
/// A localization key and the text it stands for when no table has it.
struct LocalizedText {
    var key: String
    var defaultValue: String?
    /// The table, when not the default one (bluewallet's `InfoPlist`, `sweep`).
    var table: String?
}

struct ConstValue {
    let kind: String
    let value: Any?

    struct Argument {
        let label: String?
        let value: ConstValue
    }

    struct Member {
        let kind: String
        let value: ConstValue
    }

    var raw: String? { kind == "RawLiteral" ? value as? String : nil }
    var callType: String? { (value as? [String: Any])?["type"] as? String }
    var enumName: String? { kind == "Enum" ? (value as? [String: Any])?["name"] as? String : nil }
    var member: (base: String, label: String)? {
        guard kind == "MemberReference", let object = value as? [String: Any], let base = object["baseType"] as? String, let label = object["memberLabel"] as? String else { return nil }
        return (base, label)
    }

    var arguments: [Argument]? {
        ((value as? [String: Any])?["arguments"] as? [[String: Any]])?.map {
            Argument(label: $0["label"] as? String, value: ConstValue(kind: $0["valueKind"] as? String ?? "", value: $0["value"]))
        }
    }

    var tupleElements: [ConstValue]? {
        guard kind == "Tuple" else { return nil }
        return (value as? [[String: Any]])?.map { ConstValue(kind: $0["valueKind"] as? String ?? "", value: $0["value"]) }
    }

    var elements: [ConstValue]? {
        guard kind == "Array" else { return nil }
        return (value as? [[String: Any]])?.map { ConstValue(kind: $0["valueKind"] as? String ?? "", value: $0["value"]) }
    }

    var dictionaryEntries: [(ConstValue, ConstValue)]? {
        guard kind == "Dictionary", let entries = value as? [[String: Any]] else { return nil }
        return entries.compactMap { entry in
            guard let key = entry["key"] as? [String: Any], let value = entry["value"] as? [String: Any] else { return nil }
            return (ConstValue(kind: key["valueKind"] as? String ?? "", value: key["value"]), ConstValue(kind: value["valueKind"] as? String ?? "", value: value["value"]))
        }
    }

    var builderMembers: [Member]? {
        guard kind == "Builder" else { return nil }
        return ((value as? [String: Any])?["members"] as? [[String: Any]])?.compactMap { member in
            guard let element = member["element"] as? [String: Any] else { return nil }
            return Member(kind: member["kind"] as? String ?? "", value: ConstValue(kind: element["valueKind"] as? String ?? "", value: element["value"]))
        }
    }

    var segments: [ConstValue]? {
        guard kind == "InterpolatedStringLiteral" else { return nil }
        return ((value as? [String: Any])?["segments"] as? [[String: Any]])?.map { ConstValue(kind: $0["valueKind"] as? String ?? "", value: $0["value"]) }
    }

    /// A string literal (`RawLiteral`), the text of a localized string resource.
    func localizedString() throws -> String? { raw }

    /// A localized string as `extract.actionsdata` writes it: a literal, a
    /// `LocalizedStringResource(_:defaultValue:table:comment:)` of the default locale and bundle,
    /// the comment left out (`controls`, `sweep`, `comments`), or an `IntentDescription` of either.
    func localizedText() -> LocalizedText? {
        if let raw { return LocalizedText(key: raw) }
        guard kind == "InitCall", let arguments else { return nil }
        let byLabel = Dictionary(arguments.map { ($0.label ?? "", $0.value) }, uniquingKeysWith: { first, _ in first })
        switch callType {
        case "Foundation.LocalizedStringResource":
            guard Set(byLabel.keys).isSubset(of: ["", "defaultValue", "table", "locale", "bundle", "comment"]),
                  let key = byLabel[""]?.raw, ["NilLiteral", "RawLiteral"].contains(byLabel["comment"]?.kind ?? "NilLiteral"),
                  byLabel["locale"]?.kind ?? "Runtime" == "Runtime", byLabel["bundle"]?.kind ?? "Runtime" == "Runtime" else { return nil }
            var text = LocalizedText(key: key)
            if let table = byLabel["table"], table.kind != "NilLiteral" {
                guard let name = table.raw else { return nil }
                text.table = name
            }
            if let defaultValue = byLabel["defaultValue"] {
                guard let value = defaultValue.raw else { return nil }
                text.defaultValue = value
            }
            return text
        case "AppIntents.IntentDescription":
            guard Set(byLabel.keys) == ["", "categoryName", "searchKeywords"], byLabel["categoryName"]?.kind == "NilLiteral",
                  byLabel["searchKeywords"]?.kind == "Runtime" else { return nil }
            return byLabel[""]?.localizedText()
        default:
            return nil
        }
    }

    /// A summary's interpolation: text and `\(\.$name)` as `${name}`.
    func summaryFormat() throws -> (text: String, parameters: [String])? {
        guard let segments else { return nil }
        var text = ""
        var parameters: [String] = []
        for segment in segments {
            if let raw = segment.raw {
                text += raw
            } else if segment.kind == "KeyPath", let path = (segment.value as? [String: Any])?["path"] as? String, path.hasPrefix("$") {
                text += "${" + path.dropFirst() + "}"
                parameters.append(String(path.dropFirst()))
            } else {
                return nil
            }
        }
        return (text, parameters)
    }

    /// An App Shortcut's phrase: text, `\(.applicationName)` as `${applicationName}` and a
    /// parameter (`\(\.$mood)`) as `${mood}` (`training`).
    func phraseTemplate() throws -> String? {
        // A literal is its own template (bluewallet's `"… with ${applicationName}"`, `sweep`).
        if let raw { return raw }
        guard let segments else { return nil }
        var text = ""
        for segment in segments {
            if let raw = segment.raw {
                text += raw
            } else if segment.enumName == "applicationName" {
                text += "${applicationName}"
            } else if segment.kind == "KeyPath", let path = (segment.value as? [String: Any])?["path"] as? String, path.hasPrefix("$") {
                text += "${" + path.dropFirst() + "}"
            } else {
                return nil
            }
        }
        return text
    }
}
