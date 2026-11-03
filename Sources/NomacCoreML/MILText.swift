import Foundation
import NomacCore

/// An ML program as coremlc prints it into `model.mil`: the `Program` message of coremltools'
/// public `MIL.proto` (BSD-3-Clause) written as text (coreml-experiments `programs`, `opsets`;
/// docs/formats/coreml.md "ML programs").
struct MILText {
    /// The opsets observed, by the name the specification gives them: the name printed, and the
    /// program version printed, from which scalars print as their type alone (`int32(4)`, not
    /// `tensor<int32, []>(4)`).
    static let opsets: [String: (name: String, version: String)] = [
        "CoreML5": ("ios15", "1.0"), "CoreML6": ("ios16", "1.0"), "CoreML7": ("ios17", "1.0"), "CoreML8": ("ios18", "1.3"),
    ]

    /// `MIL.proto`'s data types observed, by number.
    static let dataTypes: [Int64: String] = [1: "bool", 2: "string", 10: "fp16", 11: "fp32", 23: "int32", 33: "uint32", 34: "uint64"]

    let bareScalars: Bool

    /// The program's text, with the entries coremlc adds to its `buildInfo`.
    /// An input of flexible shape: its default shape and each dimension's range.
    struct FlexibleInput {
        var name: String
        var shape: [Int64]
        var ranges: [(Int64, Int64)]
    }

    static func text(_ program: ProtobufMessage, buildInfo: [(String, String)], flexibleInputs: [FlexibleInput]) throws
        -> (text: String, function: MILFunction) {
        let functions = try program.messages(2)
        guard functions.count == 1, let entry = functions.first, entry.string(1) == "main", let function = try entry.message(2) else {
            throw NomacError("ML programs with functions other than one `main` are not observed yet (BACKLOG B-240)")
        }
        let parsed = try MILFunction(function)
        let printer = MILText(bareScalars: parsed.programVersion == "1.3")
        var text = "program(\(parsed.programVersion))\n"
        let attributes = try program.messages(4)
        guard attributes.count == 1, attributes[0].string(1) == "buildInfo", let info = try attributes[0].message(2) else {
            throw NomacError("ML program attributes other than buildInfo are not observed yet (BACKLOG B-240)")
        }
        text += "[buildInfo = \(try printer.buildInfo(info, adding: buildInfo))]\n{\n"
        text += try printer.function(parsed, flexibleInputs: flexibleInputs)
        return (text + "}", parsed)
    }

    func buildInfo(_ value: ProtobufMessage, adding: [(String, String)]) throws -> String {
        var entries: [(String, String)] = adding
        let dictionary = try value.message(3)?.message(4) ?? ProtobufMessage()
        for pair in try dictionary.messages(1) {
            entries.append((try scalarString(pair.message(1)), try scalarString(pair.message(2))))
        }
        let string = bareScalars ? "string" : "tensor<string, []>"
        let body = entries.sorted { $0.0 < $1.0 }.map { "{\(quote($0.0)), \(quote($0.1))}" }.joined(separator: ", ")
        return "dict<\(string), \(string)>({\(body)})"
    }

    func scalarString(_ value: ProtobufMessage?) throws -> String {
        guard let tensor = try value?.message(3)?.message(1), let strings = try tensor.message(4), let text = strings.strings(1).first else {
            throw NomacError("a buildInfo entry that is not a string is not observed yet (BACKLOG B-240)")
        }
        return text
    }

    func function(_ function: MILFunction, flexibleInputs: [FlexibleInput]) throws -> String {
        let inputs = try function.inputs.sorted { $0.name < $1.name }.map { "\(try type($0.type)) \($0.name)" }.joined(separator: ", ")
        var text = "    func main<\(function.opsetName)>(\(inputs))"
        var attributes = try function.attributes.map { "\($0.0) = \(try value($0.1))" }
        if !flexibleInputs.isEmpty {
            attributes.append(flexibleShapeInformation(flexibleInputs.sorted { $0.name < $1.name }))
        }
        if !attributes.isEmpty {
            text += " [" + attributes.joined(separator: ", ") + "]"
        }
        text += " {\n"
        for operation in function.operations {
            text += try self.operation(operation)
        }
        return text + "        } -> (\(function.outputs.joined(separator: ", ")));\n"
    }

