import NomacCore

/// codesign's command line, for the options Xcode 27.0 passes: Swift Build's CodeSign tasks
/// (`--force --sign <identity> [--entitlements <file>] [--timestamp=none]
/// [--preserve-metadata=<list>] --generate-entitlement-der <path>`) and the export of an archive
/// (`-f -s <identity> --entitlements <file> --preserve-metadata=<list> --generate-entitlement-der
/// --strip-disallowed-xattrs -vvv <path>`).
public enum CodesignArguments {
    /// The paths of `-r- --display <path>…` (also `-d`), which Swift Build runs to compare a
    /// library's signature before and after it signs it again; nil for other command lines.
    public static func displayedPaths(_ arguments: [String]) throws -> [String]? {
        guard arguments.contains("--display") || arguments.contains("-d") else { return nil }
        var paths: [String] = []
        var requirements = false
        for argument in arguments {
            switch argument {
            case "--display", "-d": break
            case "-r-", "--requirements=-": requirements = true
            default:
                if argument.hasPrefix("-") { throw NomacError("unsupported codesign option \(argument) with --display") }
                paths.append(argument)
            }
        }
        guard requirements else { throw NomacError("only -r- --display is supported") }
        guard !paths.isEmpty else { throw NomacError("no files to display") }
        return paths
    }

    /// One request per path, in order. Without `--keychain`, the identity file is the environment's
    /// `CODE_SIGN_KEYCHAIN`, which Swift Build exports to script phases from its provisioning answer
    /// (observed with `nomac archive --keychain`): scripts such as CocoaPods' frameworks script run
    /// `codesign --sign` without a keychain, as Xcode's codesign then searches the user's keychains.
    public static func parse(_ arguments: [String], environment: [String: String] = [:]) throws -> [CodeSigner.Request] {
        var identity: String?
        var keychain: String?
        var preEncryptHashes = false
        var force = false
        var entitlements: String?
        var preserved: Set<String> = []
        var identifier: String?
        var verbose = false
        var paths: [String] = []
        var index = 0

        func value(_ option: String, inline: String?) throws -> String {
            if let inline { return inline }
            index += 1
            guard index < arguments.count else { throw NomacError("option \(option) requires an argument") }
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            let inline = argument.hasPrefix("--") && parts.count == 2 ? parts[1] : nil
            switch argument.hasPrefix("--") ? parts[0] : argument {
            case "-s", "--sign": identity = try value(argument, inline: inline)
            case "-f", "--force": force = true
            case "--keychain": keychain = try value(argument, inline: inline)
            case "--entitlements": entitlements = try value(argument, inline: inline)
            case "--preserve-metadata": preserved.formUnion((inline ?? "").split(separator: ",").map(String.init))
            case "-i", "--identifier": identifier = try value(argument, inline: inline)
            case "--generate-pre-encrypt-hashes": preEncryptHashes = true
            case "--generate-entitlement-der", "--strip-disallowed-xattrs":
                // DER entitlements are written in any case; files nomac signs carry no extended
                // attributes to strip.
                break
            case "--timestamp":
                guard inline == "none" else { throw NomacError("secure timestamps are not supported (--timestamp=none only)") }
            case "--verbose": verbose = true
            default:
                if argument.hasPrefix("-v"), argument.dropFirst().allSatisfy({ $0 == "v" }) {
                    verbose = true
                } else if argument.hasPrefix("-") {
                    throw NomacError("unsupported codesign option \(argument)")
                } else {
                    paths.append(argument)
                }
            }
            index += 1
        }
        guard let identity else { throw NomacError("only signing is supported: pass --sign <identity>") }
        if keychain == nil, let fromEnvironment = environment["CODE_SIGN_KEYCHAIN"], !fromEnvironment.isEmpty { keychain = fromEnvironment }
        guard !paths.isEmpty else { throw NomacError("no files to sign") }
        return paths.map {
            CodeSigner.Request(path: $0, identity: identity, keychain: keychain, force: force, entitlementsPath: entitlements,
                               preservedMetadata: preserved, identifier: identifier, verbose: verbose, preEncryptHashes: preEncryptHashes)
        }
    }
}
