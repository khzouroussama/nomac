import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacBuild

/// `extract.actionsdata` from the Swift compiler's constant values, on hand-written values shaped as
/// the compiler writes them (`.github/scripts/app_intents_experiments.py`'s `basic`, `queries`,
/// `dialogs`, `widget`).
@Suite struct AppIntentsMetadataTests {
    @Test func writesJSONAsDarwinsFoundationDoes() {
        let value = FoundationJSON.object(["b": .array([]), "a": .string("x/y"), "c": .object([:]), "d": .array([.int(1), .bool(true)])])
        #expect(value.compact == #"{"a":"x\/y","b":[],"c":{},"d":[1,true]}"#)
        #expect(value.pretty == "{\n  \"a\" : \"x\\/y\",\n  \"b\" : [\n\n  ],\n  \"c\" : {\n\n  },\n  \"d\" : [\n    1,\n    true\n  ]\n}")
    }

    static func argument(_ label: String, _ kind: String, _ value: Any? = nil) -> [String: Any] {
        var argument: [String: Any] = ["label": label, "type": "", "valueKind": kind]
        if let value { argument["value"] = value }
        return argument
    }

    static func property(_ label: String, type: String, isStatic: Bool, kind: String, value: Any? = nil) -> [String: Any] {
        var property: [String: Any] = ["label": label, "type": type, "isStatic": isStatic ? "true" : "false", "isComputed": "false", "line": 3, "valueKind": kind]
        if let value { property["value"] = value }
        return property
    }

    static func parameter(_ name: String, _ type: String, _ arguments: [[String: Any]]) -> [String: Any] {
        property("_" + name, type: "AppIntents.IntentParameter<\(type)>", isStatic: false, kind: "InitCall",
                 value: ["type": "AppIntents.IntentParameter<\(type)>", "arguments": arguments])
    }

    static var intent: [String: Any] { [
        "typeName": "App.Share", "mangledTypeName": "3App5ShareV", "kind": "struct", "file": "/src/Intents.swift", "line": 1,
        "conformances": ["AppIntents.AppIntent", "AppIntents.PersistentlyIdentifiable"],
        "associatedTypeAliases": [["typeAliasName": "PerformResult", "substitutedTypeName": "some AppIntents.IntentResult",
                                   "opaqueTypeProtocolRequirements": ["AppIntents.IntentResult"], "opaqueTypeSameTypeRequirements": []]],
        "properties": [
            property("title", type: "Foundation.LocalizedStringResource", isStatic: true, kind: "RawLiteral", value: "Share"),
            parameter("text", "Swift.String", [argument("title", "RawLiteral", "Text"), argument("default", "RawLiteral", "hi"),
                                              argument("inputConnectionBehavior", "Runtime")]),
            parameter("files", "Swift.Array<AppIntents.IntentFile>", [
                argument("title", "RawLiteral", "Files"), argument("description", "RawLiteral", "To share"),
                argument("supportedContentTypes", "Array", [["valueKind": "MemberReference", "value": ["baseType": "UniformTypeIdentifiers.UTType", "memberLabel": "gif"]]]),
                argument("inputConnectionBehavior", "Enum", ["name": "connectToPreviousIntentResult"]), argument("requestValueDialog", "RawLiteral", "Which?"),
            ]),
            property("helper", type: "Swift.Int", isStatic: true, kind: "RawLiteral", value: "1"),
        ],
    ] }

    func metadata(_ types: [[String: Any]], dependencies: [[String: Any]] = []) throws -> AppIntentsMetadata {
        let directory = try TemporaryDirectory()
        let file = directory.path + "/Intents.swiftconstvalues"
        try FileSystem.write(try JSONSerialization.data(withJSONObject: types), to: file)
        return try AppIntentsMetadata(constValueFiles: [file], moduleName: "App", dependencies: dependencies)
    }

