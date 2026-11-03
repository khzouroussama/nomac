import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// Colors ibtool converts with ColorSync (`.github/scripts/nib_experiments.py` rounds 23 and 25):
/// the corpus's, as Xcode 27.0 wrote them.
@Suite struct ConvertedColorTests {
    static func xib(_ color: String) -> String {
        ConstraintTests.constrained(ConstraintTests.subview("cnv-000-aa", (0, 0, 10, 1)).replacingOccurrences(of: "</view>", with: color + "\n</view>"), "")
    }

    /// `converted-deviceRGB`: flappy-fly-bird's launch screen background.
    @Test func compilesTheCorpusDeviceRGBColorAsXcode() throws {
        let color = #"<color key="backgroundColor" red="0.14901961389999999" green="0.14901961389999999" blue="0.14901961389999999" alpha="1" colorSpace="deviceRGB"/>"#
        let nib = try XIBCompiler.compile(Data(Self.xib(color).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1043)
        #expect(VariationTests.digest(nib) == "8df7e7e9b0621b6c93bf892b21e2072e489cfb3134e1d7aa1b2f041648bdc575")
    }

    /// `converted-calibratedRGB`, `calibrated-rgb`: conversions of the document's components, the same
    /// for two spellings of one color, and none for a color the corpus does not use.
    @Test func convertsTheObservedColors() {
        let first = NibColor.convertedColors[ConvertedColor("calibratedRGB", 0.01176470588, 0.66274509800000003, 0.95686274510000002)]
        let second = NibColor.convertedColors[ConvertedColor("calibratedRGB", 0.011764705882352941, 0.66274509803921566, 0.95686274509803915)]
        #expect(first.map { [$0.red, $0.green, $0.blue] } == [-0.104289241, 0.723522484, 0.966723382])
        #expect(second.map { [$0.red, $0.green, $0.blue] } == [-0.104289241, 0.723522484, 0.966723382])
        #expect(NibColor.convertedColors[ConvertedColor("calibratedRGB", 0.2, 0.4, 0.6)] == nil)
    }

    @Test func refusesColorsTheCorpusDoesNotUse() {
        let color = #"<color key="backgroundColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="calibratedRGB"/>"#
        #expect(throws: NomacError("nomac does not compile the calibratedRGB color 0.2 0.4 0.6 yet (BACKLOG B-260)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(Self.xib(color).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }
}
