import Foundation
import NomacCore
import NomacEnvelope
import NomacProject

/// `nomac check`'s `coreml:` domain (ADR 0011): the Core ML models targets compile, by the model
/// type their specification sets (`coreml:model=<type>`, the field of `Model.proto`'s `Type`
/// one-of), each compiled and its Swift classes generated in memory as a build runs nomac's
/// coremlc, so that a model nomac refuses is reported before a build stops on it.
public struct CoreMLDomain: FeatureDomain {
    public let name = "coreml"
    public var envelope: Envelope { Self.envelope }

    public init() {}

    static let compiled = ["glmRegressor", "supportVectorRegressor", "glmClassifier", "oneHotEncoder", "imputer", "featureVectorizer",
                           "scaler", "categoricalMapping", "normalizer", "arrayFeatureExtractor", "identity", "mlProgram"]

    static let envelope = Envelope(domain: "coreml", entries: compiled.map {
        .verified("coreml:model=\($0)", $0 == "mlProgram" ? "coreml-experiments:program-validation" : "coreml-experiments:validation")
    } + [
        .unverified("coreml:model=unreadable", "the model's specification is not a Core ML model nomac can read", backlog: "B-240"),
    ], family: { feature in
        if feature.hasPrefix("coreml:refused="), let item = feature.split(separator: "=").last {
            return item.hasPrefix("B-") ? .unverified(feature, "nomac's coremlc refuses the model", backlog: String(item))
                : .unverified(feature, "nomac's coremlc fails on the model with an error that names no BACKLOG item")
        }
        guard feature.hasPrefix("coreml:model=") else { return nil }
        return .unverified(feature, "Xcode compiles Core ML models with coremlc, which runs only on macOS, and nomac does not compile this model type yet (docs/adr/0240-core-ml-and-metal-on-linux.md): build on a Mac", backlog: "B-240")
    })

    public func scan(_ container: String, options: CheckOptions) throws -> DomainScan {
        let workspace = try XcodeWorkspace.load(path: FileSystem.absolute(container))
        var scan = DomainScan()
        for model in ProjectFiles.files(of: workspace, extensions: ["mlmodel", "mlpackage"], kind: "Core ML models", options: options,
                                        unchecked: &scan.unchecked) {
            let name = (model as NSString).lastPathComponent
            if options.descriptionOnly {
                scan.unchecked.append(UncheckedPart(what: "Core ML model contents", file: model))
                continue
            }
            let type = (try? ModelSpecification.read(at: model))?.typeName ?? "unreadable"
            scan.uses.append(FeatureUse(feature: "coreml:model=\(type)", file: model, object: name))
            if Self.compiled.contains(type), let refusal = Self.refusal(model) {
                let item = refusal.firstMatch(of: /BACKLOG (B-\d+)/).map { String($0.1) } ?? "unexplained"
                scan.uses.append(FeatureUse(feature: "coreml:refused=\(item)", file: model, object: refusal))
            }
        }
        scan.unchecked.sort()
        return scan
    }

    /// The first error of what a build runs on the model: the compile and Swift classes.
    static func refusal(_ model: String) -> String? {
        do {
            _ = try CoreMLModelCompiler.compile(model)
            _ = try SwiftClassGenerator(path: model, swiftVersion: "5.0", publicAccess: false).file
            return nil
        } catch {
            return "\(error)".replacingOccurrences(of: model + ": ", with: "")
        }
    }
}
