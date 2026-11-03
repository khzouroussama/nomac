import Foundation
import NomacLZFSE

extension AssetCatalogComparison {
    static let pdfProfiles = "the color profiles and font subsets nomac writes in a PDF image's vector rendition in place of Apple's (ADR 0204)"

    /// Two vector renditions of a PDF image (pixel format `PDF `, layout 9) match when their
    /// headers but for the rendition's length, their properties and their payloads' storage (actool
    /// keeps a PDF as it is) are identical and their PDFs
    /// are, but for the ICC profile streams and the font programs (their bytes and lengths), the
    /// names Quartz gives fonts without a PostScript name, and the byte offsets the
    /// cross-reference table and `startxref` give, which those streams' lengths move (ADR 0204).
    static func pdfRenditionsMatch(_ x: [UInt8], _ y: [UInt8]) -> Bool {
        guard x.count >= CSI.headerSize, y.count >= CSI.headerSize, x[24..<28] == [0x20, 0x46, 0x44, 0x50],
              x[0..<CSI.lengthOffset] == y[0..<CSI.lengthOffset] else { return false }
        let properties = CSI.headerSize + le32(x, CSI.propertiesOffset)
        guard x.count >= properties + 12, y.count >= properties + 12, x[CSI.headerSize..<properties] == y[CSI.headerSize..<properties],
              x[properties..<properties + 8] == y[properties..<properties + 8],
              let left = pdf(x, payload: properties), let right = pdf(y, payload: properties) else { return false }
        return withoutProfiles(left) == withoutProfiles(right)
    }

    private static func le32(_ bytes: [UInt8], _ at: Int) -> Int {
        Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
    }

    /// The PDF of a `DWAR` payload at `offset`: its flags 1 for LZFSE, then its length.
    private static func pdf(_ csi: [UInt8], payload offset: Int) -> [UInt8]? {
        let length = le32(csi, offset + 8)
        guard csi[offset..<offset + 4].elementsEqual("DWAR".utf8), offset + 12 + length <= csi.count else { return nil }
        let data = Array(csi[(offset + 12)..<(offset + 12 + length)])
        return le32(csi, offset + 4) == 1 ? try? LZFSE.decode(data) : data
    }

    /// The PDF with each ICC profile stream's `/Length` and bytes, each font program's
    /// dictionary and bytes, the `font` names' numbers, the cross-reference offsets and the
    /// `startxref` offset replaced by `#`.
    static func withoutProfiles(_ pdf: [UInt8]) -> [UInt8] {
        let marker = Array("\nstream\n".utf8), end = Array("\nendstream".utf8)
        var out: [UInt8] = []
        var position = 0
        while let stream = pdf[position...].firstRange(of: marker) {
            let lineStart = (pdf[position..<stream.lowerBound].lastIndex(of: 10) ?? position - 1) + 1
            var dictionary = Array(pdf[lineStart..<stream.lowerBound])
            guard let close = pdf[stream.upperBound...].firstRange(of: end) else { break }
            out += pdf[position..<lineStart]
            if dictionary.firstRange(of: Array("/Alternate".utf8)) != nil, let length = dictionary.firstRange(of: Array("/Length ".utf8)) {
                let digits = dictionary[length.upperBound...].prefix { (48...57).contains($0) }.count
                dictionary.replaceSubrange(length.upperBound..<length.upperBound + digits, with: [UInt8(ascii: "#")])
                out += dictionary + marker + [UInt8(ascii: "#")]
            } else if dictionary.starts(with: Array("<< /Length1 ".utf8)) || dictionary.starts(with: Array("<< /Subtype /Type1C ".utf8)) {
                out += Array("<< /FontFile # >>".utf8) + marker + [UInt8(ascii: "#")]
            } else {
                out += dictionary + pdf[stream.lowerBound..<close.lowerBound]
            }
            position = close.lowerBound
        }
        out += pdf[position...]
        var text = String(decoding: out, as: UnicodeScalar.self)
        text = text.replacingOccurrences(of: "\\n\\d{10} 00000 n ", with: "\n# n ", options: .regularExpression)
        text = text.replacingOccurrences(of: "startxref\\n\\d+", with: "startxref\n#", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\+font[0-9a-f]{16}", with: "+font#", options: .regularExpression)
        return text.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
    }
}

private extension String {
    init(decoding bytes: [UInt8], as _: UnicodeScalar.Type) {
        self.init(String.UnicodeScalarView(bytes.map { UnicodeScalar($0) }))
    }
}
