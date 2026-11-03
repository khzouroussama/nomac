import Foundation
import Testing
import NomacBuildService
import NomacCore
import NomacTestSupport

/// A hand-written PIF for a one-target iOS application project.
private func minimalPIF(projectDir: String) -> [[String: Any]] {
    let projectPath = projectDir + "/Smoke.xcodeproj"
    let config: (String) -> [String: Any] = { name in
        ["guid": "CONFIG-PROJECT-\(name)", "name": name, "buildSettings": ["SDKROOT": "iphoneos", "PRODUCT_NAME": "$(TARGET_NAME)"]]
    }
    let targetConfig: (String) -> [String: Any] = { name in
        ["guid": "CONFIG-TARGET-\(name)", "name": name, "buildSettings": ["PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.Smoke", "INFOPLIST_FILE": "Smoke/Info.plist"]]
    }
    let target: [String: Any] = [
        "guid": "TARGET-SMOKE",
        "name": "Smoke",
        "type": "standard",
        "productTypeIdentifier": "com.apple.product-type.application",
        "productReference": ["guid": "PRODUCT-SMOKE", "name": "Smoke.app", "type": "product"],
        "buildConfigurations": [targetConfig("Debug"), targetConfig("Release")],
        "buildPhases": [],
        "buildRules": [],
        "dependencies": [],
        "isPackageTarget": "false",
    ]
    let project: [String: Any] = [
        "guid": "PROJECT-SMOKE",
        "path": projectPath,
        "projectDirectory": projectDir,
        "projectName": "Smoke",
        "projectIsPackage": "false",
        "targets": ["TARGET@v11_SMOKE"],
        "groupTree": ["guid": "GROUP-ROOT", "type": "group", "name": "Smoke", "path": "", "sourceTree": "<group>", "children": []],
        "buildConfigurations": [config("Debug"), config("Release")],
        "defaultConfigurationName": "Release",
        "developmentRegion": "en",
    ]
    let workspace: [String: Any] = [
        "guid": "WORKSPACE-SMOKE",
        "name": "Smoke",
        "path": projectPath + "/project.xcworkspace",
        "projects": ["PROJECT@v11_SMOKE"],
    ]
    return [
        ["type": "workspace", "signature": "WORKSPACE@v11_SMOKE", "contents": workspace],
        ["type": "project", "signature": "PROJECT@v11_SMOKE", "contents": project],
        ["type": "target", "signature": "TARGET@v11_SMOKE", "contents": target],
    ]
}

@Suite struct EngineSmokeTests {
    @Test func evaluatesSettingsForIOSApplicationOnThisHost() async throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let pifPath = tmp.path + "/smoke.pif"
        let data = try JSONSerialization.data(withJSONObject: minimalPIF(projectDir: tmp.path + "/Smoke"), options: [.sortedKeys])
        try FileSystem.write(data, to: pifPath)

        let (targets, settings) = try await SwiftBuildEngine.withWorkspace(developerDirectory: developer, pifPath: pifPath, host: .current()) { session in
            (try await session.targets(), try await session.exportedBuildSettings(targetGUID: "TARGET-SMOKE", request: SettingsRequest(configuration: "Debug")))
        }
        #expect(targets.map(\.name) == ["Smoke"])
        #expect(settings["PRODUCT_NAME"] == "Smoke")
        #expect(settings["PLATFORM_NAME"] == "iphoneos")
        #expect(settings["CONFIGURATION"] == "Debug")
        #expect(settings["WRAPPER_EXTENSION"] == "app")
        #expect(settings["PRODUCT_BUNDLE_IDENTIFIER"] == "org.nomac.Smoke")
        #expect(settings["XCODE_PRODUCT_BUILD_VERSION"] == SyntheticDeveloperDirectory.xcodeBuild)
    }

    /// A failure while a session is open must not stop the process: Swift Build traps when a
    /// session is released unclosed (wikipedia's unreadable scheme did that to `nomac verify`).
    @Test func aFailureInsideTheSessionClosesIt() async throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let pifPath = tmp.path + "/smoke.pif"
        try FileSystem.write(try JSONSerialization.data(withJSONObject: minimalPIF(projectDir: tmp.path + "/Smoke"), options: [.sortedKeys]), to: pifPath)
        await #expect(throws: NomacError.self) {
            try await SwiftBuildEngine.withWorkspace(developerDirectory: developer, pifPath: pifPath, host: .current()) { session in
                _ = try await session.exportedBuildSettings(targetGUID: "NO-SUCH-TARGET", request: SettingsRequest(configuration: "Debug"))
            }
        }
        await #expect(throws: NomacError.self) {
            try await SwiftBuildEngine.withWorkspace(developerDirectory: developer, pifPath: tmp.path + "/missing.pif", host: .current()) { _ in }
        }
    }
}
