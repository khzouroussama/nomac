import Foundation

/// How actool turns asset and namespace names into Swift and Objective-C symbols
/// (docs/formats/asset-catalog.md, "Asset symbols"; the `symbols` experiment).
enum AssetSymbolName {
    private enum Class { case separator, upper, lower, number }

    private static func classify(_ character: Character) -> Class {
        guard let scalar = character.unicodeScalars.first else { return .separator }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .titlecaseLetter: return .upper
        case .lowercaseLetter, .modifierLetter, .otherLetter, .nonspacingMark, .spacingMark, .enclosingMark: return .lower
        case .decimalNumber, .letterNumber, .otherNumber: return .number
        default: return .separator
        }
    }

    /// The words of a name: runs of letters and numbers, split where a number starts or ends,
    /// before a capital that follows a small letter, and before the last capital of a run of
    /// capitals followed by a small letter (`HTTPSConnection`: `HTTPS`, `Connection`).
    static func words(_ name: String) -> [String] {
        var words: [String] = []
        var current: [Character] = []
        var classes: [Class] = []
        func flush() {
            if !current.isEmpty { words.append(String(current)) }
            current = []
            classes = []
        }
        for character in name {
            let kind = classify(character)
            if kind == .separator {
                flush()
                continue
            }
            if let previous = classes.last {
                if (kind == .number) != (previous == .number) || (kind == .upper && previous == .lower) {
                    flush()
                } else if kind == .lower && previous == .upper && classes.count >= 2 && classes[classes.count - 2] == .upper {
                    let last = current.removeLast()
                    classes.removeLast()
                    flush()
                    current = [last]
                    classes = [.upper]
                }
            }
            current.append(character)
            classes.append(kind)
        }
        flush()
        return words
    }

    /// A name made of capitals and decimal digits only keeps its case, its words joined by `_`.
    private static func isCapitals(_ words: [String]) -> Bool {
        words.allSatisfy { word in
            word.unicodeScalars.allSatisfy {
                [.uppercaseLetter, .titlecaseLetter, .decimalNumber].contains($0.properties.generalCategory)
            }
        }
    }

    private static func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst()
    }

    /// Swift drops a trailing "Color" or "Image" word, as long as a word remains.
    private static func strippingTypeSuffixes(_ words: [String]) -> [String] {
        var words = words
        while words.count > 1, ["color", "image"].contains(words[words.count - 1].lowercased()) {
            words.removeLast()
        }
        return words
    }

    private static func identifier(_ words: [String], upperFirst: Bool) -> String {
        let words = strippingTypeSuffixes(words)
        guard let first = words.first else { return "" }
        let symbol: String
        if isCapitals(words) {
            symbol = words.joined(separator: "_")
        } else {
            symbol = (upperFirst ? capitalized(first) : first.lowercased()) + words.dropFirst().map(capitalized).joined()
        }
        return symbol.first.map { $0.isASCII && $0.isNumber } == true ? "_" + symbol : symbol
    }

    /// The Swift member for an asset (its last path component): lower camel case, in backticks
    /// when it is one of the keywords actool escapes; empty when the name has no letters or digits.
    static func member(_ name: String) -> String {
        let symbol = identifier(words(name), upperFirst: false)
        return keywords.contains(symbol) ? "`\(symbol)`" : symbol
    }

    /// The Swift enum for a namespace folder: upper camel case.
    static func namespace(_ name: String) -> String {
        identifier(words(name), upperFirst: true)
    }

    /// The Objective-C constant's name after its `ACColorName` or `ACImageName` prefix, from the
    /// whole name with its namespaces and without dropping type words. Mixed-case names keep
    /// only their ASCII characters (`café`: `Caf`, whether the `é` is one code point or two).
    static func objectiveC(_ name: String) -> String {
        let words = words(name)
        guard !words.isEmpty else { return "" }
        if isCapitals(words) {
            return words.count == 1 ? words[0] : "_" + words.joined(separator: "_")
        }
        return words.map(capitalized).joined().filter(\.isASCII)
    }

    /// The words actool puts in backticks: every one of Swift's reserved words it was given
    /// (the `symbols` experiment); contextual keywords (`open`, `some`, `any`, `async`, ...) stay bare.
    static let keywords: Set<String> = [
        "as", "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer", "deinit", "do",
        "else", "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func", "guard", "if", "import",
        "in", "init", "inout", "internal", "is", "let", "nil", "operator", "precedencegroup", "private", "protocol",
        "public", "repeat", "rethrows", "return", "self", "static", "struct", "subscript", "super", "switch",
        "throw", "throws", "true", "try", "typealias", "var", "where", "while",
    ]

    /// The members of each extended type that a top-level asset symbol must not shadow: actool
    /// writes a warning instead of the member (the `symbols` experiment, which tried every class
    /// member of these types in the SDK's headers and interfaces).
    static let conflicts: [String: Set<String>] = [
        "NSColor": [
            "alternatingContentBackgroundColors", "black", "blue", "brown", "clear", "controlAlternatingRowBackgroundColors",
            "currentControlTint", "cyan", "darkGray", "gray", "green", "ignoresAlpha", "lightGray", "magenta", "orange",
            "purple", "red", "scrubberTexturedBackground", "systemBlue", "systemBrown", "systemCyan", "systemGray",
            "systemGreen", "systemIndigo", "systemMint", "systemOrange", "systemPink", "systemPurple", "systemRed",
            "systemTeal", "systemYellow", "white", "yellow",
        ],
        "UIColor": [
            "black", "blue", "brown", "clear", "cyan", "darkGray", "darkText", "gray", "green",
            "groupTableViewBackground", "label", "lightGray", "lightText", "link", "magenta", "opaqueSeparator",
            "orange", "placeholderText", "purple", "quaternaryLabel", "quaternarySystemFill", "red", "secondaryLabel",
            "secondarySystemBackground", "secondarySystemFill", "secondarySystemGroupedBackground", "separator",
            "systemBackground", "systemBlue", "systemBrown", "systemCyan", "systemFill", "systemGray", "systemGray2",
            "systemGray3", "systemGray4", "systemGray5", "systemGray6", "systemGreen", "systemGroupedBackground",
            "systemIndigo", "systemMint", "systemOrange", "systemPink", "systemPurple", "systemRed", "systemTeal",
            "systemYellow", "tertiaryLabel", "tertiarySystemBackground", "tertiarySystemFill",
            "tertiarySystemGroupedBackground", "white", "yellow",
        ],
        "Color": [
            "black", "blue", "brown", "clear", "cyan", "gray", "green", "indigo", "mint", "orange", "pink", "primary",
            "purple", "red", "secondary", "teal", "white", "yellow",
        ],
        "UIImage": ["actions", "add", "checkmark", "remove", "strokedCheckmark"],
        "NSImage": [
            "actionTemplateName", "addTemplateName", "advancedName", "applicationIconName", "bluetoothTemplateName",
            "bonjourName", "bookmarksTemplateName", "cautionName", "colorPanelName", "columnViewTemplateName",
            "computerName", "enterFullScreenTemplateName", "everyoneName", "exitFullScreenTemplateName",
            "flowViewTemplateName", "folderBurnableName", "folderName", "folderSmartName",
            "followLinkFreestandingTemplateName", "fontPanelName", "goBackTemplateName", "goForwardTemplateName",
            "goLeftTemplateName", "goRightTemplateName", "homeTemplateName", "iChatTheaterTemplateName",
            "iconViewTemplateName", "imageTypes", "imageUnfilteredTypes", "infoName",
            "invalidDataFreestandingTemplateName", "leftFacingTriangleTemplateName", "listViewTemplateName",
            "lockLockedTemplateName", "lockUnlockedTemplateName", "menuMixedStateTemplateName",
            "menuOnStateTemplateName", "mobileMeName", "multipleDocumentsName", "networkName", "pathTemplateName",
            "preferencesGeneralName", "quickLookTemplateName", "refreshFreestandingTemplateName", "refreshTemplateName",
            "removeTemplateName", "revealFreestandingTemplateName", "rightFacingTriangleTemplateName",
            "shareTemplateName", "slideshowTemplateName", "smartBadgeTemplateName", "statusAvailableName",
            "statusNoneName", "statusPartiallyAvailableName", "statusUnavailableName",
            "stopProgressFreestandingTemplateName", "stopProgressTemplateName", "touchBarAddDetailTemplateName",
            "touchBarAddTemplateName", "touchBarAlarmTemplateName", "touchBarAudioInputMuteTemplateName",
            "touchBarAudioInputTemplateName", "touchBarAudioOutputMuteTemplateName",
            "touchBarAudioOutputVolumeHighTemplateName", "touchBarAudioOutputVolumeLowTemplateName",
            "touchBarAudioOutputVolumeMediumTemplateName", "touchBarAudioOutputVolumeOffTemplateName",
            "touchBarBookmarksTemplateName", "touchBarColorPickerFillName", "touchBarColorPickerFontName",
            "touchBarColorPickerStrokeName", "touchBarCommunicationAudioTemplateName",
            "touchBarCommunicationVideoTemplateName", "touchBarComposeTemplateName", "touchBarDeleteTemplateName",
            "touchBarDownloadTemplateName", "touchBarEnterFullScreenTemplateName", "touchBarExitFullScreenTemplateName",
            "touchBarFastForwardTemplateName", "touchBarFolderCopyToTemplateName", "touchBarFolderMoveToTemplateName",
            "touchBarFolderTemplateName", "touchBarGetInfoTemplateName", "touchBarGoBackTemplateName",
            "touchBarGoDownTemplateName", "touchBarGoForwardTemplateName", "touchBarGoUpTemplateName",
            "touchBarHistoryTemplateName", "touchBarIconViewTemplateName", "touchBarListViewTemplateName",
            "touchBarMailTemplateName", "touchBarNewFolderTemplateName", "touchBarNewMessageTemplateName",
            "touchBarOpenInBrowserTemplateName", "touchBarPauseTemplateName", "touchBarPlayPauseTemplateName",
            "touchBarPlayTemplateName", "touchBarPlayheadTemplateName", "touchBarQuickLookTemplateName",
            "touchBarRecordStartTemplateName", "touchBarRecordStopTemplateName", "touchBarRefreshTemplateName",
            "touchBarRemoveTemplateName", "touchBarRewindTemplateName", "touchBarRotateLeftTemplateName",
            "touchBarRotateRightTemplateName", "touchBarSearchTemplateName", "touchBarShareTemplateName",
            "touchBarSidebarTemplateName", "touchBarSkipAhead15SecondsTemplateName",
            "touchBarSkipAhead30SecondsTemplateName", "touchBarSkipAheadTemplateName",
            "touchBarSkipBack15SecondsTemplateName", "touchBarSkipBack30SecondsTemplateName",
            "touchBarSkipBackTemplateName", "touchBarSkipToEndTemplateName", "touchBarSkipToStartTemplateName",
            "touchBarSlideshowTemplateName", "touchBarTagIconTemplateName", "touchBarTextBoldTemplateName",
            "touchBarTextBoxTemplateName", "touchBarTextCenterAlignTemplateName", "touchBarTextItalicTemplateName",
            "touchBarTextJustifiedAlignTemplateName", "touchBarTextLeftAlignTemplateName",
            "touchBarTextListTemplateName", "touchBarTextRightAlignTemplateName",
            "touchBarTextStrikethroughTemplateName", "touchBarTextUnderlineTemplateName", "touchBarUserAddTemplateName",
            "touchBarUserGroupTemplateName", "touchBarUserTemplateName", "touchBarVolumeDownTemplateName",
            "touchBarVolumeUpTemplateName", "trashEmptyName", "trashFullName", "userAccountsName", "userGroupName",
            "userGuestName", "userName",
        ],
    ]
}
