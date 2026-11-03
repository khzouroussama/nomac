import CZlib
import Foundation
import NomacCore

/// A PDF image set's file as actool stores it in a vector rendition: the first page drawn
/// again by Quartz into a new PDF (docs/formats/asset-catalog.md, "PDF images"; `pdf_experiments.py`).
/// nomac reads the page's content into drawings (``PDFPage``) and writes them by the rules
/// observed; what it has not observed it refuses (BACKLOG B-215).
enum QuartzPDF {
    /// The file actool stores for `page`, with nomac's own color profiles where Quartz embeds
    /// Apple's (ADR 0204).
    static func rewrite(_ page: PDFPage) -> [UInt8] {
        var document = Document(fonts: page.fonts)
        return document.write(page)
    }

    /// The page's content stream, compressed.
    static func contentStream(_ page: PDFPage) -> [UInt8] {
        var document = Document(fonts: page.fonts)
        var resources = Document.Resources()
        return document.contentStream(page.items, resources: &resources)
    }

    /// The objects of the file, numbered and written in Quartz's order: the content (4), the page
    /// (1) and its resources (3) first. A content stream numbers, from 5, the color spaces and
    /// the forms it uses as it uses them (a form's resources, then the form), and the
    /// ExtGStates new to it at its end; a form, written after the stream that uses it, numbers
    /// its group's color space first. After the page come its forms, each followed by its
    /// resources and its own forms; then the patterns and shadings; then the page's and the
    /// forms' new ExtGStates in number order (`groups-5`; corpus: firefox's `kitCircle.pdf`); then
    /// each color space after its profile, numbered then; the pages node (2), the catalog and
    /// the Info last. Names count up across the file: `/Cs` by color space, the groups' included,
    /// `/Gs` and `/Fm` (`groups`, `groups-2`: ca-on-do, ca-inside, after-group, nested-matrix;
    /// `extgstate`, `icc` for a page alone).
    struct Document {
        struct Resources {
            var spaces: [Int] = []
            var states: [Int] = []
            var patterns: [Int] = []
            var shadings: [Int] = []
            var xobjects: [XObject] = []
            var fonts: [Int] = []
        }

        /// A font Quartz writes for a PDF font: its MacRoman one, the glyphs whose names
        /// MacRomanEncoding has at their codes there, or its identity one, the others at codes
        /// from 33 in the order shown, with their Unicode values (`fonts-3`, `fonts-4`).
        struct TextFont {
            var key: Int
            var macRoman: Bool
            var index: Int
            var number: Int
            /// Its resource name: `TTn` for TrueType, `Tcn` for CFF, n counting the fonts of its kind.
            var name: String
            var codes: [(code: Int, glyph: Int, unicode: [UInt16])] = []
        }

        enum XObject {
            case form(Form)
            case image(Int)
        }

        struct Form {
            var name: Int
            var resources: Int
            var number: Int
            var group: PDFPage.Group
        }

        let fonts: [Int: PDFFontProgram]
        var writer = Writer()
        var next = 5
        /// Quartz's fonts as they are made, and those of each PDF font by its key.
        var textFonts: [TextFont] = []
        var fontsByKey: [Int: (macRoman: Int, identity: Int?)] = [:]
        var spaces: [(space: PDFPage.ColorSpace, number: Int)] = []
        var states: [(entry: String, number: Int?)] = []
        var images: [(image: PDFPage.Image, number: Int, written: Bool)] = []
        var forms = 0
        var formStates: [Int] = []
        var flushed = 0
        /// Soft masks by serial as content uses them, and those whose ExtGState is written and
        /// whose form is still to write, with its resources' number and its own.
        var softMasks: [Int: PDFPage.SoftMask] = [:]
        var pendingMasks: [(mask: PDFPage.SoftMask, resources: Int, number: Int)] = []
        var patterns: [(pattern: PDFPage.Pattern, number: Int)] = []
        var shadings: [(shading: PDFPage.Shading, number: Int)] = []
        /// Patterns and shadings drawn, in order, to write before the color spaces; then the
        /// functions sampled again, after them, and those kept, after the catalog.
        var pendingPaints: [Paint] = []
        var sampledFunctions: [(function: PDFPage.Function, components: Int, number: Int)] = []
        var keptFunctions: [(function: PDFPage.Function, number: Int)] = []

        enum Paint {
            case pattern(Int)
            case shading(Int)
        }

        mutating func write(_ page: PDFPage) -> [UInt8] {
            writer.header()
            var resources = Resources()
            let content = contentStream(page.items, resources: &resources)
            let newStates = numberStates()
            writer.stream(4, dictionary: [], data: content)
            writer.object(1, "<< /Type /Page /Parent 2 0 R /Resources 3 0 R /Contents 4 0 R >>")
            writer.object(3, dictionary(resources))
            writeXObjects(resources.xobjects)
            writePaints()
            writeStates(newStates + takeFormStates())
            writeColorSpaces()
            while !pendingMasks.isEmpty {
                let masks = pendingMasks
                pendingMasks = []
                for mask in masks { writeMask(mask) }
                writePaints()
                writeColorSpaces()
            }
            let box = page.box
            writer.object(2, Writer.wrapped(["<<", "/Type", "/Pages", "/MediaBox", "[\([box.minX, box.minY, box.maxX, box.maxY].map(number).joined(separator: " "))]",
                                             "/Count", "1", "/Kids", "[", "1 0 R", "]", ">>"]))
            writer.object(next, "<< /Type /Catalog /Pages 2 0 R\(forms > 0 || images.contains { $0.image.mask != nil } ? " /Version /1.4" : "") >>")
            let catalog = next
            next += 1
            // Kept functions last first (the same file's two PostScript functions), then the fonts
            // (corpus: kickstarter's `icon--currency-header.pdf`).
            for entry in keptFunctions.reversed() { writeFunction(entry.function, number: entry.number) }
            for font in textFonts where !font.codes.isEmpty { writeFont(font) }
            var info = ["<<"]
            if let producer = page.producer { info += ["/Producer", literal(producer)] }
            if let date = page.creationDate { info += ["/CreationDate", "(D:\(date)Z00'00')", "/ModDate", "(D:\(date)Z00'00')"] }
            writer.object(next, Writer.wrapped(info + [">>"]))
            writer.trailer(root: catalog, info: next, identifiers: page.identifiers)
            return writer.bytes
        }

