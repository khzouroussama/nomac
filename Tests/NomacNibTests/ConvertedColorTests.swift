import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// The color conversions ibtool gets from CoreGraphics, in float32 (docs/formats/nib.md "Color
/// conversions"): components as `CGColor` converted them on macOS with Xcode 27.0's SDK, by bit pattern.
@Suite struct ConvertedColorTests {
    static func xib(_ color: String) -> String {
        ConstraintTests.constrained(ConstraintTests.subview("cnv-000-aa", (0, 0, 10, 1)).replacingOccurrences(of: "</view>", with: color + "\n</view>"), "")
    }

    static func bits(_ values: [Float]) -> [UInt32] { values.map(\.bitPattern) }

    typealias Case = (input: [Double], output: [UInt32])

    @Test(arguments: [
        ([0.2, 0.4, 0.6], [0x3dd4f6b7, 0x3ecfd7c2, 0x3f1df362]),
        ([1.0, 0.0, 0.0], [0x3f8bea67, 0xbe6848d6, 0xbe19ae76]),
        ([0.1450980392, 0.7960784314, 0.4078431373], [0xbebc8bfe, 0x3f4f744f, 0x3eb6cd44]),
        ([0.03, 0.97, 0.5], [0xbefc1dd0, 0x3f7cda97, 0x3ee0a50c]),
        ([1.0, 1.0, 1.0], [0x3f7fffff, 0x3f800001, 0x3f800001]),
        ([0.0, 0.0, 0.03125], [0xb56472d2, 0x35340ef7, 0x3d0c92f6]),
        ([0.70710678, 0.5, 0.25], [0x3f3e7204, 0x3efa3b60, 0x3e427fa8]),
        ([1.2, -0.1, 0.5], [0x3f8bea54, 0xbe68457c, 0x3f00630a])
    ] as [Case])
    func displayP3(_ sample: Case) {
        #expect(Self.bits(ColorManagement.displayP3(sample.input)) == sample.output)
    }

    @Test(arguments: [
        ([0.2, 0.4, 0.6], [0x3e816dce, 0x3ef5e936, 0x3f2a3728]),
        ([1.0, 0.0, 0.0], [0x3f8168f3, 0x3e18adbe, 0xbcba8150]),
        ([0.1450980392, 0.7960784314, 0.4078431373], [0x3e004e02, 0x3f5192d3, 0x3ef74c56]),
        ([0.03, 0.97, 0.5], [0xbe275a98, 0x3f753713, 0x3f12683f]),
        ([1.0, 1.0, 1.0], [0x3f7fffff, 0x3f800001, 0x3f800001]),
        ([0.0, 0.0, 0.03125], [0x3809f7cb, 0x3a579621, 0x3ccf617e]),
        ([0.70710678, 0.5, 0.25], [0x3f43267c, 0x3f12145d, 0x3ea1c1cd]),
        ([1.2, -0.1, 0.5], [0x3f816e43, 0x3e3deeb6, 0x3f12504e])
    ] as [Case])
    func calibratedRGB(_ sample: Case) {
        #expect(Self.bits(ColorManagement.calibratedRGB(sample.input)) == sample.output)
    }

    @Test(arguments: [
        ([0.2, 0.4, 0.6], [0x3e4cccc2, 0x3eccccce, 0x3f199999]),
        ([1.0, 0.0, 0.0], [0x3f800001, 0x351bc1df, 0x3292e49e]),
        ([0.1450980392, 0.7960784314, 0.4078431373], [0x3e149490, 0x3f4bcbcb, 0x3ed0d0d3]),
        ([0.03, 0.97, 0.5], [0x3cf5bfca, 0x3f7851eb, 0x3f000001]),
        ([1.0, 1.0, 1.0], [0x3f7fffff, 0x3f800001, 0x3f800001]),
        ([0.0, 0.0, 0.03125], [0xb409bbfb, 0x351dfcf1, 0x3cffffe9]),
        ([0.70710678, 0.5, 0.25], [0x3f3504f3, 0x3f000001, 0x3e7ffffe]),
        ([1.2, -0.1, 0.5], [0x3f800001, 0x3509115f, 0x3f000000])
    ] as [Case])
    func deviceRGB(_ sample: Case) {
        #expect(Self.bits(ColorManagement.deviceRGB(sample.input)) == sample.output)
    }

    @Test(arguments: [
        ([0.2, 0.4, 0.6], [0x3e1f8e4d, 0x3ea3c52e, 0x3f07683b]),
        ([1.0, 0.0, 0.0], [0x3f7c677e, 0x0, 0x3cdcb14b]),
        ([0.1450980392, 0.7960784314, 0.4078431373], [0x3e1c92a9, 0x3f45141c, 0x3eab074e]),
        ([0.03, 0.97, 0.5], [0x3e0a6f0d, 0x3f7c9dea, 0x3ed9dca8]),
        ([1.0, 1.0, 1.0], [0x3f800000, 0x3f800000, 0x3f800000]),
        ([0.0, 0.0, 0.03125], [0x0, 0x0, 0x3d0fe27c]),
        ([0.70710678, 0.5, 0.25], [0x3f24c329, 0x3ed9d39a, 0x3e45bf6c]),
        ([1.2, -0.1, 0.5], [0x3f7c5684, 0x0, 0x3ed9fd9b])
    ] as [Case])
    func sRGBToGenericRGB(_ sample: Case) {
        #expect(Self.bits(ColorManagement.sRGBToGenericRGB(ColorManagement.input(sample.input))) == sample.output)
    }

