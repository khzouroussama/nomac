import Foundation
import NomacCore

extension LoaderScan {
    /// A setting's name and the kinds of its conditions: `KEY[sdk=iphoneos*][arch=arm64]` is
    /// `KEY`, `[sdk, arch]`.
    static func parseSettingKey(_ key: String) -> (name: String, conditions: [String])? {
        guard let bracket = key.firstIndex(of: "[") else { return (key, []) }
        var conditions: [String] = []
        var rest = key[bracket...]
        while rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            let condition = rest[rest.index(after: rest.startIndex)..<close]
            conditions.append(String(condition.split(separator: "=", maxSplits: 1).first ?? ""))
            rest = rest[rest.index(after: close)...]
        }
        return rest.isEmpty ? (String(key[..<bracket]), conditions) : nil
    }

    /// One assignment of a build setting, in a project file's configuration or an xcconfig.
    private func scanAssignment(key: String, value: String, isList: Bool, file: String, object: String, inXCConfig: Bool) -> (name: String, conditional: Bool)? {
        guard let (name, conditions) = Self.parseSettingKey(key) else {
            use("settings:key=unparsed", file, object)
            return nil
        }
        if isList { use("settings:value=list", file, object) }
        for condition in Set(conditions).sorted() { use("settings:condition=\(condition)", file, object) }
        if conditions.count > 1 { use("settings:conditions=several", file, object) }
        // Settings whose differences no other feature names (docs/formats/show-build-settings.md; B-089).
        if name == "SYMROOT", opensProject { use("settings:SYMROOT", file, object) }
        if name == "SDKROOT", value.hasSuffix("simulator") { use("settings:SDKROOT=simulator", file, object) }
        if name == "SDKROOT", !conditions.isEmpty {
            use("settings:SDKROOT=condition", file, object)
            if conditions.contains(where: { !["sdk", "config", "arch"].contains($0) }) { use("settings:SDKROOT=condition-other", file, object) }
        }
        if Self.readSettings.contains(name) {
            if inXCConfig { use("settings:\(name)=xcconfig", file, object) }
            if !conditions.isEmpty { use("settings:\(name)=condition", file, object) }
            if value.contains("$") { use("settings:\(name)=macro", file, object) }
        }
        return (name, !conditions.isEmpty)
    }

    func scanBuildSettings(_ settings: [String: Any], file: String, object: String, level: String) {
        var plain: Set<String> = []
        var conditional: Set<String> = []
        for (key, value) in settings.sorted(by: { $0.key < $1.key }) {
            let list = value as? [String]
            guard let assignment = scanAssignment(key: key, value: list?.joined(separator: " ") ?? value as? String ?? "", isList: list != nil,
                                                  file: file, object: object, inXCConfig: false) else { continue }
            if assignment.conditional { conditional.insert(assignment.name) } else { plain.insert(assignment.name) }
        }
        for name in Self.readSettings where plain.contains(name) && conditional.contains(name) {
            use("settings:\(name)=condition-and-plain", file, object)
        }
    }

    /// What one xcconfig file assigns and includes, read once however many configurations use it.
    struct XCConfigSummary {
        var includes: [String] = []
        var plain: Set<String> = []
        var conditional: Set<String> = []
    }

    /// Scans a configuration's base xcconfig and what it includes. Within that level (docs/formats/pif.md
    /// "Target object"), a setting nomac reads that is assigned both with and without a condition
    /// is BACKLOG B-026's shape.
    func scanXCConfig(_ path: String, from file: String, object: String, level: String) {
        let path = (path as NSString).standardizingPath
        guard FileSystem.isFile(path) else {
            use("xcconfig:file=missing", file, object)
            return
        }
        readXCConfig(path)
        guard path == level, visitedLevels.insert(level).inserted else { return }
        var plain: Set<String> = []
        var conditional: Set<String> = []
        var seen: Set<String> = []
        var pending = [path]
        while let next = pending.popLast() {
            guard seen.insert(next).inserted, let summary = xcconfigSummaries[next] else { continue }
            plain.formUnion(summary.plain)
            conditional.formUnion(summary.conditional)
            pending += summary.includes
        }
        for name in Self.readSettings where plain.contains(name) && conditional.contains(name) {
            use("settings:\(name)=condition-and-plain-in-xcconfig", path, "xcconfig and its includes")
        }
    }

    /// The `=` of an assignment, after the key's conditions: `KEY[sdk=iphoneos*] = value`.
    static func assignmentEquals(_ line: String) -> String.Index? {
        var depth = 0
        for index in line.indices {
            switch line[index] {
            case "[": depth += 1
            case "]": depth -= 1
            case "=" where depth == 0: return index
            default: break
            }
        }
        return nil
    }

    private func readXCConfig(_ path: String) {
        guard visitedXCConfigs.insert(path).inserted else { return }
        use("xcconfig:file", path, (path as NSString).lastPathComponent)
        guard let data = FileSystem.contents(atPath: path) else {
            use("xcconfig:unreadable", path, (path as NSString).lastPathComponent)
            return
        }
        var summary = XCConfigSummary()
        let directory = (path as NSString).deletingLastPathComponent
        let lines = String(decoding: data, as: UTF8.self).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, rawLine) in lines.enumerated() {
            let object = "line \(index + 1)"
            var line = String(rawLine)
            if let comment = line.range(of: "//") { line = String(line[..<comment.lowerBound]) }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                let directive = line.prefix { !$0.isWhitespace && $0 != "\"" && $0 != "<" }
                guard directive == "#include" || directive == "#include?" else {
                    use("xcconfig:directive=\(directive.dropFirst())", path, object)
                    continue
                }
                let feature = directive == "#include" ? "xcconfig:include" : "xcconfig:include-optional"
                use(feature, path, object)
                guard let open = line.firstIndex(of: "\""), let close = line.lastIndex(of: "\""), open < close else {
                    use("\(feature)=not-quoted", path, object)
                    continue
                }
                let included = String(line[line.index(after: open)..<close])
                let resolved = ((included.hasPrefix("/") ? included : directory + "/" + included) as NSString).standardizingPath
                guard FileSystem.isFile(resolved) else {
                    use("\(feature)=missing", path, object)
                    continue
                }
                if Self.spelledOtherwiseOnDisk(resolved) {
                    use("\(feature)=spelled-otherwise-on-disk", path, object)
                }
                summary.includes.append(resolved)
                readXCConfig(resolved)
                continue
            }
            guard let equals = Self.assignmentEquals(line) else {
                use("xcconfig:line=unparsed", path, object)
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard let first = key.unicodeScalars.first, CharacterSet.letters.contains(first) || first == "_",
                  key.prefix(while: { $0 != "[" }).allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
                use("xcconfig:line=unparsed", path, object)
                continue
            }
            if value.hasSuffix(";") {
                use("xcconfig:value=semicolon", path, object)
                value.removeLast()
            }
            guard let assignment = scanAssignment(key: key, value: value, isList: false, file: path, object: object, inXCConfig: true) else { continue }
            if assignment.conditional { summary.conditional.insert(assignment.name) } else { summary.plain.insert(assignment.name) }
        }
        xcconfigSummaries[path] = summary
    }
}
