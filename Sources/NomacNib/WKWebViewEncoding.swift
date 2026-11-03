import Foundation

/// What a `WKWebView` writes after a view's keys (docs/formats/nib.md "Web views"; nib-experiments
/// `web-view*`, `sb-web-view`): its configuration, IB's defaults but the preferences' minimum font
/// size, and the user agent, the empty string, shared with the configuration's application name.
struct WebViewContent {
    let configuration: NibWebViewConfiguration

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(configuration, forKey: "configuration")
        encoder.encode(.boolean(false), forKey: "allowsBackForwardNavigationGestures")
        try encoder.encode(configuration.applicationName, forKey: "customUserAgent")
        encoder.encode(.boolean(true), forKey: "allowsLinkPreview")
        encoder.encode(.boolean(false), forKey: "findInteractionEnabled")
    }
}

/// `WKWebViewConfiguration` as IB writes it.
final class NibWebViewConfiguration: NibArchivable {
    let preferences: NibWebPreferences
    let applicationName: NibString

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
        encoder.encode(.boolean(false), forKey: "suppressesIncrementalRendering")
        try encoder.encode(applicationName, forKey: "applicationNameForUserAgent")
        encoder.encode(.boolean(true), forKey: "allowsAirPlayForMediaPlayback")
        encoder.encode(.boolean(true), forKey: "drawsBackground")
        encoder.encode(.integer(127), forKey: "dataDetectorTypes")
        encoder.encode(.boolean(false), forKey: "allowsInlineMediaPlayback")
        encoder.encode(.boolean(false), forKey: "allowsInlineMediaPlaybackAfterFullscreen")
        encoder.encode(.boolean(false), forKey: "mediaTypesRequiringUserActionForPlayback")
        encoder.encode(.integer(0), forKey: "selectionGranularity")
        encoder.encode(.boolean(true), forKey: "allowsPictureInPictureMediaPlayback")
        encoder.encode(.boolean(false), forKey: "ignoresViewportScaleLimits")
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

/// `WKPreferences`: the minimum font size, the rest IB's defaults (`web-view-minimum-font`).
final class NibWebPreferences: NibArchivable {
    let minimumFontSize: Double

    init(minimumFontSize: Double) {
        self.minimumFontSize = minimumFontSize
    }

    var className: String { "WKPreferences" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.double(minimumFontSize), forKey: "minimumFontSize")
        encoder.encode(.boolean(false), forKey: "javaScriptCanOpenWindowsAutomatically")
        encoder.encode(.boolean(true), forKey: "javaScriptEnabled")
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
    /// A `<wkWebView>`'s `<wkWebViewConfiguration>`: media types needing no user action, preferences
    /// of a minimum font size at most; anything else is refused.
    mutating func webViewContent(_ element: XIBElement) throws -> WebViewContent {
        let configurations = element.children(named: "wkWebViewConfiguration")
        guard configurations.count == 1, let configuration = configurations.first else { throw unsupported("a web view without one configuration") }
        try check(configuration, attributes: ["key"], children: ["audiovisualMediaTypes", "wkPreferences"])
        try value(configuration, "key", in: ["configuration"])
        let media = configuration.children(named: "audiovisualMediaTypes"), preferences = configuration.children(named: "wkPreferences")
        guard media.count == 1, preferences.count == 1, let types = media.first, let preference = preferences.first else {
            throw unsupported("a web view configuration without its media types and preferences")
        }
        try check(types, attributes: ["key", "none"], children: [])
        try value(types, "key", in: ["mediaTypesRequiringUserActionForPlayback"])
        try value(types, "none", in: ["YES"])
        try check(preference, attributes: ["key", "minimumFontSize"], children: [])
        try value(preference, "key", in: ["preferences"])
        let minimum = try preference.attributes["minimumFontSize"].map { try number($0, "minimumFontSize") } ?? 0
        return WebViewContent(configuration: NibWebViewConfiguration(preferences: NibWebPreferences(minimumFontSize: minimum), applicationName: string("")))
    }
}
