import Foundation
import NomacCore
import NomacEnvelope
import NomacProject
import NomacTestSupport
import Testing
@testable import NomacBuild

/// `nomac check`'s `build:` domain on a self-written project shaped as CocoaPods' integration of
/// a React Native app: an xcconfig that sets `PODS_ROOT` and a tool path through it.
@Suite struct BuildDomainTests {
    static let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000003; mainGroup = A00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000010, ); };
        \t\tA00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000040, ); sourceTree = "<group>"; };
        \t\tA00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Release; };
        \t\tA00000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };
        \t\tA00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000011; buildPhases = (); name = App; productType = "com.apple.product-type.application"; };
        \t\tA00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000013, ); defaultConfigurationName = Release; };
        \t\tA00000000000000000000013 = {isa = XCBuildConfiguration; baseConfigurationReference = A00000000000000000000040; buildSettings = {SCRIPT_TOOL = "$(SRCROOT)/tools/run.sh"; }; name = Release; };
        \t\tA00000000000000000000040 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = App.release.xcconfig; sourceTree = "<group>"; };
        \t};
        \trootObject = A00000000000000000000001;
        }
        """

    private func executable(_ bytes: [UInt8], at path: String, mode: Int = 0o755) throws {
        try FileSystem.write(Data(bytes), to: path)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    @Test func reportsSettingsThatNameMachOExecutables() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(Self.project, to: "ios/App.xcodeproj/project.pbxproj")
        try directory.writeExactly("""
            PODS_ROOT = ${SRCROOT}/Pods
            HERMES_CLI_PATH = $(PODS_ROOT)/../../node_modules/hermesc/osx-bin/hermesc
            UNIVERSAL_TOOL = "$(PODS_ROOT)/tools/universal"
            LINUX_TOOL = $(PODS_ROOT)/tools/elf
            CLASS_FILE = $(PODS_ROOT)/tools/Main.class
            NOT_EXECUTABLE = $(PODS_ROOT)/tools/readable
            UNKNOWN = $(SOMEWHERE)/osx-bin/hermesc
            ON_DEVICE[sdk=iphoneos*] = $(PODS_ROOT)/../../node_modules/hermesc/osx-bin/hermesc

            """, to: "ios/App.release.xcconfig")
        let machO: [UInt8] = [0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]
        try executable(machO, at: directory.path + "/node_modules/hermesc/osx-bin/hermesc")
        try executable([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 2], at: directory.path + "/ios/Pods/tools/universal")
        try executable([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0], at: directory.path + "/ios/Pods/tools/elf")
        try executable([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 65], at: directory.path + "/ios/Pods/tools/Main.class")
        try executable(machO, at: directory.path + "/ios/Pods/tools/readable", mode: 0o644)
        try executable(Array("#!/bin/sh\n".utf8), at: directory.path + "/ios/tools/run.sh")

        let scan = try BuildDomain().scan(directory.path + "/ios/App.xcodeproj", options: CheckOptions())
        let xcconfig = directory.path + "/ios/App.release.xcconfig"
        #expect(scan.uses.map(\.file) == [xcconfig, xcconfig])
        #expect(scan.uses.map(\.object) == [
            "HERMES_CLI_PATH = $(PODS_ROOT)/../../node_modules/hermesc/osx-bin/hermesc",
            "UNIVERSAL_TOOL = \"$(PODS_ROOT)/tools/universal\"",
        ])
        let report = CheckReport.make(container: directory.path + "/ios/App.xcodeproj", domains: [BuildDomain()], options: CheckOptions())
        #expect(report.features.map(\.status) == [.unverified])
    }

    /// A script phase that runs a Mach-O executable by its path: wikipedia's "Update Localizations"
    /// (`"$SRCROOT/scripts/localization" "$SRCROOT"`, a macOS build in its repository).
    @Test func reportsScriptPhasesThatRunMachOExecutables() throws {
        let phase = "\t\t" + #"A00000000000000000000020 = {isa = PBXShellScriptBuildPhase; name = "Update Localizations"; shellPath = /bin/sh; "#
            + #"shellScript = "\"$SRCROOT/scripts/localization\" \"$SRCROOT\"\n# tools/commented\ncd . && tools/relative --flag\n"#
            + #"echo tools/argument\n\"${SRCROOT}/tools/run.sh\"\n$(SCRIPT_TOOL)\n"; };"# + "\n"
        let project = Self.project
            .replacingOccurrences(of: "buildPhases = ();", with: "buildPhases = (A00000000000000000000020, );")
            .replacingOccurrences(of: "\t\tA00000000000000000000040 = ", with: phase + "\t\tA00000000000000000000040 = ")
        let directory = try TemporaryDirectory()
        try directory.writeExactly(project, to: "ios/App.xcodeproj/project.pbxproj")
        try directory.writeExactly("", to: "ios/App.release.xcconfig")
        let machO: [UInt8] = [0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]
        for tool in ["scripts/localization", "tools/commented", "tools/relative", "tools/argument"] {
            try executable(machO, at: directory.path + "/ios/" + tool)
        }
        try executable(Array("#!/bin/sh\n".utf8), at: directory.path + "/ios/tools/run.sh")

        let scan = try BuildDomain().scan(directory.path + "/ios/App.xcodeproj", options: CheckOptions())
        #expect(scan.uses.map(\.feature) == ["build:script=mach-o-executable", "build:script=mach-o-executable"])
        #expect(scan.uses.map(\.file) == [directory.path + "/ios/App.xcodeproj/project.pbxproj", directory.path + "/ios/App.xcodeproj/project.pbxproj"])
        #expect(scan.uses.map(\.object) == ["App: Update Localizations: $SRCROOT/scripts/localization", "App: Update Localizations: tools/relative"])
    }

    /// The operating system's and Xcode's tools are no project's own, though on a Mac they are
    /// Mach-O files (`/bin/sh`, the expo workstream's report).
    @Test func leavesOutTheSystemsTools() {
        #expect(BuildDomain.scriptMachOExecutables("/bin/sh \"$SRCROOT/run.sh\"\n/usr/bin/true\nexec /usr/libexec/PlistBuddy -c x\n", levels: [], directory: "/") == [])
        for path in ["/bin/sh", "/usr/bin/env", "/usr/libexec/PlistBuddy", "/System/Library/Frameworks/X.framework/X",
                     "/Applications/Xcode_27.app/Contents/Developer/usr/bin/actool"] {
            #expect(BuildDomain.isProvidedBySystem(path), "\(path)")
        }
        #expect(!BuildDomain.isProvidedBySystem("/src/app/scripts/localization"))
    }

    /// Native Node modules beside the project (expo-default's `lightningcss-darwin-arm64`), and a
    /// Swift macro plugin named in OTHER_SWIFT_FLAGS (its pods' `ExpoModulesMacros`).
    @Test func reportsMacOSOnlyNodeModulesAndMacroPlugins() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(Self.project, to: "ios/App.xcodeproj/project.pbxproj")
        try directory.writeExactly("""
            PODS_ROOT = ${SRCROOT}/Pods
            OTHER_SWIFT_FLAGS = $(inherited) -D COCOAPODS -load-plugin-executable "${PODS_ROOT}/../../node_modules/macros/apple/Macros#Macros"

            """, to: "ios/App.release.xcconfig")
        let machO: [UInt8] = [0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]
        let elf: [UInt8] = [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0]
        try executable(machO, at: directory.path + "/node_modules/macros/apple/Macros")
        try directory.writeExactly(#"{"name": "macros", "optionalDependencies": {"macros-linux-arm64": "1.0.0", "macros-win32-x64": "1.0.0"}}"#,
                                   to: "node_modules/macros/package.json")
        try directory.writeExactly(#"{"name": "plain"}"#, to: "node_modules/plain/package.json")
        try executable(machO, at: directory.path + "/node_modules/plain/build/Release/plain.node", mode: 0o644)
        try directory.writeExactly(#"{"name": "fat"}"#, to: "node_modules/fat/package.json")
        try executable(machO, at: directory.path + "/node_modules/fat/prebuilds/darwin-arm64/fat.node", mode: 0o644)
        try executable(elf, at: directory.path + "/node_modules/fat/prebuilds/linux-arm64/fat.node", mode: 0o644)
        try directory.writeExactly(#"{"name": "css", "optionalDependencies": {"css-darwin-arm64": "1.0.0", "css-linux-arm64-gnu": "1.0.0", "css-linux-arm64-musl": "1.0.0"}}"#,
                                   to: "node_modules/css/package.json")
        try directory.writeExactly(#"""
            {"packages": {"": {}, "node_modules/css-darwin-arm64": {"os": ["darwin"]},
             "node_modules/css-linux-arm64-gnu": {"os": ["linux"], "cpu": ["arm64"], "libc": ["glibc"]},
             "node_modules/css-linux-arm64-musl": {"os": ["linux"], "cpu": ["arm64"], "libc": ["musl"]},
             "node_modules/macros-linux-arm64": {"os": ["linux"], "cpu": ["arm64"], "libc": ["glibc"]},
             "node_modules/macros-win32-x64": {"os": ["win32"], "cpu": ["x64"]}}}
            """#, to: "package-lock.json")
        try directory.writeExactly(#"{"name": "css-darwin-arm64", "os": ["darwin"], "cpu": ["arm64"]}"#, to: "node_modules/css-darwin-arm64/package.json")
        try executable(machO, at: directory.path + "/node_modules/css-darwin-arm64/css.darwin-arm64.node", mode: 0o644)

        func uses() throws -> [String] {
            try BuildDomain().scan(directory.path + "/ios/App.xcodeproj", options: CheckOptions()).uses.map { "\($0.feature) \($0.object)" }
        }
        let found = try uses()
        #expect(found == [
            "build:node-module=mach-o-only package css-darwin-arm64; Linux packages: css-linux-arm64-gnu",
            "build:node-module=mach-o-only package plain",
            "build:setting=mach-o-executable OTHER_SWIFT_FLAGS = -load-plugin-executable ${PODS_ROOT}/../../node_modules/macros/apple/Macros#Macros; Linux packages: macros-linux-arm64",
        ])
        try executable(elf, at: directory.path + "/node_modules/macros-linux-arm64/Macros")
        #expect(try uses().filter { $0.hasPrefix("build:setting") } == [
            "build:setting=mach-o-executable OTHER_SWIFT_FLAGS = -load-plugin-executable ${PODS_ROOT}/../../node_modules/macros/apple/Macros#Macros; Linux build: ../node_modules/macros-linux-arm64/Macros",
        ])
        try directory.writeExactly(#"{"name": "css-linux-arm64-gnu", "os": ["linux"], "cpu": ["arm64"]}"#, to: "node_modules/css-linux-arm64-gnu/package.json")
        try executable(elf, at: directory.path + "/node_modules/css-linux-arm64-gnu/css.linux-arm64-gnu.node", mode: 0o644)
        #expect(try uses().filter { $0.hasPrefix("build:node-module") } == ["build:node-module=mach-o-only package plain"])
        let report = CheckReport.make(container: directory.path + "/ios/App.xcodeproj", domains: [BuildDomain()], options: CheckOptions())
        #expect(report.text().contains("../node_modules/plain/build/Release/plain.node: package plain"))
        try directory.writeExactly("// swift-tools-version: 6.0\n", to: "node_modules/macros/apple/Package.swift")
        #expect(try uses().filter { $0.contains("Macros#Macros") } == [
            "build:macro-plugin=swift-package OTHER_SWIFT_FLAGS = -load-plugin-executable ${PODS_ROOT}/../../node_modules/macros/apple/Macros#Macros; package: ../node_modules/macros/apple/Package.swift",
        ])
        let withPackage = CheckReport.make(container: directory.path + "/ios/App.xcodeproj", domains: [BuildDomain()], options: CheckOptions())
        #expect(withPackage.features.first { $0.id == "build:macro-plugin=swift-package" }?.status == .verified)
    }

    /// The plugin flags passed through the Swift driver, each after `-Xfrontend`.
    @Test func reportsMacroPluginsPassedToTheFrontend() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(Self.project, to: "ios/App.xcodeproj/project.pbxproj")
        try directory.writeExactly("""
            PODS_ROOT = ${SRCROOT}/Pods
            OTHER_SWIFT_FLAGS = $(inherited) -Xfrontend -load-plugin-executable -Xfrontend "${PODS_ROOT}/../../node_modules/macros/Macros#Macros"

            """, to: "ios/App.release.xcconfig")
        try executable([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01], at: directory.path + "/node_modules/macros/Macros")

        let scan = try BuildDomain().scan(directory.path + "/ios/App.xcodeproj", options: CheckOptions())
        #expect(scan.uses.map { "\($0.feature) \($0.object)" } == [
            "build:setting=mach-o-executable OTHER_SWIFT_FLAGS = -load-plugin-executable ${PODS_ROOT}/../../node_modules/macros/Macros#Macros",
        ])
    }

    @Test func expandsNamesAsXcodeWritesThem() {
        let values = ["A": "/root", "B": "$(A)/b", "C": "${B}/c"]
        #expect(BuildDomain.expand("$(C)/d", lookup: { values[$0] }) == "/root/b/c/d")
        #expect(BuildDomain.expand("$A/x $(inherited)", lookup: { values[$0] }) == "/root/x ")
        #expect(BuildDomain.expand("$(A:dir)", lookup: { values[$0] }) == nil)
        #expect(BuildDomain.expand("$(MISSING)/x", lookup: { values[$0] }) == nil)
        #expect(BuildDomain.expand("$(LOOP)", lookup: { _ in "$(LOOP)" }) == nil)
    }

    /// Run-script phases and the scripts they call (ADR 0183, script_phase_survey.py); a phase
    /// another program than a shell runs is reported, not read.
    @Test func reportsWhatScriptPhasesNeedFromMacOS() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly("""
            // !$*UTF8*$!
            {
            \tarchiveVersion = 1;
            \tobjectVersion = 77;
            \tobjects = {
            \t\tA00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000003; mainGroup = A00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000010, ); };
            \t\tA00000000000000000000002 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            \t\tA00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Release; };
            \t\tA00000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };
            \t\tA00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000003; buildPhases = (A00000000000000000000020, A00000000000000000000021, ); name = App; productType = "com.apple.product-type.application"; };
            \t\tA00000000000000000000020 = {isa = PBXShellScriptBuildPhase; name = "Stamp"; shellPath = /bin/sh; shellScript = "# osascript is only mentioned here\\ndefaults write \\"${BUILT_PRODUCTS_DIR}/Info\\" Commit abc\\n\\"${SRCROOT}/scripts/tools.sh\\"\\n"; };
            \t\tA00000000000000000000021 = {isa = PBXShellScriptBuildPhase; name = "Python"; shellPath = /usr/bin/python3; shellScript = "import os\\nos.system('osascript')\\n"; };
            \t};
            \trootObject = A00000000000000000000001;
            }
            """, to: "App.xcodeproj/project.pbxproj")
        try directory.writeExactly("#!/bin/bash\nif [ \"$(uname -m)\" = arm64 ]; then tool=mac; fi\nsed -i '' 's/a/b/' file\n/usr/libexec/PlistBuddy -c 'Print :X' Info.plist\nv=$(sw_vers -productVersion || echo 0)\n",
                                   to: "scripts/tools.sh")
        let uses = try BuildDomain().scan(directory.path + "/App.xcodeproj", options: CheckOptions()).uses.filter { $0.feature.contains("script") }
        #expect(uses.map(\.feature) == ["build:script-command=defaults", "build:script-command=sw_vers", "build:script-interpreter=python3",
                                        "build:script=machine-architecture", "build:script=sed-in-place-bsd"])
        #expect(uses[2].object == "phase 'Python': shell /usr/bin/python3")
        #expect(BuildDomain.envelope.entry(for: "build:script-interpreter=ruby")?.status == .unverified)
        #expect(uses[1].object == "script: line 5: v=$(sw_vers -productVersion || echo 0); its failure is hidden by `||`, so a Linux build goes on without its result")
        #expect(uses.first?.object == "phase 'Stamp': line 2: defaults write \"${BUILT_PRODUCTS_DIR}/Info\" Commit abc")
        #expect(uses.last?.file == directory.path + "/scripts/tools.sh")
    }

    /// A phase that runs a package's script found by name in `node_modules` (Expo's bundling
    /// phase with Sentry), which runs `sentry-cli react-native xcode`.
    @Test func reportsSentryCLIsReactNativeXcode() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(#"""
            // !$*UTF8*$!
            {
            archiveVersion = 1;
            objectVersion = 77;
            objects = {
            A00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000003; mainGroup = A00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000010, ); };
            A00000000000000000000002 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            A00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Release; };
            A00000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };
            A00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000003; buildPhases = (A00000000000000000000020, ); name = App; productType = "com.apple.product-type.application"; };
            A00000000000000000000020 = {isa = PBXShellScriptBuildPhase; name = "Bundle React Native code and images"; shellPath = /bin/sh; shellScript = "/bin/sh `\"$NODE_BINARY\" --print \"require('path').dirname(require.resolve('@sentry/react-native/package.json')) + '/scripts/sentry-xcode.sh'\"`\n"; };
            };
            rootObject = A00000000000000000000001;
            }
            """#, to: "ios/App.xcodeproj/project.pbxproj")
        try directory.writeExactly("#!/bin/bash\nREACT_NATIVE_XCODE_WITH_SENTRY=\"\\\"$SENTRY_CLI_EXECUTABLE\\\" react-native xcode $ARGS \\\"$REACT_NATIVE_XCODE\\\"\"\n",
                                   to: "node_modules/@sentry/react-native/scripts/sentry-xcode.sh")
        let script = "node_modules/@sentry/react-native/scripts/sentry-xcode.sh"
        let scan = try BuildDomain().scan(directory.path + "/ios/App.xcodeproj", options: CheckOptions())
        #expect(scan.uses.filter { $0.feature == ScriptRequirements.sentryReactNativeXcode }.map(\.file) == [directory.path + "/" + script])
        #expect(scan.uses.filter { $0.feature == ProjectFixes.sentryAutoUpload.feature }.isEmpty)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/ios/App.xcodeproj")
        #expect(!ScriptRequirements.runs(ProjectFixes.sentryAutoUpload.feature, in: workspace))

        try directory.writeExactly("#!/bin/bash\nWITH_SENTRY=\"\\\"$SENTRY_CLI_EXECUTABLE\\\" react-native xcode \\\"$REACT_NATIVE_XCODE\\\"\"\nif [ \"$SENTRY_DISABLE_AUTO_UPLOAD\" == true ]; then exit 0; fi\n",
                                   to: script)
        let fixed = try BuildDomain().scan(directory.path + "/ios/App.xcodeproj", options: CheckOptions())
        #expect(fixed.uses.filter { $0.feature == ScriptRequirements.sentryReactNativeXcode }.isEmpty)
        #expect(fixed.uses.filter { $0.feature == ProjectFixes.sentryAutoUpload.feature }.map(\.file) == [directory.path + "/" + script])
        #expect(ScriptRequirements.runs(ProjectFixes.sentryAutoUpload.feature, in: workspace))

        var overrides: [String: String] = [:], synthesized: [String: String] = [:]
        let run = try ProjectFixRun(workspace: workspace, commandLine: [:], scratch: directory.path + "/scratch", overrides: &overrides, synthesized: &synthesized)
        #expect(synthesized[ScriptRequirements.sentryUploadSwitch] == "true")
        #expect(run.summary().contains { $0.contains("sentry-auto-upload") })
        var chosen: [String: String] = [:]
        let told = try ProjectFixRun(workspace: workspace, commandLine: [ScriptRequirements.sentryUploadSwitch: "false"], scratch: directory.path + "/scratch",
                                     overrides: &overrides, synthesized: &chosen)
        #expect(chosen[ScriptRequirements.sentryUploadSwitch] == nil)
        #expect(!told.summary().contains { $0.contains("sentry-auto-upload") })
    }

    /// Xcode 27.0 fails a target older than its SDK's minimum (a self-written library at 12.0 and 14.9).
    @Test func reportsDeploymentTargetsBelowTheSDKsMinimum() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly("""
            // !$*UTF8*$!
            {
            \tarchiveVersion = 1;
            \tobjectVersion = 77;
            \tobjects = {
            \t\tA00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000003; mainGroup = A00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000010, A00000000000000000000011, A00000000000000000000012, ); };
            \t\tA00000000000000000000002 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            \t\tA00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Release; };
            \t\tA00000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 15; MACOSX_DEPLOYMENT_TARGET = 10.13; }; name = Release; };
            \t\tA00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000020; buildPhases = (); name = Old; productType = "com.apple.product-type.library.static"; };
            \t\tA00000000000000000000011 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000021; buildPhases = (); name = Current; productType = "com.apple.product-type.library.static"; };
            \t\tA00000000000000000000012 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000022; buildPhases = (); name = Mac; productType = "com.apple.product-type.library.static"; };
            \t\tA00000000000000000000020 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000030, ); defaultConfigurationName = Release; };
            \t\tA00000000000000000000021 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000031, ); defaultConfigurationName = Release; };
            \t\tA00000000000000000000022 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000032, ); defaultConfigurationName = Release; };
            \t\tA00000000000000000000030 = {isa = XCBuildConfiguration; buildSettings = {IPHONEOS_DEPLOYMENT_TARGET = 14.9; }; name = Release; };
            \t\tA00000000000000000000031 = {isa = XCBuildConfiguration; buildSettings = {}; name = Release; };
            \t\tA00000000000000000000032 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 12.0; }; name = Release; };
            \t};
            \trootObject = A00000000000000000000001;
            }
            """, to: "Pods.xcodeproj/project.pbxproj")
        let uses = try BuildDomain().scan(directory.path + "/Pods.xcodeproj", options: CheckOptions()).uses.filter { $0.feature == BuildDomain.deploymentTargetBelowMinimum }
        #expect(uses.map(\.object) == ["Old (Release): IPHONEOS_DEPLOYMENT_TARGET = 14.9, minimum 15.0"])
    }
}
