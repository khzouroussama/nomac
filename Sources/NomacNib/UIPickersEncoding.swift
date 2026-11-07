import Foundation

extension DocumentCompiler {
    /// A `<datePicker>` (docs/formats/nib.md "Date pickers and picker views"; nib-experiments
    /// `date-picker-*`): after a view's keys its alignment, style and mode, date and time, IB's default,
    /// writing none, and the interval when not 1 (0 without the attribute); a count-down timer writes IB's duration of 60 seconds
    /// and, for `useCurrentDate="NO"`, that it does not use the current date. A `wheels` one is 320 x 216
    /// whatever its frame, and a compact one centered writes trailing. Dates are refused.
    mutating func datePicker(_ element: XIBElement, view: NibView) throws {
        try value(element, "contentVerticalAlignment", in: ["center"])
        let style = try element.attributes["style"].map { try mapped($0, ["automatic": 0, "wheels": 1, "compact": 2, "inline": 3], "style") }
        var alignment = try mapped(element.attributes["contentHorizontalAlignment"] ?? "center", ["center": 0, "left": 1, "right": 2, "fill": 3, "leading": 4, "trailing": 5],
                                   "contentHorizontalAlignment")
        if alignment == 0, style == 2 { alignment = 5 }
        if style == 1, let frame = view.frame { view.frame = (frame.x, frame.y, 320, 216) }
        // 0 without the attribute (the survey's DatePickerTableViewCell).
        let minuteInterval = try integer(element.attributes["minuteInterval"] ?? "0", "minuteInterval")
        // A count-down timer's duration follows the interval, and its hugging its style (`date-picker-shape-count-down-*`).
        guard element.attributes["datePickerMode"] != "countDownTimer" || (style == nil && minuteInterval == 1) else {
            throw unsupported("a count-down date picker of a style or of another interval")
        }
        view.kind = .datePicker(DatePickerContent(
            alignment: alignment, style: style == 0 ? nil : style,
            mode: try mapped(element.attributes["datePickerMode"] ?? "dateAndTime", ["time": 0, "date": 1, "dateAndTime": 2, "countDownTimer": 3], "datePickerMode"),
            minuteInterval: minuteInterval,
            usesCurrentDate: try bool(element, "useCurrentDate", default: true)))
    }

    /// A `<pickerView>`: a view's keys with its content hugging priorities, then cells it allows
    /// selecting (`picker-view*`).
    mutating func pickerView(_ element: XIBElement, view: NibView) throws {
        guard element.attributes["horizontalHuggingPriority"] == nil, element.attributes["verticalHuggingPriority"] == nil else {
            throw unsupported("content hugging priorities of a picker view")
        }
        view.flags.contentHugging = string("{250, 250}")
        view.kind = .pickerView
    }
}
