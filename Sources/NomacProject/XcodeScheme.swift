import AEXML
import Foundation
import NomacCore
import PathKit
import XcodeProj

/// A scheme: which targets an action builds, and with which configuration.
///
/// Schemes are read from `xcshareddata/xcschemes` and from the user's
/// `xcuserdata/<user>.xcuserdatad/xcschemes` of the workspace, of each project and of each Swift
/// package (in `.swiftpm/xcode`, remote packages included). Then nomac adds the schemes Xcode
/// autocreates, unless the workspace turns autocreation off: for the targets no scheme covers,
/// for local packages' products and for the test targets no scheme tests
/// (docs/formats/show-build-settings.md "Schemes": loader-experiments, icecubes, netnewswire,
/// retro-rampage, tofu).
public struct XcodeScheme: Sendable, Equatable {
    /// A target the scheme's build action builds.
    public struct TestPlanFile: Sendable, Equatable {
        public var path: String
        public var isDefault: Bool
    }

    public struct BuildEntry: Sendable, Equatable {
        /// Absolute path of the `.xcodeproj` that contains the target, or of the Swift package's
        /// directory.
        public var containerPath: String
        /// The target's object identifier in that project, or the name of the package's product
        /// or target.
        public var targetID: String
        public var targetName: String
        /// The actions this entry is built for (`running`, `testing`, `profiling`, `archiving`, `analyzing`).
        public var buildFor: Set<String>

        public init(containerPath: String, targetID: String, targetName: String, buildFor: Set<String>) {
            self.containerPath = containerPath
            self.targetID = targetID
            self.targetName = targetName
            self.buildFor = buildFor
        }

        /// Whether the entry names a product or target of a Swift package.
        public var isInPackage: Bool { !containerPath.hasSuffix(".xcodeproj") }

        var key: String { "\(containerPath)#\(targetID)" }
    }

    /// The scheme file's name, or the target's or product's for an autocreated scheme.
    public var name: String
    /// The name `-list` shows: ``name``, followed by its container (`(P project)`,
    /// `(W Workspace)`, a package folder's name) when another shared or per-user scheme has the
    /// same name (loader-experiments `user-schemes-workspace`, `user-schemes-packages`).
    public var listedName: String
    /// The build action's entries, then the targets the Launch and Profile actions run that no
    /// entry names (loader-experiments `scheme-coverage`: a launched target is built for running,
    /// after the entries, or in its entry's place; a profiled one is not). An entry that builds a
    /// test plan stands, in its place, for the plan's test targets in plan order, each built for
    /// what the entry is; a missing plan for none (loader-experiments `test-plan-entries`;
    /// wikipedia's WikipediaUITests). A target can be named by several entries.
    public var buildEntries: [BuildEntry]
    /// The targets the Launch and Profile actions run: their buildable product runnables, and the
    /// target a remote launch runnable expands macros from when the scheme builds it.
    public var runs: [BuildEntry]
    /// The target the Launch action runs: the buildable product runnable or the remote runnable's
    /// macro expansion of ``runs``, or an autocreated extension scheme's first app.
    public var launched: BuildEntry?
    /// Whether the scheme has `wasCreatedForAppExtension = "YES"`: what it runs does not count as
    /// covered (loader-experiments `scheme-extension-key`).
    public var wasCreatedForAppExtension = false
    /// The test bundles the scheme's Test action runs.
    public var testables: [BuildEntry]
    /// The test bundles the Test action lists but skips, which still cover them
    /// (loader-experiments `own-test-schemes-more`: SkipTests and SkipDepTests get no scheme).
    public var skippedTestables: [BuildEntry] = []
    /// The test bundles of the test plans the scheme's Test action uses.
    public var testPlanTestables: [BuildEntry]
    /// The test plans the scheme's Test action uses.
    public var testPlans: [TestPlanFile] = []
    /// Whether Xcode makes a test plan of the scheme's testables (`shouldAutocreateTestPlan`).
    public var autocreatesTestPlan = false
    /// A scheme limited to chosen targets (`onlyGenerateCoverageForSpecifiedTargets`): their
    /// identifiers, the only ones that count in its coverage report.
    public var coverageReportTargets: Set<String>?
    /// Whether the Test action gathers code coverage: the scheme's `codeCoverageEnabled`, or,
    /// when it uses test plans, its default plan's (loader-experiments `coverage`).
    public var codeCoverageEnabled: Bool
    public var launchConfiguration: String
    /// The configuration the Archive action builds: the scheme's, or for a project target's
    /// autocreated scheme the project's default one (`build_experiments.py`: tofu's Release,
    /// `autocreate-names`' Beta of Alpha and Beta). A scheme file without an Archive action gets
    /// XcodeProj's default, Release, which no experiment has checked (Xcode always writes one).
    /// None where no archive was observed: a package's or a test bundle's autocreated scheme.
    public var archiveConfiguration: String?
    public var isAutocreated: Bool
    /// The `orderHint` the user's `xcschememanagement.plist` gives a shared or per-user scheme.
    public var orderHint: Int?
    /// The targets whose settings blocks xcodebuild prints in an order that changes from one run
    /// to the next: the apps an autocreated extension scheme builds when there are several
    /// (loader-experiments `autocreate-hosts`: ManyHosts and Mixed, six runs each; vlc's
    /// MediaLibraryWidgetExtension). nomac builds them in project order.
    public var unorderedTargetNames: Set<String> = []
    /// The autocreated schemes of other projects' targets with this scheme's name, which
    /// xcodebuild may build in its place: it picks one of the targets from one run to the next
    /// (loader-experiments `project-reference-names`, `workspace-names`: four runs each).
    /// nomac builds the first project's.
    public var alternatives: [XcodeScheme] = []
    /// The build action's shell scripts, run before and after it (`scheme_action_experiments.py`).
    public var buildPreActions: [ScriptAction] = []
    public var buildPostActions: [ScriptAction] = []
    /// Whether the build action's post-actions also run after a failed build (`runPostActionsOnFailure`).
    public var runsBuildPostActionsOnFailure = false
    /// The archive action's shell scripts, run after the build's post-actions: before the archive
    /// is written and after.
    public var archivePreActions: [ScriptAction] = []
    public var archivePostActions: [ScriptAction] = []
    /// The configuration the Test action builds and runs tests in (`build-for-testing`, `test`).
    public var testConfiguration = "Debug"
    /// The arguments and environment the Test action gives tests: its own, or the Launch
    /// action's when it uses them (`shouldUseLaunchSchemeArgsEnv`), the enabled ones only
    /// (`xctest_experiments.py` `xctestrun-test-env`, `xctestrun-launch-env`).
    public var testArguments: [String] = []
    public var testEnvironment: [String: String] = [:]
    /// The Test action's language, region and attachment lifetimes, by the name of a test plan's
    /// option; an empty language or region is none (`xctest_experiments.py` `xctestrun-scheme-lists`,
    /// `-scheme-parallel-no`).
    public var testOptions: [String: String] = [:]
    /// What the Test action sets on each of its testables, by the target's identifier.
    public var testableOptions: [String: TestableOptions] = [:]

    public struct TestableOptions: Sendable, Equatable {
        public var parallelizable: Bool?
        public var isRandomlyOrdered = false
        public var skippedTests: [String] = []
        public var selectedTests: [String] = []
    }

