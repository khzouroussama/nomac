import Foundation
import Testing
import NomacPlist
@testable import NomacIntents

/// What `intentbuilderc generate -language Swift` (Xcode 27.0) writes
/// (`.github/scripts/intents_experiments.py`).
@Suite struct IntentCodeGeneratorTests {
    func parameter(_ name: String, _ type: String, priority: Int = 1, _ flags: [String: PropertyListValue] = [:]) -> PropertyListValue {
        var entry: [String: PropertyListValue] = ["INIntentParameterName": .string(name), "INIntentParameterType": .string(type),
                                                  "INIntentParameterDisplayPriority": .integer(priority)]
        entry.merge(flags) { $1 }
        return .dictionary(entry)
    }

    func intent(_ name: String, _ parameters: [PropertyListValue] = [], _ fields: [String: PropertyListValue] = [:]) -> PropertyListValue {
        var entry: [String: PropertyListValue] = ["INIntentName": .string(name), "INIntentType": .string("Custom"),
                                                  "INIntentParameters": .array(parameters)]
        entry.merge(fields) { $1 }
        return .dictionary(entry)
    }

    func files(intents: [PropertyListValue] = [], enums: [PropertyListValue] = [], types: [PropertyListValue] = [],
               classPrefix: String = "", visibility: String = "public") throws -> [IntentCodeGenerator.File] {
        let definition = IntentDefinition(["INIntents": .array(intents), "INEnums": .array(enums), "INTypes": .array(types)])
        return try IntentCodeGenerator(definition: definition, language: .swift, classPrefix: classPrefix, visibility: visibility).files()
    }

    func contents(_ files: [IntentCodeGenerator.File], _ name: String) -> String {
        files.first { $0.name == name }?.contents ?? ""
    }

    let color: PropertyListValue = .dictionary(["INEnumName": .string("Color"), "INEnumGeneratesHeader": .boolean(true), "INEnumValues": .array([
        .dictionary(["INEnumValueName": .string("unknown")]), .dictionary(["INEnumValueName": .string("red"), "INEnumValueIndex": .integer(1)]),
    ])])
    let thing: PropertyListValue = .dictionary(["INTypeName": .string("Thing"), "INTypeProperties": .array([])])

    @Test func filesAreIntentsThenEnumsThenTypes() throws {
        let generated = try files(intents: [intent("Zeta"), intent("Alpha"), intent("Play", [], ["INIntentType": .string("System")])],
                                  enums: [color], types: [thing])
        #expect(generated.map(\.name) == ["ZetaIntent.swift", "AlphaIntent.swift", "Color.swift", "Thing.swift"])
        #expect(contents(generated, "Color.swift").contains("    case `unknown` = 0\n    case `red` = 1\n}"))
    }