        /// The Quartz font a glyph of a PDF font goes to and its code there, the PDF font's
        /// MacRoman font made at its first glyph and its identity font at its first glyph without a
        /// MacRoman name, each numbered then (`fonts-3` named-and-unnamed, named-odd).
        mutating func textFont(_ key: Int, glyph: PDFPage.TextRun.Glyph) -> (font: Int, code: Int) {
            func make(macRoman: Bool) -> Int {
                // The subset tag counts every font, the resource name those of its kind (corpus: cwa's
                // `Icons_FaceID_light.pdf`, `/TT1` then `/Tc2` tagged `AAAAAD`).
                let prefix = fonts[key]?.resourcePrefix ?? "TT"
                let name = prefix + "\(textFonts.filter { $0.name.hasPrefix(prefix) }.count + 1)"
                textFonts.append(TextFont(key: key, macRoman: macRoman, index: textFonts.count + 1, number: next, name: name))
                next += 1
                return textFonts.count - 1
            }
            var entry = fontsByKey[key] ?? (make(macRoman: true), nil)
            defer { fontsByKey[key] = entry }
            if let name = glyph.name, let code = PDFEncoding.macRomanCodes[name] {
                if !textFonts[entry.macRoman].codes.contains(where: { $0.code == code }) {
                    textFonts[entry.macRoman].codes.append((code, glyph.glyph, []))
                }
                return (entry.macRoman, code)
            }
            let identity = entry.identity ?? make(macRoman: false)
            entry.identity = identity
            if let known = textFonts[identity].codes.first(where: { $0.glyph == glyph.glyph }) { return (identity, known.code) }
            let code = 33 + textFonts[identity].codes.count
            textFonts[identity].codes.append((code, glyph.glyph, glyph.unicode))
            return (identity, code)
        }

        /// A font after the catalog: its dictionary, then its `/ToUnicode` CMap (an identity
        /// font's), its descriptor and its program, numbered now. Its name is a tag counting its
        /// index from `AAAAAA`, then the font's PostScript name (`font` and a number Quartz takes
        /// from memory without one), its widths in thousandths of the em, rounded (`fonts`, `cff`;
        /// corpus: wikipedia's `description-cat.pdf`, `notifications-type-default.pdf`).
        mutating func writeFont(_ font: TextFont) {
            guard let program = fonts[font.key] else { return }
            let descriptor = next, toUnicode = next + 1, file = next + (font.macRoman ? 1 : 2)
            next = file + 1
            var tag = "", index = font.index
            for _ in 0..<6 {
                tag = String(UnicodeScalar(UInt8(65 + index % 26))) + tag
                index /= 26
            }
            var base = program.postScriptName ?? "font0000000000000000"
            if let plus = base.firstIndex(of: "+"), base.distance(from: base.startIndex, to: plus) == 6 { base = String(base[base.index(after: plus)...]) }
            let name = "/\(tag)+\(base)"
            let codes = font.codes.sorted { $0.code < $1.code }
            let first = codes.first!.code, last = codes.last!.code
            let widths = (first...last).map { code in codes.first { $0.code == code }.map { String(program.width($0.glyph)) } ?? "0" }
            var encoding = ["/Encoding", "/MacRomanEncoding"]
            if !font.macRoman {
                // A CFF identity font names its glyphs (corpus: cwa's `Icon_Wifi.pdf`; `cff-2` differences).
                encoding = ["/ToUnicode", "\(toUnicode) 0 R"]
                if case .cff = program {
                    encoding = ["/Encoding", "<<", "/Type", "/Encoding", "/Differences", "[", "\(first)"] + codes.map { "/" + (program.name($0.glyph) ?? ".notdef") }
                        + ["]", ">>"] + encoding
                }
            }
            writer.object(font.number, Writer.wrapped(["<<", "/Type", "/Font", "/Subtype", program.subtype, "/BaseFont", name, "/FontDescriptor", "\(descriptor) 0 R"]
                + encoding + ["/FirstChar", "\(first)", "/LastChar", "\(last)", "/Widths", "["] + widths + ["]", ">>"]))
            if !font.macRoman { writer.stream(toUnicode, dictionary: [], data: deflate(Array(Self.toUnicode(codes).utf8))) }
            let stream = program.program(codes.map { ($0.code, $0.glyph) })
            writer.object(descriptor, Writer.wrapped(["<<", "/Type", "/FontDescriptor", "/FontName", name, "/Flags", font.macRoman ? "32" : "4"]
                + program.descriptorEntries() + [stream.key, "\(file) 0 R", ">>"]))
            writer.stream(file, dictionary: stream.entries, data: deflate(stream.data))
        }

        /// An identity font's CMap: its codes' Unicode values, consecutive codes with consecutive
        /// values in one range (`fonts-4`).
        static func toUnicode(_ codes: [(code: Int, glyph: Int, unicode: [UInt16])]) -> String {
            var ranges: [(first: Int, last: Int, unicode: [UInt16])] = []
            for entry in codes where !entry.unicode.isEmpty {
                if let range = ranges.last, range.last + 1 == entry.code, range.unicode.count == 1, entry.unicode.count == 1,
                   Int(range.unicode[0]) + entry.code - range.first == Int(entry.unicode[0]) {
                    ranges[ranges.count - 1].last = entry.code
                } else {
                    ranges.append((entry.code, entry.code, entry.unicode))
                }
            }
            var text = "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo <<\n  /Registry (Adobe)\n  /Ordering (UCS)\n"
                + "  /Supplement 0\n>> def\n/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<00><FF>\nendcodespacerange\n"
            if !ranges.isEmpty {
                text += "\(ranges.count) beginbfrange\n"
                for range in ranges {
                    text += String(format: "<%02x><%02x><", range.first, range.last) + range.unicode.map { String(format: "%04x", $0) }.joined() + ">\n"
                }
                text += "endbfrange\n"
            }
            return text + "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
        }

