import Foundation

/// What an `MKMapView` writes after a view's keys (docs/formats/nib.md "Map views"; nib-experiments
/// `map-*`, `sb-map`), whatever the document's `showsBuildings`.
struct MapContent {
    static let attributes = ["mapType", "showsUserLocation", "pitchEnabled", "showsBuildings", "zoomEnabled", "rotateEnabled", "scrollEnabled", "showsCompass",
                             "showsPointsOfInterest", "showsScale", "showsTraffic"]
    static let types = ["standard": 0, "satellite": 1, "hybrid": 2, "satelliteFlyover": 3, "hybridFlyover": 4, "mutedStandard": 5]

    let type: Int
    let zoomEnabled: Bool
    let scrollEnabled: Bool
    let showsUserLocation: Bool
    let pitchEnabled: Bool
    let rotateEnabled: Bool
    let showsTraffic: Bool
    let showsCompass: Bool
    let showsScale: Bool
    let showsPointsOfInterest: Bool
    let configuration: NibMapConfiguration

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.null, forKey: "MKDelegate")
        encoder.encode(.integer(type), forKey: "MKMapType")
        encoder.encode(.boolean(zoomEnabled), forKey: "MKZoomEnabled")
        encoder.encode(.boolean(scrollEnabled), forKey: "MKScrollEnabled")
        encoder.encode(.boolean(showsUserLocation), forKey: "MKShowsUserLocation")
        encoder.encode(.boolean(pitchEnabled), forKey: "MKPitchEnabled")
        encoder.encode(.boolean(rotateEnabled), forKey: "MKRotateEnabled")
        encoder.encode(.boolean(true), forKey: "MKShowsBuildings")
        encoder.encode(.boolean(showsTraffic), forKey: "MKShowsTraffic")
        encoder.encode(.boolean(showsCompass), forKey: "MKShowsCompass")
        encoder.encode(.boolean(showsScale), forKey: "MKShowsScaleKey")
        encoder.encode(.boolean(showsPointsOfInterest), forKey: "MKShowsPointsOfInterest")
        encoder.encode(.null, forKey: "MKPointOfInterestFilter")
        try encoder.encode(configuration, forKey: "MKPreferredConfiguration")
        encoder.encode(.integer(1), forKey: "MKPitchButtonVisibility")
        encoder.encode(.boolean(false), forKey: "MKShowsUserTrackingButton")
    }
}

/// The map configuration a map type stands for: standard for the standard and muted types, imagery
/// for satellites, hybrid for hybrids; flyovers are realistic, and imagery shows no traffic
/// (`map-hybrid`, `map-satellite`, `map-flyover`, `map-muted`, `map-traffic-*`).
final class NibMapConfiguration: NibArchivable {
    let name: String
    let realistic: Bool
    let showsTraffic: Bool
    let emphasis: Int?

    init(name: String, realistic: Bool, showsTraffic: Bool, emphasis: Int?) {
        self.name = name
        self.realistic = realistic
        self.showsTraffic = showsTraffic
        self.emphasis = emphasis
    }

    var className: String { name }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.integer(realistic ? 1 : 0), forKey: "MKMapConfigurationElevationStyle")
        encoder.encode(.boolean(showsTraffic), forKey: "MKMapConfigurationShowsTraffic")
        encoder.encode(.boolean(false), forKey: "MKMapConfigurationShowsHiking")
        encoder.encode(.boolean(false), forKey: "MKMapConfigurationShowsTopographicFeatures")
        encoder.encode(.null, forKey: "MKMapConfigurationPointOfInterestFilter")
        if let emphasis { encoder.encode(.integer(emphasis), forKey: "MKStandardMapConfigurationEmphasisStyle") }
    }
}

extension DocumentCompiler {
    /// A `<mapView>`'s keys; its `<standardMapConfiguration>` wins over its `mapType`
    /// (`map-configuration-*`), its traffic the map's too (`map-configuration-traffic-only`).
    func mapContent(_ element: XIBElement) throws -> MapContent {
        var type = try mapped(element.attributes["mapType"] ?? "standard", MapContent.types, "mapType")
        var showsTraffic = try bool(element, "showsTraffic", default: false)
        var realistic = type == 3 || type == 4
        for configuration in element.children(named: "standardMapConfiguration") {
            try check(configuration, attributes: ["key", "elevationStyle", "showsTraffic"], children: [])
            try value(configuration, "key", in: ["preferredConfiguration"])
            try value(configuration, "elevationStyle", in: ["realistic", "flat"])
            guard !showsTraffic else { throw unsupported("a map view's traffic beside its configuration") }
            type = 0
            realistic = configuration.attributes["elevationStyle"] == "realistic"
            showsTraffic = try bool(configuration, "showsTraffic", default: false)
        }
        let imagery = type == 1 || type == 3, standard = type == 0 || type == 5
        let configuration = NibMapConfiguration(name: imagery ? "MKImageryMapConfiguration" : standard ? "MKStandardMapConfiguration" : "MKHybridMapConfiguration",
                                                realistic: realistic, showsTraffic: showsTraffic && !imagery, emphasis: standard ? (type == 5 ? 1 : 0) : nil)
        return MapContent(type: type, zoomEnabled: try bool(element, "zoomEnabled", default: true), scrollEnabled: try bool(element, "scrollEnabled", default: true),
                          showsUserLocation: try bool(element, "showsUserLocation", default: false), pitchEnabled: try bool(element, "pitchEnabled", default: true),
                          rotateEnabled: try bool(element, "rotateEnabled", default: true), showsTraffic: showsTraffic, showsCompass: try bool(element, "showsCompass", default: true),
                          showsScale: try bool(element, "showsScale", default: false), showsPointsOfInterest: try bool(element, "showsPointsOfInterest", default: true),
                          configuration: configuration)
    }
}
