import Testing
@testable import NomacSigning

@Suite struct DERTests {
    /// Integers as codesign encodes them in DER entitlements (observed through
    /// `CodeSignerTests.encodesEntitlementIntegersAsCodesignDoes`).
    @Test func encodesIntegersInTheirShortestForm() {
        #expect(DER.integer(0) == [0x00])
        #expect(DER.integer(42) == [0x2a])
        #expect(DER.integer(128) == [0x00, 0x80])
        #expect(DER.integer(300) == [0x01, 0x2c])
        #expect(DER.integer(-1) == [0xff])
        #expect(DER.integer(-129) == [0xff, 0x7f])
        #expect(DER.integer(.max) == [0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
        #expect(DER.integer(.min) == [0x80, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func usesTheLongLengthFormFrom128Bytes() {
        #expect(DER.length(127) == [0x7f])
        #expect(DER.length(317) == [0x82, 0x01, 0x3d])
    }
}
