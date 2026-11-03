import Foundation
import Testing
import NomacCore
@testable import NomacCoreData

/// The `.omo` of a current version (coredata-experiments `omo-*`; ADR 0230: momc's file and
/// nomac's are identical once momc's SQL column-name lists are sorted, which these digests are).
@Suite struct OptimizedModelTests {
    static let work = NSTemporaryDirectory() + "nomac-omo-tests-\(getpid())"
    static let head = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
        + #"<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">"# + "\n"
    static let current = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>_XCCurrentVersionName</key>
        \t<string>Model.xcdatamodel</string>
        </dict>
        </plist>

        """

    func compile(_ name: String, _ entities: String, tools: String = "Automatic") throws -> [String: String] {
        let path = "\(Self.work)/\(name)/Model.xcdatamodeld"
        let head = Self.head.replacingOccurrences(of: #"minimumToolsVersion="Automatic""#, with: #"minimumToolsVersion="\#(tools)""#)
        try FileSystem.write(Data((head + entities + "</model>\n").utf8), to: path + "/Model.xcdatamodel/contents")
        try FileSystem.write(Data(Self.current.utf8), to: path + "/.xccurrentversion")
        let output = try ModelCompiler.compile(path, module: "T")
        return Dictionary(uniqueKeysWithValues: output.files.map { ($0.path, hex(SHA256.digest($0.contents))) })
    }

    func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// NSManagedObject is archived and recorded as no class.
    @Test func defaultClass() throws {
        let digests = try compile("omo-default-class", """
                <entity name="Item" representedClassName="NSManagedObject" syncable="YES">
                    <attribute name="a" optional="YES" attributeType="String"/>
                </entity>

            """)
        #expect(digests["Model.momd/Model.mom"] == "0ac1fb320c394b1e0b91a0aa760730828ac9dd560527db4663eb4cbc1685beea")
        #expect(digests["Model.momd/Model.omo"] == "96b9d410ad11fbdd465b2c35e645fda10c628a3fd71746ebcdc1f284c9d6a86c")
    }

    /// Date defaults are floored to whole minutes; equal ones are one archived date.
    @Test func dateDefaults() throws {
        let intervals = ["1000", "1030", "59", "61", "-1000", "1000.7", "3599", "0", "60", "120.9", "-59", "7200", "86399"]
        let attributes = intervals.enumerated().map { index, interval in
            #"        <attribute name="d\#(String(format: "%02d", index))" optional="YES" defaultDateTimeInterval="\#(interval)" usesScalarValueType="NO" attributeType="Date"/>"#
        }.joined(separator: "\n")
        let digests = try compile("omo-date-defaults", """
                <entity name="E" representedClassName="E" syncable="YES" codeGenerationType="class">
            \(attributes)
                </entity>