    /// A shell script execution action (`ShellScriptAction`). Its `shellToInvoke` is not kept:
    /// xcodebuild runs every action with `/bin/sh`.
    public struct ScriptAction: Sendable, Equatable {
        public var title: String
        public var script: String
        /// The target whose build settings the script gets (`EnvironmentBuildable`).
        public var environmentTarget: BuildEntry?

        public init(title: String, script: String, environmentTarget: BuildEntry?) {
            self.title = title
            self.script = script
            self.environmentTarget = environmentTarget
        }
    }

    static let allActions: Set<String> = ["running", "testing", "profiling", "archiving", "analyzing"]
}

/// A project target's build settings in one configuration, as `xcodebuild -showBuildSettings
/// -target <target> -configuration <configuration>` evaluates them. Xcode reads some of them to
/// decide which schemes it autocreates and what they build and test.
public struct TargetSettingsQuery: Hashable, Sendable {
    /// Absolute path of the target's `.xcodeproj`.
    public var projectPath: String
    public var targetID: String
    public var configuration: String

    public init(projectPath: String, targetID: String, configuration: String) {
        self.projectPath = projectPath
        self.targetID = targetID
        self.configuration = configuration
    }

    /// The key under which the evaluated settings of a target whose `SDKROOT` is `auto` hold its
    /// `EXECUTABLE_PATH` for iOS and for macOS, one per line, which `-showBuildSettings -target`
    /// does not export (loader-experiments `autocreate-auto-hosts`).
    public static let platformExecutablePaths = "NOMAC_PLATFORM_EXECUTABLE_PATHS"
}

extension XcodeWorkspace {
    /// The target settings ``schemes(packages:settings:userName:)`` reads; the caller evaluates them.
    public func schemeSettingsQueries() -> Set<TargetSettingsQuery> {
        guard autocreatesSchemes else { return [] }
        let hasTestBundles = allProjects.contains(where: AutocreationRules.hasTestBundles)
        return Set(allProjects.flatMap { AutocreationRules(project: $0, settings: [:]).queries(everyTarget: hasTestBundles) })
    }

    /// The workspace's schemes: the workspace's, each project's and each package's shared and
    /// per-user schemes, then the schemes Xcode autocreates. The projects the workspace's
    /// projects reference count as its projects (loader-experiments `project-references`:
    /// `SubShared` is listed and `Lib` gets a scheme; `user-schemes-references`). `packages` are
    /// the Swift packages of the resolved package graph; `settings` holds the evaluated answers to
    /// ``schemeSettingsQueries()``; `userName` names the account whose per-user schemes count.
    public func schemes(packages: [SwiftPackageContents] = [], settings: [TargetSettingsQuery: [String: String]] = [:], userName: String) throws -> [XcodeScheme] {
        // Per-user schemes are those of the account's own `xcuserdata/<user>.xcuserdatad`, whatever
        // USER says; a project's `project.xcworkspace` gives none (loader-experiments
        // `user-schemes`: another user's schemes, WsShared and WsUser are not listed).
        let userFolder = "/xcuserdata/\(userName).xcuserdatad/xcschemes"
        var containers: [(label: String, schemes: [XcodeScheme])] = []
        func readContainer(_ folder: String, label: String, containerDirectory: String) throws {
            let hints = Self.orderHints(in: folder + userFolder)
            func hinted(_ schemes: [XcodeScheme], suffix: String) -> [XcodeScheme] {
                schemes.map { scheme in
                    var scheme = scheme
                    scheme.orderHint = hints[scheme.name + ".xcscheme" + suffix]
                    return scheme
                }
            }
            containers.append((label, hinted(try Self.readSchemes(in: folder + "/xcshareddata/xcschemes", containerDirectory: containerDirectory), suffix: "_^#shared#^_")
                                + hinted(try Self.readSchemes(in: folder + userFolder, containerDirectory: containerDirectory), suffix: "")))
        }
        if !isImplicit {
            try readContainer(path, label: "\(name) Workspace", containerDirectory: (path as NSString).deletingLastPathComponent)
        }
        for project in allProjects {
            try readContainer(project.path, label: "\(project.name) project", containerDirectory: project.containingDirectory)
        }
        for package in packages {
            try readContainer(package.directory + "/.swiftpm/xcode", label: (package.directory as NSString).lastPathComponent, containerDirectory: package.directory)
        }
        // A name several of these schemes have, in one container or several, is followed by each
        // one's container; autocreated schemes neither count nor change (`user-schemes`: Dup
        // (P project) twice for a shared and a per-user Dup; `user-schemes-workspace`;
        // `user-schemes-packages`: Clash (Kit Folder)).
        let counts = Dictionary(containers.flatMap { $0.schemes.map { ($0.name, 1) } }, uniquingKeysWith: +)
        var result = containers.flatMap { container in
            container.schemes.map { scheme in
                var scheme = scheme
                if counts[scheme.name, default: 0] > 1 {
                    scheme.listedName = "\(scheme.name) (\(container.label))"
                }
                return scheme
            }
        }
        let declared = result
        // Without autocreation, targets and packages get no schemes (loader-experiments
        // `autocreate-contexts-off`: only shared and per-user schemes are listed; kickstarter).
        guard autocreatesSchemes else { return declared }
        // An autocreated scheme keeps its target's name even when a shared scheme has it
        // (loader-experiments `test-bundles`: Shared is listed twice). Targets of different
        // projects with one name get one scheme, which xcodebuild picks from one run to the next
        // (`project-reference-names`, `workspace-names`); nomac keeps the first project's, and
        // the others' are its alternatives (docs/VERIFICATION.md).
        // A test bundle's TEST_HOST can name an executable of any project (`own-test-schemes-more`:
        // B4Tests), so every project's autocreated targets are found before any bundle's scheme.
        let missingStoryboard = allProjects.contains(where: AutocreationRules.referencesMissingStoryboard)
        let rules = allProjects.map { project in
            AutocreationRules(project: project, settings: settings, suppressed: Self.suppressedTargets(in: project.path + userFolder),
                              missingStoryboard: missingStoryboard)
        }
        let autocreatedTargets = try rules.map { try $0.autocreatedTargets(coveringSchemes: declared) }
        let executables = zip(rules, autocreatedTargets).flatMap { $0.executables(autocreated: $1) }
        var autocreated: [String: Int] = [:]
        for (rule, targets) in zip(rules, autocreatedTargets) {
            for scheme in try rule.schemes(coveringSchemes: declared, autocreated: targets, executables: executables) {
                if let index = autocreated[scheme.name] {
                    result[index].alternatives.append(scheme)
                    continue
                }
                autocreated[scheme.name] = result.count
                result.append(scheme)
            }
        }
        let built = Set(result.flatMap { $0.buildEntries.map(\.key) })
        let run = Set(result.flatMap { $0.runs.map(\.key) })
        var names = Set(result.map(\.name))
        // Local packages, root or not, get a scheme for each product; remote ones do not
        // (loader-experiments `local-packages`; swiftfin). As for apps, only a scheme that
        // launches or profiles an executable product, or names it in a RemoteRunnable's
        // MacroExpansion, covers it (`package-target-kinds`: `tool`, which ByToolProduct builds
        // for running, keeps its scheme; `tool2`, launched, `tool3`, profiled, and `tool4`,
        // RemoteTool4's MacroExpansion, do not).
        // A shared or per-user scheme of the same name does not replace a product's scheme: both are
        // listed (loader-experiments `scheme-package-clashes`: Stale, Other; wordpress's
        // `WordPressKit`).
        var autocreatedNames = Set(result.filter(\.isAutocreated).map(\.name))
        var productSchemes: [String: Set<String>] = [:]
        for package in packages where package.isLocal {
            for (product, scheme) in zip(package.products, Self.productSchemes(of: package)) {
                guard let entry = scheme.buildEntries.first, !(product.isExecutable ? run : built).contains(entry.key) else { continue }
                // A project target's autocreated scheme of the same name is listed in its place, and
                // xcodebuild builds the one or the other from one run to the next
                // (loader-experiments `scheme-name-clashes`: `-scheme Kit`, the target in three runs
                // of four): the product's scheme is that scheme's alternative.
                if autocreatedNames.contains(scheme.name) {
                    if let index = result.firstIndex(where: { $0.isAutocreated && $0.name == scheme.name && $0.buildEntries.first?.isInPackage == false }) {
                        result[index].alternatives.append(scheme)
                    }
                    continue
                }
                result.append(scheme)
                names.insert(scheme.name)
                autocreatedNames.insert(scheme.name)
                productSchemes[package.directory, default: []].insert(product.name)
            }
        }
        // A root package's test target that no scheme tests gets a scheme of its own, unless it is
        // named `<Product>Tests` after one of its package's products whose autocreated scheme is
        // listed, whatever it depends on (loader-experiments `root-package-references`: AlphaTests,
        // which tests Beta, has none, BetaChecks and GammaTests have one; `schemes`: KitTests,
        // whose Kit a shared scheme builds, and LooseTests have one, KitExtrasTests none; icecubes:
        // EnvTests, whose package shares an Env scheme testing another package's tests; element-x's
        // MacrosTests has none).
        let tested = Set(result.flatMap { ($0.testables + $0.testPlanTestables).map(\.key) })
        for package in packages where package.isRoot {
            let named = Set((productSchemes[package.directory] ?? []).map { $0 + "Tests" })
            for test in package.testTargets where !named.contains(test.name) {
                let entry = XcodeScheme.BuildEntry(containerPath: package.directory, targetID: test.name, targetName: test.name, buildFor: ["testing"])
                guard !tested.contains(entry.key), !names.contains(test.name) else { continue }
                result.append(Self.autocreatedScheme(name: test.name, buildEntries: [], testables: [entry], codeCoverageEnabled: false, launchConfiguration: "Debug"))
                names.insert(test.name)
            }
        }
        return result
    }

