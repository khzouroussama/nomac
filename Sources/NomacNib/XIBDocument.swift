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
        removeCanvasElements(root)
        return root
    }

    /// What only Interface Builder's canvas reads, with the values observed: `<animations/>` of
    /// Xcode 6 to 8 on any view (`animations-*`, `sb-animations-*`), and simulated metrics of the
    /// status bar, orientation, screen and bars on views and controllers, which change no nib, with a
    /// device or without, at 27.0 and below 17 (`old-*`, `old-no-device-*`, `sb-old-*`, round 120;
    /// bars `sb-sim-*`). Other values stay in the document, for its elements to refuse.
    private static let canvasElements: [String: [String: Set<String>]] = [
        "animations": [:],
        "simulatedStatusBarMetrics": ["key": ["statusBar", "simulatedStatusBarMetrics"], "statusBarStyle": ["lightContent", "blackOpaque", "blackTranslucent"]],
        "simulatedOrientationMetrics": ["key": ["orientation", "simulatedOrientationMetrics"], "orientation": ["landscapeRight"]],
        "simulatedScreenMetrics": ["key": ["destination", "simulatedDestinationMetrics"],
                                   "type": ["retina4", "retina47", "retina55", "iPad", "iPadPro", "retina3_5.fullscreen", "retina4_0.fullscreen", "retina4_7.fullscreen", "retina5_5.fullscreen"]],
        "simulatedNavigationBarMetrics": ["key": ["simulatedTopBarMetrics"], "prompted": ["NO"], "translucent": ["NO"], "barStyle": ["black", "blackOpaque"]],
        "simulatedTabBarMetrics": ["key": ["simulatedBottomBarMetrics"], "translucent": ["NO"], "barStyle": ["black"]],
        "simulatedToolbarMetrics": ["key": ["simulatedBottomBarMetrics"], "translucent": ["NO"], "barStyle": ["black", "blackOpaque"]],
    ]

    private static func removeCanvasElements(_ element: XIBElement) {
        element.children.removeAll { child in
            guard child.children.isEmpty, let allowed = canvasElements[child.name] else { return false }
            return child.attributes.allSatisfy { allowed[$0.key]?.contains($0.value) == true }
        }
        element.children.forEach(removeCanvasElements)
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
