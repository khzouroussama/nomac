import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// An XML element with its attributes and child elements, as schemes and workspace contents
/// are written; text content is not kept.
struct XMLTree {
    var name: String
    var attributes: [String: String]
    var children: [XMLTree]

    /// The document's root element, or nil when the data is not well-formed XML.
    static func parse(_ data: Data) -> XMLTree? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else { return nil }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [XMLTree] = []
        var root: XMLTree?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            stack.append(XMLTree(name: elementName, attributes: attributes, children: []))
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            guard let element = stack.popLast() else { return }
            if stack.isEmpty {
                root = element
            } else {
                stack[stack.count - 1].children.append(element)
            }
        }
    }
}
