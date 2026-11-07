import Foundation

/// What a `UIActivityIndicatorView` writes after a view's keys (docs/formats/nib.md "Activity
/// indicators and other controls"; nib-experiments `activity-*`): its style twice, whether it
/// hides when stopped and animates, its color, the tint the medium and large styles take, and
/// whether the color is the document's.
struct ActivityContent {
    let modernStyle: Int
    let style: Int
    var hidesWhenStopped: Bool
    var animating: Bool
    var color: NibColor?
    var tintColor: NibColor?

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.integer(modernStyle), forKey: "UIActivityIndicatorViewStyle-Modern")
        encoder.encode(.integer(style), forKey: "UIActivityIndicatorViewStyle")
        if !hidesWhenStopped { encoder.encode(.boolean(false), forKey: "UIHidesWhenStopped") }
        if animating { encoder.encode(.boolean(true), forKey: "UIAnimating") }
        try encoder.encode(color, forKey: "UIColor")
        if let tintColor { try encoder.encode(tintColor, forKey: "UITintColor") }
        if color != nil { encoder.encode(.boolean(true), forKey: "UIDisableUpdateColorOnTraitCollectionChange") }
    }

    static let attributes = ["style", "hidesWhenStopped", "animating"]
    /// `UIActivityIndicatorView.Style`, modern and legacy, by the names documents use; medium and
    /// large tint with `secondaryLabelColor` unless the document gives a color (`activity-style-*`).
    static let styles = ["medium": (100, 1), "large": (101, 0), "white": (1, 1), "whiteLarge": (0, 0), "gray": (2, 2)]
}

/// What a `UISegmentedControl` writes after a control's keys (`segmented-*`): whether it is
/// momentary, its segments, whether their widths follow their content, the selected segment and
/// its tint.
struct SegmentedContent {
    var control: ControlContent
    var momentary: Bool
    var segments: [NibView]
    var proportionalWidths: Bool
    var selectedIndex: Int
    var selectedTintColor: NibColor?

    func encode(to encoder: NibEncoder) throws {
        control.encode(to: encoder)
        if momentary { encoder.encode(.boolean(true), forKey: "UIMomentary") }
        try encoder.encode(NibArray(segments, mutable: true), forKey: "UISegments")
        if proportionalWidths { encoder.encode(.boolean(true), forKey: "UIUseProportionalWidthSegments") }
        encoder.encode(.integer(selectedIndex), forKey: "UISelectedSegmentIndex")
        if let selectedTintColor { try encoder.encode(selectedTintColor, forKey: "UISegmentedControlSelectedSegmentTintColor") }
    }

    static let attributes = ContentAlignment.attributes + ["segmentControlStyle", "selectedSegmentIndex", "momentary", "apportionsSegmentWidthsByContent"]
}

/// A `UISegment`: its title, width, style 5 and position: 0 for the first segment, 3 for the
/// second, 1 for the others (`segmented-positions-*`).
struct SegmentContent {
    let title: NibArchivable
    var width: Float?
    let position: Int

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(title, forKey: "UISegmentInfo")
        if let width { encoder.encode(.float(width), forKey: "UISegmentWidth") }
        encoder.encode(.integer(5), forKey: "UISegmentStyle")
        if position != 0 { encoder.encode(.integer(position), forKey: "UISegmentPosition") }
    }
}

/// What a `UIProgressView` writes after a view's keys (`progress-*`). Its height is at least 4
/// points, and a bar's is a point less than the document's, at least 3, its top kept
/// (`progress-height-*`, `progress-bar-height-*`).
struct ProgressContent {
    var progress: Float
    var barStyle: Bool
    var progressTintColor: NibColor?
    var trackTintColor: NibColor?

    func encode(to encoder: NibEncoder) throws {
        if progress != 0 { encoder.encode(.float(progress), forKey: "UIProgress") }
        if let progressTintColor { try encoder.encode(progressTintColor, forKey: "UIProgressProgressTintColor") }
        if barStyle { encoder.encode(.integer(1), forKey: "UIProgressViewStyle") }
        if let trackTintColor { try encoder.encode(trackTintColor, forKey: "UIProgressTrackTintColor") }
    }

