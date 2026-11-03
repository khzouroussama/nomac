import Foundation
import NomacProject
import Testing
@testable import NomacPIF

/// How Xcode's destination check reads a target's SDKROOT from its levels (loader-experiments
/// `simulator-sdks`, `simulator-sdk-conditions` and its `-project` variants; BACKLOG B-089).
@Suite struct SettingLevelsTests {
    static func level(_ assignments: [(String, String)], xcconfig: Bool = false) -> PIFDocument.SettingLevel {
        PIFDocument.SettingLevel(assignments: assignments.map { key, value in
            let (name, conditions) = XCConfigFile.key(key)!
            return XCConfigFile.Assignment(name: name, conditions: conditions, value: value)
        }, isXCConfig: xcconfig)
    }

    static func sdkroot(_ levels: [PIFDocument.SettingLevel], sdk: String = "iphoneos27.0") -> String? {
        levels.xcodeValue("SDKROOT", sdk: sdk, configuration: "Debug", evaluated: ["SRCROOT": "/p"])
    }

    @Test func projectFileConditions() {
        #expect(Self.sdkroot([Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[config=Debug]", "iphonesimulator")])]) == "iphoneos")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[config=D*]", "iphonesimulator")])]) == "iphoneos")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[config=*]", "iphonesimulator")])]) == "iphonesimulator")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[arch=arm64]", "iphonesimulator")])]) == "iphoneos")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[arch=*]", "iphonesimulator")])]) == "iphonesimulator")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[sdk=iphoneos*]", "iphonesimulator")])]) == "iphonesimulator")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "macosx"), ("SDKROOT[sdk=iphoneos*]", "iphonesimulator")])], sdk: "macosx27.0") == "macosx")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[sdk=iphoneos*][config=Debug]", "iphonesimulator")])]) == "iphoneos")
    }

    @Test func xcconfigConditions() {
        let target = Self.level([])
        #expect(Self.sdkroot([target, Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[config=Debug]", "iphonesimulator")], xcconfig: true)]) == "iphonesimulator")
        #expect(Self.sdkroot([target, Self.level([("SDKROOT[config=Debug]", "iphonesimulator"), ("SDKROOT", "iphoneos")], xcconfig: true)]) == "iphonesimulator")
        #expect(Self.sdkroot([target, Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[arch=arm64]", "iphonesimulator")], xcconfig: true)]) == "iphoneos")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "iphonesimulator")]), Self.level([("SDKROOT", "iphoneos")], xcconfig: true)]) == "iphonesimulator")
    }

    @Test func levelsWithoutAnApplyingAssignmentAndMacros() {
        let project = Self.level([("SDKROOT", "iphoneos"), ("SDKROOT[config=Debug]", "iphonesimulator")])
        #expect(Self.sdkroot([Self.level([("SDKROOT[config=Debug]", "iphonesimulator")]), Self.level([], xcconfig: true), project]) == "iphoneos")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "$(NOMAC_SDK)"), ("NOMAC_SDK", "iphoneos"), ("NOMAC_SDK[config=Debug]", "iphonesimulator")])]) == "iphoneos")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "$(NOMAC_SDK)")]),
                              Self.level([("NOMAC_SDK", "iphoneos"), ("NOMAC_SDK[config=Debug]", "iphonesimulator")], xcconfig: true)]) == "iphonesimulator")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "$(SRCROOT)/SDKs/iPhoneOS.sdk")])]) == "/p/SDKs/iPhoneOS.sdk")
        #expect(Self.sdkroot([Self.level([("SDKROOT", "$(inherited)")])]) == nil)
        #expect(Self.sdkroot([Self.level([("OTHER", "x")])]) == nil)
    }

    @Test func readsTheTargetsAndProjectsConfigurationsAndXCConfigs() throws {
        let root = FileManager.default.temporaryDirectory.path + "/nomac-levels-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/Config", withIntermediateDirectories: true)
        try Data("SDKROOT[config=Debug] = iphonesimulator\n".utf8).write(to: URL(fileURLWithPath: root + "/Config/Target.xcconfig"))
        func configuration(_ name: String, _ settings: [String: String], base: String? = nil) -> PIFValue {
            var contents: [String: PIFValue] = ["name": .string(name), "buildSettings": .object(settings.mapValues { .string($0) })]
            if let base { contents["baseConfigurationFileReference"] = .string(base) }
            return .object(contents)
        }
        let tree = PIFValue.object(["type": .string("group"), "path": .string(""), "sourceTree": .string("<group>"), "children": .array([
            .object(["type": .string("group"), "path": .string("Config"), "sourceTree": .string("<group>"), "children": .array([
                .object(["type": .string("file"), "guid": .string("X1"), "path": .string("Target.xcconfig"), "sourceTree": .string("<group>")]),
            ])]),
        ])])
        let document = PIFDocument(objects: [
            .init(type: "project", signature: "P", contents: .object([
                "projectDirectory": .string(root), "groupTree": tree, "targets": .array([.string("T-signature")]),
                "buildConfigurations": .array([configuration("Debug", ["SDKROOT": "iphoneos"]), configuration("Release", ["SDKROOT": "macosx"])]),
            ])),
            .init(type: "target", signature: "T-signature", contents: .object([
                "guid": .string("T"),
                "buildConfigurations": .array([configuration("Debug", ["PRODUCT_NAME": "App"], base: "X1"), configuration("Release", [:])]),
            ])),
        ])
        let levels = document.settingLevels(target: "T", configuration: "Debug")
        #expect(levels == [
            Self.level([("PRODUCT_NAME", "App")]), Self.level([("SDKROOT[config=Debug]", "iphonesimulator")], xcconfig: true),
            Self.level([("SDKROOT", "iphoneos")]), Self.level([], xcconfig: true),
        ])
        #expect(Self.sdkroot(levels) == "iphonesimulator")
        #expect(document.settingLevels(target: "Other", configuration: "Debug").isEmpty)
    }
}
