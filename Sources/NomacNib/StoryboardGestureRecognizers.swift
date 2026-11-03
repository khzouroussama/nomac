import Foundation
import NomacCore

/// A scene's gesture recognizer (docs/formats/nib.md "Gesture recognizers"; nib-experiments
/// `sb-gesture-*`): a top-level object of the controller's nib, which keeps it alive, that the view
/// nib loads as `UpstreamPlaceholder-1`, the controller then numbered 2.
struct SceneRecognizer {
    let recognizer: NibGestureRecognizer
    let id: String
    let placeholder = NibProxy(identifier: "UpstreamPlaceholder-1")
    /// Its actions to the controller, by selector.
    var actions: [NibString] = []

    func events(to controller: NibArchivable) -> [NibEventConnection] {
        actions.map { NibEventConnection(selector: $0, source: recognizer, destination: controller, eventMask: nil) }
    }

    /// The view nib's upstream placeholders to their objects: the recognizer, then the controller
    /// when the view nib refers to it (`sb-gesture-and-controller`), or the controller first
    /// when the view nib's connections reach it first (`sb-gesture-controller-collection`).
    func externalObjects(controller: NibArchivable?, controllerFirst: Bool) -> [(NibArchivable, NibArchivable)] {
        guard let controller else { return [(NibString("UpstreamPlaceholder-1"), recognizer)] }
        return controllerFirst ? [(NibString("UpstreamPlaceholder-1"), controller), (NibString("UpstreamPlaceholder-2"), recognizer)]
            : [(NibString("UpstreamPlaceholder-1"), recognizer), (NibString("UpstreamPlaceholder-2"), controller)]
    }
}

extension DocumentCompiler {
    /// The gesture recognizer among a scene's objects, attached to one view of the controller's,
    /// and its actions to the controller. Several recognizers in a scene are numbered by a rule not
    /// known yet (B-291); recognizers attached to no view or to several, segues and other
    /// connections of recognizers are refused.
    mutating func sceneRecognizer(_ objects: XIBElement, view: XIBElement, controller: XIBElement) throws -> SceneRecognizer? {
        let elements = objects.children.filter { NibGestureRecognizer.elements.contains($0.name) }
        guard let element = elements.first else { return nil }
        guard elements.count == 1 else { throw NomacError("nomac does not compile several gesture recognizers in a scene yet (BACKLOG B-291)", path: path) }
        guard let id = element.attributes["id"] else { throw unsupported("a gesture recognizer without an id") }
        var scene = SceneRecognizer(recognizer: try gestureRecognizer(element, connects: false), id: id)
        for container in element.children(named: "connections") {
            try check(container, attributes: [], children: ["action"])
            for action in container.children {
                try check(action, attributes: ["selector", "destination", "id"], children: [])
                guard let selector = action.attributes["selector"], action.attributes["destination"] == controller.attributes["id"] else {
                    throw unsupportedScene("an action of a gesture recognizer to another object than its controller")
                }
                scene.actions.append(string(selector))
            }
        }
        scene.actions.sort { Array($0.value.utf8).lexicographicallyPrecedes(Array($1.value.utf8)) }
        func attachments(_ element: XIBElement) -> Int {
            element.children(named: "connections").flatMap { $0.children(named: "outletCollection") }
                .filter { $0.attributes["property"] == "gestureRecognizers" && $0.attributes["destination"] == id }.count
                + element.children(named: "subviews").flatMap(\.children).map(attachments).reduce(0, +)
        }
        guard attachments(view) == 1 else { throw unsupportedScene("a gesture recognizer attached to no view, to several, or to other than a subview") }
        for container in controller.children(named: "connections") where container.children.contains(where: { $0.attributes["destination"] == id }) {
            throw unsupportedScene("a controller's connection to a gesture recognizer")
        }
        return scene
    }
}
