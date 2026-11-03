/// How each intent parameter type appears in generated Swift (intents-experiments `type-*`,
/// `response-*`, `property-*`; docs/formats/intents.md "Types"). A type intentbuilderc does not
/// know is a string.
struct IntentSwiftType: Sendable {
    /// The property's type without optionality, and that of its multiple values.
    var single: String
    var element: String
    /// Non-optional properties (`Double`).
    var isOptional = true
    /// The `INObjectCollection` element of dynamic options.
    var collectionElement: String
    /// The resolution result: a framework class, or the base of a class generated per
    /// parameter (`<Intent><Parameter>ResolutionResult`) with its unsupported reasons.
    var resolution: String
    var generatedResolutionBase: String?
    var unsupportedReasons: [String] = []
    /// The `@available` line before the property, if any.
    var availability: String?

    static let modern = "@available(iOS 13.0, macOS 10.16, watchOS 6.0, *)"
    static let numberReasons = ["negativeNumbersNotSupported", "greaterThanMaximumValue", "lessThanMinimumValue"]

    static func of(_ type: String, objectType: String?, enumType: String?) -> IntentSwiftType {
        if let enumType {
            return IntentSwiftType(single: enumType, element: "Int", isOptional: false, collectionElement: "Int",
                                   resolution: enumType + "ResolutionResult")
        }
        switch type {
        case "Integer":
            return IntentSwiftType(single: "NSNumber", element: "Int", collectionElement: "Int", resolution: "",
                                   generatedResolutionBase: "INIntegerResolutionResult", unsupportedReasons: numberReasons)
        case "Decimal":
            return IntentSwiftType(single: "NSNumber", element: "Double", collectionElement: "Double", resolution: "",
                                   generatedResolutionBase: "INDoubleResolutionResult", unsupportedReasons: numberReasons)
        case "Boolean":
            return IntentSwiftType(single: "NSNumber", element: "NSNumber", collectionElement: "NSNumber",
                                   resolution: "INBooleanResolutionResult", availability: modern)
        case "DateComponents":
            return IntentSwiftType(single: "DateComponents", element: "DateComponents", collectionElement: "NSDateComponents",
                                   resolution: "INDateComponentsResolutionResult", availability: modern)
        case "Date", "Location", "Data", "Image":
            let names = ["Date": ("Date", "Date"), "Location": ("CLLocation", "CLLocation"), "Data": ("Data", "Data"), "Image": ("INImage", "INImage")]
            let (name, collection) = names[type]!
            return IntentSwiftType(single: name, element: name, collectionElement: collection, resolution: "(null)")
        case "CurrencyAmount":
            return IntentSwiftType(single: "INCurrencyAmount", element: "INCurrencyAmount", collectionElement: "INCurrencyAmount", resolution: "",
                                   generatedResolutionBase: "INCurrencyAmountResolutionResult", unsupportedReasons: numberReasons,
                                   availability: "@available(iOS 12.0, macOS 12.0, watchOS 5.0, *)")
        case "Placemark":
            return IntentSwiftType(single: "CLPlacemark", element: "CLPlacemark", collectionElement: "CLPlacemark", resolution: "INPlacemarkResolutionResult")
        case "Person":
            return IntentSwiftType(single: "INPerson", element: "INPerson", collectionElement: "INPerson", resolution: "INPersonResolutionResult")
        case "PaymentMethod":
            return IntentSwiftType(single: "INPaymentMethod", element: "INPaymentMethod", collectionElement: "INPaymentMethod",
                                   resolution: "INPaymentMethodResolutionResult")
        case "URL":
            return IntentSwiftType(single: "URL", element: "URL", collectionElement: "NSURL", resolution: "INURLResolutionResult")
        case "File":
            return IntentSwiftType(single: "INFile", element: "INFile", collectionElement: "INFile", resolution: "INFileResolutionResult",
                                   availability: modern)
        case "Distance", "Mass", "Volume", "Temperature", "Speed", "Energy":
            let units = ["Distance": ("UnitLength", "INLengthResolutionResult", false), "Mass": ("UnitMass", "INMassResolutionResult", true),
                         "Volume": ("UnitVolume", "INVolumeResolutionResult", true), "Temperature": ("UnitTemperature", "INTemperatureResolutionResult", false),
                         "Speed": ("UnitSpeed", "INSpeedResolutionResult", true), "Energy": ("UnitEnergy", "INEnergyResolutionResult", true)]
            let (unit, base, isModern) = units[type]!
            return IntentSwiftType(single: "Measurement<\(unit)>", element: "Measurement<\(unit)>", collectionElement: "NSMeasurement", resolution: "",
                                   generatedResolutionBase: base, unsupportedReasons: ["negativeNumbersNotSupported"],
                                   availability: isModern ? modern : nil)
        case "Object":
            let name = objectType ?? "INObject"
            return IntentSwiftType(single: name, element: name, collectionElement: name, resolution: name + "ResolutionResult")
        case "Double":
            return IntentSwiftType(single: "Double", element: "Double", isOptional: false, collectionElement: "Double", resolution: "INDoubleResolutionResult")
        case "SpeakableString":
            return IntentSwiftType(single: "INSpeakableString", element: "INSpeakableString", collectionElement: "INSpeakableString",
                                   resolution: "INSpeakableStringResolutionResult")
        default:
            return IntentSwiftType(single: "String", element: "String", collectionElement: "NSString", resolution: "INStringResolutionResult")
        }
    }

    /// The property's declared type: `T?`, `[Element]?`, or without `?` when not optional.
    func property(multiple: Bool) -> String {
        let base = multiple ? "[\(element)]" : single
        return isOptional ? base + "?" : base
    }

    /// The type a default-value method returns.
    func defaultValue(multiple: Bool) -> String {
        multiple ? "[\(element)]?" : single + "?"
    }
}
