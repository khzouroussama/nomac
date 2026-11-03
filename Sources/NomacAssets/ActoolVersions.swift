import NomacCore

/// The versions the profile's Xcode's actool writes into its outputs (`XcodeProfile.actool` and
/// `.assetCatalog`): its own in the version report and the dependency info, and those of Xcode,
/// CoreUI, CoreThemeDefinition and the image libraries in `Assets.car`'s `CARHEADER` and
/// `EXTENDED_METADATA`.
public enum ActoolVersions {
    public static let bundleVersion = XcodeProfile.current.actool.bundleVersion
    public static let shortBundleVersion = XcodeProfile.current.actool.shortBundleVersion
    public static let coreUIVersion = XcodeProfile.current.assetCatalog.coreUIVersion
    public static let coreUIVersionString = XcodeProfile.current.assetCatalog.coreUIVersionString
    public static let authoringTool = XcodeProfile.current.assetCatalog.authoringTool
    /// watchOS catalogs name another CMPhoto build (`watchos` experiment).
    public static let watchOSAuthoringTool = XcodeProfile.current.assetCatalog.watchOSAuthoringTool

    static let carVersionString = XcodeProfile.current.assetCatalog.versionString
}
