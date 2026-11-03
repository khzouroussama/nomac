import Foundation
import NomacCore

/// `what`: the identification strings in a file, each the text after an `@(#)` marker up to a
/// `"`, `>`, newline, `\` or NUL, as macOS's `what` prints them (what(1)). Swift Build reads a
/// tool's version from `what -q <tool>`; nomac's launchers carry the strings of the tools they
/// stand for (``LinuxToolchain/whatIdentities``).
public enum WhatStrings {
    public static func strings(in data: Data) -> [String] {
        let bytes = [UInt8](data)
        let marker: [UInt8] = Array("@(#)".utf8)
        let terminators: Set<UInt8> = [0x22, 0x3E, 0x0A, 0x5C, 0x00]
        var found: [String] = []
        var index = 0
        while index + marker.count <= bytes.count {
            guard Array(bytes[index..<index + marker.count]) == marker else {
                index += 1
                continue
            }
            var end = index + marker.count
            while end < bytes.count, !terminators.contains(bytes[end]) { end += 1 }
            found.append(String(decoding: bytes[(index + marker.count)..<end], as: UTF8.self))
            index = end
        }
        return found
    }
}
