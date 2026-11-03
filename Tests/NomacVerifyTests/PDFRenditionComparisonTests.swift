import Foundation
import Testing
@testable import NomacVerify

/// ADR 0204: a PDF image's vector rendition may differ from actool's only in the color profiles
/// nomac embeds in place of Apple's, and the lengths and offsets those move.
@Suite struct PDFRenditionComparisonTests {
    static func pdf(profile: String, content: String = "q Q") -> [UInt8] {
        var text = "%PDF-1.3\n4 0 obj\n<< /Length \(content.count) /Filter /FlateDecode >>\nstream\n\(content)\nendstream\nendobj\n"
        text += "6 0 obj\n<< /N 3 /Alternate /DeviceRGB /Length \(profile.count) /Filter /FlateDecode >>\nstream\n\(profile)\nendstream\nendobj\n"
        let xref = text.utf8.count
        text += "xref\n0 2\n0000000000 65535 f \n" + String(format: "%010d 00000 n \n", xref / 2) + "trailer\n<< >>\nstartxref\n\(xref)\n%%EOF\n"
        return Array(text.utf8)
    }

    static func rendition(_ pdf: [UInt8], flag: UInt8 = 0) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 184)
        header.replaceSubrange(0..<4, with: Array("ISTC".utf8))
        header.replaceSubrange(24..<28, with: [0x20, 0x46, 0x44, 0x50])
        header[180] = UInt8(truncatingIfNeeded: pdf.count + 12)
        let length = withUnsafeBytes(of: UInt32(pdf.count).littleEndian, Array.init)
        return header + Array("DWAR".utf8) + [flag, 0, 0, 0] + length + pdf
    }

    @Test func onlyProfilesMayDiffer() {
        let xcode = Self.rendition(Self.pdf(profile: "Apple's profile bytes"))
        #expect(AssetCatalogComparison.pdfRenditionsMatch(xcode, Self.rendition(Self.pdf(profile: "nomac's"))))
        #expect(!AssetCatalogComparison.pdfRenditionsMatch(xcode, Self.rendition(Self.pdf(profile: "nomac's", content: "q Q q Q"))))
        #expect(!AssetCatalogComparison.pdfRenditionsMatch(xcode, Self.rendition(Array(Self.pdf(profile: "nomac's").dropLast(2)) + Array("X\n".utf8))))
        #expect(!AssetCatalogComparison.pdfRenditionsMatch(xcode, Self.rendition(Self.pdf(profile: "nomac's"), flag: 1)))
    }
}
