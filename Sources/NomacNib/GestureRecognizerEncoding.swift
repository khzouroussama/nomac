import Foundation

/// A gesture recognizer, a top-level object of a xib (docs/formats/nib.md "Gesture recognizers";
/// nib-experiments `gesture-*`): whether it is disabled, the touch types it allows, then what its
/// kind writes.
final class NibGestureRecognizer: NibArchivable {
    enum Kind {
        case tap(taps: Int, touches: Int)
        case swipe(direction: Int)
        case pan
        case longPress(duration: Float, movement: Float)
        case pinch
        case rotation
        case screenEdgePan
    }

    let kind: Kind
    var enabled = true

    init(kind: Kind) {
        self.kind = kind
    }

    var className: String {
        switch kind {
        case .tap: "UITapGestureRecognizer"
        case .swipe: "UISwipeGestureRecognizer"
        case .pan: "UIPanGestureRecognizer"
        case .longPress: "UILongPressGestureRecognizer"
        case .pinch: "UIPinchGestureRecognizer"
        case .rotation: "UIRotationGestureRecognizer"
        case .screenEdgePan: "UIScreenEdgePanGestureRecognizer"
        }
    }

    func encode(to encoder: NibEncoder) throws {
        if !enabled { encoder.encode(.boolean(true), forKey: "UIGestureRecognizer.disabled") }
        if case .screenEdgePan = kind {
            encoder.encode(.integer(11), forKey: "UIGestureRecognizer.allowedTouchTypes")
        } else {
            encoder.encode(.integer(15), forKey: "UIGestureRecognizer.allowedTouchTypes")
        }
        encoder.encode(.boolean(true), forKey: "UIGestureRecognizer.requiresExclusiveTouchType")
        switch kind {
        case .tap(let taps, let touches):
            try encoder.encode(NibTapRecognizer(taps: taps, touches: touches), forKey: "UITapGestureRecognizer._imp")
        case .swipe(let direction):
            if direction != 1 { encoder.encode(.integer(direction), forKey: "UISwipeGestureRecognizer.direction") }
        case .pan:
            encoder.encode(.integer(0), forKey: "UIPanGestureRecognizer.allowedScrollTypesMask")
        case .longPress(let duration, let movement):
            try encoder.encode(NibTapRecognizer(taps: 0, touches: 1), forKey: "UILongPressGestureRecognizer._imp")
            if duration != 0.5 { encoder.encode(.float(duration), forKey: "UILongPressGestureRecognizer.minimumPressDuration") }
            if movement != 10 { encoder.encode(.float(movement), forKey: "UILongPressGestureRecognizer.allowableMovement") }
        case .pinch, .rotation:
            break
        case .screenEdgePan:
            encoder.encode(.integer(0), forKey: "UIPanGestureRecognizer.allowedScrollTypesMask")
            encoder.encode(.integer(0), forKey: "UIScreenEdgePanGestureRecognizer.edges")
        }
    }

    /// IB writes a long press recognizer as `<pongPressGestureRecognizer>` (`gesture-long-press*`).
    static let elements = ["tapGestureRecognizer", "swipeGestureRecognizer", "panGestureRecognizer", "pongPressGestureRecognizer", "pinchGestureRecognizer",
                           "rotationGestureRecognizer", "screenEdgePanGestureRecognizer"]
    /// `UISwipeGestureRecognizer.Direction` by the names documents use; right, the default, is not written.
    static let directions = ["right": 1, "left": 2, "up": 4, "down": 8]
}

/// `UITapRecognizer`: a tap recognizer's taps and touches, each when not 1 (`gesture-tap-two-taps`).
final class NibTapRecognizer: NibArchivable {
    let taps: Int
    let touches: Int

    init(taps: Int, touches: Int) {
        self.taps = taps
        self.touches = touches
    }

    var className: String { "UITapRecognizer" }

    func encode(to encoder: NibEncoder) throws {
        if taps != 1 { encoder.encode(.integer(taps), forKey: "UITapRecognizer.numberOfTapsRequired") }
        if touches != 1 { encoder.encode(.integer(touches), forKey: "UITapRecognizer.numberOfTouchesRequired") }
    }
}

extension DocumentCompiler {
    /// A top-level gesture recognizer of one of `NibGestureRecognizer.elements` and its
    /// action, unless a storyboard's scene compiles it (`connects`); views attach it with their
    /// `gestureRecognizers` outlet collection.
    mutating func gestureRecognizer(_ element: XIBElement, connects: Bool = true) throws -> NibGestureRecognizer {
        let kind: NibGestureRecognizer.Kind
        switch element.name {
        case "tapGestureRecognizer":
            try check(element, attributes: ["id", "userLabel", "enabled", "numberOfTapsRequired", "numberOfTouchesRequired"], children: ["connections"])
            kind = .tap(taps: try integer(element.attributes["numberOfTapsRequired"] ?? "1", "numberOfTapsRequired"),
                        touches: try integer(element.attributes["numberOfTouchesRequired"] ?? "1", "numberOfTouchesRequired"))
        case "swipeGestureRecognizer":
            try check(element, attributes: ["id", "userLabel", "enabled", "direction"], children: ["connections"])
            kind = .swipe(direction: try mapped(element.attributes["direction"] ?? "right", NibGestureRecognizer.directions, "direction"))
        case "pongPressGestureRecognizer":
            // Its press duration and movement, floats left out at 0.5 and 10, after its inner tap
            // recognizer of 0 taps (`gesture-long-press*`).
            try check(element, attributes: ["id", "userLabel", "enabled", "allowableMovement", "minimumPressDuration"], children: ["connections"])
            kind = .longPress(duration: Float(try number(element.attributes["minimumPressDuration"] ?? "0.5", "minimumPressDuration")),
                              movement: Float(try number(element.attributes["allowableMovement"] ?? "10", "allowableMovement")))
        case "pinchGestureRecognizer", "rotationGestureRecognizer":
            try check(element, attributes: ["id", "userLabel", "enabled"], children: ["connections"])
            kind = element.name == "pinchGestureRecognizer" ? .pinch : .rotation
        default:
            try check(element, attributes: ["id", "userLabel", "enabled", "minimumNumberOfTouches"], children: ["connections"])
            try value(element, "minimumNumberOfTouches", in: ["1"])
            // A screen edge pan recognizer allows touch types 11 and writes no edges, 0
            // (`gesture-edge-pan`).
            kind = element.name == "screenEdgePanGestureRecognizer" ? .screenEdgePan : .pan
        }
        let recognizer = NibGestureRecognizer(kind: kind)
        recognizer.enabled = try bool(element, "enabled", default: true)
        guard let id = element.attributes["id"] else { throw unsupported("a gesture recognizer without an id") }
        if connects {
            gestureRecognizers[id] = recognizer
            try connections(of: element, source: recognizer)
        }
        return recognizer
    }
}
