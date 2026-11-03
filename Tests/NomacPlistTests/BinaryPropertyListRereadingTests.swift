import Foundation
import NomacPlist
import Testing

@Suite struct BinaryPropertyListRereadingTests {
    /// Every object kind Swift Build writes, shared and not, with counts over 14 (an integer
    /// object after the marker) and strings outside ASCII (UTF-16).
    @Test func readsWhatSwiftBuildWrites() throws {
        let value = PropertyListValue.dictionary([
            "duplicates": BinaryPropertyListTests.duplicates,
            "long": .array((0..<20).map { .integer($0 * 1000) }),
            "text": .array([.string("\u{E9}t\u{E9}"), .string("e\u{301}"), .string(String(repeating: "x", count: 300))]),
            "nested": .dictionary(["empty": .dictionary([:]), "list": .array([]), "small": .real(0.5)]),
        ])
        #expect(try BinaryPropertyList.value(from: Array(BinaryPropertyList.swiftBuildData(value)), path: "Info.plist") == value)
        #expect(try BinaryPropertyList.value(from: Array(BinaryPropertyList.foundationData(rereading: value)), path: "Info.plist") == value)
    }

    /// An app-store-connect export of a self-written archive (packaging's `AppStoreExportTests`):
    /// in 23 buckets, `UIRequiredDeviceCapabilities` wraps around past
    /// `CFBundleShortVersionString`'s bucket in the dictionary read from the file; the top
    /// dictionary's copy gives it its bucket back, a nested one keeps the first layout.
    @Test func foundationDataCopiesTheTopDictionary() throws {
        let keys = ["BuildMachineOSBuild", "CFBundleExecutable", "CFBundleIdentifier", "CFBundlePackageType", "CFBundleShortVersionString",
                    "CFBundleSupportedPlatforms", "CFBundleVersion", "DTCompiler", "DTPlatformBuild", "DTPlatformName", "DTPlatformVersion",
                    "DTSDKBuild", "DTSDKName", "DTXcode", "DTXcodeBuild", "MinimumOSVersion", "NSAppTransportSecurity", "UIDeviceFamily",
                    "UIRequiredDeviceCapabilities"]
        let nested = PropertyListValue.dictionary(Dictionary(uniqueKeysWithValues: keys.map { ($0, .boolean(true)) }))
        let plist = PropertyListValue.dictionary(Dictionary(uniqueKeysWithValues: keys.map { ($0, $0 == "NSAppTransportSecurity" ? nested : .string("v")) }))
        let data = try BinaryPropertyList.foundationData(rereading: plist)
        let middle = ["DTPlatformVersion", "CFBundleIdentifier", "DTCompiler", "DTPlatformBuild", "CFBundleVersion", "DTXcodeBuild", "CFBundleExecutable"]
        let rest = ["NSAppTransportSecurity", "DTXcode", "CFBundleSupportedPlatforms", "MinimumOSVersion", "CFBundlePackageType", "BuildMachineOSBuild",
                    "DTPlatformName", "DTSDKBuild", "DTSDKName", "UIDeviceFamily"]
        #expect(BinaryPropertyListTests.topLevelKeys(data) == middle + ["CFBundleShortVersionString"] + rest + ["UIRequiredDeviceCapabilities"])
        #expect(try FoundationHashTable.created(with: keys).keys == middle + ["UIRequiredDeviceCapabilities"] + rest + ["CFBundleShortVersionString"])
        #expect(try BinaryPropertyList.value(from: Array(data), path: "Info.plist") == plist)
    }

    /// Reading a file's objects and writing them again gives the same bytes.
    @Test func readsObjectsAsWritten() throws {
        let data = BinaryPropertyList.swiftBuildData(BinaryPropertyListTests.duplicates)
        let (objects, top) = try BinaryPropertyList.objects(from: Array(data), path: "duplicates")
        #expect(top == 0)
        #expect(BinaryPropertyList.data(objects: objects) == data)
    }

    @Test func refusesOtherFiles() {
        let xml = Array(XMLPropertyList.data(.dictionary([:])))
        #expect(throws: (any Error).self) { try BinaryPropertyList.value(from: xml, path: "Info.plist") }
        var truncated = Array(BinaryPropertyList.swiftBuildData(.array([.string("a")])))
        truncated.removeLast(40)
        #expect(throws: (any Error).self) { try BinaryPropertyList.value(from: truncated, path: "Info.plist") }
    }
}
