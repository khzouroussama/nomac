import NomacCore
import Testing
@testable import NomacPackages

/// The name of the swift-syntax prebuilts Xcode 27.0's PIF builds macro targets against
/// (`SourcePackages/prebuilts/swift-syntax/<version>/swiftlang-6.4.0.34.1-macosx27.0-MacroSupport`,
/// `macro_plugin_experiments.py` macro-package and firefox's reference).
@Suite struct PrebuiltsTests {
    @Test func namesPrebuiltsAsXcodesToolchainDoes() {
        #expect(SwiftPackages.xcodePrebuiltName() == "swiftlang-6.4.0.34.1-macosx27.0")
    }
}
