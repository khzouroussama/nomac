import Foundation

/// What a `WKWebView` writes after a view's keys (docs/formats/nib.md "Web views"; nib-experiments
/// `web-view*`, `web-config-*`, `web-media-*`, `web-detect-*`, `web-prefs-*`, `sb-web-view`): its
/// configuration, its navigation gestures, its user agent, the empty string without one, and its
/// link previews.
struct WebViewContent {
    static let attributes = ["allowsBackForwardNavigationGestures", "allowsLinkPreview", "customUserAgent"]

    let configuration: NibWebViewConfiguration
    let allowsBackForwardNavigationGestures: Bool
    let customUserAgent: NibString
    let allowsLinkPreview: Bool

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(configuration, forKey: "configuration")
        encoder.encode(.boolean(allowsBackForwardNavigationGestures), forKey: "allowsBackForwardNavigationGestures")
        try encoder.encode(customUserAgent, forKey: "customUserAgent")
        encoder.encode(.boolean(allowsLinkPreview), forKey: "allowsLinkPreview")
        encoder.encode(.boolean(false), forKey: "findInteractionEnabled")
    }
}

/// `WKWebViewConfiguration`: the document's settings among IB's defaults.
final class NibWebViewConfiguration: NibArchivable {
    static let attributes = ["key", "allowsInlineMediaPlayback", "allowsAirPlayForMediaPlayback", "allowsPictureInPictureMediaPlayback",
                             "suppressesIncrementalRendering", "applicationNameForUserAgent", "ignoresViewportScaleLimits", "selectionGranularity"]
    /// `WKDataDetectorTypes` bits by IB's names (`web-detect-*`).
    static let dataDetectorBits = ["phoneNumber": 1, "link": 2, "address": 4, "calendarEvent": 8, "trackingNumber": 16, "flightNumber": 32, "lookupSuggestion": 64]

    let preferences: NibWebPreferences
    let applicationName: NibString
    var suppressesIncrementalRendering = false
    var allowsAirPlay = true
    var dataDetectorTypes = 127
    var allowsInlineMediaPlayback = false
    var requiresUserActionForMedia = false
    var selectionGranularity = 0
    var allowsPictureInPicture = true
    var ignoresViewportScaleLimits = false

    init(preferences: NibWebPreferences, applicationName: NibString) {
        self.preferences = preferences
        self.applicationName = applicationName
    }

    var className: String { "WKWebViewConfiguration" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(NibKeylessObject("WKProcessPool"), forKey: "processPool")
        try encoder.encode(preferences, forKey: "preferences")
        try encoder.encode(NibKeylessObject("WKUserContentController"), forKey: "userContentController")
        try encoder.encode(NibWebsiteDataStore(), forKey: "websiteDataStore")
        encoder.encode(.boolean(suppressesIncrementalRendering), forKey: "suppressesIncrementalRendering")
        try encoder.encode(applicationName, forKey: "applicationNameForUserAgent")
        encoder.encode(.boolean(allowsAirPlay), forKey: "allowsAirPlayForMediaPlayback")
        encoder.encode(.boolean(true), forKey: "drawsBackground")
        encoder.encode(.integer(dataDetectorTypes), forKey: "dataDetectorTypes")
        encoder.encode(.boolean(allowsInlineMediaPlayback), forKey: "allowsInlineMediaPlayback")
        encoder.encode(.boolean(false), forKey: "allowsInlineMediaPlaybackAfterFullscreen")
        encoder.encode(.boolean(requiresUserActionForMedia), forKey: "mediaTypesRequiringUserActionForPlayback")
        encoder.encode(.integer(selectionGranularity), forKey: "selectionGranularity")
        encoder.encode(.boolean(allowsPictureInPicture), forKey: "allowsPictureInPictureMediaPlayback")
        encoder.encode(.boolean(ignoresViewportScaleLimits), forKey: "ignoresViewportScaleLimits")
        encoder.encode(.integer(0), forKey: "dragLiftDelay")
        encoder.encode(.boolean(true), forKey: "textInteractionGesturesEnabled")
        encoder.encode(.boolean(true), forKey: "longPressActionsEnabled")
        encoder.encode(.boolean(false), forKey: "systemPreviewEnabled")
        encoder.encode(.boolean(true), forKey: "shouldDecidePolicyBeforeLoadingQuickLookPreview")
        encoder.encode(.boolean(true), forKey: "scrollToTextFragmentMarkingEnabled")
        encoder.encode(.boolean(false), forKey: "multiRepresentationHEICInsertionEnabled")
        encoder.encode(.boolean(true), forKey: "scrollToTextFragmentIndicatorEnabled")
    }
}

/// `WKPreferences`: the minimum font size and JavaScript's settings, the rest IB's defaults
/// (`web-view-minimum-font`, `web-prefs-*`).
final class NibWebPreferences: NibArchivable {
    let minimumFontSize: Double
    let javaScriptCanOpenWindowsAutomatically: Bool
    let javaScriptEnabled: Bool

