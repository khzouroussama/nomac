import Foundation
import Testing
import NomacVerify

@Suite struct PIFComparisonTests {
    static let normalizer = PathNormalizer(roots: [])

    /// A project whose group tree holds two synchronized members and whose one target lists
    /// them in a sources phase, in the given order.
    static func document(signature: String, a: String, b: String, phaseOrder: [String]) -> String {
        """
        [
          {
            "contents" : {
              "groupTree" : {
                "children" : [
                  { "guid" : "\(a)", "path" : "a.swift", "type" : "file" },
                  { "guid" : "\(b)", "path" : "b.swift", "type" : "file" }
                ],
                "guid" : "root",
                "type" : "group"
              }
            },
            "signature" : "\(signature)",
            "type" : "project"
          },
          {
            "contents" : {
              "buildPhases" : [
                { "buildFiles" : [\(phaseOrder.map { #"{ "fileReference" : "\#($0)" }"# }.joined(separator: ", "))], "type" : "com.apple.buildphase.sources" }
              ]
            },
            "signature" : "TARGET@v11_hash=\(signature)",
            "type" : "target"
          }
        ]
        """
    }

    static let xcodeA = "OigWQpuLhMyq/qEDxVIE5Xm5l9DNt/fP7Zs4CDAbxP0="
    static let xcodeB = "3ATj7UcAJBGR9dnNOG7kb7LFdXRgHs+IE7g7A1r71JI="
    static let nomacA = "u3D6T/E29zeqVjKAoiDCcmvunIxTXJYxdx9YJgzne/4="
    static let nomacB = "z4rn2ZO2nKAoWtqDzQdGlTek0051+x7OJf3uhwH5Qpg="

    @Test func synchronizedGUIDsAndSignaturesAreOpaque() throws {
        let expected = Self.document(signature: "PROJECT@v11_hash=1", a: Self.xcodeA, b: Self.xcodeB, phaseOrder: [Self.xcodeA, Self.xcodeB])
        let actual = Self.document(signature: "PROJECT@v11_hash=2", a: Self.nomacA, b: Self.nomacB, phaseOrder: [Self.nomacA, Self.nomacB])
        #expect(try PIFComparison.compare(expected: expected, actual: actual, normalizer: Self.normalizer).identical)
    }

