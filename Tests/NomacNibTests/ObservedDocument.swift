import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// A document with what Xcode 27.0 made of it: the digest of its files in name order, each name then
/// its bytes, and a storyboard's warnings; no digest where ibtool makes a bundle or fails, which nomac refuses.
struct ObservedDocument: Sendable, CustomTestStringConvertible {
    let name: String
    let path: String
    let target: String
    let digest: String?
    let warnings: [String]
    let document: String

    var testDescription: String { name }

    func check() throws {
        let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: target, targetDevices: ["iphone"])
        let data = Data(document.utf8)
        func compile() throws -> (files: [String: Data], warnings: [String]) {
            guard path.hasSuffix(".storyboard") else { return (["": try XIBCompiler.compile(data, path: path, options: options)], []) }
            return try StoryboardCompiler.compileReportingWarnings(data, path: path, options: options)
        }
        guard let digest else {
            #expect { try compile() } throws: { "\($0)".contains("(BACKLOG B-") }
            return
        }
        let compiled = try compile()
        let bytes = compiled.files.sorted { $0.key < $1.key }.flatMap { Array($0.key.utf8) + Array($0.value) }
        #expect(VariationTests.digest(Data(bytes)) == digest)
        #expect(compiled.warnings == warnings)
    }
}
