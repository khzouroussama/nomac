import Foundation
import NomacCore

extension LoaderScan {
    /// Scheme attributes whose values are features, besides `YES`/`NO` ones.
    static let enumeratedSchemeAttributes: Set<String> = ["BuildableIdentifier", "launchStyle", "testExecutionOrdering", "runnableDebuggingMode", "version"]

    /// The shared schemes of a workspace, project or package, and its scheme management file.
    func scanSharedSchemes(in directory: String, containerDirectory: String) {
        guard FileSystem.isDirectory(directory), visitedSchemeFolders.insert(directory).inserted else { return }
        for name in (try? FileSystem.sortedContents(of: directory)) ?? [] {
            let file = directory + "/" + name
            if name.hasSuffix(".xcscheme") {
                scanScheme(file, containerDirectory: containerDirectory)
            } else if name == "xcschememanagement.plist" {
                use("scheme:management=shared", file, name)
                let plist = FileSystem.contents(atPath: file).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
                for key in (plist ?? [:]).keys.sorted() { use("scheme:management.\(key)", file, key) }
            }
        }
    }

    private func scanScheme(_ file: String, containerDirectory: String) {
        guard let data = FileSystem.contents(atPath: file), let root = XMLTree.parse(data) else {
            use("scheme:unreadable", file, (file as NSString).lastPathComponent)
            return
        }
        use("scheme:location=shared", file, root.name)
        if !Self.isASCII((file as NSString).lastPathComponent) { use("names:scheme=non-ascii", file, root.name) }
        func walk(_ element: XMLTree, parent: String?, path: String) {
            use("scheme:\(parent.map { $0 + "/" } ?? "")\(element.name)", file, path)
            for (attribute, value) in element.attributes.sorted(by: { $0.key < $1.key }) {
                let feature = "scheme:\(element.name)@\(attribute)"
                use(feature, file, path)
                if ["YES", "NO"].contains(value) || Self.enumeratedSchemeAttributes.contains(attribute) {
                    use("\(feature)=\(value)", file, path)
                } else if attribute == "ReferencedContainer" || attribute == "reference" {
                    use("\(feature)=\(Self.containerKind(value))", file, path)
                    if !Self.isASCII(value) { use("names:scheme-container=non-ascii", file, path) }
                }
            }
            if element.name == "BuildableReference" && element.attributes["BlueprintName"] == nil {
                use("scheme:BuildableReference@BlueprintName=missing", file, path)
            }
            if element.name == "TestPlanReference", let reference = element.attributes["reference"] {
                scanTestPlan(Self.resolveContainer(reference, relativeTo: containerDirectory), from: file, object: path)
            }
            for child in element.children { walk(child, parent: element.name, path: path + "/" + child.name) }
        }
        walk(root, parent: nil, path: root.name)
    }

    /// `container:App.xcodeproj` is `container:xcodeproj`; `container:Packages/Kit` is
    /// `container:folder`.
    static func containerKind(_ reference: String) -> String {
        let colon = reference.firstIndex(of: ":")
        let scheme = colon.map { String(reference[..<$0]) } ?? ""
        let path = colon.map { String(reference[reference.index(after: $0)...]) } ?? reference
        let pathExtension = (path as NSString).pathExtension
        return scheme + ":" + (["xcodeproj", "xctestplan", "xcworkspace"].contains(pathExtension) ? pathExtension : "folder")
    }

    /// `container:` paths of schemes and test plans, relative to the scheme's container directory
    /// (``XcodeWorkspace`` resolves them the same way).
    static func resolveContainer(_ reference: String, relativeTo directory: String) -> String {
        let path = reference.firstIndex(of: ":").map { String(reference[reference.index(after: $0)...]) } ?? reference
        if path.hasPrefix("/") { return (path as NSString).standardizingPath }
        return ((directory as NSString).appendingPathComponent(path) as NSString).standardizingPath
    }

    /// A test plan's keys, and the values that decide code coverage and which targets it tests.
    private func scanTestPlan(_ path: String, from file: String, object: String) {
        guard FileSystem.isFile(path) else {
            use("testplan:file=missing", file, object)
            return
        }
        guard visitedTestPlans.insert(path).inserted else { return }
        let name = (path as NSString).lastPathComponent
        guard let data = FileSystem.contents(atPath: path), let plan = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            use("testplan:unreadable", path, name)
            return
        }
        use("testplan:file", path, name)
        func walk(_ value: Any, keyPath: String, depth: Int) {
            switch value {
            case let dictionary as [String: Any]:
                guard depth < 4 else { return }
                for (key, child) in dictionary.sorted(by: { $0.key < $1.key }) {
                    let childPath = keyPath.isEmpty ? key : keyPath + "." + key
                    use("testplan:\(childPath)", path, childPath)
                    walk(child, keyPath: childPath, depth: depth + 1)
                }
            case let array as [Any]:
                for element in array { walk(element, keyPath: keyPath, depth: depth) }
            default:
                if let boolean = Self.boolean(value) { use("testplan:\(keyPath)=\(boolean)", path, keyPath) }
            }
        }
        walk(plan, keyPath: "", depth: 0)
        if let version = plan["version"] { use("testplan:version=\(version)", path, "version") }
        if let coverage = (plan["defaultOptions"] as? [String: Any])?["codeCoverage"], Self.boolean(coverage) == nil {
            use("testplan:defaultOptions.codeCoverage=targets", path, "defaultOptions.codeCoverage")
        }
        for configuration in plan["configurations"] as? [[String: Any]] ?? [] where (configuration["id"] as? String).flatMap(UUID.init(uuidString:)) == nil {
            use("testplan:configurations.id=not-uuid", path, "configurations")
        }
        for target in plan["testTargets"] as? [[String: Any]] ?? [] {
            if let container = (target["target"] as? [String: Any])?["containerPath"] as? String {
                use("testplan:testTargets.target.containerPath=\(Self.containerKind(container))", path, "testTargets")
            }
        }
    }

    /// A JSON `true` or `false` (Foundation reads both as numbers of type `c`).
    static func boolean(_ value: Any) -> Bool? {
        if let number = value as? NSNumber { return String(cString: number.objCType) == "c" ? number.boolValue : nil }
        return value as? Bool
    }
}
