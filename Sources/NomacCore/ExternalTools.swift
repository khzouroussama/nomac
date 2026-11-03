import Foundation

/// A program nomac runs as a subprocess, with the version nomac is tested against.
public struct ExternalTool: Sendable, Equatable {
    /// The executable name looked up on `PATH`.
    public var executable: String
    /// The environment variable that overrides the executable's location.
    public var overrideVariable: String
    /// The version nomac is tested with.
    public var pinnedVersion: String
    /// What nomac uses the tool for.
    public var purpose: String
    /// How to install the pinned version.
    public var installation: String
    /// Arguments that make the tool print its version.
    public var versionArguments: [String]

    /// Locates the tool: the override variable first, then `PATH`.
    public func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let override = environment[overrideVariable], !override.isEmpty {
            return Subprocess.locate(override, environment: environment)
        }
        return Subprocess.locate(executable, environment: environment)
    }
}

/// Every subprocess dependency of nomac. `nomac doctor` reports on each of them.
public enum ExternalTools {
    /// `unxip` expands `Xcode.xip` archives (docs/adr/0003-sdk-extraction.md).
    public static let unxip = ExternalTool(
        executable: "unxip",
        overrideVariable: "NOMAC_UNXIP",
        pinnedVersion: "3.3",
        purpose: "expands Xcode.xip for 'nomac sdk install' (not needed when installing from an Xcode.app)",
        installation: """
        git clone --branch v3.3 https://github.com/saagarjha/unxip && cd unxip && \
        swift build -c release --product unxip && sudo install .build/release/unxip /usr/local/bin/ \
        (Ubuntu: sudo apt-get install -y liblzma-dev zlib1g-dev first)
        """,
        versionArguments: ["--version"]
    )

    /// 7-Zip reads the Developer Disk Image out of Xcode's `XcodeSystemResources.pkg` (xar,
    /// cpio, UDIF and HFS+; docs/formats/ddi.md, ADR 0403).
    public static let sevenZip = ExternalTool(
        executable: "7z",
        overrideVariable: "NOMAC_7Z",
        pinnedVersion: "23.01",
        purpose: "extracts the Developer Disk Image for 'nomac sdk install' (needed to mount it on a device from Linux)",
        installation: "Ubuntu: sudo apt-get install -y 7zip",
        versionArguments: []
    )

    /// xz expands the xz chunks of the package's pbzx payload.
    public static let xz = ExternalTool(
        executable: "xz",
        overrideVariable: "NOMAC_XZ",
        pinnedVersion: "5.4.5",
        purpose: "expands the Developer Disk Image's package payload for 'nomac sdk install'",
        installation: "Ubuntu: sudo apt-get install -y xz-utils",
        versionArguments: ["--version"]
    )

    /// All tools, in the order `nomac doctor` lists them.
    public static let all: [ExternalTool] = [unxip, sevenZip, xz]
}
