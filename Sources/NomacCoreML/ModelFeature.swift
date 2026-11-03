import Foundation
import NomacCore

/// A feature of a model's description (`FeatureDescription` and `FeatureType` in coremltools'
/// `FeatureTypes.proto`), with what coremlc writes for it in `metadata.json`.
public struct ModelFeature: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case int64, double, string
        case dictionary(keyType: String)
        case multiArray(dataType: String, shape: [Int64], flexibility: Flexibility?)
        case image(width: Int64, height: Int64, colorSpace: String, flexibility: Flexibility?)
        case sequence(valueType: String, range: SizeRange)
    }

    public struct SizeRange: Sendable, Equatable {
        public var lower: Int64
        public var upper: Int64
    }

    /// Sizes a multi-array or an image accepts besides its default: ranges per dimension, or a
    /// list of shapes.
    public enum Flexibility: Sendable, Equatable {
        case ranges([SizeRange])
        case enumerated([[Int64]])
    }

    public var name: String
    /// The name of the feature's property in generated classes (`SwiftClassGenerator`).
    public var variable: String
    public var shortDescription: String
    public var isOptional: Bool
    public var kind: Kind

    /// The array data types and color spaces observed (coreml-experiments `metadata`); FLOAT16 and
    /// INT8 arrays need specification version 7, BGR and half-float grayscale are not observed.
    static let dataTypes: [Int64: String] = [65568: "Float32", 65600: "Double", 131104: "Int32"]
    static let colorSpaces: [Int64: String] = [10: "Grayscale", 20: "RGB"]

    public init(_ message: ProtobufMessage) throws {
        name = message.string(1) ?? ""
        variable = name
        shortDescription = message.string(2) ?? ""
        let type = try message.message(3) ?? ProtobufMessage()
        isOptional = try type.integer(1000) != 0
        if type.has(1) {
            kind = .int64
        } else if type.has(2) {
            kind = .double
        } else if type.has(3) {
            kind = .string
        } else if let dictionary = try type.message(6) {
            kind = .dictionary(keyType: dictionary.has(2) ? "String" : "Int64")
        } else if let array = try type.message(5) {
            let code = try array.integer(2)
            guard let dataType = Self.dataTypes[code] else { throw Self.unobserved("multi-array data type \(code)", name) }
            let shape = try array.integers(1)
            kind = .multiArray(dataType: dataType, shape: shape, flexibility: try Self.flexibility(array))
        } else if let image = try type.message(4) {
            let code = try image.integer(3)
            guard let colorSpace = Self.colorSpaces[code] else { throw Self.unobserved("image color space \(code)", name) }
            var flexibility: Flexibility?
            if let sizes = try image.message(21) {
                flexibility = .enumerated(try sizes.messages(1).map { [try $0.integer(1), try $0.integer(2)] })
            } else if let range = try image.message(31) {
                flexibility = .ranges([try Self.range(try range.message(1)), try Self.range(try range.message(2))])
            }
            kind = .image(width: try image.integer(1), height: try image.integer(2), colorSpace: colorSpace, flexibility: flexibility)
        } else if let sequence = try type.message(7) {
            kind = .sequence(valueType: sequence.has(3) ? "String" : "Int64", range: try Self.range(try sequence.message(101)))
        } else {
            throw Self.unobserved("feature type", name)
        }
    }

    static func flexibility(_ array: ProtobufMessage) throws -> Flexibility? {
        if let shapes = try array.message(21) {
            return .enumerated(try shapes.messages(1).map { try $0.integers(1) })
        }
        if let range = try array.message(31) {
            return .ranges(try range.messages(1).map { try Self.range($0) })
        }
        return nil
    }

    static func range(_ message: ProtobufMessage?) throws -> SizeRange {
        SizeRange(lower: try message?.integer(1) ?? 0, upper: try message?.integer(2) ?? 0)
    }

    static func unobserved(_ what: String, _ feature: String) -> NomacError {
        NomacError("feature \(feature): what coremlc writes for a \(what) is not observed yet (BACKLOG B-240)")
    }

    /// `metadata.json`'s entry for the feature: its keys in the order of the dictionary coremlc
    /// writes, a mutable Foundation table filled in the insertion order fitted to every observed
    /// feature dictionary, then copied (coreml-experiments `metadata`). A multi-array of fixed
    /// shape fills its dictionary in another order than a flexible one: no one order fits both.
    func metadata() throws -> FoundationJSON {
        var values: [String: FoundationJSON] = ["name": .string(name), "shortDescription": .string(shortDescription),
                                                "isOptional": .string(isOptional ? "1" : "0")]
        let formatted: String
        var order = Self.insertionOrder
        switch kind {
        case .int64, .double, .string:
            let type = kind == .int64 ? "Int64" : kind == .double ? "Double" : "String"
            values["type"] = .string(type)
            formatted = type
        case .dictionary(let keyType):
            values["type"] = .string("Dictionary")
            values["keyType"] = .string(keyType)
            formatted = "Dictionary (\(keyType) → Double)"
        case .multiArray(let dataType, let shape, let flexibility):
            values["type"] = .string("MultiArray")
            values["dataType"] = .string(dataType)
            values["shape"] = .string(Self.list(shape))
            values["hasShapeFlexibility"] = .string(flexibility == nil ? "0" : "1")
            switch flexibility {
            case .ranges(let ranges):
                values["shapeFlexibility"] = .string(ranges.map(Self.text).joined(separator: " × "))
                values["shapeRange"] = .string("[" + ranges.map { Self.list([$0.lower, $0.upper]) }.joined(separator: ", ") + "]")
            case .enumerated(let shapes):
                values["shapeFlexibility"] = .string(shapes.map { $0.map(String.init).joined(separator: " × ") }.joined(separator: " | "))
                values["enumeratedShapes"] = .string("[" + shapes.map(Self.list).joined(separator: ", ") + "]")
            case nil:
                order = Self.fixedArrayInsertionOrder
            }
            formatted = shape.isEmpty ? "MultiArray (\(dataType))" : "MultiArray (\(dataType) \(shape.map(String.init).joined(separator: " × ")))"
        case .image(let width, let height, let colorSpace, let flexibility):
            values["type"] = .string("Image")
            values["width"] = .string(String(width))
            values["height"] = .string(String(height))
            values["colorspace"] = .string(colorSpace)
            values["isColor"] = .string(colorSpace == "RGB" ? "1" : "0")
            values["hasSizeFlexibility"] = .string(flexibility == nil ? "0" : "1")
            switch flexibility {
            case .ranges(let ranges):
                values["sizeFlexibility"] = .string(ranges.map(Self.text).joined(separator: " × "))
                values["sizeRange"] = .string("[" + ranges.map { Self.list([$0.lower, $0.upper]) }.joined(separator: ", ") + "]")
            case .enumerated(let sizes):
                values["sizeFlexibility"] = .string(sizes.map { $0.map(String.init).joined(separator: " × ") }.joined(separator: " | "))
                values["enumeratedSizes"] = .string("[" + sizes.map(Self.list).joined(separator: ", ") + "]")
            case nil:
                break
            }
            formatted = "Image (\(colorSpace == "RGB" ? "Color" : colorSpace) \(width) × \(height))"
        case .sequence(let valueType, let range):
            values["type"] = .string("Sequence")
            values["valueType"] = .string(valueType)
            values["sizeRange"] = .string(Self.list([range.lower, range.upper]))
            formatted = "Sequence (\(valueType) \(range.lower)...\(range.upper))"
        }
        values["formattedType"] = .string(formatted + (isOptional ? "?" : ""))
        return try MetadataWriter.object(values, insertionOrder: order)
    }

    static func list(_ values: [Int64]) -> String {
        "[" + values.map(String.init).joined(separator: ", ") + "]"
    }

    /// A dimension's range as coremlc prints it: `3` when fixed, `1...` without an upper bound
    /// (`-1`), `32...128` otherwise.
    static func text(_ range: SizeRange) -> String {
        range.lower == range.upper ? String(range.lower) : range.upper < 0 ? "\(range.lower)..." : "\(range.lower)...\(range.upper)"
    }

    static let insertionOrder = ["sizeRange", "enumeratedShapes", "shapeRange", "hasSizeFlexibility", "sizeFlexibility", "shape", "type",
                                 "enumeratedSizes", "valueType", "width", "shapeFlexibility", "keyType", "name", "hasShapeFlexibility",
                                 "dataType", "isColor", "colorspace", "isOptional", "shortDescription", "formattedType", "height"]
    static let fixedArrayInsertionOrder = ["shape", "name", "type", "hasShapeFlexibility", "isOptional", "dataType", "shortDescription",
                                           "formattedType"]
}
