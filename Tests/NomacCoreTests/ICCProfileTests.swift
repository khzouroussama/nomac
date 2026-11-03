import Foundation
import Testing
@testable import NomacCore

/// Matrix/TRC profiles converted to sRGB as `assets-experiments profiles` observed actool convert
/// them, for colors where nomac's conversion gives actool's values (most do; the others differ by 1).
@Suite struct ICCProfileTests {
    /// Display P3 written from the ICC specification by `assets_experiments.py`'s `icc_profile`:
    /// D65 primaries adapted to D50, sRGB's parametric curve.
    static let displayP3 = Array(Data(base64Encoded: """
        AAABoG5vbmUEMAAAbW50clJHQiBYWVogB+oACgAeAAAAAAAAYWNzcEFQUEwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPbWAAEAAAAA0y1ub25lAAAAAAAAAAAAAAAAAAAAAAAA\
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJZGVzYwAAAPAAAABAd3RwdAAAATAAAAAUclhZWgAAAUQAAAAUZ1hZWgAAAVgAAAAUYlhZWgAAAWwAAAAUclRSQwAAAYAAAAAg\
        Z1RSQwAAAYAAAAAgYlRSQwAAAYAAAAAgY3BydAAAAPAAAABAbWx1YwAAAAAAAAABAAAADGVuVVMAAAAkAAAAHABEAGkAcwBwAGwAYQB5ACAAUAAzACAAKABuAG8AbQBhAGMAKVhZ\
        WiAAAAAAAAD21gABAAAAANMtWFlaIAAAAAAAAIPfAAA9v////7tYWVogAAAAAAAASr8AALE3AAAKuVhZWiAAAAAAAAAoOAAAEQsAAMi5cGFyYQAAAAAAAwAAAAJmZgAA8qcAAA1Z\
        AAAT0AAACls=
        """)!)

    @Test func displayP3ColorsBecomeActoolsSRGBValues() throws {
        let profile = try ICCProfile(Self.displayP3)
        func srgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> [UInt8] {
            let converted = profile.convert(r, g, b)
            return [converted.red, converted.green, converted.blue]
        }
        #expect(srgb(37, 180, 119) == [0, 183, 113])
        #expect(srgb(200, 200, 255) == [200, 200, 255])
        #expect(srgb(255, 0, 0) == [255, 0, 0])
        #expect(srgb(0, 255, 0) == [0, 255, 0])
        #expect(profile.convert(255, 0, 0).over > 0.2 && profile.convert(255, 0, 0).under > 0.04)
        #expect(profile.convert(128, 128, 128).under < 0.0015 && profile.convert(128, 128, 128).over < 0.0078)
        #expect(!ICCProfile.isStandardSRGB(Self.displayP3))
    }

    /// Display P3 red in extended sRGB as actool's display-gamut-1 renditions store it (1.0928,
    /// −0.2266, −0.1497 as half floats; `profiles` wide cases).
    @Test func extendedSRGBKeepsColorsOutsideTheGamut() throws {
        let red = try ICCProfile(Self.displayP3).extended(255, 0, 0)
        #expect(abs(red.red - 1.0928) < 0.002 && abs(red.green + 0.2266) < 0.002 && abs(red.blue + 0.1497) < 0.002)
    }

    @Test func curvesFollowTheSpecification() {
        #expect(ICCProfile.Curve.gamma(2).apply(0.5) == 0.25)
        #expect(ICCProfile.Curve.table([0, 0.5, 1]).apply(0.75) == 0.75)
        #expect(ICCProfile.Curve.parametric(3, [2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045]).apply(0.04) == 0.04 / 12.92)
        #expect(ICCProfile.Curve.identity.apply(0.3) == 0.3)
    }

    @Test func lookupTableProfilesAreRefused() {
        var profile = Self.displayP3
        profile.replaceSubrange(156..<160, with: Array("A2B0".utf8))
        #expect(throws: ICCProfile.Unsupported.self) { try ICCProfile(profile) }
    }
}
