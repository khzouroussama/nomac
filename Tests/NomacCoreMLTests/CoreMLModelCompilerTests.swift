import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacCoreML

/// `coremlc compile` for models stored as `spec` archives, as coreml-experiments observed it on
/// self-written models (docs/formats/coreml.md).
@Suite struct CoreMLModelCompilerTests {
    /// A GLM regressor of specification version 1: input `x`, a 3-element vector of doubles,
    /// output `y`, a double.
    static let regressor = bytes("0801121c0a0e0a01781a092a070a010310c0800452070a01791a0212005a0179e212260a1a0a18000000000000f03f000000000000004000000000000008401208000000000000e03f")
    /// An identity model of version 4 whose input `x` is a Float32 1 × 3 array whose first
    /// dimension ranges from 1 without bound.
    static let flexible = bytes("0804123a0a270a01781a222a200a02010310a08004fa01150a0d080110ffffffffffffffffff010a0408031003520f0a01791a0a2a080a02010310a08004a23800")

    static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { UInt8(hex.dropFirst($0).prefix(2), radix: 16)! }
    }

    func compile(_ model: [UInt8], name: String) throws -> CoreMLModelCompiler.Output {
        let directory = try TemporaryDirectory()
        let path = directory.path + "/\(name).mlmodel"
        try Data(model).write(to: URL(fileURLWithPath: path))
        return try CoreMLModelCompiler.compile(path)
    }

    @Test func archivesTheSpecificationWithAnEmptyMetadataMessage() throws {
        let output = try compile(Self.regressor, name: "GLM")
        let archive = try #require(output.files["coremldata.bin"])
        #expect(Array(archive.prefix(8)) == [0x2C, 0x01, 0, 0, 1, 0, 0, 0])
        #expect(Array(archive[0x1C..<0x28]) == [4, 0, 0, 0, 0, 0, 0, 0] + Array("spec".utf8))
        #expect(Array(archive[0x28..<0x2C]) == [1, 0, 0, 0])
        var expected = try ProtobufMessage(bytes: Self.regressor)
        var description = try #require(try expected.message(2))
        description.set(100, message: ProtobufMessage())
        expected.set(2, message: description)
        #expect(Array(archive.dropFirst(0x48)) == expected.bytes)
        #expect(archive.count == 0x48 + Self.regressor.count + 3)
    }

    @Test func analyticsHashTheInputFile() throws {
        let analytics = try #require(try compile(Self.regressor, name: "GLM").files["analytics/coremldata.bin"])
        let text = String(decoding: analytics.filter { $0 >= 0x20 }, as: UTF8.self)
        #expect(text == "SpecificationDetailsmodelHash,rQIJf2u1LsdrG1hmK1kQZTDVdnXz6h7PyiFbtsOLBb8=modelNameGLM")
        #expect(Array(analytics.prefix(8)) == [20, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func writesMetadataInFoundationOrder() throws {
        let metadata = try #require(try compile(Self.regressor, name: "GLM").files["metadata.json"])
        #expect(String(decoding: metadata, as: UTF8.self) == """
            [
              {
                "metadataOutputVersion" : "3.0",
                "outputSchema" : [
                  {
                    "isOptional" : "0",
                    "formattedType" : "Double",
                    "type" : "Double",
                    "name" : "y",
                    "shortDescription" : ""
                  }
                ],
                "modelParameters" : [

                ],
                "specificationVersion" : 1,
                "isUpdatable" : "0",
                "stateSchema" : [

                ],
                "availability" : {
                  "macOS" : "10.13",
                  "tvOS" : "11.0",
                  "visionOS" : "1.0",
                  "watchOS" : "4.0",
                  "iOS" : "11.0",
                  "macCatalyst" : "11.0"
                },
                "modelType" : {
                  "name" : "MLModelType_glmRegressor"
                },
                "userDefinedMetadata" : {

                },
                "inputSchema" : [
                  {
                    "hasShapeFlexibility" : "0",
                    "isOptional" : "0",
                    "dataType" : "Double",
                    "formattedType" : "MultiArray (Double 3)",
                    "shortDescription" : "",
                    "shape" : "[3]",
                    "name" : "x",
                    "type" : "MultiArray"
                  }
                ],
                "generatedClassName" : "GLM",
                "method" : "predict"
              }
            ]
            """)
    }

    /// A flexible multi-array's dictionary fills in another order than a fixed one.
    @Test func describesFlexibleShapes() throws {
        let metadata = try #require(try compile(Self.flexible, name: "Flexible").files["metadata.json"])
        let text = String(decoding: metadata, as: UTF8.self).split(separator: "\n")
        let start = try #require(text.firstIndex { $0.contains(#""inputSchema""#) }) + 2
        let lines = text[start...].prefix { $0 != "      }" }.map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines == [#""dataType" : "Float32","#, #""hasShapeFlexibility" : "1","#, #""isOptional" : "0","#,
                          #""shapeFlexibility" : "1... × 3","#, #""shapeRange" : "[[1, -1], [3, 3]]","#,
                          #""formattedType" : "MultiArray (Float32 1 × 3)","#, #""type" : "MultiArray","#, #""shape" : "[1, 3]","#,
                          #""name" : "x","#, #""shortDescription" : """#])
    }

    @Test func refusesTypesNotObserved() throws {
        var message = ProtobufMessage()
        message.fields.append(.init(number: 1, wireType: .varint, payload: [4]))
        message.set(500, message: ProtobufMessage())
        #expect(throws: (any Error).self) { try compile(message.bytes, name: "Network") }
        #expect(throws: (any Error).self) { try compile(Self.regressor, name: "My-Model") }
    }
}
