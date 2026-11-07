import Foundation
import NomacCore

/// `momc --action generate`: the classes of the entities with a `codeGenerationType`, in the
/// model's `sourceLanguage` (docs/formats/coredata.md "Code generation"). Each file names its
/// author and day, as momc does with the user's full name and the date.
public enum CodeGenerator {
    public struct Author: Sendable {
        public var name: String
        public var date: Date

        public init(name: String, date: Date) {
            self.name = name
            self.date = date
        }

        /// The user running nomac, today.
        public static var current: Author { Author(name: NSFullUserName(), date: Date()) }
    }

    /// The generated files, named as `ModelCompiler.generatedFiles` lists them.
    public static func files(_ input: String, swiftVersion: String?, author: Author) throws -> [(name: String, contents: String)] {
        guard swiftVersion == "5.0" || swiftVersion == "5" else {
            throw NomacError("code generation for --swift-version \(swiftVersion ?? "(none)") is not observed yet (BACKLOG B-258)")
        }
        let (model, name) = try ModelCompiler.generatingModel(input)
        let generator = Generator(model: model, input: input)
        let files: [(name: String, body: String)]
        switch model.sourceLanguage ?? "Swift" {
        case "Swift": files = try generator.swift(name)
        case "Objective-C": files = try generator.objectiveC(name)
        default:
            throw NomacError("\(input): code generation for sourceLanguage \(model.sourceLanguage ?? "") is not observed yet (BACKLOG B-258)", path: input)
        }
        // On a Mac's case-insensitive volume such files overwrite each other (version-strings).
        guard Set(files.map { $0.name.lowercased() }).count == files.count else {
            throw NomacError("\(input): classes whose names differ only by case generate files that overwrite each other on a Mac; nomac does not reproduce that (BACKLOG B-258)", path: input)
        }
        let day = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: author.date)
        let date = "\(day.month!)/\(day.day!)/\(String(format: "%02d", day.year! % 100))"
        return files.map { file in
            (file.name, """
                //
                //  \(file.name)
                //  \("")
                //
                //  Created by \(author.name) on \(date).
                //
                //  This file was automatically generated and should not be edited.
                //

                """ + file.body)
        }
    }
}

private struct Generator {
    let model: DataModel
    let input: String
    let entities: [String: DataModel.Entity]

