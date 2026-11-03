import Foundation
import NomacCore
import Testing
@testable import NomacStrings

/// What Xcode 27.0's builds make of self-written `.strings` and `.stringsdict` files (the `copy`
/// experiment of `.github/scripts/strings_experiments.py`), stated as the facts of
/// docs/formats/property-lists.md "Binary" and docs/formats/strings.md "Copied strings files":
/// the objects of each binary property list in order, with the sizes of its offsets and
/// references, and the text encodings' rules.
@Suite struct StringsFileCopyTests {
    enum Input {
        case text(String)
        case hex(String)
        /// A strings file of `"key" = "value";` lines.
        case pairs([(String, String)])

        var bytes: [UInt8] {
            switch self {
            case .text(let text): Array(text.utf8)
            case .hex(let hex): hexBytes(hex)
            case .pairs(let pairs): Array(pairs.map { "\"\($0.0)\" = \"\($0.1)\";\n" }.joined().utf8)
            }
        }
    }

    /// Objects as `{key refs: value refs}`, `[refs]`, `s:` ASCII and `u:` UTF-16 strings, `iN:`
    /// integers of N bytes, `r:` reals, `d:` data, `date:`, `true`, `false`.
    enum Objects {
        case objects([String])
        /// A strings table by the rules: the dictionary, its keys in Swift's order, then each value
        /// that is not already an object.
        case table([(String, String)])

        var notation: [String] {
            switch self {
            case .objects(let objects):
                return objects
            case .table(let pairs):
                let sorted = Dictionary(pairs, uniquingKeysWith: { $1 }).sorted { $0.key < $1.key }
                var strings: [String] = []
                func reference(_ string: String) -> Int {
                    if let index = strings.firstIndex(of: string) { return index + 1 }
                    strings.append(string)
                    return strings.count
                }
                let keys = sorted.map { reference($0.key) }
                let values = sorted.map { reference($0.value) }
                let dictionary = "{" + zip(keys, values).map { "\($0):\($1)" }.joined(separator: ",") + "}"
                return [dictionary] + strings.map { ($0.unicodeScalars.allSatisfy(\.isASCII) ? "s:" : "u:") + $0 }
            }
        }
    }

    static func key(_ prefix: String, _ number: Int, _ digits: Int) -> String {
        prefix + String(repeating: "0", count: max(0, digits - String(number).count)) + String(number)
    }

