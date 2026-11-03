/// The simple-font encodings Quartz reads and writes text with (PDF 1.7 annex D) and the
/// TrueType glyph names it knows (`pdf_experiments.py` fonts-3, fonts-4).
enum PDFEncoding {
    case macRoman
    case winAnsi

    /// The Unicode value of a code, `nil` where the encoding has none.
    func unicode(_ code: Int) -> Int? {
        guard code >= 128 else { return code >= 32 ? code : nil }
        let value = (self == .macRoman ? Self.macRomanUnicode : Self.winAnsiUnicode)[code - 128]
        return value == 0 ? nil : value
    }

    /// MacRomanEncoding's code of a glyph name, its first where it has two (`fonts-4` mac-names:
    /// `space` at 32, `currency` at 219, the mathematical symbols and `apple` not in it), and
    /// `.notdef` at 0 (`cff` odd-names).
    static let macRomanCodes: [String: Int] = [
        ".notdef": 0,
        "space": 32, "exclam": 33, "quotedbl": 34, "numbersign": 35, "dollar": 36, "percent": 37,
        "ampersand": 38, "quotesingle": 39, "parenleft": 40, "parenright": 41, "asterisk": 42, "plus": 43,
        "comma": 44, "hyphen": 45, "period": 46, "slash": 47, "zero": 48, "one": 49,
        "two": 50, "three": 51, "four": 52, "five": 53, "six": 54, "seven": 55,
        "eight": 56, "nine": 57, "colon": 58, "semicolon": 59, "less": 60, "equal": 61,
        "greater": 62, "question": 63, "at": 64, "A": 65, "B": 66, "C": 67,
        "D": 68, "E": 69, "F": 70, "G": 71, "H": 72, "I": 73,
        "J": 74, "K": 75, "L": 76, "M": 77, "N": 78, "O": 79,
        "P": 80, "Q": 81, "R": 82, "S": 83, "T": 84, "U": 85,
        "V": 86, "W": 87, "X": 88, "Y": 89, "Z": 90, "bracketleft": 91,
        "backslash": 92, "bracketright": 93, "asciicircum": 94, "underscore": 95, "grave": 96, "a": 97,
        "b": 98, "c": 99, "d": 100, "e": 101, "f": 102, "g": 103,
        "h": 104, "i": 105, "j": 106, "k": 107, "l": 108, "m": 109,
        "n": 110, "o": 111, "p": 112, "q": 113, "r": 114, "s": 115,
        "t": 116, "u": 117, "v": 118, "w": 119, "x": 120, "y": 121,
        "z": 122, "braceleft": 123, "bar": 124, "braceright": 125, "asciitilde": 126, "Adieresis": 128,
        "Aring": 129, "Ccedilla": 130, "Eacute": 131, "Ntilde": 132, "Odieresis": 133, "Udieresis": 134,
        "aacute": 135, "agrave": 136, "acircumflex": 137, "adieresis": 138, "atilde": 139, "aring": 140,
        "ccedilla": 141, "eacute": 142, "egrave": 143, "ecircumflex": 144, "edieresis": 145, "iacute": 146,
        "igrave": 147, "icircumflex": 148, "idieresis": 149, "ntilde": 150, "oacute": 151, "ograve": 152,
        "ocircumflex": 153, "odieresis": 154, "otilde": 155, "uacute": 156, "ugrave": 157, "ucircumflex": 158,
        "udieresis": 159, "dagger": 160, "degree": 161, "cent": 162, "sterling": 163, "section": 164,
        "bullet": 165, "paragraph": 166, "germandbls": 167, "registered": 168, "copyright": 169, "trademark": 170,
        "acute": 171, "dieresis": 172, "AE": 174, "Oslash": 175, "plusminus": 177, "yen": 180,
        "mu": 181, "ordfeminine": 187, "ordmasculine": 188, "ae": 190, "oslash": 191, "questiondown": 192,
        "exclamdown": 193, "logicalnot": 194, "florin": 196, "guillemotleft": 199, "guillemotright": 200, "ellipsis": 201,
        "Agrave": 203, "Atilde": 204, "Otilde": 205, "OE": 206, "oe": 207, "endash": 208,
        "emdash": 209, "quotedblleft": 210, "quotedblright": 211, "quoteleft": 212, "quoteright": 213, "divide": 214,
        "ydieresis": 216, "Ydieresis": 217, "fraction": 218, "currency": 219, "guilsinglleft": 220, "guilsinglright": 221,
        "fi": 222, "fl": 223, "daggerdbl": 224, "periodcentered": 225, "quotesinglbase": 226, "quotedblbase": 227,
        "perthousand": 228, "Acircumflex": 229, "Ecircumflex": 230, "Aacute": 231, "Edieresis": 232, "Egrave": 233,
        "Iacute": 234, "Icircumflex": 235, "Idieresis": 236, "Igrave": 237, "Oacute": 238, "Ocircumflex": 239,
        "Ograve": 241, "Uacute": 242, "Ucircumflex": 243, "Ugrave": 244, "dotlessi": 245, "circumflex": 246,
        "tilde": 247, "macron": 248, "breve": 249, "dotaccent": 250, "ring": 251, "cedilla": 252,
        "hungarumlaut": 253, "ogonek": 254, "caron": 255,
    ]

