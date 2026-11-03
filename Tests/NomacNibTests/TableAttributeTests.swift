import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for table views' scroll flags, selection, separators and
/// estimated section heights (`.github/scripts/nib_experiments.py` round 68, `table-*`): sizes and
/// SHA-256 digests of Xcode's nibs.
@Suite struct TableAttributeTests {
    static func with(_ attribute: String = "", extra: String = "") -> String {
        TableViewTests.tableXIB(TableViewTests.attributes.replacingOccurrences(of: " translatesAutoresizing", with: attribute + " translatesAutoresizing"), extra: extra)
    }

    static let inset = #"<inset key="separatorInset" minX="15" minY="0.0" maxX="0.0" maxY="0.0"/>"# + "\n"
    static func color(_ key: String, _ white: String) -> String {
        XIBCompilerTests.gray(white, "1").replacingOccurrences(of: "backgroundColor", with: key) + "\n"
    }

    static let cases: [(String, String, Int, String)] = [
        ("table-everything", with(#" scrollEnabled="NO" indicatorStyle="white" showsHorizontalScrollIndicator="NO" bounces="NO" bouncesZoom="NO" "#
                                  + #"canCancelContentTouches="NO" delaysContentTouches="NO" keyboardDismissMode="interactive" allowsSelection="NO" "#
                                  + #"allowsSelectionDuringEditing="YES" allowsMultipleSelection="YES" allowsMultipleSelectionDuringEditing="YES" "#
                                  + #"contentViewInsetsToSafeArea="NO" estimatedSectionHeaderHeight="44""#,
                                  extra: inset + color("separatorColor", "0.5") + color("sectionIndexBackgroundColor", "0.25")),
         2370, "650ea8bfd60c7c964351c21c5ecddd8cc4f4591a69d0a5a415d837d617d26cd9"),
        ("table-separator-etched", TableViewTests.tableXIB(TableViewTests.attributes.replacingOccurrences(of: #"separatorStyle="default""#,
                                                                                                          with: #"separatorStyle="singleLineEtched""#)),
         1876, "95eda925068f34aeda13088424000d01a4adc368d2f6d8429db78defdda3a8ca"),
        ("table-estimated-section-heights", with(#" estimatedSectionHeaderHeight="44" estimatedSectionFooterHeight="12""#), 1844,
         "da25557b238e9947ac027ade347bc326f8ea80c076788de9c34e3138436c82c0"),
        ("table-scroll-flags", with(#" showsHorizontalScrollIndicator="NO" showsVerticalScrollIndicator="NO" bounces="NO" bouncesZoom="NO" "#
                                    + #"canCancelContentTouches="NO" delaysContentTouches="NO""#), 1934, "5e4ff9b1034af46963115925744bb50b44ad005997ff2ed9696dfdcb2cf53776"),
        ("table-vertical-indicator-NO", with(#" showsVerticalScrollIndicator="NO""#), 1844, "3db627e8b985e9f9786bba45e0c0ae54def8fd715ebaa0afd182da98949c8b5a"),
        ("table-multiple-selection", with(#" allowsMultipleSelection="YES" allowsMultipleSelectionDuringEditing="YES""#), 1913,
         "2e13fa1672d29062865a199dc9aca588233e3fa4824a00952f33b895b15bda5d"),
        ("table-separator-inset", with(extra: inset), 1897, "ca27b94fe77e6133bff5c2195a9f74ae1dfe6660e3337984cf22041bb2b33db1"),
        ("table-separator-color", with(extra: color("separatorColor", "0.5")), 1977, "da9bb90ab3d934ed4f05b61c08267214dd9cadb98b50b10af13afba8a6dbd37c"),
    ]

    /// The scroll view's flags in a scroll view's order (no vertical indicator flag), separator
    /// styles, estimated section heights, multiple selection, safe area insets, then the separator
    /// color, section index background and separator inset.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
