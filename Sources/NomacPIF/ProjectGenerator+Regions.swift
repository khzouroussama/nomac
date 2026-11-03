import Foundation
import XcodeProj

/// Regions: the project's `knownRegions` and the regions of variant groups' children
/// (docs/formats/pif.md, "Project object" and "Group tree").
extension ProjectGenerator {
    /// The project's `knownRegions`, with its development region first when they lack it
    /// (loader-experiments `regions-classic-3`: `pt` and `(fr, de)` give `pt, fr, de`), then the
    /// regions they lack of the synchronized folders' variant groups, variant group by variant
    /// group in group-tree order, whether or not a target lists the folder (`pif-experiments`
    /// round 6; swiftfin's `af.lproj`), then those of the other variant groups (`regions-classic`,
    /// Base included). A synchronized folder's region is added as it is spelled unless the list
    /// has that exact spelling, and only `mul` itself is left out (netnewswire's `mul.lproj`
    /// string catalogs; `pif-experiments` regions-case-sync: `IT`, `De`, `EN`, `BASE`, `MUL`,
    /// `PT-BR` and `pt-br` are all added next to `it`, `en` and `Base`). Xcode adds the new
    /// regions of one synchronized variant group, and the other variant groups, in an order that
    /// changes from run to run (BACKLOG B-017, B-030); nomac adds them in variant order and
    /// group-tree order. The development region is matched exactly (`regions-case-2`: `EN` goes
    /// first next to `en`).
    func knownRegions() -> [String] {
        var regions = project.project.knownRegions
        if let development = project.project.developmentRegion, !regions.contains(development) {
            regions.insert(development, at: 0)
        }
        func addSynchronized(_ nodes: [SynchronizedFolder.Node]) {
            for node in nodes {
                switch node {
                case .group(_, let children, _):
                    addSynchronized(children)
                case .variantGroup(_, let variants, _):
                    for region in variants.map(\.knownRegion) where region != "mul" && !regions.contains(region) {
                        regions.append(region)
                    }
                case .file:
                    continue
                }
            }
        }
        for root in synchronizedRoots { addSynchronized(root.folder.nodes) }
        func addVariantGroups(_ group: PBXGroup) {
            for child in group.children {
                if let variantGroup = child as? PBXVariantGroup {
                    for region in variantGroup.children.compactMap(region(of:)).map(Self.canonicalRegion) {
                        if region != "mul", !regions.contains(where: { Self.canonicalRegion($0) == region }) { regions.append(region) }
                    }
                } else if let group = child as? PBXGroup, !(child is XCVersionGroup) {
                    addVariantGroups(group)
                }
            }
        }
        if let mainGroup = project.project.mainGroup { addVariantGroups(mainGroup) }
        return regions
    }

