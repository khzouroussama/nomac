import Testing
@testable import NomacPIF

/// What `build-for-testing` reads from the PIF for the `.xctestrun` (docs/formats/xctestrun.md).
@Suite struct PIFTargetQueriesTests {
    static func target(_ guid: String, name: String, dependencies: [String] = [], linked: [String] = [], sources: [String] = []) -> PIFDocument.Object {
        let buildFiles: [PIFValue] = sources.map { .object(["fileReference": .string($0)]) }
        let frameworks: [PIFValue] = linked.map { .object(["targetReference": .string($0)]) }
        return PIFDocument.Object(type: "target", signature: "target-" + guid, contents: .object([
            "guid": .string(guid), "name": .string(name),
            "dependencies": .array(dependencies.map { .object(["guid": .string($0)]) }),
            "buildPhases": .array([
                .object(["type": .string("com.apple.buildphase.sources"), "buildFiles": .array(buildFiles)]),
                .object(["type": .string("com.apple.buildphase.frameworks"), "buildFiles": .array(frameworks)]),
            ]),
        ]))
    }

    static let project = PIFDocument.Object(type: "project", signature: "project", contents: .object([
        "projectDirectory": .string("/w"),
        "groupTree": .object(["type": .string("group"), "path": .string("App"), "sourceTree": .string("<group>"), "children": .array([
            .object(["type": .string("file"), "guid": .string("a"), "path": .string("A.swift"), "sourceTree": .string("<group>")]),
            .object(["type": .string("file"), "guid": .string("b"), "path": .string("Sub/B.m"), "sourceTree": .string("<group>")]),
            .object(["type": .string("file"), "guid": .string("sdk"), "path": .string("C.swift"), "sourceTree": .string("SDKROOT")]),
        ])]),
    ]))

    static let document = PIFDocument(objects: [
        project,
        target("app", name: "App", dependencies: ["kit"], linked: ["PACKAGE-PRODUCT:p", "not-in-the-document"], sources: ["a", "b", "sdk"]),
        target("kit", name: "Kit", dependencies: ["stat"]),
        target("stat", name: "Stat", dependencies: ["app"]),
        target("PACKAGE-PRODUCT:p", name: "P-product", dependencies: ["PACKAGE-TARGET:p"]),
        target("PACKAGE-TARGET:p", name: "P"),
    ])

    @Test func dependenciesFollowListedAndLinkedTargetsOnce() {
        #expect(Self.document.withDependencies(of: ["app"]) == ["app", "kit", "PACKAGE-PRODUCT:p", "stat", "PACKAGE-TARGET:p"])
    }

    /// Generated files have no file reference, and a file under a build setting's tree has no path here.
    @Test func compileSourcesAreTheSourcesPhasesFiles() {
        #expect(Self.document.compileSources(targetGUID: "app") == ["/w/App/A.swift", "/w/App/Sub/B.m"])
        #expect(Self.document.compileSources(targetGUID: "kit").isEmpty)
        #expect(Self.document.compileSources(targetGUID: "none").isEmpty)
    }

    @Test func targetsByNameAndByGUID() {
        #expect(Self.document.targetName(guid: "kit") == "Kit")
        #expect(Self.document.targetGUID(named: "P-product") == "PACKAGE-PRODUCT:p")
        #expect(Self.document.targetGUID(named: "Nothing") == nil)
    }
}
