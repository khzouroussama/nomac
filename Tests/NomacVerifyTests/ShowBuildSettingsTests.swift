import Testing
import NomacVerify

@Suite struct ShowBuildSettingsTests {
    let sample = """
    Command line invocation:
        /usr/bin/xcodebuild -showBuildSettings -target App

    Build settings for action build and target App:
        ACTION = build
        BUILD_STYLE = 
        OTHER_SWIFT_FLAGS = -D A = B
        ARCH_COHORT_arm64e = arm64e arm64e.x1

    Build settings for action build and target "App \\"Tests\\"":
        ACTION = build


    """

    @Test func parsesBlocksAndIgnoresThePreamble() {
        let blocks = ShowBuildSettings.parse(sample)
        #expect(blocks.map(\.target) == ["App", #"App "Tests""#])
        #expect(blocks[0].dictionary["BUILD_STYLE"] == "")
        #expect(blocks[0].dictionary["OTHER_SWIFT_FLAGS"] == "-D A = B")
        #expect(blocks[0].settings.count == 4)
    }

    @Test func rendersKeysInByteOrder() {
        // Observed in Xcode 27: ARCHS_* sorts before ARCH_COHORT_* (byte order, not case-insensitive).
        let block = ShowBuildSettings.Block(action: "build", target: "App", settings: ["ARCH_COHORT_arm64e": "x", "ARCHS": "arm64", "arch": "y", "ACTION": "build"])
        #expect(ShowBuildSettings.render([block]) == """
        Build settings for action build and target App:
            ACTION = build
            ARCHS = arm64
            ARCH_COHORT_arm64e = x
            arch = y


        """)
    }

    /// The headers Xcode 27.0 printed for targets of loader-experiments `target-names`.
    @Test func quotesTargetNamesAsXcodeDoes() {
        let observed: [(String, String)] = [
            ("Plain", "Plain"), ("Dash-Name", "Dash-Name"), ("Dot.Name", "Dot.Name"), ("Under_Score", "Under_Score"),
            ("Plus+Name", "Plus+Name"), ("Comma,Name", "Comma,Name"), ("Equals=Name", "Equals=Name"), ("Slash/Name", "Slash/Name"),
            ("Ünïcödé", "Ünïcödé"), ("With Space", #""With Space""#), ("At@Name", #""At@Name""#), ("Colon:Name", #""Colon:Name""#),
            ("Semi;Name", #""Semi;Name""#), ("Quote'Name", #""Quote'Name""#), (#"Double"Name"#, #""Double\"Name""#),
            ("Dollar$Name", #""Dollar$Name""#), ("Paren(Name)", #""Paren(Name)""#), ("Bracket[Name]", #""Bracket[Name]""#),
            ("Brace{Name}", #""Brace{Name}""#), ("Star*Name", #""Star*Name""#), ("Question?Name", #""Question?Name""#),
            ("Bang!Name", #""Bang!Name""#), ("Hash#Name", #""Hash#Name""#), ("Percent%Name", #""Percent%Name""#),
            ("Amp&Name", #""Amp&Name""#), ("Pipe|Name", #""Pipe|Name""#), (#"Back\Name"#, #""Back\\Name""#),
            ("Tilde~Name", #""Tilde~Name""#), ("Angle<Name>", #""Angle<Name>""#), ("Caret^Name", #""Caret^Name""#),
            ("Grave`Name", #""Grave`Name""#), ("Trailing ", #""Trailing ""#), (" Leading", #"" Leading""#), ("Tab\tName", "\"Tab\tName\""),
        ]
        for (name, header) in observed {
            #expect(ShowBuildSettings.headerName(name) == header)
            let block = ShowBuildSettings.Block(action: "build", target: name, settings: ["ACTION": "build"])
            #expect(ShowBuildSettings.render([block]).hasPrefix("Build settings for action build and target \(header):\n"))
            #expect(ShowBuildSettings.parse(ShowBuildSettings.render([block])) == [block])
        }
    }

    /// The layout of Xcode 27.0's `-json` captures (icecubes): keys ordered with `_` before
    /// digits before letters, case-insensitively; slashes as they are; quotes escaped; an empty
    /// result as `[`, an empty line and `]`.
    @Test func rendersJSONAsXcodebuild() throws {
        let block = ShowBuildSettings.Block(action: "build", target: "App", settings: [
            "GCC3_VERSION": "3.3", "GCC_C_LANGUAGE_STANDARD": "gnu11", "__ARCHS__": "arm64", "arch": "undefined_arch",
            "BUILD_DIR": "/Users/me/Build/Products", "DEVELOPMENT_ASSET_PATHS": #""App/Resources""#, "ACTION": "build",
        ])
        #expect(try ShowBuildSettings.renderJSON([block]) == #"""
        [
          {
            "action" : "build",
            "buildSettings" : {
              "__ARCHS__" : "arm64",
              "ACTION" : "build",
              "arch" : "undefined_arch",
              "BUILD_DIR" : "/Users/me/Build/Products",
              "DEVELOPMENT_ASSET_PATHS" : "\"App/Resources\"",
              "GCC_C_LANGUAGE_STANDARD" : "gnu11",
              "GCC3_VERSION" : "3.3"
            },
            "target" : "App"
          }
        ]

        """#)
        #expect(try ShowBuildSettings.renderJSON([]) == "[\n\n]\n")
    }

    /// Property: rendering then parsing returns the same blocks.
    @Test func renderParseRoundTrip() {
        var state: UInt64 = 42
        func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state >> 33 }
        let keys = ["A", "B_C", "lower", "X1", "Y_2"]
        for _ in 0..<200 {
            var settings: [String: String] = [:]
            for key in keys where next() % 2 == 0 {
                settings[key] = ["", "v", "a b", "x = y", "$(inherited) -O"][Int(next() % 5)]
            }
            let block = ShowBuildSettings.Block(action: "build", target: "T\(next() % 3)", settings: settings)
            #expect(ShowBuildSettings.parse(ShowBuildSettings.render([block])) == [block])
        }
    }
}

@Suite struct PathNormalizerTests {
    @Test func replacesRootsAtPathBoundariesLongestFirst() {
        let normalizer = PathNormalizer(roots: [
            .init(path: "/Users/runner", symbol: "<HOME>"),
            .init(path: "/Users/runner/work/app/", symbol: "<SOURCE_ROOT>"),
        ])
        #expect(normalizer.normalize("/Users/runner/work/app/Source /Users/runner/x /Users/runnerX") == "<SOURCE_ROOT>/Source <HOME>/x /Users/runnerX")
    }

    @Test func ignoresEmptyAndRootPaths() {
        let normalizer = PathNormalizer(roots: [.init(path: "", symbol: "<E>"), .init(path: "/", symbol: "<R>")])
        #expect(normalizer.normalize("/a/b") == "/a/b")
    }
}

@Suite struct SettingsComparisonTests {
    @Test func reportsMissingExtraAndChangedSettings() {
        let expected = "Build settings for action build and target App:\n    A = 1\n    B = 2\n\n"
        let actual = "Build settings for action build and target App:\n    A = 1\n    B = 3\n    C = 4\n\n"
        let result = SettingsComparison.compare(expected: expected, actual: actual, normalizer: PathNormalizer(roots: []))
        #expect(!result.identical)
        #expect(result.differences == [
            .value(target: "App", key: "B", expected: "2", actual: "3"),
            .extra(target: "App", key: "C", actual: "4"),
        ])
    }

    @Test func identicalAfterNormalization() {
        let expected = "Command line invocation:\n    xcodebuild\n\nBuild settings for action build and target App:\n    SRCROOT = /mac/src\n\n"
        let actual = "Build settings for action build and target App:\n    SRCROOT = /linux/src\n\n"
        let normalizer = PathNormalizer(roots: [.init(path: "/mac/src", symbol: "<S>"), .init(path: "/linux/src", symbol: "<S>")])
        #expect(SettingsComparison.compare(expected: expected, actual: actual, normalizer: normalizer).identical)
    }
}
