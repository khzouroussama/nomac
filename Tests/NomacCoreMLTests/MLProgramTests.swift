import NomacCore
import Testing
@testable import NomacCoreML

/// What coremlc writes for ML programs, as coreml-experiments `programs` and `opsets` observed it.
@Suite struct MLProgramTests {
    @Test func printsNumbersAsHexadecimalFloats() {
        #expect(MILText.hexFloat(0) == "0x0p+0")
        #expect(MILText.hexFloat(1) == "0x1p+0")
        #expect(MILText.hexFloat(0.5) == "0x1p-1")
        #expect(MILText.hexFloat(3) == "0x1.8p+1")
        #expect(MILText.hexFloat(5) == "0x1.4p+2")
        #expect(MILText.hexFloat(-2) == "-0x1p+1")
        #expect(MILText.hexFloat(Double(Float(0.1))) == "0x1.99999ap-4")
    }

    /// Operations are counted under the opset of their last revision; iOS 15 ones by type.
    @Test func namesOperationsByTheirRevision() {
        #expect(MILOperations.histogramName("slice_by_index", opset: "CoreML6") == "SliceByIndex")
        #expect(MILOperations.histogramName("relu", opset: "CoreML7") == "Ios16.relu")
        #expect(MILOperations.histogramName("max_pool", opset: "CoreML7") == "Ios16.maxPool")
        #expect(MILOperations.histogramName("conv", opset: "CoreML7") == "Ios17.conv")
        #expect(MILOperations.histogramName("reduce_sum", opset: "CoreML8") == "Ios16.reduceSum")
        #expect(MILOperations.histogramName("fill_like", opset: "CoreML5") == nil)
        #expect(MILOperations.histogramName("einsum", opset: "CoreML8") == nil)
    }

    @Test func namesPrecisions() {
        #expect(CoreMLModelCompiler.precisionName(["Float32"]) == "Float32")
        #expect(CoreMLModelCompiler.precisionName(["Int32", "Float32", "Float16"]) == "Mixed (Float16, Float32, Int32)")
    }

    /// The archive of a program of specification version 7: version 5, `generic`, the description.
    @Test func archivesTheDescription() throws {
        let description = ProtobufMessage(fields: [.init(number: 100, wireType: .lengthDelimited, payload: [])])
        let archive = try CoreMLModelCompiler.genericArchive(type: 502, version: 7, description: description)
        #expect(Array(archive.prefix(8)) == [0xF6, 0x01, 0, 0, 5, 0, 0, 0])
        #expect(String(decoding: archive[0x24..<0x2B], as: UTF8.self) == "generic")
        #expect(Array(archive[0x2B..<0x2F]) == [7, 0, 0, 0])
        #expect(Array(archive[0x4B..<0x56]) == [3, 0, 0, 0, 0, 0, 0, 0, 0xA2, 0x06, 0x00])
        #expect(Array(archive.suffix(16)) == [0xF6, 0x01, 0, 0, 0, 0, 0, 0] + [UInt8](repeating: 0, count: 8))
        #expect(throws: (any Error).self) { try CoreMLModelCompiler.genericArchive(type: 502, version: 10, description: description) }
    }

    @Test func describesFlexibleInputs() {
        let input = MILText.FlexibleInput(name: "x", shape: [1, 3], ranges: [(1, 32), (3, 3)])
        #expect(MILText(bareScalars: false).flexibleShapeInformation([input]) == """
            FlexibleShapeInformation = tuple<tuple<tensor<string, []>, dict<tensor<string, []>, tensor<int32, [?]>>>, tuple<tensor<string, []>, \
            dict<tensor<string, []>, list<tensor<int32, [2]>, ?>>>>((("DefaultShapes", {{"x", [1, 3]}}), ("RangeDims", {{"x", [[1, 32], [3, 3]]}})))
            """)
    }
}
