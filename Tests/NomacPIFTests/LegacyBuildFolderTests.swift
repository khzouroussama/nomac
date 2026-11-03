import NomacPIF
import NomacProject
import Testing

/// envelope-experiments `unresolved-proxies`: the folder whose product paths Xcode hashes for
/// the build files of reference proxies whose product it does not find.
@Suite struct LegacyBuildFolderTests {
    static func folder(_ settings: [String: String] = [:], xcconfig: [String: String] = [:], configuration: String = "Debug",
                       projectDirectory: String = "/p") -> String? {
        let own = settings.sorted { $0.key < $1.key }.map { XCConfigFile.Assignment(name: $0.key, conditions: [:], value: $0.value) }
        let base = xcconfig.sorted { $0.key < $1.key }.map { XCConfigFile.Assignment(name: $0.key, conditions: [:], value: $0.value) }
        return LegacyBuildFolder.path(projectDirectory: projectDirectory, configuration: configuration, levels: [own, base])
    }

    @Test func debugElseTheFirstConfiguration() {
        #expect(LegacyBuildFolder.configuration(among: ["Release", "Debug"]) == "Debug")
        #expect(LegacyBuildFolder.configuration(among: ["Alpha", "Beta"]) == "Alpha")
        #expect(Self.folder(["SDKROOT": "iphoneos"], configuration: "Alpha") == "/p/build/Alpha-iphoneos")
    }

    @Test func theSDKNamesThePlatform() {
        #expect(Self.folder(["SDKROOT": "iphoneos"]) == "/p/build/Debug-iphoneos")
        #expect(Self.folder(["SDKROOT": "iphonesimulator"]) == "/p/build/Debug-iphonesimulator")
        #expect(Self.folder(["SDKROOT": "appletvos"]) == "/p/build/Debug-appletvos")
        #expect(Self.folder(["SDKROOT": "watchos"]) == "/p/build/Debug-watchos")
        #expect(Self.folder(["SDKROOT": "xros"]) == "/p/build/Debug-xros")
        #expect(Self.folder(["SDKROOT": "macosx"]) == "/p/build/Debug")
        #expect(Self.folder() == "/p/build/Debug")
        #expect(Self.folder(["SDKROOT": "driverkit"]) == nil)
    }

    @Test func locationSettingsApply() {
        #expect(Self.folder(["SDKROOT": "iphoneos", "SYMROOT": "$(PROJECT_DIR)/Out"]) == "/p/Out/Debug-iphoneos")
        #expect(Self.folder(["SDKROOT": "iphoneos", "SYMROOT": "Rel"]) == "/p/Rel/Debug-iphoneos")
        #expect(Self.folder(["SDKROOT": "iphoneos", "SYMROOT": "../Up"], projectDirectory: "/p/Deeper") == "/p/Up/Debug-iphoneos")
        #expect(Self.folder(["SDKROOT": "iphoneos", "SYMROOT": "${PROJECT_DIR}/Braces"]) == "/p/Braces/Debug-iphoneos")
        #expect(Self.folder(["SDKROOT": "iphoneos", "SYMROOT": "/tmp/out"]) == "/tmp/out/Debug-iphoneos")
        #expect(Self.folder(["SDKROOT": "iphoneos", "SYMROOT": "$(SRCROOT)/S"], projectDirectory: "/p/Code") == "/p/Code/S/Debug-iphoneos")
        #expect(Self.folder(["SDKROOT": "iphoneos", "BUILD_DIR": "RelBD"]) == "/p/RelBD/Debug-iphoneos")
        #expect(Self.folder(["SDKROOT": "iphoneos", "CONFIGURATION_BUILD_DIR": "$(PROJECT_DIR)/Products"]) == "/p/Products")
        #expect(Self.folder(["SDKROOT": "iphoneos", "CONFIGURATION_BUILD_DIR": "RelCBD"]) == "/p/RelCBD")
    }

    @Test func theConfigurationOutranksItsXCConfig() {
        #expect(Self.folder(["SDKROOT": "iphoneos"], xcconfig: ["SYMROOT": "$(SRCROOT)/FromConfig"]) == "/p/FromConfig/Debug-iphoneos")
        #expect(Self.folder(["SDKROOT": "iphoneos", "SYMROOT": "Own"], xcconfig: ["SYMROOT": "FromConfig"]) == "/p/Own/Debug-iphoneos")
    }

    @Test func pathsAreDecomposed() {
        #expect(Self.folder(projectDirectory: "/p/Caf\u{E9}") == "/p/Cafe\u{301}/build/Debug")
    }

    @Test func otherFormsAreNotComputed() {
        let conditional = [XCConfigFile.Assignment(name: "SYMROOT", conditions: ["sdk": "iphoneos*"], value: "Out")]
        #expect(LegacyBuildFolder.path(projectDirectory: "/p", configuration: "Debug", levels: [conditional, []]) == nil)
        #expect(Self.folder(["SYMROOT": "$(HOME)/build"]) == nil)
        #expect(Self.folder(["SYMROOT": "$(inherited)"]) == nil)
        #expect(Self.folder(["SYMROOT": "$PROJECT_DIR/build"]) == nil)
        #expect(LegacyBuildFolder.path(projectDirectory: "/p", configuration: "Debug", settings: ["SYMROOT": nil], xcconfig: nil) == nil)
    }
}
