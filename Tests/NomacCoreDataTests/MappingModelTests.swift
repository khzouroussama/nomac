import Testing
@testable import NomacCoreData

/// mapc's rules (docs/formats/coredata.md "Mapping models").
@Suite struct MappingModelTests {
    /// Property mappings in `compare(_:options: [.caseInsensitive, .numeric])` order.
    @Test func ordersPropertyMappingsCaseInsensitivelyAndNumerically() {
        let names = ["_x", "a", "a1", "a2", "a10", "a_", "aB", "b", "Z", "z1"]
        #expect(names.shuffled().sorted(by: EntityMapping.precedes) == names)
    }

    /// The embedded models are read into the inputs of Core Data's version hashes: `Item` with an
    /// optional Date `timestamp` hashes as momc's `one-date` model does.
    @Test func readsVersionHashInputsFromXcodesModelDocument() throws {
        let attribute = XDObject("XDPMAttribute", ["_name": .string("timestamp")])
        attribute.fields["XDBucketForStereotypesstorage"] = .object(XDObject.stereotypes([
            "XD_PPropStereotype": ["XD_PPSK_isOptional": .number(.boolean(true)), "XD_PPSK_isTransient": .number(.boolean(false))],
            "XD_PAtt_Stereotype": ["XD_PAttK_attributeType": .number(.integer(900, bits: 64))],
        ]))
        let entity = XDObject("XDPMEntity", ["_name": .string("Item")])
        entity.fields["XDBucketForStereotypesstorage"] = .object(XDObject.stereotypes(["XD_PStereotype": ["XD_PSK_isAbstract": .number(.boolean(false))]]))
        entity.fields["XDBucketForOwnedAttributesstorage"] = .object(XDObject.dictionary(["timestamp": .object(attribute)]))
        let package = XDObject("XDModelPackage", ["XDBucketForClassesstorage": .object(XDObject.dictionary(["Item": .object(entity)]))])
        let model = try XDModel.dataModel(KeyedArchiver.archive(XDObject("XDPMModel", ["_xd_rootPackage": .object(package)])), path: "test")
        let hashes = try VersionHash.entities(of: model)
        #expect(hashes["Item"]?.map { String(format: "%02x", $0) }.joined() == "18183a04c037273140991c06fe0c9b0daf53749cef8255d31b3136d5fd971676")
    }
}

/// An object of Xcode's model document, archived with its fields in key order.
private final class XDObject: KeyedArchivable {
    let className: String
    var fields: [String: ArchivedItem]

    init(_ className: String, _ fields: [String: ArchivedItem]) {
        self.className = className
        self.fields = fields
    }

    var archivedClassNames: [String] { [className, "NSObject"] }

    func encode(to archiver: KeyedArchiver) throws {
        for key in fields.keys.sorted() {
            try archiver.encode(fields[key], forKey: key)
        }
    }

    static func dictionary(_ entries: [String: ArchivedItem]) -> ArchivedCollection {
        let keys = entries.keys.sorted()
        return ArchivedCollection(.dictionary, keys: keys.map { .string($0) }, objects: keys.map { entries[$0]! })
    }

    /// `XDBucketForStereotypesstorage`: stereotypes of `XDUMLPropertyImp`s whose `_default` is each value.
    static func stereotypes(_ stereotypes: [String: [String: ArchivedItem]]) -> ArchivedCollection {
        dictionary(stereotypes.mapValues { values in
            .object(XDObject("XDUMLStereotypeImp", ["XDBucketForOwnedAttributesstorage": .object(dictionary(values.mapValues { value in
                .object(XDObject("XDUMLPropertyImp", ["_default": value]))
            }))]))
        })
    }
}