    func operation(_ operation: MILOperation) throws -> String {
        let outputs = try operation.outputs.map { "\(try type($0.type)) \($0.name)" }.joined(separator: ", ")
        let arguments = try operation.inputs.map { name, bindings in
            let printed = try bindings.map { binding -> String in
                if let reference = binding.string(1) { return reference }
                guard let bound = try binding.message(2) else { throw NomacError("an operation argument without a value") }
                return try value(bound)
            }
            return "\(name) = \(printed.count == 1 ? printed[0] : "(" + printed.joined(separator: ", ") + ")")"
        }.joined(separator: ", ")
        let attributes = try operation.attributes.map { "\($0.0) = \(try value($0.1))" }.joined(separator: ", ")
        return "            \(outputs) = \(operation.type)(\(arguments))[\(attributes)];\n"
    }

    /// The attribute coremlc adds to the function of a program whose description gives inputs
    /// ranges of shapes: their default shapes and ranges (coreml-experiments `programs`).
    func flexibleShapeInformation(_ inputs: [FlexibleInput]) -> String {
        let string = bareScalars ? "string" : "tensor<string, []>"
        let type = "tuple<tuple<\(string), dict<\(string), tensor<int32, [?]>>>, tuple<\(string), dict<\(string), list<tensor<int32, [2]>, ?>>>>"
        let defaults = inputs.map { "{\(quote($0.name)), [\($0.shape.map(String.init).joined(separator: ", "))]}" }.joined(separator: ", ")
        let ranges = inputs.map { input in
            "{\(quote(input.name)), [\(input.ranges.map { "[\($0.0), \($0.1)]" }.joined(separator: ", "))]}"
        }.joined(separator: ", ")
        return "FlexibleShapeInformation = \(type)(((\"DefaultShapes\", {\(defaults)}), (\"RangeDims\", {\(ranges)})))"
    }

    /// A value with its type: `tensor<int32, [2]>([0, 1])`, `string("fp16")`, a blob file's
    /// `BLOBFILE(path = ..., offset = ...)`.
    func value(_ value: ProtobufMessage) throws -> String {
        let valueType = try value.message(2) ?? ProtobufMessage()
        if let blob = try value.message(5) {
            let path = "\(bareScalars ? "string" : "tensor<string, []>")(\(quote(blob.string(1) ?? "")))"
            let offset = "\(bareScalars ? "uint64" : "tensor<uint64, []>")(\(UInt64(bitPattern: try blob.integer(2))))"
            return "\(try type(valueType))(BLOBFILE(path = \(path), offset = \(offset)))"
        }
        guard let immediate = try value.message(3) else { throw NomacError("an ML program value that is neither immediate nor in a file") }
        return "\(try type(valueType))(\(try bare(immediate, type: valueType)))"
    }

    /// A value without its type, as it is printed inside another: `[1, 3]`, `"x"`, `(a, b)`,
    /// `{{k, v}}`.
    func bare(_ immediate: ProtobufMessage, type valueType: ProtobufMessage) throws -> String {
        if let tensor = try immediate.message(1) {
            guard let tensorType = try valueType.message(1) else { throw NomacError("a tensor value whose type is not a tensor") }
            return try self.tensor(tensor, type: tensorType)
        }
        if let tuple = try immediate.message(2) {
            let types = try valueType.message(3)?.messages(1) ?? []
            let values = try tuple.messages(1)
            guard types.count == values.count else { throw NomacError("a tuple value whose type has another length") }
            return "(" + (try zip(values, types).map { try bare($0.0.message(3) ?? ProtobufMessage(), type: $0.1) }.joined(separator: ", ")) + ")"
        }
        if let list = try immediate.message(3) {
            let elementType = try valueType.message(2)?.message(1) ?? ProtobufMessage()
            return "[" + (try list.messages(1).map { try bare($0.message(3) ?? ProtobufMessage(), type: elementType) }.joined(separator: ", ")) + "]"
        }
        if let dictionary = try immediate.message(4) {
            let types = try valueType.message(4) ?? ProtobufMessage()
            let keyType = try types.message(1) ?? ProtobufMessage(), valueType = try types.message(2) ?? ProtobufMessage()
            let entries = try dictionary.messages(1).map { pair in
                (try bare(pair.message(1)?.message(3) ?? ProtobufMessage(), type: keyType),
                 try bare(pair.message(2)?.message(3) ?? ProtobufMessage(), type: valueType))
            }
            return "{" + entries.sorted { $0.0 < $1.0 }.map { "{\($0.0), \($0.1)}" }.joined(separator: ", ") + "}"
        }
        throw NomacError("an ML program value of a kind not observed yet (BACKLOG B-240)")
    }

