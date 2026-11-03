// swift-tools-version:6.2

import PackageDescription

// Swift Build pins its own sibling dependencies (llbuild, swift-driver, ...) by
// branch, so SwiftPM only accepts it as a revision dependency. The revision is the
// owner's fork's `release/6.4.2-linux-fixes`: the head of swiftlang's `release/6.4.2`
// (2d847030), the Swift Build behaviour Xcode 27.0 (27A266a) exhibits, with exactly the
// four upstream patches of docs/upstream/swift-build.md until upstream merges them
// (docs/adr/0005-swift-build-matches-xcode-27.md).
// See docs/adr/0002-dependencies.md before changing any pin in this file.
let swiftBuildRepository = "https://github.com/khzouroussama/swift-build.git"
let swiftBuildRevision = "79a7d991515d3b2cdea37db6a72b4cb9c19d8377"
// SwiftPM's package graph, at the head of `release/6.4.2` like Swift Build. Its PIF builder
// is vendored from the `swift-6.4.1-RELEASE` tag, the builder Xcode 27.0 exhibits
// (docs/adr/0010-swift-packages.md, Sources/VendoredPackagePIFBuilder/UPSTREAM.md).
let swiftPMRevision = "8054c59f07a9c8cc8e67b3ec57870710c7154854"

