import Foundation
@_spi(PackagePluginInternal) import PackagePlugin

/// What a build tool plugin applied to a target of an Xcode project is given (ADR 0105).
public struct XcodePluginContext {
    public let xcodeProject: XcodeProject

    @available(_PackageDescription, deprecated: 6.0)
    public var pluginWorkDirectory: Path {
        Path(pluginWorkDirectoryURL.path)
    }

    public let pluginWorkDirectoryURL: URL

    let accessibleTools: [String: (path: URL, triples: [String]?)]
    let toolSearchDirectoryURLs: [URL]

    /// The tool of that name the plugin may run, as `PluginContext.tool(named:)` finds it.
    public func tool(named name: String) throws -> PluginContext.Tool {
        if let tool = accessibleTools[name] {
            if let triples = tool.triples, triples.isEmpty {
                throw PluginContextError.toolNotSupportedOnTargetPlatform(name: name)
            }
            return PluginContext.Tool(name: name, path: Path(tool.path.path), url: tool.path)
        }
        for directory in toolSearchDirectoryURLs {
            let url = directory.appendingPathComponent(name)
            let path = Path(url.path)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return PluginContext.Tool(name: name, path: path, url: url)
            }
        }
        throw PluginContextError.toolNotFound(name: name)
    }
}

public struct XcodeProject {
    public typealias ID = String

    public let id: ID
    public let displayName: String

    @available(_PackageDescription, deprecated: 6.0)
    public var directory: Path {
        Path(directoryURL.path)
    }

    public let directoryURL: URL
    public let filePaths: PathList
    public let targets: [XcodeTarget]
}

public struct XcodeTarget {
    public typealias ID = String

    public let id: ID
    public let displayName: String
    public let product: XcodeProduct?
    public let dependencies: [XcodeTargetDependency]
    public let inputFiles: FileList
}

public struct XcodeProduct {
    public let name: String
    public let kind: Kind

    public enum Kind {
        case application
        case executable
        case framework
        case library
        case other(String)
    }
}

public enum XcodeTargetDependency {
    case target(XcodeTarget)
    case product(any PackagePlugin.Product)
}

public protocol XcodeBuildToolPlugin: Plugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command]
}

public protocol XcodeCommandPlugin: Plugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws
}

extension XcodeTarget {
    init(_ target: XcodeProjectPluginInvocationRecord.XcodeTarget) {
        let kind: XcodeProduct.Kind? = target.product.map { product in
            switch product.kind {
            case .application: .application
            case .executable: .executable
            case .framework: .framework
            case .library: .library
            case .other(let name): .other(name)
            }
        }
        self.init(id: target.id, displayName: target.displayName, product: target.product.map { XcodeProduct(name: $0.name, kind: kind!) },
                  dependencies: [], inputFiles: target.inputFiles)
    }
}

extension XcodePluginContext {
    init(_ record: XcodeProjectPluginInvocationRecord) {
        let project = XcodeProject(id: record.xcodeProject.id, displayName: record.xcodeProject.displayName,
                                   directoryURL: record.xcodeProject.directoryPathURL, filePaths: record.xcodeProject.filePaths,
                                   targets: record.xcodeProject.targets.map(XcodeTarget.init))
        self.init(xcodeProject: project, pluginWorkDirectoryURL: record.pluginWorkDirectoryURL,
                  accessibleTools: record.accessibleToolsByURL, toolSearchDirectoryURLs: record.toolSearchDirectoryURLs)
    }
}

/// `PackagePlugin`'s entry point for a build tool plugin applied to an Xcode project's target:
/// the plugin's commands go into the record, an error comes back retained. Public, as SPI, so
/// that the library exports the symbol `PackagePlugin` looks up.
@_cdecl("call_XcodeProjectPlugin_build_command_creation_entry_point")
@_spi(PackagePluginInternal) public func buildCommandCreationEntryPoint(_ pointer: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    let record = Unmanaged<XcodeProjectPluginInvocationRecord>.fromOpaque(pointer).takeUnretainedValue()
    do {
        guard let plugin = record.plugin as? XcodeBuildToolPlugin, let target = record.xcodeTarget else {
            throw XcodeProjectPluginEntryPointError.notXcodeBuildToolPlugin
        }
        record.generatedCommands = try plugin.createBuildCommands(context: XcodePluginContext(record), target: XcodeTarget(target))
        return nil
    } catch {
        return Unmanaged.passRetained(XcodeProjectPluginError(error)).toOpaque()
    }
}

enum XcodeProjectPluginEntryPointError: Error {
    case notXcodeBuildToolPlugin
}