    /// A tensor's elements, nested by its dimensions.
    func tensor(_ tensor: ProtobufMessage, type tensorType: ProtobufMessage) throws -> String {
        let dataType = try tensorType.integer(1)
        let shape = try MILFunction.dimensions(tensorType)
        let elements: [String]
        switch dataType {
        case 11: elements = try floats(tensor.message(1)).map { Self.hexFloat(Double($0)) }
        case 10: elements = try bytes(tensor).chunks(of: 2).map { Self.hexFloat(Double(Float16(bitPattern: $0.reversed().reduce(UInt16(0)) { $0 << 8 | UInt16($1) }))) }
        case 23: elements = try (tensor.message(2)?.integers(1) ?? []).map { String(Int32(truncatingIfNeeded: $0)) }
        case 33: elements = try bytes(tensor).chunks(of: 4).map { String($0.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) }
        case 1: elements = try (tensor.message(3)?.integers(1) ?? []).map { $0 != 0 ? "true" : "false" }
        case 2: elements = try (tensor.message(4)?.strings(1) ?? []).map(quote)
        default: throw NomacError("ML program values of data type \(dataType) are not observed yet (BACKLOG B-240)")
        }
        guard !shape.isEmpty else {
            guard elements.count == 1 else { throw NomacError("a scalar with \(elements.count) values") }
            return elements[0]
        }
        func nest(_ dimensions: ArraySlice<Int64?>, _ values: ArraySlice<String>) throws -> String {
            guard let first = dimensions.first else { return values.first ?? "" }
            if dimensions.count == 1 { return "[" + values.joined(separator: ", ") + "]" }
            guard let size = first, size > 0, values.count % Int(size) == 0 else {
                throw NomacError("a nested tensor value with a dimension of unknown size is not observed yet (BACKLOG B-240)")
            }
            let stride = values.count / Int(size)
            return "[" + (try (0..<Int(size)).map { index in
                try nest(dimensions.dropFirst(), values[(values.startIndex + index * stride)..<(values.startIndex + (index + 1) * stride)])
            }.joined(separator: ", ")) + "]"
        }
        return try nest(shape[...], elements[...])
    }

