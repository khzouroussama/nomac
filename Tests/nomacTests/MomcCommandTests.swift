import Testing
@testable import nomac

/// The deployment target momc and mapc take, as `CoreData.xcspec` passes it for each platform
/// (coredata-experiments `platforms`).
@Suite struct MomcCommandTests {
    @Test(arguments: ["iphoneos", "iphonesimulator", "watchos", "watchsimulator", "appletvos", "macosx", "xros"])
    func takesEachObservedPlatform(_ platform: String) throws {
        let momc = try MomcCommand.parse(["--sdkroot", "/SDK", "--\(platform)-deployment-target", "9.0", "--module", "W", "M.xcdatamodeld", "/out"])
        #expect(throws: Never.self) { try momc.deploymentTarget.validate(tool: "momc") }
        let mapc = try MapcCommand.parse(["--sdkroot", "/SDK", "--\(platform)-deployment-target", "9.0", "M.xcmappingmodel", "/out/M.cdm"])
        #expect(throws: Never.self) { try mapc.deploymentTarget.validate(tool: "mapc") }
    }

    @Test(arguments: ["appletvsimulator", "xrsimulator", "driverkit"])
    func refusesUnobservedPlatforms(_ platform: String) throws {
        let momc = try MomcCommand.parse(["--\(platform)-deployment-target", "27.0", "M.xcdatamodeld", "/out"])
        #expect { try momc.deploymentTarget.validate(tool: "momc") } throws: { "\($0)".contains("B-236") }
    }

    @Test func refusesWarningSwitches() throws {
        let momc = try MomcCommand.parse(["--watchos-deployment-target", "9.0", "--no-delete-rule-warnings", "M.xcdatamodeld", "/out"])
        #expect { try momc.warningSwitches.validate(tool: "momc") } throws: { "\($0)".contains("--no-delete-rule-warnings") }
    }

    @Test func needsOneTarget() throws {
        let none = try MomcCommand.parse(["M.xcdatamodeld", "/out"])
        #expect(throws: (any Error).self) { try none.deploymentTarget.validate(tool: "momc") }
        let two = try MomcCommand.parse(["--iphoneos-deployment-target", "27.0", "--watchos-deployment-target", "9.0", "M.xcdatamodeld", "/out"])
        #expect(throws: (any Error).self) { try two.deploymentTarget.validate(tool: "momc") }
    }
}
