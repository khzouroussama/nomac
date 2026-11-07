import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// The order of a nib's key-value pairs beside size class masks (`.github/scripts/nib_experiments.py`
/// round 143, `mask-pairs-*`): what a default mask excludes from a view is counted after what the view
/// lists, which attributed siblings place in the decimal order of the numbers.
@Suite struct MaskPairOrderTests {
    static let style = "<userDefinedRuntimeAttributes>\n<userDefinedRuntimeAttribute type=\"string\" keyPath=\"styleName\" value=\"S\"/>\n</userDefinedRuntimeAttributes>\n"
    static let point = #"<point key="canvasLocation""#

    static func variation(_ key: String, _ kind: String, _ verb: String, _ references: [String]) -> String {
        "<variation key=\"\(key)\">\n<mask key=\"\(kind)\">\n" + references.map { "<\(verb) reference=\"\($0)\"/>\n" }.joined() + "</mask>\n</variation>\n"
    }

    static func constraintIDs(_ numbers: Range<Int>) -> [String] {
        numbers.map { "c\(String(format: "%02d", $0))-aa-aaa" }
    }

    static func sizeClassMasks(_ excluded: [String]) -> String {
        excluded.isEmpty ? "" : variation("default", "constraints", "exclude", excluded) + variation("heightClass=compact", "constraints", "include", excluded)
    }

    static func siblingID(_ number: Int) -> String { "sv\(String(format: "%02d", number))-aa-aaa" }

    /// 30 attributed siblings, the first 4 pinned to the root.
    static func siblings(excluded: Int = 0, safeArea: Bool = false, nested: String = "") -> String {
        let subviews = (0..<30).map { number in
            ConstraintTests.subview(siblingID(number)).replacingOccurrences(of: "</view>", with: (number == 10 ? nested : "") + style + "</view>")
        }.joined()
        let pins = (0..<4).map { ConstraintTests.constraint($0, siblingID($0), "top", ConstraintTests.root, "top") }.joined()
        return ConstraintTests.constrained(subviews, pins, safeArea: safeArea)
            .replacingOccurrences(of: point, with: style + sizeClassMasks(constraintIDs(0..<excluded)) + point)
    }

    static func masked(_ key: String, _ kind: String, _ references: [String], nested: String = "") -> String {
        siblings(nested: nested).replacingOccurrences(of: point, with: variation(key, kind, "exclude", references) + point)
    }

    static func compile(_ document: String) throws -> String {
        VariationTests.digest(try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options))
    }

    @Test func rootConstraints() throws {
        #expect(try Self.compile(Self.siblings()) == "5748db295691bc6c93c2279e07a87c2707805d65949ac9bd0cee6746b05f3688")
        #expect(try Self.compile(Self.siblings(excluded: 2)) == "20c8166e4c3e61bc3cc627b002ad63ab6225d0b365b7d77c2ee81f9627dfabce")
        #expect(try Self.compile(Self.siblings(excluded: 3, safeArea: true)) == "db79183d1afa4eebc91c6e0ce640b750e124a4528ccf6aa144c940e26e5a001d")
    }

    /// Only the default size class counts.
    @Test func otherSizeClasses() throws {
        let constraints = Self.constraintIDs(0..<2)
        #expect(try Self.compile(Self.masked("heightClass=regular", "constraints", constraints)) == "719e2f422732bbbf6235628e9db4fa78fb5d52399f002429b6129a365d50eb37")
        #expect(try Self.compile(Self.masked("heightClass=compact", "constraints", constraints)) == "4c054454b2823289aa8af58506ca9e38c31de28624709c064eb6aad384424cbe")
        #expect(try Self.compile(Self.masked("heightClass=regular", "subviews", [Self.siblingID(10), Self.siblingID(11)])) == "cbdbcfe162d8eb0db44b7946222a9d8c2bcbd6f700941546924909186fa8e0b0")
    }

    @Test func excludedSubviews() throws {
        #expect(try Self.compile(Self.masked("default", "subviews", [Self.siblingID(10), Self.siblingID(11)])) == "27c3a7e59404d31e4c4b8709ed061b20c7c8faf95d492565b10b16707df2ca64")
        let nested = "<subviews>\n" + ConstraintTests.subview("nes-aa-aaa", (0, 0, 10, 10)).replacingOccurrences(of: "</view>", with: Self.style + "</view>") + "</subviews>\n"
        #expect(try Self.compile(Self.masked("default", "subviews", [Self.siblingID(10)], nested: nested)) == "344a7938ee106834dc0ea5f60d0fed057ca6e7b3c7e1dca00e677ced08b0953a")
    }

    static func box(_ number: Int, children: Int = 0, pins: String = "", masks: String = "") -> String {
        let inner = (0..<children).map { ConstraintTests.subview("ch\($0)-00-aaa", (0, 0, 10, 10)).replacingOccurrences(of: "</view>", with: style + "</view>") }.joined()
        let body = (inner.isEmpty ? "" : "<subviews>\n\(inner)</subviews>\n") + (pins.isEmpty ? "" : "<constraints>\n\(pins)</constraints>\n") + style + masks
        return ConstraintTests.subview("bx\(number)-aa-aaa", (0, 0, 100, 100)).replacingOccurrences(of: "</view>", with: body + "</view>")
    }

    /// A box of 36 attributed children and three more boxes: a mask on the root does not count for the
    /// children, listed by the first box; one on the first box does not for the other boxes.
    static func tree(onRoot: Int, onInner: Int) -> String {
        let pins = (0..<4).map { ConstraintTests.constraint($0, "bx\($0)-aa-aaa", "top", ConstraintTests.root, "top") }.joined()
        let innerPins = (0..<4).map { ConstraintTests.constraint($0 + 10, "ch\($0)-00-aaa", "top", "bx0-aa-aaa", "top") }.joined()
        let boxes = box(0, children: 36, pins: innerPins, masks: sizeClassMasks(constraintIDs(10..<(10 + onInner)))) + box(1) + box(2) + box(3)
        return ConstraintTests.constrained(boxes, pins).replacingOccurrences(of: point, with: style + sizeClassMasks(constraintIDs(0..<onRoot)) + point)
    }

    @Test func nestedOwners() throws {
        #expect(try Self.compile(Self.tree(onRoot: 2, onInner: 0)) == "bc4c6c2f510124645755cdccda87a91653f35eb77626aa2b63ed9bbe6fd52264")
        #expect(try Self.compile(Self.tree(onRoot: 0, onInner: 2)) == "7b9cdcc1d3e325994a0c00a360c334bf8e4a13e9a103f0506810c3197339336b")
        #expect(try Self.compile(Self.tree(onRoot: 1, onInner: 1)) == "e125e874533315369a41335e9bc156f16c5bed865cb6b644e82e4da5b4f2ef59")
    }
}
