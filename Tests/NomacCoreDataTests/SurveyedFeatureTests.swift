import Foundation
import NomacCore
import Testing
@testable import NomacCoreData

/// What Xcode 27.0's momc wrote for one model per feature the coverage survey's models use
/// (coredata-experiments `SURVEY_MODELS`): the SHA-256 of the `.mom`, of the `.omo` with its column
/// lists and families sorted (ADR 0230, ADR 0232), and its warnings.
@Suite struct SurveyedFeatureTests {
    static let models: [(name: String, contents: String, mom: String, omo: String, warnings: [String])] = [
        ("no-class", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" syncable="YES">
        <attribute name="a" optional="YES" attributeType="String"/>
    </entity>
    <entity name="Sub" parentEntity="Item" syncable="YES"/>
</model>
"""#, "6ee3403e7c86ee2a0c4e02916b229125a6b7fc946464af47385fc89750daa57e", "308f9e2d83f837d4b16dd9cce4f6f62b38ef2a2c9df19f7c642d71c65462e09f",
         []),
        ("version-identifier", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="2.9">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="timestamp" optional="YES" usesScalarValueType="NO" attributeType="Date"/>
    </entity>
</model>
"""#, "87167763b1b1887c42406c1f6956956d9060552433b90e8a195bada7fbc70916", "4518e28506358bf453a3e7dc33b858b9d44beddcd812e1b7b2cdf44e4afc82b7",
         []),
        ("model-attributes", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model name="Test1.xcdatamodel" usedWithSwiftData="YES" type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class">
        <attribute name="timestamp" optional="YES" usesScalarValueType="NO" attributeType="Date"/>
    </entity>
</model>
"""#, "cd986f26421062cd04c0c9f54896e048b0971cff711301860b2e113e756e6e44", "5dd56bdfda12f841ef4f89c42632f47e56b86ac67e30ce92f154fb39b2659f6f",
         []),
        ("decimal-defaults", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <attribute name="a00" optional="YES" defaultValueString="0" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a01" optional="YES" defaultValueString="0.0" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a02" optional="YES" defaultValueString="0.00" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a03" optional="YES" defaultValueString="00" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a04" optional="YES" defaultValueString="1" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a05" optional="YES" defaultValueString="1.5" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a06" optional="YES" defaultValueString="1.50" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a07" optional="YES" defaultValueString="10" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a08" optional="YES" defaultValueString="100" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a09" optional="YES" defaultValueString="1000" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a10" optional="YES" defaultValueString="-1" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a11" optional="YES" defaultValueString="-1.5" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a12" optional="YES" defaultValueString="1e3" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a13" optional="YES" defaultValueString="1E-2" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a14" optional="YES" defaultValueString=".5" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a15" optional="YES" defaultValueString="5." usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a16" optional="YES" defaultValueString="abc" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a17" optional="YES" defaultValueString="" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a18" optional="YES" defaultValueString=" 1" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a19" optional="YES" defaultValueString="1 " usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a20" optional="YES" defaultValueString="+1" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a21" optional="YES" defaultValueString="65535" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a22" optional="YES" defaultValueString="65536" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a23" optional="YES" defaultValueString="4294967296" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a24" optional="YES" defaultValueString="123456789012345678901234567890" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a25" optional="YES" defaultValueString="0.1" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a26" optional="YES" defaultValueString="0.001" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a27" optional="YES" defaultValueString="-0" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a28" optional="YES" defaultValueString="-0.0" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a29" optional="YES" defaultValueString="NaN" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a30" optional="YES" defaultValueString="1,5" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a31" optional="YES" defaultValueString="12abc" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a32" optional="YES" defaultValueString="1.2.3" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="a33" optional="YES" defaultValueString="0.000001" usesScalarValueType="NO" attributeType="Decimal"/>
    </entity>
</model>
"""#, "eca02057ca2157979681827dbd55815313bb38a11359bf6460fd446a53a943b3", "0d7359c8d042965e87344cacc29f72549e42eae6f76ad9a57ee479abf637b0a7",
         []),
        ("decimal-several", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="A" representedClassName="A" syncable="YES">
        <attribute name="a" optional="YES" usesScalarValueType="NO" attributeType="Decimal"/>
        <attribute name="b" optional="YES" usesScalarValueType="NO" attributeType="Decimal"/>
    </entity>
    <entity name="B" representedClassName="B" syncable="YES">
        <attribute name="a" optional="YES" usesScalarValueType="NO" attributeType="Decimal"/>
    </entity>
</model>
"""#, "713a5c3f1d0a3ce358d85fa1437c6f48b5ce48e546b6565b4069575da98f303f", "f7047be44b31eb0a60c9318524a88e62725d0fbb76743060f6ee05b4d537f837",
         []),
        ("default-ignored", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <attribute name="u" optional="YES" defaultValueString="https://x.y" attributeType="URI"/>
        <attribute name="i" optional="YES" defaultValueString="F6CDB0E3-3A6B-4B5C-9D4E-1F2A3B4C5D6E" attributeType="UUID"/>
        <attribute name="b" optional="YES" defaultValueString="abc" attributeType="Binary"/>
        <attribute name="t" optional="YES" valueTransformerName="V" defaultValueString="0" attributeType="Transformable"/>
    </entity>
</model>
"""#, "de4de1933644b9dd938707b75ce7a38477faf0b4bf5d1520a77080fe8827e47c", "69307e409dd92cbf3cbf311de0f87f26bddfb61460b20421135abfd4cb6fc9ea",
         []),
        ("tools-automatic-11116", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="11116" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" >
        <attribute name="a" optional="YES" indexed="YES" attributeType="String"/>
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other"/>
    </entity>
    <entity name="Other" representedClassName="Other" >
    </entity>
</model>
"""#, "1ca254c01fa87fb11adb525ea3ebf3d9c4e191760175f970ede75463d4494f1b", "347260495c1968910da615ac5683b906d247bd9cb2448ed155e2d3b09b9312c0",
         ["Item.o should have an inverse [2]"]),
        ("tools-automatic-11117", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="11117" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" >
        <attribute name="a" optional="YES" indexed="YES" attributeType="String"/>
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other"/>
    </entity>
    <entity name="Other" representedClassName="Other" >
    </entity>
</model>
"""#, "4b9857daf11cceb580316a407024eaef3c43e856831bde1524704b4db4f46a19", "58a1871def85ba1398ed446390c777a2ee16d8543a334885a322603257a7f7bc",
         ["Item.o should have an inverse [2]"]),
        ("tools-automatic-2", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="2" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" >
        <attribute name="a" optional="YES" indexed="YES" attributeType="String"/>
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other"/>
    </entity>
    <entity name="Other" representedClassName="Other" >
    </entity>
</model>
"""#, "1ca254c01fa87fb11adb525ea3ebf3d9c4e191760175f970ede75463d4494f1b", "347260495c1968910da615ac5683b906d247bd9cb2448ed155e2d3b09b9312c0",
         ["Item.o should have an inverse [2]"]),
        ("tools-automatic-fraction", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="9525.2" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" >
        <attribute name="a" optional="YES" indexed="YES" attributeType="String"/>
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other"/>
    </entity>
    <entity name="Other" representedClassName="Other" >
    </entity>
</model>
"""#, "1ca254c01fa87fb11adb525ea3ebf3d9c4e191760175f970ede75463d4494f1b", "347260495c1968910da615ac5683b906d247bd9cb2448ed155e2d3b09b9312c0",
         ["Item.o should have an inverse [2]"]),
        ("syncable-xcode-10", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Xcode 10.0" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" >
        <attribute name="a" optional="YES" indexed="YES" attributeType="String"/>
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other"/>
    </entity>
    <entity name="Other" representedClassName="Other" >
    </entity>
</model>
"""#, "9854d9f0a336859635177a22d871747ed3e1b48ba3d2e6ed8e1322cf4a0d5aeb", "729adc9058b0aef54a49cfa0e39a30e5a69ddda8a9d39dbcee20ec092a32e67c",
         ["Item.o should have an inverse [2]"]),
        ("syncable-xcode-11", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Xcode 11.0" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" >
        <attribute name="a" optional="YES" indexed="YES" attributeType="String"/>
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other"/>
    </entity>
    <entity name="Other" representedClassName="Other" >
    </entity>
</model>
"""#, "4b9857daf11cceb580316a407024eaef3c43e856831bde1524704b4db4f46a19", "58a1871def85ba1398ed446390c777a2ee16d8543a334885a322603257a7f7bc",
         ["Item.o should have an inverse [2]"]),
        ("syncable-no", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="5064" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" >
        <attribute name="a" optional="YES" indexed="YES" syncable="NO" attributeType="String"/>
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other" syncable="NO"/>
    </entity>
    <entity name="Other" representedClassName="Other" >
    </entity>
</model>
"""#, "dfeedb65851acf11e1f0415dfcf1f00672c1a00f4ce7b5d8ad7ab5d6235d08ab", "2fa5417619fd573d665c395aa1a27aba6de2e8d3e45969d099ef8a1147050580",
         ["Item.o should have an inverse [2]"]),
        ("syncable-user-info", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="5064" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" >
        <attribute name="a" optional="YES" attributeType="String"><userInfo><entry key="k" value="v"/></userInfo></attribute>
        <userInfo><entry key="e" value="f"/></userInfo>
    </entity>
</model>
"""#, "47d97a4407890dc0d279f7350169e18e72b7978c380284d3933db35fe9f99843", "9c9da616611910e0bc1c601bcc749e06956b1ec4cf6fcf740c746ced2ed5d00b",
         []),
        ("property-flags-attribute", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <attribute name="a" optional="YES" spotlightIndexingEnabled="YES" attributeType="String"/>
        <attribute name="b" optional="YES" storedInTruthFile="YES" attributeType="String"/>
        <attribute name="c" optional="YES" allowsCloudEncryption="YES" attributeType="String"/>
        <attribute name="d" optional="YES" spotlightIndexingEnabled="YES" storedInTruthFile="YES" allowsCloudEncryption="YES" attributeType="String"/>
    </entity>
</model>
"""#, "6b00415c702f2dd77521ed9365c7873dfc415d6d7796f77f71dea15947ed219b", "f49381a0bad5be30af5981e3894e61552293e2b80aabca07f0e51a475989fad6",
         ["Item.b is set to be stored using a Spotlight external record file, which is deprecated. Use Core Spotlight integration instead. [5]", "Item.d is set to be stored using a Spotlight external record file, which is deprecated. Use Core Spotlight integration instead. [5]"]),
        ("property-flags-relationship", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <relationship name="a" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other" spotlightIndexingEnabled="YES"/>
        <relationship name="b" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other" storedInTruthFile="YES"/>
        <relationship name="c" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="Other" spotlightIndexingEnabled="YES"/>
    </entity>
    <entity name="Other" representedClassName="Other" syncable="YES">
    </entity>
</model>
"""#, "0aba0755cf0f2e4d085547f8f901ca1f21c2aaddf671030662d07d71e9b2214f", "112dd079d842df35a059a7ed7e25a065d0cd873af65a4a343dac9f10a8124bf8",
         ["Item.a should have an inverse [2]", "Item.b is set to be stored using a Spotlight external record file, which is deprecated. Use Core Spotlight integration instead. [5]", "Item.b should have an inverse [2]", "Item.c does not have an inverse; this is an advanced setting (no object can be in multiple destinations for a specific relationship) [7]"]),
        ("property-flags-transient", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <attribute name="a" optional="YES" transient="YES" spotlightIndexingEnabled="YES" storedInTruthFile="YES" allowsCloudEncryption="YES" attributeType="String"/>
    </entity>
</model>
"""#, "e0869bee6c6f3ec9b27cc9685531f6a4c9a962b74367515a66542fa9b1ebc548", "fde795cebfd58c6ebbda9f85abb8d777365071851df45fa1788017df5193b908",
         ["Item.a is set to be stored using a Spotlight external record file, which is deprecated. Use Core Spotlight integration instead. [5]"]),
        ("regular-expression", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <attribute name="a" optional="YES" regularExpressionString="x+" attributeType="String"/>
        <attribute name="b" optional="YES" regularExpressionString="y+" attributeType="String"/>
        <attribute name="c" optional="YES" regularExpressionString="z+" minValueString="1" attributeType="String"/>
        <attribute name="d" optional="YES" regularExpressionString="x+" elementID="old" attributeType="String"/>
        <attribute name="e" optional="YES" attributeType="String" regularExpressionString="q+" elementID="old2" minValueString="3"><userInfo><entry key="k" value="v"/></userInfo></attribute>
        <attribute name="f" optional="YES" attributeType="String"/>
    </entity>
</model>
"""#, "bf8f76e59ab9b99aa26a0449bfe97265bfbaa21ba9a21ce67f38c8c7786e23a5", "88ce8ac3d88438674c1ce4a2cf6f9a8cfaae82ebacf6c0d820f7426e89f08c85",
         []),
        ("user-info-validation", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <attribute name="a" optional="YES" attributeType="String" minValueString="1" maxValueString="2"><userInfo><entry key="k" value="v"/></userInfo></attribute>
    </entity>
</model>
"""#, "6f14125c03e3e50715cc5ae4162ef870fa2d5b7585e09dddbd503701a3fb623e", "3c43b91660333168c2f70e3787c8c7e6321aebcd7e71fff928a16ad09b01de9c",
         []),
        ("modifier-attribute", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <attribute name="a" optional="YES" versionHashModifier="3" attributeType="String"/>
    </entity>
</model>
"""#, "5bffd801ddc2334076c7686c58da733a110735dfb63e4eeac7d6df6c8128f4ce", "a4abfc4f3dc26ea9323dc19a0450a9b9f61cabc2c8dfa6333670f53b533a2dd6",
         []),
        ("modifier-relationship", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other" versionHashModifier="3"/>
    </entity>
    <entity name="Other" representedClassName="Other" syncable="YES">
    </entity>
</model>
"""#, "bcfaee4aa0c5f90fad04ba5d8e3351a3da0cfd1422a80e3c1716c17fd7e06678", "80a220849ee41795d2293629cae05901c971656d484398799b60e2a091d2d953",
         ["Item.o should have an inverse [2]"]),
        ("modifier-strings", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <attribute name="a" optional="YES" versionHashModifier="vhm" elementID="old" defaultValueString="def" valueTransformerName="tr" attributeType="String"/>
    </entity>
</model>
"""#, "d03ac3bf56122b9504800c2621a2180ab7604a99638f9769ba77979133a74a10", "cbc31b43fb84dc4221c7c0a6d832ef7a0998ab13651cc5d5faa93b2ec764d03f",
         []),
        ("relationship-user-info", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other"><userInfo><entry key="k" value="v"/></userInfo></relationship>
    </entity>
    <entity name="Other" representedClassName="Other" syncable="YES">
    </entity>
</model>
"""#, "047751b66181296164a30e1cd5197c5afeb91e8fd473ab9b4d2e6df0569d93c5", "ffdd3433e119b36e7cc52d8d025ccd00eb1f3c9bb0f4000f8125fdbd25d26a4b",
         ["Item.o should have an inverse [2]"]),
        ("relationship-indexed", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other" indexed="YES"/>
    </entity>
    <entity name="Other" representedClassName="Other" syncable="YES">
    </entity>
</model>
"""#, "626b028c921a59e90b639690f73c14134e76f5ed8ed469d2e6b2c93b73536c1d", "5b9553c54bbd60561032abbf868a0638d23cfe21a9e936b90b7ad9db5f5ac45a",
         ["Item.o should have an inverse [2]"]),
        ("own-inverse", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
        <relationship name="s" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Item" inverseName="s" inverseEntity="Item"/>
    </entity>
</model>
"""#, "a1adab64b7ffd45ebc0b4ee879c10bd5a89b02894034c14bc63b49c71d68e45f", "ac747204bf398f87f6e82a56b6560a6d2801737ed60852d803a7d786b3c0d4ef",
         []),
        ("same-name-inverse", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="A" representedClassName="A" syncable="YES">
        <relationship name="x" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="B" inverseName="x" inverseEntity="B"/>
    </entity>
    <entity name="B" representedClassName="B" syncable="YES">
        <relationship name="x" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A" inverseName="x" inverseEntity="A"/>
    </entity>
</model>
"""#, "922931ee99ea5b4bdb7b3bef03509e15034eaeaa6b645dedfe8669b6de563ab0", "13663286876670b5b783a8599005b065dc1023e9b08eba718aa9e51c82e6cc5e",
         []),
        ("inverse-without", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="A" representedClassName="A" syncable="YES">
        <relationship name="b" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="B" inverseName="a" inverseEntity="B"/>
    </entity>
    <entity name="B" representedClassName="B" syncable="YES">
        <relationship name="a" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A"/>
    </entity>
</model>
"""#, "9067be0fa14380612963dd0fcbf0e963fcf5c9201bb77c47b4707f3be0b813f1", "332c3052721a64e2f99f21740e1b5f40610fc30df781b82adfb8874004d2b8ec",
         ["The inverse relationship for A.b does not reciprocate an inverse relationship [2]", "B.a should have an inverse [2]"]),
        ("inverse-missing", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="A" representedClassName="A" syncable="YES">
        <relationship name="b" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="B" inverseName="zzz" inverseEntity="B"/>
    </entity>
    <entity name="B" representedClassName="B" syncable="YES">
    </entity>
</model>
"""#, "df30da40d76354d43387980ef11b5658b7a01b7e974407b5244b170340661944", "a38c33069ab4cc0e72e13b4e8e1ae8766f0c6e52377f4ef16bfb6bf2771d836c",
         ["A.b should have an inverse [2]"]),
        ("inverse-attribute", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="A" representedClassName="A" syncable="YES">
        <relationship name="b" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="B" inverseName="n" inverseEntity="B"/>
    </entity>
    <entity name="B" representedClassName="B" syncable="YES">
        <attribute name="n" optional="YES" attributeType="String"/>
    </entity>
</model>
"""#, "7dad253f6775593f1d7a5821b65c7b0dabe5b6504539b1916436a1853e9b76c7", "be4877303146f96d686f18519ff1ed411d37ffefc2186283c6f87e161912da71",
         ["A.b should have an inverse [2]"]),
        ("inverse-inherited", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="A" representedClassName="A" syncable="YES">
        <relationship name="s" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Sub" inverseName="a" inverseEntity="Base"/>
    </entity>
    <entity name="Base" representedClassName="Base" syncable="YES">
        <relationship name="a" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A" inverseName="s" inverseEntity="A"/>
    </entity>
    <entity name="Sub" representedClassName="Sub" parentEntity="Base" syncable="YES">
    </entity>
</model>
"""#, "e477516afa6cbc59c9dcb429ee4b0f48566e927effae531b236c71839db394c0", "d4d2b073507f203d9264c4fc385076568dbcba679f52a5bebdd0260041768b6c",
         []),
        ("subentities-8", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
    </entity>
    <entity name="BuyableItem" representedClassName="BuyableItem" parentEntity="Item" syncable="YES">
    </entity>
    <entity name="Egg" representedClassName="Egg" parentEntity="BuyableItem" syncable="YES">
    </entity>
    <entity name="Food" representedClassName="Food" parentEntity="BuyableItem" syncable="YES">
    </entity>
    <entity name="Quest" representedClassName="Quest" parentEntity="BuyableItem" syncable="YES">
    </entity>
    <entity name="MetaReward" representedClassName="MetaReward" syncable="YES">
    </entity>
    <entity name="InAppReward" representedClassName="InAppReward" parentEntity="MetaReward" syncable="YES">
    </entity>
    <entity name="Reward" representedClassName="Reward" parentEntity="MetaReward" syncable="YES">
    </entity>
</model>
"""#, "e1d835181dbc69c41616cddeeb404a7d9c7a79b010a65068195ed9650d4d7864", "17dda4ec84413876e37ef0d1c0f29545fc8c28008e1345da0b429fbbd3fce881",
         []),
        ("subentities-9", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES">
    </entity>
    <entity name="BuyableItem" representedClassName="BuyableItem" parentEntity="Item" syncable="YES">
    </entity>
    <entity name="Egg" representedClassName="Egg" parentEntity="BuyableItem" syncable="YES">
    </entity>
    <entity name="Food" representedClassName="Food" parentEntity="BuyableItem" syncable="YES">
    </entity>
    <entity name="Quest" representedClassName="Quest" parentEntity="BuyableItem" syncable="YES">
    </entity>
    <entity name="HatchingPotion" representedClassName="HatchingPotion" parentEntity="Item" syncable="YES">
    </entity>
    <entity name="MetaReward" representedClassName="MetaReward" syncable="YES">
    </entity>
    <entity name="InAppReward" representedClassName="InAppReward" parentEntity="MetaReward" syncable="YES">
    </entity>
    <entity name="Reward" representedClassName="Reward" parentEntity="MetaReward" syncable="YES">
    </entity>
</model>
"""#, "7fe60bacb88e6509e128338dc4f4cc937a2a1059147e5f3a9d09abd82a637656", "772171ed038c1da39d57ca6c6aab6fe75291072783ecb5515e08306f4619ca4a",
         []),
        ("sibling-keys-two", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Base" representedClassName="Base" syncable="YES">
    </entity>
    <entity name="A" representedClassName="A" parentEntity="Base" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U"/>
    </entity>
    <entity name="B" representedClassName="B" parentEntity="Base" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U"/>
    </entity>
    <entity name="U" representedClassName="U" syncable="YES">
    </entity>
</model>
"""#, "54718634afad83deb20341b85182584783de434b3ae8546f1570933fbe17ee68", "a0a80f9848f4f026ae2371c83dd2cc194d04497bc847ae9b3e16e928bfae0d78",
         ["A.user should have an inverse [2]", "B.user should have an inverse [2]"]),
        ("sibling-keys-three", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Base" representedClassName="Base" syncable="YES">
    </entity>
    <entity name="A" representedClassName="A" parentEntity="Base" syncable="YES">
    </entity>
    <entity name="A1" representedClassName="A1" parentEntity="A" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U"/>
    </entity>
    <entity name="B" representedClassName="B" parentEntity="Base" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U"/>
    </entity>
    <entity name="C" representedClassName="C" parentEntity="Base" syncable="YES">
    </entity>
    <entity name="C1" representedClassName="C1" parentEntity="C" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U"/>
    </entity>
    <entity name="U" representedClassName="U" syncable="YES">
    </entity>
</model>
"""#, "99f8542f9494cb894bdf8805d7d380efc887ba2b6edba4bd32d220f1ec99b02c", "c2aa80a7a124eb2739481e5c9c7ca61d0c7cf6d4046db0d894b24d9299c05261",
         ["A1.user should have an inverse [2]", "B.user should have an inverse [2]", "C1.user should have an inverse [2]"]),
        ("sibling-keys-case", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Base" representedClassName="Base" syncable="YES">
    </entity>
    <entity name="A" representedClassName="A" parentEntity="Base" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U"/>
    </entity>
    <entity name="B" representedClassName="B" parentEntity="Base" syncable="YES">
        <relationship name="USER" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U"/>
    </entity>
    <entity name="U" representedClassName="U" syncable="YES">
    </entity>
</model>
"""#, "d1ff93b3935c527cbef403836e9522ad0e3bed9a7afa668164529651647287ec", "1a79494b303655ab06a8f49154d6f56a3681d1ac2fe654a04c34adb7ec196500",
         ["A.user should have an inverse [2]", "B.USER should have an inverse [2]"]),
        ("sibling-keys-destination", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Base" representedClassName="Base" syncable="YES">
    </entity>
    <entity name="A" representedClassName="A" parentEntity="Base" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U"/>
    </entity>
    <entity name="B" representedClassName="B" parentEntity="Base" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U"/>
    </entity>
    <entity name="U" representedClassName="U" syncable="YES">
    </entity>
    <entity name="U2" representedClassName="U2" parentEntity="U" syncable="YES">
    </entity>
</model>
"""#, "48da50bd89e098184cb6bf6a685a0a4e3108cca054b41984976366b3dfa200c6", "0232953ff93e969f2841d386b3cefea12f3cab2e4c54cebd1369021ec5de6c0a",
         ["A.user should have an inverse [2]", "B.user should have an inverse [2]"]),
        ("sibling-keys-ordered", #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Base" representedClassName="Base" syncable="YES">
    </entity>
    <entity name="A" representedClassName="A" parentEntity="Base" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U" inverseName="as" inverseEntity="U"/>
    </entity>
    <entity name="B" representedClassName="B" parentEntity="Base" syncable="YES">
        <relationship name="user" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="U" inverseName="bs" inverseEntity="U"/>
    </entity>
    <entity name="U" representedClassName="U" syncable="YES">
        <relationship name="as" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="A" inverseName="user" inverseEntity="A"/>
        <relationship name="bs" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="B" inverseName="user" inverseEntity="B"/>
    </entity>
</model>
"""#, "ac54afd985d3b6d7b2da6d645e6fdf0d442fc427e9eadc1fe9e1f259160908d6", "9a95760f04ec43741c9f0e1536cae102f16052a8bef19aede3152c3857884d6e",
         []),
    ]

    static let work = NSTemporaryDirectory() + "nomac-surveyed-features-\(getpid())"
    static let current = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>_XCCurrentVersionName</key><string>Model.xcdatamodel</string></dict></plist>"#

    func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    @Test(arguments: Self.models.map(\.name))
    func matchesMomc(_ name: String) throws {
        let model = Self.models.first { $0.name == name }!
        let plain = "\(Self.work)/\(name)/Model.xcdatamodel"
        try FileSystem.write(Data(model.contents.utf8), to: plain + "/contents")
        let compiled = try ModelCompiler.compile(plain, module: "T")
        #expect(hex(SHA256.digest(compiled.files[0].contents)) == model.mom)
        #expect(compiled.diagnostics.map { String($0[$0.range(of: ": warning: ")!.upperBound...]) } == model.warnings)
        let versioned = "\(Self.work)/\(name)/Model.xcdatamodeld"
        try FileSystem.write(Data(model.contents.utf8), to: versioned + "/Model.xcdatamodel/contents")
        try FileSystem.write(Data(Self.current.utf8), to: versioned + "/.xccurrentversion")
        let files = try ModelCompiler.compile(versioned, module: "T").files
        #expect(hex(SHA256.digest(files.first { $0.path.hasSuffix(".omo") }!.contents)) == model.omo)
    }

    /// momc's order of versions at the sizes where the copy of its table moves them
    /// (coredata-experiments `versions-*`, at the paths they were compiled at).
    @Test(arguments: [(7, ["V0", "V4", "V5", "V1", "V2", "V6", "V3"]),
                      (12, ["V5", "V11", "V9", "V0", "V10", "V4", "V3", "V8", "V7", "V2", "V1", "V6"])])
    func compilesVersionsInTheOrderOfACopiedTable(_ count: Int, _ order: [String]) throws {
        let path = "\(ModelCompilerTests.work)/versions-\(count)/Model.xcdatamodeld"
        try? FileManager.default.removeItem(atPath: path)
        let model = Self.models[0].contents
        for version in order {
            try FileSystem.write(Data(model.utf8), to: "\(path)/\(version).xcdatamodel/contents")
        }
        let notes = try ModelCompiler.compile(path, module: "T").diagnostics.filter { $0.contains(": note: ") }
        #expect(notes.map { String($0[..<$0.range(of: ".xcdatamodel")!.lowerBound]) } == order)
    }

    /// A warning of several versions is printed for each (coredata-experiments `warn-repeated`).
    @Test func repeatsWarningsOfSeveralVersions() throws {
        let path = "\(Self.work)/warn-repeated/Model.xcdatamodeld"
        let model = Self.models.first { $0.name == "inverse-missing" }!.contents
        for version in ["Model", "Model 2"] {
            try FileSystem.write(Data(model.utf8), to: "\(path)/\(version).xcdatamodel/contents")
        }
        let warnings = try ModelCompiler.compile(path, module: "T").diagnostics.filter { $0.contains(": warning: A.b should have an inverse") }
        #expect(warnings.count == 2)
    }

    /// `NSDecimalNumber(string:)` and `description`, as momc's `.mom` and `.omo` show them
    /// (coredata-experiments `decimal-defaults`).
    @Test(arguments: [("0.0", "0"), ("-0.0", "0"), ("1.50", "1.5"), ("100", "100"), ("1e3", "1000"), ("1E-2", "0.01"), ("abc", "NaN"), ("", "NaN"),
                      ("-1.5", "-1.5"), ("12abc", "12"), ("1,5", "1"), ("1.2.3", "1.2"), (" 1", "1"), (".5", "0.5"), ("0.000001", "0.000001"),
                      ("123456789012345678901234567890", "123456789012345678901234567890")])
    func describesDecimals(_ text: String, _ description: String) throws {
        #expect(try ArchivedDecimal.defaultValue(text, context: nil, location: "").description == description)
    }

    /// What needs rounding, and zero with an exponent, are not observed.
    @Test(arguments: ["0e3", "1e100", "123456789012345678901234567890123456789012"])
    func refusesUnobservedDecimals(_ text: String) {
        #expect { _ = try ArchivedDecimal.defaultValue(text, context: nil, location: "") } throws: { "\($0)".contains("B-257") }
    }

    /// Without `sourceLanguage` a model generates Swift, and without a current version its only
    /// version does (coredata-experiments `no-language`, `versioned-one-no-current`).
    @Test func generatesSwiftWithoutASourceLanguage() throws {
        let path = "\(Self.work)/no-language/Model.xcdatamodeld"
        let head = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" userDefinedModelVersionIdentifier="">"#
        try FileSystem.write(Data((head + #"<entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class"/></model>"#).utf8), to: path + "/Model.xcdatamodel/contents")
        #expect(try ModelCompiler.generatedFiles(path, destination: "/d") == ["/d/Item+CoreDataClass.swift", "/d/Item+CoreDataProperties.swift", "/d/Model+CoreDataModel.swift"])
    }

    func generated(_ name: String, _ entities: String) throws -> [String: String] {
        let path = "\(Self.work)/generated-\(name)/\(name).xcdatamodel"
        let head = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">"#
        try FileSystem.write(Data((head + entities + "</model>").utf8), to: path + "/contents")
        let files = try CodeGenerator.files(path, swiftVersion: "5.0", author: CodeGenerator.Author(name: "", date: Date(timeIntervalSince1970: 0)))
        return Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0.contents) })
    }

    /// The input's name keeps only its letters in the model file's typealiases; class names keep
    /// theirs whole (coredata-experiments `model-names`).
    @Test(arguments: [("lil_wallet", "lilwallet"), ("A-B", "AB"), ("Technex18", "Technex"), ("a+b", "ab")])
    func modelTypealiasesKeepLetters(_ name: String, _ letters: String) throws {
        let files = try generated(name, #"<entity name="Item" representedClassName="My_Item2" syncable="YES" codeGenerationType="class"/>"#)
        #expect(files["\(name)+CoreDataModel.swift"]?.contains("public typealias \(letters)FoundationFrameworkSet = NSSet") == true)
        #expect(files["My_Item2+CoreDataClass.swift"]?.contains("public typealias My_Item2CoreDataClassSet = NSSet") == true)
    }

    /// A class of the current module has no `@objc` name, and a transformable's module is imported
    /// (coredata-experiments `class-in-module`, `transformable-module`).
    @Test func classesAndTransformablesOfModules() throws {
        let inModule = try generated("Inside", #"<entity name="Item" representedClassName=".Item" syncable="YES" codeGenerationType="class"/>"#)
        #expect(inModule["Item+CoreDataClass.swift"]?.contains("@objc") == false)
        let colored = try generated("Colored", #"<entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class"><attribute name="c" optional="YES" attributeType="Transformable" valueTransformerName="V" customClassName="UIKit.UIColor"/></entity>"#)
        let properties = colored["Item+CoreDataProperties.swift"]
        #expect(properties?.contains("import UIKit\n") == true)
        #expect(properties?.contains("public var c: UIColor?") == true)
    }
}