        /// The patterns and shadings drawn so far, before the ExtGStates (`shadings`; corpus: cwa's
        /// `Corona-Warn-App.pdf`).
        mutating func writePaints() {
            let paints = pendingPaints
            pendingPaints = []
            // The patterns first, each numbering its shading, then the shadings (corpus: cwa's
            // `Icon_CurrentlyUsedCertificate_dark.pdf`, two patterns).
            var shadingsToWrite: [(shading: PDFPage.Shading, number: Int)] = []
            for paint in paints {
                switch paint {
                case .pattern(let index):
                    let (pattern, patternNumber) = patterns[index]
                    var entries = ["<<", "/Type", "/Pattern", "/PatternType", "2"]
                    let matrix = pattern.matrix
                    if !matrix.isIdentity {
                        entries += ["/Matrix", "[\([matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f].map(QuartzPDF.number).joined(separator: " "))]"]
                    }
                    shadingsToWrite.append((pattern.shading, next))
                    next += 1
                    writer.object(patternNumber, Writer.wrapped(entries + ["/Shading", "\(shadingsToWrite.last!.number) 0 R", ">>"]))
                case .shading(let index):
                    shadingsToWrite.append(shadings[index])
                }
            }
            for (shading, number) in shadingsToWrite { writeShading(shading, number: number) }
        }

        /// The color spaces not written yet, then the functions sampled again.
        mutating func writeColorSpaces() {
            flushSpaces()
            let functions = sampledFunctions
            sampledFunctions = []
            for entry in functions { writeSampled(entry.function, components: entry.components, number: entry.number) }
        }

        /// A shading: its color space, type, coordinates, domain, extension and function, which
        /// Quartz keeps when sampled or a PostScript program and samples again otherwise.
        mutating func writeShading(_ shading: PDFPage.Shading, number: Int) {
            let space = spaces[spaceIndex(shading.space)].number
            let function = next
            next += 1
            if shading.function.isKept {
                keptFunctions.append((shading.function, function))
            } else {
                sampledFunctions.append((shading.function, shading.space.components, function))
            }
            writer.object(number, Writer.wrapped(["<<", "/ColorSpace", "\(space) 0 R", "/ShadingType", "\(shading.type)", "/Coords", "["] + shading.coords.map(QuartzPDF.number)
                + ["]", "/Domain", "["] + shading.domain.map(QuartzPDF.number) + ["]", "/Extend", "[", "\(shading.extend.0)", "\(shading.extend.1)", "]",
                   "/Function", "\(function) 0 R", ">>"]))
        }

        /// An exponential or stitching function as Quartz samples it: 4,096 values divided among
        /// the components at even steps of its domain, each component's range its extremes, 8
        /// bits rounded within it (`shadings`: axial-fn2, axial-fn3, gray).
        mutating func writeSampled(_ function: PDFPage.Function, components: Int, number: Int) {
            let count = 4096 / components, domain = function.domain
            let values = (0..<count).map { function.evaluate(domain[0] + Double($0) / Double(count - 1) * (domain[1] - domain[0])) }
            let ranges = (0..<components).map { component in (values.map { $0[component] }.min()!, values.map { $0[component] }.max()!) }
            let samples = values.flatMap { value in
                (0..<components).map { component -> UInt8 in
                    let (low, high) = ranges[component]
                    return high == low ? 0 : UInt8(min(max(((value[component] - low) / (high - low) * 255).rounded(), 0), 255))
                }
            }
            writer.stream(number, dictionary: ["/FunctionType", "0", "/BitsPerSample", "8", "/Size", "[", "\(count)", "]", "/Domain", "["]
                + domain.map(QuartzPDF.number) + ["]", "/Range", "["] + ranges.flatMap { [QuartzPDF.number($0.0), QuartzPDF.number($0.1)] } + ["]"], data: deflate(samples))
        }

        /// A function Quartz keeps: a PostScript program as it is, a sampled function with its
        /// entries in Quartz's order and their defaults (`shadings`: axial-fn4, axial-fn0).
        mutating func writeFunction(_ function: PDFPage.Function, number: Int) {
            func array(_ values: [Double]) -> [String] { ["["] + values.map(QuartzPDF.number) + ["]"] }
            switch function {
            case .postScript(let domain, let range, let program):
                writer.stream(number, dictionary: ["/FunctionType", "4", "/Domain"] + array(domain) + ["/Range"] + array(range),
                              data: deflate(PostScriptCalculator.rewritten(program)))
            case .sampled(let sampled):
                writer.stream(number, dictionary: ["/Range"] + array(sampled.range) + ["/Order", "1", "/Decode"] + array(sampled.decode)
                    + ["/BitsPerSample", "\(sampled.bitsPerSample)", "/Domain"] + array(sampled.domain) + ["/Encode"] + array(sampled.encode)
                    + ["/FunctionType", "0", "/Size", "[", "\(sampled.size)", "]"], data: deflate(sampled.data))
            case .exponential, .stitching:
                break
            }
        }

        /// The color spaces not written yet, each after its profile, numbered now.
        mutating func flushSpaces() {
            for (index, (space, number)) in spaces.enumerated().dropFirst(flushed) where !spaces[..<index].contains(where: { $0.number == number }) {
                let (components, alternate, profile) = space.profile
                writer.stream(next, dictionary: ["/N", "\(components)", "/Alternate", alternate], data: profile)
                writer.object(number, "[ /ICCBased \(next) 0 R ]")
                next += 1
            }
            flushed = spaces.count
        }

        /// A soft mask's form, after the color spaces of what drew it: its content in its own
        /// space without clips, `/Resources` before `/BBox`, its `/Matrix`, a DeviceGray group, or
        /// for a luminosity mask its group's space, numbered before the content (`smasks`,
        /// `smasks-2`).
        mutating func writeMask(_ entry: (mask: PDFPage.SoftMask, resources: Int, number: Int)) {
            // A group in an ICC space names it twice, as a group's space and as itself (`smasks-3` lum-icc-gray, -own).
            let groupSpace = entry.mask.luminosity.map { luminosity in
                let index = spaceIndex(.maskGroup(luminosity.space))
                if case .icc = luminosity.space { _ = spaceIndex(luminosity.space) }
                return "\(spaces[index].number) 0 R"
            } ?? "/DeviceGray"
            var resources = Resources()
            let content = contentStream(entry.mask.items, resources: &resources)
            let newStates = numberStates()
            let box = entry.mask.box, matrix = entry.mask.matrix
            var dictionary = ["/Type", "/XObject", "/Subtype", "/Form", "/FormType", "1", "/Resources", "\(entry.resources) 0 R",
                              "/BBox", "[\([box.minX, box.minY, box.maxX, box.maxY].map(number).joined(separator: " "))]"]
            if !matrix.isIdentity {
                dictionary += ["/Matrix", "[\([matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f].map(number).joined(separator: " "))]"]
            }
            writer.stream(entry.number, dictionary: dictionary + ["/Group", "<<", "/S", "/Transparency", "/CS", groupSpace, "/I", "true", "/K", "false", ">>"],
                          data: content)
            writer.object(entry.resources, self.dictionary(resources))
            writeXObjects(resources.xobjects)
            writeStates(newStates + takeFormStates())
        }

