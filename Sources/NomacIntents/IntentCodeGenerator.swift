import Foundation
import NomacCore

/// The classes `intentbuilderc generate` writes for an intent definition in Xcode 27.0: one
/// file per intent, custom type and enum (docs/formats/intents.md "Generated classes";
/// intents-experiments and the corpus's and holdout's definitions).
public struct IntentCodeGenerator: Sendable {
    public enum Language: String, Sendable {
        case swift = "Swift"
        case objectiveC = "Objective-C"
    }

    public struct File: Sendable, Equatable {
        public var name: String
        public var contents: String
    }

    public var definition: IntentDefinition
    public var language: Language
    public var classPrefix: String
    /// `-visibility`: `project` declares everything `internal`; `public` and `private` are `public`.
    public var visibility: String

    /// `-swiftVersion` and `-moduleName` do not change what is generated (intents-experiments
    /// `swift6`, `swift-module`).
    public init(definition: IntentDefinition, language: Language, classPrefix: String = "", visibility: String = "public") {
        self.definition = definition
        self.language = language
        self.classPrefix = classPrefix
        self.visibility = visibility
    }

    /// The files, in the order intentbuilderc writes and lists them: custom intents (a system
    /// intent has none), enums, then custom types, each in the definition's order.
    public func files() throws -> [File] {
        guard language == .swift else {
            throw NomacError("intentbuilderc generate -language Objective-C is not reproduced yet (BACKLOG B-233)")
        }
        let files = definition.intents.filter { !$0.isSystem }.map(intentFile) + definition.enums.filter(\.generatesHeader).map(enumFile)
            + definition.types.map(typeFile)
        return visibility == "project" ? files.map { File(name: $0.name, contents: Self.internalAccess($0.contents)) } : files
    }

