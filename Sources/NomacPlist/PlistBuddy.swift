import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import NomacCore

/// macOS's `/usr/libexec/PlistBuddy -c <command> … <file>` for the commands build scripts run
/// (`.github/scripts/plistbuddy_experiments.py`, script_phase_survey.py): `Print`, `Add`, `Set`
/// and `Delete`, the command word in any case, entries as `:`-separated keys and array indexes
/// (the leading `:` optional), values the rest of the command with one pair of quotes removed.
/// A command that fails prints PlistBuddy's message and the next one still runs; the exit status
/// is 1 when one failed. The file is written after an `Add`, `Set` or `Delete`, even one that
/// failed, as XML with sorted keys, whatever it was read as; `Print` alone leaves it. `Print` lists a dictionary's keys in the order a Foundation
/// dictionary read from the file iterates them.
public struct PlistBuddy {
    indirect enum Node {
        case value(PropertyListValue)
        case array([Node])
        case dictionary([(key: String, node: Node)])
    }

    public struct Outcome {
        public var standardOutput = ""
        public var standardError = ""
        public var failed = false
    }

    var root: Node
    let path: String
    var changed = false
    var outcome = Outcome()

    /// Reads `path`, or starts an empty dictionary when there is no file, as PlistBuddy does.
    public init(path: String) throws {
        self.path = path
        guard let data = FileManager.default.contents(atPath: path) else {
            root = .dictionary([])
            outcome.standardOutput += "File Doesn't Exist, Will Create: \(path)\n"
            return
        }
        let bytes = [UInt8](data)
        if bytes.starts(with: Array("bplist00".utf8)) {
            let (objects, top) = try BinaryPropertyList.objects(from: bytes, path: path)
            root = try Self.node(objects, top, path: path)
        } else {
            root = try XMLReader.read(data, path: path)
        }
    }

    /// Runs `commands`, then writes the file if one of them was `Add`, `Set` or `Delete`.
    public mutating func run(_ commands: [String]) throws -> Outcome {
        for command in commands {
            run(command)
        }
        if changed {
            try FileSystem.write(XMLPropertyList.data(Self.value(root)), to: path)
        }
        return outcome
    }

    mutating func run(_ command: String) {
        var words = Words(command)
        guard let verb = words.next() else { return }
        switch verb.lowercased() {
        case "print":
            let entry = words.next() ?? ""
            guard let node = Self.lookup(root, Self.components(entry)) else { return fail("Print: Entry, \"\(entry)\", Does Not Exist") }
            outcome.standardOutput += Self.printed(node, indent: 0) + "\n"
        case "add":
            changed = true
            guard let entry = words.next(), let type = words.next() else { return fail("Add: Invalid Arguments") }
            let text = words.rest()
            guard let new = makeNode(type: type, text: text) else { return }
            var components = Self.components(entry)
            guard let last = components.popLast() else { return fail("Add: Entry, \"\(entry)\", Does Not Exist") }
            if Self.lookup(root, components + [last]) != nil { return fail("Add: \"\(entry)\" Entry Already Exists") }
            guard Self.update(&root, components[...], { parent in Self.adding(new, at: last, to: &parent) }) else {
                return fail("Add: Entry, \"\(entry)\", Does Not Exist")
            }
        case "set":
            changed = true
            guard let entry = words.next() else { return fail("Set: Invalid Arguments") }
            let text = words.rest()
            let components = Self.components(entry)
            guard let existing = Self.lookup(root, components) else { return fail("Set: Entry, \"\(entry)\", Does Not Exist") }
            guard case .value(let old) = existing else { return fail("Set: Cannot Perform Set On Containers") }
            guard let value = Self.parse(text, as: old) else { return }
            _ = Self.update(&root, components[...]) { node in node = .value(value); return true }
        case "delete":
            changed = true
            let entry = words.next() ?? ""
            var components = Self.components(entry)
            guard let last = components.popLast(), Self.lookup(root, components + [last]) != nil else {
                return fail("Delete: Entry, \"\(entry)\", Does Not Exist")
            }
            _ = Self.update(&root, components[...]) { parent in Self.removing(last, from: &parent) }
        default:
            fail("nomac PlistBuddy does not implement the \(verb) command (only Print, Add, Set and Delete)")
        }
    }

    mutating func fail(_ message: String) {
        outcome.standardError += message + "\n"
        outcome.failed = true
    }

