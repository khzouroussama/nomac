import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for a collection view's section header and footer views
/// (`.github/scripts/nib_experiments.py` round 115, `sb-cvc-section-*`): sizes and SHA-256 digests
/// of Xcode's view nibs.
@Suite struct CollectionSectionViewTests {
    typealias V = CollectionViewControllerTests

    static func view(_ key: String = "sectionFooterView", id: String = "sfv-aa-aa1", reuse: String? = "Footer", y: Int = 128, content: String = "", attributes: String = "") -> String {
        "<collectionReusableView key=\"\(key)\" opaque=\"NO\" clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"center\""
            + (reuse.map { " reuseIdentifier=\"\($0)\"" } ?? "") + "\(attributes) id=\"\(id)\">\n<rect key=\"frame\" x=\"0.0\" y=\"\(y)\" width=\"393\" height=\"50\"/>\n"
            + #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n\(content)</collectionReusableView>\n"
    }

    static let label = "<subviews>\n" + #"<label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" "#
        + #"baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="sfl-aa-aa1">"# + "\n"
        + #"<rect key="frame" x="10" y="10" width="42" height="21"/>"# + "\n" + #"<fontDescription key="fontDescription" type="system" pointSize="17"/>"# + "\n"
        + #"<nil key="textColor"/>"# + "\n" + #"<nil key="highlightedColor"/>"# + "\n</label>\n</subviews>\n"
    static let constraints = "<constraints>\n"
        + #"<constraint firstItem="sfl-aa-aa1" firstAttribute="leading" secondItem="sfv-aa-aa1" secondAttribute="leading" constant="10" id="sfc-aa-aa1"/>"# + "\n"
        + #"<constraint firstItem="sfl-aa-aa1" firstAttribute="top" secondItem="sfv-aa-aa1" secondAttribute="top" constant="10" id="sfc-aa-aa2"/>"# + "\n</constraints>\n"
    static let custom = #" customClass="Footer" customModule="T" customModuleProvider="target""#
    static let outlet = "<connections>\n" + #"<outlet property="owner" destination="cvc-aa-aaa" id="sfo-aa-aa1"/>"# + "\n</connections>\n"

    static func document(_ views: String...) -> String {
        NavigationTests.storyboard(initial: "cvc-aa-aaa", V.scene(V.cell.replacingOccurrences(of: "</cells>\n", with: "</cells>\n" + views.joined())))
    }

    static let cases: [(String, String, Int, String)] = [
        ("sb-cvc-section-footer", document(view()), 3692, "c21b812ee4008d41b1161c5ac85b3eaa9273f6d49ea36b769cb606178401ff5a"),
        ("sb-cvc-section-footer-constraints", document(view(content: label + constraints)), 5068, "1d816f6b7a41dd0ee8856faffa2ceeea8d1acc58778f1a28d33f677a56ec2eec"),
        ("sb-cvc-section-header-footer", document(view("sectionHeaderView", id: "shv-aa-aa1", reuse: "Header", y: 0), view()), 4639, "bfd16a1154645b4ad7b707b67f4bf944f01a369d70bf8bc630ff4dc29bf13ed6"),
        ("sb-cvc-section-footer-outlet", document(view(content: outlet, attributes: custom)), 3937, "bb28e460851c6ab94548dd6a7174321cbc31c3b4e26bb8ce1e7431bf3e0d7d8a"),
    ]

    /// Each a nib of its own in the supplementary view dictionaries, between and after the cells',
    /// the footer first; an outlet to the controller through the nib's own upstream placeholder.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled[V.viewNib], "\(name)")
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }

    /// ibtool warns about a section view without a reuse identifier and drops it.
    @Test func withoutAReuseIdentifierWarnsAndDrops() throws {
        let document = Self.document(Self.view(reuse: nil))
        let compiled = try StoryboardCompiler.compileReportingWarnings(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        #expect(compiled.warnings == ["/tmp/Main.storyboard:sfv-aa-aa1: warning: Prototype collection view section header or footer views must have reuse identifiers [9]"])
        let plain = try StoryboardCompiler.compile(Data(Self.document().utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        #expect(compiled.files[V.viewNib] == plain[V.viewNib])
    }

    /// ibtool fails on two section views of one reuse identifier.
    @Test func refusesOneReuseIdentifierForTwoViews() {
        let document = Self.document(Self.view("sectionHeaderView", id: "shv-aa-aa1", reuse: "Same", y: 0), Self.view(reuse: "Same"))
        #expect(throws: NomacError("nomac does not compile section views of one reuse identifier (ibtool fails) yet (BACKLOG B-260)", path: "/tmp/Main.storyboard")) {
            try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        }
    }
}
