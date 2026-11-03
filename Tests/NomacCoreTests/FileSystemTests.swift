import Foundation
import Testing
import NomacCore

/// A file is found by a path in either normalization form, as on a Mac's file systems, also
/// where the file system compares the bytes of names (Linux).
@Suite struct FileSystemNormalizationTests {
    @Test func findsFilesByEitherForm() throws {
        let root = FileManager.default.temporaryDirectory.path + "/nomac-fs-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        // Created with the names' bytes as given: Foundation decomposes them on a Mac.
        func write(_ contents: String, _ folder: String, _ name: String) throws {
            mkdir(root, 0o755)
            mkdir(root + "/" + folder, 0o755)
            let file = try #require(fopen(root + "/" + folder + "/" + name, "w"))
            fputs(contents, file)
            fclose(file)
        }
        try write("NFC\n", "Café".precomposedStringWithCanonicalMapping, "Zürich.txt".precomposedStringWithCanonicalMapping)
        try write("NFD\n", "Ångström".decomposedStringWithCanonicalMapping, "Über.txt".decomposedStringWithCanonicalMapping)
        for (path, contents) in [("Café/Zürich.txt", "NFC\n"), ("Ångström/Über.txt", "NFD\n")] {
            for form in [path.precomposedStringWithCanonicalMapping, path.decomposedStringWithCanonicalMapping] {
                let full = root + "/" + form
                #expect(FileSystem.isFile(full))
                #expect(FileSystem.exists(full))
                #expect(FileSystem.isDirectory((full as NSString).deletingLastPathComponent))
                #expect(FileSystem.contents(atPath: full) == Data(contents.utf8))
                #expect(FileManager.default.fileExists(atPath: FileSystem.onDisk(full)))
            }
        }
        #expect(try FileSystem.contentsOfDirectory(root + "/" + "Café".decomposedStringWithCanonicalMapping)
                    .map { Array($0.utf8) } == [Array("Zürich.txt".precomposedStringWithCanonicalMapping.utf8)])
        #expect(!FileSystem.exists(root + "/Cafe/Zürich.txt"))
        #expect(FileSystem.onDisk(root + "/Missing/" + "Café".decomposed).hasSuffix("/Missing/" + "Café".decomposed))
    }

    /// cwa's project names a `PDFGeneration` folder that is `PdfGeneration` on disk (BACKLOG B-062).
    @Test func findsFilesInAnyCase() throws {
        let root = FileManager.default.temporaryDirectory.path + "/nomac-fs-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/PdfGeneration", withIntermediateDirectories: true)
        try Data("swift\n".utf8).write(to: URL(fileURLWithPath: root + "/PdfGeneration/Gen.swift"))
        let caseSensitive = !FileManager.default.fileExists(atPath: root + "/PDFGENERATION")
        let path = root + "/PDFGeneration/gen.swift"
        #expect(FileSystem.onDisk(path) == (caseSensitive ? root + "/PdfGeneration/Gen.swift" : path))
        #expect(FileSystem.isFile(path))
        #expect(FileSystem.isDirectory(root + "/pdfgeneration"))
        #expect(FileSystem.contents(atPath: path) == Data("swift\n".utf8))
        #expect(!FileSystem.exists(root + "/PDFGeneration/Gen.swiftx"))
    }

    /// Where a folder can hold names that differ only in case (Linux), the one spelled as given
    /// wins, and of the others the first in byte order, whatever order the folder lists them in.
    @Test func prefersTheExactNameThenByteOrder() throws {
        let root = FileManager.default.temporaryDirectory.path + "/nomac-fs-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        for folder in ["Foo", "FOO", "foo"] {
            try FileManager.default.createDirectory(atPath: root + "/" + folder, withIntermediateDirectories: true)
            try Data(folder.utf8).write(to: URL(fileURLWithPath: root + "/" + folder + "/a.txt"))
        }
        guard try FileManager.default.contentsOfDirectory(atPath: root).count == 3 else { return }
        for folder in ["Foo", "FOO", "foo"] {
            #expect(FileSystem.onDisk(root + "/" + folder + "/a.txt") == root + "/" + folder + "/a.txt")
            #expect(FileSystem.onDisk(root + "/" + folder + "/A.TXT") == root + "/" + folder + "/a.txt")
            #expect(FileSystem.contents(atPath: root + "/" + folder + "/A.txt") == Data(folder.utf8))
        }
        #expect(FileSystem.onDisk(root + "/fOO/a.txt") == root + "/FOO/a.txt")
    }

    @Test func decomposesAndComparesBytes() {
        #expect(Array("Café".precomposedStringWithCanonicalMapping.decomposed.utf8) == Array("Cafe\u{301}".utf8))
        #expect("Caf\u{E9}" == "Cafe\u{301}")
        #expect(!"Caf\u{E9}".isIdentical(to: "Cafe\u{301}"))
        #expect("Cafe\u{301}".isIdentical(to: "Caf\u{E9}".decomposed))
    }

    /// xcodebuild spells a derived-data path under `/private/tmp` with `/tmp`.
    @Test func derivedDataPathsUnderPrivateTmpUseTmp() {
        #expect(FileSystem.xcodebuildSpelling("/private/tmp/nomac-corpus/App-DerivedData") == "/tmp/nomac-corpus/App-DerivedData")
        #expect(FileSystem.xcodebuildSpelling("/private/tmp") == "/tmp")
        #expect(FileSystem.xcodebuildSpelling("/private/tmpdir/D") == "/private/tmpdir/D")
        #expect(FileSystem.xcodebuildSpelling("/Users/me/D") == "/Users/me/D")
    }
}
