import Foundation

/// A storyboard view controller's attributes besides its class and identifier (docs/formats/nib.md
/// "Storyboards"; nib-experiments `sb-vc-*`): its title first, its restoration identifier after its
/// storyboard identifier, the others after its segue templates.
struct ControllerSettings {
    var title: NibArchivable?
    var restorationIdentifier: NibString?
    var modalTransitionStyle: Int?
    var modalPresentationStyle: Int?
    /// `<value key="contentSizeForViewInPopover" type="size">`, after the presentation style
    /// (`sb-popover-content-size*`).
    var preferredContentSize: (width: Double, height: Double)?
    var hidesBottomBarWhenPushed = false
    /// `<extendedEdge key="edgesForExtendedLayout">`'s edges: top 1, left 2, bottom 4, right 8 (`sb-edges-*`).
    var edgesForExtendedLayout: Int?
    var extendedLayoutIncludesOpaqueBars = false
    var adjustsScrollViewInsets = true

    func encodeTitle(to encoder: NibEncoder) throws {
        if let title { try encoder.encode(title, forKey: "UITitle") }
    }

    func encodeRestorationIdentifier(to encoder: NibEncoder) throws {
        if let restorationIdentifier { try encoder.encode(restorationIdentifier, forKey: "UIRestorationIdentifier") }
    }

    /// Whether it writes any presentation key.
    var presents: Bool {
        modalTransitionStyle != nil || modalPresentationStyle != nil || preferredContentSize != nil || hidesBottomBarWhenPushed || edgesForExtendedLayout != nil || extendedLayoutIncludesOpaqueBars
            || !adjustsScrollViewInsets
    }

    func encodePresentation(to encoder: NibEncoder) {
        if let modalTransitionStyle { encoder.encode(.integer(modalTransitionStyle), forKey: "UIModalTransitionStyle") }
        if let modalPresentationStyle { encoder.encode(.integer(modalPresentationStyle), forKey: "UIModalPresentationStyle") }
        if let preferredContentSize { encoder.encode(.data(NibView.doubles([preferredContentSize.width, preferredContentSize.height])), forKey: "UIPreferredContentSize") }
        if hidesBottomBarWhenPushed { encoder.encode(.boolean(true), forKey: "UIHidesBottomBarWhenPushed") }
        if let edgesForExtendedLayout { encoder.encode(.integer(edgesForExtendedLayout), forKey: "UIKeyEdgesForExtendedLayout") }
        if extendedLayoutIncludesOpaqueBars { encoder.encode(.integer(1), forKey: "UIKeyExtendedLayoutIncludesOpaqueBars") }
        if !adjustsScrollViewInsets { encoder.encode(.integer(0), forKey: "UIKeyAutomaticallyAdjustsScrollViewInsets") }
    }

    static let attributes = ["title", "restorationIdentifier", "useStoryboardIdentifierAsRestorationIdentifier", "modalTransitionStyle",
                             "modalPresentationStyle", "hidesBottomBarWhenPushed", "extendedLayoutIncludesOpaqueBars", "automaticallyAdjustsScrollViewInsets"]
    /// `UIModalTransitionStyle` (coverVertical, the default, is not written) and
    /// `UIModalPresentationStyle` (written whenever given) by the names documents use.
    static let transitionStyles = ["coverVertical": 0, "flipHorizontal": 1, "crossDissolve": 2]
    static let presentationStyles = ["fullScreen": 0, "pageSheet": 1, "formSheet": 2, "currentContext": 3, "overFullScreen": 5, "overCurrentContext": 6]
}

extension DocumentCompiler {
    /// A view controller's settings; `useStoryboardIdentifierAsRestorationIdentifier` makes the
    /// storyboard identifier its restoration identifier (`sb-vc-restoration-storyboard-id`); an equal
    /// restoration identifier or title is the same string of the document's
    /// (`sb-vc-restoration-equal-storyboard-id`, `sb-cvc-netnewswire`); in an `.lproj` folder the title
    /// is localizable as `<id>.title` (the corpus's uncloudnotes CreateNoteWithImages).
    mutating func controllerSettings(_ controller: XIBElement, storyboardIdentifier: NibString?) throws -> ControllerSettings {
        let attributes = controller.attributes
        var settings = ControllerSettings()
        settings.title = attributes["title"].map { text($0, id: attributes["id"], property: "title") }
        if try bool(controller, "useStoryboardIdentifierAsRestorationIdentifier", default: false) {
            guard attributes["restorationIdentifier"] == nil, let storyboardIdentifier else {
                throw unsupported("a restoration identifier from a missing storyboard identifier")
            }
            settings.restorationIdentifier = storyboardIdentifier
        } else {
            settings.restorationIdentifier = attributes["restorationIdentifier"].map { string($0) }
        }
        settings.modalTransitionStyle = try attributes["modalTransitionStyle"].flatMap { style in
            style == "coverVertical" ? nil : try mapped(style, ControllerSettings.transitionStyles, "modalTransitionStyle")
        }
        settings.modalPresentationStyle = try attributes["modalPresentationStyle"].map { try mapped($0, ControllerSettings.presentationStyles, "modalPresentationStyle") }
        settings.hidesBottomBarWhenPushed = try bool(controller, "hidesBottomBarWhenPushed", default: false)
        let values = controller.children(named: "value")
        guard values.count <= 1 else { throw unsupported("a view controller of two <value>s") }
        settings.preferredContentSize = try values.first.map { value in
            try check(value, attributes: ["key", "type", "width", "height"], children: [])
            try self.value(value, "key", in: ["contentSizeForViewInPopover"])
            try self.value(value, "type", in: ["size"])
            return (try number(value.attributes["width"] ?? "", "width"), try number(value.attributes["height"] ?? "", "height"))
        }
        guard settings.preferredContentSize == nil || !settings.hidesBottomBarWhenPushed else {
            throw unsupported("a popover content size beside hidesBottomBarWhenPushed")
        }
        let edges = controller.children(named: "extendedEdge")
        guard edges.count <= 1 else { throw unsupported("a view controller of two <extendedEdge>s") }
        settings.edgesForExtendedLayout = try edges.first.map { edge in
            try check(edge, attributes: ["key", "top", "left", "bottom", "right"], children: [])
            try value(edge, "key", in: ["edgesForExtendedLayout"])
            return try [("top", 1), ("left", 2), ("bottom", 4), ("right", 8)].reduce(0) { bits, side in try bool(edge, side.0, default: false) ? bits | side.1 : bits }
        }
        settings.extendedLayoutIncludesOpaqueBars = try bool(controller, "extendedLayoutIncludesOpaqueBars", default: false)
        settings.adjustsScrollViewInsets = try bool(controller, "automaticallyAdjustsScrollViewInsets", default: true)
        return settings
    }
}