    static let attributes = ["progress", "progressViewStyle"]
}

/// What a `UIPageControl` writes after a control's keys (`page-*`).
struct PageContent {
    var control: ControlContent
    var numberOfPages: Int
    var currentPage: Int
    var hidesForSinglePage: Bool
    var defersCurrentPageDisplay: Bool
    var currentPageIndicatorTintColor: NibColor?
    var pageIndicatorTintColor: NibColor?

    func encode(to encoder: NibEncoder) throws {
        control.encode(to: encoder)
        encoder.encode(.integer(numberOfPages), forKey: "UINumberOfPages")
        encoder.encode(.integer(currentPage), forKey: "UICurrentPage")
        if hidesForSinglePage { encoder.encode(.boolean(true), forKey: "UIHideForSinglePage") }
        if defersCurrentPageDisplay { encoder.encode(.boolean(true), forKey: "UIDefersCurrentPageDisplay") }
        if let currentPageIndicatorTintColor { try encoder.encode(currentPageIndicatorTintColor, forKey: "UICurrentPageIndicatorTintColor") }
        if let pageIndicatorTintColor { try encoder.encode(pageIndicatorTintColor, forKey: "UIPageIndicatorTintColor") }
    }

    static let attributes = ContentAlignment.attributes + ["numberOfPages", "currentPage", "hidesForSinglePage", "defersCurrentPageDisplay"]
}

/// What a `UISlider` writes after a control's keys (`slider-*`).
struct SliderContent {
    var control: ControlContent
    var value: Float
    var minimumValue: Float
    var maximumValue: Float
    var continuous: Bool
    var minimumValueImage: NibImage?
    var maximumValueImage: NibImage?
    var minimumTrackTintColor: NibColor?
    var maximumTrackTintColor: NibColor?
    var thumbTintColor: NibColor?

    func encode(to encoder: NibEncoder) throws {
        control.encode(to: encoder)
        if value != 0 { encoder.encode(.float(value), forKey: "UIValue") }
        if minimumValue != 0 { encoder.encode(.float(minimumValue), forKey: "UIMinValue") }
        if maximumValue != 1 { encoder.encode(.float(maximumValue), forKey: "UIMaxValue") }
        if !continuous { encoder.encode(.boolean(false), forKey: "UIContinuous") }
        if let minimumValueImage { try encoder.encode(minimumValueImage, forKey: "UIMinimumValueImage") }
        if let maximumValueImage { try encoder.encode(maximumValueImage, forKey: "UIMaximumValueImage") }
        if let minimumTrackTintColor { try encoder.encode(minimumTrackTintColor, forKey: "UIMinimumTintColor") }
        if let maximumTrackTintColor { try encoder.encode(maximumTrackTintColor, forKey: "UIMaximumTintColor") }
        if let thumbTintColor { try encoder.encode(thumbTintColor, forKey: "UIThumbTintColor") }
        encoder.encode(.integer(0), forKey: "UIBehavioralStyle")
    }

    static let attributes = ContentAlignment.attributes + ["value", "minValue", "maxValue", "continuous", "minimumValueImage", "maximumValueImage"]
}

/// The content alignment attributes of the controls that take no other control attribute.
enum ContentAlignment {
    static let attributes = ["contentHorizontalAlignment", "contentVerticalAlignment", "enabled", "selected"]
}