    /// (file, input, objects, offset size, reference size, detected encoding)
    static let binary: [(String, Input, Objects, Int, Int, String?)] = [
        ("simple.strings", .text("\"key\" = \"value\";\n"), .objects(["{1:2}", "s:key", "s:value"]), 1, 1, "Unicode (UTF-8)"),
        ("empty.strings", .text(""), .objects(["{}"]), 1, 1, nil),
        ("whitespace.strings", .text("\n  \n"), .objects(["{}"]), 1, 1, "Unicode (UTF-8)"),
        ("comments.strings", .text("/* a comment */\n// another\n"), .objects(["{}"]), 1, 1, "Unicode (UTF-8)"),
        ("two.strings", .text("\"b\" = \"2\";\n\"a\" = \"1\";\n"), .objects(["{1:3,2:4}", "s:a", "s:b", "s:1", "s:2"]), 1, 1, "Unicode (UTF-8)"),
        ("unsorted.strings", .text("\"zeta\" = \"z\";\n\"Alpha\" = \"A\";\n\"alpha\" = \"a\";\n\"_x\" = \"u\";\n\"10\" = \"ten\";\n\"9\" = \"nine\";\n"), .objects(["{1:7,2:8,3:9,4:10,5:11,6:12}", "s:10", "s:9", "s:Alpha", "s:_x", "s:alpha", "s:zeta", "s:ten", "s:nine", "s:A", "s:u", "s:a", "s:z"]), 1, 1, "Unicode (UTF-8)"),
        ("same-values.strings", .text("\"a\" = \"same\";\n\"b\" = \"same\";\n\"c\" = \"other\";\n"), .objects(["{1:4,2:4,3:5}", "s:a", "s:b", "s:c", "s:same", "s:other"]), 1, 1, "Unicode (UTF-8)"),
        ("key-is-value.strings", .text("\"a\" = \"b\";\n\"b\" = \"a\";\n"), .objects(["{1:2,2:1}", "s:a", "s:b"]), 1, 1, "Unicode (UTF-8)"),
        ("shorthand.strings", .text("\"key\";\n"), .objects(["{1:1}", "s:key"]), 1, 1, "Unicode (UTF-8)"),
        ("unquoted.strings", .text("key = value;\nother = \"x y\";\n"), .objects(["{1:3,2:4}", "s:key", "s:other", "s:value", "s:x y"]), 1, 1, "Unicode (UTF-8)"),
        ("escapes.strings", .text("\"k1\" = \"line\\nnext\";\n\"k2\" = \"tab\\tq\\\"b\\\\\";\n\"k3\" = \"\\U00e9\\U2603\";\n\"k4\" = \"\\101\\102\";\n"), .objects(["{1:5,2:6,3:7,4:8}", "s:k1", "s:k2", "s:k3", "s:k4", "s:line\nnext", "s:tab\tq\"b\\", "u:\u{E9}\u{2603}", "s:AB"]), 1, 1, "Unicode (UTF-8)"),
        ("unicode.strings", .text("\"caf\u{E9}\" = \"na\u{EF}ve \u{2603} \u{1F600}\";\n\"ascii\" = \"plain\";\n"), .objects(["{1:3,2:4}", "s:ascii", "u:caf\u{E9}", "s:plain", "u:na\u{EF}ve \u{2603} \u{1F600}"]), 1, 1, "Unicode (UTF-8)"),
        ("utf8-bom.strings", .hex("efbbbf226b657922203d202276616c7565223b0a"), .objects(["{1:2}", "s:key", "s:value"]), 1, 1, "Unicode (UTF-8)"),
        ("utf16le-bom.strings", .hex("fffe22006b0065007900220020003d0020002200760061006c007500650022003b000a002200e900220020003d0020002200e80022003b000a00"), .objects(["{1:3,2:4}", "s:key", "u:\u{E9}", "s:value", "u:\u{E8}"]), 1, 1, "Unicode (UTF-16)"),
        ("utf16be-bom.strings", .hex("feff0022006b0065007900220020003d0020002200760061006c007500650022003b000a"), .objects(["{1:2}", "s:key", "s:value"]), 1, 1, "Unicode (UTF-16)"),
        ("long-14.strings", .text("\"k\" = \"12345678901234\";\n"), .objects(["{1:2}", "s:k", "s:12345678901234"]), 1, 1, "Unicode (UTF-8)"),
        ("long-15.strings", .text("\"k\" = \"123456789012345\";\n"), .objects(["{1:2}", "s:k", "s:123456789012345"]), 1, 1, "Unicode (UTF-8)"),
        ("long-300.strings", .text("\"k\" = \"" + String(repeating: "x", count: 300) + "\";\n"), .objects(["{1:2}", "s:k", "s:" + String(repeating: "x", count: 300)]), 2, 1, "Unicode (UTF-8)"),
        ("long-70000.strings", .text("\"k\" = \"" + String(repeating: "y", count: 70000) + "\";\n"), .objects(["{1:2}", "s:k", "s:" + String(repeating: "y", count: 70000)]), 4, 1, "Unicode (UTF-8)"),
        ("unicode-long.strings", .text("\"k\" = \"" + String(repeating: "\u{E9}", count: 20) + "\";\n"), .objects(["{1:2}", "s:k", "u:\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}"]), 1, 1, "Unicode (UTF-8)"),
        ("many-20.strings", .pairs((0..<20).map { (Self.key("k", $0, 4), "value \($0)") }), .table((0..<20).map { (Self.key("k", $0, 4), "value \($0)") }), 2, 1, "Unicode (UTF-8)"),
        ("many-200.strings", .pairs((0..<200).map { (Self.key("k", $0, 4), "value \($0)") }), .table((0..<200).map { (Self.key("k", $0, 4), "value \($0)") }), 2, 2, "Unicode (UTF-8)"),
        ("many-300.strings", .pairs((0..<300).map { (Self.key("k", $0, 4), "value \($0)") }), .table((0..<300).map { (Self.key("k", $0, 4), "value \($0)") }), 2, 2, "Unicode (UTF-8)"),
        ("nested.strings", .text("\"array\" = (\"a\", \"b\");\n\"dict\" = { \"x\" = \"1\"; };\n"), .objects(["{1:3,2:6}", "s:array", "s:dict", "[4,5]", "s:a", "s:b", "{7:8}", "s:x", "s:1"]), 1, 1, "Unicode (UTF-8)"),
        ("data.strings", .text("\"d\" = <0fbd77>;\n"), .objects(["{1:2}", "s:d", "d:0fbd77"]), 1, 1, "Unicode (UTF-8)"),
        ("xml-format.strings", .text("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>k</key>\n\t<string>v</string>\n</dict>\n</plist>\n"), .objects(["{1:2}", "s:k", "s:v"]), 1, 1, "Unicode (UTF-8)"),
        ("xml-typed.strings", .text("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>i</key>\n\t<integer>7</integer>\n\t<key>b</key>\n\t<true/>\n\t<key>r</key>\n\t<real>1.5</real>\n</dict>\n</plist>\n"), .objects(["{1:4,2:5,3:6}", "s:b", "s:i", "s:r", "true", "i1:7", "r:1.5"]), 1, 1, "Unicode (UTF-8)"),
        ("duplicate-keys.strings", .text("\"k\" = \"first\";\n\"k\" = \"second\";\n"), .objects(["{1:2}", "s:k", "s:second"]), 1, 1, "Unicode (UTF-8)"),
        ("empty-value.strings", .text("\"k\" = \"\";\n"), .objects(["{1:2}", "s:k", "s:"]), 1, 1, "Unicode (UTF-8)"),
        ("no-trailing-newline.strings", .text("\"key\" = \"value\";"), .objects(["{1:2}", "s:key", "s:value"]), 1, 1, "Unicode (UTF-8)"),
        ("crlf.strings", .text("\"a\" = \"1\";\r\n\"b\" = \"2\";\r\n"), .objects(["{1:3,2:4}", "s:a", "s:b", "s:1", "s:2"]), 1, 1, "Unicode (UTF-8)"),
        ("xml-duplicates.strings", .text("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>a</key>\n\t<integer>1</integer>\n\t<key>b</key>\n\t<integer>1</integer>\n\t<key>c</key>\n\t<real>1</real>\n\t<key>d</key>\n\t<true/>\n\t<key>e</key>\n\t<true/>\n\t<key>f</key>\n\t<data>AAE=</data>\n\t<key>g</key>\n\t<data>AAE=</data>\n\t<key>h</key>\n\t<real>2.5</real>\n\t<key>i</key>\n\t<real>2.5</real>\n\t<key>j</key>\n\t<integer>-1</integer>\n\t<key>k</key>\n\t<integer>300</integer>\n\t<key>l</key>\n\t<integer>70000</integer>\n\t<key>m</key>\n\t<integer>5000000000</integer>\n\t<key>n</key>\n\t<false/>\n\t<key>o</key>\n\t<date>2001-01-01T00:00:00Z</date>\n\t<key>p</key>\n\t<string>1</string>\n</dict>\n</plist>\n"), .objects(["{1:17,2:17,3:18,4:19,5:19,6:21,7:22,8:23,9:24,10:25,11:26,12:27,13:28,14:29,15:30,16:31}", "s:a", "s:b", "s:c", "s:d", "s:e", "s:f", "s:g", "s:h", "s:i", "s:j", "s:k", "s:l", "s:m", "s:n", "s:o", "s:p", "i1:1", "r:1.0", "true", "true", "d:0001", "d:0001", "r:2.5", "r:2.5", "i8:-1", "i2:300", "i4:70000", "i8:5000000000", "false", "date:0.0", "s:1"]), 1, 1, "Unicode (UTF-8)"),
        ("container-duplicates.strings", .text("\"a\" = { \"x\" = \"1\"; };\n\"b\" = { \"x\" = \"1\"; };\n\"c\" = (\"1\", \"1\");\n\"d\" = (\"1\", \"1\");\n\"e\" = ();\n\"f\" = ();\n\"g\" = {};\n"), .objects(["{1:8,2:11,3:12,4:13,5:14,6:15,7:16}", "s:a", "s:b", "s:c", "s:d", "s:e", "s:f", "s:g", "{9:10}", "s:x", "s:1", "{9:10}", "[10,10]", "[10,10]", "[]", "[]", "{}"]), 1, 1, "Unicode (UTF-8)"),
        ("table-at-255.strings", .text("\"k\" = \"" + String(repeating: "t", count: 239) + "\";\n"), .objects(["{1:2}", "s:k", "s:" + String(repeating: "t", count: 239)]), 1, 1, "Unicode (UTF-8)"),
        ("table-at-256.strings", .text("\"k\" = \"" + String(repeating: "t", count: 240) + "\";\n"), .objects(["{1:2}", "s:k", "s:" + String(repeating: "t", count: 240)]), 2, 1, "Unicode (UTF-8)"),
        ("objects-255.strings", .text("\"k000\" = \"v000\";\n\"k001\" = \"v001\";\n\"k002\" = \"v002\";\n\"k003\" = \"v003\";\n\"k004\" = \"v004\";\n\"k005\" = \"v005\";\n\"k006\" = \"v006\";\n\"k007\" = \"v007\";\n\"k008\" = \"v008\";\n\"k009\" = \"v009\";\n\"k010\" = \"v010\";\n\"k011\" = \"v011\";\n\"k012\" = \"v012\";\n\"k013\" = \"v013\";\n\"k014\" = \"v014\";\n\"k015\" = \"v015\";\n\"k016\" = \"v016\";\n\"k017\" = \"v017\";\n\"k018\" = \"v018\";\n\"k019\" = \"v019\";\n\"k020\" = \"v020\";\n\"k021\" = \"v021\";\n\"k022\" = \"v022\";\n\"k023\" = \"v023\";\n\"k024\" = \"v024\";\n\"k025\" = \"v025\";\n\"k026\" = \"v026\";\n\"k027\" = \"v027\";\n\"k028\" = \"v028\";\n\"k029\" = \"v029\";\n\"k030\" = \"v030\";\n\"k031\" = \"v031\";\n\"k032\" = \"v032\";\n\"k033\" = \"v033\";\n\"k034\" = \"v034\";\n\"k035\" = \"v035\";\n\"k036\" = \"v036\";\n\"k037\" = \"v037\";\n\"k038\" = \"v038\";\n\"k039\" = \"v039\";\n\"k040\" = \"v040\";\n\"k041\" = \"v041\";\n\"k042\" = \"v042\";\n\"k043\" = \"v043\";\n\"k044\" = \"v044\";\n\"k045\" = \"v045\";\n\"k046\" = \"v046\";\n\"k047\" = \"v047\";\n\"k048\" = \"v048\";\n\"k049\" = \"v049\";\n\"k050\" = \"v050\";\n\"k051\" = \"v051\";\n\"k052\" = \"v052\";\n\"k053\" = \"v053\";\n\"k054\" = \"v054\";\n\"k055\" = \"v055\";\n\"k056\" = \"v056\";\n\"k057\" = \"v057\";\n\"k058\" = \"v058\";\n\"k059\" = \"v059\";\n\"k060\" = \"v060\";\n\"k061\" = \"v061\";\n\"k062\" = \"v062\";\n\"k063\" = \"v063\";\n\"k064\" = \"v064\";\n\"k065\" = \"v065\";\n\"k066\" = \"v066\";\n\"k067\" = \"v067\";\n\"k068\" = \"v068\";\n\"k069\" = \"v069\";\n\"k070\" = \"v070\";\n\"k071\" = \"v071\";\n\"k072\" = \"v072\";\n\"k073\" = \"v073\";\n\"k074\" = \"v074\";\n\"k075\" = \"v075\";\n\"k076\" = \"v076\";\n\"k077\" = \"v077\";\n\"k078\" = \"v078\";\n\"k079\" = \"v079\";\n\"k080\" = \"v080\";\n\"k081\" = \"v081\";\n\"k082\" = \"v082\";\n\"k083\" = \"v083\";\n\"k084\" = \"v084\";\n\"k085\" = \"v085\";\n\"k086\" = \"v086\";\n\"k087\" = \"v087\";\n\"k088\" = \"v088\";\n\"k089\" = \"v089\";\n\"k090\" = \"v090\";\n\"k091\" = \"v091\";\n\"k092\" = \"v092\";\n\"k093\" = \"v093\";\n\"k094\" = \"v094\";\n\"k095\" = \"v095\";\n\"k096\" = \"v096\";\n\"k097\" = \"v097\";\n\"k098\" = \"v098\";\n\"k099\" = \"v099\";\n\"k100\" = \"v100\";\n\"k101\" = \"v101\";\n\"k102\" = \"v102\";\n\"k103\" = \"v103\";\n\"k104\" = \"v104\";\n\"k105\" = \"v105\";\n\"k106\" = \"v106\";\n\"k107\" = \"v107\";\n\"k108\" = \"v108\";\n\"k109\" = \"v109\";\n\"k110\" = \"v110\";\n\"k111\" = \"v111\";\n\"k112\" = \"v112\";\n\"k113\" = \"v113\";\n\"k114\" = \"v114\";\n\"k115\" = \"v115\";\n\"k116\" = \"v116\";\n\"k117\" = \"v117\";\n\"k118\" = \"v118\";\n\"k119\" = \"v119\";\n\"k120\" = \"v120\";\n\"k121\" = \"v121\";\n\"k122\" = \"v122\";\n\"k123\" = \"v123\";\n\"k124\" = \"v124\";\n\"k125\" = \"v125\";\n\"k126\" = \"v125\";\n"), .objects(["{1:128,2:129,3:130,4:131,5:132,6:133,7:134,8:135,9:136,10:137,11:138,12:139,13:140,14:141,15:142,16:143,17:144,18:145,19:146,20:147,21:148,22:149,23:150,24:151,25:152,26:153,27:154,28:155,29:156,30:157,31:158,32:159,33:160,34:161,35:162,36:163,37:164,38:165,39:166,40:167,41:168,42:169,43:170,44:171,45:172,46:173,47:174,48:175,49:176,50:177,51:178,52:179,53:180,54:181,55:182,56:183,57:184,58:185,59:186,60:187,61:188,62:189,63:190,64:191,65:192,66:193,67:194,68:195,69:196,70:197,71:198,72:199,73:200,74:201,75:202,76:203,77:204,78:205,79:206,80:207,81:208,82:209,83:210,84:211,85:212,86:213,87:214,88:215,89:216,90:217,91:218,92:219,93:220,94:221,95:222,96:223,97:224,98:225,99:226,100:227,101:228,102:229,103:230,104:231,105:232,106:233,107:234,108:235,109:236,110:237,111:238,112:239,113:240,114:241,115:242,116:243,117:244,118:245,119:246,120:247,121:248,122:249,123:250,124:251,125:252,126:253,127:253}", "s:k000", "s:k001", "s:k002", "s:k003", "s:k004", "s:k005", "s:k006", "s:k007", "s:k008", "s:k009", "s:k010", "s:k011", "s:k012", "s:k013", "s:k014", "s:k015", "s:k016", "s:k017", "s:k018", "s:k019", "s:k020", "s:k021", "s:k022", "s:k023", "s:k024", "s:k025", "s:k026", "s:k027", "s:k028", "s:k029", "s:k030", "s:k031", "s:k032", "s:k033", "s:k034", "s:k035", "s:k036", "s:k037", "s:k038", "s:k039", "s:k040", "s:k041", "s:k042", "s:k043", "s:k044", "s:k045", "s:k046", "s:k047", "s:k048", "s:k049", "s:k050", "s:k051", "s:k052", "s:k053", "s:k054", "s:k055", "s:k056", "s:k057", "s:k058", "s:k059", "s:k060", "s:k061", "s:k062", "s:k063", "s:k064", "s:k065", "s:k066", "s:k067", "s:k068", "s:k069", "s:k070", "s:k071", "s:k072", "s:k073", "s:k074", "s:k075", "s:k076", "s:k077", "s:k078", "s:k079", "s:k080", "s:k081", "s:k082", "s:k083", "s:k084", "s:k085", "s:k086", "s:k087", "s:k088", "s:k089", "s:k090", "s:k091", "s:k092", "s:k093", "s:k094", "s:k095", "s:k096", "s:k097", "s:k098", "s:k099", "s:k100", "s:k101", "s:k102", "s:k103", "s:k104", "s:k105", "s:k106", "s:k107", "s:k108", "s:k109", "s:k110", "s:k111", "s:k112", "s:k113", "s:k114", "s:k115", "s:k116", "s:k117", "s:k118", "s:k119", "s:k120", "s:k121", "s:k122", "s:k123", "s:k124", "s:k125", "s:k126", "s:v000", "s:v001", "s:v002", "s:v003", "s:v004", "s:v005", "s:v006", "s:v007", "s:v008", "s:v009", "s:v010", "s:v011", "s:v012", "s:v013", "s:v014", "s:v015", "s:v016", "s:v017", "s:v018", "s:v019", "s:v020", "s:v021", "s:v022", "s:v023", "s:v024", "s:v025", "s:v026", "s:v027", "s:v028", "s:v029", "s:v030", "s:v031", "s:v032", "s:v033", "s:v034", "s:v035", "s:v036", "s:v037", "s:v038", "s:v039", "s:v040", "s:v041", "s:v042", "s:v043", "s:v044", "s:v045", "s:v046", "s:v047", "s:v048", "s:v049", "s:v050", "s:v051", "s:v052", "s:v053", "s:v054", "s:v055", "s:v056", "s:v057", "s:v058", "s:v059", "s:v060", "s:v061", "s:v062", "s:v063", "s:v064", "s:v065", "s:v066", "s:v067", "s:v068", "s:v069", "s:v070", "s:v071", "s:v072", "s:v073", "s:v074", "s:v075", "s:v076", "s:v077", "s:v078", "s:v079", "s:v080", "s:v081", "s:v082", "s:v083", "s:v084", "s:v085", "s:v086", "s:v087", "s:v088", "s:v089", "s:v090", "s:v091", "s:v092", "s:v093", "s:v094", "s:v095", "s:v096", "s:v097", "s:v098", "s:v099", "s:v100", "s:v101", "s:v102", "s:v103", "s:v104", "s:v105", "s:v106", "s:v107", "s:v108", "s:v109", "s:v110", "s:v111", "s:v112", "s:v113", "s:v114", "s:v115", "s:v116", "s:v117", "s:v118", "s:v119", "s:v120", "s:v121", "s:v122", "s:v123", "s:v124", "s:v125"]), 2, 1, "Unicode (UTF-8)"),
        ("objects-256.strings", .pairs((0..<128).map { (Self.key("k", $0, 3), Self.key("v", min($0, 126), 3)) }), .table((0..<128).map { (Self.key("k", $0, 3), Self.key("v", min($0, 126), 3)) }), 2, 2, "Unicode (UTF-8)"),
        ("objects-257.strings", .pairs((0..<128).map { (Self.key("k", $0, 3), Self.key("v", $0, 3)) }), .table((0..<128).map { (Self.key("k", $0, 3), Self.key("v", $0, 3)) }), 2, 2, "Unicode (UTF-8)"),
        ("key-order-unicode.strings", .text("\"\u{FF01}\" = \"1\";\n\"\u{1F600}\" = \"2\";\n\"\u{E9}\" = \"3\";\n\"e\u{301}x\" = \"4\";\n\"z\" = \"5\";\n"), .objects(["{1:6,2:7,3:8,4:9,5:10}", "s:z", "u:\u{E9}", "u:e\u{301}x", "u:\u{FF01}", "u:\u{1F600}", "s:5", "s:3", "s:4", "s:1", "s:2"]), 1, 1, "Unicode (UTF-8)"),
        ("plural.stringsdict", .text("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>%d items</key>\n\t<dict>\n\t\t<key>NSStringLocalizedFormatKey</key>\n\t\t<string>%#@items@</string>\n\t\t<key>items</key>\n\t\t<dict>\n\t\t\t<key>NSStringFormatSpecTypeKey</key>\n\t\t\t<string>NSStringPluralRuleType</string>\n\t\t\t<key>NSStringFormatValueTypeKey</key>\n\t\t\t<string>d</string>\n\t\t\t<key>one</key>\n\t\t\t<string>%d item</string>\n\t\t\t<key>other</key>\n\t\t\t<string>%d items</string>\n\t\t</dict>\n\t</dict>\n</dict>\n</plist>\n"), .objects(["{1:2}", "s:%d items", "{3:5,4:6}", "s:NSStringLocalizedFormatKey", "s:items", "s:%#@items@", "{7:11,8:12,9:13,10:1}", "s:NSStringFormatSpecTypeKey", "s:NSStringFormatValueTypeKey", "s:one", "s:other", "s:NSStringPluralRuleType", "s:d", "s:%d item"]), 1, 1, "Unicode (UTF-8)"),
        ("two-entries.stringsdict", .text("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>b</key>\n\t<dict>\n\t\t<key>NSStringLocalizedFormatKey</key>\n\t\t<string>%#@n@</string>\n\t\t<key>n</key>\n\t\t<dict>\n\t\t\t<key>NSStringFormatSpecTypeKey</key>\n\t\t\t<string>NSStringPluralRuleType</string>\n\t\t\t<key>NSStringFormatValueTypeKey</key>\n\t\t\t<string>d</string>\n\t\t\t<key>other</key>\n\t\t\t<string>%d b</string>\n\t\t</dict>\n\t</dict>\n\t<key>a</key>\n\t<dict>\n\t\t<key>NSStringLocalizedFormatKey</key>\n\t\t<string>%#@n@</string>\n\t\t<key>n</key>\n\t\t<dict>\n\t\t\t<key>NSStringFormatSpecTypeKey</key>\n\t\t\t<string>NSStringPluralRuleType</string>\n\t\t\t<key>NSStringFormatValueTypeKey</key>\n\t\t\t<string>d</string>\n\t\t\t<key>other</key>\n\t\t\t<string>%d a</string>\n\t\t</dict>\n\t</dict>\n</dict>\n</plist>\n"), .objects(["{1:3,2:14}", "s:a", "s:b", "{4:6,5:7}", "s:NSStringLocalizedFormatKey", "s:n", "s:%#@n@", "{8:11,9:12,10:13}", "s:NSStringFormatSpecTypeKey", "s:NSStringFormatValueTypeKey", "s:other", "s:NSStringPluralRuleType", "s:d", "s:%d a", "{4:6,5:15}", "{8:11,9:12,10:16}", "s:%d b"]), 1, 1, "Unicode (UTF-8)"),
        ("variable-width.stringsdict", .text("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>Title</key>\n\t<dict>\n\t\t<key>NSStringVariableWidthRuleType</key>\n\t\t<dict>\n\t\t\t<key>1</key>\n\t\t\t<string>T</string>\n\t\t\t<key>20</key>\n\t\t\t<string>Title</string>\n\t\t</dict>\n\t</dict>\n</dict>\n</plist>\n"), .objects(["{1:2}", "s:Title", "{3:4}", "s:NSStringVariableWidthRuleType", "{5:7,6:1}", "s:1", "s:20", "s:T"]), 1, 1, "Unicode (UTF-8)"),
        ("empty-dict.stringsdict", .text("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict/>\n</plist>\n"), .objects(["{}"]), 1, 1, "Unicode (UTF-8)"),
        ("openstep.stringsdict", .text("{ \"k\" = { \"NSStringLocalizedFormatKey\" = \"%#@n@\"; }; }\n"), .objects(["{1:2}", "s:k", "{3:4}", "s:NSStringLocalizedFormatKey", "s:%#@n@"]), 1, 1, "Unicode (UTF-8)"),
    ]