    init(model: DataModel, input: String) {
        self.model = model
        self.input = input
        entities = Dictionary(model.entities.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Swift

    func swift(_ name: String) throws -> [(name: String, body: String)] {
        var files: [(String, String)] = []
        for entity in model.entities {
            guard let generation = entity.codeGeneration else { continue }
            let className = try self.className(entity)
            if generation == .class {
                // A class with a module, the current one's `.Name` too, gets no @objc name
                // (codegen-order's Other.Beta, the survey's `.Account`).
                let objcName = entity.className?.contains(".") == true ? "" : "@objc(\(className))"
                let parent = try parentClassName(entity) ?? "NSManagedObject"
                files.append(("\(className)+CoreDataClass.swift", swiftImports() + """

                    public typealias \(className)CoreDataClassSet = NSSet

                    \(objcName)
                    public class \(className): \(parent) {

                    }

                    """))
            }
            files.append(("\(className)+CoreDataProperties.swift", try swiftProperties(entity, className)))
        }
        guard !files.isEmpty else { return [] }
        // The input's name keeps only its letters: `lil_wallet` is `lilwallet`, `Technex18` is
        // `Technex` (coredata-experiments `model-names`).
        guard name.allSatisfy(\.isASCII) else {
            throw NomacError("\(input): code generation for a model name of other characters than ASCII is not observed yet (BACKLOG B-258)", path: input)
        }
        let letters = name.filter(\.isLetter)
        files.append(("\(name)+CoreDataModel.swift", swiftImports() + """

            public typealias \(letters)FoundationFrameworkSet = NSSet
            public typealias \(letters)CoreDataFrameworkManagedObject = NSManagedObject



            """))
        return files
    }

    private func swiftImports(_ line: String = "") -> String {
        "\npublic import Foundation\npublic import CoreData\n" + line
    }

    private func swiftProperties(_ entity: DataModel.Entity, _ className: String) throws -> String {
        var declarations: [String] = []
        var accessors: [String] = []
        var modules: Set<String> = []
        for attribute in attributes(entity) {
            declarations.append("    @NSManaged nonisolated public var \(attribute.name): \(try swiftType(attribute, entity))")
            // `UIKit.UIColor` is imported as a relationship's module is (the survey's iCloudCoreDataStarter).
            if attribute.type == .transformable, let dot = attribute.customClassName?.firstIndex(of: "."), dot != attribute.customClassName?.startIndex {
                modules.insert(String(attribute.customClassName![..<dot]))
            }
        }
        for relationship in relationships(entity) {
            let destination = try self.destination(relationship, entity)
            let target = try self.className(destination)
            // A destination of another module is imported (relationships-order's Other.Mod).
            if let represented = destination.className, let dot = represented.firstIndex(of: "."), dot != represented.startIndex {
                modules.insert(String(represented[..<dot]))
            }
            guard relationship.isToMany else {
                declarations.append("    @NSManaged nonisolated public var \(relationship.name): \(target)?")
                continue
            }
            let collection = relationship.isOrdered ? "NSOrderedSet" : "NSSet"
            declarations.append("    @NSManaged nonisolated public var \(relationship.name): \(collection)?")
            accessors.append(swiftAccessors(relationship.name, target, collection, className, ordered: relationship.isOrdered))
        }
        guard modules.count <= 1 else {
            throw NomacError("\(input): code generation for relationships to classes of several modules is not observed yet (BACKLOG B-258)", path: input)
        }
        let identifiable = entity.parentName == nil ? """

            extension \(className) : Identifiable {

            }

            """ : ""
        return swiftImports(modules.first.map { "import \($0)\n" } ?? "\n") + """

            public typealias \(className)CoreDataPropertiesSet = NSSet

            extension \(className) {

                @nonobjc public class func fetchRequest() -> NSFetchRequest<\(className)> {
                    return NSFetchRequest<\(className)>(entityName: "\(entity.name)")
                }

            \(declarations.map { $0 + "\n" }.joined())
            }

            """ + accessors.joined() + identifiable
    }

    /// The `@NSManaged` accessors of a to-many relationship (`to-many`, `ordered`).
    private func swiftAccessors(_ name: String, _ target: String, _ collection: String, _ className: String, ordered: Bool) -> String {
        let capitalized = capitalize(name)
        var methods: [(String, String)] = []
        if ordered {
            methods += [
                ("insertObject:in\(capitalized)AtIndex:", "insertInto\(capitalized)(_ value: \(target), at idx: Int)"),
                ("removeObjectFrom\(capitalized)AtIndex:", "removeFrom\(capitalized)(at idx: Int)"),
                ("insert\(capitalized):atIndexes:", "insertInto\(capitalized)(_ values: [\(target)], at indexes: NSIndexSet)"),
                ("remove\(capitalized)AtIndexes:", "removeFrom\(capitalized)(at indexes: NSIndexSet)"),
                ("replaceObjectIn\(capitalized)AtIndex:withObject:", "replace\(capitalized)(at idx: Int, with value: \(target))"),
                ("replace\(capitalized)AtIndexes:with\(capitalized):", "replace\(capitalized)(at indexes: NSIndexSet, with values: [\(target)])"),
            ]
        }
        methods += [
            ("add\(capitalized)Object:", "addTo\(capitalized)(_ value: \(target))"),
            ("remove\(capitalized)Object:", "removeFrom\(capitalized)(_ value: \(target))"),
            ("add\(capitalized):", "addTo\(capitalized)(_ values: \(collection))"),
            ("remove\(capitalized):", "removeFrom\(capitalized)(_ values: \(collection))"),
        ]
        return """

            // MARK: Generated accessors for \(name)
            extension \(className) {

            \(methods.map { "    @objc(\($0.0))\n    @NSManaged nonisolated public func \($0.1)\n\n" }.joined())}

            """
    }

    /// Scalars with `usesScalarValueType`, otherwise optional objects (`type-*`, `type-*-object`).
    private func swiftType(_ attribute: DataModel.Attribute, _ entity: DataModel.Entity) throws -> String {
        if let scalar = try scalarType(attribute, entity, ["Int16", "Int32", "Int64", "Double", "Float", "Bool"]) {
            return scalar
        }
        switch attribute.type {
        case .integer16, .integer32, .integer64, .double, .float, .boolean: return "NSNumber?"
        case .decimal: return "NSDecimalNumber?"
        case .string: return "String?"
        case .date: return "Date?"
        case .binary: return "Data?"
        case .uuid: return "UUID?"
        case .uri: return "URL?"
        case .transformable: return (attribute.customClassName?.split(separator: ".").last.map(String.init) ?? "NSObject") + "?"
        case .undefined:
            throw NomacError("attribute \(entity.name).\(attribute.name): code generation for an undefined type is not observed yet (BACKLOG B-258)", path: input)
        }
    }

    // MARK: Objective-C

    func objectiveC(_ name: String) throws -> [(name: String, body: String)] {
        var files: [(String, String)] = []
        var imports: [String] = []
        for entity in model.entities {
            guard let generation = entity.codeGeneration else { continue }
            let className = try self.className(entity)
            let represented = entity.className ?? className
            let classes = try forwardDeclarations(entity, className)
            if generation == .class {
                if represented.hasPrefix(".") {
                    throw NomacError("\(input): code generation for the class \(represented) of the current module is not observed yet (BACKLOG B-258)", path: input)
                }
                let parent = try parentClassName(entity)
                let declarations = classes.isEmpty ? "" : "@class \(classes.joined(separator: ", "));\n\n"
                files.append(("\(className)+CoreDataClass.h", """

                    #import <Foundation/Foundation.h>
                    \(parent.map { "#import \"\($0)+CoreDataClass.h\"" } ?? "#import <CoreData/CoreData.h>")

                    \(declarations)NS_ASSUME_NONNULL_BEGIN

                    @interface \(className) : \(parent ?? "NSManagedObject")

                    @end

                    NS_ASSUME_NONNULL_END

                    #import "\(className)+CoreDataProperties.h"

                    """))
                files.append(("\(className)+CoreDataClass.m", """

                    #import "\(className)+CoreDataClass.h"

                    @implementation \(className)

                    @end

                    """))
                imports.append(represented + "+CoreDataClass.h")
            } else {
                guard classes.isEmpty else {
                    throw NomacError("\(input): Objective-C code generation for the category of \(entity.name), which refers to other classes, is not observed yet (BACKLOG B-258)", path: input)
                }
                imports.append(represented + "+CoreDataProperties.h")
            }
            let header = generation == .class ? "\(represented)+CoreDataClass.h" : "\(represented).h"
            files += try objectiveCProperties(entity, className, header: header)
        }
        guard !files.isEmpty else { return [] }
        // The model's header imports each entity's in the order of their class names (relationships-order).
        let sorted = imports.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        files.append(("\(name)+CoreDataModel.h", """

            #import <Foundation/Foundation.h>
            #import <CoreData/CoreData.h>

            \(sorted.map { "#import \"\($0)\"\n" }.joined())




            """))
        files.append(("\(name)+CoreDataModel.m", "\n#import \"\(name)+CoreDataModel.h\"\n\n\n"))
        return files
    }

    /// The classes a class header declares with `@class`: those of its relationships' destinations
    /// and transformable attributes but its own, in byte order (relationships-several, -order).
    private func forwardDeclarations(_ entity: DataModel.Entity, _ className: String) throws -> [String] {
        var classes = Set(try attributes(entity).filter { $0.type == .transformable }.map { try transformableClass($0, entity) })
        for relationship in relationships(entity) {
            classes.insert(try self.className(try destination(relationship, entity)))
        }
        classes.remove(className)
        return classes.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private func objectiveCProperties(_ entity: DataModel.Entity, _ className: String, header: String) throws -> [(String, String)] {
        var declarations: [String] = []
        var accessors: [String] = []
        for attribute in attributes(entity) {
            declarations.append(try objectiveCProperty(attribute, entity))
        }
        for relationship in relationships(entity) {
            let target = try self.className(try destination(relationship, entity))
            guard relationship.isToMany else {
                declarations.append("@property (nullable, nonatomic, retain) \(target) *\(relationship.name);")
                continue
            }
            let collection = relationship.isOrdered ? "NSOrderedSet" : "NSSet"
            declarations.append("@property (nullable, nonatomic, retain) \(collection)<\(target) *> *\(relationship.name);")
            accessors.append(objectiveCAccessors(relationship.name, target, collection, ordered: relationship.isOrdered))
        }
        // Entities with subentities keep the Objective-C name of the method in Swift (inheritance's Base).
        let hasSubentities = model.entities.contains { $0.parentName == entity.name }
        let swiftName = hasSubentities ? "" : " NS_SWIFT_NAME(fetchRequest())"
        let generatedAccessors = accessors.isEmpty ? "" : """

            @interface \(className) (CoreDataGeneratedAccessors)

            \(accessors.joined(separator: "\n"))
            @end

            """
        let names = attributes(entity).map(\.name) + relationships(entity).map(\.name)
        return [("\(className)+CoreDataProperties.h", """

            #import "\(header)"


            NS_ASSUME_NONNULL_BEGIN

            @interface \(className) (CoreDataProperties)

            + (NSFetchRequest<\(className) *> *)fetchRequest\(swiftName);

            \(declarations.map { $0 + "\n" }.joined())
            @end
            \(generatedAccessors)
            NS_ASSUME_NONNULL_END

            """), ("\(className)+CoreDataProperties.m", """

            #import "\(className)+CoreDataProperties.h"

            @implementation \(className) (CoreDataProperties)

            + (NSFetchRequest<\(className) *> *)fetchRequest {
            \treturn [NSFetchRequest fetchRequestWithEntityName:@"\(entity.name)"];
            }

            \(names.map { "@dynamic \($0);\n" }.joined())
            @end

            """)]
    }

    /// The methods Core Data implements for a to-many relationship (moonlight, relationships-order).
    private func objectiveCAccessors(_ name: String, _ target: String, _ collection: String, ordered: Bool) -> String {
        let capitalized = capitalize(name)
        var methods: [String] = []
        if ordered {
            methods += [
                "insertObject:(\(target) *)value in\(capitalized)AtIndex:(NSUInteger)idx",
                "removeObjectFrom\(capitalized)AtIndex:(NSUInteger)idx",
                "insert\(capitalized):(NSArray<\(target) *> *)value atIndexes:(NSIndexSet *)indexes",
                "remove\(capitalized)AtIndexes:(NSIndexSet *)indexes",
                "replaceObjectIn\(capitalized)AtIndex:(NSUInteger)idx withObject:(\(target) *)value",
                "replace\(capitalized)AtIndexes:(NSIndexSet *)indexes with\(capitalized):(NSArray<\(target) *> *)values",
            ]
        }
        methods += [
            "add\(capitalized)Object:(\(target) *)value",
            "remove\(capitalized)Object:(\(target) *)value",
            "add\(capitalized):(\(collection)<\(target) *> *)values",
            "remove\(capitalized):(\(collection)<\(target) *> *)values",
        ]
        return methods.map { "- (void)\($0);\n" }.joined()
    }

    /// Scalars with `usesScalarValueType`; objects copied, but data and transformables retained (`objc-type-*`).
    private func objectiveCProperty(_ attribute: DataModel.Attribute, _ entity: DataModel.Entity) throws -> String {
        if let scalar = try scalarType(attribute, entity, ["int16_t", "int32_t", "int64_t", "double", "float", "BOOL"]) {
            return "@property (nonatomic) \(scalar) \(attribute.name);"
        }
        let (type, semantics): (String, String)
        switch attribute.type {
        case .integer16, .integer32, .integer64, .double, .float, .boolean: (type, semantics) = ("NSNumber", "copy")
        case .decimal: (type, semantics) = ("NSDecimalNumber", "copy")
        case .string: (type, semantics) = ("NSString", "copy")
        case .date: (type, semantics) = ("NSDate", "copy")
        case .binary: (type, semantics) = ("NSData", "retain")
        case .uuid: (type, semantics) = ("NSUUID", "copy")
        case .uri: (type, semantics) = ("NSURL", "copy")
        case .transformable: (type, semantics) = (try transformableClass(attribute, entity), "retain")
        case .undefined:
            throw NomacError("attribute \(entity.name).\(attribute.name): code generation for an undefined type is not observed yet (BACKLOG B-258)", path: input)
        }
        return "@property (nullable, nonatomic, \(semantics)) \(type) *\(attribute.name);"
    }

    // MARK: Both languages

    /// The attributes, then the relationships, each in file order (relationships-order).
    private func attributes(_ entity: DataModel.Entity) -> [DataModel.Attribute] {
        entity.properties.compactMap {
            guard case .attribute(let attribute) = $0 else { return nil }
            return attribute
        }
    }

    private func relationships(_ entity: DataModel.Entity) -> [DataModel.Relationship] {
        entity.properties.compactMap {
            guard case .relationship(let relationship) = $0 else { return nil }
            return relationship
        }
    }

    private func className(_ entity: DataModel.Entity) throws -> String {
        guard let name = entity.className?.split(separator: ".").last.map(String.init) else {
            throw NomacError("entity \(entity.name) generates code but has no class name", path: input)
        }
        return name
    }

    private func parentClassName(_ entity: DataModel.Entity) throws -> String? {
        guard let parent = entity.parentName.flatMap({ entities[$0] }) else { return nil }
        if parent.className?.contains(".") == true, parent.className?.hasPrefix(".") != true {
            throw NomacError("\(input): code generation for a subclass of \(parent.className!) is not observed yet (BACKLOG B-258)", path: input)
        }
        return try className(parent)
    }

    private func destination(_ relationship: DataModel.Relationship, _ entity: DataModel.Entity) throws -> DataModel.Entity {
        guard let destination = entities[relationship.destination] else {
            throw NomacError("relationship \(entity.name).\(relationship.name) names the entity \(relationship.destination), which is not in the model", path: input)
        }
        return destination
    }

    /// The scalar of `names` (Integer 16, 32, 64, Double, Float, Boolean) when the attribute uses one.
    private func scalarType(_ attribute: DataModel.Attribute, _ entity: DataModel.Entity, _ names: [String]) throws -> String? {
        let index: Int
        switch attribute.type {
        case .integer16: index = 0
        case .integer32: index = 1
        case .integer64: index = 2
        case .double: index = 3
        case .float: index = 4
        case .boolean: index = 5
        case .date:
            guard attribute.usesScalarValueType != true else {
                throw NomacError("attribute \(entity.name).\(attribute.name): a scalar Date is not observed yet (BACKLOG B-258)", path: input)
            }
            return nil
        default: return nil
        }
        guard let usesScalar = attribute.usesScalarValueType else {
            throw NomacError("attribute \(entity.name).\(attribute.name) has no usesScalarValueType, whose generated type is not observed yet (BACKLOG B-258)", path: input)
        }
        return usesScalar ? names[index] : nil
    }

    private func transformableClass(_ attribute: DataModel.Attribute, _ entity: DataModel.Entity) throws -> String {
        let name = attribute.customClassName ?? "NSObject"
        if name.contains(".") {
            throw NomacError("attribute \(entity.name).\(attribute.name): code generation for the class \(name) is not observed yet (BACKLOG B-258)", path: input)
        }
        return name
    }

    private func capitalize(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }
}