extension DocumentCompiler {
    /// The kind of an activity indicator, segmented control, progress view, page control or slider.
    /// Segmented controls, page controls and sliders write their content hugging priorities even when
    /// they are 250, and document priorities of theirs are refused (`segmented`, `page`, `slider`).
    mutating func controlKind(_ element: XIBElement, view: NibView, frame: (x: Double, y: Double, width: Double, height: Double)) throws {
        switch element.name {
        case "activityIndicatorView":
            let activity = try activityContent(element)
            view.kind = .activity(activity)
            // A stopped indicator that does not hide when stopped writes no UIHidden (`activity-hidden-*`).
            if !activity.animating {
                view.flags.hidden = activity.hidesWhenStopped
            }
            // `noauto-activity`, `auto-activity-unmasked`; none of 437 of the survey and the holdout that hide or animate.
            if activity.hidesWhenStopped, !activity.animating, element.attributes["hidden"] != "YES", let id = element.attributes["id"] {
                warnings.append((id, "Hides When Stopped, but is neither Hidden nor Animating [9]"))
            }
        case "segmentedControl":
            let segmented = try segmentedContent(element)
            view.kind = .segmented(segmented)
            if !segmented.control.enabled {
                view.flags.alpha = 0.5
            }
            let selected = segmented.segments.indices.contains(segmented.selectedIndex) ? [segmented.segments[segmented.selectedIndex]] : []
            view.subviews = segmented.segments.filter { segment in !selected.contains { $0 === segment } } + selected
        case "progressView":
            let progress = try progressContent(element)
            view.kind = .progress(progress)
            view.frame?.height = progress.barStyle ? max(frame.height - 1, 3) : max(frame.height, 4)
        case "pageControl":
            view.kind = .page(try pageContent(element))
        case "slider":
            view.kind = .slider(try sliderContent(element))
        default:
            return
        }
        if ["segmentedControl", "pageControl", "slider"].contains(element.name) {
            guard element.attributes["horizontalHuggingPriority"] == nil, element.attributes["verticalHuggingPriority"] == nil else {
                throw unsupported("content hugging priorities of a \(element.name)")
            }
            view.flags.contentHugging = string("{250, 250}")
        }
    }

    /// The colors of a control's document, by key, refusing the keys it does not take.
    mutating func controlColors(_ element: XIBElement, keys: Set<String>) throws -> [String: NibColor] {
        var colors: [String: NibColor] = [:]
        for color in element.children(named: "color") where !["backgroundColor", "tintColor"].contains(color.attributes["key"]) {
            guard let key = color.attributes["key"], keys.contains(key) else {
                throw unsupported("<color key=\"\(color.attributes["key"] ?? "")\"> in <\(element.name)>")
            }
            colors[key] = try self.color(color)
        }
        return colors
    }

    /// A control's state and content alignments (`segmented-selected`, `page-*`, `slider-*`).
    func controlContent(_ element: XIBElement) throws -> ControlContent {
        var control = ControlContent()
        control.selected = try bool(element, "selected", default: false)
        control.enabled = try bool(element, "enabled", default: true)
        control.horizontalAlignment = try mapped(element.attributes["contentHorizontalAlignment"] ?? "center", ControlContent.horizontalAlignments,
                                                 "contentHorizontalAlignment")
        control.verticalAlignment = try mapped(element.attributes["contentVerticalAlignment"] ?? "center", ControlContent.verticalAlignments,
                                               "contentVerticalAlignment")
        return control
    }

    mutating func activityContent(_ element: XIBElement) throws -> ActivityContent {
        guard element.child("color", key: "tintColor") == nil else { throw unsupported("a tint color of an activity indicator") }
        guard let style = ActivityContent.styles[element.attributes["style"] ?? "medium"] else {
            throw unsupported("style=\"\(element.attributes["style"] ?? "")\" in <activityIndicatorView>")
        }
        let color = try controlColors(element, keys: ["color"])["color"]
        let tint = try color ?? (style.0 >= 100 ? self.color(XIBElement(name: "color", attributes: ["systemColor": "secondaryLabelColor"])) : nil)
        return ActivityContent(modernStyle: style.0, style: style.1, hidesWhenStopped: try bool(element, "hidesWhenStopped", default: false),
                               animating: try bool(element, "animating", default: false), color: color, tintColor: tint)
    }

