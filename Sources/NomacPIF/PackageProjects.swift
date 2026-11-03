import Foundation

/// The PIF of a workspace's Swift packages, made by NomacPackages with SwiftPM's package PIF
/// builder, for ``PIFGenerator`` to add to the workspace.
public struct PackageProjects: Sendable, Equatable {
    /// One package project: its contents (without targets) and its targets' contents, in
    /// the project's order.
    public struct Project: Sendable, Equatable {
        public var contents: PIFValue
        public var targets: [PIFValue]
        /// The order Xcode writes the target objects in, as indices into `targets`: the order
        /// the PIF builder reports its modules and products in, with dynamic-library variants
        /// last (netnewswire, icecubes: all 52 packages).
        public var documentOrder: [Int]

        public init(contents: PIFValue, targets: [PIFValue], documentOrder: [Int]? = nil) {
            self.contents = contents
            self.targets = targets
            self.documentOrder = documentOrder ?? Array(targets.indices)
        }
    }

    /// The package product an `XCSwiftPackageProductDependency` names: the GUID of its PIF
    /// target and the product's name.
    public struct Product: Sendable, Equatable {
        public var guid: String
        public var name: String

        public init(guid: String, name: String) {
            self.guid = guid
            self.name = name
        }
    }

    /// Package projects, in the order nomac lists them in the workspace (by package identity;
    /// Xcode's order depends on the checkout path, docs/adr/0010-swift-packages.md).
    public var projects: [Project]
    /// Products by the object ID of the `XCSwiftPackageProductDependency` that names them.
    public var products: [String: Product]

    public init(projects: [Project] = [], products: [String: Product] = [:]) {
        self.projects = projects
        self.products = products
    }
}