        /// The forms' new ExtGStates, written with the stream's after them.
        mutating func takeFormStates() -> [Int] {
            defer { formStates = [] }
            return formStates
        }

        mutating func writeXObjects(_ list: [XObject]) {
            for item in list {
                guard case .form(let form) = item else {
                    if case .image(let index) = item, !images[index].written { writeImage(index) }
                    continue
                }
                let space = spaceIndex(form.group.space)
                var resources = Resources()
                let content = contentStream(form.group.items, resources: &resources)
                let newStates = numberStates()
                let box = form.group.bounds
                writer.stream(form.number, dictionary: [
                    "/Type", "/XObject", "/Subtype", "/Form", "/FormType", "1", "/BBox", "[\([box.minX, box.minY, box.maxX, box.maxY].map(number).joined(separator: " "))]",
                    "/Resources", "\(form.resources) 0 R", "/Group", "<<", "/S", "/Transparency", "/CS", "\(spaces[space].number) 0 R",
                    "/I", "true", "/K", "false", ">>",
                ], data: content)
                writer.object(form.resources, dictionary(resources))
                writeXObjects(resources.xobjects)
                formStates += newStates
            }
        }

        /// An image XObject: its size, `/Interpolate`, `/ImageMask` or its color space, its soft
        /// mask (a DeviceGray image written next), `/Decode` and depth, the samples compressed
        /// again, a JPEG's bytes as they are (`images`).
        mutating func writeImage(_ index: Int) {
            images[index].written = true
            let (image, objectNumber, _) = images[index]
            let samples = image.samples
            var entries = ["/Type", "/XObject", "/Subtype", "/Image", "/Width", "\(samples.width)", "/Height", "\(samples.height)"]
            if samples.interpolate { entries += ["/Interpolate", "true"] }
            if let space = samples.space {
                entries += ["/ColorSpace", "\(spaces[spaceIndex(space)].number) 0 R"]
                if let intent = samples.intent { entries += ["/Intent", "/\(intent)"] }
            } else {
                entries += ["/ImageMask", "true"]
            }
            let maskNumber = image.mask.map { _ in next }
            if let maskNumber {
                next += 1
                entries += ["/SMask", "\(maskNumber) 0 R"]
            }
            if let decode = samples.decode { entries += ["/Decode", "["] + decode.map(number) + ["]"] }
            // An RGB JPEG with a soft mask is decoded and compressed with Flate; a gray one, or one
            // without a mask, kept (`images-4`; corpus: firefox's onboarding images).
            let jpeg = image.mask != nil && samples.space?.components == 3 ? nil : samples.jpeg
            writer.stream(objectNumber, dictionary: entries + ["/BitsPerComponent", "\(samples.bitsPerComponent)"],
                          data: jpeg ?? deflate(Self.rows(samples)), filter: jpeg == nil ? "/FlateDecode" : "/DCTDecode")
            if let mask = image.mask, let maskNumber {
                writer.stream(maskNumber, dictionary: ["/Type", "/XObject", "/Subtype", "/Image", "/Width", "\(mask.width)", "/Height", "\(mask.height)",
                                                       "/ColorSpace", "/DeviceGray", "/BitsPerComponent", "8"], data: deflate(Self.rows(mask)))
            }
        }

        /// The samples an image's size holds, what follows them dropped.
        static func rows(_ samples: PDFPage.Samples) -> [UInt8] {
            let row = (samples.width * (samples.space?.components ?? 1) * samples.bitsPerComponent + 7) / 8
            return Array(samples.data.prefix(row * samples.height))
        }

        /// Numbers the ExtGStates first used since the last call, in that order.
        mutating func numberStates() -> [Int] {
            var numbered: [Int] = []
            for index in states.indices where states[index].number == nil {
                states[index].number = next
                next += 1
                numbered.append(index)
            }
            return numbered
        }

        /// The ExtGStates in number order, a soft mask's numbering its form's resources and form
        /// (`smasks`).
        mutating func writeStates(_ indices: [Int]) {
            for index in indices.sorted(by: { states[$0].number! < states[$1].number! }) {
                let entry = states[index].entry
                if entry.hasPrefix(Self.maskMarker), let mask = softMasks[Int(entry.dropFirst(Self.maskMarker.count))!] {
                    pendingMasks.append((mask, next, next + 1))
                    var units = ["<<", "/Type", "/ExtGState", "/SMask", "<<", "/G", "\(next + 1) 0 R", "/S"]
                    units += mask.luminosity.map { ["/Luminosity", "/BC", "["] + $0.backdrop.map(number) + ["]"] } ?? ["/Alpha"]
                    next += 2
                    if let transfer = mask.transfer {
                        // Kept or sampled again as a shading's function (`smasks-2` tr-function, alpha-tr; `smasks-3`).
                        if transfer.isKept { keptFunctions.append((transfer, next)) } else { sampledFunctions.append((transfer, 1, next)) }
                        units += ["/TR", "\(next) 0 R"]
                        next += 1
                    }
                    writer.object(states[index].number!, Writer.wrapped(units + [">>", ">>"]))
                } else {
                    writer.object(states[index].number!, "<< /Type /ExtGState \(entry) >>")
                }
            }
        }

        static let maskMarker = "soft mask "

        /// A color space's index, made at its first use: a new name, and a new object but for a
        /// luminosity mask's group space and the space it stands for, which share one (`smasks-2`,
        /// `smasks-3`).
        mutating func spaceIndex(_ space: PDFPage.ColorSpace) -> Int {
            if let index = spaces.firstIndex(where: { $0.space == space }) { return index }
            if let shared = spaces.first(where: { $0.space.plain == space.plain }) {
                spaces.append((space, shared.number))
            } else {
                spaces.append((space, next))
                next += 1
            }
            return spaces.count - 1
        }