            """)
        #expect(digests["Model.momd/Model.mom"] == "5a4dfa4485b6735b0d0e06bc25bb4bb29151d84c880b451790443d3f0f955a83")
        #expect(digests["Model.momd/Model.omo"] == "dabccb9f13a7b9f440c5e91eb1e25b24f3dfd2a97b1aae94f3e7a844ba5a7a38")
    }

    /// Every default-value type, transient and external attributes, a transformer, to-one and
    /// to-many relationships, entities in UTF-8 order (`CampSite` before `Camper`).
    @Test func coverage() throws {
        let digests = try compile("omo-coverage", """
                <entity name="CampSite" representedClassName="CampSite" syncable="YES" codeGenerationType="class">
                    <attribute name="number" optional="YES" attributeType="Integer 16" defaultValueString="3" usesScalarValueType="YES"/>
                    <relationship name="camper" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Camper" inverseName="site" inverseEntity="Camper"/>
                </entity>
                <entity name="Camper" representedClassName=".Camper" syncable="YES" codeGenerationType="class">
                    <attribute name="big" optional="YES" attributeType="Integer 64" defaultValueString="-7" usesScalarValueType="YES"/>
                    <attribute name="cached" optional="YES" transient="YES" attributeType="String"/>
                    <attribute name="flag" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
                    <attribute name="name" attributeType="String" defaultValueString="hello"/>
                    <attribute name="photo" optional="YES" attributeType="Binary" allowsExternalBinaryDataStorage="YES"/>
                    <attribute name="ratio" optional="YES" attributeType="Double" defaultValueString="0.5" usesScalarValueType="YES"/>
                    <attribute name="since" optional="YES" attributeType="Date" defaultDateTimeInterval="1000" usesScalarValueType="NO"/>
                    <attribute name="tags" optional="YES" attributeType="Transformable" valueTransformerName="NSSecureUnarchiveFromData" customClassName="[String]"/>
                    <attribute name="weight" optional="YES" attributeType="Float" defaultValueString="1.5" usesScalarValueType="YES"/>
                    <relationship name="notes" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Note" inverseName="camper" inverseEntity="Note"/>
                    <relationship name="site" optional="YES" maxCount="1" deletionRule="No Action" destinationEntity="CampSite" inverseName="camper" inverseEntity="CampSite"/>
                </entity>
                <entity name="Note" representedClassName="NSManagedObject" versionHashModifier="v2" syncable="YES">
                    <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
                    <attribute name="link" optional="YES" attributeType="URI"/>
                    <attribute name="text" optional="YES" attributeType="String"/>
                    <attribute name="when" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
                    <relationship name="camper" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Camper" inverseName="notes" inverseEntity="Camper"/>
                </entity>

            """)
        #expect(digests["Model.momd/Model.mom"] == "3eba651112e2098bdf033a420e94f5b2f627e0f44a497576879db49b91f9e678")
        #expect(digests["Model.momd/Model.omo"] == "d4c2d35c935fbf1bc415cb344042aba6ea5a948e55dada9e84112339be607527")
    }

    /// `elementID` on an entity, an attribute and a relationship, and one equal to an entity's name.
    @Test func renamingIdentifiers() throws {
        let digests = try compile("omo-renaming", """
                <entity name="Item" representedClassName="Item" elementID="OldItem" syncable="YES" codeGenerationType="class">
                    <attribute name="t" optional="YES" elementID="oldT" attributeType="String"/>
                    <attribute name="u" optional="YES" attributeType="String"/>
                    <relationship name="tags" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="Tag" inverseName="item" inverseEntity="Tag" elementID="oldTags"/>
                </entity>
                <entity name="Tag" representedClassName="Tag" elementID="Tag" versionHashModifier="v2" syncable="YES" codeGenerationType="class">
                    <relationship name="item" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Item" inverseName="tags" inverseEntity="Item"/>
                </entity>