    @Test(arguments: binary)
    func binaryOutput(file: String, input: Input, objects: Objects, offsetSize: Int, referenceSize: Int, encoding: String?) throws {
        let result = try StringsFileCopy.copy(input.bytes, outputEncoding: .binary, validate: true)
        let written = try #require(BinaryPropertyListNotation(Array(result.contents)), "\(file)")
        #expect(written.objects == objects.notation, "\(file)")
        #expect(written.offsetSize == offsetSize, "\(file)")
        #expect(written.referenceSize == referenceSize, "\(file)")
        #expect(result.notes == encoding.map { ["detected encoding of input file as \($0)"] } ?? [], "\(file)")
    }

    /// `\U` escapes are UTF-16 code units: a high surrogate then a low one make one character, and
    /// each other surrogate becomes U+FFFD (the `copy-escapes` experiment).
    static let surrogateEscapes: [(String, String, String)] = [
        ("\"k\" = \"\\UD83D\\UDE00\";\n", "k", "\u{1F600}"),
        ("\"k\" = \"\\UD83D\";\n", "k", "\u{FFFD}"),
        ("\"k\" = \"\\UDE00\";\n", "k", "\u{FFFD}"),
        ("\"k\" = \"\\UD83Dx\";\n", "k", "\u{FFFD}x"),
        ("\"\\UD83D\\UDE00\" = \"v\";\n", "\u{1F600}", "v"),
        ("\"k\" = \"\\UD83D\\U0041\";\n", "k", "\u{FFFD}A"),
        ("\"k\" = \"\\UD83D\\UD83D\\UDE00\";\n", "k", "\u{FFFD}\u{1F600}"),
        ("\"k\" = \"\\UDE00\\UD83D\";\n", "k", "\u{FFFD}\u{FFFD}"),
    ]

