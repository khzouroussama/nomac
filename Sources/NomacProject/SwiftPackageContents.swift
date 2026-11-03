/// What scheme discovery needs to know about a Swift package the workspace uses: its library
/// and executable products as its manifest declares them, and the targets its PIF project has
/// (NomacPackages fills it in from the resolved graph).
public struct SwiftPackageContents: Sendable, Equatable {
    /// A library or executable product.
    public struct Product: Sendable, Equatable {
        public var name: String
        /// The targets the manifest lists for the product.
        public var targets: [String]
        public var isExecutable: Bool

        public init(name: String, targets: [String], isExecutable: Bool = false) {
            self.name = name
            self.targets = targets
            self.isExecutable = isExecutable
        }
    }

    public struct TestTarget: Sendable, Equatable {
        public var name: String
        /// The package's own targets the test target depends on directly.
        public var dependencies: [String]

        public init(name: String, dependencies: [String]) {
            self.name = name
            self.dependencies = dependencies
        }
    }

    /// The package's directory: its checkout, for a remote package.
    public var directory: String
    /// Whether the package is a root of the graph (a package folder in the workspace's file tree).
    public var isRoot: Bool
    /// Whether the package is on a local path: a root package, or a dependency the project or a
    /// package names by path, not a remote one.
    public var isLocal: Bool
    /// Library and executable products, in manifest order.
    public var products: [Product]
    /// The targets the package's PIF project has, sorted by name: no test or binary targets, and
    /// for a dependency only those its products use.
    public var targets: [String]
    /// A root package's test targets; Xcode loads no test targets of the packages it depends on.
    public var testTargets: [TestTarget]

    public init(directory: String, isRoot: Bool, isLocal: Bool = false, products: [Product], targets: [String], testTargets: [TestTarget]) {
        self.directory = directory
        self.isRoot = isRoot
        self.isLocal = isRoot || isLocal
        self.products = products
        self.targets = targets
        self.testTargets = testTargets
    }

    /// Whether `name` names something a scheme can build or test in this package.
    public func contains(_ name: String) -> Bool {
        products.contains { $0.name == name } || targets.contains(name) || testTargets.contains { $0.name == name }
    }
}
