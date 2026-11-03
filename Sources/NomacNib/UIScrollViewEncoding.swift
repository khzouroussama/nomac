import Foundation

/// What a `UIScrollView` writes after a view's keys (docs/formats/nib.md "UIScrollView";
/// nib-experiments `scroll-*`): its indicator inset adjustment, then each attribute that differs
/// from IB's, then its content inset adjustment, always.
struct ScrollContent {
    var indicatorStyle: Int?
    var bounces = true
    var showsHorizontalScrollIndicator = true
    var showsVerticalScrollIndicator = true
    var scrollEnabled = true
    var delaysContentTouches = true
    var canCancelContentTouches = true
    var pagingEnabled = false
    var bouncesZoom = true
    var alwaysBounceVertical = false
    var alwaysBounceHorizontal = false
    var directionalLockEnabled = false
    var minimumZoomScale: Float?
    var maximumZoomScale: Float?
    var keyboardDismissMode: Int?
    var contentInsetAdjustmentBehavior = 0
    /// A collection view of prototypes writes a nil delegate (`collection-prototypes-mode`).
    var nilDelegate = false

    func encode(to encoder: NibEncoder) {
        encoder.encode(.integer(1), forKey: "UIScrollViewIndicatorInsetAdjustmentBehavior")
        if let indicatorStyle { encoder.encode(.integer(indicatorStyle), forKey: "UIIndicatorStyle") }
        if !bounces { encoder.encode(.boolean(false), forKey: "UIBounceEnabled") }
        if !showsHorizontalScrollIndicator { encoder.encode(.boolean(false), forKey: "UIShowsHorizontalScrollIndicator") }
        if !showsVerticalScrollIndicator { encoder.encode(.boolean(false), forKey: "UIShowsVerticalScrollIndicator") }
        if !scrollEnabled { encoder.encode(.boolean(true), forKey: "UIScrollDisabled") }
        if !delaysContentTouches { encoder.encode(.boolean(false), forKey: "UIDelaysContentTouches") }
        if !canCancelContentTouches { encoder.encode(.boolean(false), forKey: "UICanCancelContentTouches") }
        if pagingEnabled { encoder.encode(.boolean(true), forKey: "UIPagingEnabled") }
        if bouncesZoom { encoder.encode(.boolean(true), forKey: "UIBouncesZoom") }
        if alwaysBounceVertical { encoder.encode(.boolean(true), forKey: "UIAlwaysBounceVertical") }
        if alwaysBounceHorizontal { encoder.encode(.boolean(true), forKey: "UIAlwaysBounceHorizontal") }
        if directionalLockEnabled { encoder.encode(.boolean(true), forKey: "UIDirectionalLockEnabled") }
        if let minimumZoomScale { encoder.encode(.float(minimumZoomScale), forKey: "UIMinimumZoomScale") }
        if let maximumZoomScale { encoder.encode(.float(maximumZoomScale), forKey: "UIMaximumZoomScale") }
        if let keyboardDismissMode { encoder.encode(.integer(keyboardDismissMode), forKey: "UIKeyboardDismissMode") }
        if nilDelegate { encoder.encode(.null, forKey: "UIDelegate") }
        encoder.encode(.integer(contentInsetAdjustmentBehavior), forKey: "UIScrollViewContentInsetAdjustmentBehavior")
    }

    static let attributes = ["indicatorStyle", "bounces", "showsHorizontalScrollIndicator", "showsVerticalScrollIndicator", "scrollEnabled",
                             "delaysContentTouches", "canCancelContentTouches", "pagingEnabled", "bouncesZoom", "alwaysBounceVertical",
                             "alwaysBounceHorizontal", "directionalLockEnabled", "minimumZoomScale", "maximumZoomScale", "keyboardDismissMode",
                             "contentInsetAdjustmentBehavior"]
    /// `UIScrollView.IndicatorStyle`, `KeyboardDismissMode` and `ContentInsetAdjustmentBehavior` by
    /// the names documents use.
    static let indicatorStyles = ["default": 0, "black": 1, "white": 2]
    static let keyboardDismissModes = ["none": 0, "onDrag": 1, "interactive": 2]
    static let contentInsetAdjustmentBehaviors = ["automatic": 0, "scrollableAxes": 1, "never": 2, "always": 3]
}

extension DocumentCompiler {
    /// A `<scrollView>`'s content (`scroll-*`). Its content and frame layout guides are listed as
    /// placeholders, like a safe area no constraint names (`scroll-guides`, `scroll-subview-guides`);
    /// constraints to them are refused.
    func scrollContent(_ element: XIBElement) throws -> ScrollContent {
        let attributes = element.attributes
        var scroll = ScrollContent()
        scroll.indicatorStyle = try attributes["indicatorStyle"].flatMap { style in
            style == "default" ? nil : try mapped(style, ScrollContent.indicatorStyles, "indicatorStyle")
        }
        scroll.bounces = try bool(element, "bounces", default: true)
        scroll.showsHorizontalScrollIndicator = try bool(element, "showsHorizontalScrollIndicator", default: true)
        scroll.showsVerticalScrollIndicator = try bool(element, "showsVerticalScrollIndicator", default: true)
        scroll.scrollEnabled = try bool(element, "scrollEnabled", default: true)
        scroll.delaysContentTouches = try bool(element, "delaysContentTouches", default: true)
        scroll.canCancelContentTouches = try bool(element, "canCancelContentTouches", default: true)
        scroll.pagingEnabled = try bool(element, "pagingEnabled", default: false)
        scroll.bouncesZoom = try bool(element, "bouncesZoom", default: true)
        scroll.alwaysBounceVertical = try bool(element, "alwaysBounceVertical", default: false)
        scroll.alwaysBounceHorizontal = try bool(element, "alwaysBounceHorizontal", default: false)
        scroll.directionalLockEnabled = try bool(element, "directionalLockEnabled", default: false)
        scroll.minimumZoomScale = try attributes["minimumZoomScale"].map { Float(try number($0, "minimumZoomScale")) }
        scroll.maximumZoomScale = try attributes["maximumZoomScale"].map { Float(try number($0, "maximumZoomScale")) }
        scroll.keyboardDismissMode = try attributes["keyboardDismissMode"].flatMap { mode in
            mode == "none" ? nil : try mapped(mode, ScrollContent.keyboardDismissModes, "keyboardDismissMode")
        }
        scroll.contentInsetAdjustmentBehavior = try mapped(attributes["contentInsetAdjustmentBehavior"] ?? "automatic",
                                                           ScrollContent.contentInsetAdjustmentBehaviors, "contentInsetAdjustmentBehavior")
        for guide in element.children(named: "viewLayoutGuide") {
            try check(guide, attributes: ["key", "id"], children: [])
            try value(guide, "key", in: ["contentLayoutGuide", "frameLayoutGuide"])
        }
        return scroll
    }
}
