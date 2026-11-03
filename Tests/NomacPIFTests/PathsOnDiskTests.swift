import Foundation
import Testing
@testable import NomacPIF

/// The PIF Swift Build loads names a file reference spelled in another case than the disk by its
/// path on disk where the file system tells cases apart (BACKLOG B-062).
@Suite struct PathsOnDiskTests {
    @Test func namesFilesSpelledInAnotherCaseByTheirPathOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.path + "/nomac-pif-disk-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/PdfGeneration", withIntermediateDirectories: true)
        for name in ["App.swift", "PdfGeneration/Gen.swift", "PdfGeneration/Page.swift"] {
            try Data().write(to: URL(fileURLWithPath: root + "/" + name))
        }
        func file(_ path: String, _ sourceTree: String = "<group>") -> PIFValue {
            .object(["type": .string("file"), "path": .string(path), "sourceTree": .string(sourceTree)])
        }
        let tree = PIFValue.object([
            "type": .string("group"), "path": .string(""), "sourceTree": .string("<group>"),
            "children": .array([
                file("App.swift"),
                file("PDFGeneration/Gen.swift"),
                .object(["type": .string("group"), "path": .string("PDFGENERATION"), "sourceTree": .string("<group>"),
                         "children": .array([file("Page.swift")])]),
                file("Missing.swift", "SOURCE_ROOT"),
            ]),
        ])
        let document = PIFDocument(objects: [.init(type: "project", signature: "P", contents: .object([
            "projectDirectory": .string(root), "groupTree": tree,
        ]))])
        let children = try #require(document.resolvingPathsOnDisk().objects[0].contents.objectValue?["groupTree"]?.objectValue?["children"]?.arrayValue)

        if FileManager.default.fileExists(atPath: root + "/PDFGENERATION") {
            #expect(children == tree.objectValue?["children"]?.arrayValue)
            return
        }
        #expect(children[0] == file("App.swift"))
        #expect(children[1] == file(root + "/PdfGeneration/Gen.swift", "<absolute>"))
        #expect(children[2].objectValue?["path"] == .string("PDFGENERATION"))
        #expect(children[2].objectValue?["children"] == .array([file(root + "/PdfGeneration/Page.swift", "<absolute>")]))
        #expect(children[3] == file("Missing.swift", "SOURCE_ROOT"))
    }
}