    /// A framework's entity and enum as an app intent's parameters (`dependency`): typed by the
    /// framework's metadata, an entity without dynamic options, an enum default by its title.
    @Test func writesTypesOfDependencies() throws {
        let kit: [String: Any] = [
            "entities": ["Fruit": ["fullyQualifiedTypeName": "Kit.Fruit", "typeName": "Fruit"]],
            "enums": [["fullyQualifiedTypeName": "Kit.Flavor", "identifier": "Flavor",
                       "cases": [["identifier": "sweet", "displayRepresentation": ["title": ["alternatives": [Any](), "key": "Sweet"]]]]]],
        ]
        var intent = Self.intent
        intent["associatedTypeAliases"] = [[String: Any]]()
        intent["properties"] = [
            Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Eat"),
            Self.parameter("fruit", "Kit.Fruit", [Self.argument("title", "RawLiteral", "Fruit")]),
            Self.parameter("flavor", "Kit.Flavor", [Self.argument("title", "RawLiteral", "Flavor"), Self.argument("default", "Enum", ["name": "sweet"])]),
        ]
        guard case .object(let top) = try metadata([intent], dependencies: [kit]).actionsData(xcodeVersion: "27A266a"), case .object(let actions)? = top["actions"],
              case .object(let action)? = actions["Share"], case .array(let parameters)? = action["parameters"] else {
            Issue.record("no Eat action")
            return
        }
        #expect(parameters[0].compact.contains(#""dynamicOptionsSupport":0"#) && parameters[0].compact.contains(#""valueType":{"entity":{"wrapper":{"typeName":"Fruit"}}}"#))
        #expect(parameters[1].compact.contains(#"["LNValueTypeSpecificMetadataKeyDefaultValue",{"string":{"wrapper":"Sweet"}}]"#))
        #expect(throws: NomacError.self) { try metadata([intent]).actionsData(xcodeVersion: "27A266a") }
    }

