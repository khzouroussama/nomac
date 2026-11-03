import Foundation
import Testing
import NomacCore
@testable import NomacBuild

/// `nomac build --case-aliases` (BACKLOG B-062): links for the paths a project spells in another
/// case than the disk, made only where the file system tells cases apart, removed afterwards.
@Suite struct CaseAliasesTests {
    static func tree(_ files: [String]) throws -> String {
        let root = FileManager.default.temporaryDirectory.path + "/nomac-aliases-\(UUID().uuidString)"
        for file in files {
            try FileManager.default.createDirectory(atPath: root + "/" + (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data().write(to: URL(fileURLWithPath: root + "/" + file))
        }
        return root
    }

    static func caseSensitive(_ root: String) -> Bool {
        !FileManager.default.fileExists(atPath: root.uppercased())
    }

    @Test func linksEachComponentInAnotherCaseAndRemovesThem() throws {
        let root = try Self.tree(["PdfGeneration/Gen.swift", "a/b/C.swift", "App.swift"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        var aliases = CaseAliases(paths: [root + "/PDFGeneration/Gen.swift", root + "/PDFGeneration/Page.swift", root + "/A/B/c.swift",
                                          root + "/App.swift", root + "/Missing/X.swift"])
        guard Self.caseSensitive(root) else {
            #expect(aliases.links.isEmpty)
            return
        }
        #expect(aliases.links == [
            .init(path: root + "/PDFGeneration", destination: "PdfGeneration"), .init(path: root + "/A", destination: "a"),
            .init(path: root + "/a/B", destination: "b"), .init(path: root + "/a/b/c.swift", destination: "C.swift"),
        ])
        try aliases.make()
        #expect(FileManager.default.fileExists(atPath: root + "/PDFGeneration/Gen.swift"))
        #expect(FileManager.default.fileExists(atPath: root + "/A/B/c.swift"))
        aliases.remove()
        #expect(try FileManager.default.contentsOfDirectory(atPath: root).sorted() == ["App.swift", "PdfGeneration", "a"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root + "/a/b") == ["C.swift"])
    }

    @Test func refusesAFolderItCannotWrite() throws {
        let root = try Self.tree(["PdfGeneration/Gen.swift"])
        defer {
            chmod(root, 0o755)
            try? FileManager.default.removeItem(atPath: root)
        }
        var aliases = CaseAliases(paths: [root + "/PDFGeneration/Gen.swift"])
        chmod(root, 0o555)
        guard Self.caseSensitive(root), !FileManager.default.isWritableFile(atPath: root) else { return }
        #expect(throws: NomacError.self) { try aliases.make() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root) == ["PdfGeneration"])
    }
}