        func dictionary(_ resources: Resources) -> String {
            let hasImages = resources.xobjects.contains { if case .image = $0 { true } else { false } }
            var units = ["<<", "/ProcSet", "[", "/PDF"] + (resources.fonts.isEmpty ? [] : ["/Text"]) + (hasImages ? ["/ImageB", "/ImageC", "/ImageI"] : []) + ["]"]
            if !resources.spaces.isEmpty {
                units += ["/ColorSpace", "<<"] + resources.spaces.sorted().flatMap { ["/Cs\($0 + 1)", "\(spaces[$0].number) 0 R"] } + [">>"]
            }
            if !resources.states.isEmpty {
                units += ["/ExtGState", "<<"] + resources.states.sorted().flatMap { ["/Gs\($0 + 1)", "\(states[$0].number!) 0 R"] } + [">>"]
            }
            if !resources.fonts.isEmpty {
                units += ["/Font", "<<"] + resources.fonts.sorted().flatMap { ["/\(textFonts[$0].name)", "\(textFonts[$0].number) 0 R"] } + [">>"]
            }
            if !resources.patterns.isEmpty {
                units += ["/Pattern", "<<"] + resources.patterns.flatMap { ["/P\($0 + 1)", "\(patterns[$0].number) 0 R"] } + [">>"]
            }
            if !resources.shadings.isEmpty {
                units += ["/Shading", "<<"] + resources.shadings.flatMap { ["/Sh\($0 + 1)", "\(shadings[$0].number) 0 R"] } + [">>"]
            }
            if !resources.xobjects.isEmpty {
                units += ["/XObject", "<<"] + resources.xobjects.flatMap { item -> [String] in
                    switch item {
                    case .form(let form): ["/Fm\(form.name)", "\(form.number) 0 R"]
                    case .image(let index): ["/Im\(index + 1)", "\(images[index].number) 0 R"]
                    }
                } + [">>"]
            }
            return Writer.wrapped(units + [">>"])
        }

