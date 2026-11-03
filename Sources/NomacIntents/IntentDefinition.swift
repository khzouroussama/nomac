import Foundation
import NomacCore
import NomacPlist

/// An intent definition (`.intentdefinition`), the property list Xcode's intent editor writes
/// (docs/formats/intents.md). Values are read as intentbuilderc reads them: a number written
/// as a string or a boolean is that number, and a missing boolean is false (intents-experiments).
public struct IntentDefinition: Sendable {
    public var intents: [Intent]
    public var enums: [Enumeration]
    public var types: [CustomType]

    public struct Intent: Sendable {
        public var name: String
        public var className: String?
        public var isSystem: Bool
        public var eligibleForWidgets: Bool
        public var parameters: [Parameter]
        public var responseCodes: [ResponseCode]
        public var responseParameters: [Parameter]
    }

    /// An intent's parameter, a response's parameter or a custom type's property.
    public struct Parameter: Sendable {
        public var name: String
        public var type: String
        public var objectType: String?
        public var objectTypeNamespace: String?
        public var enumType: String?
        public var supportsMultipleValues: Bool
        public var isConfigurable: Bool
        public var supportsDynamicEnumeration: Bool
        public var supportsResolution: Bool
        public var supportsSearch: Bool
        public var displayPriority: Int
    }

    public struct ResponseCode: Sendable {
        public var name: String
        public var formatString: String?
        public var conciseFormatString: String?
    }

    public struct Enumeration: Sendable {
        public var name: String
        public var className: String?
        public var generatesHeader: Bool
        public var values: [(name: String, index: Int)]
    }

    public struct CustomType: Sendable {
        public var name: String
        public var className: String?
        public var properties: [Parameter]
    }

    public static func read(at path: String) throws -> IntentDefinition {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw NomacError("The file “\((path as NSString).lastPathComponent)” doesn’t exist.", path: path)
        }
        let value: PropertyListValue
        if data.starts(with: Array("bplist00".utf8)) {
            value = try BinaryPropertyList.value(from: Array(data), path: path)
        } else {
            value = try TextPropertyListParser.parse(String(decoding: data, as: UTF8.self))
        }
        guard case .dictionary(let root) = value else {
            throw NomacError("not an intent definition", path: path)
        }
        return IntentDefinition(root)
    }

    init(_ root: [String: PropertyListValue]) {
        intents = Self.dictionaries(root["INIntents"]).map { intent in
            let response = Self.dictionary(intent["INIntentResponse"])
            return Intent(
                name: Self.string(intent["INIntentName"]) ?? "",
                className: Self.string(intent["INIntentClassName"]),
                isSystem: Self.string(intent["INIntentType"]) == "System",
                eligibleForWidgets: Self.bool(intent["INIntentEligibleForWidgets"]),
                parameters: Self.byPriority(Self.dictionaries(intent["INIntentParameters"]).map { Self.parameter($0, prefix: "INIntentParameter") }),
                responseCodes: Self.dictionaries(response["INIntentResponseCodes"]).map { code in
                    ResponseCode(name: Self.string(code["INIntentResponseCodeName"]) ?? "",
                                 formatString: Self.string(code["INIntentResponseCodeFormatString"]),
                                 conciseFormatString: Self.string(code["INIntentResponseCodeConciseFormatString"]))
                },
                responseParameters: Self.byPriority(Self.dictionaries(response["INIntentResponseParameters"]).map {
                    Self.parameter($0, prefix: "INIntentResponseParameter")
                }))
        }
        enums = Self.dictionaries(root["INEnums"]).map { entry in
            Enumeration(name: Self.string(entry["INEnumName"]) ?? "", className: Self.string(entry["INEnumClassName"]),
                        generatesHeader: Self.bool(entry["INEnumGeneratesHeader"]),
                        values: Self.dictionaries(entry["INEnumValues"]).map {
                            (Self.string($0["INEnumValueName"]) ?? "", Self.integer($0["INEnumValueIndex"]) ?? 0)
                        })
        }
        types = Self.dictionaries(root["INTypes"]).map { entry in
            CustomType(name: Self.string(entry["INTypeName"]) ?? "", className: Self.string(entry["INTypeClassName"]),
                       properties: Self.byPriority(Self.dictionaries(entry["INTypeProperties"]).map { Self.parameter($0, prefix: "INTypeProperty") }))
        }
    }

    private static func parameter(_ entry: [String: PropertyListValue], prefix: String) -> Parameter {
        Parameter(name: string(entry[prefix + "Name"]) ?? "", type: string(entry[prefix + "Type"]) ?? "",
                  objectType: string(entry[prefix + "ObjectType"]), objectTypeNamespace: string(entry[prefix + "ObjectTypeNamespace"]),
                  enumType: string(entry[prefix + "EnumType"]),
                  supportsMultipleValues: bool(entry[prefix + "SupportsMultipleValues"]),
                  isConfigurable: bool(entry[prefix + "Configurable"]),
                  supportsDynamicEnumeration: bool(entry[prefix + "SupportsDynamicEnumeration"]),
                  supportsResolution: bool(entry[prefix + "SupportsResolution"]),
                  supportsSearch: bool(entry[prefix + "SupportsSearch"]),
                  displayPriority: integer(entry[prefix + "DisplayPriority"]) ?? 0)
    }

    /// Parameters and properties in display priority order, ties in the file's order
    /// (intents-experiments `parameter-order`).
    private static func byPriority(_ parameters: [Parameter]) -> [Parameter] {
        parameters.enumerated().sorted { ($0.element.displayPriority, $0.offset) < ($1.element.displayPriority, $1.offset) }.map(\.element)
    }

    private static func dictionaries(_ value: PropertyListValue?) -> [[String: PropertyListValue]] {
        guard case .array(let elements) = value else { return [] }
        return elements.compactMap { if case .dictionary(let entry) = $0 { entry } else { nil } }
    }

    private static func dictionary(_ value: PropertyListValue?) -> [String: PropertyListValue] {
        if case .dictionary(let entry) = value { entry } else { [:] }
    }

    static func string(_ value: PropertyListValue?) -> String? {
        switch value {
        case .string(let string): string
        case .integer(let integer): String(integer)
        default: nil
        }
    }

    static func integer(_ value: PropertyListValue?) -> Int? {
        switch value {
        case .integer(let integer): integer
        case .real(let real): Int(real)
        case .boolean(let flag): flag ? 1 : 0
        case .string(let string): Int(string.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    static func bool(_ value: PropertyListValue?) -> Bool {
        switch value {
        case .boolean(let flag): flag
        case .integer(let integer): integer != 0
        case .real(let real): real != 0
        case .string(let string): ["yes", "true"].contains(string.lowercased()) || (Int(string) ?? 0) != 0
        default: false
        }
    }
}
