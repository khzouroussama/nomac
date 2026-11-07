import Foundation
import NomacCore
import Testing
@testable import NomacCoreData

/// What Xcode 27.0's momc writes for self-written models (coredata-experiments, compiled where the
/// experiments compile them: momc's order of versions depends on their paths), stated as the
/// SHA-256 of each file and the diagnostics it prints (docs/formats/coredata.md).
@Suite struct ModelCompilerTests {
    static let work = "/tmp/nomac-coredata-experiments"

    /// The self-written models of coredata-experiments, and the SHA-256 of each file momc wrote.
    static let models: [(name: String, contents: String, digests: [String: String])] = [
        ("one-date", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="timestamp" optional="YES" usesScalarValueType="NO" attributeType="Date"/>
    </entity>
</model>
"""#, ["Model.mom": "cd986f26421062cd04c0c9f54896e048b0971cff711301860b2e113e756e6e44"]),
        ("defaults", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="i16" optional="YES" defaultValueString="7" usesScalarValueType="YES" attributeType="Integer 16"/>
        <attribute name="s" optional="YES" defaultValueString="hello" attributeType="String"/>
        <attribute name="b" optional="YES" defaultValueString="YES" usesScalarValueType="YES" attributeType="Boolean"/>
        <attribute name="d" optional="YES" defaultValueString="1.5" usesScalarValueType="YES" attributeType="Double"/>
        <attribute name="t" optional="YES" defaultDateTimeInterval="0" usesScalarValueType="NO" attributeType="Date"/>
    </entity>
</model>
"""#, ["Model.mom": "f58b9e515fc6cdf74af8295efc8dbb9316fb908ee3631fc6f0d990c571dfe836"]),
        ("min-max", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="n" optional="YES" minValueString="1" maxValueString="9" usesScalarValueType="YES" attributeType="Integer 32"/>
        <attribute name="s" optional="YES" minValueString="2" maxValueString="5" attributeType="String"/>
    </entity>
</model>
"""#, ["Model.mom": "0fdec6b28a9be40c0eeb576e5a24b90d879d804d125c7fa481d7925925345873"]),
        ("ordered", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="A" representedClassName="A" syncable="YES" codeGenerationType="class">
        <relationship name="bs" optional="YES" toMany="YES" ordered="YES" deletionRule="Deny" destinationEntity="B"/>
    </entity>
    <entity name="B" representedClassName="B" syncable="YES" codeGenerationType="class">
    </entity>
</model>
"""#, ["Model.mom": "2b179ac4409d8d3f7deb8da66db414f925822e448b884cb14eee3309e073cafc"]),
        ("inheritance", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Base" representedClassName="Base" syncable="YES" codeGenerationType="class">
        <attribute name="name" optional="YES" attributeType="String"/>
    </entity>
    <entity name="Sub" representedClassName="Sub" parentEntity="Base" syncable="YES" codeGenerationType="class">
        <attribute name="n" optional="YES" usesScalarValueType="YES" attributeType="Integer 64"/>
    </entity>
</model>
"""#, ["Model.mom": "ae400647c06c95df40e1c6c67b192255aa8e34616613e9c2d69225dc43792102"]),
        ("uniqueness", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="t" optional="YES" attributeType="String"/>
        <uniquenessConstraints><uniquenessConstraint><constraint value="t"/></uniquenessConstraint></uniquenessConstraints>
    </entity>
</model>
"""#, ["Model.mom": "8cdf3fbabf84e86ae2aedc48c7f463683536997448ae238e2f3b9d2b2d459997"]),
        ("fetch-index", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="t" optional="YES" attributeType="String"/>
        <fetchIndex name="byT"><fetchIndexElement property="t" type="Binary" order="ascending"/></fetchIndex>
    </entity>
</model>
"""#, ["Model.mom": "0530e8b50b383da0d1d240a1c456b33db25a40a422bceef483c49e26026de853"]),
        ("fetch-request", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="t" optional="YES" attributeType="String"/>
    </entity>
    <fetchRequest name="All" entity="Item"/>
</model>
"""#, ["Model.mom": "6c2c35874ff594d62863b321f65a7f8ceff024ef3a490e072940fd3dc5fdffc4"]),
        ("indexed-tools-xcode-4-3", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Xcode 4.3" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="t" optional="YES" indexed="YES" attributeType="String"/>
    </entity>
</model>
"""#, ["Model.mom": "3b698f753c1b8e07f41099f906ae68243518013c04d78c3e01107eb0ba95f936"]),
    ]

    /// versioned-no-current: three versions and no `.xccurrentversion`.
    static let versions: [(name: String, contents: String)] = [
        ("Model", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="timestamp" optional="YES" usesScalarValueType="NO" attributeType="Date"/>
    </entity>
</model>
"""#),
        ("Model 2", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="timestamp" optional="YES" usesScalarValueType="NO" attributeType="Date"/>
        <attribute name="title" optional="YES" attributeType="String"/>
    </entity>
</model>
"""#),
        ("Other", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Base" representedClassName="Base" syncable="YES" codeGenerationType="class">
        <attribute name="name" optional="YES" attributeType="String"/>
    </entity>
    <entity name="Sub" representedClassName="Sub" parentEntity="Base" syncable="YES" codeGenerationType="class">
        <attribute name="n" optional="YES" usesScalarValueType="YES" attributeType="Integer 64"/>
    </entity>
</model>
"""#),
    ]
    static let versionDigests = [
        "Model.momd/Model 2.mom": "c4755c0bafe7030f63d8dbc71bade812686d01aac7b36c4dcfb5e7fc6536d214",
        "Model.momd/Model.mom": "cd986f26421062cd04c0c9f54896e048b0971cff711301860b2e113e756e6e44",
        "Model.momd/Other.mom": "ae400647c06c95df40e1c6c67b192255aa8e34616613e9c2d69225dc43792102",
        "Model.momd/VersionInfo.plist": "2d4b31075cc23a974343a210f59983ffd7589a7a055703db727f11a1413a74a6",
    ]
    static let versionDiagnostics = [
        "Model.xcdatamodel: note: Model Model version checksum: VNIRJOjhqmU35OF02buOyYQnU/0ToUzUMpGW5jvR3Ic=",
        "Model 2.xcdatamodel: note: Model Model 2 version checksum: AWLJQpiTskHZr9/FsZct8SpZ1+QR60255TKlemvjoLI=",
        "Other.xcdatamodel: note: Model Other version checksum: P4KgHweHpc2BqsedC/NhRCX6XHEgJ6rX6Br9wjuJQMM=",
        "/tmp/nomac-coredata-experiments/versioned-no-current/Model.xcdatamodeld:: warning: Missing current version declaration [0]",
    ]
    static let orderedWarning = "/tmp/nomac-coredata-experiments/ordered/Model.xcdatamodel:A.bs: warning: A.bs does not have an inverse; this is an advanced setting (no object can be in multiple destinations for a specific relationship) [7]"

    @Test(arguments: models.map(\.name))
    func compilesModelsAsMomc(_ name: String) throws {
        let model = try #require(Self.models.first { $0.name == name })
        let path = "\(Self.work)/\(name)/Model.xcdatamodel"
        try FileSystem.write(Data(model.contents.utf8), to: path + "/contents")
        let output = try ModelCompiler.compile(path, module: "T")
        #expect(Dictionary(uniqueKeysWithValues: output.files.map { ($0.path, hex(SHA256.digest($0.contents))) }) == model.digests)
        #expect(output.diagnostics == (name == "ordered" ? [Self.orderedWarning] : []))
    }

    @Test func compilesVersionsInTheOrderOfTheirPaths() throws {
        let path = "\(Self.work)/versioned-no-current/Model.xcdatamodeld"
        try? FileManager.default.removeItem(atPath: path)
        for version in Self.versions {
            try FileSystem.write(Data(version.contents.utf8), to: "\(path)/\(version.name).xcdatamodel/contents")
        }
        let output = try ModelCompiler.compile(path, module: "T")
        #expect(Dictionary(uniqueKeysWithValues: output.files.map { ($0.path, hex(SHA256.digest($0.contents))) }) == Self.versionDigests)
        #expect(output.diagnostics == Self.versionDiagnostics)
    }

    /// An insecure value transformer warns only in the current version, or in every version when
    /// none is current (coredata-experiments `warn-transformer-*`).
    @Test(arguments: [("Model 2", false), ("Model", true), (nil, true)])
    func transformersWarnInTheCurrentVersion(_ current: String?, _ warns: Bool) throws {
        let path = "\(Self.work)/warn-transformer-\(current ?? "none")/Model.xcdatamodeld".replacingOccurrences(of: " ", with: "-")
        try? FileManager.default.removeItem(atPath: path)
        let head = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">"#
        try FileSystem.write(Data((head + #"<entity name="Item" representedClassName="Item" syncable="YES"><attribute name="v" optional="YES" attributeType="Transformable"/></entity></model>"#).utf8),
                             to: path + "/Model.xcdatamodel/contents")
        try FileSystem.write(Data((head + #"<entity name="Item" representedClassName="Item" syncable="YES"><attribute name="t" optional="YES" attributeType="Date" usesScalarValueType="NO"/></entity></model>"#).utf8),
                             to: path + "/Model 2.xcdatamodel/contents")
        if let current {
            try FileSystem.write(Data(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>_XCCurrentVersionName</key><string>\#(current).xcdatamodel</string></dict></plist>"#.utf8),
                                 to: path + "/.xccurrentversion")
        }
        let warnings = try ModelCompiler.compile(path, module: "T").diagnostics.filter { $0.contains("insecure value transformer") }
        #expect(warnings.count == (warns ? 1 : 0))
    }

    /// coredata-experiments `codegen-order`, and moonlight's Objective-C model.
    @Test(arguments: [("Swift", ["swift"]), ("Objective-C", ["h", "m"])])
    func listsGeneratedFilesInFileOrder(_ language: String, _ extensions: [String]) throws {
        let path = "\(Self.work)/codegen-order-\(extensions[0])/Model.xcdatamodel"
        try FileSystem.write(Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" minimumToolsVersion="Automatic" sourceLanguage="\(language)">
                <entity name="Zeta" representedClassName="Zeta" syncable="YES" codeGenerationType="class"/>
                <entity name="Alpha" representedClassName="MyAlpha" syncable="YES" codeGenerationType="class"/>
                <entity name="Mid" representedClassName=".Mid" syncable="YES" codeGenerationType="category"/>
                <entity name="Plain" representedClassName="Plain" syncable="YES"/>
                <entity name="Beta" representedClassName="Other.Beta" syncable="YES" codeGenerationType="class"/>
            </model>
            """.utf8), to: path + "/contents")
        let names = ["Zeta+CoreDataClass", "Zeta+CoreDataProperties", "MyAlpha+CoreDataClass", "MyAlpha+CoreDataProperties",
                     "Mid+CoreDataProperties", "Beta+CoreDataClass", "Beta+CoreDataProperties", "Model+CoreDataModel"]
        #expect(try ModelCompiler.generatedFiles(path, destination: "/out") == names.flatMap { name in extensions.map { "/out/\(name).\($0)" } })
    }
}

/// Core Data's version hashes, as `NSPropertyDescription.versionHash` and friends give them for
/// the probes of coredata-experiments `version-hashes`.
@Suite struct VersionHashTests {
    static func attribute(_ name: String, _ type: DataModel.AttributeType = .undefined, optional: Bool = false,
                          transient: Bool = false) -> DataModel.Property {
        .attribute(DataModel.Attribute(name: name, type: type, isOptional: optional, isTransient: transient, defaultValue: nil,
                                       defaultDateTimeInterval: nil, usesScalarValueType: nil, minimum: nil, maximum: nil,
                                       isIndexed: false, valueTransformerName: nil, customClassName: nil, renamingIdentifier: nil,
                                       allowsExternalBinaryDataStorage: false, userInfo: [], hasSyncable: true))
    }

    static func relationship(_ name: String = "", destination: String = "", inverse: String? = nil, min: Int = 0, max: Int = 0,
                             ordered: Bool = false) -> DataModel.Property {
        .relationship(DataModel.Relationship(name: name, isOptional: false, isTransient: false, isToMany: max != 1, isOrdered: ordered,
                                             minCount: min, maxCount: max, deleteRule: .nullify, destination: destination,
                                             inverseName: inverse, renamingIdentifier: nil, hasSyncable: true))
    }

    static func entity(_ name: String, _ properties: [DataModel.Property], parent: String? = nil,
                       uniqueness: [[String]] = []) -> DataModel.Entity {
        DataModel.Entity(name: name, className: name, parentName: parent, isAbstract: false, versionHashModifier: nil,
                         renamingIdentifier: nil, codeGeneration: nil, properties: properties, uniquenessConstraints: uniqueness,
                         fetchIndexes: [], compoundIndexes: [], userInfo: [], hasSyncable: true)
    }

    static func model(_ entities: [DataModel.Entity]) -> DataModel {
        DataModel(entities: entities, fetchRequests: [], minimumToolsVersion: nil, sourceLanguage: "Swift")
    }

    @Test func propertiesHashTheirOwnHashThenTheirKind() {
        #expect(hex(VersionHash.property(Self.attribute(""))) == "cb738391ec58038c10cf387a525f059c885d1933b9cc0c6c6cf95ea0b3ad9cc5")
        #expect(hex(VersionHash.property(Self.attribute("a"))) == "d5866122ad8eaac88a85f3e2dd69de1075245401fe6e0546a25bac6982c50844")
        #expect(hex(VersionHash.property(Self.attribute("a\u{0}b"))) == "d5866122ad8eaac88a85f3e2dd69de1075245401fe6e0546a25bac6982c50844")
        #expect(hex(VersionHash.property(Self.attribute("", optional: true))) == "eba06cebb1653cdf6a6db45842c5ba075fae7d12b26ca088bd4178d9b4fadf97")
        #expect(hex(VersionHash.property(Self.attribute("", transient: true))) == "359c0aa904f8d0ff958c3c8c8d5a8513586dab458ce4cff2c55e9e85baaaf13d")
        #expect(hex(VersionHash.property(Self.attribute("", .date))) == "3d1511bbe84424ec96569016107620799a0fe0989374a342bedd6696e6a1eaa1")
        #expect(hex(VersionHash.property(Self.relationship())) == "171fa3118b952580147adb55e798af2665f5ac70f82d58f423d443ddc327cf35")
        #expect(hex(VersionHash.property(Self.relationship(destination: "D", inverse: "i"))) == "007ebfa3a5727f6901e5ecc319106024cd614d1d16b3481daf76ef095c1a25b9")
        #expect(hex(VersionHash.property(Self.relationship(min: 2, max: 5, ordered: true))) == "d944a48ca4b5c1a3412a63ed6324c8b1ffc811c3f5c3279d65c2fe38f117917c")
    }

    @Test func entitiesHashPersistentPropertiesByNameParentsAndUniqueness() throws {
        let item = Self.entity("Item", [Self.attribute("timestamp", .date, optional: true)])
        let hashes = try VersionHash.entities(of: Self.model([
            item,
            Self.entity("", []),
            Self.entity("E", [Self.attribute("a"), Self.attribute("", transient: true)]),
            Self.entity("S", [Self.attribute("a")], parent: "Item"),
            Self.entity("T", [Self.attribute("ab")], parent: "S"),
        ]))
        #expect(hex(hashes["Item"]!) == "18183a04c037273140991c06fe0c9b0daf53749cef8255d31b3136d5fd971676")
        #expect(hex(hashes[""]!) == "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d")
        #expect(hex(hashes["E"]!) == "535acdb7c9f472d5da050f3cf82fa2f6fa786b2000c1ab4e76a76c8e73393543")
        #expect(hex(hashes["T"]!) == "4bacfb42462f0235ad9d8e225aba70a6789ba0167e272f5b0df7635263a10c66")
        var unique = Self.entity("E", [Self.attribute("a"), Self.attribute("ab")], uniqueness: [["ab", "a"], ["a"]])
        unique.versionHashModifier = "m"
        #expect(hex(try VersionHash.entities(of: Self.model([unique]))["E"]!) == "fc4b07d9a4003ba25c8f5c411ac7f952edac4b74b0e89beec474004c9e9b737b")
    }

    @Test func checksumsHashEntityHashesByName() throws {
        #expect(Data(VersionHash.checksum([:])).base64EncodedString() == "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=")
        let hashes = try VersionHash.entities(of: Self.model([
            Self.entity("Item", [Self.attribute("timestamp", .date, optional: true)]),
            Self.entity("E", [Self.attribute("ab"), Self.attribute("a"), Self.relationship("r")]),
        ]))
        #expect(Data(VersionHash.checksum(hashes)).base64EncodedString() == "nDFEGS8GUqF5pHcun/sxDbkPs/NheK0MrsC8ma2yNE0=")
    }
}

/// Which equal strings a Mac makes one object, and how its default volume lists a directory.
@Suite struct ObjectIdentityTests {
    @Test func taggedPointerStrings() {
        #expect(TaggedPointerString.fits("Model 2"))
        #expect(TaggedPointerString.fits("CacheItem"))
        #expect(TaggedPointerString.fits("dateCreated"))
        #expect(TaggedPointerString.fits("eeeeeeeeeee"))
        #expect(!TaggedPointerString.fits("Attachment"))
        #expect(!TaggedPointerString.fits("Abcdefghij"))
        #expect(!TaggedPointerString.fits("Abcdefghijkl"))
        #expect(!TaggedPointerString.fits("\u{e9}t\u{e9}"))
    }

    /// mastodon's CoreData.xcdatamodeld as `ls -f` lists it on the owner's Mac.
    @Test func listsDirectoriesInAPFSOrder() {
        let listing = ["CoreData 9.xcdatamodel", "CoreData 5.xcdatamodel", "CoreData 6.xcdatamodel", "CoreData 3.xcdatamodel",
                       ".xccurrentversion", "CoreData 4.xcdatamodel", "CoreData 8.xcdatamodel", "CoreData 2.xcdatamodel",
                       "CoreData.xcdatamodel", "CoreData 10.xcdatamodel", "CoreData 7.xcdatamodel"]
        #expect(APFSDirectoryOrder.sorted(listing.sorted()) == listing)
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}
