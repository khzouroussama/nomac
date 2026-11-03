import Foundation
import NomacCore

/// The Swift file `coremlc generate --language Swift` writes for a model: `<Name>Input`,
/// `<Name>Output` and `<Name>`, a template filled from the model's description, its declarations
/// marked available from the model's specification version and, when later, from the Core ML API
/// they use (coreml-experiments `metadata`, `types`, `validation`; docs/formats/coreml.md "What
/// generate writes").
public struct SwiftClassGenerator {
    let name: String
    let inputs: [ModelFeature]
    let outputs: [ModelFeature]
    let model: Availability
    /// Swift 6 writes `@preconcurrency import CoreML` and `any` before protocol types.
    let swift6: Bool
    let access: String

    /// The platform versions of an `@available` attribute.
    struct Availability: Comparable {
        var macOS: String, iOS: String, watchOS: String, visionOS: String

        var attribute: String {
            "@available(macOS \(macOS), iOS \(iOS), tvOS \(iOS), watchOS \(watchOS), visionOS \(visionOS), *)"
        }

        static func < (lhs: Availability, rhs: Availability) -> Bool {
            lhs.iOS.split(separator: ".").map { Int($0)! }.lexicographicallyPrecedes(rhs.iOS.split(separator: ".").map { Int($0)! })
        }

        /// What the Core ML API the classes use needs: configurations and batches, images from
        /// `CGImage` and URLs, completion handlers, shaped arrays and `async` loading, `async`
        /// prediction.
        static let configuration = Availability(macOS: "10.14", iOS: "12.0", watchOS: "5.0", visionOS: "1.0")
        static let images = Availability(macOS: "10.15", iOS: "13.0", watchOS: "6.0", visionOS: "1.0")
        static let completion = Availability(macOS: "11.0", iOS: "14.0", watchOS: "7.0", visionOS: "1.0")
        static let shapedArrays = Availability(macOS: "12.0", iOS: "15.0", watchOS: "8.0", visionOS: "1.0")
        static let asyncPrediction = Availability(macOS: "14.0", iOS: "17.0", watchOS: "10.0", visionOS: "1.0")
    }

