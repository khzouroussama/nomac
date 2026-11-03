/// The system colors a color set can reference (`"reference": "systemBlueColor"`), with the
/// components actool stores for each, observed on self-written catalogs (`colors`,
/// system-colors): the same at deployment targets 15.0 and 18.0, for every idiom and display
/// gamut, and for the `ios` and `universal` platforms. Names marked iOS-only make actool warn
/// when referenced for `universal`, as do names it does not know, which get a placeholder color.
enum SystemColors {
    struct Value {
        /// The `COLR` color space number.
        var space: UInt32
        /// Each component's 32-bit float, which actool stores widened to a double.
        var components: [UInt32]

        init(_ space: UInt32, _ components: [UInt32]) {
            self.space = space
            self.components = components
        }
    }

    /// Each name's light and dark values and whether `universal` references it without a warning.
    static let values: [String: (light: Value, dark: Value, universal: Bool)] = [
        "darkTextColor": (.init(6, [0x00000000, 0x3F800000]), .init(6, [0x00000000, 0x3F800000]), false),
        "labelColor": (.init(2, [0x00000000, 0x3F800000]), .init(2, [0x3F800000, 0x3F800000]), true),
        "lightTextColor": (.init(6, [0x3F800000, 0x3F19999A]), .init(6, [0x3F800000, 0x3F19999A]), false),
        "linkColor": (.init(4, [0x00000000, 0x3EF4BC6A, 0x3F800000, 0x3F800000]), .init(4, [0x3D0F5C29, 0x3F049BA6, 0x3F800000, 0x3F800000]), false),
        "opaqueSeparatorColor": (.init(4, [0x3F46A7F0, 0x3F46A7F0, 0x3F48B439, 0x3F800000]), .init(4, [0x3E6147AE, 0x3E6147AE, 0x3E6872B0, 0x3F800000]), false),
        "placeholderTextColor": (.init(1, [0x3E70A3D7, 0x3E70A3D7, 0x3E86A7F0, 0x3E989375]), .init(1, [0x3F6C0831, 0x3F6C0831, 0x3F760419, 0x3E989375]), false),
        "quaternaryLabelColor": (.init(1, [0x3E70A3D7, 0x3E70A3D7, 0x3E86A7F0, 0x3E343958]), .init(1, [0x3F6C0831, 0x3F6C0831, 0x3F760419, 0x3E20C49C]), true),
        "quaternarySystemFillColor": (.init(4, [0x3EE8F5C3, 0x3EE8F5C3, 0x3F008312, 0x3DA3D70A]), .init(4, [0x3EED0E56, 0x3EED0E56, 0x3F008312, 0x3E3851EC]), false),
        "secondaryLabelColor": (.init(1, [0x3E70A3D7, 0x3E70A3D7, 0x3E86A7F0, 0x3F19999A]), .init(1, [0x3F6C0831, 0x3F6C0831, 0x3F760419, 0x3F19999A]), true),
        "secondarySystemBackgroundColor": (.init(4, [0x3F72F1AA, 0x3F72F1AA, 0x3F781062, 0x3F800000]), .init(4, [0x3DE147AE, 0x3DE147AE, 0x3DF1A9FC, 0x3F800000]), false),
        "secondarySystemFillColor": (.init(4, [0x3EF126E9, 0x3EF126E9, 0x3F008312, 0x3E23D70A]), .init(4, [0x3EF126E9, 0x3EF126E9, 0x3F008312, 0x3EA3D70A]), false),
        "secondarySystemGroupedBackgroundColor": (.init(6, [0x3F800000, 0x3F800000]), .init(4, [0x3DE147AE, 0x3DE147AE, 0x3DF1A9FC, 0x3F800000]), false),
        "separatorColor": (.init(4, [0x3E70A3D7, 0x3E70A3D7, 0x3E86A7F0, 0x3DF5C28F]), .init(4, [0x3EA872B0, 0x3EA872B0, 0x3EB0A3D7, 0x3F000000]), false),
        "systemBackgroundColor": (.init(6, [0x3F800000, 0x3F800000]), .init(6, [0x00000000, 0x3F800000]), false),
        "systemBlueColor": (.init(1, [0x00000000, 0x3F0872B0, 0x3F800000, 0x3F800000]), .init(1, [0x00000000, 0x3F11A9FC, 0x3F800000, 0x3F800000]), true),
        "systemBrownColor": (.init(1, [0x3F2CCCCD, 0x3EFEF9DB, 0x3EBCED91, 0x3F800000]), .init(1, [0x3F37CED9, 0x3F0A7EFA, 0x3ECCCCCD, 0x3F800000]), true),
        "systemCyanColor": (.init(1, [0x00000000, 0x3F40C49C, 0x3F68F5C3, 0x3F800000]), .init(1, [0x3E70A3D7, 0x3F53B646, 0x3F7EF9DB, 0x3F800000]), true),
        "systemFillColor": (.init(4, [0x3EF126E9, 0x3EF126E9, 0x3F008312, 0x3E4CCCCD]), .init(4, [0x3EF126E9, 0x3EF126E9, 0x3F008312, 0x3EB851EC]), false),
        "systemGray2Color": (.init(4, [0x3F2E978D, 0x3F2E978D, 0x3F32B021, 0x3F800000]), .init(4, [0x3EC6A7F0, 0x3EC6A7F0, 0x3ECCCCCD, 0x3F800000]), false),
        "systemGray3Color": (.init(4, [0x3F47AE14, 0x3F47AE14, 0x3F4CCCCD, 0x3F800000]), .init(4, [0x3E90624E, 0x3E90624E, 0x3E947AE1, 0x3F800000]), false),
        "systemGray4Color": (.init(4, [0x3F51EB85, 0x3F51EB85, 0x3F56C8B4, 0x3F800000]), .init(4, [0x3E6872B0, 0x3E6872B0, 0x3E70A3D7, 0x3F800000]), false),
        "systemGray5Color": (.init(4, [0x3F65E354, 0x3F65E354, 0x3F6B020C, 0x3F800000]), .init(4, [0x3E3126E9, 0x3E3126E9, 0x3E3851EC, 0x3F800000]), false),
        "systemGray6Color": (.init(4, [0x3F72F1AA, 0x3F72F1AA, 0x3F781062, 0x3F800000]), .init(4, [0x3DE147AE, 0x3DE147AE, 0x3DF1A9FC, 0x3F800000]), false),
        "systemGrayColor": (.init(1, [0x3F0E978D, 0x3F0E978D, 0x3F1374BC, 0x3F800000]), .init(1, [0x3F0E978D, 0x3F0E978D, 0x3F1374BC, 0x3F800000]), true),
        "systemGreenColor": (.init(1, [0x3E50E560, 0x3F47AE14, 0x3EB2B021, 0x3F800000]), .init(1, [0x3E408312, 0x3F51EB85, 0x3EB0A3D7, 0x3F800000]), true),
        "systemGroupedBackgroundColor": (.init(4, [0x3F72F1AA, 0x3F72F1AA, 0x3F781062, 0x3F800000]), .init(6, [0x00000000, 0x3F800000]), false),
        "systemIndigoColor": (.init(1, [0x3EC28F5C, 0x3EAA7EFA, 0x3F760419, 0x3F800000]), .init(1, [0x3ED70A3D, 0x3EBAE148, 0x3F800000, 0x3F800000]), true),
        "systemMintColor": (.init(1, [0x00000000, 0x3F48B439, 0x3F33B646, 0x3F800000]), .init(1, [0x00000000, 0x3F5AE148, 0x3F43D70A, 0x3F800000]), true),
        "systemOrangeColor": (.init(1, [0x3F800000, 0x3F0D9168, 0x3E20C49C, 0x3F800000]), .init(1, [0x3F800000, 0x3F12B021, 0x3E408312, 0x3F800000]), true),
        "systemPinkColor": (.init(1, [0x3F800000, 0x3E343958, 0x3EAA7EFA, 0x3F800000]), .init(1, [0x3F800000, 0x3E5D2F1B, 0x3EBEF9DB, 0x3F800000]), true),
        "systemPurpleColor": (.init(1, [0x3F4BC6A8, 0x3E408312, 0x3F60C49C, 0x3F800000]), .init(1, [0x3F5BE76D, 0x3E50E560, 0x3F72F1AA, 0x3F800000]), true),
        "systemRedColor": (.init(1, [0x3F800000, 0x3E6147AE, 0x3E70A3D7, 0x3F800000]), .init(1, [0x3F800000, 0x3E849BA6, 0x3E8AC083, 0x3F800000]), true),
        "systemTealColor": (.init(1, [0x00000000, 0x3F43D70A, 0x3F50E560, 0x3F800000]), .init(1, [0x00000000, 0x3F52F1AA, 0x3F60C49C, 0x3F800000]), true),
        "systemYellowColor": (.init(1, [0x3F800000, 0x3F4CCCCD, 0x00000000, 0x3F800000]), .init(1, [0x3F800000, 0x3F56C8B4, 0x00000000, 0x3F800000]), true),
        "tertiaryLabelColor": (.init(1, [0x3E70A3D7, 0x3E70A3D7, 0x3E86A7F0, 0x3E989375]), .init(1, [0x3F6C0831, 0x3F6C0831, 0x3F760419, 0x3E989375]), true),
        "tertiarySystemBackgroundColor": (.init(6, [0x3F800000, 0x3F800000]), .init(4, [0x3E3126E9, 0x3E3126E9, 0x3E3851EC, 0x3F800000]), false),
        "tertiarySystemFillColor": (.init(4, [0x3EED0E56, 0x3EED0E56, 0x3F008312, 0x3DF5C28F]), .init(4, [0x3EED0E56, 0x3EED0E56, 0x3F008312, 0x3E75C28F]), false),
        "tertiarySystemGroupedBackgroundColor": (.init(4, [0x3F72F1AA, 0x3F72F1AA, 0x3F781062, 0x3F800000]), .init(4, [0x3E3126E9, 0x3E3126E9, 0x3E3851EC, 0x3F800000]), false),
        "tintColor": (.init(1, [0x00000000, 0x3F0872B0, 0x3F800000, 0x3F800000]), .init(1, [0x00000000, 0x3F11A9FC, 0x3F800000, 0x3F800000]), false),
    ]
}