    func floats(_ message: ProtobufMessage?) throws -> [Float] {
        guard let message else { return [] }
        return message.all(1).flatMap { field -> [Float] in
            stride(from: 0, to: field.payload.count - 3, by: 4).map { index in
                Float(bitPattern: field.payload[index..<index + 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            }
        }
    }

    func bytes(_ tensor: ProtobufMessage) throws -> [UInt8] {
        try tensor.message(7)?.first(1)?.payload ?? []
    }

    func type(_ valueType: ProtobufMessage) throws -> String {
        if let tensorType = try valueType.message(1) {
            let code = try tensorType.integer(1)
            guard let name = Self.dataTypes[code] else { throw NomacError("ML program data type \(code) is not observed yet (BACKLOG B-240)") }
            let dimensions = try MILFunction.dimensions(tensorType)
            if dimensions.isEmpty && bareScalars { return name }
            return "tensor<\(name), [\(dimensions.map { $0.map(String.init) ?? "?" }.joined(separator: ", "))]>"
        }
        if let list = try valueType.message(2) {
            let length = try list.message(2).map { try MILFunction.dimension($0) } ?? nil
            return "list<\(try type(list.message(1) ?? ProtobufMessage())), \(length.map(String.init) ?? "?")>"
        }
        if let tuple = try valueType.message(3) {
            return "tuple<" + (try tuple.messages(1).map(type).joined(separator: ", ")) + ">"
        }
        if let dictionary = try valueType.message(4) {
            return "dict<\(try type(dictionary.message(1) ?? ProtobufMessage())), \(try type(dictionary.message(2) ?? ProtobufMessage()))>"
        }
        throw NomacError("ML program value types other than tensors, lists, tuples and dictionaries are not observed yet (BACKLOG B-240)")
    }

    func quote(_ text: String) -> String {
        "\"\(text)\""
    }

    /// A number as C's `%a` prints a double: `0x1.8p+1`, `0x0p+0`, `-0x1p-1`.
    static func hexFloat(_ value: Double) -> String {
        let sign = value.sign == .minus ? "-" : ""
        if value == 0 { return sign + "0x0p+0" }
        let bits = value.bitPattern
        let exponent = Int((bits >> 52) & 0x7FF) - 1023
        var digits = String(bits & 0xF_FFFF_FFFF_FFFF, radix: 16)
        digits = String(repeating: "0", count: 13 - digits.count) + digits
        while digits.hasSuffix("0") { digits.removeLast() }
        return sign + "0x1" + (digits.isEmpty ? "" : "." + digits) + "p" + (exponent < 0 ? "-" : "+") + String(abs(exponent))
    }
}

/// The function of an ML program, read from its `Function` message.
struct MILFunction {
    struct NamedType {
        var name: String
        var type: ProtobufMessage
    }

    var opset: String
    var opsetName: String
    var programVersion: String
    var inputs: [NamedType]
    var attributes: [(String, ProtobufMessage)]
    var operations: [MILOperation]
    var outputs: [String]

    init(_ function: ProtobufMessage) throws {
        opset = function.string(2) ?? ""
        guard let known = MILText.opsets[opset] else {
            throw NomacError("ML programs of opset \(opset) are not observed yet (BACKLOG B-240)")
        }
        opsetName = known.name
        programVersion = known.version
        inputs = try function.messages(1).map { NamedType(name: $0.string(1) ?? "", type: try $0.message(2) ?? ProtobufMessage()) }
        attributes = try Self.map(function, field: 4).sorted { $0.0 < $1.0 }
        let blocks = try function.messages(3)
        guard blocks.count == 1, blocks[0].string(1) == opset, let block = try blocks[0].message(2) else {
            throw NomacError("ML program functions with block specializations other than their opset's are not observed yet (BACKLOG B-240)")
        }
        operations = try block.messages(3).map(MILOperation.init)
        outputs = block.strings(2)
    }

    /// A `map<string, Value>` field's entries.
    static func map(_ message: ProtobufMessage, field: Int) throws -> [(String, ProtobufMessage)] {
        try message.messages(field).map { ($0.string(1) ?? "", try $0.message(2) ?? ProtobufMessage()) }
    }

    /// A tensor type's dimensions, `nil` for those of unknown size.
    static func dimensions(_ tensorType: ProtobufMessage) throws -> [Int64?] {
        try tensorType.messages(3).map(dimension)
    }

    static func dimension(_ message: ProtobufMessage) throws -> Int64? {
        if let constant = try message.message(1) { return try constant.integer(1) }
        if let unknown = try message.message(2), try unknown.integer(1) == 0 { return nil }
        throw NomacError("variadic ML program dimensions are not observed yet (BACKLOG B-240)")
    }
}

/// An operation of an ML program's block.
struct MILOperation {
    var type: String
    /// Arguments by name, sorted, each a list of bindings (`Argument.Binding`).
    var inputs: [(String, [ProtobufMessage])]
    var outputs: [MILFunction.NamedType]
    var attributes: [(String, ProtobufMessage)]

    init(_ message: ProtobufMessage) throws {
        type = message.string(1) ?? ""
        guard try message.messages(4).isEmpty else {
            throw NomacError("ML program operations with nested blocks (\(type)) are not observed yet (BACKLOG B-240)")
        }
        inputs = try message.messages(2).map { entry in
            (entry.string(1) ?? "", try entry.message(2)?.messages(1) ?? [])
        }.sorted { $0.0 < $1.0 }
        outputs = try message.messages(3).map { MILFunction.NamedType(name: $0.string(1) ?? "", type: try $0.message(2) ?? ProtobufMessage()) }
        attributes = try MILFunction.map(message, field: 5).sorted { $0.0 < $1.0 }
    }
}

extension Array {
    func chunks(of size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
