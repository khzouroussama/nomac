import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacAssets

/// Self-written data catalogs and the outputs Xcode 27.0's actool writes for them, recorded as
/// observed facts by `assets-experiments data` and `colors`.
@Suite struct DataCatalogTests {
    static func dataSet(_ catalog: String, _ name: String, _ filename: String, _ content: [UInt8], type: String? = nil) throws {
        var item: [String: Any] = ["filename": filename, "idiom": "universal"]
        item["universal-type-identifier"] = type
        let contents: [String: Any] = ["data": [item], "info": ["author": "xcode", "version": 1]]
        try FileSystem.write(Data(content), to: "\(catalog)/\(name).dataset/\(filename)")
        try FileSystem.write(try JSONSerialization.data(withJSONObject: contents), to: "\(catalog)/\(name).dataset/Contents.json")
    }

    /// 25,000 bytes: data sets are stored as they are, without compression.
    static var bigData: [UInt8] {
        let varied: [UInt8] = (0..<5000).map { (index: Int) -> UInt8 in UInt8((index * 7 + index / 3) & 0xFF) }
        return varied + [UInt8](repeating: UInt8(ascii: "A"), count: 20000)
    }

    @Test func dataOnly() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.dataSet(catalog, "Small", "blob.txt", Array("hello".utf8))
        try Self.dataSet(catalog, "Big", "big.bin", Self.bigData)
        try Self.dataSet(catalog, "Json", "data.json", Array(#"{"a": [1, 2, 3]}"#.utf8), type: "public.json")
        _ = try ColorCatalogTests.compile(catalog, in: temporary.path + "/out")
        let car = try ColorCatalogTests.car(temporary.path + "/out")
        #expect(car.count == 39752)
        #expect(ColorCatalogTests.hex(SHA256.digest(car)) == "ccad27d5a3f3fe049a28d770463237aaee8a84518e6225f85ad46c716ae3c265")
    }

    /// Data next to colors in folders with and without a namespace.
    @Test func dataAndColors() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        let red = [ColorCatalogTests.entry(ColorCatalogTests.rgb("1.000", "0.000", "0.000"))]
        try ColorCatalogTests.writeCatalog(catalog, ["Red": red])
        try ColorCatalogTests.writeCatalog(catalog + "/G", ["Blue": red])
        try ColorCatalogTests.writeCatalog(catalog + "/F", ["Red": red])
        let namespace: [String: Any] = ["info": ["author": "xcode", "version": 1], "properties": ["provides-namespace": true]]
        try FileSystem.write(try JSONSerialization.data(withJSONObject: namespace), to: catalog + "/F/Contents.json")
        try Self.dataSet(catalog, "Hello", "blob.txt", Array("hello".utf8))
        _ = try ColorCatalogTests.compile(catalog, in: temporary.path + "/out")
        let car = try ColorCatalogTests.car(temporary.path + "/out")
        #expect(car.count == 19336)
        #expect(ColorCatalogTests.hex(SHA256.digest(car)) == "69bcc395218b5a4797d517343d1355f0a93870b9a78170964a2e0cef2303841c")
    }

    /// The appearance keys list only the appearances renditions use.
    @Test func darkOnlyColor() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        let dark: [String: Any] = ["appearances": [["appearance": "luminosity", "value": "dark"]]]
        try ColorCatalogTests.writeCatalog(catalog, ["D": [ColorCatalogTests.entry(ColorCatalogTests.rgb("1.000", "0.000", "0.000"), dark)]])
        _ = try ColorCatalogTests.compile(catalog, in: temporary.path + "/out")
        let car = try ColorCatalogTests.car(temporary.path + "/out")
        #expect(ColorCatalogTests.hex(SHA256.digest(car)) == "9ac017b3d8ef7b05910f81d00376ad4f8f17cfe27ecc430f6e72b3ccd79e12f1")
    }

    @Test func sameNameForTwoAssetTypesIsAnError() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, ["Red": [ColorCatalogTests.entry(ColorCatalogTests.rgb("1.000", "0.000", "0.000"))]])
        try Self.dataSet(catalog, "Red", "blob.txt", Array("hello".utf8))
        #expect(throws: NomacError.self) { try ColorCatalogTests.compile(catalog, in: temporary.path + "/out") }
    }

    /// An extension macOS does not know gets a dynamic type identifier (`dynamic-identifiers`).
    @Test func unknownExtensionCompiles() throws {
        let temporary = try TemporaryDirectory()
        let catalog = temporary.path + "/A.xcassets"
        try ColorCatalogTests.writeCatalog(catalog, [:])
        try Self.dataSet(catalog, "D", "f.xyzzy", [1])
        #expect(try ColorCatalogTests.compile(catalog, in: temporary.path + "/out").failed == false)
    }
}
