import Foundation

/// A `<keyboardLayoutGuide key="keyboard">` of a view: a `UIKeyboardLayoutGuide` listed among its
/// view's objects like the safe area's unarchived guide (nib-experiments `mx-keyboard-guide*`,
/// `mx-sb-keyboard-guide*`).
final class NibKeyboardGuidePlaceholder: NibArchivable {
    let identifier: NibString

    init(identifier: NibString) {
        self.identifier = identifier
    }

    var className: String { "UIKeyboardLayoutGuide" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(nil, forKey: "UILayoutGuideOwningView")
        try encoder.encode(identifier, forKey: "UILayoutGuideIdentifier")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideOwningViewIsLocked")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideShouldBeArchived")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideAllowsNegativeDimensions")
        encoder.encode(.boolean(false), forKey: "UIKeyboardLayoutGuideFollowsUndocked")
    }
}

/// The keyboard guide constraints name: owned by the view, which does not list it, named, not
/// archived and without system constraints (`mx-keyboard-guide-constraint`).
final class NibKeyboardLayoutGuide: NibArchivable {
    unowned let owningView: NibView
    let identifier: NibString

    init(owningView: NibView, identifier: NibString) {
        self.owningView = owningView
        self.identifier = identifier
    }

    var className: String { "UIKeyboardLayoutGuide" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(owningView, forKey: "UILayoutGuideOwningView")
        try encoder.encode(identifier, forKey: "UILayoutGuideIdentifier")
        encoder.encode(.boolean(true), forKey: "UILayoutGuideOwningViewIsLocked")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideShouldBeArchived")
        encoder.encode(.boolean(false), forKey: "UILayoutGuideAllowsNegativeDimensions")
        try encoder.encode(nil, forKey: "UILayoutGuideSystemConstraints")
        encoder.encode(.boolean(false), forKey: "UIKeyboardLayoutGuideFollowsUndocked")
    }
}

extension DocumentCompiler {
    /// A plain view's keyboard guide, which constraints find by id.
    mutating func keyboardGuide(_ element: XIBElement, view: NibView, id: String) throws {
        for guide in element.children(named: "keyboardLayoutGuide") {
            guard element.name == "view" else { throw unsupported("<keyboardLayoutGuide> in <\(element.name)>") }
            guard view.safeAreaPlaceholder == nil else { throw unsupported("<keyboardLayoutGuide> beside a safe area") }
            try check(guide, attributes: ["key", "id"], children: [])
            try value(guide, "key", in: ["keyboard"])
            guard let guideID = guide.attributes["id"], keyboardGuides[guideID] == nil else { throw unsupported("<keyboardLayoutGuide> without one id") }
            view.layoutGuidePlaceholders.append(NibKeyboardGuidePlaceholder(identifier: string("")))
            keyboardGuides[guideID] = id
        }
    }
}