            """)
        #expect(digests["Model.momd/Model.mom"] == "9bb4fd9f9359796924a76338f572cd36e8a4c1a73d30c35a183e2578742c42b4")
        #expect(digests["Model.momd/Model.omo"] == "4c354e2f9c247e5cbf9542831a9bcb5facdcffc4ebfdf3b0d002542feab92175")
    }

    /// An ordered to-many's order key, a to-many without an inverse as a hidden to-one on its
    /// destination, counts and delete rules.
    @Test(arguments: [
        ("omo-rel-ordered", """
            <entity name="A" representedClassName="A" syncable="YES" codeGenerationType="class">
                <relationship name="bs" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="B" inverseName="a" inverseEntity="B"/>
            </entity>
            <entity name="B" representedClassName="B" syncable="YES" codeGenerationType="class">
                <relationship name="a" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A" inverseName="bs" inverseEntity="A"/>
            </entity>
            """, "e95bcd8dc0633d59829060f99d1f4450b5421a7f85fbf83fe4a00763e7c9e647"),
        ("omo-rel-no-inverse", """
            <entity name="A" representedClassName="A" syncable="YES" codeGenerationType="class">
                <relationship name="bs" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="B"/>
                <relationship name="c" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="B"/>
            </entity>
            <entity name="B" representedClassName="B" syncable="YES" codeGenerationType="class">
            </entity>
            """, "31dbb64061c30bca672a847ad77f402b1b69cc2d930caca75b6e4e1ab0170e98"),
        ("omo-rel-rules", """
            <entity name="A" representedClassName="A" syncable="YES" codeGenerationType="class">
                <relationship name="b" maxCount="1" deletionRule="Deny" destinationEntity="B" inverseName="as" inverseEntity="B"/>
                <relationship name="cs" optional="YES" toMany="YES" minCount="1" maxCount="5" deletionRule="Cascade" destinationEntity="B" inverseName="a" inverseEntity="B"/>
            </entity>
            <entity name="B" representedClassName="B" syncable="YES" codeGenerationType="class">
                <relationship name="a" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A" inverseName="cs" inverseEntity="A"/>
                <relationship name="as" optional="YES" toMany="YES" deletionRule="Deny" destinationEntity="A" inverseName="b" inverseEntity="A"/>
            </entity>
            """, "0c33c90fdb33162341a074a9b5f06f82ef6673725c95e0794ef19abca1f6f507"),
    ])
    func relationships(_ name: String, _ entities: String, _ digest: String) throws {
        #expect(try compile(name, entities + "\n")["Model.momd/Model.omo"] == digest)
    }

    /// Indexed attributes, a compound index and fetch indexes of several elements, in either
    /// order and on a relationship, recorded in the entity (`omo-fi-*`).
    @Test(arguments: [
        ("omo-fi-indexed-compound", """
            <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
                <attribute name="x" optional="YES" indexed="YES" attributeType="String"/>
                <attribute name="y" optional="YES" indexed="YES" usesScalarValueType="YES" attributeType="Integer 16"/>
                <attribute name="z" optional="YES" attributeType="String"/>
                <compoundIndexes><compoundIndex><index value="y"/><index value="z"/></compoundIndex></compoundIndexes>
            </entity>
            """, "d9d414bf1834a4cc655530ad58d0f52c7a7f8b50ea6ba726057c41cd50a54dc5"),
        ("omo-fi-class", """
            <entity name="Item" representedClassName="StoredItem" syncable="YES">
                <attribute name="a" optional="YES" attributeType="String"/>
                <fetchIndex name="byA"><fetchIndexElement property="a" type="Binary" order="ascending"/></fetchIndex>
            </entity>
            """, "8067505fd3cc3419ce6ceb4917a7980b012781d049479061fb6d45ef3ecf78c4"),
        ("omo-fi-several", """
            <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
                <attribute name="a" optional="YES" attributeType="String"/>
                <attribute name="b" optional="YES" usesScalarValueType="YES" attributeType="Integer 32"/>
                <relationship name="c" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Tag" inverseName="items" inverseEntity="Tag"/>
                <fetchIndex name="byA"><fetchIndexElement property="a" type="Binary" order="ascending"/></fetchIndex>
                <fetchIndex name="byBA"><fetchIndexElement property="b" type="Binary" order="descending"/><fetchIndexElement property="a" type="Binary" order="ascending"/></fetchIndex>
                <fetchIndex name="byC"><fetchIndexElement property="c" type="Binary" order="ascending"/></fetchIndex>
            </entity>
            <entity name="Tag" representedClassName="Tag" syncable="YES" codeGenerationType="class">
                <attribute name="name" optional="YES" attributeType="String"/>
                <relationship name="items" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="Item" inverseName="c" inverseEntity="Item"/>
                <fetchIndex name="byName"><fetchIndexElement property="name" type="Binary" order="ascending"/></fetchIndex>
            </entity>
            """, "0a7bf94801f848a853afba24c453b37841a7a0b19a4c8b0b3d289126ef9cda52"),
    ])
    func indexes(_ name: String, _ entities: String, _ digest: String) throws {
        #expect(try compile(name, entities + "\n")["Model.momd/Model.omo"] == digest)
    }

    /// Uniqueness constraints of one or several properties, a to-one among them (`omo-uq-several`).
    @Test func uniquenessConstraints() throws {
        let digests = try compile("omo-uq-several", """
                <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
                    <attribute name="a" optional="YES" attributeType="String"/>
                    <attribute name="b" optional="YES" attributeType="String"/>
                    <attribute name="c" optional="YES" usesScalarValueType="YES" attributeType="Integer 64"/>
                    <relationship name="tag" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Tag" inverseName="items" inverseEntity="Tag"/>
                    <uniquenessConstraints><uniquenessConstraint><constraint value="a"/></uniquenessConstraint><uniquenessConstraint><constraint value="b"/><constraint value="c"/></uniquenessConstraint><uniquenessConstraint><constraint value="tag"/><constraint value="a"/></uniquenessConstraint></uniquenessConstraints>
                </entity>
                <entity name="Other" representedClassName="Other" syncable="YES" codeGenerationType="class">
                    <attribute name="x" optional="YES" attributeType="String"/>
                </entity>
                <entity name="Tag" representedClassName="Tag" syncable="YES" codeGenerationType="class">
                    <attribute name="name" optional="YES" attributeType="String"/>
                    <relationship name="items" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="Item" inverseName="tag" inverseEntity="Item"/>
                    <uniquenessConstraints><uniquenessConstraint><constraint value="name"/></uniquenessConstraint></uniquenessConstraints>
                </entity>

