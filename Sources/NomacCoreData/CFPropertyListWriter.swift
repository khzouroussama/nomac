import NomacPlist

/// Core Foundation's binary property list writer (`bplist00`) as momc runs it, where sharing
/// follows object identity, not value (docs/formats/coredata.md "Keyed archives"): a string or
/// number already written is referenced again; booleans and archive UIDs are written at every
/// use, every reference naming the first one of that value; containers and data are never shared.
enum CFPropertyListWriter {
    indirect enum Node {
        case dictionary([(Node, Node)])
        case array([Node])
        /// Strings of one `shared` kind and text are one object; nil makes a new one.
        case string(String, shared: String?)
        /// Integers of one `shared` kind and value are one object (tagged `NSNumber`s of one type).
        case integer(Int, shared: String)
        case double(Double, shared: Bool)
        case float(Float)
        case boolean(Bool)
        case uid(Int)
        case data([UInt8])

        /// A string constant of the writing tool: keys, `$null`, the archiver's name.
        static func constant(_ string: String) -> Node { .string(string, shared: "constant") }
    }

    static func data(_ root: Node) -> [UInt8] {
        var flattener = Flattener()
        _ = flattener.flatten(root)
        return Array(BinaryPropertyList.data(objects: flattener.objects))
    }

    private struct Flattener {
        var objects: [BinaryPropertyList.Object] = []
        var shared: [String: Int] = [:]
        var firstBooleans: [Bool: Int] = [:]
        var firstUIDs: [Int: Int] = [:]

        /// Appends `node` and what it holds, depth first: a dictionary, then its keys, then its
        /// values; an array, then its elements. Returns the reference to it.
        mutating func flatten(_ node: Node) -> Int {
            switch node {
            case .dictionary(let entries):
                let index = append(.dictionary(keys: [], values: []))
                let keys = entries.map { flatten($0.0) }
                let values = entries.map { flatten($0.1) }
                objects[index] = .dictionary(keys: keys, values: values)
                return index
            case .array(let elements):
                let index = append(.array([]))
                objects[index] = .array(elements.map { flatten($0) })
                return index
            case .string(let string, let kind):
                guard let kind else { return append(.string(string)) }
                return once("\(kind)\u{0}\(string)") { .string(string) }
            case .integer(let integer, let kind):
                return once("\(kind)\u{0}\(integer)") { .integer(integer) }
            case .double(let double, let isShared):
                guard isShared else { return append(.real(double)) }
                return once("double\u{0}\(double.bitPattern)") { .real(double) }
            case .float(let float):
                return once("float\u{0}\(float.bitPattern)") { .float(float) }
            case .boolean(let boolean):
                let index = append(.boolean(boolean))
                if let first = firstBooleans[boolean] { return first }
                firstBooleans[boolean] = index
                return index
            case .uid(let uid):
                let index = append(.uid(uid))
                if let first = firstUIDs[uid] { return first }
                firstUIDs[uid] = index
                return index
            case .data(let bytes):
                return append(.data(bytes))
            }
        }

        private mutating func once(_ identity: String, _ object: () -> BinaryPropertyList.Object) -> Int {
            if let index = shared[identity] { return index }
            let index = append(object())
            shared[identity] = index
            return index
        }

        private mutating func append(_ object: BinaryPropertyList.Object) -> Int {
            objects.append(object)
            return objects.count - 1
        }
    }
}
