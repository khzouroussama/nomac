import Foundation
import SwiftBuild

/// The per-request parameters for evaluating build settings: the build action,
/// configuration, run destination, build locations and command-line overrides.
///
/// These correspond one to one with what `xcodebuild` derives from its command line
/// (`-configuration`, `-sdk`, `-destination`, `-derivedDataPath`, `KEY=value` overrides).
public struct SettingsRequest: Sendable, Equatable {
    /// The build action (`build`, `archive`, `install`, `analyze`, ...).
    public var action: String
    /// The configuration name, or `nil` for the project's default configuration.
    public var configuration: String?
    /// The active run destination, or `nil` for none.
    public var destination: RunDestination?
    /// The build locations, or `nil` to let the project defaults apply.
    public var locations: BuildLocations?
    /// Command-line build setting overrides (`KEY=value`), highest precedence.
    public var overrides: [String: String]
    /// Settings the client synthesizes: from the scheme (for example code coverage), and off
    /// macOS those Swift Build would otherwise take from the machine.
    public var synthesizedOverrides: [String: String]
    /// The toolchain xcodebuild names from its environment's `TOOLCHAINS`.
    public var toolchainOverride: String?

    public init(action: String = "build", configuration: String? = nil, destination: RunDestination? = nil, locations: BuildLocations? = nil, overrides: [String: String] = [:], synthesizedOverrides: [String: String] = [:]) {
        self.action = action
        self.configuration = configuration
        self.destination = destination
        self.locations = locations
        self.overrides = overrides
        self.synthesizedOverrides = synthesizedOverrides
    }

    package var buildParameters: SWBBuildParameters {
        var parameters = SWBBuildParameters()
        parameters.action = action
        parameters.configurationName = configuration
        if let destination {
            parameters.activeRunDestination = SWBRunDestinationInfo(
                platform: destination.platform,
                sdk: destination.sdk,
                sdkVariant: destination.sdkVariant,
                targetArchitecture: destination.targetArchitecture,
                supportedArchitectures: destination.supportedArchitectures,
                disableOnlyActiveArch: destination.disableOnlyActiveArch)
            parameters.activeArchitecture = destination.targetArchitecture
        }
        if let locations {
            parameters.arenaInfo = SWBArenaInfo(
                derivedDataPath: locations.derivedDataPath,
                buildProductsPath: locations.buildProductsPath,
                buildIntermediatesPath: locations.buildIntermediatesPath,
                pchPath: locations.pchPath,
                indexRegularBuildProductsPath: nil,
                indexRegularBuildIntermediatesPath: nil,
                indexPCHPath: locations.indexPCHPath,
                indexDataStoreFolderPath: nil,
                indexEnableDataStore: false)
        }
        if !synthesizedOverrides.isEmpty {
            parameters.overrides.synthesized = SWBSettingsTable()
            for (key, value) in synthesizedOverrides.sorted(by: { $0.key < $1.key }) {
                parameters.overrides.synthesized?.set(value: value, for: key)
            }
        }
        if !overrides.isEmpty {
            parameters.overrides.commandLine = SWBSettingsTable()
            for (key, value) in overrides.sorted(by: { $0.key < $1.key }) {
                parameters.overrides.commandLine?.set(value: value, for: key)
            }
        }
        parameters.overrides.toolchainOverride = toolchainOverride
        return parameters
    }
}

/// A run destination: the platform, SDK and architectures a build targets.
public struct RunDestination: Sendable, Equatable {
    public var platform: String
    public var sdk: String
    public var sdkVariant: String?
    public var targetArchitecture: String
    public var supportedArchitectures: [String]
    public var disableOnlyActiveArch: Bool

    public init(platform: String, sdk: String, sdkVariant: String? = nil, targetArchitecture: String, supportedArchitectures: [String], disableOnlyActiveArch: Bool) {
        self.platform = platform
        self.sdk = sdk
        self.sdkVariant = sdkVariant
        self.targetArchitecture = targetArchitecture
        self.supportedArchitectures = supportedArchitectures
        self.disableOnlyActiveArch = disableOnlyActiveArch
    }
}

/// Where build products and intermediates go (Xcode's "arena").
public struct BuildLocations: Sendable, Equatable {
    public var derivedDataPath: String
    public var buildProductsPath: String
    public var buildIntermediatesPath: String
    public var pchPath: String
    public var indexPCHPath: String

    public init(derivedDataPath: String, buildProductsPath: String, buildIntermediatesPath: String, pchPath: String, indexPCHPath: String) {
        self.derivedDataPath = derivedDataPath
        self.buildProductsPath = buildProductsPath
        self.buildIntermediatesPath = buildIntermediatesPath
        self.pchPath = pchPath
        self.indexPCHPath = indexPCHPath
    }
}