            """)
        #expect(digests["Model.momd/Model.omo"] == "7874437e9f923a38f9e38a33b257d0b6f83fa3b2472c99ad725f58be369e3d4b")
    }

    /// Validation bounds of every type, alone and beside a renaming identifier, aligned in records
    /// that start on either 8-byte boundary; user info of an entity and an attribute.
    @Test(arguments: [
        ("omo-val-cases", """
            <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
                <attribute name="a" optional="YES" minValueString="-5" usesScalarValueType="YES" attributeType="Integer 16"/>
                <attribute name="b" optional="YES" maxValueString="9000000000" usesScalarValueType="YES" attributeType="Integer 64"/>
                <attribute name="c" optional="YES" minValueString="0.5" maxValueString="2.25" usesScalarValueType="YES" attributeType="Double"/>
                <attribute name="d" optional="YES" minValueString="-1.5" usesScalarValueType="YES" attributeType="Float"/>
                <attribute name="e" optional="YES" minValueString="3" attributeType="String"/>
                <attribute name="f" optional="YES" maxValueString="8" elementID="oldF" attributeType="String"/>
                <attribute name="g" optional="YES" minValueString="0" maxValueString="0" usesScalarValueType="YES" attributeType="Integer 32"/>
            </entity>
            """, "49b80d031708c3d4473db4917248e700b28e6a8e438c2ac77da0073269b53d54", "2f7d2f3bfb2303cb179ce67645741868c2daee92ae93becbd8c2d4aa5b4dfe1d"),
        ("omo-val-float", """
            <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
                <attribute name="a" optional="YES" defaultValueString="3" usesScalarValueType="YES" attributeType="Integer 16"/>
                <attribute name="b" optional="YES" minValueString="0.1" usesScalarValueType="YES" attributeType="Float"/>
                <attribute name="c" optional="YES" defaultValueString="4" usesScalarValueType="YES" attributeType="Integer 16"/>
                <attribute name="d" optional="YES" maxValueString="0.3" usesScalarValueType="YES" attributeType="Double"/>
                <attribute name="e" optional="YES" minValueString="7" usesScalarValueType="YES" attributeType="Integer 32"/>
            </entity>
            """, "0de54d2217bab86d4baea5b6cfc67058807102a0507cfbc74c3716b5fd9898d5", "649432546821f8f0d3e4ba99d18df3ece934851a9f1c846cb2faafbf8ac55628"),
        ("omo-user-info", """
            <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
                <attribute name="t" optional="YES" attributeType="String"><userInfo><entry key="k" value="v"/></userInfo></attribute>
                <userInfo><entry key="ek" value="ev"/></userInfo>
            </entity>
            """, nil, "9a39012d8d583f5f3d276c0d3dc2727358d1cbe944c6541c62caab4c42a18781"),
    ])
    func validationAndUserInfo(_ name: String, _ entities: String, _ mom: String?, _ omo: String) throws {
        let digests = try compile(name, entities + "\n")
        if let mom { #expect(digests["Model.momd/Model.mom"] == mom) }
        #expect(digests["Model.momd/Model.omo"] == omo)
    }

    /// Fetch request templates, in the order of a copy of a dictionary of their names
    /// (`omo-fr-several`).
    @Test func fetchRequestTemplates() throws {
        let digests = try compile("omo-fr-several", """
                <entity name="Alpha" representedClassName="Alpha" syncable="YES" codeGenerationType="class">
                    <attribute name="a" optional="YES" attributeType="String"/>
                </entity>
                <entity name="Beta" representedClassName="Beta" syncable="YES" codeGenerationType="class">
                    <attribute name="b" optional="YES" attributeType="String"/>
                </entity>
                <fetchRequest name="zAll" entity="Beta"/>
                <fetchRequest name="AllAlpha" entity="Alpha"/>
                <fetchRequest name="Second" entity="Alpha"/>

