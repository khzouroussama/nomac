/// Tasks Swift Build sandboxes, off macOS (docs/adr/0103-script-phase-shell.md, addendum).
///
/// With `ENABLE_USER_SCRIPT_SANDBOXING = YES`, Xcode's default for new projects, Swift Build runs
/// each script phase as `/usr/bin/sandbox-exec -D … -f <profile> /bin/sh -c <script>`, the profile
/// allowing writes to the phase's declared outputs only (`script_sandbox_experiments.py`: Xcode
/// 27.0 builds a script that keeps to them and refuses one that writes elsewhere). Linux has no
/// `sandbox-exec` ("unable to spawn process '/usr/bin/sandbox-exec'"), and Swift Build starts it
/// itself, out of the exec interposer's reach. Builds off macOS synthesize
/// `DISABLE_TASK_SANDBOXING`, which drops only the wrapper and its profile: the script runs as the
/// plain command, with the same planning and outputs for a script that keeps to its declared
/// inputs and outputs; the sandbox's enforcement is not reproduced (B-132).
public enum TaskSandbox {
    /// The settings a build off macOS synthesizes, below the command line's.
    public static let overrides = ["DISABLE_TASK_SANDBOXING": "YES"]
}