    mutating func makeNode(type: String, text: String) -> Node? {
        switch type.lowercased() {
        case "string": return .value(.string(text))
        case "array": return .array([])
        case "dict": return .dictionary([])
        case "bool": return .value(.boolean(Self.boolean(text)))
        case "integer": return .value(.integer(Self.integer(text)))
        case "real": return .value(.real(Double(text.trimmingCharacters(in: .whitespaces)) ?? 0))
        case "data": return .value(.data(Array(text.utf8)))
        case "date":
            guard let date = Self.dateFormatter.date(from: text) else {
                outcome.standardOutput += "Unrecognized Date Format\n"
                return nil
            }
            return .value(.date(date.timeIntervalSinceReferenceDate))
        default:
            fail("Unrecognized Type: \(type)")
            return nil
        }
    }

    // MARK: Entries

    static func components(_ entry: String) -> [String] {
        let trimmed = entry.hasPrefix(":") ? String(entry.dropFirst()) : entry
        return trimmed.isEmpty ? [] : trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    }

    static func lookup(_ node: Node, _ components: [String]) -> Node? {
        guard let first = components.first else { return node }
        switch node {
        case .dictionary(let entries):
            return entries.first { $0.key == first }.flatMap { lookup($0.node, Array(components.dropFirst())) }
        case .array(let items):
            guard let index = Int(first), items.indices.contains(index) else { return nil }
            return lookup(items[index], Array(components.dropFirst()))
        case .value:
            return nil
        }
    }

    /// Applies `change` to the node at `components`; false when there is none.
    static func update(_ node: inout Node, _ components: ArraySlice<String>, _ change: (inout Node) -> Bool) -> Bool {
        guard let first = components.first else { return change(&node) }
        switch node {
        case .dictionary(var entries):
            guard let index = entries.firstIndex(where: { $0.key == first }) else { return false }
            let done = update(&entries[index].node, components.dropFirst(), change)
            node = .dictionary(entries)
            return done
        case .array(var items):
            guard let index = Int(first), items.indices.contains(index) else { return false }
            let done = update(&items[index], components.dropFirst(), change)
            node = .array(items)
            return done
        case .value:
            return false
        }
    }

    static func adding(_ new: Node, at key: String, to parent: inout Node) -> Bool {
        switch parent {
        case .dictionary(var entries):
            entries.append((key, new))
            parent = .dictionary(entries)
            return true
        case .array(var items):
            guard let index = Int(key), index >= 0, index <= items.count else { return false }
            items.insert(new, at: index)
            parent = .array(items)
            return true
        case .value:
            return false
        }
    }

    static func removing(_ key: String, from parent: inout Node) -> Bool {
        switch parent {
        case .dictionary(var entries):
            entries.removeAll { $0.key == key }
            parent = .dictionary(entries)
            return true
        case .array(var items):
            guard let index = Int(key), items.indices.contains(index) else { return false }
            items.remove(at: index)
            parent = .array(items)
            return true
        case .value:
            return false
        }
    }

    // MARK: Values

    static func boolean(_ text: String) -> Bool {
        let word = text.trimmingCharacters(in: .whitespaces).lowercased()
        return word == "true" || word == "yes" || (Int(word).map { $0 != 0 } ?? false)
    }

    static func integer(_ text: String) -> Int {
        let word = text.trimmingCharacters(in: .whitespaces)
        let digits = word.prefix { $0.isNumber || $0 == "-" || $0 == "+" }
        return Int(digits) ?? 0
    }

    /// `text` as a value of `old`'s type, as `Set` keeps an entry's type.
    static func parse(_ text: String, as old: PropertyListValue) -> PropertyListValue? {
        switch old {
        case .string: return .string(text)
        case .boolean: return .boolean(boolean(text))
        case .integer: return .integer(integer(text))
        case .real: return .real(Double(text.trimmingCharacters(in: .whitespaces)) ?? 0)
        case .data: return .data(Array(text.utf8))
        case .date: return dateFormatter.date(from: text).map { .date($0.timeIntervalSinceReferenceDate) }
        case .array, .dictionary: return nil
        }
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss zzz yyyy"
        return formatter
    }()

