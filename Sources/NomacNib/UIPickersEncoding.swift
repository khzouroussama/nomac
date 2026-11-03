import Foundation

extension DocumentCompiler {
    /// A `<datePicker>` (docs/formats/nib.md "Date pickers and picker views"; nib-experiments
    /// `date-picker-*`): date and time, IB's default, writes nothing after a view's keys; a count-down
    /// timer writes its mode 3, IB's duration of 60 seconds and, for `useCurrentDate="NO"`, that it
    /// does not use the current date. Other modes, intervals and dates are refused.
    mutating func datePicker(_ element: XIBElement, view: NibView) throws {
        try value(element, "contentHorizontalAlignment", in: ["center"])
        try value(element, "contentVerticalAlignment", in: ["center"])
        try value(element, "datePickerMode", in: ["dateAndTime", "countDownTimer"])
        try value(element, "minuteInterval", in: ["1"])
        let countDown = element.attributes["datePickerMode"] == "countDownTimer"
        view.kind = .datePicker(countDown: countDown, usesCurrentDate: try bool(element, "useCurrentDate", default: true))
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