let package = Package(
    name: "nomac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "nomac", targets: ["nomac"]),
    ],
    dependencies: [
        .package(url: swiftBuildRepository, revision: swiftBuildRevision),
        .package(url: "https://github.com/swiftlang/swift-package-manager.git", revision: swiftPMRevision),
        .package(url: "https://github.com/tuist/XcodeProj.git", exact: "9.17.6"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        // The revision SwiftPM itself depends on (docs/adr/0300-signing-crypto.md).
        .package(url: "https://github.com/apple/swift-crypto.git", revision: "3.12.5"),
        // TLS for lockdownd's sessions, the same on macOS and Linux (docs/adr/0401-device-tls.md).
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.5"),
        // Swift Build's and SwiftPM's swift-driver, from the owner's fork with the patch of
        // docs/upstream/swift-driver.md; the same branch requirement makes it replace theirs.
        .package(url: "https://github.com/khzouroussama/swift-driver.git", branch: "release/6.4.x"),
        // Swift Build's and SwiftPM's swift-llbuild, from the owner's fork with the patch of
        // docs/upstream/swift-llbuild.md, replacing theirs the same way.
        .package(url: "https://github.com/khzouroussama/swift-llbuild.git", branch: "release/6.4.x"),
    ],
    targets: [
        .executableTarget(
            name: "nomac",
            dependencies: [
                "NomacCore",
                "NomacSDK",
                "NomacProject",
                "NomacPIF",
                "NomacPackages",
                "NomacBuildService",
                "NomacVerify",
                "NomacInspect",
                "NomacSigning",
                "NomacPackaging",
                "NomacPlist",
                "NomacStrings",
                "NomacNib",
                "NomacCoreData",
                "NomacIntents",
                "NomacCoreML",
                "NomacEnvelope",
                "NomacAssets",
                "NomacBuild",
                "NomacMacros",
                "NomacDevice",
                "NomacDistribution",
                "NomacDeviceTest",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .target(name: "NomacCore"),
        .target(
            name: "NomacSDK",
            dependencies: ["NomacCore"]
        ),
        .target(
            name: "NomacProject",
            dependencies: [
                "NomacCore",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .target(
            name: "NomacPIF",
            dependencies: [
                "NomacCore",
                "NomacProject",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .target(
            name: "VendoredPackagePIFBuilder",
            dependencies: [
                .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
                .product(name: "SwiftBuild", package: "swift-build"),
            ],
            exclude: ["UPSTREAM.md", "LICENSE.txt", "NOTICE.txt"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "NomacPackages",
            dependencies: [
                "NomacCore",
                "NomacProject",
                "NomacPIF",
                "VendoredPackagePIFBuilder",
                "NomacPluginAPI",
                .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
                .product(name: "SwiftBuild", package: "swift-build"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .target(
            name: "NomacVerify",
            dependencies: ["NomacCore", "CZlib", "NomacLZFSE"]
        ),
        .target(
            name: "NomacInspect",
            dependencies: ["NomacCore", "NomacProject", "NomacPIF", "NomacPackages", "NomacBuildService", "NomacVerify"]
        ),
        .target(
            name: "NomacEnvelope",
            dependencies: ["NomacCore", "NomacProject", "NomacPIF", "NomacPackages"]
        ),
        .target(
            name: "NomacBuild",
            dependencies: [
                "NomacCore",
                "NomacLZFSE",
                "NomacPackages",
                "NomacSigning",
                "CZlib",
                "NomacBuildService",
                "NomacPIF",
                "NomacVerify",
                "NomacEnvelope",
                "NomacProject",
                .product(name: "SwiftBuild", package: "swift-build"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .target(
            name: "NomacPluginAPI",
            dependencies: ["NomacCore"],
            resources: [.copy("PluginAPI")]
        ),
        .target(
            name: "NomacMacros",
            dependencies: ["NomacCore"],
            resources: [.copy("Plugins")]
        ),
        .target(
            name: "NomacBuildService",
            dependencies: [
                "NomacCore",
                .product(name: "SwiftBuild", package: "swift-build"),
                .product(name: "SWBBuildService", package: "swift-build"),
            ]
        ),
        .target(
            name: "NomacPlist",
            dependencies: ["NomacCore"]
        ),
        .target(
            name: "NomacNib",
            dependencies: ["NomacCore", "NomacPlist"]
        ),
        .target(
            name: "NomacStrings",
            dependencies: ["NomacCore", "NomacPlist"]
        ),
        .target(
            name: "NomacCoreData",
            dependencies: ["NomacCore", "NomacPlist", "NomacEnvelope", "NomacProject", .product(name: "XcodeProj", package: "XcodeProj")]
        ),
        .target(
            name: "NomacIntents",
            dependencies: ["NomacCore", "NomacPlist"]
        ),
        .target(
            name: "NomacCoreML",
            dependencies: ["NomacCore", "NomacPlist", "NomacEnvelope", "NomacProject", .product(name: "XcodeProj", package: "XcodeProj")]
        ),
        .target(
            name: "NomacSigning",
            dependencies: [
                "NomacCore",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "NomacDevice",
            dependencies: [
                "NomacCore", "NomacSigning", "NomacPlist",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]
        ),
        .target(
            name: "NomacDistribution",
            dependencies: ["NomacCore", "CZlib", .product(name: "Crypto", package: "swift-crypto")]
        ),
        .target(
            name: "NomacDeviceTest",
            dependencies: ["NomacCore", "NomacDevice", "NomacPlist", "NomacSigning"]
        ),
        .systemLibrary(name: "CZlib", providers: [.apt(["zlib1g-dev"])]),
        .systemLibrary(name: "CSQLite", providers: [.apt(["libsqlite3-dev"])]),
        .target(
            name: "NomacPackaging",
            dependencies: [
                "NomacCore", "NomacSigning", "NomacPlist", "NomacEnvelope", "NomacProject", "NomacAssets", "CZlib", "CSQLite",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .target(
            name: "NomacAssets",
            dependencies: [
                "NomacCore", "NomacPlist", "NomacEnvelope", "NomacProject", "NomacLZFSE", "CZlib",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .target(
            name: "NomacLZFSE",
            exclude: ["LICENSE.txt", "UPSTREAM.md"]
        ),
        .target(
            name: "NomacTestSupport",
            dependencies: ["NomacCore", .product(name: "Crypto", package: "swift-crypto"), .product(name: "_CryptoExtras", package: "swift-crypto")]
        ),
        .testTarget(
            name: "NomacCoreTests",
            dependencies: ["NomacCore"]
        ),
        .testTarget(
            name: "NomacPIFTests",
            dependencies: ["NomacPIF", "NomacProject", "NomacCore", "NomacTestSupport", "NomacBuildService"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "NomacInspectTests",
            dependencies: ["NomacInspect", "NomacBuildService", "NomacCore", "NomacProject", "NomacTestSupport", "NomacVerify"],
            resources: [.copy("../NomacPIFTests/Fixtures")]
        ),
        .testTarget(
            name: "NomacPackagesTests",
            dependencies: [
                "NomacPackages", "NomacPIF", "NomacProject", "NomacCore", "NomacTestSupport",
                .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
            ]
        ),
        .testTarget(
            name: "NomacEnvelopeTests",
            dependencies: ["NomacEnvelope", "NomacCore", "NomacTestSupport"]
        ),
        .testTarget(
            name: "NomacVerifyTests",
            dependencies: ["NomacVerify"]
        ),
        .testTarget(
            name: "NomacPluginAPITests",
            dependencies: ["NomacPluginAPI", "NomacCore", "NomacTestSupport"]
        ),
        .testTarget(
            name: "NomacSDKTests",
            dependencies: ["NomacSDK", "NomacCore", "NomacTestSupport"]
        ),
        .testTarget(
            name: "NomacSigningTests",
            dependencies: ["NomacSigning", "NomacCore", "NomacTestSupport"]
        ),
        .testTarget(
            name: "NomacDistributionTests",
            dependencies: ["NomacDistribution", "NomacCore", .product(name: "Crypto", package: "swift-crypto")]
        ),
        .testTarget(
            name: "NomacDeviceTests",
            dependencies: ["NomacDevice", "NomacSigning", "NomacCore", "NomacTestSupport"]
        ),
        .testTarget(
            name: "NomacDeviceTestTests",
            dependencies: ["NomacDeviceTest", "NomacDevice", "NomacPlist", "NomacCore"]
        ),
        .testTarget(
            name: "NomacPackagingTests",
            dependencies: ["NomacPackaging", "NomacSigning", "NomacPlist", "NomacEnvelope", "NomacCore", "NomacTestSupport", "NomacAssets", "CSQLite"]
        ),
        .testTarget(
            name: "NomacPlistTests",
            dependencies: ["NomacPlist"]
        ),
        .testTarget(
            name: "NomacNibTests",
            dependencies: ["NomacNib", "NomacPlist", "NomacCore"]
        ),
        .testTarget(
            name: "NomacCoreDataTests",
            dependencies: ["NomacCoreData", "NomacCore", "NomacEnvelope", "NomacTestSupport"]
        ),
        .testTarget(
            name: "NomacIntentsTests",
            dependencies: ["NomacIntents", "NomacPlist", "NomacCore"]
        ),
        .testTarget(
            name: "NomacCoreMLTests",
            dependencies: ["NomacCoreML", "NomacCore", "NomacEnvelope", "NomacTestSupport"]
        ),
        .testTarget(
            name: "NomacStringsTests",
            dependencies: ["NomacStrings", "NomacPlist", "NomacCore"]
        ),
        .testTarget(
            name: "NomacAssetsTests",
            dependencies: ["NomacAssets", "NomacCore", "NomacEnvelope", "NomacPlist", "NomacTestSupport"]
        ),
        .testTarget(
            name: "NomacLZFSETests",
            dependencies: ["NomacLZFSE", "NomacCore"]
        ),
        .testTarget(
            name: "NomacBuildTests",
            dependencies: ["NomacBuild", "NomacBuildService", "NomacCore", "NomacPIF", "NomacPackaging", "NomacSigning", "NomacTestSupport", "NomacVerify", .product(name: "SwiftBuild", package: "swift-build")]
        ),
        .testTarget(
            name: "NomacMacrosTests",
            dependencies: ["NomacMacros", "NomacCore", "NomacTestSupport"]
        ),
        .testTarget(
            name: "NomacBuildServiceTests",
            dependencies: ["NomacBuildService", "NomacCore", "NomacTestSupport"]
        ),
        .testTarget(
            name: "nomacTests",
            dependencies: ["nomac", "NomacCore", "NomacPackaging", "NomacTestSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
