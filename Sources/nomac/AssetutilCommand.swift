import ArgumentParser
import Foundation
import NomacAssets
import NomacCore

/// `nomac assetutil`: thins an `Assets.car` for one device as macOS's `assetutil` does with the
/// same options (the tool Xcode's app thinning runs).
struct AssetutilCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assetutil",
        abstract: "Thin a compiled asset catalog (Assets.car) for a device, as assetutil does.",
        discussion: """
        Takes assetutil's thinning options, for example: -i phone -s 3 -t 2436 -p P3 -h car -g APPLE5 \
        -k APPLE4:APPLE3:APPLE3v1:APPLE2:APPLE1:GLES2,0 -M 3 -r 18.0 -o <out.car> <in.car>. See \
        docs/formats/asset-catalog.md "Thinning" for what is supported.
        """,
        shouldDisplay: false,
        helpNames: [.long]
    )

    @Option(name: [.customShort("i"), .customLong("idiom")]) var idiom: String
    @Option(name: [.customShort("s"), .customLong("scale")]) var scale: Int
    @Option(name: [.customShort("t"), .customLong("subtype")]) var subtype: Int?
    @Option(name: [.customShort("u"), .customLong("subtypefallbacks")]) var subtypeFallbacks: String?
    @Option(name: [.customShort("p"), .customLong("display-gamut")]) var displayGamut: String?
    @Option(name: [.customShort("h"), .customLong("hostedidioms")]) var hostedIdioms: String?
    @Option(name: [.customShort("g"), .customLong("graphicsclass")]) var graphicsClass: String
    @Option(name: [.customShort("k"), .customLong("graphicsclassfallbacks")]) var graphicsFallbacks: String = ""
    @Option(name: [.customShort("M"), .customLong("memory")]) var memory: Int
    @Option(name: [.customShort("r"), .customLong("deployment-target")]) var deploymentTarget: String
    @Option(name: [.customShort("o"), .customLong("output")]) var output: String
    @Argument var input: String

    func run() throws {
        let input = FileSystem.absolute(self.input), output = FileSystem.absolute(self.output)
        guard let data = FileManager.default.contents(atPath: input) else { throw NomacError("cannot read the catalog", path: input) }
        let traits = ThinningTraits(idiom: idiom, scale: scale, subtype: subtype, subtypeFallbacks: subtypeFallbacks, displayGamut: displayGamut,
                                    hostedIdioms: hostedIdioms.map { $0.split(separator: ",").map(String.init) } ?? [],
                                    graphicsClass: graphicsClass, graphicsFallbacks: graphicsFallbacks.split(separator: ":").map(String.init),
                                    memory: memory, deploymentTarget: deploymentTarget)
        try FileSystem.write(Data(try CARThinning.thin([UInt8](data), for: traits, path: input)), to: output)
    }
}
