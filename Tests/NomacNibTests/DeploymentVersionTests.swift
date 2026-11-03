import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) does with a document's `<deployment version>` (`.github/scripts/
/// nib_experiments.py` round 58, `document-version-*`, `sb-document-version-*`).
@Suite struct DeploymentVersionTests {
    static let plugIn = #"<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin""#
    static let warning = "/tmp/View.xib:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]"

    static func versioned(_ document: String, _ version: Int) -> String {
        document.replacingOccurrences(of: plugIn, with: "<deployment version=\"\(version)\" identifier=\"iOS\"/>\n" + plugIn)
    }

    static let xib = ConstraintTests.constrained(ConstraintTests.subview(), "")

    /// From 8.0 to 27.0 the nib is the document's without a version; below 5888 (23.0) ibtool warns.
    @Test(arguments: [(2048, true), (4352, true), (5376, true), (5887, true), (5888, false), (6656, false), (6912, false)])
    func writesTheSameNib(version: Int, warns: Bool) throws {
        let plain = try XIBCompiler.compile(Data(Self.xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        let compiled = try XIBCompiler.compileReportingWarnings(Data(Self.versioned(Self.xib, version).utf8), path: "/tmp/View.xib",
                                                               options: XIBCompilerTests.options)
        #expect(compiled.nib == plain, "\(version)")
        #expect(compiled.warnings == (warns ? [Self.warning] : []), "\(version)")
    }

    /// A storyboard warns the same way, for the whole document.
    @Test func warnsInAStoryboard() throws {
        let document = StoryboardCompilerTests.storyboard(StoryboardCompilerTests.scene())
        let compiled = try StoryboardCompiler.compileReportingWarnings(Data(Self.versioned(document, 4352).utf8), path: "/tmp/Main.storyboard",
                                                                       options: StoryboardCompilerTests.options)
        #expect(compiled.warnings == [Self.warning.replacingOccurrences(of: "/tmp/View.xib", with: "/tmp/Main.storyboard")])
    }

    /// Before 8.0 ibtool writes nib bundles (B-263); after 27.0 is not observed.
    @Test func refusesVersionsNotObserved() {
        #expect(throws: NomacError("nomac does not compile documents whose <deployment version=\"1792\"> is before iOS 8.0 (ibtool writes nib bundles) yet (BACKLOG B-263)",
                                   path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(Self.versioned(Self.xib, 1792).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
        #expect(throws: NomacError("nomac does not compile <deployment version=\"6913\"> yet (BACKLOG B-260)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(Self.versioned(Self.xib, 6913).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }
}
