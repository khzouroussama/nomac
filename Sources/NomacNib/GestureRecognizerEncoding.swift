import Foundation

/// A gesture recognizer, a top-level object of a xib (docs/formats/nib.md "Gesture recognizers";
/// nib-experiments `gesture-*`): whether it is disabled, the touch types it allows, then what its
/// kind writes.
final class NibGestureRecognizer: NibArchivable {
    enum Kind {
        case tap(taps: Int, touches: Int)
        case swipe(direction: Int)
        case pan
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
        }
    }

    func encode(to encoder: NibEncoder) throws {
        if !enabled { encoder.encode(.boolean(true), forKey: "UIGestureRecognizer.disabled") }
        encoder.encode(.integer(15), forKey: "UIGestureRecognizer.allowedTouchTypes")
        encoder.encode(.boolean(true), forKey: "UIGestureRecognizer.requiresExclusiveTouchType")
        switch kind {
        case .tap(let taps, let touches):
            try encoder.encode(NibTapRecognizer(taps: taps, touches: touches), forKey: "UITapGestureRecognizer._imp")
        case .swipe(let direction):
            if direction != 1 { encoder.encode(.integer(direction), forKey: "UISwipeGestureRecognizer.direction") }
        case .pan:
            encoder.encode(.integer(0), forKey: "UIPanGestureRecognizer.allowedScrollTypesMask")
        }
    }

    static let elements = ["tapGestureRecognizer", "swipeGestureRecognizer", "panGestureRecognizer"]
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
    /// A top-level `<tapGestureRecognizer>`, `<swipeGestureRecognizer>` or `<panGestureRecognizer>` and its
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
        default:
            try check(element, attributes: ["id", "userLabel", "enabled", "minimumNumberOfTouches"], children: ["connections"])
            try value(element, "minimumNumberOfTouches", in: ["1"])
            kind = .pan
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
