import Foundation

/// A property list value, written by nomac's own serializers so that their bytes are the same on
/// every platform (docs/formats/property-lists.md).
public indirect enum PropertyListValue: Hashable, Sendable {
    case string(String)
    case integer(Int)
    case real(Double)
    case boolean(Bool)
    /// Seconds since 2001-01-01 00:00:00 UTC.
    case date(Double)
    case data([UInt8])
    case array([PropertyListValue])
    case dictionary([String: PropertyListValue])
}