    @Test func propertiesFollowTheirTypesAndPriorities() throws {
        let text = contents(try files(intents: [intent("Probe", [
            parameter("zulu", "String", priority: 2), parameter("flag", "Boolean", priority: 0),
            parameter("many", "Integer", priority: 3, ["INIntentParameterSupportsMultipleValues": .boolean(true)]),
            parameter("place", "Placemark", priority: 4), parameter("amount", "Double", priority: 5), parameter("odd", "Bogus", priority: 6),
        ])]), "ProbeIntent.swift")
        #expect(text.contains("import Intents\nimport CoreLocation\n"))
        #expect(text.contains("""
                @available(iOS 13.0, macOS 10.16, watchOS 6.0, *)
                @NSManaged public var flag: NSNumber?
                @NSManaged public var zulu: String?
                @NSManaged public var many: [Int]?
                @NSManaged public var place: CLPlacemark?
                @NSManaged public var amount: Double
                @NSManaged public var odd: String?
            """))
    }

    /// Widget intents handle optionally, after confirming; the others must handle, first.
    @Test func handlingOrderDependsOnWidgets() throws {
        func methods(_ fields: [String: PropertyListValue]) throws -> [String] {
            contents(try files(intents: [intent("Probe", [], fields)]), "ProbeIntent.swift").split(separator: "\n")
                .filter { $0.contains("func handle") || $0.contains("func confirm") }.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        #expect(try methods([:]).first == "func handle(intent: ProbeIntent, completion: @escaping (ProbeIntentResponse) -> Swift.Void)")
        #expect(try methods(["INIntentEligibleForWidgets": .boolean(true)]).first
            == "optional func confirm(intent: ProbeIntent, completion: @escaping (ProbeIntentResponse) -> Swift.Void)")
    }

    @Test func dynamicOptionsAndResolution() throws {
        let text = contents(try files(intents: [intent("Probe", [
            parameter("count", "Integer", ["INIntentParameterSupportsResolution": .boolean(true)]),
            parameter("pay", "PaymentMethod", priority: 2, ["INIntentParameterConfigurable": .boolean(true)]),
            parameter("term", "String", priority: 3, ["INIntentParameterSupportsDynamicEnumeration": .boolean(true),
                                                      "INIntentParameterSupportsSearch": .boolean(true)]),
        ])]), "ProbeIntent.swift")
        #expect(text.contains("func resolveCount(for intent: ProbeIntent) async -> ProbeCountResolutionResult"))
        #expect(text.contains("public class ProbeCountResolutionResult: INIntegerResolutionResult {"))
        #expect(text.contains("    case negativeNumbersNotSupported = 1\n    case greaterThanMaximumValue\n    case lessThanMinimumValue\n"))
        let term = try #require(text.range(of: "func provideTermOptionsCollection(for intent: ProbeIntent, searchTerm: String?)"))
        let pay = try #require(text.range(of: "func providePayOptionsCollection(for intent: ProbeIntent)"))
        #expect(term.lowerBound < pay.lowerBound)
    }

    @Test func responseCodesAndConvenienceInitializers() throws {
        let response: PropertyListValue = .dictionary([
            "INIntentResponseCodes": .array([
                .dictionary(["INIntentResponseCodeName": .string("success"), "INIntentResponseCodeFormatString": .string("Got ${result}")]),
                .dictionary(["INIntentResponseCodeName": .string("notFound"), "INIntentResponseCodeConciseFormatString": .string("${count} ${result}")]),
            ]),
            "INIntentResponseParameters": .array([
                .dictionary(["INIntentResponseParameterName": .string("result"), "INIntentResponseParameterType": .string("String")]),
                .dictionary(["INIntentResponseParameterName": .string("count"), "INIntentResponseParameterType": .string("Integer")]),
            ]),
        ])
        let text = contents(try files(intents: [intent("Probe", [], ["INIntentResponse": response])]), "ProbeIntent.swift")
        #expect(text.contains("    case failureRequiringAppLaunch\n    case notFound = 100\n}"))
        #expect(text.contains("@objc(notFoundIntentResponseWithCount:result:)\n    public static func notFound(count: NSNumber, result: String) -> ProbeIntentResponse {"))
    }

    @Test func prefixVisibilityAndSystemObjects() throws {
        let generated = try files(intents: [intent("Probe", [parameter("item", "Object", ["INIntentParameterObjectType": .string("MediaItem"),
                                                                                           "INIntentParameterObjectTypeNamespace": .string("System")])])],
                                  types: [thing], classPrefix: "XY", visibility: "project")
        #expect(generated.map(\.name) == ["XYProbeIntent.swift", "XYThing.swift"])
        #expect(contents(generated, "XYProbeIntent.swift").contains("internal class XYProbeIntent: INIntent {\n\n    @NSManaged internal var item: INMediaItem?"))
        #expect(contents(generated, "XYThing.swift").contains("@objc(successWithResolvedThing:)\n    internal class func success(with resolvedObject: XYThing) -> Self {"))
    }

    /// An enum without a header of its own is a deprecated enum of the intent that uses it.
    @Test func enumsWithoutHeadersBelongToTheirIntents() throws {
        guard case .dictionary(var entry) = color else { return }
        entry["INEnumGeneratesHeader"] = .boolean(false)
        let generated = try files(intents: [intent("Probe", [parameter("shade", "Integer", ["INIntentParameterEnumType": .string("Color")])])],
                                  enums: [.dictionary(entry)])
        #expect(generated.map(\.name) == ["ProbeIntent.swift"])
        let text = contents(generated, "ProbeIntent.swift")
        #expect(text.contains("renamed: \"Color\")\n@objc public enum ProbeColor: Int {"))
        #expect(text.contains("@NSManaged public var shade: ProbeColor\n"))
    }

    @Test func objectiveCIsRefused() {
        let generator = IntentCodeGenerator(definition: IntentDefinition([:]), language: .objectiveC)
        #expect(throws: (any Error).self) { try generator.files() }
    }

    @Test func valuesAreReadAsIntentbuildercReadsThem() {
        #expect(IntentDefinition.integer(.string("01")) == 1)
        #expect(IntentDefinition.integer(.boolean(true)) == 1)
        #expect(IntentDefinition.bool(.string("YES")))
        #expect(!IntentDefinition.bool(nil))
    }
}
