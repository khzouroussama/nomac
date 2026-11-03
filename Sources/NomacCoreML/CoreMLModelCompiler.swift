import Foundation
import NomacCore
import NomacPlist

/// `coremlc compile` as Xcode 27.0's writes a model's `.mlmodelc` (docs/formats/coreml.md), for the
/// model types it stores as a `spec` archive.
public enum CoreMLModelCompiler {
    /// The model types observed as `spec` archives (coreml-experiments `tools`, `types`).
    static let specArchiveTypes: Set<Int> = [300, 301, 400, 600, 601, 602, 604, 606, 607, 609, 900]

    /// iOS, macOS, tvOS, watchOS, visionOS and Mac Catalyst availability by specification version
    /// (coreml-experiments `types`, versions 1 to 9).
    static let availability: [Int64: (iOS: String, macOS: String, watchOS: String, visionOS: String)] = [
        1: ("11.0", "10.13", "4.0", "1.0"), 2: ("11.2", "10.13.2", "4.2", "1.0"), 3: ("12.0", "10.14", "5.0", "1.0"),
        4: ("13.0", "10.15", "6.0", "1.0"), 5: ("14.0", "11.0", "7.0", "1.0"), 6: ("15.0", "12.0", "8.0", "1.0"),
        7: ("16.0", "13.0", "9.0", "1.0"), 8: ("17.0", "14.0", "10.0", "1.0"), 9: ("18.0", "15.0", "11.0", "2.0"),
    ]

    /// The insertion order fitted to every observed top-level `metadata.json` dictionary: a
    /// mutable Foundation table filled in this order, then copied (coreml-experiments `metadata`,
    /// 20 different key sets).
    static let insertionOrder = ["author", "outputSchema", "license", "availability", "modelType", "classLabels", "modelParameters", "version",
                                 "shortDescription", "metadataOutputVersion", "method", "specificationVersion", "inputSchema", "stateSchema",
                                 "isUpdatable", "generatedClassName", "userDefinedMetadata", "mlProgramOperationTypeHistogram",
                                 "neuralNetworkLayerTypeHistogram", "storagePrecision", "computePrecision"]

    public struct Output: Sendable {
        /// Files of the `.mlmodelc` directory by path inside it.
        public var files: [String: [UInt8]]
        /// The model's name: its file name without extension.
        public var name: String
    }

    /// The compiled model of the `.mlmodel` or `.mlpackage` at `path`.
    public static func compile(_ path: String) throws -> Output {
        let specificationPath = try ModelSpecification.specificationPath(of: path)
        let bytes = Array(try Data(contentsOf: URL(fileURLWithPath: specificationPath)))
        let specification = try ModelSpecification(bytes: bytes)
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            throw NomacError("the class name coremlc derives from the file name \(name) is not observed yet (BACKLOG B-240)", path: path)
        }
        guard let type = specification.typeField, specArchiveTypes.contains(type) || type == mlProgramType else {
            throw NomacError("nomac does not compile \(specification.typeName) models yet (BACKLOG \(specification.typeName.hasPrefix("neuralNetwork") ? "B-242" : "B-240"))", path: path)
        }
        let version = specification.specificationVersion
        guard availability[version] != nil else {
            throw NomacError("the availability of specification version \(version) is not observed yet (BACKLOG B-240)", path: path)
        }
        if try specification.message.integer(10) != 0 {
            throw NomacError("updatable models are not observed yet (BACKLOG B-240)", path: path)
        }
        var description = try specification.message.message(2) ?? ProtobufMessage()
        for (field, what) in [(13, "state features"), (20, "functions"), (50, "training inputs")] where description.has(field) {
            throw NomacError("models with \(what) are not observed yet (BACKLOG B-240)", path: path)
        }
        var model = specification.message
        if !description.has(100) {
            description.set(100, message: ProtobufMessage())
        }
        model.set(2, message: description)

