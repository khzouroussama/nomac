import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for user-defined runtime attributes of cells and their content
/// views, of bar button items and navigation bars, and of the point, rect, range, nil and localized
/// string types (`.github/scripts/nib_experiments.py` rounds 100 and 101): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct RuntimeAttributeHolderTests {
    typealias R = RuntimeAttributeTests

    static let name = R.attribute("name", "string", value: "Card")
    static func typed(_ attribute: String) -> String { R.xib(R.withRuntime(R.runtime(attribute))) }

    static let cases: [(String, String, Int, String)] = [
        ("udra-tv-cell", CellTests.cellXIB("", cellExtra: R.runtime(R.radius)), 1534, "2ba16fb058e41f1b252814fc4784e7270e1604030d67e764344a9894c44e0370"),
        ("udra-tv-cell-two", CellTests.cellXIB("", cellExtra: R.runtime(R.radius, name)), 1581, "ea3ccda837c850a3b8c850a1700588ac58a2169703cdcd20b80a28c6af7823d1"),
        ("udra-tv-content", CellTests.cellXIB("", content: R.runtime(R.radius)), 1534, "1369a0617a0ea91f089ee8ae255d6c5980c4b376d0645895364e9d99d9ca1239"),
        ("udra-tv-cell-and-content", CellTests.cellXIB("", content: R.runtime(name), cellExtra: R.runtime(R.radius)),
         1581, "97dcc9f82902516e516c1b38e58e45ee6d0f280fe893d5813b6e75fbf9c62fd0"),
        ("udra-cv-cell", CollectionViewCellTests.cellXIB("", R.runtime(R.radius)), 1714, "a89c6c34062dfb541c11eabac41eb8485b647392227250f01e558c4af3c64b6d"),
        ("udra-point", typed(R.attribute("startPoint", "point", child: #"<point key="value" x="0.5" y="0.0"/>"#)),
         1026, "ceb7b10c731f442f6510457623a9b9d1a53639534fdf7453bc7df2550e6bd46a"),
        ("udra-point-whole", typed(R.attribute("startPoint", "point", child: #"<point key="value" x="1" y="2"/>"#)),
         1024, "d38d16048dcf942585bea75ecf9535a4b6361ca8addb0b74dee7f65deccf2e39"),
        ("udra-rect", typed(R.attribute("box", "rect", child: #"<rect key="value" x="1" y="2" width="3" height="4"/>"#)),
         1026, "25d882876d29e6626ea1d6507bebef50bbaf93e74e8f36127622fe10d984abc5"),
        ("udra-range", typed(R.attribute("span", "range", child: #"<range key="value" location="1" length="2"/>"#)),
         1073, "11f95a2c52eb60dca06f5ce08dfcfcb1b595c9dd11066c0e0565346287d1fc2b"),
        ("udra-nil", typed(R.attribute("thing", "nil")), 958, "4726a2308d59e75430baac6ac198563886fa9c8388719886a10fa7247e90a8e5"),
        ("udra-localized", typed(R.attribute("title", "localizedString", value: "Hello")), 973, "9f6e78daf418f670235cbc3a6a3d1e1344f3477d280e5685aafcc8b63748dd70"),
    ]

    /// A cell's pairs as any view's, its content view's too; points and rectangles as strings in
    /// `NSValue`s, a range as its length and location, nil as no value, a localized string outside
    /// `.lproj` folders as a string.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    static let accLabel = R.attribute("accLabelText", "string", value: "Add")
    static func barItem(_ attributes: String...) -> String {
        NavigationTests.barItem("rightBarButtonItem", "add", 1).replacingOccurrences(of: "/>\n", with: ">\n" + attributes.joined() + "</barButtonItem>\n")
    }

    static func navigation(_ bar: String = "", item: String) -> String {
        NavigationTests.storyboard(NavigationTests.navigation().replacingOccurrences(of: "</navigationBar>", with: bar + "</navigationBar>"),
                                   SceneTests.scene(1, afterView: item))
    }

    static let navigationNib = NavigationTests.navigationNib
    static let storyboardCases: [(String, String, Int, String)] = [
        ("sb-udra-bar-item", navigation(item: NavigationTests.item(items: barItem(R.runtime(accLabel)))),
         2095, "a87973840d0b3bfaf73141740fcd505f11b0fd92db6a8d893849e84b5dc7f432"),
        ("sb-udra-bar-item-two", navigation(item: NavigationTests.item(items: barItem(R.runtime(accLabel, R.attribute("accEnabled", "boolean", value: "YES"))))),
         2165, "d7af380b03c6023499510968183c6965a335381db2e38e53e0d3027641b1f348"),
        ("sb-udra-nav-bar", navigation(R.runtime(R.radius), item: ""), 1827, "197ddb86cb6715bf21985b53a2fe12fa8f41e144a37458e34491a42e68906f34"),
    ]

    /// Bar button items' and navigation bars' pairs in the navigation controller's nib; the root's
    /// view nib has none.
    @Test(arguments: storyboardCases)
    func compilesNavigationAsXcode(name: String, document: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let nib = try #require(compiled[Self.navigationNib], "\(name)")
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
        #expect(compiled["vc1-aa-aaa-view-vw1-aa-aaa.nib"].map(VariationTests.digest) == "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a", "\(name)")
    }
}
