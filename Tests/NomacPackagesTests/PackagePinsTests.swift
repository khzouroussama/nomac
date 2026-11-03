import Foundation
import NomacCore
import NomacPIF
import NomacProject
import NomacTestSupport
import Testing
@testable import NomacPackages

/// loader-experiments `package-pins-*` and `product-target-dependencies`, written again here.
@Suite struct PackagePinsTests {
    /// The workspace's Package.resolved pins the packages when it exists; otherwise a single root
    /// package's own does; two root packages or an unpinned one leave it to the workspace's
    /// (pocket-casts' `Modules`).
    @Test func choosesTheFileThatPinsThePackages() throws {
        let directory = try TemporaryDirectory()
        let workspace = directory.path + "/P.xcodeproj/project.xcworkspace"
        let shared = workspace + "/xcshareddata/swiftpm/Package.resolved"
        let (root, other) = (directory.path + "/Root", directory.path + "/Other")
        try FileSystem.write(Data("{}\n".utf8), to: root + "/Package.resolved")
        try FileSystem.createDirectory(other)
        #expect(PackageReferences.resolvedFile(workspace: workspace, rootPackages: [root]) == root + "/Package.resolved")
        #expect(PackageReferences.resolvedFile(workspace: workspace, rootPackages: [root, other]) == shared)
        #expect(PackageReferences.resolvedFile(workspace: workspace, rootPackages: [other]) == shared)
        #expect(PackageReferences.resolvedFile(workspace: workspace, rootPackages: []) == shared)
        try FileSystem.write(Data("{}\n".utf8), to: shared)
        #expect(PackageReferences.resolvedFile(workspace: workspace, rootPackages: [root]) == shared)
    }

    /// A target dependency that names a package product is listed in place, with its platform
    /// filters, before the products the build phases link, even when a build file links the same
    /// object (firefox's `RustMozillaAppServices`); the remote package's pins are written in the
    /// workspace, whose folders did not exist.
    @Test func listsProductTargetDependenciesInPlace() async throws {
        let directory = try TemporaryDirectory()
        let developer = try PackageFixtures.developerDirectory(at: directory.path + "/sdk")
        let root = (directory.path as NSString).standardizingPath + "/app"
        let path = try ProductFixtures.project(at: root, targets: [(true, [0], [("RemoteKit", PackageProductTests.remote)]),
                                                                   (true, [0], [("LocalKit", PackageProductTests.local)])])
        let objects = """
        \t\tT00000000000000000000001 = {isa = PBXTargetDependency; platformFilters = (ios, ); productRef = E00000000000000000000009; };
        \t\tE00000000000000000000009 = {isa = XCSwiftPackageProductDependency; package = \(PackageProductTests.local); productName = LocalKit; };
        \t\tT00000000000000000000002 = {isa = PBXTargetDependency; productRef = E00000000000000000000002; };

        """
        let pbxproj = try String(contentsOfFile: path + "/project.pbxproj", encoding: .utf8)
            .replacingOccurrences(of: "\t\tF00000000000000000000006 = {isa = PBXProject;", with: objects + "\t\tF00000000000000000000006 = {isa = PBXProject;")
            .replacingOccurrences(of: "name = App1; ", with: "dependencies = (T00000000000000000000001, ); name = App1; ")
            .replacingOccurrences(of: "name = App2; ", with: "dependencies = (T00000000000000000000002, ); name = App2; ")
        try FileSystem.write(Data(pbxproj.utf8), to: path + "/project.pbxproj")
        let workspace = try XcodeWorkspace.load(path: path)
        var packages = try SwiftPackages(workspace: workspace, sourcePackagesDirectory: directory.path + "/SourcePackages", developerDirectory: developer)
        var generator = PIFGenerator(workspace: workspace, packages: try await packages.load())
        let document = try generator.generate()
        func product(_ name: String, filters: Bool = false) -> PIFValue {
            var contents: [String: PIFValue] = ["guid": .string("PACKAGE-PRODUCT:" + name), "name": .string(String(name.split(separator: ".").last!))]
            if filters { contents["platformFilters"] = .array([.object(["platform": .string("ios")])]) }
            return .object(contents)
        }
        #expect(try ProductFixtures.target("App1", in: document)["dependencies"] == .array([product("local_LocalKit.LocalKit", filters: true), product("remote_RemoteKit.RemoteKit")]))
        #expect(try ProductFixtures.target("App2", in: document)["dependencies"] == .array([product("local_LocalKit.LocalKit"), product("local_LocalKit.LocalKit")]))
        #expect(FileSystem.isFile(path + "/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"))
    }
}
