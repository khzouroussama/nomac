import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacCoreML

/// `coremlc generate --language Swift`, as coreml-experiments observed it on self-written models.
@Suite struct SwiftClassGeneratorTests {
    /// An identity model of version 1: an optional image input `photo` and an output `y`, both
    /// 64 × 32 color images.
    static func model() -> [UInt8] {
        var image = ProtobufMessage()
        image.fields += [.init(number: 1, wireType: .varint, payload: [64]), .init(number: 2, wireType: .varint, payload: [32]),
                         .init(number: 3, wireType: .varint, payload: [20])]
        func feature(_ name: String, optional: Bool) -> ProtobufMessage {
            var type = ProtobufMessage()
            type.set(4, message: image)
            if optional { type.fields.append(.init(number: 1000, wireType: .varint, payload: [1])) }
            var feature = ProtobufMessage(fields: [.init(number: 1, wireType: .lengthDelimited, payload: Array(name.utf8))])
            feature.set(3, message: type)
            return feature
        }
        var description = ProtobufMessage()
        description.fields.append(.init(number: 1, wireType: .lengthDelimited, payload: feature("photo", optional: true).bytes))
        description.fields.append(.init(number: 10, wireType: .lengthDelimited, payload: feature("y", optional: false).bytes))
        var model = ProtobufMessage(fields: [.init(number: 1, wireType: .varint, payload: [1])])
        model.set(2, message: description)
        model.set(900, message: ProtobufMessage())
        return model.bytes
    }

    func generate(swiftVersion: String = "6.0", publicAccess: Bool = false) throws -> String {
        let directory = try TemporaryDirectory()
        let path = directory.path + "/Pictures.mlmodel"
        try Data(Self.model()).write(to: URL(fileURLWithPath: path))
        let file = try SwiftClassGenerator(path: path, swiftVersion: swiftVersion, publicAccess: publicAccess).file
        #expect(file.name == "Pictures.swift")
        return file.contents
    }

    /// An optional image gets optional convenience initializers and setters, marked available
    /// from iOS 13, later than the model's iOS 11.
    @Test func annotatesNewerAPI() throws {
        let text = try generate()
        #expect(text.hasPrefix("//\n// Pictures.swift\n//\n// This file was automatically generated and should not be edited.\n//\n\n@preconcurrency import CoreML\n\n\n/// Model Prediction Input Type\n"))
        #expect(text.contains("    /// photo as optional color (kCVPixelFormatType_32BGRA) image buffer, 64 pixels wide by 32 pixels high\n    var photo: CVPixelBuffer? = nil\n"))
        #expect(text.contains("    var featureNames: Set<String> { [\"photo\"] }\n"))
        #expect(text.contains("""
                @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
                convenience init(photoFrom photo: CGImage? = nil) throws {
            """))
        #expect(text.contains("""
                func setPhoto(with photo: URL?) throws  {
                    if let _photo = photo {
                            self.photo = try MLFeatureValue(imageAt: _photo, pixelsWide: 64, pixelsHigh: 32, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
                    }
                }
            """))
        #expect(text.contains("@available(*, deprecated, message: \"Use init(configuration:) instead and handle errors appropriately.\")"))
        #expect(text.hasSuffix("        return results\n    }\n}\n"))
    }

    /// Swift 5 writes no `any` and no `@preconcurrency`; public access leaves `init(model:)` and
    /// the bundle URL internal.
    @Test func swift5AndPublicAccess() throws {
        let text = try generate(swiftVersion: "5.0", publicAccess: true)
        #expect(text.contains("\nimport CoreML\n"))
        #expect(!text.contains("any "))
        #expect(text.contains("    public init(features: MLFeatureProvider) {\n"))
        #expect(text.contains("    init(model: MLModel) {\n"))
        #expect(text.contains("    class var urlOfModelInThisBundle : URL {\n"))
        #expect(text.contains("public class Pictures {\n"))
    }

    /// Reserved words get `_` after them in the property's name, other characters than letters,
    /// digits and `_` become `_`, a leading digit gets `_` before it.
    @Test func escapesNames() throws {
        for (name, expected) in [("x y", "x_y"), ("1x", "_1x"), ("x.y", "x_y"), ("input_", "input__"), ("model", "model"), ("async", "async"),
                                 ("in", "in_"), ("out", "out_"), ("double", "double_")] {
            var feature = try ModelFeature(ProtobufMessage(fields: [.init(number: 1, wireType: .lengthDelimited, payload: Array(name.utf8)),
                                                                    .init(number: 3, wireType: .lengthDelimited, payload: [0x12, 0x00])]))
            feature.variable = try feature.swiftName()
            #expect(feature.variable == expected)
        }
    }
}
