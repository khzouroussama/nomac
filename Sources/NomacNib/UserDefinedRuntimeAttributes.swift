import Foundation
import NomacCore

/// `UINibKeyValuePair`: a user-defined runtime attribute or a switch's frame, the object it is set
/// on, its value and its key path (docs/formats/nib.md "User-defined runtime attributes",
/// "Text fields, switches and actions"; nib-experiments `udra-*`, `sw-*`).
final class NibKeyValuePair: NibArchivable {
    let object: NibArchivable
    let value: NibArchivable?
    let keyPath: NibString

    init(object: NibArchivable, value: NibArchivable?, keyPath: NibString) {
        self.object = object
        self.value = value
        self.keyPath = keyPath
    }

    var className: String { "UINibKeyValuePair" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(object, forKey: "UIObject")
        try encoder.encode(value, forKey: "UIValue")
        try encoder.encode(keyPath, forKey: "UIKeyPath")
    }
}

/// `NSValue` of a point, size or rectangle: its special type (1, 2, 3) and the value as a string
/// (`udra-point*`, `udra-size`, `udra-rect`).
final class NibGeometryValue: NibArchivable {
    let special: Int
    let key: String
    let text: NibString

    init(special: Int, key: String, text: NibString) {
        self.special = special
        self.key = key
        self.text = text
    }

    var className: String { "NSValue" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.integer(special), forKey: "NS.special")
        try encoder.encode(text, forKey: key)
    }
}

/// `NSValue` of a range: special type 4, its length and location as numbers (`udra-range`).
final class NibRangeValue: NibArchivable {
    let length: NibNumber
    let location: NibNumber

    init(length: NibNumber, location: NibNumber) {
        self.length = length
        self.location = location
    }

    var className: String { "NSValue" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.integer(4), forKey: "NS.special")
        try encoder.encode(length, forKey: "NS.rangeval.length")
        try encoder.encode(location, forKey: "NS.rangeval.location")
    }
}

extension DocumentCompiler {
    /// An object's `<userDefinedRuntimeAttributes>`: numbers (integers and reals, booleans as the
    /// integers 1 and 0), strings (not localizable: `udra-lproj`), colors, whole sizes (`{0, 2}`) and
    /// images, as the values of key-value pairs.
    mutating func runtimeAttributes(of element: XIBElement, object: NibArchivable) throws {
        for container in element.children(named: "userDefinedRuntimeAttributes") {
            try check(container, attributes: [], children: ["userDefinedRuntimeAttribute"])
            for attribute in container.children {
                guard let keyPath = attribute.attributes["keyPath"] else { throw unsupported("a user-defined runtime attribute without a key path") }
                keyValuePairs.append(NibKeyValuePair(object: object, value: try runtimeValue(attribute), keyPath: string(keyPath)))
            }
        }
    }

    /// The nib's key-value pairs in the order of their objects' places in all objects plus one, as
    /// decimal strings compared byte by byte (`10` before `4`), those of one object in the document's
    /// order (`udra-order-*`, 153 nibs of the corpus and the experiments and 48 of the holdout unseen
    /// when the rule was found; the root and File's Owner `udra-order-root-*`, `udra-order-owner-*`;
    /// past 99 `udra-order-many-120`).
    mutating func takeKeyValuePairs(allObjects: [NibArchivable]) throws -> [NibArchivable] {
        defer { keyValuePairs = [] }
        let places = Dictionary(allObjects.enumerated().map { (ObjectIdentifier($0.element), $0.offset) }) { first, _ in first }
        let keyed = try keyValuePairs.enumerated().map { offset, pair in
            guard let place = places[ObjectIdentifier(pair.object)] else { throw unsupported("user-defined runtime attributes of an object outside the nib's objects") }
            return (key: Array(String(place + 1).utf8), offset: offset, pair: pair)
        }
        return keyed.sorted { left, right in
            left.key == right.key ? left.offset < right.offset : left.key.lexicographicallyPrecedes(right.key)
        }.map(\.pair)
    }

    /// A point's or rectangle's coordinate as Foundation writes it: whole numbers without a
    /// fraction, others where their shortest form is also `%.17g`'s (`udra-point`: 0.5); others
    /// are not observed.
    private func geometryText(_ element: XIBElement, _ name: String) throws -> String {
        let value = try number(element.attributes[name] ?? "0", name)
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        guard String(format: "%.17g", value) == "\(value)" else { throw unsupported("the runtime attribute coordinate \(value)") }
        return "\(value)"
    }

