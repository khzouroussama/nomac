import Testing
@testable import NomacBuild

/// The settings that make swift.org's compilers do what Xcode's do unasked: load cross-import
/// overlays (B-154), follow Clang 4's C++ ABI and call the unsized `operator delete` in the Clang
/// importer, search the toolchain's
/// `usr/include` (`<swift/bridging>`), and accept C++ types in library-evolution modules.
@Suite struct LinuxCompilerTests {
    @Test func addsWhatXcodesCompilersDoUnasked() {
        let swiftFlags = "-Xfrontend -enable-cross-import-overlays -enable-experimental-feature AssumeResilientCxxTypes -Xcc -fclang-abi-compat=4.0 -Xcc -fno-sized-deallocation -Xcc -idirafter -Xcc $(TOOLCHAIN_DIR)/usr/include"
        var overrides: [String: String] = [:]
        var synthesized: [String: String] = [:]
        LinuxCompiler.apply(to: &overrides, synthesized: &synthesized)
        #expect(overrides.isEmpty)
        #expect(synthesized == ["OTHER_SWIFT_FLAGS": "$(inherited) " + swiftFlags,
                                "OTHER_SWIFT_FLAGS[sdk=linux*]": "$(inherited) -resource-dir $(TOOLCHAIN_DIR)/usr/lib/nomac/swift -I $(TOOLCHAIN_DIR)/usr/lib/nomac/modules -Xfrontend -import-module -Xfrontend NomacHostFoundation",
                                "OTHER_CFLAGS": "$(inherited) -idirafter $(TOOLCHAIN_DIR)/usr/include",
                                "OTHER_CPLUSPLUSFLAGS": "$(inherited) -fno-sized-deallocation"])

        var commandLine = ["OTHER_SWIFT_FLAGS": "-DNOMAC", "OTHER_CFLAGS": "-DC", "OTHER_CPLUSPLUSFLAGS": "-DCXX"]
        var none: [String: String] = [:]
        LinuxCompiler.apply(to: &commandLine, synthesized: &none)
        #expect(commandLine == ["OTHER_SWIFT_FLAGS": "-DNOMAC " + swiftFlags,
                                "OTHER_SWIFT_FLAGS[sdk=linux*]": "$(inherited) -resource-dir $(TOOLCHAIN_DIR)/usr/lib/nomac/swift -I $(TOOLCHAIN_DIR)/usr/lib/nomac/modules -Xfrontend -import-module -Xfrontend NomacHostFoundation",
                                "OTHER_CFLAGS": "-DC -idirafter $(TOOLCHAIN_DIR)/usr/include",
                                "OTHER_CPLUSPLUSFLAGS": "-DCXX -fno-sized-deallocation"])
        #expect(none.isEmpty)
    }
}
