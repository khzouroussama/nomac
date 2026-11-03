import Basics
import Foundation
import PackageLoading
import PackageModel
import TSCBasic
import struct TSCUtility.Version

/// A manifest loader that evaluates manifests as the Mac Xcode runs on would: it hands
/// SwiftPM's loader a view of the file system in which every manifest's host conditions are
/// already answered (``ManifestConditions``).
///
/// SwiftPM reads a manifest through the file system it is given (the checkout, or a
/// repository's object store while resolving), copies the contents to a temporary file and
/// compiles that, so the rewritten text is what runs. It also keys its manifest cache by the
/// contents, so Linux and Mac evaluations of one manifest never mix.
final class MacManifestLoader: ManifestLoaderProtocol {
    private let underlying: ManifestLoaderProtocol
    private let host: HostConditions
    private let unanswered = UnansweredConditions()

    init(underlying: ManifestLoaderProtocol, host: HostConditions = .mac) {
        self.underlying = underlying
        self.host = host
    }

    /// Host conditions that manifests used and the host table had no answer for, by manifest.
    var unansweredConditions: [String: [String]] { unanswered.all }

    func load(
        manifestPath: Basics.AbsolutePath,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        fileSystem: Basics.FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) async throws -> Manifest {
        try await underlying.load(
            manifestPath: manifestPath,
            manifestToolsVersion: manifestToolsVersion,
            packageIdentity: packageIdentity,
            packageKind: packageKind,
            packageLocation: packageLocation,
            packageVersion: packageVersion,
            identityResolver: identityResolver,
            dependencyMapper: dependencyMapper,
            fileSystem: ManifestConditionsFileSystem(underlying: fileSystem, host: host, unanswered: unanswered),
            observabilityScope: observabilityScope,
            delegateQueue: delegateQueue
        )
    }

    func resetCache(observabilityScope: ObservabilityScope) async {
        await underlying.resetCache(observabilityScope: observabilityScope)
    }

    func purgeCache(observabilityScope: ObservabilityScope) async {
        await underlying.purgeCache(observabilityScope: observabilityScope)
    }
}

/// Unanswered host conditions, collected from concurrent manifest loads.
final class UnansweredConditions: @unchecked Sendable {
    private let lock = NSLock()
    private var conditions: [String: [String]] = [:]

    func record(_ found: [String], manifest: String) {
        guard !found.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        conditions[manifest] = found
    }

    var all: [String: [String]] {
        lock.lock()
        defer { lock.unlock() }
        return conditions
    }
}

/// A file system that returns manifests (`Package.swift`, `Package@swift-*.swift`) with their
/// host conditions answered, and everything else as the underlying file system has it.
struct ManifestConditionsFileSystem: TSCBasic.FileSystem {
    let underlying: TSCBasic.FileSystem
    let host: HostConditions
    let unanswered: UnansweredConditions

    static func isManifest(_ name: String) -> Bool {
        name == "Package.swift" || (name.hasPrefix("Package@swift-") && name.hasSuffix(".swift"))
    }

    func readFileContents(_ path: TSCBasic.AbsolutePath) throws -> ByteString {
        let contents = try underlying.readFileContents(path)
        guard Self.isManifest(path.basename) else { return contents }
        let result = ManifestConditions.rewrite(String(decoding: contents.contents, as: UTF8.self), host: host)
        unanswered.record(result.unanswered, manifest: path.pathString)
        return ByteString(encodingAsUTF8: result.source)
    }

    func exists(_ path: TSCBasic.AbsolutePath, followSymlink: Bool) -> Bool { underlying.exists(path, followSymlink: followSymlink) }
    func isDirectory(_ path: TSCBasic.AbsolutePath) -> Bool { underlying.isDirectory(path) }
    func isFile(_ path: TSCBasic.AbsolutePath) -> Bool { underlying.isFile(path) }
    func isExecutableFile(_ path: TSCBasic.AbsolutePath) -> Bool { underlying.isExecutableFile(path) }
    func isSymlink(_ path: TSCBasic.AbsolutePath) -> Bool { underlying.isSymlink(path) }
    func isReadable(_ path: TSCBasic.AbsolutePath) -> Bool { underlying.isReadable(path) }
    func isWritable(_ path: TSCBasic.AbsolutePath) -> Bool { underlying.isWritable(path) }
    func itemReplacementDirectories(for path: TSCBasic.AbsolutePath) throws -> [TSCBasic.AbsolutePath] {
        try underlying.itemReplacementDirectories(for: path)
    }
    func hasAttribute(_ name: FileSystemAttribute, _ path: TSCBasic.AbsolutePath) -> Bool { underlying.hasAttribute(name, path) }
    func getDirectoryContents(_ path: TSCBasic.AbsolutePath) throws -> [String] { try underlying.getDirectoryContents(path) }
    var currentWorkingDirectory: TSCBasic.AbsolutePath? { underlying.currentWorkingDirectory }
    func changeCurrentWorkingDirectory(to path: TSCBasic.AbsolutePath) throws { try underlying.changeCurrentWorkingDirectory(to: path) }
    var homeDirectory: TSCBasic.AbsolutePath { get throws { try underlying.homeDirectory } }
    var cachesDirectory: TSCBasic.AbsolutePath? { underlying.cachesDirectory }
    var tempDirectory: TSCBasic.AbsolutePath { get throws { try underlying.tempDirectory } }
    func createDirectory(_ path: TSCBasic.AbsolutePath, recursive: Bool) throws { try underlying.createDirectory(path, recursive: recursive) }
    func createSymbolicLink(_ path: TSCBasic.AbsolutePath, pointingAt destination: TSCBasic.AbsolutePath, relative: Bool) throws {
        try underlying.createSymbolicLink(path, pointingAt: destination, relative: relative)
    }
    func writeFileContents(_ path: TSCBasic.AbsolutePath, bytes: ByteString) throws { try underlying.writeFileContents(path, bytes: bytes) }
    func writeFileContents(_ path: TSCBasic.AbsolutePath, bytes: ByteString, atomically: Bool) throws {
        try underlying.writeFileContents(path, bytes: bytes, atomically: atomically)
    }
    func removeFileTree(_ path: TSCBasic.AbsolutePath) throws { try underlying.removeFileTree(path) }
    func chmod(_ mode: FileMode, path: TSCBasic.AbsolutePath, options: Set<FileMode.Option>) throws {
        try underlying.chmod(mode, path: path, options: options)
    }
    func getFileInfo(_ path: TSCBasic.AbsolutePath) throws -> FileInfo { try underlying.getFileInfo(path) }
    func copy(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {
        try underlying.copy(from: sourcePath, to: destinationPath)
    }
    func move(from sourcePath: TSCBasic.AbsolutePath, to destinationPath: TSCBasic.AbsolutePath) throws {
        try underlying.move(from: sourcePath, to: destinationPath)
    }
    func withLock<T>(on path: TSCBasic.AbsolutePath, type: FileLock.LockType, blocking: Bool, _ body: () throws -> T) throws -> T {
        try underlying.withLock(on: path, type: type, blocking: blocking, body)
    }
    func withLock<T>(on path: TSCBasic.AbsolutePath, type: FileLock.LockType, blocking: Bool, _ body: () async throws -> T) async throws -> T {
        try await underlying.withLock(on: path, type: type, blocking: blocking, body)
    }
}
