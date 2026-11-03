import Testing
import NomacSDK

@Suite struct XcodeSubsetTests {
    let subset = XcodeSubset(payloadPlatforms: ["iPhoneOS"])

    private func decide(_ path: String, directory: Bool = false) -> XcodeSubset.Decision {
        subset.decide(path.split(separator: "/").map(String.init), isDirectory: directory)
    }

    @Test func keepsXcodeVersionMetadata() {
        #expect(decide("Contents/version.plist") == .keep)
        #expect(decide("Contents/Info.plist") == .keep)
        #expect(decide("Contents/MacOS", directory: true) == .skip)
        #expect(decide("Contents/Applications", directory: true) == .skip)
    }

    @Test func keepsTheDeviceTraitsOfPayloadPlatforms() {
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/usr", directory: true) == .descend)
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/usr/standalone", directory: true) == .descend)
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/usr/standalone/device_traits.db") == .keep)
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/usr/bin", directory: true) == .skip)
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/usr/standalone/other.db") == .skip)
        #expect(decide("Contents/Developer/Platforms/AppleTVOS.platform/usr", directory: true) == .skip)
    }

    @Test func keepsMetadataOfEveryPlatform() {
        for platform in ["iPhoneOS", "iPhoneSimulator", "MacOSX", "WatchOS", "XROS", "AppleTVOS", "DriverKit"] {
            #expect(decide("Contents/Developer/Platforms/\(platform).platform/Info.plist") == .keep)
            #expect(decide("Contents/Developer/Platforms/\(platform).platform/version.plist") == .keep)
        }
    }

