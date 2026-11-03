import Foundation
import Testing
import NomacPlist

@Suite struct XMLPropertyListTests {
    static let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">

        """

    /// The file `xcstringstool compile` writes for one translated key (strings-experiments
    /// `xcstrings` `translated`).
    @Test func writesStringTables() {
        let data = XMLPropertyList.data(.dictionary(["Hello": .string("Bonjour")]))
        #expect(String(decoding: data, as: UTF8.self) == Self.header + """
            <dict>
            \t<key>Hello</key>
            \t<string>Bonjour</string>
            </dict>
            </plist>

            """)
    }

    /// Only `&`, `<` and `>` are escaped; quotes, tabs, newlines and control characters are
    /// written as they are (`plutil -convert xml1`, and `xcstrings` `escapes`).
    @Test func escapesOnlyMarkupCharacters() {
        let data = XMLPropertyList.data(.dictionary(["q\"\\\n": .string("a\"b\\c\nd\te<f>&g\u{1}")]))
        #expect(String(decoding: data, as: UTF8.self) == Self.header + """
            <dict>
            \t<key>q"\\
            </key>
            \t<string>a"b\\c
            d\te&lt;f&gt;&amp;g\u{1}</string>
            </dict>
            </plist>

            """)
    }

    /// Keys sort by UTF-16 code units (`xcstrings` `key-order`): the emoji's lead surrogate,
    /// D83D, comes before U+FF01.
    @Test func sortsKeysInUTF16Order() {
        let keys = ["\u{FF01}", "\u{1F600}", "z", "Z", "_", "\u{E9}", "e", "a b", "a", "aa", "A"]
        let data = XMLPropertyList.data(.dictionary(Dictionary(uniqueKeysWithValues: keys.map { ($0, PropertyListValue.string($0)) })))
        let written = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
            .filter { $0.hasPrefix("\t<key>") }
            .map { $0.dropFirst(6).dropLast(6) }
        #expect(written == ["A", "Z", "_", "a", "a b", "aa", "e", "z", "\u{E9}", "\u{1F600}", "\u{FF01}"])
    }

    /// Nested and empty containers, numbers and booleans as `plutil -convert xml1` writes them.
    @Test func writesEveryValueType() {
        let value = PropertyListValue.dictionary([
            "arr": .array([]),
            "arr2": .array([.string("a"), .dictionary(["x": .string("y")]), .array([])]),
            "empty": .dictionary([:]),
            "f": .boolean(false),
            "i": .integer(7),
            "neg": .integer(-3),
            "r": .real(1.5),
            "r2": .real(0.1),
            "t": .boolean(true),
        ])
        #expect(String(decoding: XMLPropertyList.data(value), as: UTF8.self) == Self.header + """
            <dict>
            \t<key>arr</key>
            \t<array/>
            \t<key>arr2</key>
            \t<array>
            \t\t<string>a</string>
            \t\t<dict>
            \t\t\t<key>x</key>
            \t\t\t<string>y</string>
            \t\t</dict>
            \t\t<array/>
            \t</array>
            \t<key>empty</key>
            \t<dict/>
            \t<key>f</key>
            \t<false/>
            \t<key>i</key>
            \t<integer>7</integer>
            \t<key>neg</key>
            \t<integer>-3</integer>
            \t<key>r</key>
            \t<real>1.5</real>
            \t<key>r2</key>
            \t<real>0.10000000000000001</real>
            \t<key>t</key>
            \t<true/>
            </dict>
            </plist>

            """)
    }
}
