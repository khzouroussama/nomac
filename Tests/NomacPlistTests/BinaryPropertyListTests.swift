import Foundation
import Testing
import NomacPlist

@Suite struct BinaryPropertyListTests {
    /// strings-experiments `copy` `xml-duplicates`, as the values Swift Build reads from it.
    static let duplicates = PropertyListValue.dictionary([
        "a": .integer(1), "b": .integer(1), "c": .real(1), "d": .boolean(true), "e": .boolean(true),
        "f": .data([0, 1]), "g": .data([0, 1]), "h": .real(2.5), "i": .real(2.5), "j": .integer(-1),
        "k": .integer(300), "l": .integer(70000), "m": .integer(5_000_000_000), "n": .boolean(false),
        "o": .date(0), "p": .string("1"),
    ])

    /// Integers are shared, reals and data are not, and the second `true` is written but
    /// never referenced (Xcode's 214 bytes, objects 17 to 31: `1`, `1.0`, `true`, `true`,
    /// two data, two `2.5`, ...).
    @Test func sharesObjectsAsXcodeDoes() {
        let data = BinaryPropertyList.swiftBuildData(Self.duplicates)
        #expect(data.count == 214)
        #expect(Array(data.prefix(43)) == Array("bplist00".utf8) + [0xDF, 0x10, 0x10] + Array(1...16)
            + [17, 17, 18, 19, 19, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31])
        #expect(Array(data[75..<88]) == [0x10, 0x01, 0x23, 0x3F, 0xF0, 0, 0, 0, 0, 0, 0, 0x09, 0x09])
    }

    @Test func readsWhatItWrites() throws {
        let xml = String(decoding: XMLPropertyList.data(Self.duplicates), as: UTF8.self)
        #expect(try TextPropertyListParser.parse(xml) == Self.duplicates)
    }

    /// XML keys and strings lose one leading U+FEFF, raw or `&#xFEFF;`; old-style text keeps it
    /// (strings-experiments `xml-bom-values`, `xml-bom-keys`, `text-bom-values`).
    @Test func xmlDropsOneLeadingByteOrderMark() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>\u{FEFF}k</key><string>\u{FEFF}\u{FEFF}x</string>\
            <key>m</key><string>a\u{FEFF}b</string><key>r</key><string>&#xFEFF;v</string><key>s</key><string> \u{FEFF}v</string></dict></plist>
            """
        #expect(try TextPropertyListParser.parse(xml) == .dictionary([
            "k": .string("\u{FEFF}x"), "m": .string("a\u{FEFF}b"), "r": .string("v"), "s": .string(" \u{FEFF}v"),
        ]))
        #expect(try TextPropertyListParser.parse("\"k\" = \"\u{FEFF}v\";") == .dictionary(["k": .string("\u{FEFF}v")]))
    }

    /// Strings are one object when their UTF-16 code units are equal, so a precomposed and a
    /// decomposed `é` stay two.
    @Test func sharesStringsByCodeUnits() {
        let data = BinaryPropertyList.swiftBuildData(.array([.string("\u{E9}"), .string("e\u{301}"), .string("\u{E9}")]))
        #expect(Array(data[8...11]) == [0xA3, 1, 2, 1])
    }

    @Test func readsOldStyleText() throws {
        let text = """
            /* comment */ "a" = "x\\n\\U00e9\\101"; // trailing
            b = ( 1, "2", ); c = { d = <0fbd 77>; }; "e";
            """
        #expect(try TextPropertyListParser.parse(text) == .dictionary([
            "a": .string("x\n\u{E9}A"), "b": .array([.string("1"), .string("2")]),
            "c": .dictionary(["d": .data([0x0F, 0xBD, 0x77])]), "e": .string("e"),
        ]))
    }

    /// Explicit objects are written as `swiftBuildData` writes the objects it flattens.
    @Test func writesExplicitObjects() {
        let objects: [BinaryPropertyList.Object] = [.dictionary(keys: [1, 2], values: [3, 4]), .string("a"), .string("b"), .string("x"), .integer(1)]
        #expect(BinaryPropertyList.data(objects: objects) == BinaryPropertyList.swiftBuildData(.dictionary(["a": .string("x"), "b": .integer(1)])))
    }

    /// Keyed archives' objects as momc's `.mom` files hold them (docs/formats/coredata.md "Keyed
    /// archives"): a float default value in 4 bytes, and UIDs in 1 byte up to 255 and 2 above.
    @Test func writesFloatsAndUIDs() {
        let data = BinaryPropertyList.data(objects: [.array([1, 2, 3]), .float(0.5), .uid(255), .uid(269)])
        #expect(Array(data.dropFirst(8).prefix(14)) == [0xA3, 1, 2, 3, 0x22, 0x3F, 0x00, 0x00, 0x00, 0x80, 0xFF, 0x81, 0x01, 0x0D])
    }

    /// The keys of the top-level dictionary, in the order written.
    static func topLevelKeys(_ data: Data) -> [String] {
        let bytes = Array(data)
        let offsetSize = Int(bytes[bytes.count - 26]), referenceSize = Int(bytes[bytes.count - 25])
        func number(_ slice: ArraySlice<UInt8>) -> Int { slice.reduce(0) { $0 << 8 | Int($1) } }
        let top = number(bytes[(bytes.count - 16)..<(bytes.count - 8)]), table = number(bytes[(bytes.count - 8)...])
        func offset(_ object: Int) -> Int { number(bytes[(table + object * offsetSize)..<(table + (object + 1) * offsetSize)]) }
        func counted(_ start: Int) -> (count: Int, start: Int) {
            guard bytes[start] & 0x0F == 0x0F else { return (Int(bytes[start] & 0x0F), start + 1) }
            let size = 1 << Int(bytes[start + 1] & 0x0F)
            return (number(bytes[(start + 2)..<(start + 2 + size)]), start + 2 + size)
        }
        let dictionary = counted(offset(top))
        return (0..<dictionary.count).map { index in
            let reference = number(bytes[(dictionary.start + index * referenceSize)..<(dictionary.start + (index + 1) * referenceSize)])
            let key = counted(offset(reference))
            return String(decoding: bytes[key.start..<(key.start + key.count)], as: UTF8.self)
        }
    }

    /// signing-experiments `nested`: an app-store-connect export writes the share extension's
    /// Info.plist with its 23 keys in a 41-bucket dictionary's order, and `NSExtension`'s 3 in a
    /// 3-bucket one's; the values stay the same objects.
    @Test func foundationDataOrdersEveryDictionary() throws {
        let plist = PropertyListValue.dictionary(Dictionary(uniqueKeysWithValues: [
            "BuildMachineOSBuild", "CFBundleDevelopmentRegion", "CFBundleDisplayName", "CFBundleExecutable",
            "CFBundleIdentifier", "CFBundleInfoDictionaryVersion", "CFBundleName", "CFBundlePackageType",
            "CFBundleShortVersionString", "CFBundleSupportedPlatforms", "CFBundleVersion", "DTCompiler", "DTPlatformBuild",
            "DTPlatformName", "DTPlatformVersion", "DTSDKBuild", "DTSDKName", "DTXcode", "DTXcodeBuild", "MinimumOSVersion",
            "NSExtension", "UIDeviceFamily", "UIRequiredDeviceCapabilities",
        ].map { ($0, $0 == "NSExtension" ? Self.share : .string("v")) }))
        let data = try BinaryPropertyList.foundationData(rereading: plist)
        #expect(Self.topLevelKeys(data) == [
            "CFBundleName", "DTSDKName", "DTXcode", "DTSDKBuild", "CFBundleDevelopmentRegion", "CFBundleVersion",
            "BuildMachineOSBuild", "DTPlatformName", "CFBundlePackageType", "CFBundleShortVersionString",
            "CFBundleSupportedPlatforms", "CFBundleInfoDictionaryVersion", "CFBundleExecutable", "DTCompiler",
            "UIRequiredDeviceCapabilities", "MinimumOSVersion", "CFBundleIdentifier", "UIDeviceFamily", "DTPlatformVersion",
            "DTXcodeBuild", "CFBundleDisplayName", "DTPlatformBuild", "NSExtension",
        ])
        #expect(data.count == BinaryPropertyList.swiftBuildData(plist).count)
        #expect(try BinaryPropertyList.foundationData(rereading: Self.share) == BinaryPropertyList.swiftBuildData(Self.share))
    }

    static let share = PropertyListValue.dictionary([
        "NSExtensionAttributes": .dictionary(["NSExtensionActivationRule": .string("TRUEPREDICATE")]),
        "NSExtensionPointIdentifier": .string("com.apple.share-services"),
        "NSExtensionPrincipalClass": .string("Share.ShareViewController"),
    ])
}