            """)
        #expect(digests["Model.momd/Model.mom"] == "2d15b21072b0e49f290e3410eb295011d5cf14872626414447c3185dac804d80")
        #expect(digests["Model.momd/Model.omo"] == "e00d087ce32b903dfd8c97eb07aa225fc549753d9a9cd04586ec1e098b646e67")
    }

    /// Entity inheritance: three levels, and inherited attributes and a relationship beside own
    /// attributes; each family list sorted (ADR 0232).
    @Test(arguments: [
        ("omo-inh-chain", """
            <entity name="Base" representedClassName="Base" syncable="YES" codeGenerationType="class">
                <attribute name="name" optional="YES" attributeType="String"/>
            </entity>
            <entity name="Mid" representedClassName="Mid" parentEntity="Base" syncable="YES" codeGenerationType="class">
                <attribute name="m" optional="YES" attributeType="String"/>
            </entity>
            <entity name="Leaf" representedClassName="Leaf" parentEntity="Mid" syncable="YES" codeGenerationType="class">
                <attribute name="l" optional="YES" attributeType="String"/>
            </entity>
            """, "986bcbe67a70b672f076c74688eee59642c51b15a1c766b466a0625dec33a172", "43ac3cfed92348bf45cb621c336a5e0e2184c02f7f64d8138dac11303bf410a4"),
        ("omo-inh-members", """
            <entity name="Base" representedClassName="Base" syncable="YES" codeGenerationType="class">
                <attribute name="name" optional="YES" attributeType="String"/>
                <attribute name="size" optional="YES" usesScalarValueType="YES" attributeType="Integer 32"/>
                <relationship name="tag" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Tag" inverseName="items" inverseEntity="Tag"/>
            </entity>
            <entity name="Sub" representedClassName="Sub" parentEntity="Base" syncable="YES" codeGenerationType="class">
                <attribute name="extra" optional="YES" attributeType="String"/>
                <attribute name="count" optional="YES" usesScalarValueType="YES" attributeType="Integer 64"/>
            </entity>
            <entity name="Tag" representedClassName="Tag" syncable="YES" codeGenerationType="class">
                <attribute name="label" optional="YES" attributeType="String"/>
                <relationship name="items" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="Base" inverseName="tag" inverseEntity="Base"/>
            </entity>
            """, "d002e011adcb1d8a720360593b90447bd389a0c6490186ac2a52e2723324f062", "2732af33185125a9a58cd4c9b33be92d8fa4f8aa1910050c4fc7d9509221c16d"),
    ])
    func inheritance(_ name: String, _ entities: String, _ mom: String, _ omo: String) throws {
        let digests = try compile(name, entities + "\n")
        #expect(digests["Model.momd/Model.mom"] == mom)
        #expect(digests["Model.momd/Model.omo"] == omo)
    }

    /// Fetch indexes under a `minimumToolsVersion` before Xcode 9.0 are not observed in an `.omo`
    /// (BACKLOG B-256).
    @Test func refusesLegacyIndexes() {
        #expect {
            _ = try compile("refused-legacy-indexes", """
                    <entity name="Item" representedClassName="Item" syncable="YES">
                        <attribute name="a" optional="YES" attributeType="String" indexed="YES"/>
                    </entity>

                """, tools: "Xcode 8.0")
        } throws: { error in
            "\(error)".contains("B-256") && "\(error)".contains("fetch indexes")
        }
    }
}