    /// A `<segmentedControl>`, which writes an alpha of 0.5 when disabled, whatever its own
    /// (`segmented-control-disabled*`, the ladder `ladderlong112-b3-none`), and its segments, as
    /// subviews 0 wide and 32 high whatever the control's height,
    /// the selected one last, which all objects does not list (`segmented-*`, `segmented-height-*`); in
    /// a document of an `.lproj` folder their titles are localizable, keyed `<id>.segmentTitles[<index>]`
    /// (`segmented-lproj`).
    mutating func segmentedContent(_ element: XIBElement) throws -> SegmentedContent {
        try value(element, "segmentControlStyle", in: ["plain"])
        let containers = element.children(named: "segments")
        guard containers.count == 1, let container = containers.first else { throw unsupported("a segmented control without one <segments>") }
        try check(container, attributes: [], children: ["segment"])
        var segments: [NibView] = []
        for (index, segment) in container.children.enumerated() {
            try check(segment, attributes: ["title", "width", "enabled"], children: [])
            guard let title = segment.attributes["title"] else { throw unsupported("a segment without a title") }
            var flags = NibView.Flags()
            flags.opaque = false
            flags.userInteractionDisabled = !(try bool(segment, "enabled", default: true))
            let view = NibView(frame: (0, 0, 0, 32), autoresizingMask: 0, flags: flags, subviews: [], backgroundColor: nil, customClass: nil)
            view.kind = .segment(SegmentContent(title: text(title, id: element.attributes["id"], property: "segmentTitles[\(index)]"), width: try segment.attributes["width"].map { Float(try number($0, "width")) },
                                                position: index == 0 ? 0 : index == 1 ? 3 : 1))
            segments.append(view)
        }
        let momentary = try bool(element, "momentary", default: false)
        let selected = try element.attributes["selectedSegmentIndex"].map { try integer($0, "selectedSegmentIndex") } ?? -1
        var control = try controlContent(element)
        control.pointerInteractionEnabled = true
        return SegmentedContent(control: control, momentary: momentary, segments: segments,
                                proportionalWidths: try bool(element, "apportionsSegmentWidthsByContent", default: false), selectedIndex: selected,
                                selectedTintColor: try controlColors(element, keys: ["selectedSegmentTintColor"])["selectedSegmentTintColor"])
    }

    mutating func progressContent(_ element: XIBElement) throws -> ProgressContent {
        try value(element, "progressViewStyle", in: ["default", "bar"])
        let colors = try controlColors(element, keys: ["progressTintColor", "trackTintColor"])
        return ProgressContent(progress: Float(try number(element.attributes["progress"] ?? "0", "progress")),
                               barStyle: element.attributes["progressViewStyle"] == "bar",
                               progressTintColor: colors["progressTintColor"], trackTintColor: colors["trackTintColor"])
    }

    mutating func pageContent(_ element: XIBElement) throws -> PageContent {
        let colors = try controlColors(element, keys: ["pageIndicatorTintColor", "currentPageIndicatorTintColor"])
        return PageContent(control: try controlContent(element), numberOfPages: try integer(element.attributes["numberOfPages"] ?? "3", "numberOfPages"),
                           currentPage: try integer(element.attributes["currentPage"] ?? "0", "currentPage"),
                           hidesForSinglePage: try bool(element, "hidesForSinglePage", default: false),
                           defersCurrentPageDisplay: try bool(element, "defersCurrentPageDisplay", default: false),
                           currentPageIndicatorTintColor: colors["currentPageIndicatorTintColor"], pageIndicatorTintColor: colors["pageIndicatorTintColor"])
    }

    mutating func sliderContent(_ element: XIBElement) throws -> SliderContent {
        let colors = try controlColors(element, keys: ["minimumTrackTintColor", "maximumTrackTintColor", "thumbTintColor"])
        let attributes = element.attributes
        return SliderContent(control: try controlContent(element), value: Float(try number(attributes["value"] ?? "0", "value")),
                             minimumValue: Float(try number(attributes["minValue"] ?? "0", "minValue")),
                             maximumValue: Float(try number(attributes["maxValue"] ?? "1", "maxValue")),
                             continuous: try bool(element, "continuous", default: true),
                             minimumValueImage: try attributes["minimumValueImage"].map { try image($0, catalog: nil) },
                             maximumValueImage: try attributes["maximumValueImage"].map { try image($0, catalog: nil) },
                             minimumTrackTintColor: colors["minimumTrackTintColor"], maximumTrackTintColor: colors["maximumTrackTintColor"],
                             thumbTintColor: colors["thumbTintColor"])
    }
}