    @Test func writesAnIntentsParameters() throws {
        let data = try metadata([Self.intent]).actionsData(xcodeVersion: "27A266a")
        guard case .object(let top) = data, case .object(let actions)? = top["actions"], case .object(let share)? = actions["Share"],
              case .array(let parameters)? = share["parameters"], case .object(let text) = parameters[0], case .object(let files) = parameters[1] else {
            Issue.record("no Share action in \(data.compact)")
            return
        }
        #expect(top["autoShortcutProviderMangledName"] == nil)
        #expect(share["supportedModes"] == .int(1))
        #expect(text["capabilities"] == .int(1))
        #expect(text["typeSpecificMetadata"] == .array([.string("LNValueTypeSpecificMetadataKeyDefaultValue"), .object(["string": .object(["wrapper": .string("hi")])])]))
        #expect(files["isInput"] == .bool(true) && files["inputConnectionBehavior"] == .int(2))
        #expect(files["parameterDescription"] == AppIntentsMetadata.string("To share"))
        #expect(files["valueType"] == AppIntentsMetadata.array(of: .object(["intents": .object(["wrapper": .object(["typeIdentifier": .int(12)])])]), capabilities: 3))
        #expect(files["typeSpecificMetadata"] == .array([.string("LNValueTypeMetadataKeyFileSupportedTypes"),
                                                       .object(["array": .object(["elements": .array([.object(["string": .object(["wrapper": .string("com.compuserve.gif")])])])])])]))
    }

    @Test func refusesWhatNoExperimentShowed() throws {
        var intent = Self.intent
        intent["properties"] = [Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Share"),
                                Self.parameter("data", "Foundation.Data", [Self.argument("title", "RawLiteral", "Data")])]
        #expect(throws: NomacError.self) { try metadata([intent]).actionsData(xcodeVersion: "27A266a") }
        intent["properties"] = [Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Share"),
                                Self.property("authenticationPolicy", type: "AppIntents.IntentAuthenticationPolicy", isStatic: true, kind: "Enum", value: ["name": "requiresAuthentication"])]
        #expect(throws: NomacError.self) { try metadata([intent]).actionsData(xcodeVersion: "27A266a") }
    }

    /// Xcode writes resolvable input types and root.ssu.yaml's parameter variables in set order,
    /// which changes from build to build (three builds of `basic`); nothing else may differ.
    @Test func judgesOutputsThatDifferOnlyInSetOrderEquivalent() throws {
        let a = #"{"actions":{"A":{"parameters":[{"name":"x","resolvableInputTypes":[{"t":0},{"t":2}]}]}}}"#
        let b = #"{"actions":{"A":{"parameters":[{"name":"x","resolvableInputTypes":[{"t":2},{"t":0}]}]}}}"#
        let c = #"{"actions":{"A":{"parameters":[{"name":"y","resolvableInputTypes":[{"t":2},{"t":0}]}]}}}"#
        #expect(AppIntentsMetadata.sameButForSetOrder("extract.actionsdata", a, b))
        #expect(!AppIntentsMetadata.sameButForSetOrder("extract.actionsdata", a, c))
        let head = "apiVersion: ssu/v1\nvariables:\n- name: +applicationName\n  type: ssu/expansion\n"
        let x = head + "- name: Mood\n  type: ssu/parameter\n- name: Note\n  type: ssu/parameter\n"
        let y = head + "- name: Note\n  type: ssu/parameter\n- name: Mood\n  type: ssu/parameter\n"
        #expect(AppIntentsMetadata.sameButForSetOrder("root.ssu.yaml", x, y))
        #expect(!AppIntentsMetadata.sameButForSetOrder("root.ssu.yaml", x, y.replacingOccurrences(of: "Mood", with: "Mode")))
        let directory = try TemporaryDirectory()
        try directory.writeExactly(a, to: "x/App.app/Metadata.appintents/extract.actionsdata")
        try directory.writeExactly(b, to: "y/App.app/Metadata.appintents/extract.actionsdata")
        #expect(try BuildProducts.compareFile(directory.path + "/x/App.app/Metadata.appintents/extract.actionsdata",
                                              directory.path + "/y/App.app/Metadata.appintents/extract.actionsdata")
            == .equivalent([BuildProducts.documented["appintents.set-order"]!]))
    }

    static func resource(_ key: String, _ defaultValue: String) -> [String: Any] {
        ["type": "Foundation.LocalizedStringResource", "arguments": [argument("", "RawLiteral", key), argument("defaultValue", "RawLiteral", defaultValue),
                                                                     argument("table", "NilLiteral"), argument("locale", "Runtime"),
                                                                     argument("bundle", "Runtime"), argument("comment", "NilLiteral")]]
    }

    /// home-assistant's control forms (`controls`): string resources with default values,
    /// `@available`, a control configuration intent, a migrated SiriKit intent.
    @Test func writesControlsAvailabilityAndMigratedIntents() throws {
        var control = Self.intent
        control["typeName"] = "App.Run"
        control["conformances"] = ["AppIntents.ControlConfigurationIntent", "AppIntents.AppIntent"]
        control["associatedTypeAliases"] = [[String: Any]]()
        control["availabilityAttributes"] = [["platform": "iOS", "introducedVersion": "17.0", "isUnavailable": false, "isDeprecated": false]]
        control["properties"] = [Self.property("title", type: "", isStatic: true, kind: "InitCall", value: Self.resource("run.title", "Run Script"))]
        var migrated = Self.intent
        migrated["typeName"] = "App.Update"
        migrated["conformances"] = ["AppIntents.AppIntent", "AppIntents.CustomIntentMigratedAppIntent"]
        migrated["associatedTypeAliases"] = [[String: Any]]()
        migrated["properties"] = [Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Update"),
                                  Self.property("intentClassName", type: "Swift.String", isStatic: true, kind: "RawLiteral", value: "UpdateSensorsIntent")]
        guard case .object(let top) = try metadata([control, migrated]).actionsData(xcodeVersion: "27A266a"), case .object(let actions)? = top["actions"],
              case .object(let run)? = actions["Run"], case .object(let update)? = actions["UpdateSensorsIntent"] else {
            Issue.record("no Run or UpdateSensorsIntent action")
            return
        }
        #expect(run["title"] == .object(["alternatives": .array([]), "defaultValue": .string("Run Script"), "key": .string("run.title")]))
        #expect(run["availabilityAnnotations"] == .object(["LNPlatformNameIOS": .object(["introducedVersion": .string("17.0")]),
                                                           "LNPlatformNameWildcard": .object(["introducedVersion": .string("*")])]))
        #expect(run["isDiscoverable"] == .bool(false) && run["outputFlags"] == .int(8)
            && run["systemProtocols"] == .array([.string("com.apple.link.systemProtocol.ControlConfiguration")]))
        #expect(update["identifier"] == .string("UpdateSensorsIntent") && update["customIntentClassName"] == .string("UpdateSensorsIntent"))
        control["availabilityAttributes"] = [["platform": "tvOS", "introducedVersion": "17.0", "isUnavailable": false, "isDeprecated": false]]
        #expect(throws: NomacError.self) { try metadata([control]).actionsData(xcodeVersion: "27A266a") }
    }

    /// `When(\.$on, .equalTo, true) { Summary { \.$on } } otherwise: { Summary("Off \(\.$on)") }`
    /// (`summaries`).
    @Test func writesWhenSummaries() throws {
        func keyPath(_ name: String) -> [String: Any] { ["valueKind": "KeyPath", "value": ["path": "$" + name, "rootType": "App.Share", "components": [[String: Any]]()]] }
        func builder(_ elements: [[String: Any]]) -> [String: Any] { ["members": elements.map { ["kind": "buildExpression", "element": $0] }] }
        let list = ["valueKind": "InitCall", "value": ["type": "AppIntents.IntentParameterSummary<App.Share>",
                                                        "arguments": [Self.argument("", "Builder", builder([keyPath("on")]))]]] as [String: Any]
        let format = ["valueKind": "InitCall", "value": ["type": "AppIntents.IntentParameterSummary<App.Share>", "arguments": [
            Self.argument("", "InterpolatedStringLiteral", ["segments": [["valueKind": "RawLiteral", "value": "Off "], keyPath("on")]]),
            Self.argument("table", "NilLiteral")]]] as [String: Any]
        var intent = Self.intent
        intent["associatedTypeAliases"] = [[String: Any]]()
        intent["properties"] = [
            Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Share"),
            Self.parameter("on", "Swift.Bool", [Self.argument("title", "RawLiteral", "On"), Self.argument("default", "RawLiteral", "true")]),
            Self.property("parameterSummary", type: "", isStatic: true, kind: "InitCall", value: [
                "type": "AppIntents.ParameterSummaryWhenCondition<App.Share>", "arguments": [
                    Self.argument("", "KeyPath", keyPath("on")["value"]), Self.argument("", "Enum", ["name": "equalTo"]), Self.argument("", "RawLiteral", "true"),
                    Self.argument("", "Builder", builder([list])), Self.argument("otherwise", "Builder", builder([format])),
                ]]),
        ]
        let data = try metadata([intent]).actionsData(xcodeVersion: "27A266a")
        #expect(data.compact.contains(#""actionConfiguration":{"whenClause":{"wrapper":{"condition":{"comparisonOperator":2,"parameterIdentifier":"on","value":{"bool":{"value":true}}},"#
            + #""otherwise":{"actionSummary":{"wrapper":{"otherParameterIdentifiers":[],"summaryString":{"formatString":"Off ${on}","parameterIdentifiers":["on"]}}}},"#
            + #""when":{"actionSummary":{"wrapper":{"otherParameterIdentifiers":["on"]}}}}}}"#))
    }

    /// home-assistant's entity forms (`entities`): a transient entity with a URL property and a
    /// resource name, an indexed entity with `@available`, an open intent on it.
    @Test func writesTransientIndexedAndOpenedEntities() throws {
        func type(_ name: String, _ conformances: [String], _ properties: [[String: Any]], availability: [[String: Any]] = []) -> [String: Any] {
            ["typeName": "App." + name, "mangledTypeName": "3App\(name.count)\(name)V", "kind": "struct", "file": "/src/E.swift", "line": 1,
             "conformances": conformances, "associatedTypeAliases": [[String: Any]](), "properties": properties, "availabilityAttributes": availability]
        }
        let state = type("State", ["AppIntents.TransientAppEntity", "AppIntents.AppEntity"], [
            Self.property("typeDisplayRepresentation", type: "AppIntents.TypeDisplayRepresentation", isStatic: true, kind: "InitCall", value: [
                "type": "AppIntents.TypeDisplayRepresentation", "arguments": [Self.argument("name", "InitCall", Self.resource("state.name", "Entity State")),
                                                                              Self.argument("numericFormat", "NilLiteral")]]),
            Self.property("_link", type: "AppIntents.EntityProperty<Swift.Optional<Foundation.URL>>", isStatic: false, kind: "InitCall", value: [
                "type": "AppIntents.EntityProperty<Swift.Optional<Foundation.URL>>", "arguments": [Self.argument("title", "RawLiteral", "Link")]]),
        ])
        let place = type("Place", ["AppIntents.AppEntity", "AppIntents.IndexedEntity"], [
            Self.property("typeDisplayRepresentation", type: "", isStatic: true, kind: "RawLiteral", value: "Place"),
            Self.property("defaultQuery", type: "App.PlaceQuery", isStatic: true, kind: "InitCall", value: ["type": "App.PlaceQuery", "arguments": [[String: Any]]()]),
        ], availability: [["platform": "iOS", "introducedVersion": "17", "isUnavailable": false, "isDeprecated": false]])
        let query = type("PlaceQuery", ["AppIntents.EntityQuery"], [])
        var open = Self.intent
        open["conformances"] = ["AppIntents.OpenIntent", "AppIntents.AppIntent", "AppIntents.SystemIntent"]
        open["associatedTypeAliases"] = [[String: Any]]()
        open["properties"] = [Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Show"),
                              Self.parameter("target", "App.Place", [Self.argument("title", "RawLiteral", "Place")])]
        guard case .object(let top) = try metadata([state, place, query, open]).actionsData(xcodeVersion: "27A266a"), case .object(let entities)? = top["entities"],
              case .object(let transient)? = entities["State"], case .object(let indexed)? = entities["Place"],
              case .object(let actions)? = top["actions"], case .object(let show)? = actions["Share"] else {
            Issue.record("no entities or open intent")
            return
        }
        #expect(transient["transient"] == .bool(true) && transient["defaultQueryIdentifier"] == nil)
        #expect(transient["displayTypeName"] == .object(["alternatives": .array([]), "defaultValue": .string("Entity State"), "key": .string("state.name")]))
        #expect(transient["properties"]?.compact.contains(#""isOptional":true"#) == true && transient["properties"]?.compact.contains(#""typeIdentifier":11"#) == true)
        #expect(indexed["systemProtocolMetadata"] == .array([.string("com.apple.appintents.entity.Indexed"), .object(["empty": .object([:])])]))
        #expect(indexed["availabilityAnnotations"]?.compact.contains(#""LNPlatformNameIOS":{"introducedVersion":"17"}"#) == true)
        #expect(show["openAppWhenRun"] == .bool(true) && show["systemProtocols"] == .array([.string("com.apple.link.systemProtocol.OpenEntity")]))
        #expect(show["typeSpecificMetadata"] == .array([.string("LNActionTypeMetadataKeyEntityMetadata"), .object(["entityMetadata": .object(["wrapper": .object(indexed)])]),
                                                        .string("LNActionTypeMetadataKeyEntityType"), .object(["string": .object(["wrapper": .string("Place")])])]))
    }

    /// gomap's live activity intents and home-assistant's focus filter, sized widget arrays and
    /// date kinds (`sessions`).
    @Test func writesSessionsSizesAndDateKinds() throws {
        var focus = Self.intent
        focus["conformances"] = ["AppIntents.SetFocusFilterIntent", "AppIntents.AppIntent", "AppIntents.LiveActivityIntent"]
        focus["associatedTypeAliases"] = [[String: Any]]()
        focus["properties"] = [
            Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Focus"),
            Self.property("isDiscoverable", type: "Swift.Bool", isStatic: true, kind: "RawLiteral", value: "false"),
            Self.parameter("start", "Swift.Optional<Foundation.Date>", [Self.argument("title", "RawLiteral", "Starts"), Self.argument("kind", "Enum", ["name": "dateTime"])]),
            Self.parameter("tags", "Swift.Array<Swift.String>", [Self.argument("title", "RawLiteral", "Tags"), Self.argument("size", "Dictionary", [
                ["key": ["valueKind": "Enum", "value": ["name": "systemSmall"]], "value": ["valueKind": "RawLiteral", "value": "3"]]])]),
        ]
        guard case .object(let top) = try metadata([focus]).actionsData(xcodeVersion: "27A266a"), case .object(let actions)? = top["actions"],
              case .object(let action)? = actions["Share"], case .array(let parameters)? = action["parameters"] else {
            Issue.record("no focus filter")
            return
        }
        #expect(action["systemProtocols"] == .array([.string("com.apple.link.systemProtocol.FocusConfiguration"), .string("com.apple.link.systemProtocol.SessionStarting")]))
        #expect(action["systemProtocolMetadata"]?.compact == #"["com.apple.link.systemProtocol.FocusConfiguration",{"empty":{}},"com.apple.link.systemProtocol.SessionStarting",{"empty":{}}]"#)
        #expect(action["isDiscoverable"] == .bool(false) && action["visibilityMetadata"]?.compact == #"{"assistantOnly":false,"isDiscoverable":false}"#)
        #expect(parameters[0].compact.contains(#""typeSpecificMetadata":["LNValueTypeMetadataKeyDateFormat",{"int":{"wrapper":2}}]"#))
        #expect(parameters[1].compact.contains(#"["LNValueTypeMetadataKeyCollectionSizes",{"collectionSizes":{"sizes":{"systemSmall":{"max":3,"min":3}}}}]"#))
    }

    /// The RN sweep's forms (`sweep`): bluewallet's titles from the InfoPlist table, visionOS,
    /// its provider's tile color and availability, App Shortcuts behind `if #available` left out.
    @Test func writesTablesVisionOSAndTileColors() throws {
        var intent = Self.intent
        intent["associatedTypeAliases"] = [[String: Any]]()
        intent["availabilityAttributes"] = [["platform": "visionOS", "introducedVersion": "2.0", "isUnavailable": false, "isDeprecated": false]]
        intent["properties"] = [Self.property("title", type: "", isStatic: true, kind: "InitCall", value: [
            "type": "Foundation.LocalizedStringResource", "arguments": [Self.argument("", "RawLiteral", "SEND"), Self.argument("table", "RawLiteral", "InfoPlist"),
                                                                        Self.argument("locale", "Runtime"), Self.argument("bundle", "Runtime"), Self.argument("comment", "NilLiteral")]])]
        let shortcut: [String: Any] = ["valueKind": "InitCall", "value": ["type": "AppIntents.AppShortcut", "arguments": [
            Self.argument("intent", "InitCall", ["type": "App.Share", "arguments": [[String: Any]]()]),
            Self.argument("phrases", "Array", [["valueKind": "RawLiteral", "value": "Share with ${applicationName}"]]),
            Self.argument("shortTitle", "RawLiteral", "Share"), Self.argument("systemImageName", "RawLiteral", "square")]]]
        let provider: [String: Any] = [
            "typeName": "App.Shortcuts", "mangledTypeName": "3App9ShortcutsV", "kind": "struct", "file": "/src/S.swift", "line": 1,
            "conformances": ["AppIntents.AppShortcutsProvider"], "associatedTypeAliases": [[String: Any]](),
            "availabilityAttributes": [["platform": "iOS", "introducedVersion": "16.4", "isUnavailable": false, "isDeprecated": false]],
            "properties": [Self.property("shortcutTileColor", type: "AppIntents.ShortcutTileColor", isStatic: true, kind: "Enum", value: ["name": "blue"]),
                           Self.property("appShortcuts", type: "", isStatic: true, kind: "Builder", value: ["members": [
                               ["kind": "buildExpression", "element": shortcut],
                               ["kind": "buildLimitedAvailability", "ifElements": [shortcut], "elseElements": [[String: Any]]()],
                           ]])],
        ]
        guard case .object(let top) = try metadata([intent, provider]).actionsData(xcodeVersion: "27A266a"), case .object(let actions)? = top["actions"],
              case .object(let share)? = actions["Share"], case .array(let shortcuts)? = top["autoShortcuts"] else {
            Issue.record("no Share action or shortcuts")
            return
        }
        #expect(share["title"] == .object(["alternatives": .array([]), "key": .string("SEND"), "table": .string("InfoPlist")]))
        #expect(share["availabilityAnnotations"]?.compact.contains(#""LNPlatformNameVISIONOS":{"introducedVersion":"2.0"}"#) == true)
        #expect(top["shortcutTileColor"] == .int(7) && shortcuts.count == 1)
        #expect(shortcuts[0].compact.contains(#""availabilityAnnotations":{"LNPlatformNameIOS":{"introducedVersion":"16.4"}"#))
        #expect(shortcuts[0].compact.contains(#""phraseTemplates":[{"alternatives":[],"key":"Share with ${applicationName}"}]"#))
    }

    /// URLs, Int ranges and length measurements (`more`).
    @Test func writesURLsIntRangesAndMeasurements() throws {
        var intent = Self.intent
        intent["associatedTypeAliases"] = [[String: Any]]()
        intent["properties"] = [
            Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Values"),
            Self.parameter("link", "Foundation.URL", [Self.argument("title", "RawLiteral", "Link")]),
            Self.parameter("count", "Swift.Int", [Self.argument("title", "RawLiteral", "Count"),
                                                  Self.argument("inclusiveRange", "Tuple", [["valueKind": "RawLiteral", "value": "1"], ["valueKind": "RawLiteral", "value": "10"]])]),
            Self.parameter("distance", "Swift.Optional<Foundation.Measurement<Foundation.UnitLength>>", [
                Self.argument("title", "RawLiteral", "Distance"), Self.argument("defaultUnitAdjustForLocale", "Runtime"), Self.argument("supportsNegativeNumbers", "Runtime")]),
        ]
        guard case .object(let top) = try metadata([intent]).actionsData(xcodeVersion: "27A266a"), case .object(let actions)? = top["actions"],
              case .object(let action)? = actions["Share"], case .array(let parameters)? = action["parameters"] else {
            Issue.record("no Values action")
            return
        }
        #expect(parameters[0].compact.contains(#""valueType":{"primitive":{"wrapper":{"typeIdentifier":11}}}"#))
        #expect(parameters[1].compact.contains(#""LNValueTypeMetadataKeyNumberUpperBound",{"double":{"wrapper":10}}"#))
        #expect(parameters[2].compact.contains(#""valueType":{"measurement":{"wrapper":{"unitType":1}}}"#)
            && parameters[2].compact.contains(#""LNValueTypeMetadataKeyMeasurementUnitAdjustsForLocale",{"int":{"wrapper":0}}"#))
        intent["properties"] = [Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Values"),
                                Self.parameter("speed", "Foundation.Measurement<Foundation.UnitSpeed>", [Self.argument("title", "RawLiteral", "Speed")])]
        #expect(throws: NomacError.self) { try metadata([intent]).actionsData(xcodeVersion: "27A266a") }
    }

    /// `extract.packagedata` (`package`): the mangled names of the packages a target's
    /// `AppIntentsPackage` includes; set-ordered keys are equivalent.
    @Test func writesPackageData() throws {
        let package: [String: Any] = [
            "typeName": "App.AppPackage", "mangledTypeName": "3App0A7PackageV", "kind": "struct", "file": "/src/P.swift", "line": 1,
            "conformances": ["AppIntents.AppIntentsPackage"], "associatedTypeAliases": [[String: Any]](),
            "properties": [Self.property("includedPackages", type: "", isStatic: true, kind: "Array", value: [
                ["valueKind": "Type", "value": ["type": "Kit.KitPackage", "mangledName": "3Kit0A7PackageV"]]])],
        ]
        #expect(try metadata([Self.intent, package]).packageData()?.compact == #"{"includes":["3Kit0A7PackageV"],"version":1}"#)
        #expect(try metadata([Self.intent]).packageData() == nil)
        #expect(throws: NomacError.self) { try metadata([package]).packageData() }
        #expect(AppIntentsMetadata.sameButForSetOrder("extract.packagedata", #"{"version":1,"includes":[]}"#, #"{"includes":[],"version":1}"#))
    }

    /// netnewswire's titles with translator comments (`comments`): the comment is left out.
    @Test func leavesCommentsOut() {
        let title = ConstValue(kind: "InitCall", value: ["type": "Foundation.LocalizedStringResource", "arguments": [
            Self.argument("", "RawLiteral", "URL"), Self.argument("table", "NilLiteral"), Self.argument("locale", "Runtime"),
            Self.argument("bundle", "Runtime"), Self.argument("comment", "RawLiteral", "Label for a feed URL")]])
        #expect(title.localizedText().map(AppIntentsMetadata.string) == AppIntentsMetadata.string("URL"))
    }

    @Test func writesNumbersRangesAndInputOptions() throws {
        var intent = Self.intent
        intent["properties"] = [
            Self.property("title", type: "", isStatic: true, kind: "RawLiteral", value: "Types"),
            Self.parameter("ratio", "Swift.Double", [Self.argument("title", "RawLiteral", "Ratio"), Self.argument("default", "RawLiteral", "0.5"),
                                                    Self.argument("inclusiveRange", "Tuple", [["valueKind": "RawLiteral", "value": "0"], ["valueKind": "RawLiteral", "value": "1"]])]),
            Self.parameter("on", "Swift.Bool", [Self.argument("title", "RawLiteral", "On"), Self.argument("default", "RawLiteral", "true")]),
            Self.parameter("name", "Swift.Optional<Swift.String>", [Self.argument("title", "RawLiteral", "Name"),
                                                                   Self.argument("optionsProvider", "InitCall", ["type": "App.Names", "arguments": [[String: Any]]()]),
                                                                   Self.argument("inputOptions", "InitCall", ["type": "Swift.String.IntentInputOptions", "arguments": [
                                                                       Self.argument("keyboardType", "Runtime"), Self.argument("capitalizationType", "Enum", ["name": "none"]),
                                                                       Self.argument("multiline", "RawLiteral", "true")]])]),
        ]
        guard case .object(let top) = try metadata([intent]).actionsData(xcodeVersion: "27A266a"), case .object(let actions)? = top["actions"],
              case .object(let share)? = actions["Share"], case .array(let parameters)? = share["parameters"],
              case .object(let ratio) = parameters[0], case .object(let on) = parameters[1], case .object(let name) = parameters[2] else {
            Issue.record("no parameters")
            return
        }
        #expect(ratio["valueType"] == AppIntentsMetadata.primitive(7))
        #expect(ratio["typeSpecificMetadata"]?.compact.contains(#""LNValueTypeMetadataKeyNumberUpperBound",{"double":{"wrapper":1}}"#) == true)
        #expect(ratio["typeSpecificMetadata"]?.compact.contains(#"{"double":{"wrapper":0.5}}"#) == true)
        #expect(on["typeSpecificMetadata"] == .array([.string("LNValueTypeSpecificMetadataKeyDefaultValue"), .object(["int": .object(["wrapper": .int(1)])])]))
        #expect(name["capabilities"] == .int(8) && name["dynamicOptionsSupport"] == .int(1))
        #expect(name["typeSpecificMetadata"]?.compact.contains(#""LNValueTypeMetadataKeyStringMultiline",{"int":{"wrapper":1}}"#) == true)
        let a = #"{"p":{"typeSpecificMetadata":["a",{"int":1},"b",{"int":2}]}}"#
        let b = #"{"p":{"typeSpecificMetadata":["b",{"int":2},"a",{"int":1}]}}"#
        #expect(AppIntentsMetadata.sameButForSetOrder("extract.actionsdata", a, b))
        #expect(!AppIntentsMetadata.sameButForSetOrder("extract.actionsdata", a, b.replacingOccurrences(of: "2}", with: "3}")))
    }
}
