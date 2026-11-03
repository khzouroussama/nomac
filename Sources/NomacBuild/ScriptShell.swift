import Foundation
import NomacCore
import NomacPIF

/// The shell script phases run under off macOS (docs/adr/0103-script-phase-shell.md).
///
/// Swift Build runs every script phase as `/bin/sh -c <script>` and writes the script with
/// `#!<shellPath>` first, so the shell that runs the script is the phase's `shellPath`. On macOS
/// `/bin/sh` is bash 3.2 in POSIX mode, whose `echo` interprets backslash escapes;
/// `.github/scripts/shell_experiments.py` found Ubuntu's dash like it in 4 of 20 constructs, and
/// bash run as `sh` with `xpg_echo` in 19. `nomac toolchain install` writes that shell into the
/// developer directory, and off macOS `nomac build` gives the PIF it builds (never the one it
/// prints) that shell for the phases whose `shellPath` is `/bin/sh`.
public enum ScriptShell {
    /// Where the shell is, in the developer directory.
    public static let relativePath = "usr/libexec/nomac/sh"

    static let contents = """
        #!/bin/bash
        # Written by 'nomac toolchain install' (docs/adr/0103-script-phase-shell.md, docs/adr/0180-scripts-run-by-path.md).
        interposer="${0%/*}/libnomac-exec.so"
        if [ -f "$interposer" ]; then
          case ":${LD_PRELOAD-}:" in
            *":$interposer:"*) ;;
            *) export LD_PRELOAD="$interposer${LD_PRELOAD:+:$LD_PRELOAD}" ;;
          esac
        fi
        exec -a /bin/sh /bin/bash -O xpg_echo "$@"

        """

    /// Added to the signature of each PIF object the redirection changes, so that it stays unique.
    static let signatureSuffix = "_nomac-script-shell"

    /// The installed shell of `developerDirectory`, if it is there and its path can follow `#!`.
    public static func installed(developerDirectory: String) -> String? {
        let path = developerDirectory + "/" + relativePath
        return FileSystem.isFile(path) && !path.contains(where: \.isWhitespace) ? path : nil
    }

    /// `document` with `shell` for every script phase whose `shellPath` is `/bin/sh`; the targets
    /// that changed, the projects that list them and the workspace get new signatures.
    public static func redirecting(_ document: PIFDocument, to shell: String) -> PIFDocument {
        var document = document
        var renamed: [String: String] = [:]
        for type in ["target", "project", "workspace"] {
            for index in document.objects.indices where document.objects[index].type == type {
                var contents = redirect(document.objects[index].contents, to: shell)
                if case .object(var fields) = contents {
                    for key in ["targets", "projects"] {
                        if let references = fields[key]?.arrayValue {
                            fields[key] = .array(references.map { reference in reference.stringValue.flatMap { renamed[$0] }.map(PIFValue.string) ?? reference })
                        }
                    }
                    contents = .object(fields)
                }
                guard contents != document.objects[index].contents else { continue }
                let signature = document.objects[index].signature
                renamed[signature] = signature + signatureSuffix
                document.objects[index].contents = contents
                document.objects[index].signature = signature + signatureSuffix
            }
        }
        return document
    }

    private static func redirect(_ value: PIFValue, to shell: String) -> PIFValue {
        switch value {
        case .object(var fields):
            if fields["type"]?.stringValue == "com.apple.buildphase.shell-script", fields["shellPath"]?.stringValue == "/bin/sh" {
                fields["shellPath"] = .string(shell)
            }
            return .object(fields.mapValues { redirect($0, to: shell) })
        case .array(let items):
            return .array(items.map { redirect($0, to: shell) })
        default:
            return value
        }
    }

    /// Constructs where dash or plain bash differ from macOS's `sh`: pattern substitution, `echo`
    /// escapes and POSIX mode.
    static let probe = #"v=1-0-2; echo ${v/-0-/-}; echo "a\nb"; case "$SHELLOPTS" in *posix*) echo posix;; *) echo plain;; esac"#
    /// What macOS's `/bin/sh` prints for ``probe``.
    static let macOSOutput = "1-2\na\nb\nposix\n"

    /// A warning when `shell` does not run ``probe`` as macOS's `/bin/sh` does.
    public static func warning(shell: String = "/bin/sh") -> String? {
        let result = try? Subprocess.run(shell, ["-c", probe], environment: ["PATH": "/usr/bin:/bin"])
        guard result?.exitStatus != 0 || result?.outputString != macOSOutput else { return nil }
        return "\(shell) does not run scripts as macOS's sh does (bash in POSIX mode, echo escapes): "
            + "script phases may fail or write other files; 'nomac toolchain install' writes a shell that does (docs/adr/0103-script-phase-shell.md)"
    }
}