    /// The first shared or per-user scheme of `schemes` listed as `name`, else the first whose own
    /// name it is, else the autocreated scheme of that name; xcodebuild's error, with its exit
    /// status, when there is none. Of a shared and a per-user scheme of one container, the one
    /// with an order hint comes before one without and the lower hint first, as a project
    /// opened alone or through a workspace, by either name (loader-experiments `scheme-pairs`
    /// `-hints`, `-hints-reverse`, `-hints-shared-only`, `-hints-user-only`, `-workspace-hints`:
    /// four names each, two runs; without hints the choice depends on the other schemes, BACKLOG
    /// B-065). A shared or per-user scheme's name matches in any
    /// normalization form, an autocreated one's only byte for byte (loader-experiments
    /// `unicode-nfc`, `unicode-nfd`: `Schémé` and `Àutre` are found in both forms, `Ötro` only in
    /// its own). A name only renamed schemes have picks one of them, even next to an autocreated
    /// scheme of that name, and xcodebuild's choice among schemes of several containers changes
    /// from one run to the next (`user-schemes-workspace`: Same, Pair, Mixed, four runs each;
    /// `scheme-name-clashes`: Dup, Q's or R's in four runs, never the autocreated one; BACKLOG B-065).
    public static func scheme(named name: String, in schemes: [XcodeScheme], workspace: XcodeWorkspace) throws -> XcodeScheme {
        if !schemes.contains(where: { !$0.isAutocreated && $0.listedName == name }) {
            // A name only renamed schemes have: xcodebuild takes the scheme of one of their
            // containers, which one changing from one run to the next (loader-experiments
            // `user-schemes-workspace`, `scheme-name-clashes`: Dup); nomac takes the first, the
            // other containers' are its alternatives. Within one container the choice is stable
            // and not known (BACKLOG B-065).
            let renamed = schemes.filter { !$0.isAutocreated && $0.name == name }
            if let listed = renamed.first?.listedName, var first = preferred(renamed.filter { $0.listedName == listed }) {
                first.alternatives += renamed.filter { $0.listedName != listed }
                return first
            }
        }
        let listed = schemes.filter { !$0.isAutocreated && $0.listedName == name }
        let renamed = listed.first.flatMap { $0.name == $0.listedName ? nil : preferred(listed.filter { $0.name != $0.listedName }) }
        guard let scheme = renamed ?? listed.first ?? schemes.first(where: { $0.isAutocreated && $0.listedName.isIdentical(to: name) }) else {
            let kind = workspace.isImplicit ? "project" : "workspace"
            throw NomacError("The \(kind) named \"\(workspace.name)\" does not contain a scheme named \"\(name)\". The \"-list\" option can be used to find the names of the schemes in the \(kind).",
                             exitStatus: 65)
        }
        return scheme
    }

    /// The scheme autocreated for each library and executable product of a local package: it
    /// builds the product and tests nothing (loader-experiments `schemes`: `KitExtras`,
    /// `root-package-references`: `Alpha`, `Beta`, each "not currently configured for the test
    /// action").
    static func productSchemes(of package: SwiftPackageContents) -> [XcodeScheme] {
        package.products.map { product in
            autocreatedScheme(
                name: product.name,
                buildEntries: [XcodeScheme.BuildEntry(containerPath: package.directory, targetID: product.name, targetName: product.name,
                                                      buildFor: XcodeScheme.allActions)],
                testables: [],
                codeCoverageEnabled: false,
                launchConfiguration: "Debug")
        }
    }

    static func autocreatedScheme(name: String, buildEntries: [XcodeScheme.BuildEntry], testables: [XcodeScheme.BuildEntry], codeCoverageEnabled: Bool,
                                  launchConfiguration: String, archiveConfiguration: String? = nil, launched: XcodeScheme.BuildEntry? = nil) -> XcodeScheme {
        XcodeScheme(
            name: name,
            listedName: name,
            buildEntries: buildEntries,
            runs: [],
            launched: launched,
            testables: testables,
            testPlanTestables: [],
            codeCoverageEnabled: codeCoverageEnabled,
            launchConfiguration: launchConfiguration,
            archiveConfiguration: archiveConfiguration,
            isAutocreated: true)
    }

    /// The scheme xcodebuild takes of `schemes`, shared and per-user schemes of one container
    /// listed under one name: the one with the lowest order hint, else the first.
    private static func preferred(_ schemes: [XcodeScheme]) -> XcodeScheme? {
        schemes.enumerated().min { ($0.element.orderHint ?? .max, $0.offset) < ($1.element.orderHint ?? .max, $1.offset) }?.element
    }