    init(minimumFontSize: Double, javaScriptCanOpenWindowsAutomatically: Bool, javaScriptEnabled: Bool) {
        self.minimumFontSize = minimumFontSize
        self.javaScriptCanOpenWindowsAutomatically = javaScriptCanOpenWindowsAutomatically
        self.javaScriptEnabled = javaScriptEnabled
    }

    var className: String { "WKPreferences" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.double(minimumFontSize), forKey: "minimumFontSize")
        encoder.encode(.boolean(javaScriptCanOpenWindowsAutomatically), forKey: "javaScriptCanOpenWindowsAutomatically")
        encoder.encode(.boolean(javaScriptEnabled), forKey: "javaScriptEnabled")
        encoder.encode(.boolean(true), forKey: "textInteractionEnabled")
        encoder.encode(.boolean(false), forKey: "shouldPrintBackgrounds")
    }
}

/// `WKWebsiteDataStore`, the default one.
final class NibWebsiteDataStore: NibArchivable {
    var className: String { "WKWebsiteDataStore" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.boolean(true), forKey: "isDefaultDataStore")
    }
}

/// An object of a class that writes no keys (`WKProcessPool`, `WKUserContentController`).
final class NibKeylessObject: NibArchivable {
    let className: String

    init(_ className: String) {
        self.className = className
    }

    func encode(to encoder: NibEncoder) throws {}
}

extension DocumentCompiler {
    /// A `<wkWebView>`'s attributes and `<wkWebViewConfiguration>`. ibtool fails on a web view without
    /// a configuration or preferences. A `<dataDetectorTypes>` is the bits it names, 127 without one;
    /// media types other than `none`, or none given, require a user action (`web-media-*`).
    mutating func webViewContent(_ element: XIBElement) throws -> WebViewContent {
        let configurations = element.children(named: "wkWebViewConfiguration")
        guard configurations.count == 1, let configuration = configurations.first else { throw unsupported("a web view without one configuration") }
        try check(configuration, attributes: NibWebViewConfiguration.attributes, children: ["audiovisualMediaTypes", "wkPreferences", "dataDetectorTypes"])
        try value(configuration, "key", in: ["configuration"])
        let media = configuration.children(named: "audiovisualMediaTypes"), preferences = configuration.children(named: "wkPreferences")
        let detectors = configuration.children(named: "dataDetectorTypes")
        guard media.count <= 1, detectors.count <= 1, preferences.count == 1, let preference = preferences.first else {
            throw unsupported("a web view configuration without one preferences, or with two media types or data detectors")
        }
        for types in media {
            try check(types, attributes: ["key", "none", "audio", "video"], children: [])
            try value(types, "key", in: ["mediaTypesRequiringUserActionForPlayback"])
        }
        try check(preference, attributes: ["key", "minimumFontSize", "javaScriptCanOpenWindowsAutomatically", "javaScriptEnabled"], children: [])
        try value(preference, "key", in: ["preferences"])
        let minimum = try preference.attributes["minimumFontSize"].map { try number($0, "minimumFontSize") } ?? 0
        let content = NibWebViewConfiguration(
            preferences: NibWebPreferences(minimumFontSize: minimum,
                                           javaScriptCanOpenWindowsAutomatically: try bool(preference, "javaScriptCanOpenWindowsAutomatically", default: false),
                                           javaScriptEnabled: try bool(preference, "javaScriptEnabled", default: true)),
            applicationName: string(configuration.attributes["applicationNameForUserAgent"] ?? ""))
        content.suppressesIncrementalRendering = try bool(configuration, "suppressesIncrementalRendering", default: false)
        content.allowsAirPlay = try bool(configuration, "allowsAirPlayForMediaPlayback", default: true)
        content.allowsInlineMediaPlayback = try bool(configuration, "allowsInlineMediaPlayback", default: false)
        content.allowsPictureInPicture = try bool(configuration, "allowsPictureInPictureMediaPlayback", default: true)
        content.ignoresViewportScaleLimits = try bool(configuration, "ignoresViewportScaleLimits", default: false)
        content.selectionGranularity = try mapped(configuration.attributes["selectionGranularity"] ?? "dynamic", ["dynamic": 0, "character": 1], "selectionGranularity")
        content.requiresUserActionForMedia = try media.first.map { !(try bool($0, "none", default: false)) } ?? true
        if let detector = detectors.first {
            try check(detector, attributes: ["key", "none"] + NibWebViewConfiguration.dataDetectorBits.keys, children: [])
            try value(detector, "key", in: ["dataDetectorTypes"])
            content.dataDetectorTypes = try NibWebViewConfiguration.dataDetectorBits.reduce(0) { bits, entry in
                try bool(detector, entry.key, default: false) ? bits | entry.value : bits
            }
        }
        return WebViewContent(configuration: content,
                              allowsBackForwardNavigationGestures: try bool(element, "allowsBackForwardNavigationGestures", default: false),
                              customUserAgent: string(element.attributes["customUserAgent"] ?? ""),
                              allowsLinkPreview: try bool(element, "allowsLinkPreview", default: true))
    }
}
