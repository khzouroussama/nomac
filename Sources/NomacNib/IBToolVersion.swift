import Foundation
import NomacCore
import NomacPlist

/// What `ibtool --version --output-format xml1` prints, which Swift Build asks before it plans
/// any Interface Builder task (SWBApplePlatform `InterfaceBuilderShared.swift`). nomac answers
/// with the version of the ibtool whose behavior it reproduces (`XcodeProfile.ibtool`), and adds
/// its own under `nomac` (docs/adr/0102-linker.md, "Tool probes").
public enum IBToolVersion {
    public static var report: String {
        let ibtool = XcodeProfile.current.ibtool
        return String(decoding: XMLPropertyList.data(.dictionary([
            "com.apple.ibtool.version": .dictionary(["bundle-version": .string(ibtool.bundleVersion), "short-bundle-version": .string(ibtool.shortBundleVersion)]),
            "nomac": .dictionary(["version": .string(NomacVersion.current)]),
        ])), as: UTF8.self)
    }
}
