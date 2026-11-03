import Foundation
import NomacLZFSE

extension AssetCatalogComparison {
    static let pdfProfiles = "the color profiles and font subsets nomac writes in a PDF image's vector rendition in place of Apple's (ADR 0204)"

    /// Two vector renditions of a PDF image (pixel format `PDF `, layout 9) match when their
    /// headers but for the rendition's length, their properties and their payloads' storage (actool
    /// keeps a PDF as it is) are identical and their PDFs
    /// are, but for the ICC profile streams and the font programs (their bytes and lengths), the
    /// names Quartz gives fonts without a PostScript name, the samples of images with a soft mask
    /// within `decodedJPEGBound`, and the byte offsets the cross-reference table and `startxref`
    /// give, which those streams' lengths move (ADR 0204).
    static func pdfRenditionsMatch(_ x: [UInt8], _ y: [UInt8]) -> Bool {
        guard x.count >= CSI.headerSize, y.count >= CSI.headerSize, x[24..<28] == [0x20, 0x46, 0x44, 0x50],
              x[0..<CSI.lengthOffset] == y[0..<CSI.lengthOffset] else { return false }
        let properties = CSI.headerSize + le32(x, CSI.propertiesOffset)
        guard x.count >= properties + 12, y.count >= properties + 12, x[CSI.headerSize..<properties] == y[CSI.headerSize..<properties],
              x[properties..<properties + 8] == y[properties..<properties + 8],
              let left = pdf(x, payload: properties), let right = pdf(y, payload: properties) else { return false }
        return withoutProfiles(left) == withoutProfiles(right) && maskedSamplesAlike(left, right)
    }

    /// The largest difference, premultiplied by the soft mask's alpha, between a sample Quartz
    /// decodes from an RGB JPEG drawn with a soft mask and nomac's: 9 (`images-4`, at quality 50).
    static let decodedJPEGBound = 9

    /// Whether the images with a soft mask in two PDFs, in order, have the same samples, or RGB
    /// samples whose differences premultiplied by the mask's alpha stay within `decodedJPEGBound`.
    static func maskedSamplesAlike(_ x: [UInt8], _ y: [UInt8]) -> Bool {
        let left = maskedImages(x), right = maskedImages(y)
        guard left.count == right.count else { return false }
        func premultiplied(_ sample: UInt8, _ alpha: UInt8) -> Int { (Int(sample) * Int(alpha) * 2 + 255) / 510 }
        return zip(left, right).allSatisfy { a, b in
            a.samples == b.samples || a.samples.count == b.samples.count && a.alphas == b.alphas && a.samples.count == a.alphas.count * 3
                && a.samples.indices.allSatisfy { index in
                    let alpha = a.alphas[index / 3]
                    return abs(premultiplied(a.samples[index], alpha) - premultiplied(b.samples[index], alpha)) <= decodedJPEGBound
                }
        }
    }

    /// Each 8-bit image with a soft mask stored with Flate: its samples and its mask's.
    private static func maskedImages(_ pdf: [UInt8]) -> [(samples: [UInt8], alphas: [UInt8])] {
        let objects = streams(pdf)
        let byNumber = Dictionary(objects.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        return objects.compactMap { image in
            let dictionary = String(decoding: pdf[image.dictionary], as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
            guard isMaskedImage(dictionary), dictionary.contains("/BitsPerComponent 8 "),
                  let mask = dictionary.firstMatch(of: /\/SMask (\d+) 0 R/).flatMap({ Int($0.1) }).flatMap({ byNumber[$0] }) else { return nil }
            return (inflated(Array(pdf[image.data])) ?? [], inflated(Array(pdf[mask.data])) ?? [])
        }
    }

    private static func isMaskedImage(_ dictionary: String) -> Bool {
        ["/Subtype /Image ", "/SMask", "/FlateDecode "].allSatisfy(dictionary.contains)
    }

    /// Each stream object's number, dictionary and data.
    private static func streams(_ pdf: [UInt8]) -> [(number: Int, dictionary: Range<Int>, data: Range<Int>)] {
        let marker = Array("\nstream\n".utf8), end = Array("\nendstream".utf8), object = Array(" 0 obj\n".utf8)
        var result: [(number: Int, dictionary: Range<Int>, data: Range<Int>)] = []
        var position = 0
        while let stream = pdf[position...].firstRange(of: marker), let close = pdf[stream.upperBound...].firstRange(of: end),
              let header = pdf[position..<stream.lowerBound].ranges(of: object).last {
            let digits = pdf[position..<header.lowerBound].reversed().prefix { (48...57).contains($0) }.count
            let number = Int(String(decoding: pdf[(header.lowerBound - digits)..<header.lowerBound], as: UTF8.self)) ?? -1
            result.append((number, header.upperBound..<stream.lowerBound, stream.upperBound..<close.lowerBound))
            position = close.lowerBound
        }
        return result
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

    /// The PDF with each ICC profile stream's and Flate image with a soft mask's `/Length` and
    /// bytes, each font program's dictionary and bytes, the `font` names' numbers, the
    /// cross-reference offsets and the `startxref` offset replaced by `#`.
    static func withoutProfiles(_ pdf: [UInt8]) -> [UInt8] {
        let marker = Array("\nstream\n".utf8)
        var out: [UInt8] = []
        var position = 0
        for stream in streams(pdf) {
            var dictionary = Array(pdf[stream.dictionary])
            out += pdf[position..<stream.dictionary.lowerBound]
            let text = String(decoding: dictionary, as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
            if text.contains("/Alternate") || isMaskedImage(text), let length = dictionary.firstRange(of: Array("/Length ".utf8)) {
                let digits = dictionary[length.upperBound...].prefix { (48...57).contains($0) }.count
                dictionary.replaceSubrange(length.upperBound..<length.upperBound + digits, with: [UInt8(ascii: "#")])
                out += dictionary + marker + [UInt8(ascii: "#")]
            } else if dictionary.starts(with: Array("<< /Length1 ".utf8)) || dictionary.starts(with: Array("<< /Subtype /Type1C ".utf8)) {
                out += Array("<< /FontFile # >>".utf8) + marker + [UInt8(ascii: "#")]
            } else {
                out += pdf[stream.dictionary.lowerBound..<stream.data.upperBound]
            }
            position = stream.data.upperBound
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