    public init(path: String, swiftVersion: String, publicAccess: Bool) throws {
        let specification = try ModelSpecification.read(at: path)
        name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            throw NomacError("the class name coremlc derives from the file name \(name) is not observed yet (BACKLOG B-240)", path: path)
        }
        guard let platforms = CoreMLModelCompiler.availability[specification.specificationVersion] else {
            throw NomacError("the availability of specification version \(specification.specificationVersion) is not observed yet (BACKLOG B-240)", path: path)
        }
        model = Availability(macOS: platforms.macOS, iOS: platforms.iOS, watchOS: platforms.watchOS, visionOS: platforms.visionOS)
        let description = try specification.message.message(2) ?? ProtobufMessage()
        inputs = try description.messages(1).map(Self.feature)
        outputs = try description.messages(10).map(Self.feature)
        for feature in inputs + outputs {
            if case .image = feature.kind, feature.variable != feature.name, inputs.contains(feature) {
                throw NomacError("feature \(feature.name): the setters coremlc writes for an image input whose name it escapes are not observed yet (BACKLOG B-240)", path: path)
            }
            if case .sequence = feature.kind, feature.isOptional || outputs.contains(feature) {
                throw NomacError("feature \(feature.name): optional sequences and sequence outputs are not observed yet (BACKLOG B-240)", path: path)
            }
        }
        guard let major = Int(swiftVersion.split(separator: ".").first ?? ""), [5, 6].contains(major) else {
            throw NomacError("classes for Swift \(swiftVersion) are not observed yet (BACKLOG B-240)", path: path)
        }
        swift6 = major >= 6
        access = publicAccess ? "public " : ""
    }

    static func feature(_ message: ProtobufMessage) throws -> ModelFeature {
        var feature = try ModelFeature(message)
        feature.variable = try feature.swiftName()
        return feature
    }

    var any: String { swift6 ? "any " : "" }

    /// `@available` before a member that needs `needed`, when the model's own is older.
    func available(_ needed: Availability, indent: String = "    ") -> String {
        model < needed ? indent + needed.attribute + "\n" : ""
    }

    /// The inputs in the order initializers take them: required ones, then optional ones.
    var parameters: [ModelFeature] {
        inputs.filter { !$0.isOptional } + inputs.filter(\.isOptional)
    }

    public var file: (name: String, contents: String) {
        (name + ".swift", header + inputClass + "\n\n\n" + outputClass + "\n\n\n" + modelClass)
    }

    var header: String {
        """
        //
        // \(name).swift
        //
        // This file was automatically generated and should not be edited.
        //

        \(swift6 ? "@preconcurrency " : "")import CoreML



        """
    }

    var inputClass: String {
        var text = "/// Model Prediction Input Type\n\(model.attribute)\n\(access)class \(name)Input : MLFeatureProvider {\n\n"
        for feature in inputs {
            text += "    /// \(feature.comment)\n    \(access)var \(feature.variable): \(feature.swiftType)\(feature.isOptional ? "? = nil" : "")\n\n"
        }
        text += "    \(access)var featureNames: Set<String> { [\(inputs.map { "\"\($0.name)\"" }.joined(separator: ", "))] }\n\n"
        text += "    \(access)func featureValue(for featureName: String) -> MLFeatureValue? {\n"
        for feature in inputs {
            text += "        if featureName == \"\(feature.name)\" {\n            return \(feature.inputValue)\n        }\n"
        }
        text += "        return nil\n    }\n\n"
        text += "    \(access)init(\(parameters.map { "\($0.variable): \($0.swiftType)\($0.isOptional ? "? = nil" : "")" }.joined(separator: ", "))) {\n"
        text += parameters.map { "        self.\($0.variable) = \($0.variable)\n" }.joined()
        text += "    }\n\n"
        text += convenienceInitializers
        text += imageSetters
        return text + "}"
    }

    enum ImageSource { case buffer, cgImage, url }

    /// One initializer for each way to pass images (pixel buffers, `CGImage`s, URLs) and arrays
    /// (`MLMultiArray`, `MLShapedArray`), but the designated one.
    var convenienceInitializers: String {
        let arrays = inputs.contains { if case .multiArray = $0.kind { true } else { false } }
        let images = inputs.contains { if case .image = $0.kind { true } else { false } }
        var text = ""
        for source in [ImageSource.buffer, .cgImage, .url] where source == .buffer || images {
            for shaped in [false, true] where (source != .buffer || shaped) && (!shaped || arrays) {
                var needed = Availability(macOS: "0", iOS: "0", watchOS: "0", visionOS: "0")
                if source != .buffer { needed = max(needed, .images) }
                if shaped { needed = max(needed, .shapedArrays) }
                let declared = parameters.map { $0.convenienceParameter(source: source, shaped: shaped) }.joined(separator: ", ")
                let passed = parameters.map { "\($0.variable): \($0.convenienceArgument(source: source, shaped: shaped))" }.joined(separator: ", ")
                text += available(needed)
                text += "    \(access)convenience init(\(declared))\(source == .buffer ? "" : " throws") {\n        self.init(\(passed))\n    }\n\n"
            }
        }
        return text
    }

    var imageSetters: String {
        var text = ""
        for source in [ImageSource.cgImage, .url] {
            for feature in inputs {
                guard case .image = feature.kind else { continue }
                let setter = "set" + feature.variable.prefix(1).uppercased() + feature.variable.dropFirst()
                let type = source == .cgImage ? "CGImage" : "URL"
                text += available(.images)
                if feature.isOptional {
                    text += "    \(access)func \(setter)(with \(feature.variable): \(type)?) throws  {\n        if let _\(feature.variable) = \(feature.variable) {\n"
                    text += "                self.\(feature.variable) = \(feature.imageConversion(source: source, value: "_" + feature.variable))\n        }\n    }\n\n"
                } else {
                    text += "    \(access)func \(setter)(with \(feature.variable): \(type)) throws  {\n"
                    text += "        self.\(feature.variable) = \(feature.imageConversion(source: source, value: feature.variable))\n    }\n\n"
                }
            }
        }
        return text
    }

    var outputClass: String {
        var text = "/// Model Prediction Output Type\n\(model.attribute)\n\(access)class \(name)Output : MLFeatureProvider {\n\n"
        text += "    /// Source provided by CoreML\n    private let provider : \(any)MLFeatureProvider\n\n"
        for feature in outputs {
            text += "    /// \(feature.comment)\n    \(access)var \(feature.variable): \(feature.swiftType) {\n"
            text += "        provider.featureValue(for: \"\(feature.name)\")!.\(feature.outputAccessor)\n    }\n\n"
            if case .multiArray = feature.kind {
                let shaped = "MLShapedArray<\(feature.elementType)>"
                text += "    /// \(feature.comment)\n" + available(.shapedArrays)
                text += "    \(access)var \(feature.variable)ShapedArray: \(shaped) {\n        \(shaped)(\(feature.variable))\n    }\n\n"
            }
        }
        text += "    \(access)var featureNames: Set<String> {\n        provider.featureNames\n    }\n\n"
        text += "    \(access)func featureValue(for featureName: String) -> MLFeatureValue? {\n        provider.featureValue(for: featureName)\n    }\n\n"
        text += "    \(access)init(\(outputs.map { "\($0.variable): \($0.swiftType)" }.joined(separator: ", "))) {\n"
        text += "        self.provider = try! MLDictionaryFeatureProvider(dictionary: [\(outputs.map { "\"\($0.name)\" : \($0.outputValue)" }.joined(separator: ", "))])\n    }\n\n"
        text += "    \(access)init(features: \(any)MLFeatureProvider) {\n        self.provider = features\n    }\n}"
        return text
    }

    var modelClass: String {
        let result = "Swift.Result<\(name), \(any)Error>"
        var text = """
            /// Class for model loading and prediction
            \(model.attribute)
            \(access)class \(name) {
                \(access)let model: MLModel

                /// URL of model assuming it was installed in the same bundle as this class
                class var urlOfModelInThisBundle : URL {
                    let bundle = Bundle(for: self)
                    return bundle.url(forResource: "\(name)", withExtension:"mlmodelc")!
                }

                /**
                    Construct \(name) instance with an existing MLModel object.

                    Usually the application does not use this initializer unless it makes a subclass of \(name).
                    Such application may want to use `MLModel(contentsOfURL:configuration:)` and `\(name).urlOfModelInThisBundle` to create a MLModel object to pass-in.

                    - parameters:
                      - model: MLModel object
                */
                init(model: MLModel) {
                    self.model = model
                }


            """
        if model < .completion {
            text += """
                    /**
                        Construct \(name) instance by automatically loading the model from the app's bundle.
                    */
                    @available(*, deprecated, message: "Use init(configuration:) instead and handle errors appropriately.")
                    \(access)convenience init() {
                        try! self.init(contentsOf: type(of:self).urlOfModelInThisBundle)
                    }


                """
        }
        text += """
                /**
                    Construct a model with configuration

                    - parameters:
                       - configuration: the desired model configuration

                    - throws: an NSError object that describes the problem
                */

            """
        text += available(.configuration)
        text += """
                \(access)convenience init(configuration: MLModelConfiguration\(model < .completion ? "" : " = MLModelConfiguration()")) throws {
                    try self.init(contentsOf: type(of:self).urlOfModelInThisBundle, configuration: configuration)
                }

                /**
                    Construct \(name) instance with explicit path to mlmodelc file
                    - parameters:
                       - modelURL: the file url of the model

                    - throws: an NSError object that describes the problem
                */
                \(access)convenience init(contentsOf modelURL: URL) throws {
                    try self.init(model: MLModel(contentsOf: modelURL))
                }

                /**
                    Construct a model with URL of the .mlmodelc directory and configuration

                    - parameters:
                       - modelURL: the file url of the model
                       - configuration: the desired model configuration

                    - throws: an NSError object that describes the problem
                */

            """
        text += available(.configuration)
        text += """
                \(access)convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
                    try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
                }

                /**
                    Construct \(name) instance asynchronously with optional configuration.

                    Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

                    - parameters:
                      - configuration: the desired model configuration
                      - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
                */

            """
        text += available(.completion)
        text += """
                \(access)class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (\(result)) -> Void) {
                    load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
                }

                /**
                    Construct \(name) instance asynchronously with optional configuration.

                    Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

                    - parameters:
                      - configuration: the desired model configuration
                */

            """
        text += available(.shapedArrays)
        text += """
                \(access)class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> \(name) {
                    try await load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
                }

                /**
                    Construct \(name) instance asynchronously with URL of the .mlmodelc directory with optional configuration.

                    Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

                    - parameters:
                      - modelURL: the URL to the model
                      - configuration: the desired model configuration
                      - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
                */

            """
        text += available(.completion)
        text += """
                \(access)class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (\(result)) -> Void) {
                    MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
                        switch result {
                        case .failure(let error):
                            handler(.failure(error))
                        case .success(let model):
                            handler(.success(\(name)(model: model)))
                        }
                    }
                }

                /**
                    Construct \(name) instance asynchronously with URL of the .mlmodelc directory with optional configuration.

                    Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

                    - parameters:
                      - modelURL: the URL to the model
                      - configuration: the desired model configuration
                */

            """
        text += available(.shapedArrays)
        text += """
                \(access)class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> \(name) {
                    let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
                    return \(name)(model: model)
                }

                /**
                    Make a prediction using the structured interface

                    It uses the default function if the model has multiple functions.

                    - parameters:
                       - input: the input to the prediction as \(name)Input

                    - throws: an NSError object that describes the problem

                    - returns: the result of the prediction as \(name)Output
                */
                \(access)func prediction(input: \(name)Input) throws -> \(name)Output {
                    try prediction(input: input, options: MLPredictionOptions())
                }

                /**
                    Make a prediction using the structured interface

                    It uses the default function if the model has multiple functions.

                    - parameters:
                       - input: the input to the prediction as \(name)Input
                       - options: prediction options

                    - throws: an NSError object that describes the problem

                    - returns: the result of the prediction as \(name)Output
                */
                \(access)func prediction(input: \(name)Input, options: MLPredictionOptions) throws -> \(name)Output {
                    let outFeatures = try model.prediction(from: input, options: options)
                    return \(name)Output(features: outFeatures)
                }

                /**
                    Make an asynchronous prediction using the structured interface

                    It uses the default function if the model has multiple functions.

                    - parameters:
                       - input: the input to the prediction as \(name)Input
                       - options: prediction options

                    - throws: an NSError object that describes the problem

                    - returns: the result of the prediction as \(name)Output
                */

            """
        text += available(.asyncPrediction)
        text += """
                \(access)func prediction(input: \(name)Input, options: MLPredictionOptions = MLPredictionOptions()) async throws -> \(name)Output {
                    let outFeatures = try await model.prediction(from: input, options: options)
                    return \(name)Output(features: outFeatures)
                }


            """
        let arrays = inputs.contains { if case .multiArray = $0.kind { true } else { false } }
        for shaped in [false, true] where !shaped || arrays {
            text += """
                    /**
                        Make a prediction using the convenience interface

                        It uses the default function if the model has multiple functions.

                        - parameters:

                """
            text += parameters.map { "            - \($0.variable): \($0.parameterDocumentation)\n" }.joined()
            text += """

                        - throws: an NSError object that describes the problem

                        - returns: the result of the prediction as \(name)Output
                    */

                """
            if shaped {
                text += "\n" + available(.shapedArrays)
            }
            let declared = parameters.map { "\($0.variable): \(shaped ? $0.shapedType : $0.swiftType)\($0.isOptional ? "?" : "")" }.joined(separator: ", ")
            text += """
                    \(access)func prediction(\(declared)) throws -> \(name)Output {
                        let input_ = \(name)Input(\(parameters.map { "\($0.variable): \($0.variable)" }.joined(separator: ", ")))
                        return try prediction(input: input_)
                    }


                """
        }
        text += """
                /**
                    Make a batch prediction using the structured interface

                    It uses the default function if the model has multiple functions.

                    - parameters:
                       - inputs: the inputs to the prediction as [\(name)Input]
                       - options: prediction options

                    - throws: an NSError object that describes the problem

                    - returns: the result of the prediction as [\(name)Output]
                */

            """
        text += available(.configuration)
        text += """
                \(access)func predictions(inputs: [\(name)Input], options: MLPredictionOptions = MLPredictionOptions()) throws -> [\(name)Output] {
                    let batchIn = MLArrayBatchProvider(array: inputs)
                    let batchOut = try model.predictions(from: batchIn, options: options)
                    var results : [\(name)Output] = []
                    results.reserveCapacity(inputs.count)
                    for i in 0..<batchOut.count {
                        let outProvider = batchOut.features(at: i)
                        let result =  \(name)Output(features: outProvider)
                        results.append(result)
                    }
                    return results
                }
            }

            """
        return text
    }
}

