import Foundation
import NomacCore

/// A Core ML model's specification, the `Model` message of Core ML's public format
/// (coremltools' `mlmodel/format/Model.proto`, BSD-3-Clause): what nomac reads of it.
public struct ModelSpecification: Sendable {
    /// The `Model` message as read.
    public var message: ProtobufMessage

    public init(bytes: [UInt8]) throws {
        message = try ProtobufMessage(bytes: bytes)
    }

    /// Reads a `.mlmodel` file, or the root model of a `.mlpackage` (its `Manifest.json`'s
    /// `rootModelIdentifier` item).
    public static func read(at path: String) throws -> ModelSpecification {
        try ModelSpecification(bytes: Array(try Data(contentsOf: URL(fileURLWithPath: try specificationPath(of: path)))))
    }

    /// The file of a model's specification: the `.mlmodel` itself, or the root model a package's
    /// manifest names.
    public static func specificationPath(of path: String) throws -> String {
        guard (path as NSString).pathExtension == "mlpackage" else { return path }
        let manifestPath = (path as NSString).appendingPathComponent("Manifest.json")
        guard let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: manifestPath))) as? [String: Any],
              let root = manifest["rootModelIdentifier"] as? String,
              let item = (manifest["itemInfoEntries"] as? [String: Any])?[root] as? [String: Any],
              let name = item["path"] as? String else {
            throw NomacError("the package's Manifest.json names no root model", path: manifestPath)
        }
        return ((path as NSString).appendingPathComponent("Data") as NSString).appendingPathComponent(name)
    }

    public var specificationVersion: Int64 {
        (try? message.integer(1)) ?? 0
    }

    /// The field of the `Type` one-of that is set, by its number in `Model.proto`.
    public var typeField: Int? {
        message.fields.map(\.number).first { Self.typeNames[$0] != nil }
    }

    /// The name of the model's type, as `Model.proto` names the one-of's field.
    public var typeName: String {
        typeField.flatMap { Self.typeNames[$0] } ?? "unknown"
    }

    /// The fields of `Model.proto`'s `Type` one-of.
    public static let typeNames: [Int: String] = [
        200: "pipelineClassifier", 201: "pipelineRegressor", 202: "pipeline", 300: "glmRegressor", 301: "supportVectorRegressor",
        302: "treeEnsembleRegressor", 303: "neuralNetworkRegressor", 304: "bayesianProbitRegressor", 400: "glmClassifier",
        401: "supportVectorClassifier", 402: "treeEnsembleClassifier", 403: "neuralNetworkClassifier", 404: "kNearestNeighborsClassifier",
        500: "neuralNetwork", 501: "itemSimilarityRecommender", 502: "mlProgram", 555: "customModel", 556: "linkedModel",
        560: "classConfidenceThresholding", 600: "oneHotEncoder", 601: "imputer", 602: "featureVectorizer", 603: "dictVectorizer",
        604: "scaler", 606: "categoricalMapping", 607: "normalizer", 609: "arrayFeatureExtractor", 610: "nonMaximumSuppression",
        900: "identity", 2000: "textClassifier", 2001: "wordTagger", 2002: "visionFeaturePrint", 2003: "soundAnalysisPreprocessing",
        2004: "gazetteer", 2005: "wordEmbedding", 2006: "audioFeaturePrint", 3000: "serializedModel",
    ]
}