    /// The `orderHint` of each scheme the user's `xcschememanagement.plist` in `folder` names, by
    /// its key: a per-user scheme's file name, a shared one's followed by `_^#shared#^_`.
    static func orderHints(in folder: String) -> [String: Int] {
        guard let data = FileManager.default.contents(atPath: folder + "/xcschememanagement.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let states = plist["SchemeUserState"] as? [String: Any] else { return [:] }
        return states.compactMapValues { ($0 as? [String: Any])?["orderHint"] as? Int }
    }

    /// The targets whose autocreated scheme the user's `xcschememanagement.plist` in `folder`
    /// suppresses: those of `SuppressBuildableAutocreation` whose `primary` is true
    /// (loader-experiments `user-schemes`: FwSuppressed and AppSuppressed get no scheme,
    /// FwSuppressedNo does; another user's file is not read).
    static func suppressedTargets(in folder: String) -> Set<String> {
        guard let data = FileManager.default.contents(atPath: folder + "/xcschememanagement.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let suppressed = plist["SuppressBuildableAutocreation"] as? [String: Any] else { return [] }
        return Set(suppressed.compactMap { target, value in ((value as? [String: Any])?["primary"] as? Bool) == true ? target : nil })
    }

    private static func readSchemes(in directory: String, containerDirectory: String) throws -> [XcodeScheme] {
        guard FileSystem.isDirectory(directory) else { return [] }
        var schemes: [XcodeScheme] = []
        for file in try FileSystem.sortedContents(of: directory) where file.hasSuffix(".xcscheme") {
            let schemePath = directory + "/" + file
            let parsed: XCScheme
            let items: [BuildActionItem]
            let autocreatesTestPlan: Bool
            do {
                (parsed, items, autocreatesTestPlan) = try parseScheme(at: FileSystem.onDisk(schemePath))
            } catch {
                throw NomacError("could not parse the scheme: \(error)", path: schemePath)
            }
            func entry(_ reference: XCScheme.BuildableReference?, buildFor: Set<String>) -> XcodeScheme.BuildEntry? {
                guard let reference, let targetID = reference.blueprintIdentifier else { return nil }
                return XcodeScheme.BuildEntry(
                    containerPath: resolveContainer(reference.referencedContainer, relativeTo: containerDirectory),
                    targetID: targetID,
                    targetName: reference.blueprintName,
                    buildFor: buildFor)
            }
            var entries: [XcodeScheme.BuildEntry] = items.flatMap { item -> [XcodeScheme.BuildEntry] in
                switch item {
                case .buildable(let built):
                    return entry(built.buildableReference, buildFor: Set(built.buildFor.map { "\($0)" })).map { [$0] } ?? []
                case .testPlan(let reference, let buildFor):
                    return testPlanTargets(at: resolveContainer(reference, relativeTo: containerDirectory), containerDirectory: containerDirectory).map {
                        var planned = $0
                        planned.buildFor = buildFor
                        return planned
                    }
                }
            }
            let launched = (parsed.launchAction?.runnable as? XCScheme.BuildableProductRunnable).flatMap { entry($0.buildableReference, buildFor: ["running"]) }
            let profiled = (parsed.profileAction?.runnable as? XCScheme.BuildableProductRunnable).flatMap { entry($0.buildableReference, buildFor: ["profiling"]) }
            let runnables = [launched, profiled].compactMap { $0 }
            var runs = runnables
            var remote: XcodeScheme.BuildEntry?
            if parsed.launchAction?.runnable is XCScheme.RemoteRunnable,
               let expanded = entry(parsed.launchAction?.macroExpansion, buildFor: []), entries.contains(where: { $0.key == expanded.key }) {
                runs.append(expanded)
                remote = expanded
            }
            for run in runnables {
                if let index = entries.firstIndex(where: { $0.key == run.key }) {
                    entries[index].buildFor.formUnion(run.buildFor)
                } else {
                    entries.append(run)
                }
            }
            let listed = parsed.testAction?.testables ?? []
            let testables = listed.filter { !$0.skipped }.compactMap { entry($0.buildableReference, buildFor: ["testing"]) }
            let skippedTestables = listed.filter(\.skipped).compactMap { entry($0.buildableReference, buildFor: ["testing"]) }
            let plans = parsed.testAction?.testPlans ?? []
            let testPlanTestables = plans.flatMap { plan in
                testPlanTargets(at: resolveContainer(plan.reference, relativeTo: containerDirectory), containerDirectory: containerDirectory)
            }
            var codeCoverageEnabled = parsed.testAction?.codeCoverageEnabled ?? false
            // A test plan Xcode autocreates for the scheme's testables, skipped ones included,
            // gathers coverage (loader-experiments `coverage-autocreated-plan`; pocket-casts'
            // `Pocket Casts Prototype Build`).
            if autocreatesTestPlan, !(parsed.testAction?.testables ?? []).isEmpty { codeCoverageEnabled = true }
            if let plan = plans.first(where: \.default) ?? plans.first {
                codeCoverageEnabled = testPlanGathersCoverage(at: resolveContainer(plan.reference, relativeTo: containerDirectory))
            }
            let name = (file as NSString).deletingPathExtension
            let script = { (action: XCScheme.ExecutionAction) in
                XcodeScheme.ScriptAction(title: action.title, script: action.scriptText,
                                         environmentTarget: entry(action.environmentBuildable, buildFor: []))
            }
            var scheme = XcodeScheme(
                name: name,
                listedName: name,
                buildEntries: entries,
                runs: runs,
                launched: launched ?? remote,
                testables: testables,
                skippedTestables: skippedTestables,
                testPlanTestables: testPlanTestables,
                codeCoverageEnabled: codeCoverageEnabled,
                launchConfiguration: parsed.launchAction?.buildConfiguration ?? "Debug",
                archiveConfiguration: parsed.archiveAction?.buildConfiguration,
                isAutocreated: false)
            scheme.wasCreatedForAppExtension = parsed.wasCreatedForAppExtension == true
            scheme.buildPreActions = parsed.buildAction?.preActions.map(script) ?? []
            scheme.buildPostActions = parsed.buildAction?.postActions.map(script) ?? []
            scheme.runsBuildPostActionsOnFailure = parsed.buildAction?.runPostActionsOnFailure ?? false
            scheme.archivePreActions = parsed.archiveAction?.preActions.map(script) ?? []
            scheme.archivePostActions = parsed.archiveAction?.postActions.map(script) ?? []
            scheme.testConfiguration = parsed.testAction?.buildConfiguration ?? "Debug"
            let usesLaunch = parsed.testAction?.shouldUseLaunchSchemeArgsEnv ?? true
            let arguments = usesLaunch ? parsed.launchAction?.commandlineArguments : parsed.testAction?.commandlineArguments
            let variables = usesLaunch ? parsed.launchAction?.environmentVariables : parsed.testAction?.environmentVariables
            scheme.testPlans = plans.map { XcodeScheme.TestPlanFile(path: resolveContainer($0.reference, relativeTo: containerDirectory), isDefault: $0.default) }
            scheme.autocreatesTestPlan = autocreatesTestPlan
            if parsed.testAction?.onlyGenerateCoverageForSpecifiedTargets == true {
                scheme.coverageReportTargets = Set((parsed.testAction?.codeCoverageTargets ?? []).map(\.blueprintIdentifier).compactMap { $0 })
            }
            scheme.testArguments = arguments?.arguments.filter(\.enabled).map(\.name) ?? []
            scheme.testEnvironment = Dictionary((variables ?? []).filter(\.enabled).map { ($0.variable, $0.value) }) { $1 }
            let testAction = parsed.testAction
            let options = ["language": testAction?.language, "region": testAction?.region, "uiTestingScreenshotsLifetime": testAction?.systemAttachmentLifetime?.rawValue,
                           "userAttachmentLifetime": testAction?.userAttachmentLifetime?.rawValue]
            scheme.testOptions = options.compactMapValues { $0 }.filter { !$0.value.isEmpty }
            for testable in listed where !testable.skipped {
                guard let identifier = testable.buildableReference.blueprintIdentifier else { continue }
                scheme.testableOptions[identifier] = XcodeScheme.TestableOptions(
                    parallelizable: testable.parallelization == .swiftTestingOnly ? nil : testable.parallelization == .all,
                    isRandomlyOrdered: testable.randomExecutionOrdering,
                    skippedTests: testable.skippedTests.map(\.identifier),
                    selectedTests: testable.selectedTests.map(\.identifier))
            }
            schemes.append(scheme)
        }
        return schemes
    }

    /// A build action entry: a buildable, or a test plan the entry builds.
    private enum BuildActionItem {
        case buildable(XCScheme.BuildAction.Entry)
        case testPlan(reference: String, buildFor: Set<String>)
    }

    /// The scheme at `path`, its build action entries in order, and whether its test action sets
    /// `shouldAutocreateTestPlan`, which XcodeProj does not read. XcodeProj cannot read an
    /// entry that holds a `TestPlanReference` instead of a `BuildableReference`, so such entries
    /// are read here and left out of the copy of the file XcodeProj parses. An entry that holds an
    /// `AutocreatedTestPlanReference` builds nothing, whatever it is built for, and is left out
    /// too (envelope-experiments `autocreated-test-plan`, `autocreated-test-plan-running`). Nor
    /// can it read a `BuildableReference` without `BlueprintName`, which Xcode reads, finding the
    /// target by its `BlueprintIdentifier` alone (loader-experiments `blueprint-names`;
    /// home-assistant's `WatchApp` schemes): the copy gives such references an empty name.
    private static func parseScheme(at path: String) throws -> (XCScheme, [BuildActionItem], Bool) {
        let document = try AEXMLDocument(xml: try Data(contentsOf: URL(fileURLWithPath: path)))
        let autocreatesTestPlan = document.root["TestAction"].attributes["shouldAutocreateTestPlan"] == "YES"
        let elements = document.root["BuildAction"]["BuildActionEntries"]["BuildActionEntry"].all ?? []
        var plans: [Int: BuildActionItem] = [:]
        var autocreated: Set<Int> = []
        for (index, element) in elements.enumerated() {
            if element["AutocreatedTestPlanReference"].error == nil {
                autocreated.insert(index)
                element.removeFromParent()
                continue
            }
            let plan = element["TestPlanReference"]
            guard plan.error == nil, let reference = plan.attributes["reference"] else { continue }
            let flags = ["testing": "buildForTesting", "running": "buildForRunning", "profiling": "buildForProfiling",
                         "archiving": "buildForArchiving", "analyzing": "buildForAnalyzing"]
            plans[index] = .testPlan(reference: reference, buildFor: Set(flags.filter { element.attributes[$0.value].map { $0 == "YES" } ?? true }.keys))
            element.removeFromParent()
        }
        let unnamed = buildableReferences(in: document.root).filter { $0.attributes["BlueprintName"] == nil }
        for reference in unnamed {
            reference.attributes["BlueprintName"] = ""
        }
        guard !plans.isEmpty || !autocreated.isEmpty || !unnamed.isEmpty else {
            let scheme = try XCScheme(path: Path(path))
            return (scheme, (scheme.buildAction?.buildActionEntries ?? []).map(BuildActionItem.buildable), autocreatesTestPlan)
        }
        let copyDirectory = FileManager.default.temporaryDirectory.path + "/nomac-scheme-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: copyDirectory) }
        let copy = copyDirectory + "/" + (path as NSString).lastPathComponent
        try FileSystem.write(Data(document.xml.utf8), to: copy)
        let scheme = try XCScheme(path: Path(copy))
        var buildables = (scheme.buildAction?.buildActionEntries ?? []).makeIterator()
        let items = elements.indices.filter { !autocreated.contains($0) }.compactMap { plans[$0] ?? buildables.next().map(BuildActionItem.buildable) }
        return (scheme, items, autocreatesTestPlan)
    }

    private static func buildableReferences(in element: AEXMLElement) -> [AEXMLElement] {
        element.children.flatMap { ($0.name == "BuildableReference" ? [$0] : []) + buildableReferences(in: $0) }
    }

    /// The test targets of an `.xctestplan`; its `container:` paths are relative to the
    /// directory of the scheme that uses it (netnewswire: `container:Modules/RSWeb`). A missing
    /// or unreadable plan has none.
    static func testPlanTargets(at path: String, containerDirectory: String) -> [XcodeScheme.BuildEntry] {
        guard let data = FileSystem.contents(atPath: path),
              let plan = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targets = plan["testTargets"] as? [[String: Any]] else { return [] }
        return targets.compactMap { entry in
            guard let target = entry["target"] as? [String: Any],
                  let container = target["containerPath"] as? String,
                  let identifier = target["identifier"] as? String else { return nil }
            return XcodeScheme.BuildEntry(
                containerPath: resolveContainer(container, relativeTo: containerDirectory),
                targetID: identifier,
                targetName: target["name"] as? String ?? identifier,
                buildFor: ["testing"])
        }
    }

    /// Whether the test plan at `path` gathers code coverage: unless its default options set
    /// `codeCoverage` to `false`, a list of targets or `true` included, and only if Xcode can
    /// read it, which it cannot when the file is missing or a configuration's `id` is not a UUID
    /// (loader-experiments `coverage`; cwa's `ENAScreenshots` and `ENA` schemes).
    static func testPlanGathersCoverage(at path: String) -> Bool {
        guard let data = FileSystem.contents(atPath: path),
              let plan = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let configurations = plan["configurations"] as? [[String: Any]] ?? []
        guard configurations.allSatisfy({ ($0["id"] as? String).flatMap(UUID.init(uuidString:)) != nil }) else { return false }
        return ((plan["defaultOptions"] as? [String: Any])?["codeCoverage"] as? Bool) != false
    }

    /// `container:Rampage.xcodeproj` and friends, relative to the scheme's container directory,
    /// decomposed as Xcode spells the paths of projects: a reference in either form names the
    /// project (loader-experiments `unicode-nfc`, `unicode-nfd`: `container:Café.xcodeproj`).
    static func resolveContainer(_ reference: String, relativeTo directory: String) -> String {
        let path: String
        if let colon = reference.firstIndex(of: ":") {
            path = String(reference[reference.index(after: colon)...])
        } else {
            path = reference
        }
        if path.hasPrefix("/") { return (path as NSString).standardizingPath.decomposed }
        return ((directory as NSString).appendingPathComponent(path) as NSString).standardizingPath.decomposed
    }
}

/// Which schemes Xcode autocreates for one project's targets, and what they build and test
/// (docs/formats/show-build-settings.md "Schemes"; loader-experiments `autocreate`,
/// `extension-points`, `product-types`, `autocreate-hosts`, `scheme-coverage`, `test-bundles`,
/// `test-hosts`, `autocreate-order`, `autocreate-names`, `autocreate-three`; netnewswire, tofu).
struct AutocreationRules {
    let project: XcodeProject
    let settings: [TargetSettingsQuery: [String: String]]
    /// The targets the user's `xcschememanagement.plist` keeps from being autocreated.
    var suppressed: Set<String> = []
    /// Whether a project of the workspace references a storyboard missing from disk.
    var missingStoryboard = false

    /// An executable a test bundle's `TEST_HOST` can name: a target's `EXECUTABLE_PATH` and
    /// `$(BUILT_PRODUCTS_DIR)/$(EXECUTABLE_PATH)` in its project's default configuration.
    struct Executable {
        var executablePath: String
        var path: String
        var isAutocreated: Bool
    }

    private static func type(_ name: String) -> String { "com.apple.product-type." + name }
    private static let unitTest = type("bundle.unit-test")
    private static let testBundles: Set<String> = [unitTest, type("bundle.ui-testing")]
    /// Targets a shared scheme covers only by launching or profiling them (`product-types`:
    /// Built-NN keeps its autocreated scheme).
    private static let runnables: Set<String> = [type("application"), type("tool"), type("application.on-demand-install-capable"), type("application.watchapp2")]
    /// Targets that never get an autocreated scheme (`product-types`).
    private static let unlisted: Set<String> = [type("application.watchapp2-container"), type("watchkit2-extension"), type("application.messages")]
    /// Targets whose autocreated scheme also builds the apps that depend on them (`autocreate-hosts`).
    private static let extensions: Set<String> = [
        type("app-extension"), type("extensionkit-extension"), type("app-extension.messages-sticker-pack"),
        type("app-extension.messages"), type("tv-app-extension"), type("xcode-extension"),
    ]
    /// The apps such a scheme builds (`autocreate-hosts`: a command-line tool is none).
    private static let hostApps: Set<String> = [type("application"), type("application.on-demand-install-capable"), type("application.watchapp2"), type("application.messages")]
    /// Extensions whose Info.plist names one of `safariExtensionPoints` get no scheme
    /// (`extension-points`; netnewswire's "Subscribe to Feed").
    private static let safariChecked: Set<String> = [type("app-extension"), type("extensionkit-extension")]
    private static let safariExtensionPoints: Set<String> = ["com.apple.Safari.extension", "com.apple.Safari.web-extension"]
    /// The targets a UI test bundle's `TestTargetID` can name for their scheme to test it, iOS and
    /// macOS apps and App Clips (`autocreate-ui-targets`: not frameworks, app extensions, sticker
    /// packs, static libraries, bundles, command-line tools or watchOS apps).
    private static let uiTested: Set<String> = [type("application"), type("application.on-demand-install-capable")]

    /// The configuration Xcode reads Info.plists and test hosts in: Debug, else the first one
    /// (`autocreate-order`, `autocreate-names`, `autocreate-three`; `autocreate-debug-suffix`:
    /// Release, not Debugging).
    private var readConfiguration: String {
        let names = project.project.buildConfigurationList?.buildConfigurations.map(\.name) ?? []
        return names.contains("Debug") ? "Debug" : names.first ?? "Debug"
    }

    /// The project's default configuration (`defaultConfigurationName`).
    private var defaultConfiguration: String {
        let list = project.project.buildConfigurationList
        return list?.defaultConfigurationName ?? list?.buildConfigurations.last?.name ?? "Release"
    }

    /// The configuration autocreated schemes launch with: Debug, else the first whose name starts
    /// with `Debug`, case-sensitively, else the default one (`autocreate-names`: Beta of Alpha and
    /// Beta; `autocreate-debug-dev`: Debug-Dev; `autocreate-debug-suffix`: Debugging, not MyDebug;
    /// `autocreate-debug-upper`: Debugger, not DEBUG; `autocreate-debug-lower`: Release, not debug;
    /// `autocreate-debug-both`: Debug before Debug-Dev).
    private var launchConfiguration: String {
        let names = project.project.buildConfigurationList?.buildConfigurations.map(\.name) ?? []
        return names.contains("Debug") ? "Debug" : names.first { $0.hasPrefix("Debug") } ?? defaultConfiguration
    }

    private func productType(_ target: PBXTarget) -> String { target.productType?.rawValue ?? "" }

    /// The targets of the same project `target` depends on directly.
    private func dependencies(of target: PBXTarget) -> [PBXTarget] { target.dependencies.compactMap(\.target) }

    private func query(_ target: PBXTarget, _ configuration: String) -> TargetSettingsQuery {
        TargetSettingsQuery(projectPath: project.path, targetID: target.uuid, configuration: configuration)
    }

    /// Whether `project` has a file reference whose path ends in `.storyboard` and names no file
    /// (loader-experiments `watch-schemes-missing`, `-extension-only`; an empty or unreadable
    /// storyboard, `-empty` and `-garbage`, or the storyboard type on another name, `-type-only`,
    /// is not; fuzzer seed 70155).
    static func referencesMissingStoryboard(_ project: XcodeProject) -> Bool {
        project.pbxproj.fileReferences.contains { reference in
            guard let path = reference.path, path.hasSuffix(".storyboard"),
                  let fullPath = diskPath(of: reference, path: path, sourceRoot: project.projectDirectory) else { return false }
            return !FileSystem.exists(fullPath)
        }
    }

    /// Where `reference` is on disk. A variant group's children are relative to the variant
    /// group's own group, which XcodeProj's `fullPath` puts the variant group's name under
    /// (fuzzer seed 70101: `Desktop/Base.lproj/Main.storyboard`).
    private static func diskPath(of reference: PBXFileReference, path: String, sourceRoot: String) -> String? {
        guard reference.sourceTree == .group, let variantGroup = reference.parent as? PBXVariantGroup else {
            return try? reference.fullPath(sourceRoot: sourceRoot)
        }
        guard let group = variantGroup.parent, let directory = try? group.fullPath(sourceRoot: sourceRoot) else { return nil }
        return directory + "/" + path
    }

    static func hasTestBundles(_ project: XcodeProject) -> Bool {
        project.project.targets.contains { testBundles.contains($0.productType?.rawValue ?? "") }
    }

    /// The settings these rules read; `everyTarget` when the workspace has test bundles, whose
    /// `TEST_HOST` can name any target's executable.
    func queries(everyTarget: Bool) -> [TargetSettingsQuery] {
        project.project.targets.flatMap { target -> [TargetSettingsQuery] in
            let type = productType(target)
            var result: [TargetSettingsQuery] = []
            if target.product != nil && (Self.safariChecked.contains(type) || type == Self.type("watchkit2-extension")) {
                result.append(query(target, readConfiguration))
            }
            // A test bundle's TEST_HOST, and the executables it may name, in the default
            // configuration; a unit test bundle's test host in the read configuration.
            if everyTarget {
                result.append(query(target, defaultConfiguration))
            }
            let tested = dependencies(of: target)
            if type == Self.unitTest && !tested.isEmpty {
                result += [query(target, readConfiguration)] + tested.map { query($0, readConfiguration) }
            }
            return result
        }
    }

    private func evaluated(_ target: PBXTarget, _ configuration: String) throws -> [String: String] {
        guard let values = settings[query(target, configuration)] else {
            throw NomacError("the build settings of target '\(target.name)' in configuration \(configuration) were not evaluated", path: project.path)
        }
        return values
    }

    private func isCovered(_ target: PBXTarget, by schemes: [XcodeScheme]) -> Bool {
        guard !suppressed.contains(target.uuid) else { return true }
        if target.product != nil && Self.runnables.contains(productType(target)) {
            let key = entry(target, buildFor: []).key
            return schemes.contains { !$0.wasCreatedForAppExtension && $0.runs.contains { $0.key == key } }
        }
        return isBuiltOrTested(target, by: schemes)
    }

    private func isBuiltOrTested(_ target: PBXTarget, by schemes: [XcodeScheme]) -> Bool {
        let key = entry(target, buildFor: []).key
        return schemes.contains { ($0.buildEntries + $0.runs + $0.testables + $0.skippedTestables + $0.testPlanTestables).contains { $0.key == key } }
    }

    /// The targets, other than test bundles, that get an autocreated scheme: those none of
    /// `coveringSchemes`, the shared and per-user schemes, covers, and that the user does not
    /// suppress (loader-experiments `user-schemes`: per-user schemes cover targets as shared
    /// ones do).
    func autocreatedTargets(coveringSchemes: [XcodeScheme]) throws -> Set<String> {
        var result: Set<String> = []
        for target in project.project.targets where !Self.testBundles.contains(productType(target)) && !isCovered(target, by: coveringSchemes) {
            if target.product != nil {
                guard !Self.unlisted.contains(productType(target)) else { continue }
                guard try !isSafariExtension(target) else { continue }
            }
            result.insert(target.uuid)
        }
        return result
    }

    /// The executables of the project's targets, those of `autocreated` marked; none when the
    /// workspace has no test bundles, as their settings are then not read.
    func executables(autocreated: Set<String>) -> [Executable] {
        project.project.targets.flatMap { target -> [Executable] in
            guard let values = settings[query(target, defaultConfiguration)], let directory = values["BUILT_PRODUCTS_DIR"] else { return [] }
            return Self.executablePaths(values).map { executable in
                Executable(executablePath: Self.standardized(executable), path: Self.standardized(directory + "/" + executable),
                           isAutocreated: autocreated.contains(target.uuid))
            }
        }
    }

    /// A target's `EXECUTABLE_PATH`, or for one whose `SDKROOT` is `auto` its iOS and macOS ones.
    private static func executablePaths(_ values: [String: String]) -> [String] {
        let paths = values["EXECUTABLE_PATH"].map { [$0] } ?? values[TargetSettingsQuery.platformExecutablePaths]?.components(separatedBy: "\n") ?? []
        return paths.filter { !$0.isEmpty }
    }

    /// The project's autocreated schemes: one for each target of `autocreated`, and one for each
    /// test bundle that gets its own; `executables` are those of every project of the workspace.
    /// A target's scheme tests no bundle a shared or per-user scheme builds or tests, skipped or
    /// in a test plan (loader-experiments `autocreate-testables`: App01 to App06, App24).
    func schemes(coveringSchemes: [XcodeScheme], autocreated: Set<String>, executables: [Executable]) throws -> [XcodeScheme] {
        let targets = project.project.targets
        var testablesByTarget: [String: [XcodeScheme.BuildEntry]] = [:]
        var hostedBundles: Set<String> = []
        for bundle in targets where Self.testBundles.contains(productType(bundle)) {
            for tested in try testedTargets(of: bundle) {
                hostedBundles.insert(bundle.uuid)
                guard !isBuiltOrTested(bundle, by: coveringSchemes) else { continue }
                testablesByTarget[tested.uuid, default: []].append(entry(bundle, buildFor: ["testing"]))
            }
        }
        var result: [XcodeScheme] = []
        for target in targets {
            let type = productType(target)
            if Self.testBundles.contains(type) {
                guard !isCovered(target, by: coveringSchemes), !hostedBundles.contains(target.uuid),
                      try ownsScheme(testBundle: target, autocreated: autocreated, executables: executables) else { continue }
                result.append(XcodeWorkspace.autocreatedScheme(name: target.name, buildEntries: [], testables: [entry(target, buildFor: ["testing"])],
                                                               codeCoverageEnabled: true, launchConfiguration: launchConfiguration))
                continue
            }
            guard autocreated.contains(target.uuid) else { continue }
            var entries = [entry(target, buildFor: XcodeScheme.allActions)]
            if Self.extensions.contains(type) {
                for host in hosts(of: target) where !entries.contains(where: { $0.targetID == host.uuid }) {
                    entries.append(entry(host, buildFor: XcodeScheme.allActions))
                }
            }
            // An extension's scheme also tests the bundles of the apps it builds (`autocreate-testables`:
            // Ext07 to Ext15, both apps of Ext14; Ext23, the bundle of the framework between).
            let testables = entries.flatMap { testablesByTarget[$0.targetID] ?? [] }
            // An extension's scheme launches its first app, whose platform decides the
            // destinations (loader-experiments `scheme-destinations`: ExtIOS18, an iOS extension a
            // macOS app depends on, fails with an iOS destination, and ExtMac19 accepts one;
            // `autocreate-hosts`: WatchWidget, which builds a watchOS app first, fails).
            var scheme = XcodeWorkspace.autocreatedScheme(name: target.name, buildEntries: entries, testables: testables,
                                                          codeCoverageEnabled: !testables.isEmpty, launchConfiguration: launchConfiguration,
                                                          archiveConfiguration: defaultConfiguration, launched: entries.dropFirst().first)
            let hostApps = entries.dropFirst().filter { entry in targets.contains { $0.uuid == entry.targetID && Self.hostApps.contains(productType($0)) } }
            if hostApps.count > 1 {
                scheme.unorderedTargetNames = Set(entries.dropFirst().map(\.targetName))
            }
            result.append(scheme)
            for interface in try watchInterfaces(of: target) {
                var variant = scheme
                variant.name = "\(target.name) (\(interface))"
                variant.listedName = variant.name
                result.append(variant)
            }
        }
        return result
    }

    /// The schemes a watch app's autocreated scheme comes with, the same but for their name: a
    /// `(Complication)` one when a watch extension it depends on names a
    /// `CLKComplicationPrincipalClass` in its Info.plist, whatever the deployment target, and a
    /// `(Notification)` one when such an extension compiles a file whose name, or path without
    /// one, is `NotificationController.swift` (loader-experiments `watch-schemes`: neither a
    /// storyboard's notification scene, nor a path ending so, nor `.m`; octopod). A storyboard
    /// missing from any project of the workspace gives every watch app `(Glance)` and
    /// `(Notification)` (`watch-schemes-missing`, `-referencing`, `-referenced`, `-workspace`,
    /// `-complication`: after `(Complication)`).
    private func watchInterfaces(of target: PBXTarget) throws -> [String] {
        guard productType(target) == Self.type("application.watchapp2") else { return [] }
        let extensions = dependencies(of: target).filter { productType($0) == Self.type("watchkit2-extension") }
        var interfaces: [String] = []
        if try extensions.contains(where: { try infoPlist(of: $0)?["CLKComplicationPrincipalClass"] != nil }) { interfaces.append("Complication") }
        let compilesNotification = extensions.contains { watchExtension in
            watchExtension.buildPhases.contains { phase in
                phase is PBXSourcesBuildPhase && (phase.files ?? []).contains { ($0.file?.name ?? $0.file?.path) == "NotificationController.swift" }
            }
        }
        if missingStoryboard { interfaces.append("Glance") }
        if compilesNotification || missingStoryboard { interfaces.append("Notification") }
        return interfaces
    }

    private func entry(_ target: PBXTarget, buildFor: Set<String>) -> XcodeScheme.BuildEntry {
        XcodeScheme.BuildEntry(containerPath: project.path, targetID: target.uuid, targetName: target.name, buildFor: buildFor)
    }

    /// The apps that depend on `target` directly or through one other target, each followed by
    /// that target, in project order. With several, xcodebuild's order changes from one run to
    /// the next (`autocreate-hosts`: ManyHosts, Mixed); nomac keeps project order.
    private func hosts(of target: PBXTarget) -> [PBXTarget] {
        let targets = project.project.targets
        let direct = targets.filter { dependencies(of: $0).contains(target) }
        return targets.filter { Self.hostApps.contains(productType($0)) }.flatMap { host -> [PBXTarget] in
            if direct.contains(host) { return [host] }
            guard let middle = direct.first(where: { dependencies(of: host).contains($0) }) else { return [] }
            return [host, middle]
        }
    }

    /// Whether `target`'s Info.plist, in the read configuration, names a Safari extension point.
    private func isSafariExtension(_ target: PBXTarget) throws -> Bool {
        guard Self.safariChecked.contains(productType(target)),
              let point = (try infoPlist(of: target)?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String else { return false }
        return Self.safariExtensionPoints.contains(point)
    }

    /// `target`'s Info.plist, its `INFOPLIST_FILE` in the read configuration.
    private func infoPlist(of target: PBXTarget) throws -> [String: Any]? {
        let values = try evaluated(target, readConfiguration)
        guard let file = values["INFOPLIST_FILE"], !file.isEmpty else { return nil }
        let path = file.hasPrefix("/") ? file : (values["SRCROOT"] ?? project.projectDirectory) + "/" + file
        guard let data = FileSystem.contents(atPath: path) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// The targets whose autocreated scheme tests `bundle` (`test-hosts`): a UI test bundle's
    /// `TestTargetID` when it is an app (``uiTested``), a unit test bundle's test host, if the
    /// bundle depends on it. A unit test
    /// bundle's `TEST_HOST` must be that target's executable, and so must its `BUNDLE_LOADER`
    /// when it has no `TestTargetID` (tofu: TofuTests and TofuUITests, tested by Tofu). Such a
    /// bundle gets no scheme of its own, even when a shared or per-user scheme covers that
    /// target instead (`own-test-schemes`: App14Tests, App26Tests, App32UITests). A path names the
    /// executable when it is that path, or when its part under the bundle's `BUILT_PRODUCTS_DIR` is
    /// the target's `EXECUTABLE_PATH`, as for a bundle or an app whose `SDKROOT` is `auto`, whose
    /// products folder is `Debug-unknown` (`autocreate-testables`: Auto16 to Auto20). Such an app's
    /// executable is its iOS or its macOS one (`autocreate-auto-hosts`: A01 to A04, A11 and A12,
    /// with either layout and the platforms in either order; not A09's, naming another app).
    private func testedTargets(of bundle: PBXTarget) throws -> [PBXTarget] {
        let testTargetID = project.project.targetAttributes[bundle]?["TestTargetID"]?.stringValue
        let candidates = dependencies(of: bundle)
        guard productType(bundle) == Self.unitTest, !candidates.isEmpty else {
            return candidates.filter { $0.uuid == testTargetID && Self.uiTested.contains(productType($0)) }
        }
        let values = try evaluated(bundle, readConfiguration)
        let products = Self.standardized(values["BUILT_PRODUCTS_DIR"] ?? "")
        return try candidates.filter { tested in
            guard testTargetID == nil || testTargetID == tested.uuid else { return false }
            let host = try evaluated(tested, readConfiguration)
            guard let directory = host["BUILT_PRODUCTS_DIR"] else { return false }
            return Self.executablePaths(host).contains { executable in
                let path = Self.standardized(directory + "/" + executable)
                func names(_ setting: String) -> Bool {
                    let value = Self.standardized(values[setting] ?? "")
                    return value == path || (value.hasPrefix(products + "/") && String(value.dropFirst(products.count + 1)) == Self.standardized(executable))
                }
                return names("TEST_HOST") && (testTargetID != nil || names("BUNDLE_LOADER"))
            }
        }
    }

    /// Whether a test bundle that no scheme covers and no target's scheme would test gets a
    /// scheme of its own. When its `TEST_HOST` in the default configuration is the executable of
    /// a target of any project of the workspace, that target decides: unless it has an autocreated
    /// scheme. Otherwise, unless it depends on a target with an autocreated scheme
    /// (loader-experiments `own-test-schemes`, `own-test-schemes-hosts`, `own-test-schemes-more`:
    /// B1Tests, which depends on an autocreated framework and whose TEST_HOST is an app a shared
    /// scheme launches, gets one, as does B4Tests, whose TEST_HOST is another project's; B3Tests,
    /// whose TEST_HOST names nothing, does not; a TEST_HOST naming an app's bundle, a suppressed
    /// app or a messages app does not count; `test-bundles`, `test-hosts`; `BUNDLE_LOADER` alone
    /// does not count). A TEST_HOST under the bundle's `BUILT_PRODUCTS_DIR` names the executables
    /// at the same place under their own, whatever their configuration (B5Tests names an app
    /// whose project has the configurations AppStore and Production).
    private func ownsScheme(testBundle: PBXTarget, autocreated: Set<String>, executables: [Executable]) throws -> Bool {
        let values = try evaluated(testBundle, defaultConfiguration)
        let host = Self.standardized(values["TEST_HOST"] ?? "")
        if !host.isEmpty {
            let products = Self.standardized(values["BUILT_PRODUCTS_DIR"] ?? "")
            let relative = host.hasPrefix(products + "/") ? String(host.dropFirst(products.count + 1)) : nil
            let named = executables.filter { $0.path == host || $0.executablePath == relative }
            if !named.isEmpty {
                return !named.contains(where: \.isAutocreated)
            }
        }
        return !dependencies(of: testBundle).contains { autocreated.contains($0.uuid) }
    }

    private static func standardized(_ path: String) -> String { (path as NSString).standardizingPath }
}