    /// `-visibility project` declares everything `internal` where the others say `public`
    /// (intents-experiments `swift-project`; `private` is `public`).
    static func internalAccess(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let code = line.drop { $0 == " " }
            guard !code.hasPrefix("//"), !code.hasPrefix("/*"), !code.hasPrefix("@abstract"), !code.hasPrefix("@discussion"),
                  !code.hasPrefix("@param"), !code.hasPrefix("@see") else { return String(line) }
            return line.replacingOccurrences(of: "public ", with: "internal ")
        }.joined(separator: "\n")
    }

    static let availability = "@available(iOS 12.0, macOS 11.0, watchOS 5.0, *) @available(tvOS, unavailable)"
    static let resultAvailability = "@available(iOS 13.0, macOS 11.0, watchOS 6.0, *) @available(tvOS, unavailable)"

    /// Placemark and Location parameters and properties also import CoreLocation.
    func header(_ name: String, parameters: [IntentDefinition.Parameter]) -> String {
        let location = parameters.contains { ["Placemark", "Location"].contains($0.type) && $0.enumType == nil }
        return """
            //
            // \(name).swift
            //
            // This file was automatically generated and should not be edited.
            //

            #if canImport(Intents)

            import Intents\(location ? "\nimport CoreLocation" : "")


            """
    }

    func className(of intent: IntentDefinition.Intent) -> String {
        intent.className ?? (classPrefix + intent.name + "Intent")
    }

    /// A parameter's Swift type. System object types are the framework's (`MediaItem` is
    /// `INMediaItem`); an enum without a header of its own is the intent's (`<Intent><Enum>`).
    func type(of parameter: IntentDefinition.Parameter, in intent: IntentDefinition.Intent? = nil) -> IntentSwiftType {
        let objectType = parameter.objectType.map { name in
            parameter.objectTypeNamespace == "System" ? "IN" + name : definition.types.first { $0.name == name }.map(typeName) ?? name
        }
        let enumType = parameter.enumType.map { name in
            guard let entry = definition.enums.first(where: { $0.name == name }) else { return name }
            if !entry.generatesHeader, let intent { return classPrefix + intent.name + entry.name }
            return enumName(entry)
        }
        return IntentSwiftType.of(parameter.type, objectType: objectType, enumType: enumType)
    }

    /// The enums without a header of their own that an intent's parameters use, declared
    /// deprecated in the intent's file (intents-experiments `enum-no-header`).
    func legacyEnums(_ intent: IntentDefinition.Intent) -> String {
        var text = ""
        var seen: Set<String> = []
        for parameter in intent.parameters {
            guard let name = parameter.enumType, !seen.contains(name),
                  let entry = definition.enums.first(where: { $0.name == name && !$0.generatesHeader }) else { continue }
            seen.insert(name)
            let legacy = classPrefix + intent.name + entry.name
            let current = enumName(entry)
            let message = "\(legacy) is deprecated. Please use \(current) instead. You can update this by tapping the warning icon next to this enum in the Intent Definition file"
            text += "@available(iOS, introduced: 12.0, deprecated: 12.0, message: \"\(message)\", renamed: \"\(current)\")\n"
            text += "@available(watchOS, introduced: 5.0, deprecated: 5.0, message: \"\(message)\", renamed: \"\(current)\")\n"
            text += "@objc public enum \(legacy): Int {\n"
            for value in entry.values {
                text += "    case `\(value.name)` = \(value.index)\n"
            }
            text += "}\n\n"
        }
        return text
    }

    func typeName(_ type: IntentDefinition.CustomType) -> String {
        type.className ?? (classPrefix + type.name)
    }

    func enumName(_ entry: IntentDefinition.Enumeration) -> String {
        entry.className ?? (classPrefix + entry.name)
    }

    static func capitalized(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: Intents

    func intentFile(_ intent: IntentDefinition.Intent) -> File {
        let name = className(of: intent)
        var text = header(name, parameters: intent.parameters + intent.responseParameters)
        text += legacyEnums(intent)
        text += "\(Self.availability)\n@objc(\(name))\npublic class \(name): INIntent {\n\n"
        text += properties(intent.parameters, in: intent)
        text += "}\n\n"
        text += handlingProtocol(intent, className: name)
        text += responseCodes(intent, className: name)
        text += response(intent, className: name)
        text += generatedResolutionResults(intent)
        text += "#endif\n"
        return File(name: name + ".swift", contents: text)
    }

    /// `@NSManaged` properties; one with an `@available` line is set apart by a blank line.
    func properties(_ parameters: [IntentDefinition.Parameter], in intent: IntentDefinition.Intent) -> String {
        var text = ""
        for (index, parameter) in parameters.enumerated() {
            let type = type(of: parameter, in: intent)
            if let availability = type.availability {
                if index > 0 { text += "\n" }
                text += "    \(availability)\n"
            }
            text += "    @NSManaged public var \(parameter.name): \(type.property(multiple: parameter.supportsMultipleValues))\n"
        }
        return text.isEmpty ? "" : text + "\n"
    }

    func handlingProtocol(_ intent: IntentDefinition.Intent, className name: String) -> String {
        let selectorName = intent.name
        var text = """
            /*!
             @abstract Protocol to declare support for handling a \(name). By implementing this protocol, a class can provide logic for resolving, confirming and handling the intent.
             @discussion The minimum requirement for an implementing class is that it should be able to handle the intent. The confirmation method is optional. The handling method is always called last, after confirming the intent.
             */
            \(Self.availability)
            @objc(\(name)Handling)
            public protocol \(name)Handling: NSObjectProtocol {


            """
        let handlingIsOptional = intent.eligibleForWidgets
        var blocks: [String] = []
        if !handlingIsOptional {
            blocks.append(handle(name, selectorName, optional: false))
        }
        if let resolution = resolutionMethods(intent, className: name) { blocks.append(resolution) }
        if let options = dynamicOptions(intent, className: name) { blocks.append(options) }
        blocks.append(confirm(name, selectorName))
        if handlingIsOptional {
            blocks.append(handle(name, selectorName, optional: true))
        }
        if let defaults = defaultValues(intent, className: name) { blocks.append(defaults) }
        if let deprecated = deprecatedOptions(intent, className: name) { blocks.append(deprecated) }
        text += blocks.joined(separator: "\n")
        return text + "\n}\n\n"
    }

    func handle(_ name: String, _ selectorName: String, optional: Bool) -> String {
        let doc = """
                /*!
                 @abstract Handling method - Execute the task represented by the \(name) that's passed in
                 @discussion Called to actually execute the intent. The app must return a response for this intent.

                 @param  intent The input intent
                 @param  completion The response handling block takes a \(name)Response containing the details of the result of having executed the intent

                 @see  \(name)Response
                 */

            """
        let prefix = optional ? "optional " : ""
        let completion = """
                @available(*, renamed: "handle(intent:)")
                @objc(handle\(selectorName):completion:)
                \(prefix)func handle(intent: \(name), completion: @escaping (\(name)Response) -> Swift.Void)
                \n
            """
        let async = """
                @available(iOS 13.0, macOS 11.0, watchOS 6.0, *)
                @objc(handle\(selectorName):completion:)
                \(prefix)func handle(intent: \(name)) async -> \(name)Response

            """
        return optional ? doc + completion + async : completion + doc + async
    }

    func confirm(_ name: String, _ selectorName: String) -> String {
        """
            @available(*, renamed: "confirm(intent:)")
            @objc(confirm\(selectorName):completion:)
            optional func confirm(intent: \(name), completion: @escaping (\(name)Response) -> Swift.Void)

            /*!
             @abstract Confirmation method - Validate that this intent is ready for the next step (i.e. handling)
             @discussion Called prior to asking the app to handle the intent. The app should return a response object that contains additional information about the intent, which may be relevant for the system to show the user prior to handling. If unimplemented, the system will assume the intent is valid, and will assume there is no additional information relevant to this intent.

             @param  intent The input intent
             @param  completion The response block contains a \(name)Response containing additional details about the intent that may be relevant for the system to show the user prior to handling.

             @see \(name)Response
             */
            @available(iOS 13.0, macOS 11.0, watchOS 6.0, *)
            @objc(confirm\(selectorName):completion:)
            optional func confirm(intent: \(name)) async -> \(name)Response

        """
    }

    func resolutionType(_ intent: IntentDefinition.Intent, _ parameter: IntentDefinition.Parameter) -> String {
        let type = type(of: parameter, in: intent)
        let single = type.generatedResolutionBase != nil
            ? classPrefix + intent.name + Self.capitalized(parameter.name) + "ResolutionResult" : type.resolution
        return parameter.supportsMultipleValues ? "[\(single)]" : single
    }

    func resolutionMethods(_ intent: IntentDefinition.Intent, className name: String) -> String? {
        let resolved = intent.parameters.filter(\.supportsResolution)
        guard !resolved.isEmpty else { return nil }
        var text = """
                /*!
                 @abstract Resolution methods - Determine if this intent is ready for the next step (confirmation)
                 @discussion Called to make sure the app extension is capable of handling this intent in its current form. This method is for validating if the intent needs any further fleshing out.

                 @param  intent The input intent
                 @param  completion The response block contains an INIntentResolutionResult for the parameter being resolved

                 @see INIntentResolutionResult
                 */

            """
        text += resolved.map { parameter in
            let method = "resolve" + Self.capitalized(parameter.name)
            let result = resolutionType(intent, parameter)
            return """
                    @available(iOS 13.0, macOS 11.0, watchOS 6.0, *)
                    @available(*, renamed: "\(method)(for:)")
                    @objc(\(method)For\(intent.name):withCompletion:)
                    func \(method)(for intent: \(name), with completion: @escaping (\(result)) -> Swift.Void)

                    @available(iOS 13.0, macOS 11.0, watchOS 6.0, *)
                    @objc(\(method)For\(intent.name):withCompletion:)
                    func \(method)(for intent: \(name)) async -> \(result)

                """
        }.joined(separator: "\n")
        return text
    }

    /// Parameters with dynamic options: those that say so, and payment methods that are
    /// configurable or resolved (intents-experiments `type-PaymentMethod-*`).
    func dynamic(_ intent: IntentDefinition.Intent) -> [IntentDefinition.Parameter] {
        intent.parameters.filter { parameter in
            parameter.supportsDynamicEnumeration
                || (parameter.type == "PaymentMethod" && (parameter.isConfigurable || parameter.supportsResolution))
        }
    }

    func dynamicOptions(_ intent: IntentDefinition.Intent, className name: String) -> String? {
        let parameters = dynamic(intent)
        guard !parameters.isEmpty else { return nil }
        let searching = parameters.contains(where: \.supportsSearch)
        var text = """
                /*!
                 @abstract Dynamic options methods - provide options for the parameter at runtime
                 @discussion Called to query dynamic options for the parameter and this intent in its current form.

                 @param  intent The input intent

            """
        if searching { text += "     @param  searchTerm The search term\n" }
        text += "     @param  completion The response block contains options for the parameter\n     */\n"
        let ordered = parameters.filter(\.supportsSearch) + parameters.filter { !$0.supportsSearch }
        text += ordered.map { parameter in
            let method = "provide" + Self.capitalized(parameter.name) + "OptionsCollection"
            let element = type(of: parameter, in: intent).collectionElement
            let search = parameter.supportsSearch
            let label = search ? "for:searchTerm:" : "for:"
            let selector = "\(method)For\(intent.name):\(search ? "searchTerm:" : "")withCompletion:"
            let arguments = "for intent: \(name)" + (search ? ", searchTerm: String?" : "")
            return """
                    @available(iOS 14.0, macOS 11.0, watchOS 7.0, *)
                    @available(*, renamed: "\(method)(\(label))")
                    @objc(\(selector))
                    func \(method)(\(arguments), with completion: @escaping (INObjectCollection<\(element)>?, Error?) -> Swift.Void)

                    @available(iOS 14.0, macOS 11.0, watchOS 7.0, *)
                    @objc(\(selector))
                    func \(method)(\(arguments)) async throws -> INObjectCollection<\(element)>

                """
        }.joined(separator: "\n")
        return text
    }

    func defaultValues(_ intent: IntentDefinition.Intent, className name: String) -> String? {
        let parameters = dynamic(intent)
        guard !parameters.isEmpty else { return nil }
        var text = """
                /*!
                 @abstract Default values for parameters with dynamic options
                 @discussion Called to query the parameter default value.
                 */

            """
        text += parameters.map { parameter in
            let method = "default" + Self.capitalized(parameter.name)
            return """
                    @available(iOS 14.0, macOS 11.0, watchOS 7.0, *)
                    @objc(\(method)For\(intent.name):)
                    optional func \(method)(for intent: \(name)) -> \(type(of: parameter, in: intent).defaultValue(multiple: parameter.supportsMultipleValues))

                """
        }.joined(separator: "\n")
        return text
    }

    func deprecatedOptions(_ intent: IntentDefinition.Intent, className name: String) -> String? {
        let parameters = dynamic(intent)
        guard !parameters.isEmpty else { return nil }
        var text = """
                /*!
                 @abstract Deprecated dynamic options methods.
                 */

            """
        text += parameters.map { parameter in
            let method = "provide" + Self.capitalized(parameter.name) + "Options"
            return """
                    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "")
                    @available(watchOS, introduced: 6.0, deprecated: 7.0, message: "")
                    @objc(\(method)For\(intent.name):withCompletion:)
                    optional func \(method)(for intent: \(name), with completion: @escaping ([\(type(of: parameter, in: intent).element)]?, Error?) -> Swift.Void)

                """
        }.joined(separator: "\n")
        return text
    }

    // MARK: Responses

    static let builtInCodes = ["unspecified", "ready", "continueInApp", "inProgress", "success", "failure", "failureRequiringAppLaunch"]

    func responseCodes(_ intent: IntentDefinition.Intent, className name: String) -> String {
        var text = """
            /*!
             @abstract Constants indicating the state of the response.
             */
            \(Self.availability)
            @objc public enum \(name)ResponseCode: Int {
                case unspecified = 0
                case ready
                case continueInApp
                case inProgress
                case success
                case failure
                case failureRequiringAppLaunch

            """
        let custom = intent.responseCodes.filter { !Self.builtInCodes.contains($0.name) }
        for (index, code) in custom.enumerated() {
            text += index == 0 ? "    case \(code.name) = 100\n" : "    case \(code.name)\n"
        }
        return text + "}\n\n"
    }

    /// The response parameters a code's format strings name, in order of first appearance.
    static func referencedParameters(_ code: IntentDefinition.ResponseCode, among parameters: [IntentDefinition.Parameter]) -> [IntentDefinition.Parameter] {
        var names: [String] = []
        for format in [code.formatString, code.conciseFormatString].compactMap({ $0 }) {
            var rest = Substring(format)
            while let start = rest.range(of: "${") {
                rest = rest[start.upperBound...]
                guard let end = rest.firstIndex(of: "}") else { break }
                let name = String(rest[..<end])
                if !names.contains(name) { names.append(name) }
                rest = rest[rest.index(after: end)...]
            }
        }
        return names.compactMap { name in parameters.first { $0.name == name } }
    }

    func response(_ intent: IntentDefinition.Intent, className name: String) -> String {
        var text = "\(Self.availability)\n@objc(\(name)Response)\npublic class \(name)Response: INIntentResponse {\n\n"
        text += properties(intent.responseParameters, in: intent)
        text += """
                /*!
                 @abstract The response code indicating your success or failure in confirming or handling the intent.
                 */
                @objc public fileprivate(set) var code: \(name)ResponseCode = .unspecified

                /*!
                 @abstract Initializes the response object with the specified code and user activity object.
                 @discussion The app extension has the option of capturing its private state as an NSUserActivity and returning it as the 'currentActivity'. If the app is launched, an NSUserActivity will be passed in with the private state. The NSUserActivity may also be used to query the app's UI extension (if provided) for a view controller representing the current intent handling state. In the case of app launch, the NSUserActivity will have its activityType set to the name of the intent. This intent object will also be available in the NSUserActivity.interaction property.

                 @param  code The response code indicating your success or failure in confirming or handling the intent.
                 @param  userActivity The user activity object to use when launching your app. Provide an object if you want to add information that is specific to your app. If you specify nil, the system automatically creates a user activity object for you, sets its type to the class name of the intent being handled, and fills it with an INInteraction object containing the intent and your response.
                 */
                @objc(initWithCode:userActivity:)
                public convenience init(code: \(name)ResponseCode, userActivity: NSUserActivity?) {
                    self.init()
                    self.code = code
                    self.userActivity = userActivity
                }


            """
        for code in intent.responseCodes {
            let parameters = Self.referencedParameters(code, among: intent.responseParameters)
            guard !parameters.isEmpty else { continue }
            let selector = code.name + "IntentResponseWith" + parameters.enumerated().map { index, parameter in
                (index == 0 ? Self.capitalized(parameter.name) : parameter.name) + ":"
            }.joined()
            let arguments = parameters.map { "\($0.name): \(argumentType($0, in: intent))" }.joined(separator: ", ")
            text += """
                    /*!
                     @abstract Initializes and returns the response object with the \(code.name) code.
                     */
                    @objc(\(selector))
                    public static func \(code.name)(\(arguments)) -> \(name)Response {
                        let intentResponse = \(name)Response(code: .\(code.name), userActivity: nil)

                """
            for parameter in parameters {
                text += "        intentResponse.\(parameter.name) = \(parameter.name)\n"
            }
            text += "        return intentResponse\n    }\n\n"
        }
        return text + "}\n\n"
    }

    func argumentType(_ parameter: IntentDefinition.Parameter, in intent: IntentDefinition.Intent) -> String {
        let type = type(of: parameter, in: intent)
        return parameter.supportsMultipleValues ? "[\(type.element)]" : type.single
    }

    func generatedResolutionResults(_ intent: IntentDefinition.Intent) -> String {
        var text = ""
        for parameter in intent.parameters where parameter.supportsResolution {
            let type = type(of: parameter, in: intent)
            guard let base = type.generatedResolutionBase else { continue }
            let name = classPrefix + intent.name + Self.capitalized(parameter.name)
            if !type.unsupportedReasons.isEmpty {
                text += "@available(iOS 13.0, macOS 11.0, watchOS 6.0, *)\n@objc public enum \(name)UnsupportedReason: Int {\n"
                for (index, reason) in type.unsupportedReasons.enumerated() {
                    text += index == 0 ? "    case \(reason) = 1\n" : "    case \(reason)\n"
                }
                text += "}\n\n"
            }
            text += """
                @available(iOS 13.0, macOS 11.0, watchOS 6.0, *)
                @objc(\(name)ResolutionResult)
                public class \(name)ResolutionResult: \(base) {
                    @objc(unsupportedForReason:)
                    public class func unsupported(forReason reason: \(name)UnsupportedReason) -> Self {
                        return __unsupported(withReason: reason.rawValue)
                    }
                }


                """
        }
        return text
    }

    // MARK: Custom types and enums

    func typeFile(_ type: IntentDefinition.CustomType) -> File {
        let name = typeName(type)
        let selectorName = type.name
        var text = header(name, parameters: type.properties)
        text += "\(Self.availability)\n@objc(\(name))\npublic class \(name): INObject {\n\n"
        let defaults: Set<String> = ["identifier", "displayString", "pronunciationHint", "alternativeSpeakableMatches"]
        for property in type.properties where !defaults.contains(property.name) {
            let propertyType = self.type(of: property)
            text += "    \(propertyType.availability ?? "@available(iOS 13.0, macOS 11.0, watchOS 6.0, *)")\n"
            text += "    @NSManaged public var \(property.name): \(propertyType.property(multiple: property.supportsMultipleValues))\n\n"
        }
        text += """
                override public class var supportsSecureCoding: Bool { true }

            }

            \(Self.resultAvailability)
            @objc(\(name)ResolutionResult)
            public class \(name)ResolutionResult: INObjectResolutionResult {

                // This resolution result is for when the app extension wants to tell Siri to proceed, with a given \(name). The resolvedValue can be different than the original \(name). This allows app extensions to apply business logic constraints.
                // Use notRequired() to continue with a 'nil' value.
                @objc(successWithResolved\(selectorName):)
                public class func success(with resolvedObject: \(name)) -> Self {
                    return super.success(with: resolvedObject)
                }

                // This resolution result is to ask Siri to disambiguate between the provided \(name).
                @objc(disambiguationWith\(selectorName)sToDisambiguate:)
                public class func disambiguation(with objectsToDisambiguate: [\(name)]) -> Self {
                    return super.disambiguation(with: objectsToDisambiguate)
                }

                // This resolution result is to ask Siri to confirm if this is the value with which the user wants to continue.
                @objc(confirmationRequiredWith\(selectorName)ToConfirm:)
                public class func confirmationRequired(with objectToConfirm: \(name)?) -> Self {
                    return super.confirmationRequired(with: objectToConfirm)
                }

                @available(*, unavailable)
                override public class func success(with resolvedObject: INObject) -> Self {
                    fatalError()
                }

                @available(*, unavailable)
                override public class func disambiguation(with objectsToDisambiguate: [INObject]) -> Self {
                    fatalError()
                }

                @available(*, unavailable)
                override public class func confirmationRequired(with objectToConfirm: INObject?) -> Self {
                    fatalError()
                }

            }

            #endif

            """
        return File(name: name + ".swift", contents: text)
    }

    func enumFile(_ entry: IntentDefinition.Enumeration) -> File {
        let name = enumName(entry)
        let selectorName = entry.name
        var text = header(name, parameters: [])
        text += "\(Self.availability)\n@objc public enum \(name): Int {\n"
        for value in entry.values {
            text += "    case `\(value.name)` = \(value.index)\n"
        }
        text += """
            }

            \(Self.resultAvailability)
            @objc(\(name)ResolutionResult)
            public class \(name)ResolutionResult: INEnumResolutionResult {

                // This resolution result is for when the app extension wants to tell Siri to proceed, with a given \(name). The resolvedValue can be different than the original \(name). This allows app extensions to apply business logic constraints.
                // Use notRequired() to continue with a 'nil' value.
                @objc(successWithResolved\(selectorName):)
                public class func success(with resolvedValue: \(name)) -> Self {
                    return __success(withResolvedValue: resolvedValue.rawValue)
                }

                // This resolution result is to ask Siri to confirm if this is the value with which the user wants to continue.
                @objc(confirmationRequiredWith\(selectorName)ToConfirm:)
                public class func confirmationRequired(with valueToConfirm: \(name)) -> Self {
                    return __confirmationRequiredWithValue(toConfirm: valueToConfirm.rawValue)
                }
            }

            #endif

            """
        return File(name: name + ".swift", contents: text)
    }
}