        /// A content stream: an empty `q Q`, then a `q … Q` block per clip in drawing order,
        /// each with its clip paths and its drawings and groups. Each block starts from the
        /// defaults (black, opaque, no overprinting, smoothness 0, the relative colorimetric
        /// intent, a line 1 wide with butt caps, miter joins, a miter limit of 10 and no dash).
        /// Before a drawing, what changed is written in this order: for a stroke the line (`w`,
        /// `J`, `j`, `M`, `d`), the rendering intent, the smoothness; for a fill its color (when
        /// it or the opacity changed), opacity, overprinting and its mode; for a stroke its color,
        /// opacity and overprinting. A group is its form's `Do` after its opacity, in a block of
        /// its own that what follows may join. Each setting of an ExtGState is one with that
        /// entry alone (`details`, `state-changes`, `extgstate`, `strokes`, `colors` default,
        /// `clips`; `groups`: twice, after-fill; `groups-2`: ca-on-do, after-group).
        mutating func contentStream(_ items: [PDFPage.Item], resources: inout Resources) -> [UInt8] {
            var units = ["q", "Q"]
            var openClip: [PDFPage.Clip]?
            var block = Block()
            func state(_ entry: String) {
                let index = states.firstIndex(where: { $0.entry == entry }) ?? {
                    states.append((entry, nil))
                    return states.count - 1
                }()
                if !resources.states.contains(index) { resources.states.append(index) }
                units += ["/Gs\(index + 1)", "gs"]
            }
            /// A fill's or a stroke's color, the block's state updated.
            func color(_ color: PDFPage.Color, stroke: Bool) {
                let written = stroke ? block.strokeSpace : block.fillSpace
                let patternSpace = stroke ? block.strokePatterns : block.fillPatterns
                if stroke { block.strokePatterns = color.pattern != nil } else { block.fillPatterns = color.pattern != nil }
                if let pattern = color.pattern {
                    // A pattern takes a number never written before its own (`shadings` pattern-fill).
                    let index = patterns.firstIndex(where: { $0.pattern.key == pattern.key }) ?? {
                        patterns.append((pattern, next + 1))
                        next += 2
                        pendingPaints.append(.pattern(patterns.count - 1))
                        return patterns.count - 1
                    }()
                    if !resources.patterns.contains(index) { resources.patterns.append(index) }
                    // `/Pattern cs` only when the space changes (corpus: cwa's two-pattern icons).
                    if !patternSpace { units += ["/Pattern", stroke ? "CS" : "cs"] }
                    units += ["/P\(index + 1)", stroke ? "SCN" : "scn"]
                    if stroke { block.strokeSpace = nil } else { block.fillSpace = nil }
                    return
                }
                guard let space = color.space else {
                    units += color.components.map(number) + [stroke ? "K" : "k"]
                    return
                }
                let index = spaceIndex(space)
                if !resources.spaces.contains(index) { resources.spaces.append(index) }
                // A device color is written with its space each time, an ICCBased one's space only when
                // it changes (`icc`: same-twice, sc-only, icc-device-icc, device-cs-twice).
                let sameICCSpace: Bool
                if case .icc = space { sameICCSpace = space == written } else { sameICCSpace = false }
                if !sameICCSpace { units += ["/Cs\(index + 1)", stroke ? "CS" : "cs"] }
                units += color.components.map(number) + [stroke ? "SC" : "sc"]
                if stroke { block.strokeSpace = space } else { block.fillSpace = space }
            }
            /// The soft mask in force, written after everything else a drawing sets (`smasks`:
            /// fill, stroke, reset, in-q, group-do).
            func mask(_ softMask: PDFPage.SoftMask?) {
                guard softMask?.serial != block.softMask else { return }
                if let softMask {
                    softMasks[softMask.serial] = softMask
                    state(Self.maskMarker + "\(softMask.serial)")
                } else {
                    state("/SMask /None")
                }
                block.softMask = softMask?.serial
            }
            func open(_ allClips: [PDFPage.Clip], always: Bool = false) {
                let clips = allClips.filter(\.written)
                guard always || openClip != clips else { return }
                if openClip != nil { units.append("Q") }
                units.append("q")
                openClip = clips
                block = Block()
                units += clipUnits(clips)
            }
            /// What a drawing changes before it paints, in Quartz's order.
            func settings(_ drawing: PDFPage.Drawing) {
                    if drawing.stroke {
                        units += lineUnits(drawing.line, from: block.line)
                        block.line = drawing.line
                        if drawing.strokeSettings.adjust != block.strokeSettings.adjust { state("/SA \(drawing.strokeSettings.adjust)") }
                        block.strokeSettings.adjust = drawing.strokeSettings.adjust
                    }
                    let new = drawing.settings
                    if new.renderingIntent != block.settings.renderingIntent { units += ["/\(new.renderingIntent)", "ri"] }
                    if new.smoothness != block.settings.smoothness { state("/SM \(number(new.smoothness))") }
                    block.settings.renderingIntent = new.renderingIntent
                    block.settings.smoothness = new.smoothness
                    if drawing.fill {
                        if drawing.color != block.color || new.alpha != block.settings.alpha {
                            color(drawing.color, stroke: false)
                            block.color = drawing.color
                        }
                        if new.alpha != block.settings.alpha { state("/ca \(number(new.alpha))") }
                        if new.overprint != block.settings.overprint { state("/op \(new.overprint)") }
                        if new.overprintMode != block.settings.overprintMode { state("/OPM \(new.overprintMode)") }
                        block.settings = new
                    }
                    if drawing.stroke {
                        let stroke = drawing.strokeSettings
                        if drawing.strokeColor != block.strokeColor || stroke.alpha != block.strokeSettings.alpha {
                            color(drawing.strokeColor, stroke: true)
                            block.strokeColor = drawing.strokeColor
                        }
                        if stroke.alpha != block.strokeSettings.alpha { state("/CA \(number(stroke.alpha))") }
                        if stroke.overprint != block.strokeSettings.overprint {
                            // `OP` sets fill overprinting too where `op` is absent, so the fill's is written
                            // again after it (`strokes`: stroke-overprint, explicit-overprints).
                            state("/OP \(stroke.overprint)")
                            if stroke.overprint != block.settings.overprint { state("/op \(block.settings.overprint)") }
                        }
                        block.strokeSettings = stroke
                    }
            }
            /// Text: its paint, rendering mode and transformation, then its glyphs between `BT`
            /// and `ET` under the first glyph's em as `Tm`, a size of 1, the first space between
            /// glyphs as `Tc` unless a space is 0, the others as `TJ` numbers of thousandths (whole
            /// ones after a `Tc`, those rounding to 0 left out), `0 Tc` again unless a `Q` follows,
            /// a switch of font where its glyphs go to the PDF font's other Quartz font (`fonts`:
            /// tj, uneven, word-spacing, spacing, matrix, stroke-mode, invisible, twice; `fonts-3`
            /// named-tj, named-odd; `fonts-6`; corpus: cwa's `Illu_Onboarding_Getestet.pdf`).
            func text(_ run: PDFPage.TextRun) {
                let drawing = run.drawing
                open(drawing.clips)
                if run.mode != 3 { settings(drawing) }
                if run.mode != block.textMode { units += ["\(run.mode)", "Tr"] }
                block.textMode = run.mode
                mask(drawing.softMask)
                let matrix = drawing.matrix ?? PDFPage.Matrix()
                if !matrix.isIdentity { units += ["q", QuartzPDF.matrixUnit(matrix), "cm"] }
                let gaps = run.glyphs.dropFirst().map(\.gap)
                let spacing = gaps.contains { abs($0) < 1e-9 } ? 0 : gaps.first ?? 0
                units.append("BT")
                if spacing != 0 { units += [number(spacing), "Tc"] }
                units += [QuartzPDF.matrixUnit(run.matrix), "Tm"]
                var segment: (font: Int, parts: [String], numbers: Bool)?
                func flush() {
                    guard let segment else { return }
                    units += ["/\(textFonts[segment.font].name)", "1", "Tf"]
                    units += segment.numbers ? ["["] + segment.parts + ["]", "TJ"] : segment.parts + ["Tj"]
                }
                for (index, glyph) in run.glyphs.enumerated() {
                    let font = textFont(run.font, glyph: glyph)
                    if !resources.fonts.contains(font.font) { resources.fonts.append(font.font) }
                    if segment?.font != font.font {
                        flush()
                        segment = (font.font, [], false)
                    }
                    let shift = (spacing - glyph.gap) * 1000
                    if index > 0, abs(spacing == 0 ? shift : shift.rounded()) > 1e-6 {
                        segment!.parts.append(number(spacing == 0 ? shift : shift.rounded()))
                        segment!.numbers = true
                    }
                    if let last = segment!.parts.last, last.hasPrefix("(") {
                        segment!.parts[segment!.parts.count - 1] = String(last.dropLast()) + QuartzPDF.escaped(font.code) + ")"
                    } else {
                        segment!.parts.append("(" + QuartzPDF.escaped(font.code) + ")")
                    }
                }
                flush()
                if spacing != 0, matrix.isIdentity { units += ["0", "Tc"] }
                units.append("ET")
                if !matrix.isIdentity { units.append("Q") }
            }
            for item in items {
                let drawing: PDFPage.Drawing
                switch item {
                case .group(let group):
                    open(group.clips, always: true)
                    if group.alpha != block.settings.alpha {
                        state("/ca \(number(group.alpha))")
                        block.settings.alpha = group.alpha
                    }
                    // Overprinting and its mode as for a fill; a stroke opacity not at all (`groups-4`).
                    if group.overprint != block.settings.overprint { state("/op \(group.overprint)") }
                    if group.overprintMode != block.settings.overprintMode { state("/OPM \(group.overprintMode)") }
                    block.settings.overprint = group.overprint
                    block.settings.overprintMode = group.overprintMode
                    mask(group.softMask)
                    forms += 1
                    resources.xobjects.append(.form(Form(name: forms, resources: next, number: next + 1, group: group)))
                    next += 2
                    units += ["/Fm\(forms)", "Do"]
                    continue
                case .image(let image):
                    // The image is numbered before a stencil's color space (`images` stencil).
                    let index = images.firstIndex(where: { $0.image.key == image.key }) ?? {
                        images.append((image, next, false))
                        next += 1
                        return images.count - 1
                    }()
                    open(image.clips)
                    // Its rendering intent first, its opacity and overprinting after its color, as a
                    // fill's (`images-2`; corpus: kickstarter's `icon--currency-header.pdf`).
                    if image.renderingIntent != block.settings.renderingIntent {
                        units += ["/\(image.renderingIntent)", "ri"]
                        block.settings.renderingIntent = image.renderingIntent
                    }
                    if image.samples.space == nil, image.color != block.color || image.alpha != block.settings.alpha {
                        color(image.color, stroke: false)
                        block.color = image.color
                    }
                    if image.alpha != block.settings.alpha {
                        state("/ca \(number(image.alpha))")
                        block.settings.alpha = image.alpha
                    }
                    if image.overprint != block.settings.overprint { state("/op \(image.overprint)") }
                    if image.overprintMode != block.settings.overprintMode { state("/OPM \(image.overprintMode)") }
                    block.settings.overprint = image.overprint
                    block.settings.overprintMode = image.overprintMode
                    mask(image.softMask)
                    if !resources.xobjects.contains(where: { if case .image(index) = $0 { true } else { false } }) { resources.xobjects.append(.image(index)) }
                    let matrix = image.matrix
                    units += ["q", QuartzPDF.matrixUnit(matrix), "cm", "/Im\(index + 1)", "Do", "Q"]
                    continue
                case .shading(let fill):
                    let index = shadings.firstIndex(where: { $0.shading.key == fill.shading.key }) ?? {
                        shadings.append((fill.shading, next))
                        next += 1
                        pendingPaints.append(.shading(shadings.count - 1))
                        return shadings.count - 1
                    }()
                    if !resources.shadings.contains(index) { resources.shadings.append(index) }
                    open(fill.clips)
                    // Its rendering intent, then its opacity, overprinting and its mode, as a fill's
                    // (corpus: cwa's `Corona-Warn-App.pdf`; `shadings-2`).
                    if fill.renderingIntent != block.settings.renderingIntent {
                        units += ["/\(fill.renderingIntent)", "ri"]
                        block.settings.renderingIntent = fill.renderingIntent
                    }
                    if fill.alpha != block.settings.alpha {
                        state("/ca \(number(fill.alpha))")
                        block.settings.alpha = fill.alpha
                    }
                    if fill.overprint != block.settings.overprint { state("/op \(fill.overprint)") }
                    if fill.overprintMode != block.settings.overprintMode { state("/OPM \(fill.overprintMode)") }
                    block.settings.overprint = fill.overprint
                    block.settings.overprintMode = fill.overprintMode
                    mask(fill.softMask)
                    let matrix = fill.matrix
                    units += matrix.isIdentity ? ["/Sh\(index + 1)", "sh"]
                        : ["q", QuartzPDF.matrixUnit(matrix), "cm", "/Sh\(index + 1)", "sh", "Q"]
                    continue
                case .text(let run):
                    text(run)
                    continue
                case .drawing(let value):
                    drawing = value
                }
                open(drawing.clips)
                settings(drawing)
                mask(drawing.softMask)
                let paint = drawing.fill ? (drawing.stroke ? (drawing.evenOdd ? "B*" : "B") : (drawing.evenOdd ? "f*" : "f")) : "S"
                if let matrix = drawing.matrix {
                    units += ["q", QuartzPDF.matrixUnit(matrix), "cm"] + pathUnits(drawing.path) + [paint, "Q"]
                } else {
                    units += pathUnits(drawing.path) + [paint]
                }
            }
            if openClip != nil { units.append("Q") }
            return deflate(Writer.latin1(Writer.wrapped(units)))
        }
    }

