import Testing
@testable import nomac

@Suite struct ProjectFixesFlagTests {
    @Test func buildAndArchiveTakeTheSwitch() throws {
        #expect(try BuildCommand.parse(["-project", "A.xcodeproj"]).options.noProjectFixes == false)
        #expect(try BuildCommand.parse(["--no-project-fixes", "-project", "A.xcodeproj"]).options.noProjectFixes == true)
        #expect(try ArchiveCommand.parse(["--no-project-fixes", "-project", "A.xcodeproj", "-archivePath", "A.xcarchive"]).options.noProjectFixes == true)
    }
}