        // A package's analytics name its specification file, `model` (coreml-experiments `tools`).
        let specificationName = ((specificationPath as NSString).lastPathComponent as NSString).deletingPathExtension
        if type == mlProgramType {
            return try program(specification, description: description, model: model, name: name, specificationName: specificationName,
                               bytes: bytes, directory: (specificationPath as NSString).deletingLastPathComponent)
        }
        let metadata = try Self.metadata(specification, description: description, type: type, name: name)
        return Output(files: [
            "coremldata.bin": specArchive(type: type, version: version) + model.bytes,
            "metadata.json": Array(metadata.pretty.utf8),
            "analytics/coremldata.bin": analytics([("SpecificationDetails", [("modelHash", Data(SHA256.digest(bytes)).base64EncodedString()), ("modelName", specificationName)])]),
        ], name: name)
    }

    static let mlProgramType = 502

    /// An ML program (docs/formats/coreml.md "ML programs"): a `generic` archive of its
    /// description, the program as MIL text, the weight files it reads, and in `metadata.json` the
    /// operations it counts and the precisions of its values.
    static func program(_ specification: ModelSpecification, description: ProtobufMessage, model: ProtobufMessage, name: String,
                        specificationName: String, bytes: [UInt8], directory: String) throws -> Output {
        let profile = XcodeProfile.current.coremlc
        let program = try model.message(mlProgramType) ?? ProtobufMessage()
        var flexibleInputs: [MILText.FlexibleInput] = []
        for input in try description.messages(1).map(ModelFeature.init) {
            guard case .multiArray(_, let shape, let flexibility) = input.kind, let flexibility else { continue }
            guard case .ranges(let ranges) = flexibility else {
                throw NomacError("ML programs whose inputs have enumerated shapes are not observed yet (BACKLOG B-240)")
            }
            flexibleInputs.append(.init(name: input.name, shape: shape, ranges: ranges.map { ($0.lower, $0.upper) }))
        }
        let (text, function) = try MILText.text(program, buildInfo: [("coremlc-component-MIL", profile.milComponentVersion),
                                                                    ("coremlc-version", profile.version)],
                                                flexibleInputs: flexibleInputs)
        var histogram: [String: Int] = [:]
        var operationOrder: [String] = []
        var computed: Set<String> = [], stored: Set<String> = [], blobFiles: Set<String> = []
        for operation in function.operations {
            for output in operation.outputs {
                if let precision = try precision(output.type) { computed.insert(precision) }
            }
            if operation.type == "const" {
                if let value = operation.attributes.first(where: { $0.0 == "val" })?.1, let blob = try value.message(5) {
                    guard let precision = try precision(value.message(2) ?? ProtobufMessage()) else {
                        throw NomacError("ML program weights of a type other than numbers are not observed yet (BACKLOG B-240)")
                    }
                    stored.insert(precision)
                    blobFiles.insert(blob.string(1) ?? "")
                }
                continue
            }
            guard let counted = MILOperations.histogramName(operation.type, opset: function.opset) else {
                throw NomacError("the name Core ML counts the operation \(operation.type) of an \(function.opsetName) program under is not observed yet (BACKLOG B-245)")
            }
            if histogram[counted] == nil { operationOrder.append(counted) }
            histogram[counted, default: 0] += 1
        }
        var files: [String: [UInt8]] = [
            "coremldata.bin": try genericArchive(type: mlProgramType, version: specification.specificationVersion, description: description),
            "analytics/coremldata.bin": analytics([
                ("NeuralNetworkModelDetails", [("containsCustomLayer", "0"), ("modelDimension", "0")]),
                ("SpecificationDetails", [("modelHash", Data(SHA256.digest(bytes)).base64EncodedString()), ("modelName", specificationName)]),
            ]),
            "model.mil": Array(text.utf8),
        ]
        for file in blobFiles {
            guard file.hasPrefix("@model_path/") else { throw NomacError("an ML program weight file outside the model: \(file)") }
            let relative = String(file.dropFirst("@model_path/".count))
            files[relative] = Array(try Data(contentsOf: URL(fileURLWithPath: (directory as NSString).appendingPathComponent(relative))))
        }
        var extra: [String: FoundationJSON] = [
            "mlProgramOperationTypeHistogram": try MetadataWriter.object(histogram.mapValues { .int($0) }, insertionOrder: operationOrder),
            "computePrecision": .string(Self.precisionName(computed)),
        ]
        if !stored.isEmpty { extra["storagePrecision"] = .string(Self.precisionName(stored)) }
        files["metadata.json"] = Array(try Self.metadata(specification, description: description, type: mlProgramType, name: name, extra: extra).pretty.utf8)
        return Output(files: files, name: name)
    }

    /// The precisions `metadata.json` lists, by `MIL.proto` data type; booleans and strings are
    /// left out (coreml-experiments `programs`, `opsets`).
    static let precisions: [Int64: String] = [10: "Float16", 11: "Float32", 23: "Int32", 33: "UInt32"]

    static func precision(_ valueType: ProtobufMessage) throws -> String? {
        guard let tensorType = try valueType.message(1) else { return nil }
        let code = try tensorType.integer(1)
        if code == 1 || code == 2 { return nil }
        guard let name = precisions[code] else { throw NomacError("the precision coremlc names for ML program data type \(code) is not observed yet (BACKLOG B-240)") }
        return name
    }

    static func precisionName(_ precisions: Set<String>) -> String {
        precisions.count == 1 ? precisions.first! : "Mixed (\(precisions.sorted().joined(separator: ", ")))"
    }

    /// The archive version of an ML program's `generic` archive, by specification version
    /// (coreml-experiments `programs`).
    static let programArchiveVersions: [Int64: UInt64] = [6: 5, 7: 5, 8: 8, 9: 9]

    /// A `generic` archive: the type's field number, the archive version, the kind, the
    /// specification version, the description's length and bytes, then the type again and a zero,
    /// as 64-bit words.
    static func genericArchive(type: Int, version: Int64, description: ProtobufMessage) throws -> [UInt8] {
        guard let archiveVersion = programArchiveVersions[version] else {
            throw NomacError("the archive of an ML program of specification version \(version) is not observed yet (BACKLOG B-240)")
        }
        var header = [UInt8](repeating: 0, count: 0x53)
        func put(_ value: UInt64, at offset: Int, size: Int, into bytes: inout [UInt8]) {
            for index in 0..<size { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * UInt64(index))) }
        }
        let body = description.bytes
        put(UInt64(type), at: 0, size: 4, into: &header)
        put(archiveVersion, at: 4, size: 4, into: &header)
        put(7, at: 0x1c, size: 8, into: &header)
        header.replaceSubrange(0x24..<0x2b, with: Array("generic".utf8))
        put(UInt64(version), at: 0x2b, size: 4, into: &header)
        put(UInt64(body.count), at: 0x4b, size: 8, into: &header)
        var trailer = [UInt8](repeating: 0, count: 16)
        put(UInt64(type), at: 0, size: 8, into: &trailer)
        return header + body + trailer
    }

    /// Writes the compiled model into `directory` as `<name>.mlmodelc`, and the partial Info.plist
    /// when asked.
    public static func write(_ path: String, to directory: String, partialInfoPlist: String?) throws -> String {
        let output = try compile(path)
        let bundle = (directory as NSString).appendingPathComponent(output.name + ".mlmodelc")
        try? FileManager.default.removeItem(atPath: bundle)
        for (file, contents) in output.files {
            try FileSystem.write(Data(contents), to: (bundle as NSString).appendingPathComponent(file))
        }
        if let partialInfoPlist {
            try FileSystem.write(Data(Self.partialInfoPlist.utf8), to: partialInfoPlist)
        }
        return bundle
    }

    /// The partial Info.plist, the same for every model observed.
    static let partialInfoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>LSBundleContainsCoreMLmlmodelc</key>
        \t<true/>
        </dict>
        </plist>

        """

    /// The 72 bytes before the specification in a `spec` archive: the type's field number, 1, the
    /// kind's length and name, and the specification version.
    static func specArchive(type: Int, version: Int64) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 0x48)
        func put(_ value: UInt64, at offset: Int, size: Int) {
            for index in 0..<size { header[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * UInt64(index))) }
        }
        put(UInt64(type), at: 0, size: 4)
        put(1, at: 4, size: 4)
        put(4, at: 0x1c, size: 8)
        header.replaceSubrange(0x24..<0x28, with: Array("spec".utf8))
        put(UInt64(version), at: 0x28, size: 4)
        return header
    }

    /// `analytics/coremldata.bin`: each group's name, its entry count and its entries, every string
    /// after its 64-bit length.
    static func analytics(_ groups: [(String, [(String, String)])]) -> [UInt8] {
        var out: [UInt8] = []
        func append(_ value: UInt64) {
            for index in 0..<8 { out.append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(index)))) }
        }
        func append(_ string: String) {
            append(UInt64(string.utf8.count))
            out += Array(string.utf8)
        }
        for (group, entries) in groups {
            append(group)
            append(UInt64(entries.count))
            for (key, value) in entries {
                append(key)
                append(value)
            }
        }
        return out
    }

    static func metadata(_ specification: ModelSpecification, description: ProtobufMessage, type: Int, name: String,
                         extra: [String: FoundationJSON] = [:]) throws -> FoundationJSON {
        let version = specification.specificationVersion
        let platforms = availability[version]!
        let metadata = try description.message(100) ?? ProtobufMessage()
        var userDefined: [String: FoundationJSON] = [:]
        var userKeys: [String] = []
        for entry in try metadata.messages(100) {
            let key = entry.string(1) ?? ""
            if userDefined[key] == nil { userKeys.append(key) }
            userDefined[key] = .string(entry.string(2) ?? "")
        }
        var values: [String: FoundationJSON] = [
            "metadataOutputVersion": .string("3.0"),
            "inputSchema": .array(try description.messages(1).map { try ModelFeature($0).metadata() }),
            "outputSchema": .array(try description.messages(10).map { try ModelFeature($0).metadata() }),
            "modelParameters": .array([]),
            "stateSchema": .array([]),
            "specificationVersion": .int(Int(version)),
            "isUpdatable": .string("0"),
            "availability": try MetadataWriter.object([
                "iOS": .string(platforms.iOS), "macCatalyst": .string(platforms.iOS), "macOS": .string(platforms.macOS),
                "tvOS": .string(platforms.iOS), "visionOS": .string(platforms.visionOS), "watchOS": .string(platforms.watchOS),
            ], insertionOrder: ["iOS", "macCatalyst", "macOS", "tvOS", "visionOS", "watchOS"]),
            "modelType": .orderedObject([.init("name", .string("MLModelType_" + specification.typeName))]),
            "userDefinedMetadata": try MetadataWriter.object(userDefined, insertionOrder: userKeys),
            "generatedClassName": .string(name),
            "method": .string("predict"),
        ]
        for (field, key) in [(1, "shortDescription"), (2, "version"), (3, "author"), (4, "license")] {
            if let text = metadata.string(field), !text.isEmpty { values[key] = .string(text) }
        }
        if type == 400, let classifier = try specification.message.message(type) {
            if let labels = try classifier.message(100) {
                values["classLabels"] = .array(labels.strings(1).map { .string($0) })
            } else if let labels = try classifier.message(101) {
                values["classLabels"] = .array(try labels.integers(1).map { .int(Int($0)) })
            }
        }
        values.merge(extra) { $1 }
        return .array([try MetadataWriter.object(values, insertionOrder: insertionOrder)])
    }
}

/// Dictionaries as coremlc's `metadata.json` lists them: the keys in the iteration order of a
/// mutable Foundation table filled in a given order, then copied (docs/formats/coreml.md).
enum MetadataWriter {
    static func object(_ values: [String: FoundationJSON], insertionOrder: [String]) throws -> FoundationJSON {
        let keys = insertionOrder.filter { values[$0] != nil }
        guard keys.count == values.count else {
            throw NomacError("metadata keys whose order is not observed: \(Set(values.keys).subtracting(keys).sorted())")
        }
        // Tables of more keys than any copy observed keep the mutable table's order: programs
        // counting 124 to 127 operations (coreml-experiments `opsets`).
        let table = try FoundationHashTable.inserting(keys)
        let ordered = keys.count > FoundationHashTable.copyCapacities.last! ? table.keys : try table.copied().keys
        return .orderedObject(ordered.map { .init($0, values[$0]!) })
    }
}