    @Test(arguments: surrogateEscapes)
    func surrogateEscape(input: String, key: String, value: String) throws {
        let result = try StringsFileCopy.copy(Array(input.utf8), outputEncoding: .binary, validate: true)
        let written = try #require(BinaryPropertyListNotation(Array(result.contents)))
        #expect(written.objects == Objects.table([(key, value)]).notation)
    }

    /// The input's text, without a byte order mark: valid UTF-8, or UTF-16 after a mark.
    static func text(of bytes: [UInt8]) -> String {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: bytes.dropFirst(3), as: UTF8.self) }
        if bytes.starts(with: [0xFF, 0xFE]) {
            let units = stride(from: 2, to: bytes.count, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
            return String(decoding: units, as: UTF16.self)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static let textInputs: [Input] = [
        .text("\"key\" = \"value\";\n"), .text(""), .text("\n  \n"), .hex("efbbbf226b657922203d202276616c7565223b0a"),
        .hex("fffe22006b0065007900220020003d0020002200760061006c007500650022003b000a002200e900220020003d0020002200e80022003b000a00"),
        .text("\"caf\u{E9}\" = \"na\u{EF}ve \u{2603} \u{1F600}\";\n\"ascii\" = \"plain\";\n"), .text("\"a\" = \"1\";\r\n\"b\" = \"2\";\r\n"),
        .text("\"key\";\n"),
    ]

    /// UTF-16 output is the mark FF FE and the input's text in little-endian code units; an empty
    /// input gives an empty file.
    @Test(arguments: textInputs)
    func utf16Output(input: Input) throws {
        let result = try StringsFileCopy.copy(input.bytes, outputEncoding: .utf16, validate: true)
        let text = Self.text(of: input.bytes)
        let expected: [UInt8] = text.isEmpty ? [] : [0xFF, 0xFE] + text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        #expect(Array(result.contents) == expected)
    }

    /// UTF-8 output is the input's text without a mark.
    @Test(arguments: textInputs)
    func utf8Output(input: Input) throws {
        let result = try StringsFileCopy.copy(input.bytes, outputEncoding: .utf8, validate: true)
        #expect(Array(result.contents) == Array(Self.text(of: input.bytes).utf8))
    }

    /// Swift Build's message for anything that is not a property list, with no note.
    @Test func invalidInputFailsValidation() {
        #expect(throws: NomacError("validation failed: Couldn't parse property list because the input data was in an invalid format")) {
            try StringsFileCopy.copy(Array("\"key\" = \"value\"\n".utf8), outputEncoding: .binary, validate: true)
        }
    }

    @Test func octalEscapesAboveASCIIAreRefused() {
        #expect(throws: NomacError("nomac does not read octal escapes above \\177 yet (BACKLOG B-252)")) {
            try StringsFileCopy.copy(Array("\"k\" = \"\\351\";\n".utf8), outputEncoding: .binary, validate: true)
        }
    }

    @Test func specifiedInputEncodingIsNotReported() throws {
        let result = try StringsFileCopy.copy(Array("\"k\" = \"v\";\n".utf8), inputEncoding: "utf-8", outputEncoding: .binary, validate: true)
        #expect(result.notes.isEmpty)
    }
}

