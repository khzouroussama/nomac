import Foundation
import Testing
import NomacVerify

/// How `nomac corpus results` measures each progress line (docs/VERIFICATION.md "Progress").
@Suite struct CorpusResultsTests {
    typealias Check = VerificationReport.Check

    let manifest: CorpusManifest

    init() throws {
        let app = { (id: String) in
            "{\"id\": \"\(id)\", \"name\": \"\(id)\", \"repository\": \"\", \"commit\": \"\", \"license\": \"MIT\", \"container\": \"A.xcodeproj\", \"tier\": \"A\", \"submodules\": false, \"prepare\": [], \"exercises\": [], \"notes\": \"\"}"
        }
        let json = """
            {"schemaVersion": 1, "xcode": {"version": "27.0", "build": "27A266a", "runner": "xcode-27", "path": "/Applications/Xcode_27.app"},
             "progress": [
               {"title": "Loader", "weight": 20, "kinds": ["pif", "settings"], "measure": "apps"},
               {"title": "Nibs", "weight": 10, "kinds": ["nib"], "measure": "checks"},
               {"title": "Core Data", "weight": 4, "kinds": ["coredata"], "measure": "checks"},
               {"title": "Device", "weight": 6, "kinds": [], "measure": "checks"},
               {"title": "Harness", "weight": 2, "kinds": [], "measure": "reports"},
               {"title": "Build", "weight": 25, "kinds": ["build"], "measure": "checks", "host": "Linux"}
             ],
             "apps": [\(app("a")), \(app("b")), \(app("c"))]}
            """
        manifest = try JSONDecoder().decode(CorpusManifest.self, from: Data(json.utf8))
    }

    var results: CorpusResults {
        let mac = VerificationReport.Host(system: "macOS", toolchain: "xcode")
        let build = { (status: Check.Status) in Check(kind: "build", name: "Release-iphoneos/App.app", status: status, detail: []) }
        return CorpusResults(manifest: manifest, reports: [
            VerificationReport(app: "a", xcodeBuild: "27A266a", host: mac, checks: [
                build(.identical), build(.equivalent),
                Check(kind: "pif", name: "workspace.pif", status: .identical, detail: []),
                Check(kind: "settings", name: "default", status: .identical, detail: []),
                Check(kind: "nib", name: "App CompileStoryboard Main.storyboard", status: .identical, detail: []),
                Check(kind: "nib", name: "App CompileXIB Cell.xib", status: .refused,
                      detail: ["nomac ibtool exited with status 1", "/src/Cell.xib: error: nomac does not compile <tableViewCell> in <objects> yet (BACKLOG B-260)"]),
            ]),
            // The same app verified on Linux: only its build checks count, for the build line.
            VerificationReport(app: "a", xcodeBuild: "27A266a", host: .init(system: "Linux", toolchain: "nomac"), checks: [
                Check(kind: "pif", name: "workspace.pif", status: .identical, detail: []),
                Check(kind: "nib", name: "App CompileStoryboard Main.storyboard", status: .different, detail: []),
                build(.identical), build(.different),
            ]),
            VerificationReport(app: "b", xcodeBuild: "27A266a", host: mac, checks: [
                build(.identical),
                Check(kind: "pif", name: "workspace.pif", status: .different, detail: []),
                Check(kind: "nib", name: "App CompileStoryboard Main.storyboard", status: .different, detail: []),
                Check(kind: "nib", name: "App CompileXIB Other.xib", status: .refused,
                      detail: ["nomac ibtool exited with status 1", "/src/Other.xib: error: nomac does not compile <tableViewCell> in <objects> yet (BACKLOG B-260)"]),
                Check(kind: "nib", name: "App LinkStoryboards", status: .referenceFailed, detail: []),
            ]),
        ])
    }

    @Test func measuresLinesByAppsOrByChecks() {
        let lines = manifest.progress
        let percentages: [Int] = lines.map { results.percentage($0) }
        #expect(percentages == [33, 25, 0, 0, 66, 50])
        let nibs = results.measurement(lines[1])
        #expect(nibs.passing == 1 && nibs.total == 4 && nibs.apps == 2)
        // (20 × 33 + 10 × 25 + 2 × 66 + 25 × 50) / 67
        #expect(results.overall == 34)
    }

    @Test func theBuildDriverCountsLinuxBuildsAndShowsTheMacsBeside() {
        let mac = results.measurement(manifest.progress[5], host: "macOS")
        #expect(mac.passing == 3 && mac.total == 3 && mac.apps == 2)
        let section = results.progressSection(date: "2026-10-22")
        #expect(section.contains("Corpus: 0 / 3 apps build on Linux (2 / 3 on the Mac with Xcode's compilers) · 0 / 3 pass their tests on device\n"))
        #expect(section.contains("- [ ] Build · 50% · weight 25 · 1 / 2 build checks on Linux in 1 app · 3 / 3 on the Mac with Xcode's compilers, in 2 apps\n"))
        let markdown = results.resultsMarkdown(date: "2026-10-22", runURL: nil)
        #expect(markdown.contains("| build on Linux | 1 | 0 | 1 | 0 | 2 |\n"))
        #expect(markdown.contains("| build on the Mac (Xcode's compilers) | 2 | 1 | 0 | 0 | 3 |\n"))
    }

    @Test func saysWhatEachLineCounts() {
        let section = results.progressSection(date: "2026-10-22")
        #expect(section.contains("- [ ] Loader · 33% · weight 20 · 1 / 3 apps\n"))
        #expect(section.contains("- [ ] Nibs · 25% · weight 10 · 1 / 4 nib checks in 2 apps\n"))
        #expect(section.contains("- [ ] Core Data · 0% · weight 4 · no coredata checks compared yet\n"))
        #expect(section.contains("- [ ] Device · 0% · weight 6 · no check kind yet\n"))
        #expect(section.contains("- [ ] Harness · 66% · weight 2 · 2 / 3 apps verified\n"))
    }

    @Test func listsRefusalsByMessage() {
        let markdown = results.resultsMarkdown(date: "2026-10-22", runURL: nil)
        #expect(markdown.contains("| a | A | identical | 1 / 1 | 0 | 0 | ✓ | – | 1 / 2 | – | – | – | – | 1 / 2 | 2 / 2 | – |\n"))
        #expect(markdown.contains("| nib | 1 | 0 | 1 | 2 | 4 |\n"))
        #expect(markdown.contains("| nib | 2 | nomac does not compile <tableViewCell> in <objects> yet (BACKLOG B-260) |\n"))
    }
}
