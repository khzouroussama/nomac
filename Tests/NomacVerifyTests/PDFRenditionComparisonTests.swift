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

    /// zlib data of one stored block.
    static func zlib(_ data: [UInt8]) -> [UInt8] {
        let (a, b) = data.reduce((1, 0)) { sums, byte in ((sums.0 + Int(byte)) % 65521, (sums.1 + (sums.0 + Int(byte)) % 65521) % 65521) }
        let length = data.count, adler = b << 16 | a
        return [0x78, 0x01, 0x01, UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8 & 0xFF)] + data
            + [24, 16, 8, 0].map { UInt8(adler >> $0 & 0xFF) }
    }

    /// A page drawing a 3-pixel RGB image with a soft mask of alphas 255, 128 and 0, both stored
    /// with Flate, their dictionaries wrapped as Quartz wraps them.
    static func maskedPDF(_ samples: [UInt8]) -> [UInt8] {
        let image = zlib(samples), mask = zlib([255, 128, 0])
        var pdf = Array("%PDF-1.3\n5 0 obj\n<< /Type /XObject /Subtype /Image /Width 3 /Height 1 /ColorSpace /DeviceRGB /SMask\n7 0 R /BitsPerComponent 8 /Length \(image.count) /Filter /FlateDecode >>\nstream\n".utf8)
        pdf += image + Array("\nendstream\nendobj\n7 0 obj\n<< /Type /XObject /Subtype /Image /Width 3 /Height 1 /ColorSpace /DeviceGray\n/BitsPerComponent 8 /Length \(mask.count) /Filter /FlateDecode >>\nstream\n".utf8)
        return pdf + mask + Array("\nendstream\nendobj\n".utf8)
    }

    @Test func decodedJPEGSamplesWithinTheBound() {
        let quartz: [UInt8] = [100, 100, 100, 200, 200, 200, 0, 0, 0]
        let xcode = Self.rendition(Self.maskedPDF(quartz))
        #expect(AssetCatalogComparison.pdfRenditionsMatch(xcode, Self.rendition(Self.maskedPDF([109, 100, 91, 200, 215, 200, 90, 255, 3]))))
        #expect(!AssetCatalogComparison.pdfRenditionsMatch(xcode, Self.rendition(Self.maskedPDF([110, 100, 100, 200, 200, 200, 0, 0, 0]))))
        #expect(!AssetCatalogComparison.pdfRenditionsMatch(xcode, Self.rendition(Self.maskedPDF([100, 100, 100, 200, 220, 200, 0, 0, 0]))))
        #expect(!AssetCatalogComparison.pdfRenditionsMatch(xcode, Self.rendition(Self.maskedPDF(Array(quartz.dropLast(3))))))
    }
}
