import NomacPlist
import Testing

/// Orders observed in Xcode 27.0's archives (docs/formats/foundation-collections.md).
@Suite struct FoundationHashTableTests {
    /// coredata-experiments `attributes-16`: 16 properties fill 13 buckets (12 held), then 23.
    @Test func propertyDictionaries() throws {
        let names = (0..<16).map { "a" + String($0 < 10 ? "0\($0)" : "\($0)") }
        #expect(try FoundationHashTable.inserting(names).copied().keys == [
            "a15", "a07", "a02", "a13", "a05", "a11", "a00", "a08", "a03", "a14", "a06", "a01", "a12", "a09", "a04", "a10",
        ])
    }

    /// `attributes-12`: twelve names stay in 13 buckets, and the copy moves them to 23.
    @Test func copiesChangeSize() throws {
        let names = (0..<12).map { "a" + String($0 < 10 ? "0\($0)" : "\($0)") }
        #expect(try FoundationHashTable.inserting(names).copied().keys == [
            "a07", "a02", "a05", "a11", "a00", "a08", "a03", "a06", "a01", "a09", "a04", "a10",
        ])
    }

    /// `entities-12`: an entities dictionary is rebuilt from a copy, then copied again.
    @Test func entityDictionaries() throws {
        let names = (0..<12).map { "E" + String($0 < 10 ? "0\($0)" : "\($0)") }
        let first = try FoundationHashTable.inserting(names).copied()
        #expect(try FoundationHashTable.inserting(first.keys).copied().keys == [
            "E11", "E00", "E05", "E08", "E03", "E06", "E01", "E09", "E04", "E10", "E07", "E02",
        ])
    }

    /// signing-experiments `nested`: an app-store-connect export reads the app's Info.plist (24
    /// keys in Swift's order) into a dictionary of 41 buckets and writes its keys in that order.
    @Test func createdWithKeys() throws {
        let archived = [
            "BuildMachineOSBuild", "CFBundleDevelopmentRegion", "CFBundleExecutable", "CFBundleIdentifier",
            "CFBundleInfoDictionaryVersion", "CFBundleName", "CFBundlePackageType", "CFBundleShortVersionString",
            "CFBundleSupportedPlatforms", "CFBundleVersion", "DTCompiler", "DTPlatformBuild", "DTPlatformName",
            "DTPlatformVersion", "DTSDKBuild", "DTSDKName", "DTXcode", "DTXcodeBuild", "LSRequiresIPhoneOS", "MinimumOSVersion",
            "UIApplicationSupportsIndirectInputEvents", "UIDeviceFamily", "UILaunchStoryboardName",
            "UIRequiredDeviceCapabilities",
        ]
        #expect(try FoundationHashTable.created(with: archived).keys == [
            "CFBundleName", "DTSDKName", "DTXcode", "UILaunchStoryboardName", "DTSDKBuild", "CFBundleDevelopmentRegion",
            "CFBundleVersion", "BuildMachineOSBuild", "DTPlatformName", "CFBundlePackageType", "CFBundleShortVersionString",
            "CFBundleSupportedPlatforms", "UIApplicationSupportsIndirectInputEvents", "CFBundleInfoDictionaryVersion",
            "CFBundleExecutable", "DTCompiler", "UIRequiredDeviceCapabilities", "MinimumOSVersion", "CFBundleIdentifier",
            "UIDeviceFamily", "DTPlatformVersion", "DTXcodeBuild", "LSRequiresIPhoneOS", "DTPlatformBuild",
        ])
    }

    /// A nib's key table (docs/formats/nib.md "Encoding"): its keys inserted in first-use order,
    /// `UINibEncoderEmptyKey` uncounted until the archive is finished.
    static func nibTable(_ used: [String]) throws -> [String] {
        var table = FoundationHashTable()
        for key in used {
            try table.insert(key, counted: key != "UINibEncoderEmptyKey")
        }
        try table.count("UINibEncoderEmptyKey")
        return table.keys
    }

    /// nib-experiments `view` (20 keys, 23 buckets), `system-red` (31, 41), `color-key-outer-rgb-3-0`
    /// (34 keys: 33 and the empty key in 41 buckets, then 71 when it is counted), and the
    /// `ladder-*` rungs of 54, 87 and 120 keys (127, 191 and 251 buckets).
    static let nibTables: [(String, [String], [String])] = [
        ("view", [
            "UINibTopLevelObjectsKey", "NSInlinedValue", "UINibEncoderEmptyKey", "UIProxiedObjectIdentifier", "NS.bytes",
            "UIBounds", "UICenter", "UIDeepDrawRect", "UIOpaque", "UIAutoresizeSubviews", "UIAutoresizingMask",
            "UIViewSemanticContentAttribute", "UIViewLargeContentStoredProperties", "UINibObjectsKey", "UINibConnectionsKey",
            "UINibVisibleWindowsKey", "UINibAccessibilityConfigurationsKey", "UINibTraitStorageListsKey",
            "UINibKeyValuePairsKey", "IBUINibLNEVersionKey",
        ], [
            "IBUINibLNEVersionKey", "UIDeepDrawRect", "UICenter", "UIViewLargeContentStoredProperties",
            "UINibTopLevelObjectsKey", "UINibVisibleWindowsKey", "NSInlinedValue", "UIAutoresizeSubviews", "UIBounds",
            "UINibAccessibilityConfigurationsKey", "UINibEncoderEmptyKey", "UIOpaque", "UINibKeyValuePairsKey", "NS.bytes",
            "UINibConnectionsKey", "UIViewSemanticContentAttribute", "UINibTraitStorageListsKey", "UIAutoresizingMask",
            "UIProxiedObjectIdentifier", "UINibObjectsKey",
        ]),
        ("system-red", [
            "UINibTopLevelObjectsKey", "NSInlinedValue", "UINibEncoderEmptyKey", "UIProxiedObjectIdentifier", "NS.bytes",
            "UIBounds", "UICenter", "UIBackgroundColor", "UISystemColorName", "UIColorComponentCount", "UIRed", "UIGreen",
            "UIGreen-Double", "UIBlue", "UIBlue-Double", "UIAlpha", "NSRGB", "NSColorSpace", "UIDeepDrawRect", "UIOpaque",
            "UIAutoresizeSubviews", "UIAutoresizingMask", "UIViewSemanticContentAttribute", "UIViewLargeContentStoredProperties",
            "UINibObjectsKey", "UINibConnectionsKey", "UINibVisibleWindowsKey", "UINibAccessibilityConfigurationsKey",
            "UINibTraitStorageListsKey", "UINibKeyValuePairsKey", "IBUINibLNEVersionKey",
        ], [
            "NSColorSpace", "IBUINibLNEVersionKey", "UIAutoresizeSubviews", "UIColorComponentCount", "UIBlue",
            "UIBackgroundColor", "UIDeepDrawRect", "UINibTopLevelObjectsKey", "UIViewSemanticContentAttribute",
            "UIViewLargeContentStoredProperties", "NSRGB", "UIAlpha", "NS.bytes", "UINibKeyValuePairsKey",
            "UINibEncoderEmptyKey", "UIBlue-Double", "UIProxiedObjectIdentifier", "UINibVisibleWindowsKey",
            "UINibAccessibilityConfigurationsKey", "UINibObjectsKey", "UIOpaque", "UICenter", "NSInlinedValue", "UIBounds",
            "UIAutoresizingMask", "UINibConnectionsKey", "UIRed", "UIGreen-Double", "UISystemColorName", "UIGreen",
            "UINibTraitStorageListsKey",
        ]),
        ("color-key-outer-rgb-3-0", [
            "UINibTopLevelObjectsKey", "NSInlinedValue", "UINibEncoderEmptyKey", "UIProxiedObjectIdentifier", "NS.bytes",
            "UIBounds", "UICenter", "UISubviews", "UIDeepDrawRect", "UIOpaque", "UIHidden", "UITag", "UIAutoresizeSubviews",
            "UIAutoresizingMask", "UIAlpha", "UIViewSemanticContentAttribute", "UIViewLargeContentStoredProperties",
            "UIBackgroundColor", "UIColorComponentCount", "UIRed", "UIRed-Double", "UIGreen", "UIGreen-Double", "UIBlue",
            "UIBlue-Double", "NSRGB", "NSColorSpace", "UINibObjectsKey", "UINibConnectionsKey", "UINibVisibleWindowsKey",
            "UINibAccessibilityConfigurationsKey", "UINibTraitStorageListsKey", "UINibKeyValuePairsKey", "IBUINibLNEVersionKey",
        ], [
            "UINibVisibleWindowsKey", "UIRed-Double", "UINibAccessibilityConfigurationsKey", "UISubviews", "NS.bytes",
            "UINibEncoderEmptyKey", "UIBounds", "NSInlinedValue", "IBUINibLNEVersionKey", "UIViewLargeContentStoredProperties",
            "UINibKeyValuePairsKey", "UIOpaque", "UIAutoresizeSubviews", "UIAlpha", "NSRGB", "UIGreen", "UIGreen-Double",
            "UIHidden", "UINibTopLevelObjectsKey", "UINibConnectionsKey", "UICenter", "UIRed", "UINibTraitStorageListsKey",
            "UIProxiedObjectIdentifier", "UIViewSemanticContentAttribute", "UIBackgroundColor", "UIDeepDrawRect",
            "UIBlue-Double", "NSColorSpace", "UIColorComponentCount", "UIBlue", "UITag", "UIAutoresizingMask", "UINibObjectsKey",
        ]),
        ("ladder48-b53-end-5", [
            "UINibTopLevelObjectsKey", "NSInlinedValue", "UINibEncoderEmptyKey", "UIProxiedObjectIdentifier", "NS.bytes",
            "UIBounds", "UICenter", "UISubviews", "UIDeepDrawRect", "UIAutoresizeSubviews", "UIViewSemanticContentAttribute",
            "UIViewLargeContentStoredProperties", "UISegmentInfo", "UISegmentStyle", "UISegmentPosition", "UIBackgroundColor",
            "UIColorComponentCount", "UIRed", "UIGreen", "UIBlue", "UIAlpha", "UIAlpha-Double", "NSRGB", "NSColorSpace",
            "UIAutoresizingMask", "UIClipsToBounds", "UIViewContentHuggingPriority", "UIDisabled", "UIContentVerticalAlignment",
            "UIContentVerticalAlignment2", "UIContentHorizontalAlignment", "UIPointerInteractionEnabled", "UIMomentary",
            "UISegments", "UIUseProportionalWidthSegments", "UISelectedSegmentIndex", "UITag", "UIUserInteractionDisabled",
            "UINumberOfPages", "UICurrentPage", "UIHideForSinglePage", "UIValue", "UIStepValue", "UIContinuous", "UIAutorepeat",
            "UIWraps", "UIOpaque", "UINibObjectsKey", "UINibConnectionsKey", "UINibVisibleWindowsKey",
            "UINibAccessibilityConfigurationsKey", "UINibTraitStorageListsKey", "UINibKeyValuePairsKey", "IBUINibLNEVersionKey",
        ], [
            "UIValue", "UINibVisibleWindowsKey", "NS.bytes", "UISegmentPosition", "UIViewSemanticContentAttribute",
            "UINibTopLevelObjectsKey", "UIBlue", "UIViewContentHuggingPriority", "UINibObjectsKey", "UIContentVerticalAlignment",
            "UIContinuous", "UINibKeyValuePairsKey", "UIBounds", "UINibTraitStorageListsKey", "UINibConnectionsKey",
            "UIBackgroundColor", "UICurrentPage", "UIDeepDrawRect", "UISubviews", "UITag", "UICenter", "UIOpaque",
            "UIContentHorizontalAlignment", "UIClipsToBounds", "UIGreen", "UINumberOfPages",
            "UIViewLargeContentStoredProperties", "UIAutoresizeSubviews", "UIHideForSinglePage", "NSRGB", "UISegmentStyle",
            "UIAutorepeat", "NSInlinedValue", "UIUserInteractionDisabled", "UIPointerInteractionEnabled", "UINibEncoderEmptyKey",
            "UISelectedSegmentIndex", "UIDisabled", "NSColorSpace", "UIAlpha-Double", "UINibAccessibilityConfigurationsKey",
            "UIAutoresizingMask", "UIProxiedObjectIdentifier", "UIAlpha", "UISegmentInfo", "UIContentVerticalAlignment2",
            "UIMomentary", "IBUINibLNEVersionKey", "UIColorComponentCount", "UISegments", "UIWraps", "UIStepValue",
            "UIUseProportionalWidthSegments", "UIRed",
        ]),
        ("ladderlong80-b20-end-7", [
            "UINibTopLevelObjectsKey", "NSInlinedValue", "UINibEncoderEmptyKey", "UIProxiedObjectIdentifier", "NS.bytes",
            "UIBounds", "UICenter", "UISubviews", "UIBackgroundColor", "UIColorComponentCount", "UIRed", "UIRed-Double",
            "UIGreen", "UIGreen-Double", "UIBlue", "UIBlue-Double", "UIAlpha", "NSRGB", "NSColorSpace", "UIDeepDrawRect",
            "UITag", "UIMultipleTouchEnabled", "UIAutoresizeSubviews", "UIAutoresizingMask", "UIViewSemanticContentAttribute",
            "UIViewLargeContentStoredProperties", "UISelected", "UIDisabled", "UIButtonStatefulContent", "NS.intval", "UITitle",
            "UIShowsTouchWhenHighlighted", "UIAdjustsImageWhenDisabled", "UIButtonType", "UIFont", "UIFontName",
            "UIFontDescriptor", "UIFontDescriptorAttributes", "NS.dblval", "UIFontDescriptorOptions", "UIFontPointSize",
            "UIFontTextStyleForScaling", "UIFontPointSizeForScaling", "UIFontMaximumPointSizeAfterScaling", "UIFontTraits",
            "UISystemFont", "NSName", "NSSize", "UIButtonConfiguration", "UIOpaque", "UIUserInteractionDisabled",
            "UIAlpha-Double", "UIHidden", "UIContentMode", "UIClipsToBounds", "UIHighlighted", "UIWhite", "NSWhite",
            "UIViewContentHuggingPriority", "UIActivityIndicatorViewStyle-Modern", "UIActivityIndicatorViewStyle",
            "UIHidesWhenStopped", "UIColor", "UITintColor", "UISystemColorName", "UIViewLayoutMargins",
            "UIViewLayoutMarginsFollowReadableWidth", "UIStackViewAxis", "UIStackViewDistribution", "UIStackViewAlignment",
            "UIStackViewSpacing", "UIStackViewBaselineRelative", "UIStackViewLayoutMarginsRelative", "UIValue", "UIStepValue",
            "UIContinuous", "UIAutorepeat", "UIWraps", "UIProgress", "UIProgressViewStyle", "UINibObjectsKey",
            "UINibConnectionsKey", "UINibVisibleWindowsKey", "UINibAccessibilityConfigurationsKey", "UINibTraitStorageListsKey",
            "UINibKeyValuePairsKey", "IBUINibLNEVersionKey",
        ], [
            "UIActivityIndicatorViewStyle-Modern", "UIViewLargeContentStoredProperties", "NS.bytes", "UIRed",
            "UIStackViewLayoutMarginsRelative", "UIStackViewSpacing", "UINibTraitStorageListsKey", "UIProgressViewStyle",
            "UIHighlighted", "UITitle", "NSInlinedValue", "UINibVisibleWindowsKey", "UITag", "UIAutorepeat", "UIFontTraits",
            "UIDisabled", "UIBounds", "NSRGB", "UINibKeyValuePairsKey", "UIContinuous", "UIOpaque", "NS.intval",
            "UIViewLayoutMargins", "UIGreen", "UIStackViewBaselineRelative", "UIAutoresizeSubviews", "UIColor",
            "UIProxiedObjectIdentifier", "UIShowsTouchWhenHighlighted", "UIRed-Double", "UIStackViewDistribution",
            "UIUserInteractionDisabled", "UIViewContentHuggingPriority", "UIStackViewAlignment", "UIButtonStatefulContent",
            "UISystemColorName", "UIHidden", "UIMultipleTouchEnabled", "UINibConnectionsKey", "UIViewSemanticContentAttribute",
            "UIButtonType", "UICenter", "UISelected", "NS.dblval", "UIProgress", "UIFontDescriptorAttributes",
            "UIFontPointSizeForScaling", "UIAlpha", "UIDeepDrawRect", "UIStackViewAxis", "IBUINibLNEVersionKey", "UITintColor",
            "UIFont", "NSName", "UIFontDescriptor", "NSSize", "UINibObjectsKey", "UIFontTextStyleForScaling",
            "UIFontMaximumPointSizeAfterScaling", "UIBlue", "UIFontDescriptorOptions", "UIAdjustsImageWhenDisabled",
            "UINibEncoderEmptyKey", "UIStepValue", "UIViewLayoutMarginsFollowReadableWidth", "UIColorComponentCount",
            "UIFontPointSize", "NSWhite", "UIAlpha-Double", "UISubviews", "UIWraps", "UIGreen-Double", "UIFontName",
            "UIAutoresizingMask", "UIBackgroundColor", "UIWhite", "UIClipsToBounds", "UIButtonConfiguration", "UISystemFont",
            "NSColorSpace", "UINibAccessibilityConfigurationsKey", "UINibTopLevelObjectsKey", "UIValue", "UIBlue-Double",
            "UIContentMode", "UIHidesWhenStopped", "UIActivityIndicatorViewStyle",
        ]),
        ("ladderlong112-b3-end-7", [
            "UINibTopLevelObjectsKey", "NSInlinedValue", "UINibEncoderEmptyKey", "UIProxiedObjectIdentifier", "NS.bytes",
            "UIBounds", "UICenter", "UISubviews", "UIDeepDrawRect", "UIOpaque", "UIAutoresizeSubviews", "UIAutoresizingMask",
            "UIViewSemanticContentAttribute", "UIViewLargeContentStoredProperties", "UIBackgroundColor", "UIColorComponentCount",
            "UIWhite", "UIAlpha", "NSWhite", "NSColorSpace", "UITag", "UIContentHorizontalAlignment", "UIFont", "UIFontName",
            "UIFontDescriptor", "UIFontDescriptorAttributes", "NS.dblval", "UIFontDescriptorOptions", "UIFontPointSize",
            "UIFontTextStyleForScaling", "UIFontPointSizeForScaling", "UIFontMaximumPointSizeAfterScaling", "UIFontTraits",
            "UISystemFont", "NSName", "NSSize", "UIPlaceholder", "UITextAlignment", "UIText", "UITextColor", "UISystemColorName",
            "UIBorderStyle", "UIClearsOnBeginEditing", "UIAdjustsFontSizeToFit", "UIMinimumFontSize", "UIClearButtonMode",
            "UIClearButtonOffset", "UIDisableTextColorUpdateOnTraitCollectionChange", "UIRoundedRectBackgroundCornerRadius",
            "UIUserInteractionDisabled", "UIMultipleTouchEnabled", "UIClipsToBounds",
            "UIScrollViewIndicatorInsetAdjustmentBehavior", "UIBounceEnabled", "UIShowsVerticalScrollIndicator",
            "UIPagingEnabled", "UIKeyboardDismissMode", "UIScrollViewContentInsetAdjustmentBehavior", "UIRed", "UIGreen",
            "UIBlue", "UIAlpha-Double", "NSRGB", "UIShowsHorizontalScrollIndicator", "UISegmentInfo", "UISegmentStyle",
            "UISegmentPosition", "UIViewContentHuggingPriority", "UIDisabled", "UIContentVerticalAlignment",
            "UIContentVerticalAlignment2", "UIPointerInteractionEnabled", "UISegments", "UISelectedSegmentIndex", "UIHidden",
            "UIActivityIndicatorViewStyle-Modern", "UIActivityIndicatorViewStyle", "UIHidesWhenStopped", "UIColor",
            "UITintColor", "UIRed-Double", "UIGreen-Double", "UIBlue-Double", "UIHighlighted", "UIButtonStatefulContent",
            "NS.intval", "UITitle", "UIShowsTouchWhenHighlighted", "UIAdjustsImageWhenDisabled", "UIButtonType",
            "UIButtonConfiguration", "UINumberOfPages", "UICurrentPage", "UIHideForSinglePage", "UIViewLayoutMargins",
            "UIViewLayoutMarginsFollowReadableWidth", "UIStackViewAxis", "UIStackViewDistribution", "UIStackViewAlignment",
            "UIStackViewSpacing", "UIStackViewBaselineRelative", "UIStackViewLayoutMarginsRelative", "UIBouncesZoom",
            "UIDirectionalLockEnabled", "UIContentMode", "UIAdjustsImageSizeForAccessibilityContentSizeCategory", "UIValue",
            "UIStepValue", "UIContinuous", "UIAutorepeat", "UIWraps", "UIProgress", "UIProgressViewStyle", "UINibObjectsKey",
            "UINibConnectionsKey", "UINibVisibleWindowsKey", "UINibAccessibilityConfigurationsKey", "UINibTraitStorageListsKey",
            "UINibKeyValuePairsKey", "IBUINibLNEVersionKey",
        ], [
            "UIViewLargeContentStoredProperties", "NSColorSpace", "UIRed-Double", "UIPagingEnabled", "UIColorComponentCount",
            "UIStepValue", "UINumberOfPages", "NSWhite", "UINibConnectionsKey", "UIContentHorizontalAlignment",
            "UIScrollViewContentInsetAdjustmentBehavior", "UIBackgroundColor", "UIFontName", "UINibTraitStorageListsKey",
            "UIGreen-Double", "UIClearsOnBeginEditing", "UIContentMode", "UIButtonType", "UIGreen", "UIProgress",
            "IBUINibLNEVersionKey", "UIFontDescriptor", "UIClearButtonOffset", "UIViewLayoutMarginsFollowReadableWidth",
            "UIClipsToBounds", "UIShowsTouchWhenHighlighted", "UIAlpha-Double", "UINibEncoderEmptyKey", "UIClearButtonMode",
            "UIDisabled", "UINibTopLevelObjectsKey", "UIFontMaximumPointSizeAfterScaling", "UIHidesWhenStopped",
            "UIProgressViewStyle", "UIColor", "UIAdjustsFontSizeToFit", "UIHideForSinglePage",
            "UIShowsHorizontalScrollIndicator", "UIScrollViewIndicatorInsetAdjustmentBehavior", "UIValue", "UIDeepDrawRect",
            "UIPlaceholder", "UINibAccessibilityConfigurationsKey", "UISegmentStyle", "NSName", "UIFontDescriptorOptions",
            "UISystemFont", "UISegmentInfo", "UIStackViewLayoutMarginsRelative", "UIMultipleTouchEnabled", "UISegmentPosition",
            "NSInlinedValue", "UIOpaque", "UIButtonStatefulContent", "UIProxiedObjectIdentifier", "UIDirectionalLockEnabled",
            "UIViewContentHuggingPriority", "UIFontTextStyleForScaling", "UIBounceEnabled", "UIActivityIndicatorViewStyle",
            "UIAutorepeat", "UITitle", "UIContinuous", "UIFontPointSize", "UIStackViewAlignment", "UIUserInteractionDisabled",
            "UITag", "UIKeyboardDismissMode", "NS.dblval", "UIFontDescriptorAttributes", "UISystemColorName",
            "UIAdjustsImageWhenDisabled", "UIHighlighted", "UIDisableTextColorUpdateOnTraitCollectionChange",
            "UIViewLayoutMargins", "UIBlue-Double", "UIFont", "UIStackViewDistribution", "NS.bytes", "UINibObjectsKey",
            "UIFontPointSizeForScaling", "UIButtonConfiguration", "UIHidden", "UIShowsVerticalScrollIndicator",
            "UINibKeyValuePairsKey", "UIAutoresizingMask", "UIAlpha", "UIViewSemanticContentAttribute", "UIStackViewAxis",
            "UIStackViewSpacing", "UIContentVerticalAlignment2", "UIWraps", "UIRed", "UITextAlignment", "UIBouncesZoom",
            "NSSize", "UITintColor", "UIFontTraits", "UICenter", "UISubviews", "UIWhite", "UIRoundedRectBackgroundCornerRadius",
            "UIBounds", "UIActivityIndicatorViewStyle-Modern", "UINibVisibleWindowsKey", "UIMinimumFontSize",
            "UIAutoresizeSubviews", "UIBlue", "UITextColor", "UISegments", "UICurrentPage", "UIBorderStyle", "NSRGB",
            "UIAdjustsImageSizeForAccessibilityContentSizeCategory", "UIContentVerticalAlignment", "UIPointerInteractionEnabled",
            "UIStackViewBaselineRelative", "UISelectedSegmentIndex", "UIText", "NS.intval",
        ]),
    ]

    @Test(arguments: nibTables)
    func nibKeyTables(name: String, used: [String], observed: [String]) throws {
        #expect(try Self.nibTable(used) == observed, "\(name)")
    }

    static let thresholds: [([String], [String])] = [
        // threshold-41-33: names in file order, then the observed order.
        (["bcepaun", "bdxfj", "biq", "ctnsbfwq", "cxwhaqfc", "dbimbl", "dwau", "hdifzm", "jcjz", "jqosli", "kazegws", "khiuvxqmm", "kyjtqrus", "lhfsicwdm", "mvl", "nnft", "qfek", "qiavjiv", "qkxfcdgks", "qshzvq", "rspzsh", "rumylbz", "sxwhsh", "trydlkplc", "vhbceo", "wizn", "wjrm", "xbczene", "xcum", "xojmjox", "xznixeo", "ykkbrlh", "yortyqlbc"],
         ["khiuvxqmm", "qshzvq", "kazegws", "xojmjox", "qiavjiv", "xbczene", "vhbceo", "mvl", "trydlkplc", "dwau", "hdifzm", "jcjz", "bcepaun", "rspzsh", "yortyqlbc", "lhfsicwdm", "ykkbrlh", "xcum", "nnft", "rumylbz", "wizn", "wjrm", "dbimbl", "kyjtqrus", "ctnsbfwq", "xznixeo", "jqosli", "bdxfj", "qkxfcdgks", "cxwhaqfc", "biq", "qfek", "sxwhsh"]),
        // threshold-41-34: names in file order, then the observed order.
        (["bcmtx", "bxakm", "bzposccx", "dczne", "dxeci", "flx", "gdlen", "imjdelyq", "iugqivdum", "joikpa", "jqlvfq", "ktzhgkgyx", "lcdosw", "mtokecija", "mud", "mvmd", "nueahlg", "ogjuszg", "ojqm", "oszpxbn", "otajy", "owy", "pzqerufuy", "qwcknasj", "secmylj", "skut", "tfisup", "tjxxn", "vnhlt", "vqaa", "xpsor", "yczwyva", "yzhjumh", "zjupju"],
         ["imjdelyq", "pzqerufuy", "secmylj", "tfisup", "dxeci", "flx", "gdlen", "ktzhgkgyx", "ogjuszg", "vqaa", "joikpa", "vnhlt", "owy", "nueahlg", "tjxxn", "jqlvfq", "lcdosw", "xpsor", "yczwyva", "qwcknasj", "mvmd", "bxakm", "mud", "ojqm", "oszpxbn", "mtokecija", "skut", "yzhjumh", "otajy", "zjupju", "dczne", "bcmtx", "iugqivdum", "bzposccx"]),
        // threshold-71-52: names in file order, then the observed order.
        (["abscfydt", "cfdopp", "clzqyp", "dds", "dlkiaq", "egje", "ervzbvir", "exlelv", "ggdkavxim", "gipmjekvf", "inspvu", "jdmshulk", "jmizlp", "jvliip", "khtrfb", "kks", "kwkx", "kymsw", "lsuoweq", "lutgtldqv", "manohblry", "mfluhek", "necigfjga", "nkafuj", "onuwdp", "oynrgmsxv", "penobrwn", "pkjevfhvo", "pprapi", "pqbbmkjyc", "pqmj", "pyqphei", "qekh", "qxokvqoto", "sdd", "tcjhgf", "tudvpxof", "tvf", "uazsbqe", "uflaf", "urvdrf", "wqdbnxen", "wsxyk", "xfpup", "xgqknlprc", "xoohpkeqa", "ybwilgwg", "yovwzcl", "yqos", "yytxcseha", "zhywltgsz", "znciq"],
         ["gipmjekvf", "dlkiaq", "pyqphei", "lutgtldqv", "yytxcseha", "oynrgmsxv", "dds", "exlelv", "penobrwn", "xfpup", "khtrfb", "sdd", "urvdrf", "necigfjga", "zhywltgsz", "tvf", "jdmshulk", "manohblry", "pprapi", "tcjhgf", "yovwzcl", "kymsw", "wqdbnxen", "pkjevfhvo", "onuwdp", "lsuoweq", "kwkx", "cfdopp", "abscfydt", "clzqyp", "inspvu", "qxokvqoto", "uazsbqe", "ervzbvir", "egje", "tudvpxof", "xgqknlprc", "yqos", "ybwilgwg", "jvliip", "znciq", "jmizlp", "pqmj", "mfluhek", "pqbbmkjyc", "ggdkavxim", "qekh", "uflaf", "wsxyk", "nkafuj", "xoohpkeqa", "kks"]),
        // threshold-71-53: names in file order, then the observed order.
        (["ahalpsv", "cgezyjoer", "chmntn", "cijmvns", "cinaxew", "crsrggbh", "dgvgy", "ehlypnq", "ejivjaspr", "ejvzctt", "epapwsn", "fkzq", "frqld", "fxmtx", "gekak", "gxdhh", "haer", "hrmte", "iqii", "jvtst", "lfpatle", "lgzhzrv", "lodcejiik", "lrtmj", "mgobu", "nfchfyah", "nkeztfib", "nuywb", "nyquusmwv", "optlh", "pgcgzux", "qdgqimrk", "qgaxcytr", "qqzjfhsg", "qvc", "ratrclpg", "rnqa", "rqmaydz", "skwthdwju", "tpkijei", "ugmdqg", "vtzsqmqvj", "wuefcladv", "wxp", "xigwvzhil", "xizcmtd", "xjxvu", "xpu", "xsrroh", "ymtb", "zhnblcm", "zsaednyq", "zveobji"],
         ["qqzjfhsg", "ehlypnq", "lrtmj", "cinaxew", "gxdhh", "wxp", "cijmvns", "ymtb", "xizcmtd", "qgaxcytr", "zveobji", "pgcgzux", "nkeztfib", "xigwvzhil", "jvtst", "ejvzctt", "haer", "tpkijei", "nyquusmwv", "xpu", "dgvgy", "frqld", "lodcejiik", "gekak", "fkzq", "mgobu", "wuefcladv", "xsrroh", "fxmtx", "zsaednyq", "cgezyjoer", "nuywb", "qdgqimrk", "hrmte", "iqii", "rnqa", "xjxvu", "crsrggbh", "rqmaydz", "ratrclpg", "zhnblcm", "vtzsqmqvj", "optlh", "ahalpsv", "lgzhzrv", "skwthdwju", "ugmdqg", "lfpatle", "ejivjaspr", "qvc", "chmntn", "epapwsn", "nfchfyah"]),
    ]

    @Test(arguments: thresholds)
    func capacityLimits(names: [String], observed: [String]) throws {
        #expect(try FoundationHashTable.inserting(names).copied().keys == observed)
    }

    /// 157 keys grow the table to 383 buckets, observed holding up to 199 keys; 200 are refused
    /// (BACKLOG B-259).
    @Test func refusesTablesLargerThanObserved() throws {
        #expect(try FoundationHashTable.inserting((0..<157).map { "k\($0)" }).keys.count == 157)
        #expect(throws: (any Error).self) {
            try FoundationHashTable.inserting((0..<200).map { "k\($0)" })
        }
    }
}
