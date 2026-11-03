import Foundation
import NomacCore

/// What Xcode's Swift compiler does unasked and swift.org's only when asked.
public enum LinuxCompiler {
    /// Xcode 27.0's compiler loads cross-import overlays (`_SwiftData_SwiftUI`, which declares
    /// `@Query`) though its driver passes no flag, for iOS and macOS alike, and with
    /// `-Xfrontend -disable-cross-import-overlays` fails on `@Query` as swift.org's does
    /// (`.github/scripts/cross_import_experiments.py`); swift.org 6.4.0's frontend loads them only
    /// with `-enable-cross-import-overlays` (B-154). The flag goes to the driver, whose dependency
    /// scan, in Swift Build's process, must find the overlays too.
    public static let crossImportOverlays = "-Xfrontend -enable-cross-import-overlays"

    /// The compiles for the build machine itself (Linux targets: macro and host tool packages) get
    /// the toolchain's resource directory that has swift.org's headers
    /// (``LinuxToolchain/hostResourceDirectory``), and import ``HostFoundationModule``, which
    /// loads Foundation as a Mac's swift-syntax does.
    public static let hostCompiles = "-resource-dir $(TOOLCHAIN_DIR)/usr/" + LinuxToolchain.hostResourceDirectory
        + " -I $(TOOLCHAIN_DIR)/usr/" + HostFoundationModule.relativeDirectory + " -Xfrontend -import-module -Xfrontend " + HostFoundationModule.name

    /// Xcode 27.0's clang, and its Swift compiler's Clang importer, search the toolchain's
    /// `usr/include` after the SDK's `usr/include` (`-v` for an iOS compile); swift.org 6.4.0's do
    /// not, so C++ interoperability's `<swift/bridging>`, which the toolchain keeps there
    /// (``LinuxToolchain/copiedDirectories``), is not found (expo-default's ExpoModulesJSI).
    public static let toolchainHeaders = "-idirafter $(TOOLCHAIN_DIR)/usr/include"
    /// swift.org 6.4.0's compiler rejects a C++ type other than a C-like struct (declared `class`,
    /// or with a member function or constructor) in the public API of a library-evolution module
    /// ("C++ types from imported module '__ObjC' do not support library evolution",
    /// expo-default's ExpoModulesJSI); Xcode 27.0's accepts it, and so does swift.org's with this
    /// feature. In Xcode's compiler the feature changes no symbol or section, but a
    /// library-evolution module's interface lists it in `swift-module-flags` (docs/formats/build.md
    /// "C++ types in library-evolution modules").
    public static let resilientCxxTypes = "-enable-experimental-feature AssumeResilientCxxTypes"
    /// Xcode 27.0's clang calls the unsized `operator delete(void *)` at every iOS deployment
    /// target and C++ standard; swift.org 6.4.0's calls the sized one (`__ZdlPvm`), and the unsized
    /// one with this flag (expo-default's RNReanimated). So do their Swift compilers' Clang
    /// importers, for the C++ Swift code instantiates (`clang_abi_experiments.py`'s interop source;
    /// expo-default's nested ExpoModulesJSI).
    public static let unsizedDeallocation = "-fno-sized-deallocation"
    /// Xcode 27.0's clang and its Swift compiler's Clang importer follow Clang 4's C++ ABI unasked:
    /// at every target, their output is that of `-fclang-abi-compat=4.0` and differs from every later
    /// level in template argument mangling (`Node<Name>`: `XadL_Z4NameE` for swift.org 6.4.0's
    /// `XadsoKcL_Z4NameEE`), record layout and argument passing
    /// (docs/formats/build.md "Clang's C++ ABI"). swift.org's clang gets it from
    /// ``LinuxToolchain/clangConfiguration``, which the Clang importer of swift-frontend reads too;
    /// the Swift compiles also ask for it, because without it they could not load the SDK's modules
    /// built for them (rn-bare on Linux: "version of Clang that we should attempt to be
    /// ABI-compatible with differs in precompiled file").
    public static let clangABI = "-fclang-abi-compat=4.0"
    /// What Xcode 27.0's driver passes for every Apple target and C-family language and swift.org
    /// 6.4.0's does not: C tentative definitions as common symbols (`-fcommon`; without it lld
    /// reports one defined in two files as a duplicate) and return values that may be undefined
    /// (`-fno-strict-return`, no `noundef` on them). It passes neither for Linux targets, and a
    /// command line's `-fno-common` or `-fstrict-return` wins (docs/formats/build.md "Clang's driver").
    /// Xcode's clang was also built for a linker version (``XcodeTools/clangLinkerVersion``, 1166.2), which it
    /// gives every compile (`-target-linker-version 1166.2`) and which turns its `objc_msgSend$<selector>` calls on for
    /// arm64 targets; swift.org's clang has none, and both take it from `-mlinker-version`, which
    /// changes no link argument for `ld64.lld`. For Apple targets it also calls `__dynamic_cast` for a
    /// `dynamic_cast` to a final class (`-fno-assume-unique-vtables`) and accepts `typedef enum E : int F;`
    /// in C++ (`-Wno-elaborated-enum-base`).
    public static let appleDriverDefaults = [
        "-fcommon", "-fno-strict-return", "-mlinker-version=" + XcodeProfile.current.xcodeTools.clangLinkerVersion,
        "-fno-assume-unique-vtables", "-Wno-elaborated-enum-base",
    ]
    /// The settings a build off macOS adds: `OTHER_SWIFT_FLAGS` with the flags after the inherited
    /// value, and for Linux targets the host resource directory too, `OTHER_CFLAGS` with the
    /// toolchain's headers and `OTHER_CPLUSPLUSFLAGS` with unsized deallocation, which the Swift
    /// flags give the Clang importer too, among the
    /// synthesized settings or, when the command line sets one, beside its value.
    public static func apply(to overrides: inout [String: String], synthesized: inout [String: String]) {
        let linux = "OTHER_SWIFT_FLAGS[sdk=linux*]"
        let swiftFlags = crossImportOverlays + " " + resilientCxxTypes + " -Xcc " + clangABI + " -Xcc " + unsizedDeallocation + " -Xcc "
            + toolchainHeaders.replacingOccurrences(of: " ", with: " -Xcc ")
        if let commandLine = overrides["OTHER_SWIFT_FLAGS"] {
            overrides["OTHER_SWIFT_FLAGS"] = commandLine + " " + swiftFlags
            overrides[linux] = "$(inherited) " + hostCompiles
        } else {
            synthesized["OTHER_SWIFT_FLAGS"] = "$(inherited) " + swiftFlags
            synthesized[linux] = "$(inherited) " + hostCompiles
        }
        if let commandLine = overrides["OTHER_CFLAGS"] {
            overrides["OTHER_CFLAGS"] = commandLine + " " + toolchainHeaders
        } else {
            synthesized["OTHER_CFLAGS"] = "$(inherited) " + toolchainHeaders
        }
        if let commandLine = overrides["OTHER_CPLUSPLUSFLAGS"] {
            overrides["OTHER_CPLUSPLUSFLAGS"] = commandLine + " " + unsizedDeallocation
        } else {
            synthesized["OTHER_CPLUSPLUSFLAGS"] = "$(inherited) " + unsizedDeallocation
        }
    }
}