    /// What a block has written so far.
    private struct Block {
        var color = PDFPage.Color.black
        var settings = PDFPage.Settings()
        var fillSpace: PDFPage.ColorSpace?
        var strokeColor = PDFPage.Color.black
        var strokeSettings = PDFPage.StrokeSettings()
        var strokeSpace: PDFPage.ColorSpace?
        var line = PDFPage.Line()
        var softMask: Int?
        var fillPatterns = false
        var strokePatterns = false
        var textMode = 0
    }

    /// The line settings that differ from `previous`, in Quartz's order (`strokes`).
    static func lineUnits(_ line: PDFPage.Line, from previous: PDFPage.Line) -> [String] {
        var units: [String] = []
        if line.width != previous.width { units += [number(line.width), "w"] }
        if line.cap != previous.cap { units += ["\(line.cap)", "J"] }
        if line.join != previous.join { units += ["\(line.join)", "j"] }
        if line.miterLimit != previous.miterLimit { units += [number(line.miterLimit), "M"] }
        if line.dash != previous.dash || line.phase != previous.phase { units += ["["] + line.dash.map(number) + ["]", number(line.phase), "d"] }
        return units
    }

    /// A clip's paths: in order those that are not rectangles, then the rectangles'
    /// intersection, even-odd ones included, as `W` (`clips` two-clips, `details`
    /// clip-rect-curve, `rect-forms` even-odd cases).
    static func clipUnits(_ clips: [PDFPage.Clip]) -> [String] {
        var units: [String] = []
        var rectangle: PDFPage.Rect?
        for clip in clips {
            if let rect = clip.path.rectangle {
                rectangle = rectangle.map { $0.intersection(rect) } ?? rect
            } else {
                units += pathUnits(clip.path) + [clip.evenOdd ? "W*" : "W", "n"]
            }
        }
        if let rectangle { units += [rectangleUnit(rectangle), "re", "W", "n"] }
        return units
    }

    /// A path's units: one rectangle as `re`, otherwise each element (`paths`).
    static func pathUnits(_ path: PDFPage.Path) -> [String] {
        if let rect = path.rectangle { return [rectangleUnit(rect), "re"] }
        var units: [String] = []
        for element in path.elements {
            switch element {
            case .move(let point): units += [number(point.x), number(point.y), "m"]
            case .line(let point): units += [number(point.x), number(point.y), "l"]
            case .curve(let a, let b, let point): units += [a.x, a.y, b.x, b.y, point.x, point.y].map(number) + ["c"]
            case .close: units.append("h")
            }
        }
        return units
    }