extension ModelFeature {
    /// The words coremlc escapes with a trailing `_` in feature names (coreml-experiments `names`,
    /// 155 names: Swift's keywords but those added since Swift 5, Objective-C's and C's; not C++'s
    /// or the classes' own members, but `input_`, the convenience predictions' local).
    static let reservedNames: Set<String> = [
        "BOOL", "Class", "IMP", "NO", "NULL", "Protocol", "SEL", "Self", "Type", "YES", "as", "auto", "break", "bycopy", "byref", "case",
        "char", "class", "const", "continue", "convenience", "default", "deinit", "didSet", "do", "double", "dynamic", "else", "enum",
        "extension", "extern", "fallthrough", "false", "final", "float", "for", "func", "get", "goto", "id", "if", "import", "in", "init",
        "inout", "input_", "int", "internal", "is", "lazy", "left", "let", "long", "mutating", "nil", "none", "nonmutating", "oneway",
        "operator", "optional", "out", "override", "postfix", "prefix", "private", "protocol", "public", "register", "required",
        "restrict", "return", "right", "self", "set", "short", "signed", "sizeof", "static", "struct", "subscript", "super", "switch",
        "true", "typealias", "typedef", "union", "unowned", "unsigned", "var", "void", "volatile", "weak", "where", "while",
    ]