    @Test(arguments: [
        ([0.2, 0.4, 0.6], [0x3dba8a19, 0x3ea6b70a, 0x3f0c19c8]),
        ([1.0, 0.0, 0.0], [0x3f800000, 0x0, 0x0]),
        ([0.1450980392, 0.7960784314, 0.4078431373], [0x0, 0x3f4a2f6e, 0x3e92818d]),
        ([0.03, 0.97, 0.5], [0x0, 0x3f800000, 0x3eba7467]),
        ([1.0, 1.0, 1.0], [0x3f800000, 0x3f800000, 0x3f800000]),
        ([0.0, 0.0, 0.03125], [0x0, 0x0, 0x3d1792c9]),
        ([0.70710678, 0.5, 0.25], [0x3f2f4874, 0x3ed36d17, 0x3e1505fe]),
        ([1.2, -0.1, 0.5], [0x3f800000, 0x0, 0x3edaf3c0])
    ] as [Case])
    func displayP3ToGenericRGB(_ sample: Case) {
        #expect(Self.bits(ColorManagement.displayP3ToGenericRGB(ColorManagement.input(sample.input))) == sample.output)
    }

    @Test(arguments: [
        ([0.0], [0x0]),
        ([0.03], [0x3cc67382]),
        ([0.03125], [0x3cceb852]),
        ([0.25], [0x3ea2d0be]),
        ([0.3333333333333333], [0x3ed0cdb2]),
        ([0.5], [0x3f1282b2]),
        ([0.70710678], [0x3f422e1f]),
        ([1.0], [0x3f800000])
    ] as [Case])
    func calibratedWhite(_ sample: Case) {
        #expect([ColorManagement.calibratedWhite(sample.input[0], alpha: 1).bitPattern] == sample.output)
    }

    @Test(arguments: [
        ([0.0], [0x0, 0x0, 0x0]),
        ([0.03], [0x3d0ce97a, 0x3d0ce97a, 0x3d0ce97a]),
        ([0.03125], [0x3d1024ee, 0x3d1024ee, 0x3d1024ee]),
        ([0.25], [0x3e43bf62, 0x3e43bf62, 0x3e43bf62]),
        ([0.3333333333333333], [0x3e871061, 0x3e871061, 0x3e871061]),
        ([0.5], [0x3ed96ea8, 0x3ed96ea8, 0x3ed96ea8]),
        ([0.70710678], [0x3f25ee08, 0x3f25ee08, 0x3f25ee08]),
        ([1.0], [0x3f800000, 0x3f800000, 0x3f800000])
    ] as [Case])
    func gamma22WhiteToGenericRGB(_ sample: Case) {
        let white = ColorManagement.gamma22WhiteToGenericRGB(sample.input[0]).bitPattern
        #expect([white, white, white] == sample.output)
    }

    /// `white-alpha-*`: ibtool's gray is clamped only when it is opaque.
    @Test func clampsAWhiteOnlyWhenOpaque() {
        #expect(ColorManagement.calibratedWhite(1, alpha: 1).bitPattern == 0x3f800000)
        #expect(ColorManagement.calibratedWhite(1, alpha: 0.4).bitPattern == 0x3f800001)
        #expect(ColorManagement.calibratedWhite(1.2, alpha: 0.5).bitPattern == 0x3f800001)
    }

    /// `converted-deviceRGB`: flappy-fly-bird's launch screen background.
    @Test func compilesTheCorpusDeviceRGBColorAsXcode() throws {
        let color = #"<color key="backgroundColor" red="0.14901961389999999" green="0.14901961389999999" blue="0.14901961389999999" alpha="1" colorSpace="deviceRGB"/>"#
        let nib = try XIBCompiler.compile(Data(Self.xib(color).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1043)
        #expect(VariationTests.digest(nib) == "8df7e7e9b0621b6c93bf892b21e2072e489cfb3134e1d7aa1b2f041648bdc575")
    }

    /// `converted-calibratedRGB`: two spellings of one of the corpus's colors, as Xcode wrote them.
    @Test func convertsTheCorpusSpellingsAlike() {
        let expected: [Float] = [-0.104289241, 0.723522484, 0.966723382]
        #expect(ColorManagement.calibratedRGB([0.01176470588, 0.66274509800000003, 0.95686274510000002]) == expected)
        #expect(ColorManagement.calibratedRGB([0.011764705882352941, 0.66274509803921566, 0.95686274509803915]) == expected)
    }

    /// `unmatched-survey-whites`: without `colorMatched`, the observed `calibratedWhite` values, and no others.
    @Test func refusesAnUnobservedWhiteWithoutColorMatching() {
        let color = #"<color key="backgroundColor" white="0.1234" alpha="1" colorSpace="calibratedWhite"/>"#
        let document = Self.xib(color).replacingOccurrences(of: #" colorMatched="YES""#, with: "")
        #expect(throws: NomacError(#"nomac does not compile the calibratedWhite 0.1234 in a document without colorMatched="YES" yet (BACKLOG B-281)"#, path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
        #expect(NibColor.unmatchedCalibratedWhites[1] == 1)
        #expect(NibColor.unmatchedCalibratedWhites[0.5] == 0.5)
    }
}