    /// How an ordinary variant group's child region is added to `knownRegions`, and compared with
    /// the regions there (spelled the same way): as Foundation's `canonicalLocaleIdentifier` spells
    /// it on a Mac when that differs from it only in case and separators, else as it is written
    /// (loader-experiments `regions-case`, `-4`, `-5`, `-6`, `variant-regions`: all 159 regions
    /// observed). nomac writes that out rather than ask Foundation, whose spelling differs off
    /// Darwin:
    ///
    /// - the names of languages Foundation knows are kept (``languageNames``: `English`, `French`,
    ///   `Nynorsk`, 115 observed; not `Klingon`, `Brazilian`, `Zulu`, which are lowercased), and any
    ///   case of `base` is `Base`;
    /// - otherwise the first subtag is lowercased; a later four-letter one is a script, titled and
    ///   joined with `-`; a two-letter or three-digit one is a region, uppercased with the separator
    ///   it is written with; after a region joined with `_` the rest keeps its separators and is
    ///   uppercased; anything else is lowercased and joined with `-` (`ZH-hans` and `zh_hans` →
    ///   `zh-Hans`, `Zh-HANT-tw` → `zh-Hant-TW`, `Sr-latn-RS` → `sr-Latn-RS`, `ES-419` → `es-419`,
    ///   `Portuguese_BR` → `portuguese_BR`, `Norwegian_Nynorsk` → `norwegian-nynorsk`, `x-Private` →
    ///   `x-private`, `ENGLISH` → `english`).
    ///
    /// Equal spellings match, so `de` after `De` adds nothing, `fr` matches a listed `Fr`, `base` and
    /// `BASE` match `Base`, while `German` and `german` are both added; `mul` in any case never is.
    /// Foundation also rewrites some tags beyond case (`zh_Hans_CN` to `zh_CN`), which by this rule
    /// Xcode keeps as written; that is not observed, and nomac cases them (BACKLOG B-030).
    static func canonicalRegion(_ region: String) -> String {
        if languageNames.contains(region) { return region }
        if region.lowercased() == "base" { return "Base" }
        var subtags: [(separator: Character, text: String)] = []
        var current = "", separator: Character = "-"
        for character in region {
            if character == "-" || character == "_" {
                subtags.append((separator, current))
                current = ""
                separator = character
            } else {
                current.append(character)
            }
        }
        subtags.append((separator, current))
        var result = subtags[0].text.lowercased()
        var regionSeparator: Character?
        for (separator, text) in subtags.dropFirst() {
            let letters = !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isLetter }
            let digits = !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
            if regionSeparator == "_" {
                result += String(separator) + text.uppercased()
            } else if regionSeparator == nil, (text.count == 2 && letters) || (text.count == 3 && digits) {
                regionSeparator = separator
                result += String(separator) + text.uppercased()
            } else if text.count == 4 && letters {
                result += "-" + text.prefix(1).uppercased() + text.dropFirst().lowercased()
            } else {
                result += "-" + text.lowercased()
            }
        }
        return result
    }

    /// The names of languages whose `.lproj` folders Xcode lists as written (`regions-case-5`,
    /// `regions-case-6`, `variant-regions`).
    static let languageNames: Set<String> = [
        "Afrikaans", "Albanian", "Amharic", "Arabic", "Armenian", "Assamese", "Aymara", "Azerbaijani", "Basque", "Belarusian",
        "Bengali", "Breton", "Bulgarian", "Burmese", "Byelorussian", "Catalan", "Chinese", "Croatian", "Czech", "Danish",
        "Dutch", "Dzongkha", "English", "Esperanto", "Estonian", "Faroese", "Farsi", "Finnish", "Flemish", "French", "Galician",
        "Georgian", "German", "Greek", "Greenlandic", "Guarani", "Gujarati", "Hawaiian", "Hebrew", "Hindi", "Hungarian",
        "Icelandic", "Indonesian", "Inuktitut", "Irish", "Italian", "Japanese", "Javanese", "Kannada", "Kashmiri", "Kazakh",
        "Khmer", "Kinyarwanda", "Kirghiz", "Korean", "Kurdish", "Lao", "Latin", "Latvian", "Lithuanian", "Macedonian",
        "Malagasy", "Malay", "Malayalam", "Maltese", "Manx", "Marathi", "Moldavian", "Mongolian", "Nepali", "Norwegian",
        "Nyanja", "Nynorsk", "Oriya", "Oromo", "Pashto", "Persian", "Polish", "Portuguese", "Punjabi", "Quechua", "Romanian",
        "Rundi", "Russian", "Sami", "Sanskrit", "Scottish", "Serbian", "Sindhi", "Sinhalese", "Slovak", "Slovenian", "Somali",
        "Spanish", "Sundanese", "Swahili", "Swedish", "Tagalog", "Tajiki", "Tamil", "Tatar", "Telugu", "Thai", "Tibetan",
        "Tigrinya", "Tongan", "Turkish", "Turkmen", "Uighur", "Ukrainian", "Urdu", "Uzbek", "Vietnamese", "Welsh", "Yiddish",
    ]

    /// The region of a variant group's child: the `<region>.lproj` folder that holds it on the
    /// file system, its groups' paths included, whatever its `name` (loader-experiments
    /// `regions-classic-2`: `name = Foo; path = it.lproj/F.strings` is `it`; `lproj-groups`:
    /// `L1.strings` in a group whose path is `x/ar.lproj` is `ar`, as mattermost's
    /// `Localizable.strings` are, and `../sv.lproj/L7.strings` there is `sv`), or `nil` when that
    /// folder is not a `.lproj` folder (`X.strings`, `nl.lproj/sub/N.strings`; `regions-case`:
    /// `.lproj/B.strings`; `lproj-groups`: a group only named `it.lproj`, a variant group whose
    /// path `sub` is inside `es.lproj`). A reference outside the project's file system goes by
    /// its own path.
    func region(of element: PBXFileElement) -> String? {
        let path = referencePaths[element.uuid] ?? element.path ?? ""
        let folder = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        guard folder.hasSuffix(".lproj"), folder.count > ".lproj".count else { return nil }
        return String(folder.dropLast(".lproj".count))
    }

    /// A group's children in the PIF. A variant group's children without a region are listed
    /// before it instead of in it, and a variant group left with no child is not listed
    /// (`regions-classic-3`: `[ko, M.strings, ja]` gives the file `M.strings`, then the variant
    /// group with `ko` and `ja`; two such children replace their variant group). A variant group
    /// with no children at all is listed.
    /// A child the variant group does not keep is listed with the variant group's path before its
    /// own (`lproj-groups`: `sub/L4.strings`).
    func children(of group: PBXGroup) throws -> [PIFValue] {
        try group.children.filter { !productReferenceIDs.contains($0.uuid) }.flatMap { child in
            try listedElements(child).map { element in
                guard element !== child, let folder = child.path, !folder.isEmpty, element.sourceTree == .group || element.sourceTree == nil else {
                    return try reference(element)
                }
                return try reference(element, folder: folder)
            }
        }
    }

    /// What the PIF lists for a group-tree element: the element itself, or for a variant group,
    /// its children without a region, then the group unless they were all its children. Build
    /// files that name the variant group name those elements too.
    func listedElements(_ element: PBXFileElement) -> [PBXFileElement] {
        guard let variantGroup = element as? PBXVariantGroup else { return [element] }
        let unlocalized = variantGroup.children.filter { region(of: $0) == nil }
        let listed = unlocalized.count < variantGroup.children.count || variantGroup.children.isEmpty
        return unlocalized + (listed ? [variantGroup] : [])
    }
}
