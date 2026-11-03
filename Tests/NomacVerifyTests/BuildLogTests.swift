import Testing
import NomacVerify

/// xcodebuild's task blocks as its build logs print them (reference captures of the corpus apps).
@Suite struct BuildLogTests {
    @Test func splitsWordsAsAShellDoes() {
        #expect(BuildLog.words(#"a\ b 'c d' "e \"f\"" -x\=1  g"#) == ["a b", "c d", #"e "f""#, "-x=1", "g"])
        #expect(BuildLog.words("") == [])
        #expect(BuildLog.words("''") == [""])
    }

    @Test func readsTasksTheirOutputAndTheFailedOnes() {
        let log = """
            Build description signature: 0123

            CompileXIB /src/My\\ View.xib (in target 'My App' from project 'App')
                cd /src
                export XCODE_DEVELOPER_USR_PATH\\=/Xcode/usr/bin/..
                /Xcode/usr/bin/ibtool --compile /dd/My\\ View.nib /src/My\\ View.xib
            /* com.apple.ibtool.document.notices */
            /src/My View.xib: note: a notice

            SwiftExplicitDependencyGeneratePcm arm64 /dd/A.pcm
            ** BUILD FAILED **


            The following build commands failed:
            \tCompileXIB /src/My\\ View.xib (in target 'My App' from project 'App')
            (1 failure)
            """
        let parsed = BuildLog(log)
        #expect(parsed.tasks.count == 1)
        let task = parsed.tasks[0]
        #expect(task.rule == "CompileXIB")
        #expect(task.target == "My App")
        #expect(task.headerArguments == ["/src/My View.xib"])
        #expect(task.directory == "/src")
        #expect(task.environment == ["XCODE_DEVELOPER_USR_PATH": "/Xcode/usr/bin/.."])
        #expect(task.command == ["/Xcode/usr/bin/ibtool", "--compile", "/dd/My View.nib", "/src/My View.xib"])
        #expect(task.output == ["/* com.apple.ibtool.document.notices */", "/src/My View.xib: note: a notice"])
        #expect(parsed.failed == [task.header])
    }
}
