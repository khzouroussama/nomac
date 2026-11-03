import Foundation
import NomacCore
import Testing
@testable import NomacCoreData

/// What Xcode 27.0's momc generates and compiles for the models of coredata-experiments
/// `relationships-order` and `relationships-several`, stated as SHA-256 digests. Generated files
/// name their author and day, here a fixed one (docs/formats/coredata.md "Code generation").
@Suite struct CodeGeneratorTests {
    static let relationshipsOrder = """
            <entity name="Hub" representedClassName="Hub" syncable="YES" codeGenerationType="class">
                <relationship name="z" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Zed"/>
                <attribute name="t" optional="YES" customClassName="NSValue" attributeType="Transformable"/>
                <relationship name="b" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Yon"/>
                <relationship name="c" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="Zed"/>
                <attribute name="m" optional="YES" attributeType="String"/>
                <relationship name="d" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Plain"/>
                <relationship name="e" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="Low"/>
                <relationship name="f" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Mod"/>
            </entity>
            <entity name="Zed" representedClassName="Zed" syncable="YES" codeGenerationType="class"/>
            <entity name="Yon" representedClassName="Yon" syncable="YES" codeGenerationType="class"/>
            <entity name="Plain" representedClassName="Plain" syncable="YES"/>
            <entity name="Low" representedClassName="low" syncable="YES" codeGenerationType="class"/>
            <entity name="Mod" representedClassName="Other.Mod" syncable="YES" codeGenerationType="class"/>
        """
    static let relationshipsSeveral = """
            <entity name="A" representedClassName="A" syncable="YES" codeGenerationType="class">
                <attribute name="name" optional="YES" attributeType="String"/>
                <relationship name="b" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="B"/>
                <relationship name="cs" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="C"/>
                <relationship name="parent" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A"/>
            </entity>
            <entity name="B" representedClassName="B" syncable="YES" codeGenerationType="class"/>
            <entity name="C" representedClassName="C" syncable="YES" codeGenerationType="class"/>
            <entity name="Sub" representedClassName="Sub" parentEntity="A" syncable="YES" codeGenerationType="class">
                <relationship name="items" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="B"/>
            </entity>
        """

    static func write(_ directory: String, _ entities: String, language: String) throws -> String {
        let path = "\(ModelCompilerTests.work)/\(directory)/Model.xcdatamodel"
        try FileSystem.write(Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="\(language)" userDefinedModelVersionIdentifier="">
            \(entities)
            </model>
            """.utf8), to: path + "/contents")
        return path
    }

    /// The SHA-256 of every generated file's name and contents, in byte order of the names.
    @Test(arguments: [
        ("relationships-order", "Swift", "896322abbd07cdcf78f5aee27aca55d089eef3a44d30d970bc61ba772c5a1ab2"),
        ("relationships-order", "Objective-C", "a23bb48b8967eacb506b8441c766b5540c34675ea3093e5888894ed2b082bf52"),
        ("relationships-several", "Objective-C", "096048152f6b8b8e01f097c5f2d4b13c056d198e07242a1e4ffb03d5f51717f3"),
    ])
    func generatesClassesAsMomc(_ model: String, _ language: String, _ digest: String) throws {
        let entities = model == "relationships-order" ? Self.relationshipsOrder : Self.relationshipsSeveral
        let path = try Self.write("\(model)-\(language)", entities, language: language)
        let date = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12)))
        let files = try CodeGenerator.files(path, swiftVersion: "5.0", author: .init(name: "Test", date: date))
        var bytes: [UInt8] = []
        for file in files.sorted(by: { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }) {
            bytes += Array(file.name.utf8) + [0] + Array(file.contents.utf8) + [0]
        }
        #expect(hex(SHA256.digest(bytes)) == digest)
    }

    /// Attributes, then relationships, each by name, in the archive and the warnings.
    @Test func compilesPropertiesByKindThenName() throws {
        let path = try Self.write("relationships-order-compile", Self.relationshipsOrder, language: "Swift")
        let output = try ModelCompiler.compile(path, module: "T")
        #expect(output.files.map { hex(SHA256.digest($0.contents)) } == ["c9d3838ca52231d462337937512d312a0b5705e49120b6abda2ecd43546e0446"])
        let warned = output.diagnostics.map { $0.components(separatedBy: ": warning: ")[0].split(separator: ":").last.map(String.init) }
        #expect(warned == ["Hub.t", "Hub.b", "Hub.c", "Hub.d", "Hub.e", "Hub.f", "Hub.z"])
    }

    /// coredata-experiments `sort-order`, whose warnings list the relationships in momc's order.
    @Test func sortsNamesAsMomc() throws {
        let names = ["Ab", "aB", "ab", "aZ", "a_x", "a1", "A2", "a10", "a9"]
        #expect(try ModelNameOrder.sorted(names) { $0 } == ["a_x", "a1", "A2", "a9", "a10", "ab", "aB", "Ab", "aZ"])
        #expect(throws: NomacError.self) { try ModelNameOrder.sorted(["a01", "a1"]) { $0 } }
    }
}
