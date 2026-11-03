import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for table views in xibs (`.github/scripts/nib_experiments.py`
/// round 29, `table_xib`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct TableViewTests {
    static let attributes = #"clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" translatesAutoresizingMaskIntoConstraints="NO""#
    static let grouped = attributes.replacingOccurrences(of: #"style="plain""#, with: #"style="grouped""#).replacingOccurrences(of: #""28""#, with: #""18""#)
    static let outlets = "<connections>\n<outlet property=\"dataSource\" destination=\"-1\" id=\"tds-aa-aaa\"/>\n"
        + "<outlet property=\"delegate\" destination=\"-1\" id=\"tdl-aa-aaa\"/>\n</connections>\n"
    static let custom = #" customClass="ListView" customModule="T" customModuleProvider="target""#

    static func tableXIB(_ attributes: String = attributes, extra: String = "", custom: String = "") -> String {
        let table = "<tableView \(attributes)\(custom) id=\"tbl-aa-aaa\">\n<rect key=\"frame\" x=\"0.0\" y=\"0.0\" width=\"393\" height=\"852\"/>\n\(extra)</tableView>\n"
        return ConstraintTests.constrained(table, ConstraintTests.edges.enumerated().map {
            ConstraintTests.constraint($0.offset, "tbl-aa-aaa", $0.element, ConstraintTests.root, $0.element)
        }.joined())
    }

    static let white = XIBCompilerTests.gray("1", "1") + "\n"
    static let cases: [(String, String, Int, String)] = [
        ("table-plain", tableXIB(), 1844, "3db627e8b985e9f9786bba45e0c0ae54def8fd715ebaa0afd182da98949c8b5a"),
        ("table-grouped-outlets-custom", tableXIB(grouped, extra: outlets, custom: custom), 2378, "467fabaf11d3ad5ad600b1ec8fc6cf26ebe9796469f225df510105f520a52979"),
        ("table-inset-grouped", tableXIB(grouped.replacingOccurrences(of: #"style="grouped""#, with: #"style="insetGrouped""#)),
         2145, "6b2eb5c1a180dd529c543e3f0373872941d31d595dd65e9be0f1a43d89b5fdf5"),
        ("table-separator-none", tableXIB(attributes.replacingOccurrences(of: #"separatorStyle="default""#, with: #"separatorStyle="none""#)),
         1824, "50673b8416e16cedb0dc0083b05f48dd98bcae65a551c4e9890a8171a04bea71"),
        ("table-no-estimated", tableXIB(attributes.replacingOccurrences(of: #" estimatedRowHeight="-1""#, with: "")),
         1844, "a2dd3cb5d9360b73916cddc701b08abf5f43b9b25ed49366b2aab1e5d22dcf13"),
        ("table-keyboard-drag", tableXIB(attributes + #" keyboardDismissMode="onDrag""#), 1869, "9e9767ce945a251938ec848d08ddd68622f7e864dfe424f8b667033fd76c6fe3"),
        ("table-background-white", tableXIB(extra: white), 2026, "5f2443d166d849b78bbafe97f72ab9d985d9ff1157efdb00b5ea2e6e22c4aaf3"),
        ("table-background-white-system", tableXIB(extra: XIBCompilerTests.system("systemBackgroundColor") + "\n"),
         2026, "5f2443d166d849b78bbafe97f72ab9d985d9ff1157efdb00b5ea2e6e22c4aaf3"),
        ("table-grouped-background-white", tableXIB(grouped, extra: white), 2016, "1583220cfcafce84dc54f64fdc431157528398dc7d3860838256a8e8b025cf89"),
        ("table-scroll-disabled", tableXIB(attributes + #" scrollEnabled="NO""#), 1863, "704131b540b09fad62fdb243842b13db49499d0c551e72e50961555ec6eb6aa9"),
    ]

    /// The scroll view's and the table's keys; grouped tables get `systemGroupedBackgroundColor`, a
    /// plain one's white background is named `tableBackgroundColor`.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
