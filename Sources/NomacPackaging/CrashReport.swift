import Foundation
import NomacCore

/// A crash report as iOS writes it (`.ips`, `bug_type` 309): a JSON header line, then the JSON
/// report (docs/formats/crash-report.md). The device symbolicates its own libraries' frames
/// (`symbol`, `symbolLocation`); the app's frames keep only `imageIndex` and `imageOffset` (a
/// Mac's crash reporter, for a simulator, names them too). ``render(symbolicators:)`` gives
/// every frame of an image whose UUID a dSYM has `atos -i`'s lines, with sources and inlined
/// calls, and the others the report's name.
public struct CrashReport {
    public let header: [String: Any]
    public let body: [String: Any]

    public init(bytes: [UInt8], path: String) throws {
        guard let newline = bytes.firstIndex(of: 0x0a),
              let header = try? JSONSerialization.jsonObject(with: Data(bytes[..<newline])) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(bytes[(newline + 1)...])) as? [String: Any] else {
            throw NomacError("not a crash report (.ips): a JSON header line, then the JSON report", path: path)
        }
        self.header = header
        self.body = body
    }

    struct Image {
        let name: String
        let uuid: String
    }

    var images: [Image] {
        (body["usedImages"] as? [[String: Any]] ?? []).map { Image(name: $0["name"] as? String ?? "???", uuid: ($0["uuid"] as? String ?? "").uppercased()) }
    }

    /// The UUIDs of the images the report's frames are in, uppercase.
    public var imageUUIDs: Set<String> { Set(images.map(\.uuid)) }

    /// The report as text: the process, the exception and its reason, the last exception
    /// backtrace, then each thread, the crashed one marked; one line per frame, `<index>
    /// <image> <symbol> + <offset>`, or for an image with a dSYM `atos -i`'s lines.
    public func render(symbolicators: [String: Symbolicator]) -> String {
        var lines: [String] = []
        let process = body["procName"] as? String ?? header["app_name"] as? String ?? "?"
        lines.append("Process: \(process) [\(body["pid"].map { "\($0)" } ?? "?")]")
        if let identifier = header["bundleID"] as? String { lines.append("Identifier: \(identifier)") }
        if let version = header["os_version"] as? String { lines.append("OS Version: \(version)") }
        if let exception = body["exception"] as? [String: Any] {
            lines.append("Exception: \(exception["type"] as? String ?? "?")" + ((exception["signal"] as? String).map { " (\($0))" } ?? ""))
        }
        if let termination = body["termination"] as? [String: Any] {
            lines.append("Termination: \(termination["namespace"] as? String ?? "?") \(termination["code"].map { "\($0)" } ?? "")"
                + ((termination["indicator"] as? String).map { ", \($0)" } ?? ""))
        }
        if let reasons = (body["asi"] as? [String: [String]])?.sorted(by: { $0.key < $1.key }) {
            for (library, messages) in reasons { lines += messages.map { "Application Specific Information (\(library)): \($0)" } }
        }
        if let backtrace = body["lastExceptionBacktrace"] as? [[String: Any]] {
            lines += ["", "Last Exception Backtrace:"] + frames(backtrace, symbolicators: symbolicators)
        }
        let crashed = body["faultingThread"] as? Int
        for (index, thread) in (body["threads"] as? [[String: Any]] ?? []).enumerated() {
            let title = "Thread \(index)" + (index == crashed ? " Crashed" : "")
                + ((thread["queue"] as? String).map { " (\($0))" } ?? (thread["name"] as? String).map { " (\($0))" } ?? "")
            lines += ["", title + ":"] + frames(thread["frames"] as? [[String: Any]] ?? [], symbolicators: symbolicators)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func frames(_ frames: [[String: Any]], symbolicators: [String: Symbolicator]) -> [String] {
        let images = self.images
        var lines: [String] = []
        for (index, frame) in frames.enumerated() {
            let imageIndex = frame["imageIndex"] as? Int ?? -1
            let image = images.indices.contains(imageIndex) ? images[imageIndex] : Image(name: "???", uuid: "")
            let offset = (frame["imageOffset"] as? NSNumber)?.uint64Value ?? 0
            let prefix = "\(index)".padding(toLength: 4, withPad: " ", startingAt: 0) + image.name.padding(toLength: 30, withPad: " ", startingAt: 0) + " "
            if let symbolicator = symbolicators[image.uuid], case let found = symbolicator.frames(offset: offset), !found.isEmpty {
                lines += found.enumerated().map { ($0.offset == 0 ? prefix : String(repeating: " ", count: prefix.count)) + $0.element.formatted(image: image.name) }
            } else if let symbol = frame["symbol"] as? String {
                lines.append(prefix + symbol + " + \((frame["symbolLocation"] as? NSNumber)?.uint64Value ?? 0)")
            } else {
                lines.append(prefix + String(format: "0x%llx", offset))
            }
        }
        return lines
    }
}
