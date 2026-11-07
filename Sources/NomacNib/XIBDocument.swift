import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import NomacCore

/// An element of an Interface Builder document.
final class XIBElement {
    let name: String
    let attributes: [String: String]
    var children: [XIBElement] = []
    /// The text the element holds (`<string key="text">`).
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func children(named name: String) -> [XIBElement] {
        children.filter { $0.name == name }
    }

    /// The child `<name key="key">`.
    func child(_ name: String, key: String) -> XIBElement? {
        children.first { $0.name == name && $0.attributes["key"] == key }
    }
}

/// Reads an Interface Builder document's XML into elements.
enum XIBReader {
    static func read(_ data: Data, path: String) throws -> XIBElement {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw NomacError("nomac does not reproduce ibtool's messages for \((path as NSString).lastPathComponent), which is not a well-formed document (BACKLOG B-260)", path: path)
        }
        return root
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var root: XIBElement?
        var stack: [XIBElement] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            var attributes = attributes
            // Below the document, `propertyAccessControl` changes nothing (`cell-attr-access-*`, `view-access-*`).
            if !stack.isEmpty { attributes["propertyAccessControl"] = nil }
            let element = XIBElement(name: elementName, attributes: attributes)
            if let parent = stack.last {
                parent.children.append(element)
            } else {
                root = element
            }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
            // IB's empty `<animations/>` changes nothing, wherever it is (`*-animations`, `sb-animations-view`).
            if elementName == "animations", let parent = stack.last, parent.children.last?.children.isEmpty == true {
                parent.children.removeLast()
            }
        }
    }
}