    /// A matrix's six numbers, one unit for the line breaks (`fonts` two-runs, two-fonts; corpus:
    /// wikipedia's `places-show-more.pdf` and `description-cat.pdf`, a `Tm` and two `cm`).
    static func matrixUnit(_ matrix: PDFPage.Matrix) -> String {
        [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f].map(number).joined(separator: " ")
    }

    static func rectangleUnit(_ rect: PDFPage.Rect) -> String {
        "\(number(rect.minX)) \(number(rect.minY)) \(number(rect.maxX - rect.minX)) \(number(rect.maxY - rect.minY))"
    }

    /// A code in a text string: `(`, `)` and `\\` escaped, control codes in octal (`cff`
    /// odd-names), others as they are (`fonts-4` mac-names).
    static func escaped(_ code: Int) -> String {
        if code < 0x20 { return String(format: "\\%03o", code) }
        let character = String(UnicodeScalar(UInt8(code)))
        return "()\\".contains(character) ? "\\" + character : character
    }

    /// A text string as Quartz writes it, one character per byte of the result: ASCII as it is,
    /// anything else in UTF-16BE after a byte order mark; `(`, `)` and `\\` escaped, control
    /// bytes in octal (`info`: producer-escapes, producer-hex, producer-latin1).
    static func literal(_ text: String) -> String {
        let bytes: [UInt8] = text.unicodeScalars.allSatisfy(\.isASCII)
            ? Array(text.utf8)
            : [0xFE, 0xFF] + text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        var result = "("
        for byte in bytes {
            switch byte {
            case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "\\"): result += "\\" + String(UnicodeScalar(byte))
            case 0..<0x20: result += "\\" + String(format: "%03o", byte)
            default: result.unicodeScalars.append(UnicodeScalar(byte))
            }
        }
        return result + ")"
    }

    /// A number as Quartz writes it: the nearest integer when within a millionth of it. Below 1,
    /// the fewest decimals whose value scaled to the last one is within 1e-5 of an integer, else
    /// seven significant digits with their trailing zeros; from 1, seven significant digits without
    /// trailing zeros. No exponent (`number-values` to `number-values-5`, 1,554 numbers of cwa's
    /// `Stars_half.pdf`; 0.025000025 and 0.000100001 are written otherwise, B-216).
    static func number(_ value: Double) -> String {
        let nearest = value.rounded()
        if abs(value - nearest) < 1e-6 { return nearest == 0 ? "0" : String(Int64(nearest)) }
        let magnitude = Int(floor(log10(abs(value))))
        let decimals = max(0, 6 - magnitude)
        if abs(value) < 1 {
            for places in 1..<decimals {
                let scaled = value * pow(10, Double(places))
                let whole = scaled.rounded()
                if whole != 0, abs(scaled - whole) < 1e-5 { return String(format: "%.\(places)f", whole / pow(10, Double(places))) }
            }
            return String(format: "%.\(decimals)f", value)
        }
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// zlib at level 1 with the default window and memory, as every stream Quartz writes.
    static func deflate(_ data: [UInt8]) -> [UInt8] {
        var stream = z_stream()
        deflateInit_(&stream, 1, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        defer { deflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(data.count))))
        var input = data
        input.withUnsafeMutableBufferPointer { source in
            output.withUnsafeMutableBufferPointer { target in
                stream.next_in = source.baseAddress
                stream.avail_in = uInt(source.count)
                stream.next_out = target.baseAddress
                stream.avail_out = uInt(target.count)
                _ = CZlib.deflate(&stream, Z_FINISH)
            }
        }
        return Array(output.prefix(Int(stream.total_out)))
    }

    /// The bytes of the file, with the offsets of its objects for the cross-reference table.
    struct Writer {
        private(set) var bytes: [UInt8] = []
        private var offsets: [Int: Int] = [:]

        mutating func header() {
            bytes += Array("%PDF-1.3\n%".utf8) + [0xC4, 0xE5, 0xF2, 0xE5, 0xEB, 0xA7, 0xF3, 0xA0, 0xD0, 0xC4, 0xC6, 0x0A]
        }

        mutating func object(_ number: Int, _ body: String) {
            offsets[number] = bytes.count
            bytes += Self.latin1("\(number) 0 obj\n\(body)\nendobj\n")
        }

        mutating func stream(_ number: Int, dictionary: [String], data: [UInt8], filter: String = "/FlateDecode") {
            offsets[number] = bytes.count
            let header = Self.wrapped(["<<"] + dictionary + ["/Length", "\(data.count)", "/Filter", filter, ">>"])
            bytes += Array("\(number) 0 obj\n\(header)\nstream\n".utf8) + data + Array("\nendstream\nendobj\n".utf8)
        }

        mutating func trailer(root: Int, info: Int, identifiers: ([UInt8], [UInt8])?) {
            let start = bytes.count
            let count = (offsets.keys.max() ?? 0) + 1
            var table = "xref\n0 \(count)\n0000000000 65535 f \n"
            for number in 1..<count {
                table += String(format: "%010d 00000 n \n", offsets[number] ?? 0)
            }
            let ids = [identifiers?.0 ?? [UInt8](repeating: 0, count: 16), identifiers?.1 ?? [UInt8](repeating: 0, count: 16)]
                .map { "<" + $0.map { String(format: "%02x", $0) }.joined() + ">" }
            let dictionary = Self.wrapped(["<<", "/Size", "\(count)", "/Root", "\(root)", "0", "R", "/Info", "\(info)", "0", "R", "/ID", "["] + ids + ["]", ">>"])
            bytes += Array((table + "trailer\n" + dictionary + "\nstartxref\n\(start)\n%%EOF\n").utf8)
        }

        /// Text whose characters are bytes (`literal`'s strings).
        static func latin1(_ text: String) -> [UInt8] { text.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) } }

        /// Units separated by spaces, a line break instead once a line is past column 72: each
        /// number, name and operator a unit, but a rectangle's four numbers one and a matrix's six (every content
        /// stream of `pdf_experiments.py`, and cwa's `Icon_Modify.pdf`, which breaks between a
        /// point's coordinates).
        static func wrapped(_ units: [String]) -> String {
            var text = ""
            var column = 0
            for (index, unit) in units.enumerated() {
                text += unit
                column += unit.count
                guard index < units.count - 1 else { break }
                if column > 72 {
                    text += "\n"
                    column = 0
                } else {
                    text += " "
                    column += 1
                }
            }
            return text
        }
    }
}