    /// The build files of the file references the caller names (variant group children Xcode
    /// lifts out of their group) get stand-ins: Xcode draws their GUIDs at random.
    @Test func buildFilesOfLiftedChildrenAreOpaque() throws {
        func document(_ buildFileGUID: String) -> String {
            """
            [
              { "contents" : { "groupTree" : { "children" : [ { "guid" : "P1C2", "path" : "Extra/de.strings", "type" : "file" } ], "guid" : "root", "type" : "group" } },
                "signature" : "PROJECT@v11_hash=1", "type" : "project" },
              { "contents" : { "buildPhases" : [ { "buildFiles" : [ { "fileReference" : "P1C2", "guid" : "\(buildFileGUID)" } ], "type" : "com.apple.buildphase.resources" } ] },
                "signature" : "TARGET@v11_hash=1", "type" : "target" }
            ]
            """
        }
        #expect(try PIFComparison.compare(expected: document("P1random"), actual: document("P1nomac"), normalizer: Self.normalizer,
                                          randomBuildFileReferences: ["P1C2"]).identical)
        #expect(try !PIFComparison.compare(expected: document("P1random"), actual: document("P1nomac"), normalizer: Self.normalizer).identical)
    }

    @Test func aDifferentBuildPhaseOrderStillDiffers() throws {
        let expected = Self.document(signature: "PROJECT@v11_hash=1", a: Self.xcodeA, b: Self.xcodeB, phaseOrder: [Self.xcodeA, Self.xcodeB])
        let actual = Self.document(signature: "PROJECT@v11_hash=1", a: Self.nomacA, b: Self.nomacB, phaseOrder: [Self.nomacB, Self.nomacA])
        let result = try PIFComparison.compare(expected: expected, actual: actual, normalizer: Self.normalizer)
        #expect(!result.identical)
        #expect(result.firstDifference?.expected.contains("<SYNCHRONIZED-0>") == true)
        #expect(result.firstDifference?.actual.contains("<SYNCHRONIZED-1>") == true)
    }

    /// A workspace with one project and the given package projects, in that order, each
    /// followed by one target.
    static func workspace(packages: [(guid: String, setting: String)]) -> String {
        func project(_ guid: String, isPackage: Bool, setting: String) -> String {
            """
              { "contents" : { "guid" : "\(guid)", \(isPackage ? #""projectIsPackage" : "true", "# : "")"setting" : "\(setting)", "targets" : [ "TARGET@\(guid)" ] }, "signature" : "PROJECT@\(guid)", "type" : "project" },
              { "contents" : { "guid" : "\(guid)-target" }, "signature" : "TARGET@\(guid)", "type" : "target" }
            """
        }
        let projects = [("app", false, "A")] + packages.map { ($0.guid, true, $0.setting) }
        return """
        [
          { "contents" : { "projects" : [ \(projects.map { #""PROJECT@\#($0.0)""# }.joined(separator: ", ")) ] }, "signature" : "WORKSPACE@1", "type" : "workspace" },
        \(projects.map { project($0.0, isPackage: $0.1, setting: $0.2) }.joined(separator: ",\n"))
        ]
        """
    }

    @Test func packageProjectOrderIsOpaque() throws {
        let expected = Self.workspace(packages: [("PACKAGE:b", "B"), ("PACKAGE:a", "A")])
        let actual = Self.workspace(packages: [("PACKAGE:a", "A"), ("PACKAGE:b", "B")])
        #expect(try PIFComparison.compare(expected: expected, actual: actual, normalizer: Self.normalizer).identical)
    }

    @Test func packageProjectContentsAreStillCompared() throws {
        let expected = Self.workspace(packages: [("PACKAGE:b", "B"), ("PACKAGE:a", "A")])
        let actual = Self.workspace(packages: [("PACKAGE:a", "A"), ("PACKAGE:b", "C")])
        let result = try PIFComparison.compare(expected: expected, actual: actual, normalizer: Self.normalizer)
        #expect(!result.identical)
        #expect(result.firstDifference?.expected.contains("\"B\"") == true)
        #expect(result.firstDifference?.actual.contains("\"C\"") == true)
    }

    /// A project whose group tree holds a variant group with the GUID `group` and two variants,
    /// which one target's resources phase copies with the build file `buildFile`.
    static func variantGroup(group: String, children: (String, String), buildFile: String) -> String {
        """
        [
          {
            "contents" : {
              "groupTree" : {
                "children" : [
                  { "children" : [
                      { "guid" : "\(children.0)", "path" : "de.lproj/L.strings", "type" : "file" },
                      { "guid" : "\(children.1)", "path" : "fr.lproj/L.strings", "type" : "file" }
                    ], "guid" : "\(group)", "name" : "L.strings", "type" : "variantGroup" }
                ],
                "guid" : "root",
                "type" : "group"
              }
            },
            "signature" : "PROJECT@1",
            "type" : "project"
          },
          {
            "contents" : {
              "buildPhases" : [ { "buildFiles" : [ { "fileReference" : "\(group)", "guid" : "\(buildFile)" } ], "type" : "com.apple.buildphase.resources" } ]
            },
            "signature" : "TARGET@1",
            "type" : "target"
          }
        ]
        """
    }

    /// Xcode draws the GUIDs of a synchronized variant group with neither a development-region nor
    /// a Base variant, and of its build files, at random (pif-experiments `hexguid-*`); those of
    /// an ordinary variant group, whose children are not synchronized, are still compared.
    @Test func randomVariantGroupGUIDsAreOpaque() throws {
        let hex = "644b85a0f80239533865c3385522c10523f467cb2fe906c315fe294ceecda37d"
        let expected = Self.variantGroup(group: hex, children: (Self.xcodeA, Self.xcodeB), buildFile: "644b85a0f80239533865c3385522c1051d120c71c6b9cae25d3e406775f5bbdf")
        let actual = Self.variantGroup(group: "ylBa1MQrnBkksVobQNTSwskfiEQmsWeTegtyggdk/ZM=", children: (Self.nomacA, Self.nomacB), buildFile: "xMOUCM1BTO6TWOsFI9OJCe+GPxZgJF0wzjtqYt1x/so=")
        #expect(try PIFComparison.compare(expected: expected, actual: actual, normalizer: Self.normalizer).identical)
        let ordinary = Self.variantGroup(group: hex, children: ("child-1", "child-2"), buildFile: "build-file")
        let other = Self.variantGroup(group: "other-group", children: ("child-1", "child-2"), buildFile: "build-file")
        #expect(try !PIFComparison.compare(expected: ordinary, actual: other, normalizer: Self.normalizer).identical)
    }

    @Test func otherStringsAreCompared() throws {
        let expected = Self.document(signature: "PROJECT@v11_hash=1", a: Self.xcodeA, b: "Rampage-hex-guid", phaseOrder: [Self.xcodeA])
        let actual = Self.document(signature: "PROJECT@v11_hash=1", a: Self.nomacA, b: "Rampage-other-guid", phaseOrder: [Self.nomacA])
        #expect(try !PIFComparison.compare(expected: expected, actual: actual, normalizer: Self.normalizer).identical)
    }
}
