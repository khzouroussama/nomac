/// The fonts ibtool (Xcode 27.0) resolves by name, by their `UIFontTraits`: italic 1, bold 2, both 3
/// (nib-experiments round 115, `label-named-*`). Every other name, a bundled custom font's or a
/// system font ibtool does not find (`Courier-Bold`), is unresolved: options 0, traits 0 and no scaling
/// keys (`label-named-unknown`). Found by compiling a label of each PostScript name of the Mac's fonts
/// and the iOS 18, 26 and 27 simulator runtimes' (docs/formats/nib.md "Named fonts").
extension NibFont {
    static let resolvedFontOptions = 2_147_483_648
    /// The one name ibtool writes as another font's (`label-named-stheitisc-light`).
    static let renamedFonts = ["STHeitiSC-Light": "PingFangSC-Light"]
    static let resolvedFonts: [String: Int] = {
        let byTraits: [(traits: Int, names: [String])] = [
            (0, [
                ".SFUI-Regular", ".SFUI-RegularItalic", ".SFUI-Semibold", "AcademyEngravedLetPlain", "AlNile", "AmericanTypewriter",
                "AmericanTypewriter-Condensed", "AmericanTypewriter-CondensedLight", "AmericanTypewriter-Light", "AppleColorEmoji",
                "AppleSDGothicNeo-Light", "AppleSDGothicNeo-Medium", "AppleSDGothicNeo-Regular", "AppleSDGothicNeo-Thin",
                "AppleSDGothicNeo-UltraLight", "AppleSymbols", "ArialHebrew", "ArialHebrew-Light", "ArialMT", "ArialRoundedMTBold", "Avenir-Book",
                "Avenir-Light", "Avenir-Medium", "Avenir-Roman", "AvenirNext-Medium", "AvenirNext-Regular", "AvenirNext-UltraLight",
                "AvenirNextCondensed-Medium", "AvenirNextCondensed-Regular", "AvenirNextCondensed-UltraLight", "Baskerville", "BodoniOrnamentsITCTT",
                "BodoniSvtyTwoITCTT-Book", "BodoniSvtyTwoOSITCTT-Bold", "BodoniSvtyTwoOSITCTT-Book", "BodoniSvtyTwoSCITCTT-Book",
                "ChalkboardSE-Light", "ChalkboardSE-Regular", "Chalkduster", "Charter-Roman", "Cochin", "Copperplate", "Copperplate-Light",
                "Courier", "CourierNewPSMT", "Damascus", "DamascusLight", "DamascusMedium", "DevanagariSangamMN", "Didot", "DiwanMishafi",
                "EuphemiaUCAS", "Farah", "Futura-CondensedMedium", "Futura-Medium", "Galvji", "GeezaPro", "Georgia", "GillSans", "GillSans-Light",
                "GranthaSangamMN-Regular", "Helvetica", "Helvetica-Light", "HelveticaNeue", "HelveticaNeue-Light", "HelveticaNeue-Medium",
                "HelveticaNeue-Thin", "HelveticaNeue-UltraLight", "HiraKakuProN-W3", "HiraMaruProN-W4", "HiraMinProN-W3", "HiraginoSans-W3",
                "HiraginoSans-W4", "HoeflerText-Regular", "Kailasa", "KefaIII-Light", "KefaIII-Regular", "KhmerSangamMN", "KohinoorBangla-Light",
                "KohinoorBangla-Regular", "KohinoorDevanagari-Light", "KohinoorDevanagari-Regular", "KohinoorGujarati-Light",
                "KohinoorGujarati-Regular", "KohinoorTelugu-Light", "KohinoorTelugu-Medium", "KohinoorTelugu-Regular", "LaoSangamMN",
                "MalayalamSangamMN", "MarkerFelt-Thin", "Menlo-Regular", "MuktaMahee-Light", "MuktaMahee-Regular", "MyanmarSangamMN",
                "Noteworthy-Light", "NotoNastaliqUrdu", "NotoSansKannada-Light", "NotoSansKannada-Regular", "NotoSansMyanmar-Light",
                "NotoSansMyanmar-Regular", "NotoSansOriya", "NotoSansSyriac-Regular", "NotoSansSyriac-Regular_ExtraLight",
                "NotoSansSyriac-Regular_Light", "NotoSansSyriac-Regular_Medium", "NotoSansSyriac-Regular_Thin", "Optima-Regular", "Palatino-Roman",
                "Papyrus", "Papyrus-Condensed", "PartyLetPlain", "PingFangHK-Light", "PingFangHK-Medium", "PingFangHK-Regular", "PingFangHK-Thin",
                "PingFangHK-Ultralight", "PingFangMO-Light", "PingFangMO-Medium", "PingFangMO-Regular", "PingFangMO-Thin", "PingFangMO-Ultralight",
                "PingFangSC-Light", "PingFangSC-Medium", "PingFangSC-Regular", "PingFangSC-Thin", "PingFangSC-Ultralight", "PingFangTC-Light",
                "PingFangTC-Medium", "PingFangTC-Regular", "PingFangTC-Thin", "PingFangTC-Ultralight", "Rockwell-Regular", "STHeitiSC-Light",
                "STIXTwoMath-Regular", "STIXTwoText", "STIXTwoText_Medium", "SavoyeLetPlain", "SinhalaSangamMN", "SnellRoundhand", "Symbol",
                "TamilSangamMN", "Thonburi", "Thonburi-Light", "TimesNewRomanPSMT", "TrebuchetMS", "Verdana", "ZapfDingbatsITC", "Zapfino"
            ]),
            (1, [
                "Arial-ItalicMT", "Avenir-BookOblique", "Avenir-LightOblique", "Avenir-MediumOblique", "Avenir-Oblique", "AvenirNext-Italic",
                "AvenirNext-MediumItalic", "AvenirNext-UltraLightItalic", "AvenirNextCondensed-Italic", "AvenirNextCondensed-MediumItalic",
                "AvenirNextCondensed-UltraLightItalic", "Baskerville-Italic", "BodoniSvtyTwoITCTT-BookIta", "BodoniSvtyTwoOSITCTT-BookIt",
                "Charter-Italic", "Cochin-Italic", "CourierNewPS-ItalicMT", "Didot-Italic", "EuphemiaUCAS-Italic", "Futura-MediumItalic",
                "Georgia-Italic", "GillSans-Italic", "GillSans-LightItalic", "Helvetica-LightOblique", "Helvetica-Oblique", "HelveticaNeue-Italic",
                "HelveticaNeue-LightItalic", "HelveticaNeue-MediumItalic", "HelveticaNeue-ThinItalic", "HelveticaNeue-UltraLightItalic",
                "HoeflerText-Italic", "Menlo-Italic", "Optima-Italic", "Palatino-Italic", "Rockwell-Italic", "STIXTwoText-Italic",
                "STIXTwoText-Italic_Medium-Italic", "TimesNewRomanPS-ItalicMT", "TrebuchetMS-Italic", "Verdana-Italic"
            ]),
            (2, [
                "AlNile-Bold", "AmericanTypewriter-Bold", "AmericanTypewriter-CondensedBold", "AmericanTypewriter-Semibold", "AppleSDGothicNeo-Bold",
                "AppleSDGothicNeo-SemiBold", "Arial-BoldMT", "ArialHebrew-Bold", "Avenir-Black", "Avenir-Heavy", "AvenirNext-Bold",
                "AvenirNext-DemiBold", "AvenirNext-Heavy", "AvenirNextCondensed-Bold", "AvenirNextCondensed-DemiBold", "AvenirNextCondensed-Heavy",
                "Baskerville-Bold", "Baskerville-SemiBold", "BodoniSvtyTwoITCTT-Bold", "BradleyHandITCTT-Bold", "ChalkboardSE-Bold", "Charter-Black",
                "Charter-Bold", "Cochin-Bold", "Copperplate-Bold", "CourierNewPS-BoldMT", "DINAlternate-Bold", "DINCondensed-Bold", "DamascusBold",
                "DamascusSemiBold", "DevanagariSangamMN-Bold", "Didot-Bold", "EuphemiaUCAS-Bold", "Futura-Bold", "Futura-CondensedExtraBold",
                "Galvji-Bold", "GeezaPro-Bold", "Georgia-Bold", "GillSans-Bold", "GillSans-SemiBold", "GillSans-UltraBold", "GranthaSangamMN-Bold",
                "Helvetica-Bold", "HelveticaNeue-Bold", "HelveticaNeue-CondensedBlack", "HelveticaNeue-CondensedBold", "HiraMinProN-W6",
                "HiraginoSans-W5", "HiraginoSans-W6", "HiraginoSans-W7", "HiraginoSans-W8", "HoeflerText-Black", "Impact", "Kailasa-Bold",
                "KefaIII-Bold", "KefaIII-ExtraBold", "KohinoorBangla-Semibold", "KohinoorDevanagari-Semibold", "KohinoorGujarati-Bold",
                "MalayalamSangamMN-Bold", "MarkerFelt-Wide", "Menlo-Bold", "MuktaMahee-Bold", "MyanmarSangamMN-Bold", "Noteworthy-Bold",
                "NotoNastaliqUrdu-Bold", "NotoSansKannada-Bold", "NotoSansMyanmar-Bold", "NotoSansOriya-Bold", "NotoSansSyriac-Regular_Black",
                "NotoSansSyriac-Regular_Bold", "NotoSansSyriac-Regular_ExtraBold", "NotoSansSyriac-Regular_SemiBold", "Optima-Bold",
                "Optima-ExtraBlack", "Palatino-Bold", "PingFangHK-Semibold", "PingFangMO-Semibold", "PingFangSC-Semibold", "PingFangTC-Semibold",
                "Rockwell-Bold", "STIXTwoText_Bold", "STIXTwoText_SemiBold", "SinhalaSangamMN-Bold", "SnellRoundhand-Black", "SnellRoundhand-Bold",
                "TamilSangamMN-Bold", "Thonburi-Bold", "TimesNewRomanPS-BoldMT", "TrebuchetMS-Bold", "Verdana-Bold"
            ]),
            (3, [
                "Arial-BoldItalicMT", "Avenir-BlackOblique", "Avenir-HeavyOblique", "AvenirNext-BoldItalic", "AvenirNext-DemiBoldItalic",
                "AvenirNext-HeavyItalic", "AvenirNextCondensed-BoldItalic", "AvenirNextCondensed-DemiBoldItalic", "AvenirNextCondensed-HeavyItalic",
                "Baskerville-BoldItalic", "Baskerville-SemiBoldItalic", "Charter-BlackItalic", "Charter-BoldItalic", "Cochin-BoldItalic",
                "CourierNewPS-BoldItalicMT", "Georgia-BoldItalic", "GillSans-BoldItalic", "GillSans-SemiBoldItalic", "Helvetica-BoldOblique",
                "HelveticaNeue-BoldItalic", "HoeflerText-BlackItalic", "Menlo-BoldItalic", "Optima-BoldItalic", "Palatino-BoldItalic",
                "Rockwell-BoldItalic", "STIXTwoText-Italic_Bold-Italic", "STIXTwoText-Italic_SemiBold-Italic", "TimesNewRomanPS-BoldItalicMT",
                "Trebuchet-BoldItalic", "Verdana-BoldItalic"
            ]),
        ]
        return Dictionary(uniqueKeysWithValues: byTraits.flatMap { group in group.names.map { ($0, group.traits) } })
    }()
}