    @Test func keepsFullSDKOnlyForPayloadPlatforms() {
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk", directory: true) == .keep)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk", directory: true) == .descend)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/SDKSettings.json") == .keep)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/SDKSettings.plist") == .keep)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/CoreServices/SystemVersion.plist") == .keep)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library", directory: true) == .descend)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks", directory: true) == .skip)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr", directory: true) == .descend)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr/include", directory: true) == .skip)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr/lib/libobjc.tbd") == .keep)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr/lib/libobjc.A.tbd") == .keep)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr/lib/libz.tbd") == .skip)
    }

    @Test func keepsSDKSymbolicLinks() {
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk", directory: false) == .keep)
    }

    @Test func keepsTestingFrameworksOnlyForPayloadPlatforms() {
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks", directory: true) == .keep)
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/PrivateFrameworks", directory: true) == .keep)
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/Developer/usr/lib", directory: true) == .keep)
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin", directory: true) == .skip)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks", directory: true) == .skip)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib", directory: true) == .skip)
    }

    @Test func keepsTestingBinariesOfEveryPlatform() {
        let frameworks = "Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"
        #expect(decide(frameworks, directory: true) == .descend)
        #expect(decide("\(frameworks)/XCTest.framework", directory: true) == .descend)
        #expect(decide("\(frameworks)/XCTest.framework/XCTest") == .keep)
        #expect(decide("\(frameworks)/XCTest.framework/Versions", directory: true) == .descend)
        #expect(decide("\(frameworks)/XCTest.framework/Versions/Current") == .keep)
        #expect(decide("\(frameworks)/XCTest.framework/Versions/A", directory: true) == .descend)
        #expect(decide("\(frameworks)/XCTest.framework/Versions/A/XCTest") == .keep)
        #expect(decide("\(frameworks)/XCTest.framework/Versions/A/Resources", directory: true) == .skip)
        #expect(decide("\(frameworks)/XCTest.framework/Headers", directory: true) == .skip)
        #expect(decide("\(frameworks)/XCTest.framework/Modules", directory: true) == .skip)
        #expect(decide("\(frameworks)/Testing.framework/Testing") == .keep)
        #expect(decide("\(frameworks)/XCUIAutomation.framework", directory: true) == .skip)
        #expect(decide("Contents/Developer/Platforms/XROS.platform/Developer/Library/Frameworks/Testing.framework/Testing") == .keep)
    }

    @Test func keepsToolchainMetadataAndPerPlatformRuntimes() {
        let toolchain = "Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
        #expect(decide("\(toolchain)/ToolchainInfo.plist") == .keep)
        #expect(decide("\(toolchain)/usr/bin", directory: true) == .skip)
        #expect(decide("\(toolchain)/usr/lib/clang", directory: true) == .keep)
        #expect(decide("\(toolchain)/usr/lib/arc", directory: true) == .keep)
        #expect(decide("\(toolchain)/usr/lib/swift", directory: true) == .descend)
        #expect(decide("\(toolchain)/usr/lib/swift/iphoneos", directory: true) == .keep)
        #expect(decide("\(toolchain)/usr/lib/swift/macosx", directory: true) == .skip)
        #expect(decide("\(toolchain)/usr/lib/swift/clang") == .keep)
        #expect(decide("\(toolchain)/usr/lib/swift/apinotes", directory: true) == .keep)
        #expect(decide("\(toolchain)/usr/lib/swift_static/iphoneos", directory: true) == .keep)
        #expect(decide("\(toolchain)/usr/lib/sourcekitd.framework", directory: true) == .skip)
        #expect(decide("\(toolchain)/usr/share", directory: true) == .descend)
        #expect(decide("\(toolchain)/usr/share/swift/SwiftConstantValues", directory: true) == .keep)
        #expect(decide("\(toolchain)/usr/share/man", directory: true) == .skip)
    }

    @Test func keepsMessagesStubsOnlyForPayloadPlatforms() {
        let support = "Contents/Developer/Platforms/iPhoneOS.platform/Library/Application Support"
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/Library", directory: true) == .descend)
        #expect(decide(support, directory: true) == .descend)
        #expect(decide(support + "/MessagesApplicationExtensionStub", directory: true) == .keep)
        #expect(decide(support + "/MessagesApplicationStub", directory: true) == .keep)
        #expect(decide(support + "/Other", directory: true) == .skip)
        #expect(decide("Contents/Developer/Platforms/iPhoneOS.platform/Library/Other", directory: true) == .skip)
        #expect(decide("Contents/Developer/Platforms/MacOSX.platform/Library/Application Support/MessagesApplicationStub", directory: true) == .skip)
    }

    @Test func keepsTheAppShortcutsPhraseLists() {
        let framework = "Contents/Frameworks/SiriSSUKitModel.framework"
        #expect(decide("Contents/Frameworks", directory: true) == .descend)
        #expect(decide(framework + "/Resources") == .keep)
        #expect(decide(framework + "/Versions/Current") == .keep)
        #expect(decide(framework + "/Versions/A/Resources", directory: true) == .descend)
        #expect(decide(framework + "/Versions/A/Resources/prefix", directory: true) == .keep)
        #expect(decide(framework + "/Versions/A/Resources/standardAppShortcutNegatives", directory: true) == .keep)
        #expect(decide(framework + "/Versions/A/Resources/en.lproj", directory: true) == .skip)
        #expect(decide(framework + "/Versions/A/SiriSSUKitModel") == .skip)
        #expect(decide("Contents/Frameworks/IDEFoundation.framework", directory: true) == .skip)
    }

    /// An iOS app's watch app builds with the watchOS SDK and Swift runtime, so the default
    /// payload has them (home-assistant, pocket-casts).
    @Test func defaultPayloadHasWatchOS() {
        let subset = XcodeSubset()
        let toolchain = "Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
        #expect(subset.decide(toolchain.split(separator: "/").map(String.init) + ["usr", "lib", "swift", "watchos"], isDirectory: true) == .keep)
        #expect(subset.decide(toolchain.split(separator: "/").map(String.init) + ["usr", "lib", "swift", "iphoneos"], isDirectory: true) == .keep)
        #expect(subset.decide(toolchain.split(separator: "/").map(String.init) + ["usr", "lib", "swift", "appletvos"], isDirectory: true) == .skip)
    }

    @Test func skipsEverythingElseInDeveloper() {
        #expect(decide("Contents/Developer/usr", directory: true) == .skip)
        #expect(decide("Contents/Developer/Library", directory: true) == .skip)
        #expect(decide("Contents/Developer/Applications", directory: true) == .skip)
        #expect(decide("Contents/SharedFrameworks", directory: true) == .skip)
    }
}
