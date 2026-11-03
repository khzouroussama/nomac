/// The hash `NSString` reports for a string on a Mac: CoreFoundation's string hash over UTF-16
/// code units, as its open-source implementation (`__CFStrHashCharacters`) computes it, with
/// 64-bit arithmetic except for each group of four units, whose weighted sum wraps at 32 bits
/// (observed on macOS 27.0.1: 405 strings of accented, Greek, CJK and combining characters; with
/// 64 bits, every group starting with a unit above U+00FC differs). Strings longer than 96 units
/// are hashed by their first, middle and last 32 units. Xcode places synchronized folders'
/// members in build phases with it (docs/formats/pif.md "Order in a phase").
public enum FoundationStringHash {
    public static func hash(_ string: String) -> UInt64 {
        let units = Array(string.utf16)
        let length = units.count
        var result = UInt64(length)
        func four(at index: Int) {
            let group = UInt32(units[index]) &* 16_974_593 &+ UInt32(units[index + 1]) &* 66_049
                &+ UInt32(units[index + 2]) &* 257 &+ UInt32(units[index + 3])
            result = result &* 67_503_105 &+ UInt64(group)
        }
        if length <= 96 {
            var index = 0
            while index + 4 <= length {
                four(at: index)
                index += 4
            }
            while index < length {
                result = result &* 257 &+ UInt64(units[index])
                index += 1
            }
        } else {
            for start in [0, length / 2 - 16, length - 32] {
                for index in stride(from: start, to: start + 32, by: 4) { four(at: index) }
            }
        }
        return result &+ (result << UInt64(length & 31))
    }
}