    /// A date as PlistBuddy prints it: in the local time zone, named as the system names it.
    static func printedDate(_ seconds: Double) -> String {
        var time = time_t(Date(timeIntervalSinceReferenceDate: seconds).timeIntervalSince1970)
        var parts = tm()
        localtime_r(&time, &parts)
        var buffer = [Int8](repeating: 0, count: 64)
        let count = strftime(&buffer, buffer.count, "%a %b %d %H:%M:%S %Z %Y", &parts)
        return String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func printed(_ node: Node, indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        switch node {
        case .value(let value):
            switch value {
            case .string(let text): return text
            case .boolean(let flag): return flag ? "true" : "false"
            case .integer(let number): return String(number)
            case .real(let number): return String(format: "%f", number)
            case .date(let seconds): return printedDate(seconds)
            case .data(let bytes): return String(decoding: bytes, as: UTF8.self)
            case .array, .dictionary: return ""
            }
        case .array(let items):
            return "Array {\n" + items.map { pad + "    " + printed($0, indent: indent + 4) + "\n" }.joined() + pad + "}"
        case .dictionary(let entries):
            let order = (try? FoundationHashTable.inserting(entries.map(\.key)).keys) ?? entries.map(\.key)
            let byKey = Dictionary(entries.map { ($0.key, $0.node) }, uniquingKeysWith: { first, _ in first })
            return "Dict {\n" + order.map { pad + "    " + $0 + " = " + printed(byKey[$0]!, indent: indent + 4) + "\n" }.joined() + pad + "}"
        }
    }

    static func value(_ node: Node) -> PropertyListValue {
        switch node {
        case .value(let value): return value
        case .array(let items): return .array(items.map(value))
        case .dictionary(let entries): return .dictionary(Dictionary(entries.map { ($0.key, value($0.node)) }, uniquingKeysWith: { _, last in last }))
        }
    }

    static func node(_ objects: [BinaryPropertyList.Object], _ index: Int, path: String) throws -> Node {
        switch objects[index] {
        case .boolean(let flag): return .value(.boolean(flag))
        case .integer(let number): return .value(.integer(number))
        case .real(let number): return .value(.real(number))
        case .float(let number): return .value(.real(Double(number)))
        case .date(let seconds): return .value(.date(seconds))
        case .data(let bytes): return .value(.data(bytes))
        case .string(let text): return .value(.string(text))
        case .array(let items): return .array(try items.map { try node(objects, $0, path: path) })
        case .dictionary(let keys, let values):
            return .dictionary(try zip(keys, values).map { key, value in
                guard case .string(let name) = objects[key] else { throw NomacError("a dictionary key is not a string", path: path) }
                return (name, try node(objects, value, path: path))
            })
        default:
            throw NomacError("the property list holds an object PlistBuddy's commands do not edit", path: path)
        }
    }

    /// A command's words: the command, entry and type, each possibly quoted, then the rest.
    struct Words {
        var text: Substring

        init(_ text: String) { self.text = Substring(text) }

        mutating func next() -> String? {
            text = text.drop { $0 == " " || $0 == "\t" }
            guard let first = text.first else { return nil }
            if first == "'" || first == "\"", let end = text.dropFirst().firstIndex(of: first) {
                let word = String(text[text.index(after: text.startIndex)..<end])
                text = text[text.index(after: end)...]
                return word
            }
            let end = text.firstIndex { $0 == " " || $0 == "\t" } ?? text.endIndex
            defer { text = text[end...] }
            return String(text[..<end])
        }

        /// The rest of the command, without the space before it and one pair of quotes around it.
        mutating func rest() -> String {
            let rest = text.drop { $0 == " " || $0 == "\t" }
            if let first = rest.first, first == "'" || first == "\"", rest.count >= 2, rest.last == first {
                return String(rest.dropFirst().dropLast())
            }
            return String(rest)
        }
    }

    /// An XML property list as a tree that keeps each dictionary's keys in file order.
    final class XMLReader: NSObject, XMLParserDelegate {
        private var stack: [(element: String, children: [Node], keys: [String])] = [("", [], [])]
        private var text = ""
        private var failure: String?

        static func read(_ data: Data, path: String) throws -> Node {
            let reader = XMLReader()
            let parser = XMLParser(data: data)
            parser.delegate = reader
            guard parser.parse(), reader.failure == nil, let root = reader.stack.first?.children.first else {
                throw NomacError("cannot read the property list: \(reader.failure ?? parser.parserError.map { "\($0)" } ?? "no value")", path: path)
            }
            return root
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            if elementName == "dict" || elementName == "array" { stack.append((elementName, [], [])) }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let node: Node
            switch elementName {
            case "plist": return
            case "key":
                stack[stack.count - 1].keys.append(text)
                return
            case "dict":
                let level = stack.removeLast()
                node = .dictionary(Array(zip(level.keys, level.children)).map { (key: $0.0, node: $0.1) })
            case "array": node = .array(stack.removeLast().children)
            case "string": node = .value(.string(text))
            case "integer": node = .value(.integer(Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
            case "real": node = .value(.real(Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
            case "true": node = .value(.boolean(true))
            case "false": node = .value(.boolean(false))
            case "data": node = .value(.data(Array(Data(base64Encoded: text.filter { !$0.isWhitespace }) ?? Data())))
            case "date":
                guard let date = ISO8601DateFormatter().date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    failure = "a date is not in ISO 8601 form"
                    return
                }
                node = .value(.date(date.timeIntervalSinceReferenceDate))
            default:
                failure = "unknown element <\(elementName)>"
                return
            }
            stack[stack.count - 1].children.append(node)
            text = ""
        }
    }
}