    private mutating func runtimeValue(_ attribute: XIBElement) throws -> NibArchivable? {
        switch attribute.attributes["type"] {
        case "number":
            try check(attribute, attributes: ["type", "keyPath"], children: ["integer", "real"])
            guard attribute.children.count == 1, let number = attribute.children.first, number.attributes["key"] == "value" else {
                throw unsupported("a number runtime attribute without one value")
            }
            try check(number, attributes: ["key", "value"], children: [])
            let text = number.attributes["value"] ?? ""
            return number.name == "integer" ? NibNumber(integer: try integer(text, "value")) : NibNumber(try self.number(text, "value"))
        case "boolean":
            try check(attribute, attributes: ["type", "keyPath", "value"], children: [])
            return NibNumber(integer: try bool(attribute, "value", default: false) ? 1 : 0)
        case "string":
            try check(attribute, attributes: ["type", "keyPath", "value"], children: [])
            return string(attribute.attributes["value"] ?? "")
        case "color":
            try check(attribute, attributes: ["type", "keyPath"], children: ["color"])
            guard let color = attribute.child("color", key: "value") else { throw unsupported("a color runtime attribute without a color") }
            return try self.color(color)
        case "size":
            try check(attribute, attributes: ["type", "keyPath"], children: ["size"])
            guard let size = attribute.child("size", key: "value") else { throw unsupported("a size runtime attribute without a size") }
            try check(size, attributes: ["key", "width", "height"], children: [])
            let values = try ["width", "height"].map { name in
                guard let value = Int(exactly: try number(size.attributes[name] ?? "0", name)) else { throw unsupported("a fractional size runtime attribute") }
                return value
            }
            return NibGeometryValue(special: 2, key: "NS.sizeval", text: string("{\(values[0]), \(values[1])}"))
        case "point":
            try check(attribute, attributes: ["type", "keyPath"], children: ["point"])
            guard let point = attribute.child("point", key: "value") else { throw unsupported("a point runtime attribute without a point") }
            try check(point, attributes: ["key", "x", "y"], children: [])
            let values = try ["x", "y"].map { try geometryText(point, $0) }
            return NibGeometryValue(special: 1, key: "NS.pointval", text: string("{\(values[0]), \(values[1])}"))
        case "rect":
            try check(attribute, attributes: ["type", "keyPath"], children: ["rect"])
            guard let rect = attribute.child("rect", key: "value") else { throw unsupported("a rect runtime attribute without a rect") }
            try check(rect, attributes: ["key", "x", "y", "width", "height"], children: [])
            let values = try ["x", "y", "width", "height"].map { try geometryText(rect, $0) }
            return NibGeometryValue(special: 3, key: "NS.rectval", text: string("{{\(values[0]), \(values[1])}, {\(values[2]), \(values[3])}}"))
        case "range":
            try check(attribute, attributes: ["type", "keyPath"], children: ["range"])
            guard let range = attribute.child("range", key: "value") else { throw unsupported("a range runtime attribute without a range") }
            try check(range, attributes: ["key", "location", "length"], children: [])
            guard try integer(range.attributes["location"] ?? "0", "location") != integer(range.attributes["length"] ?? "0", "length") else {
                throw unsupported("a range runtime attribute of equal location and length")
            }
            return NibRangeValue(length: NibNumber(integer: try integer(range.attributes["length"] ?? "0", "length")),
                                 location: NibNumber(integer: try integer(range.attributes["location"] ?? "0", "location")))
        case "nil":
            try check(attribute, attributes: ["type", "keyPath"], children: [])
            return nil
        case "localizedString":
            try check(attribute, attributes: ["type", "keyPath", "value"], children: [])
            guard !localizable else { throw unsupported("a localized string runtime attribute in a localized document") }
            return string(attribute.attributes["value"] ?? "")
        case "image":
            try check(attribute, attributes: ["type", "keyPath", "value", "catalog"], children: [])
            return try image(attribute.attributes["value"] ?? "", catalog: attribute.attributes["catalog"])
        case let other:
            throw unsupported("user-defined runtime attributes of type \(other ?? "none")")
        }
    }
}