    /// The name of the feature's property and parameters: characters other than ASCII letters,
    /// digits and `_` become `_`, a leading digit gets a `_` before it, a reserved word one after.
    func swiftName() throws -> String {
        guard name.unicodeScalars.allSatisfy(\.isASCII), !name.isEmpty else {
            throw NomacError("feature \(name): the property name coremlc derives from a name outside ASCII is not observed yet (BACKLOG B-240)")
        }
        var text = String(name.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : "_" })
        if text.first!.isNumber { text = "_" + text }
        return Self.reservedNames.contains(text) ? text + "_" : text
    }

    /// The feature's type as the classes' comments describe it.
    var phrase: String {
        let text: String
        switch kind {
        case .double: text = "double value"
        case .int64: text = "integer value"
        case .string: text = "string value"
        case .dictionary(let keyType): text = "dictionary of \(keyType == "String" ? "strings" : "64-bit integers") to doubles"
        case .multiArray(let dataType, let shape, _):
            let elements = ["Double": "doubles", "Float32": "floats", "Int32": "32-bit integers"][dataType]!
            switch shape.count {
            case 0: text = "multidimensional array of \(elements)"
            case 1: text = "\(shape[0]) element vector of \(elements)"
            case 2: text = "\(shape[0]) by \(shape[1]) matrix of \(elements)"
            default: text = "\(shape.map(String.init).joined(separator: " × ")) \(shape.count)-dimensional array of \(elements)"
            }
        case .image(let width, let height, let colorSpace, _):
            text = (colorSpace == "RGB" ? "color (kCVPixelFormatType_32BGRA)" : "grayscale (kCVPixelFormatType_OneComponent8)")
                + " image buffer, \(width) pixels wide by \(height) pixels high"
        case .sequence(let valueType, _): text = "sequence of \(valueType == "String" ? "strings" : "64-bit integers")"
        }
        return (isOptional ? "optional " : "") + text
    }

    /// `<description or name> as <phrase>`.
    var comment: String {
        "\(shortDescription.isEmpty ? name : shortDescription) as \(phrase)"
    }

    var parameterDocumentation: String {
        shortDescription.isEmpty ? phrase : "\(shortDescription) as \(phrase)"
    }

    var swiftType: String {
        switch kind {
        case .double: "Double"
        case .int64: "Int64"
        case .string: "String"
        case .dictionary(let keyType): "[\(keyType) : Double]"
        case .multiArray: "MLMultiArray"
        case .image: "CVPixelBuffer"
        case .sequence(let valueType, _): "[\(valueType)]"
        }
    }

    var elementType: String {
        guard case .multiArray(let dataType, _, _) = kind else { return "" }
        return ["Double": "Double", "Float32": "Float", "Int32": "Int32"][dataType]!
    }

    var shapedType: String {
        if case .multiArray = kind { "MLShapedArray<\(elementType)>" } else { swiftType }
    }

    /// The `MLFeatureValue` an input returns; an optional one returns `nil` when unset.
    var inputValue: String {
        let value = isOptional ? variable + "!" : variable
        let expression: String
        switch kind {
        case .double: expression = "MLFeatureValue(double: \(value))"
        case .int64: expression = "MLFeatureValue(int64: \(value))"
        case .string: expression = "MLFeatureValue(string: \(value))"
        case .dictionary:
            return (isOptional ? "try! \(variable) == nil ? nil : " : "try! ") + "MLFeatureValue(dictionary: \(value) as [NSObject : NSNumber])"
        case .multiArray: expression = "MLFeatureValue(multiArray: \(value))"
        case .image: expression = "MLFeatureValue(pixelBuffer: \(value))"
        case .sequence(let valueType, _):
            expression = valueType == "String" ? "MLFeatureValue(sequence: MLSequence(strings: \(value)))"
                : "MLFeatureValue(sequence: MLSequence(int64s: \(value) as [NSNumber]))"
        }
        return isOptional ? "\(variable) == nil ? nil : \(expression)" : expression
    }

    var outputAccessor: String {
        switch kind {
        case .double: "doubleValue"
        case .int64: "int64Value"
        case .string: "stringValue"
        case .dictionary: "dictionaryValue as! \(swiftType)"
        case .multiArray: "multiArrayValue!"
        case .image: "imageBufferValue!"
        case .sequence: "sequenceValue!"
        }
    }

    var outputValue: String {
        switch kind {
        case .double: "MLFeatureValue(double: \(variable))"
        case .int64: "MLFeatureValue(int64: \(variable))"
        case .string: "MLFeatureValue(string: \(variable))"
        case .dictionary: "MLFeatureValue(dictionary: \(variable) as [AnyHashable : NSNumber])"
        case .multiArray: "MLFeatureValue(multiArray: \(variable))"
        case .image: "MLFeatureValue(pixelBuffer: \(variable))"
        case .sequence: "MLFeatureValue(sequence: \(variable))"
        }
    }

    func imageConversion(source: SwiftClassGenerator.ImageSource, value: String) -> String {
        guard case .image(let width, let height, let colorSpace, _) = kind else { return value }
        let format = colorSpace == "RGB" ? "kCVPixelFormatType_32ARGB" : "kCVPixelFormatType_OneComponent8"
        let initializer = source == .url ? "imageAt" : "cgImage"
        return "try MLFeatureValue(\(initializer): \(value), pixelsWide: \(width), pixelsHigh: \(height), pixelFormatType: \(format), options: nil).imageBufferValue!"
    }

    func convenienceParameter(source: SwiftClassGenerator.ImageSource, shaped: Bool) -> String {
        let suffix = isOptional ? "? = nil" : ""
        switch kind {
        case .image where source != .buffer:
            let label = source == .url ? "At" : isOptional ? "From" : "With"
            return "\(variable)\(label) \(variable): \(source == .url ? "URL" : "CGImage")\(suffix)"
        case .multiArray where shaped:
            return "\(variable): \(shapedType)\(suffix)"
        default:
            return "\(variable): \(swiftType)\(suffix)"
        }
    }

    func convenienceArgument(source: SwiftClassGenerator.ImageSource, shaped: Bool) -> String {
        switch kind {
        case .image where source != .buffer:
            let conversion = imageConversion(source: source, value: variable)
            return isOptional ? "try { ()->CVPixelBuffer? in if let \(variable) = \(variable) { return \(conversion) } else { return nil } }()" : conversion
        case .multiArray where shaped:
            return isOptional ? "\(variable) != nil ? MLMultiArray(\(variable)!) : nil" : "MLMultiArray(\(variable))"
        default:
            return variable
        }
    }
}
