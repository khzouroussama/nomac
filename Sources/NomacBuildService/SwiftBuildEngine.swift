import Foundation
import NomacCore
import SwiftBuild
import SWBBuildService

/// Hosts Apple's open-source Swift Build engine in-process.
///
/// nomac never reimplements build-setting resolution, dependency planning or
/// task construction: it hands Swift Build a PIF (Project Interchange Format)
/// document describing the workspace, exactly as Xcode does, and asks Swift Build
/// for results. The engine runs in this process (`.inProcessStatic`), so the
/// `nomac` binary has no separate build-service executable to locate at runtime.
///
/// Swift Build stops the process when a session is released without being closed, so sessions
/// exist only inside ``withWorkspace(developerDirectory:pifPath:host:_:)``, which closes them
/// whether its body returns or throws.
public final class SwiftBuildEngine: Sendable {
    private let service: SWBBuildService

    private init(service: SWBBuildService) {
        self.service = service
    }

    /// Starts the build service, opens a session whose platforms, SDKs and toolchains come from
    /// `developerDirectory` (an Xcode `Contents/Developer` directory, or the copy produced by
    /// `nomac sdk install`), loads the PIF document at `pifPath` into it and runs `body` with it.
    /// The session is closed and the service stopped on every path.
    ///
    /// - Parameters:
    ///   - developerDirectory: Absolute path of the developer directory.
    ///   - pifPath: Absolute path of a JSON PIF file.
    ///   - host: The machine and user identity the session reports to Swift Build.
    public static func withWorkspace<T>(developerDirectory: String, pifPath: String, host: HostIdentity,
                                        _ body: (WorkspaceSession) async throws -> T) async throws -> T {
        let engine: SwiftBuildEngine
        do {
            engine = SwiftBuildEngine(service: try await SWBBuildService(connectionMode: .inProcessStatic(swiftbuildServiceEntryPoint)))
        } catch {
            throw NomacError("could not start the Swift Build service: \(error)")
        }
        return try await finally({
            let session = try await engine.openWorkspace(developerDirectory: developerDirectory, pifPath: pifPath, host: host)
            return try await finally({ try await body(session) }, then: { await session.close() })
        }, then: { await engine.service.close() })
    }

    /// `body`'s result or error, after `cleanup` has run.
    private static func finally<T>(_ body: () async throws -> T, then cleanup: () async -> Void) async throws -> T {
        let result: T
        do {
            result = try await body()
        } catch {
            await cleanup()
            throw error
        }
        await cleanup()
        return result
    }

    private func openWorkspace(developerDirectory: String, pifPath: String, host: HostIdentity) async throws -> WorkspaceSession {
        let (result, diagnostics) = await service.createSession(
            name: pifPath,
            developerPath: developerDirectory,
            resourceSearchPaths: [],
            cachePath: nil,
            inferiorProductsPath: nil,
            environment: host.environment
        )
        let session: SWBBuildServiceSession
        switch result {
        case .success(let created):
            session = created
        case .failure(let error):
            let notes = diagnostics.map { $0.message }
            throw NomacError("Swift Build could not initialize the developer directory: \(error)", path: developerDirectory, notes: notes)
        }
        do {
            try await session.loadWorkspace(containerPath: pifPath)
            try await session.setSystemInfo(SWBSystemInfo(
                operatingSystemVersion: OperatingSystemVersion(
                    majorVersion: host.operatingSystemVersion.count > 0 ? host.operatingSystemVersion[0] : 0,
                    minorVersion: host.operatingSystemVersion.count > 1 ? host.operatingSystemVersion[1] : 0,
                    patchVersion: host.operatingSystemVersion.count > 2 ? host.operatingSystemVersion[2] : 0),
                productBuildVersion: host.operatingSystemBuild,
                nativeArchitecture: host.nativeArchitecture))
            try await session.setUserInfo(SWBUserInfo(
                userName: host.userName,
                groupName: host.groupName,
                uid: host.uid,
                gid: host.gid,
                homeDirectory: host.homeDirectory,
                processEnvironment: host.environment,
                buildSystemEnvironment: host.environment))
        } catch {
            try? await session.close()
            throw NomacError("Swift Build could not load the workspace: \(error)", path: pifPath)
        }
        return WorkspaceSession(session: session)
    }
}

/// A Swift Build session with one workspace loaded.
public final class WorkspaceSession: Sendable {
    package let session: SWBBuildServiceSession

    init(session: SWBBuildServiceSession) {
        self.session = session
    }

    /// Closes the session and releases the workspace.
    func close() async {
        try? await session.close()
    }

    /// Every target in the loaded workspace, in workspace order.
    public func targets() async throws -> [WorkspaceTarget] {
        let info = try await session.workspaceInfo()
        return info.targetInfos.map {
            WorkspaceTarget(guid: $0.guid, name: $0.targetName)
        }
    }

    /// Computes the build settings exported for `targetGUID`, using exactly the
    /// algorithm Xcode uses for `xcodebuild -showBuildSettings` and for the
    /// environment of shell-script build phases.
    public func exportedBuildSettings(targetGUID: String, request: SettingsRequest) async throws -> [String: String] {
        do {
            return try await session.allExportedMacroNamesAndValues(level: .target(targetGUID), buildParameters: request.buildParameters)
        } catch {
            throw NomacError("Swift Build could not evaluate build settings for target \(targetGUID): \(error)")
        }
    }

    /// Evaluates a single build setting expression (for example `$(PRODUCT_NAME)`) for a target.
    public func evaluate(_ expression: String, targetGUID: String, request: SettingsRequest) async throws -> String {
        try await session.evaluateMacroExpressionAsString(expression, level: .target(targetGUID), buildParameters: request.buildParameters, overrides: nil)
    }

    /// Evaluates a build setting expression as a list of words (for example `$(OTHER_SWIFT_FLAGS)`) for a target.
    public func evaluateList(_ expression: String, targetGUID: String, request: SettingsRequest) async throws -> [String] {
        try await session.evaluateMacroExpressionAsStringList(expression, level: .target(targetGUID), buildParameters: request.buildParameters, overrides: nil)
    }
}

/// A target as reported by a loaded workspace.
public struct WorkspaceTarget: Sendable, Equatable {
    public var guid: String
    public var name: String

    public init(guid: String, name: String) {
        self.guid = guid
        self.name = name
    }
}
