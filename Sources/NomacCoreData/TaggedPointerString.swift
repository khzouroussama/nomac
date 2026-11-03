/// Which strings a Mac stores in the pointer itself (`NSTaggedPointerString`), so that every copy of
/// them is one object: ASCII strings of up to 7 characters, of 8 and 9 characters from a 64-character
/// alphabet, and of 10 and 11 from its first 32 characters. Equal strings of models compiled in one
/// momc run are one object only when tagged; observed on the entity names of coredata-experiments
/// `version-strings` (128 names ending in each letter, digit and underscore) and of every versioned
/// corpus model (docs/formats/coredata.md "VersionInfo.plist").
enum TaggedPointerString {
    static let alphabet = Array("eilotrm.apdnsIc ufkMShjTRxgC4013bDNvwyUL2O856P-B79AFKEWV_zGJ/HYX")

    static func fits(_ string: String) -> Bool {
        let characters = Array(string.unicodeScalars)
        guard characters.allSatisfy(\.isASCII) else { return false }
        switch characters.count {
        case ...7:
            return true
        case 8...9:
            return characters.allSatisfy { alphabet.contains(Character($0)) }
        case 10...11:
            return characters.allSatisfy { alphabet[..<32].contains(Character($0)) }
        default:
            return false
        }
    }
}