/// A binary property list as the objects notation of ``StringsFileCopyTests/Objects``.
struct BinaryPropertyListNotation {
    var offsetSize: Int
    var referenceSize: Int
    var objects: [String]

    init?(_ bytes: [UInt8]) {
        guard bytes.count >= 40, Array(bytes.prefix(8)) == Array("bplist00".utf8) else { return nil }
        let trailer = Array(bytes.suffix(32))
        func number(_ slice: ArraySlice<UInt8>) -> Int { slice.reduce(0) { $0 << 8 | Int($1) } }
        offsetSize = Int(trailer[6])
        referenceSize = Int(trailer[7])
        let count = number(trailer[8..<16])
        let table = number(trailer[24..<32])
        objects = []
        for index in 0..<count {
            let offset = number(bytes[(table + index * offsetSize)..<(table + (index + 1) * offsetSize)])
            objects.append(Self.object(bytes, at: offset, referenceSize: referenceSize))
        }
    }

    private static func object(_ bytes: [UInt8], at offset: Int, referenceSize: Int) -> String {
        let marker = bytes[offset]
        func integer(at position: Int) -> (value: Int, size: Int, end: Int) {
            let size = 1 << Int(bytes[position] & 0x0F)
            let raw = bytes[(position + 1)...(position + size)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            return (size == 8 ? Int(Int64(bitPattern: raw)) : Int(raw), size, position + 1 + size)
        }
        func count() -> (Int, Int) {
            guard marker & 0x0F == 0x0F else { return (Int(marker & 0x0F), offset + 1) }
            let parsed = integer(at: offset + 1)
            return (parsed.value, parsed.end)
        }
        func references(_ number: Int, from start: Int) -> [Int] {
            (0..<number).map { item in bytes[(start + item * referenceSize)..<(start + (item + 1) * referenceSize)].reduce(0) { $0 << 8 | Int($1) } }
        }
        func double(at position: Int) -> Double {
            Double(bitPattern: bytes[(position + 1)...(position + 8)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        }
        switch marker >> 4 {
        case 0: return marker == 0x09 ? "true" : "false"
        case 1:
            let parsed = integer(at: offset)
            return "i\(parsed.size):\(parsed.value)"
        case 2: return "r:\(double(at: offset))"
        case 3: return "date:\(double(at: offset))"
        case 4:
            let (length, start) = count()
            return "d:" + bytes[start..<(start + length)].map { String(format: "%02x", $0) }.joined()
        case 5:
            let (length, start) = count()
            return "s:" + String(decoding: bytes[start..<(start + length)], as: UTF8.self)
        case 6:
            let (length, start) = count()
            let units = (0..<length).map { UInt16(bytes[start + 2 * $0]) << 8 | UInt16(bytes[start + 2 * $0 + 1]) }
            return "u:" + String(decoding: units, as: UTF16.self)
        case 0xA:
            let (length, start) = count()
            return "[" + references(length, from: start).map(String.init).joined(separator: ",") + "]"
        default:
            let (length, start) = count()
            let all = references(2 * length, from: start)
            return "{" + (0..<length).map { "\(all[$0]):\(all[length + $0])" }.joined(separator: ",") + "}"
        }
    }
}

func hexBytes(_ hex: String) -> [UInt8] {
    var bytes: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        bytes.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return bytes
}