    /// MacRomanEncoding's glyph names by code.
    static let macRomanNames: [Int: String] = Dictionary(macRomanCodes.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

    /// The glyph names of WinAnsiEncoding outside MacRomanEncoding, whose Unicode values Quartz
    /// writes for them (`fonts-4` other-names; `Lslash`, `minus` and `uni0416` take the code's).
    static let winAnsiNames: [String: Int] = [
        "Euro": 0x20AC, "Scaron": 0x0160, "scaron": 0x0161, "Zcaron": 0x017D, "zcaron": 0x017E,
        "brokenbar": 0x00A6, "Eth": 0x00D0, "eth": 0x00F0, "Yacute": 0x00DD, "yacute": 0x00FD,
        "Thorn": 0x00DE, "thorn": 0x00FE, "onesuperior": 0x00B9, "twosuperior": 0x00B2, "threesuperior": 0x00B3,
        "onehalf": 0x00BD, "onequarter": 0x00BC, "threequarters": 0x00BE, "multiply": 0x00D7,
    ]

    /// The 258 standard Macintosh glyph names, in their order, of a `post` table's glyph indices
    /// below 258.
    static let macintoshGlyphNames: [String] = [
        ".notdef", ".null", "nonmarkingreturn", "space", "exclam", "quotedbl", "numbersign", "dollar",
        "percent", "ampersand", "quotesingle", "parenleft", "parenright", "asterisk", "plus", "comma",
        "hyphen", "period", "slash", "zero", "one", "two", "three", "four",
        "five", "six", "seven", "eight", "nine", "colon", "semicolon", "less",
        "equal", "greater", "question", "at", "A", "B", "C", "D",
        "E", "F", "G", "H", "I", "J", "K", "L",
        "M", "N", "O", "P", "Q", "R", "S", "T",
        "U", "V", "W", "X", "Y", "Z", "bracketleft", "backslash",
        "bracketright", "asciicircum", "underscore", "grave", "a", "b", "c", "d",
        "e", "f", "g", "h", "i", "j", "k", "l",
        "m", "n", "o", "p", "q", "r", "s", "t",
        "u", "v", "w", "x", "y", "z", "braceleft", "bar",
        "braceright", "asciitilde", "Adieresis", "Aring", "Ccedilla", "Eacute", "Ntilde", "Odieresis",
        "Udieresis", "aacute", "agrave", "acircumflex", "adieresis", "atilde", "aring", "ccedilla",
        "eacute", "egrave", "ecircumflex", "edieresis", "iacute", "igrave", "icircumflex", "idieresis",
        "ntilde", "oacute", "ograve", "ocircumflex", "odieresis", "otilde", "uacute", "ugrave",
        "ucircumflex", "udieresis", "dagger", "degree", "cent", "sterling", "section", "bullet",
        "paragraph", "germandbls", "registered", "copyright", "trademark", "acute", "dieresis", "notequal",
        "AE", "Oslash", "infinity", "plusminus", "lessequal", "greaterequal", "yen", "mu",
        "partialdiff", "summation", "product", "pi", "integral", "ordfeminine", "ordmasculine", "Omega",
        "ae", "oslash", "questiondown", "exclamdown", "logicalnot", "radical", "florin", "approxequal",
        "Delta", "guillemotleft", "guillemotright", "ellipsis", "nonbreakingspace", "Agrave", "Atilde", "Otilde",
        "OE", "oe", "endash", "emdash", "quotedblleft", "quotedblright", "quoteleft", "quoteright",
        "divide", "lozenge", "ydieresis", "Ydieresis", "fraction", "currency", "guilsinglleft", "guilsinglright",
        "fi", "fl", "daggerdbl", "periodcentered", "quotesinglbase", "quotedblbase", "perthousand", "Acircumflex",
        "Ecircumflex", "Aacute", "Edieresis", "Egrave", "Iacute", "Icircumflex", "Idieresis", "Igrave",
        "Oacute", "Ocircumflex", "apple", "Ograve", "Uacute", "Ucircumflex", "Ugrave", "dotlessi",
        "circumflex", "tilde", "macron", "breve", "dotaccent", "ring", "cedilla", "hungarumlaut",
        "ogonek", "caron", "Lslash", "lslash", "Scaron", "scaron", "Zcaron", "zcaron",
        "brokenbar", "Eth", "eth", "Yacute", "yacute", "Thorn", "thorn", "minus",
        "multiply", "onesuperior", "twosuperior", "threesuperior", "onehalf", "onequarter", "threequarters", "franc",
        "Gbreve", "gbreve", "Idotaccent", "Scedilla", "scedilla", "Cacute", "cacute", "Ccaron",
        "ccaron", "dcroat",
    ]

    /// The Unicode values of MacRomanEncoding's codes 128 to 255.
    static let macRomanUnicode: [Int] = [
        0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1, 0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8,
        0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3, 0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC,
        0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF, 0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,
        0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211, 0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x03A9, 0x00E6, 0x00F8,
        0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB, 0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153,
        0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA, 0x00FF, 0x0178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
        0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1, 0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4,
        0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC, 0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7,
    ]

    /// The Unicode values of WinAnsiEncoding's codes 128 to 255 (0 where it has none).
    static let winAnsiUnicode: [Int] = [
        0x20AC, 0x0000, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x0000, 0x017D, 0x0000,
        0x0000, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x0000, 0x017E, 0x0178,
        0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7, 0x00A8, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
        0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, 0x00B8, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF,
        0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00C6, 0x00C7, 0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF,
        0x00D0, 0x00D1, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6, 0x00D7, 0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00DD, 0x00DE, 0x00DF,
        0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5, 0x00E6, 0x00E7, 0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF,
        0x00F0, 0x00F1, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00F7, 0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x00FD, 0x00FE, 0x00FF,
    ]

    /// The CFF standard strings 0 to 228, the glyph names of string identifiers below 229 (the
    /// Compact Font Format specification, appendix A; 229 to 390, expert names, not kept).
    static let cffStandardStrings: [String] = [
        ".notdef", "space", "exclam", "quotedbl", "numbersign", "dollar", "percent", "ampersand", "quoteright",
        "parenleft", "parenright", "asterisk", "plus", "comma", "hyphen", "period", "slash", "zero",
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "colon", "semicolon", "less", "equal", "greater", "question", "at", "A", "B",
        "C", "D", "E", "F", "G", "H", "I", "J", "K",
        "L", "M", "N", "O", "P", "Q", "R", "S", "T",
        "U", "V", "W", "X", "Y", "Z", "bracketleft", "backslash", "bracketright",
        "asciicircum", "underscore", "quoteleft", "a", "b", "c", "d", "e", "f",
        "g", "h", "i", "j", "k", "l", "m", "n", "o",
        "p", "q", "r", "s", "t", "u", "v", "w", "x",
        "y", "z", "braceleft", "bar", "braceright", "asciitilde", "exclamdown", "cent", "sterling",
        "fraction", "yen", "florin", "section", "currency", "quotesingle", "quotedblleft", "guillemotleft", "guilsinglleft",
        "guilsinglright", "fi", "fl", "endash", "dagger", "daggerdbl", "periodcentered", "paragraph", "bullet",
        "quotesinglbase", "quotedblbase", "quotedblright", "guillemotright", "ellipsis", "perthousand", "questiondown", "grave", "acute",
        "circumflex", "tilde", "macron", "breve", "dotaccent", "dieresis", "ring", "cedilla", "hungarumlaut",
        "ogonek", "caron", "emdash", "AE", "ordfeminine", "Lslash", "Oslash", "OE", "ordmasculine",
        "ae", "dotlessi", "lslash", "oslash", "oe", "germandbls", "onesuperior", "logicalnot", "mu",
        "trademark", "Eth", "onehalf", "plusminus", "Thorn", "onequarter", "divide", "brokenbar", "degree",
        "thorn", "threequarters", "twosuperior", "registered", "minus", "eth", "multiply", "threesuperior", "copyright",
        "Aacute", "Acircumflex", "Adieresis", "Agrave", "Aring", "Atilde", "Ccedilla", "Eacute", "Ecircumflex",
        "Edieresis", "Egrave", "Iacute", "Icircumflex", "Idieresis", "Igrave", "Ntilde", "Oacute", "Ocircumflex",
        "Odieresis", "Ograve", "Otilde", "Scaron", "Uacute", "Ucircumflex", "Udieresis", "Ugrave", "Yacute",
        "Ydieresis", "Zcaron", "aacute", "acircumflex", "adieresis", "agrave", "aring", "atilde", "ccedilla",
        "eacute", "ecircumflex", "edieresis", "egrave", "iacute", "icircumflex", "idieresis", "igrave", "ntilde",
        "oacute", "ocircumflex", "odieresis", "ograve", "otilde", "scaron", "uacute", "ucircumflex", "udieresis",
        "ugrave", "yacute", "ydieresis", "zcaron",
    ]

    /// StandardEncoding's glyph names by code (PDF 1.7 annex D), a CFF font's built-in encoding.
    static let standardNames: [Int: String] = [
        32: "space", 33: "exclam", 34: "quotedbl", 35: "numbersign", 36: "dollar", 37: "percent", 38: "ampersand",
        39: "quoteright", 40: "parenleft", 41: "parenright", 42: "asterisk", 43: "plus", 44: "comma", 45: "hyphen",
        46: "period", 47: "slash", 48: "zero", 49: "one", 50: "two", 51: "three", 52: "four",
        53: "five", 54: "six", 55: "seven", 56: "eight", 57: "nine", 58: "colon", 59: "semicolon",
        60: "less", 61: "equal", 62: "greater", 63: "question", 64: "at", 65: "A", 66: "B",
        67: "C", 68: "D", 69: "E", 70: "F", 71: "G", 72: "H", 73: "I",
        74: "J", 75: "K", 76: "L", 77: "M", 78: "N", 79: "O", 80: "P",
        81: "Q", 82: "R", 83: "S", 84: "T", 85: "U", 86: "V", 87: "W",
        88: "X", 89: "Y", 90: "Z", 91: "bracketleft", 92: "backslash", 93: "bracketright", 94: "asciicircum",
        95: "underscore", 96: "quoteleft", 97: "a", 98: "b", 99: "c", 100: "d", 101: "e",
        102: "f", 103: "g", 104: "h", 105: "i", 106: "j", 107: "k", 108: "l",
        109: "m", 110: "n", 111: "o", 112: "p", 113: "q", 114: "r", 115: "s",
        116: "t", 117: "u", 118: "v", 119: "w", 120: "x", 121: "y", 122: "z",
        123: "braceleft", 124: "bar", 125: "braceright", 126: "asciitilde", 161: "exclamdown", 162: "cent", 163: "sterling",
        164: "fraction", 165: "yen", 166: "florin", 167: "section", 168: "currency", 169: "quotesingle", 170: "quotedblleft",
        171: "guillemotleft", 172: "guilsinglleft", 173: "guilsinglright", 174: "fi", 175: "fl", 177: "endash", 178: "dagger",
        179: "daggerdbl", 180: "periodcentered", 182: "paragraph", 183: "bullet", 184: "quotesinglbase", 185: "quotedblbase", 186: "quotedblright",
        187: "guillemotright", 188: "ellipsis", 189: "perthousand", 191: "questiondown", 193: "grave", 194: "acute", 195: "circumflex",
        196: "tilde", 197: "macron", 198: "breve", 199: "dotaccent", 200: "dieresis", 202: "ring", 203: "cedilla",
        205: "hungarumlaut", 206: "ogonek", 207: "caron", 208: "emdash", 225: "AE", 227: "ordfeminine", 232: "Lslash",
        233: "Oslash", 234: "OE", 235: "ordmasculine", 241: "ae", 245: "dotlessi", 248: "lslash", 249: "oslash",
        250: "oe", 251: "germandbls",
    ]
}
