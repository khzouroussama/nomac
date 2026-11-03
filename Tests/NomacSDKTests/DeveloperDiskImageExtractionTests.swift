import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacSDK

/// The pbzx payload of Xcode's `XcodeSystemResources.pkg` (docs/formats/ddi.md): stored chunks
/// are copied, anything else is not a pbzx stream.
@Suite struct DeveloperDiskImageExtractionTests {
    static func number(_ value: Int) -> [UInt8] { (0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }

    @Test func copiesStoredChunks() throws {
        let tmp = try TemporaryDirectory()
        let chunks = [Array("070707 cpio".utf8), Array(" trailer".utf8)]
        let stream = Array("pbzx".utf8) + Self.number(16 << 20) + chunks.flatMap { Self.number($0.count) + Self.number($0.count) + $0 }
        try FileSystem.write(Data(stream), to: tmp.path + "/Payload")
        try DeveloperDiskImageExtraction.pbzx(tmp.path + "/Payload", to: tmp.path + "/payload.cpio", xz: "/nonexistent/xz", work: tmp.path)
        #expect(FileSystem.contents(atPath: tmp.path + "/payload.cpio") == Data("070707 cpio trailer".utf8))
    }

    @Test func refusesAnotherFormat() throws {
        let tmp = try TemporaryDirectory()
        try FileSystem.write(Data("xar!".utf8), to: tmp.path + "/Payload")
        #expect(throws: NomacError.self) {
            try DeveloperDiskImageExtraction.pbzx(tmp.path + "/Payload", to: tmp.path + "/out", xz: "/nonexistent/xz", work: tmp.path)
        }
    }
}
