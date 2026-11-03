import ArgumentParser
import NomacCore

/// The `--<platform>-deployment-target` option a build gives momc and mapc (`CoreData.xcspec`:
/// `--$(PLATFORM_NAME)-deployment-target`). For each platform but the refused ones, Xcode 27.0's
/// tools write the same outputs as for iOS (coredata-experiments `platforms`).
struct DeploymentTargetOptions: ParsableArguments {
    @Option(name: .customLong("iphoneos-deployment-target"), help: "An iOS target.")
    var iphoneos: String?

    @Option(name: .customLong("iphonesimulator-deployment-target"), help: "An iOS Simulator target.")
    var iphonesimulator: String?

    @Option(name: .customLong("watchos-deployment-target"), help: "A watchOS target.")
    var watchos: String?

    @Option(name: .customLong("watchsimulator-deployment-target"), help: "A watchOS Simulator target.")
    var watchsimulator: String?

    @Option(name: .customLong("appletvos-deployment-target"), help: "A tvOS target.")
    var appletvos: String?

    @Option(name: .customLong("macosx-deployment-target"), help: "A macOS target.")
    var macosx: String?

    @Option(name: .customLong("xros-deployment-target"), help: "A visionOS target.")
    var xros: String?

    @Option(name: .customLong("appletvsimulator-deployment-target"), help: "Refused: not observed (BACKLOG B-236).")
    var appletvsimulator: String?

    @Option(name: .customLong("xrsimulator-deployment-target"), help: "Refused: not observed (BACKLOG B-236).")
    var xrsimulator: String?

    @Option(name: .customLong("driverkit-deployment-target"), help: "Refused: not observed (BACKLOG B-236).")
    var driverkit: String?

    /// Fails unless exactly one observed platform's target is given, as a build gives it.
    func validate(tool: String) throws {
        let observed = [iphoneos, iphonesimulator, watchos, watchsimulator, appletvos, macosx, xros].compactMap { $0 }
        let unobserved = [("appletvsimulator", appletvsimulator), ("xrsimulator", xrsimulator), ("driverkit", driverkit)].filter { $0.1 != nil }
        if let platform = unobserved.first {
            throw NomacError("nomac \(tool) for \(platform.0) is not observed yet (BACKLOG B-236)")
        }
        guard observed.count == 1 else {
            throw NomacError("nomac \(tool) needs one --<platform>-deployment-target, as builds give it")
        }
    }
}

/// The warning switches of `CoreData.xcspec`, which change the diagnostics momc and mapc print in
/// ways not observed yet: refused by name (BACKLOG B-236).
struct WarningSwitches: ParsableArguments {
    @Flag(name: .customLong("no-warnings"), help: "Refused: not observed (BACKLOG B-236).")
    var noWarnings = false

    @Flag(name: .customLong("no-inverse-relationship-warnings"), help: "Refused: not observed (BACKLOG B-236).")
    var noInverseRelationshipWarnings = false

    @Flag(name: .customLong("no-max-property-count-warnings"), help: "Refused: not observed (BACKLOG B-236).")
    var noMaxPropertyCountWarnings = false

    @Flag(name: .customLong("no-delete-rule-warnings"), help: "Refused: not observed (BACKLOG B-236).")
    var noDeleteRuleWarnings = false

    @Flag(name: .customLong("suppress-inverse-transient-error"), help: "Refused: not observed (BACKLOG B-236).")
    var suppressInverseTransientError = false

    @Flag(name: .customLong("mapc-no-warnings"), help: "Refused: not observed (BACKLOG B-236).")
    var mapcNoWarnings = false

    func validate(tool: String) throws {
        let given = [("--no-warnings", noWarnings), ("--no-inverse-relationship-warnings", noInverseRelationshipWarnings),
                     ("--no-max-property-count-warnings", noMaxPropertyCountWarnings), ("--no-delete-rule-warnings", noDeleteRuleWarnings),
                     ("--suppress-inverse-transient-error", suppressInverseTransientError), ("--mapc-no-warnings", mapcNoWarnings)]
        if let flag = given.first(where: \.1) {
            throw NomacError("nomac \(tool) \(flag.0) is not observed yet (BACKLOG B-236)")
        }
    }
}
