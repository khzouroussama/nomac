#!/usr/bin/env python3
"""How xcodebuild runs a Swift package's build tool plugin, for self-written packages (B-009).

The package `Gen` has an executable `GenTool`, a build tool plugin `GenPlugin` that depends on
it, and a library `Lib` that applies the plugin. The plugin uses only `PackagePlugin`: for each
target it applies to, one build command runs `GenTool` to write `Generated.swift` into the
plugin's work directory, which `Lib` compiles. It also writes `probe.json` there, with what it
was given: its work directory, the package's and the target's folders and source files, the
tool's path, its arguments, working directory and environment. Each variant builds the
package's `Lib` scheme in the package's folder for `generic/platform=iOS`, code signing off:

- buildCommand: the build command above;
- prebuildCommand: a prebuild command instead, writing into its output folder;
- project: loader_experiments.py's `build-tool-plugin` app, a target of an Xcode project that
  applies a local package's plugin, whose `XcodeBuildToolPlugin` conformance records its
  `XcodePluginContext` the same way and returns the build command; built by the project's `App`
  scheme;
- project-quoting: the same, with two commands: the first given arguments with a space, a quote,
  a `$`, a backslash and each other printable punctuation character, an environment variable, the app's source as an input and two outputs,
  the second one output; the tool writes a constant named after each output file;
- project-package-only: the project, with a plugin that has only its `BuildToolPlugin`
  conformance.

Usage:
  build_plugin_experiments.py <out>                  on a Mac: xcodebuild (DEVELOPER_DIR)
  build_plugin_experiments.py <out> --nomac <nomac> [nomac build options...]

<out>/<variant>/<tool>.log keeps the build's output; <out>/<tool>.json lists, per variant, the
exit status, the log's plugin lines, the plugin executables folder, the plugin's compile command
(from its `-state.json`), the custom tasks and shell-script phases of the PIF xcodebuild gave Swift Build,
the log's CustomTask blocks, the scripts of the targets' shell-script phases, the files the
build generated and the probe's record, with the derived data folder written `<dd>` and the
package's `<src>`.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loader_experiments as loader  # noqa: E402

PACKAGE = """// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Gen",
    products: [.library(name: "Lib", targets: ["Lib"])],
    targets: [
        .executableTarget(name: "GenTool"),
        .plugin(name: "GenPlugin", capability: .buildTool(), dependencies: ["GenTool"]),
        .target(name: "Lib", plugins: ["GenPlugin"]),
    ]
)
"""
TOOL = """import Foundation

try "public let generated = 1\\n".write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
"""
PLUGIN = """import Foundation
import PackagePlugin

@main
struct GenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let work = context.pluginWorkDirectoryURL
        let tool = try context.tool(named: "GenTool")
        let probe: [String: Any] = [
            "pluginWorkDirectory": work.path,
            "package": ["id": context.package.id, "displayName": context.package.displayName, "directory": context.package.directoryURL.path,
                        "targets": context.package.targets.map(\\.name), "products": context.package.products.map(\\.name)],
            "target": ["name": target.name, "directory": target.sourceModule?.directoryURL.path ?? "",
                       "sourceFiles": target.sourceModule.map { $0.sourceFiles.map(\\.url.path) } ?? []],
            "tool": ["name": tool.name, "path": tool.url.path],
            "arguments": CommandLine.arguments,
            "workingDirectory": FileManager.default.currentDirectoryPath,
            "environment": ProcessInfo.processInfo.environment,
        ]
        try JSONSerialization.data(withJSONObject: probe, options: [.prettyPrinted, .sortedKeys]).write(to: work.appending(path: "probe.json"))
        COMMAND
    }
}
"""
COMMANDS = {
    "buildCommand": """let output = work.appending(path: "Generated.swift")
        return [.buildCommand(displayName: "Generate \\(target.name)", executable: tool.url, arguments: [output.path], outputFiles: [output])]""",
    "prebuildCommand": """let folder = work.appending(path: "Prebuilt")
        return [.prebuildCommand(displayName: "Prebuild \\(target.name)", executable: tool.url, arguments: [folder.appending(path: "Generated.swift").path],
                                 outputFilesDirectory: folder)]""",
}
XCODE_PLUGIN = """import Foundation
import PackagePlugin

@main
struct GenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] { [] }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension GenPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let work = context.pluginWorkDirectoryURL
        let tool = try context.tool(named: "GenTool")
        func describe(_ target: XcodeTarget) -> [String: Any] {
            ["id": target.id, "displayName": target.displayName,
             "product": target.product.map { ["name": $0.name, "kind": String(describing: $0.kind)] } ?? NSNull(),
             "dependencies": target.dependencies.map { dependency -> String in
                 switch dependency {
                 case .target(let target): return "target:" + target.displayName
                 case .product(let product): return "product:" + product.name
                 @unknown default: return "unknown"
                 }
             },
             "inputFiles": target.inputFiles.map { [$0.url.path, String(describing: $0.type)] }]
        }
        let probe: [String: Any] = [
            "pluginWorkDirectory": work.path,
            "project": ["id": context.xcodeProject.id, "displayName": context.xcodeProject.displayName,
                        "directory": context.xcodeProject.directoryURL.path, "filePaths": context.xcodeProject.filePaths.map(\\.string),
                        "targets": context.xcodeProject.targets.map(describe)],
            "target": describe(target),
            "tool": ["name": tool.name, "path": tool.url.path],
            "arguments": CommandLine.arguments,
            "workingDirectory": FileManager.default.currentDirectoryPath,
            "environment": ProcessInfo.processInfo.environment,
        ]
        try JSONSerialization.data(withJSONObject: probe, options: [.prettyPrinted, .sortedKeys]).write(to: work.appending(path: "probe.json"))
        COMMAND
    }
}
#endif
"""
XCODE_COMMAND = """let output = work.appending(path: "Generated.swift")
        return [.buildCommand(displayName: "Generate", executable: tool.url, arguments: [output.path], outputFiles: [output])]"""
XCODE_PLUGIN = XCODE_PLUGIN.replace("COMMAND", XCODE_COMMAND)
QUOTING_TOOL = """import Foundation

for path in CommandLine.arguments.dropFirst() where path.hasSuffix(".swift") {
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    try "let \\(name) = 1\\n".write(toFile: path, atomically: true, encoding: .utf8)
}
"""
# One argument for each printable ASCII punctuation character but the quote, the backslash and the
# backtick, which xcodebuild leaves unescaped in the script it writes, so that the script fails.
PUNCTUATION = ", ".join('"a' + c + 'b"' for c in "!#$%&'()*+,-./:;<=>?@[]^_{|}~")
QUOTING_COMMANDS = """let first = work.appending(path: "First.swift"), extra = work.appending(path: "Extra.swift"), second = work.appending(path: "Second.swift")
        let source = target.inputFiles.first { $0.url.lastPathComponent == "App.swift" }!.url
        return [.buildCommand(displayName: "Generate first", executable: tool.url, arguments: [first.path, extra.path, "a b", "q\\"uote", "$HOME", "back\\\\slash", """ + PUNCTUATION + """],
                              environment: ["NOMAC_ENV": "v w"], inputFiles: [source], outputFiles: [first, extra]),
                .buildCommand(displayName: "Generate second", executable: tool.url, arguments: [second.path], outputFiles: [second])]"""
SOURCES = {"Sources/GenTool/main.swift": TOOL, "Sources/Lib/Lib.swift": "public func value() -> Int { generated }\n", "Package.swift": PACKAGE}


def normalize(value, derived, source):
    if isinstance(value, str):
        return value.replace(str(derived), "<dd>").replace(str(source), "<src>")
    if isinstance(value, list):
        return [normalize(item, derived, source) for item in value]
    if isinstance(value, dict):
        return {key: normalize(item, derived, source) for key, item in value.items()}
    return value


def plugin_tasks(derived):
    """The PIF's custom tasks and shell-script phases, by target, as the build gave them to Swift Build."""
    tasks = {}
    for path in sorted((derived / "Build/Intermediates.noindex/XCBuildData/PIFCache/target").glob("*")):
        target = json.loads(path.read_text())
        phases = [phase for phase in target.get("buildPhases", []) if phase.get("type") == "com.apple.buildphase.shell-script"]
        if target.get("customTasks") or phases:
            tasks[target.get("name")] = {"customTasks": target.get("customTasks", []), "scriptPhases": phases}
    return tasks


def custom_task_blocks(log):
    """The log's CustomTask blocks, without the task's hash and the PATH Swift Build exports, which
    names Swift Build's own bundle."""
    blocks = []
    for block in log.split("\n\n"):
        lines = block.splitlines()
        if lines and lines[0].startswith("CustomTask "):
            header = re.sub(r" [0-9a-f]{32} ", " <hash> ", lines[0])
            blocks.append([header] + [line for line in lines[1:] if not line.startswith("    export PATH\\=")])
    return blocks


def variant_files(name):
    """The variant's files, and the arguments that select what xcodebuild builds."""
    if name in ("project", "project-quoting", "project-package-only"):
        files = loader.build_tool_plugin()
        files["Deps/Gen/Plugins/GenPlugin/plugin.swift"] = XCODE_PLUGIN
        if name == "project-package-only":
            files["Deps/Gen/Plugins/GenPlugin/plugin.swift"] = XCODE_PLUGIN[:XCODE_PLUGIN.index("#if canImport(XcodeProjectPlugin)")]
        if name == "project-quoting":
            files["Deps/Gen/Plugins/GenPlugin/plugin.swift"] = XCODE_PLUGIN.replace(XCODE_COMMAND, QUOTING_COMMANDS)
            files["Deps/Gen/Sources/GenTool/main.swift"] = QUOTING_TOOL
            files["App.swift"] = "@main struct App { static func main() { print(First, Extra, Second) } }\n"
        return files, ["-project", "P.xcodeproj", "-scheme", "App", "SWIFT_VERSION=6.0"]
    return dict(SOURCES, **{"Plugins/GenPlugin/plugin.swift": PLUGIN.replace("COMMAND", COMMANDS[name])}), ["-scheme", "Lib"]


def main():
    out = Path(sys.argv[1]).resolve()
    nomac = sys.argv[sys.argv.index("--nomac") + 1] if "--nomac" in sys.argv else None
    extra = sys.argv[sys.argv.index("--nomac") + 2:] if nomac else []
    tool = "nomac" if nomac else "xcode"
    results = {}
    for name in [*COMMANDS, "project", "project-quoting", "project-package-only"]:
        work = out / name
        source = work / f"src-{tool}"
        derived = work / f"dd-{tool}"
        shutil.rmtree(source, ignore_errors=True)
        shutil.rmtree(derived, ignore_errors=True)
        files, selection = variant_files(name)
        for path, text in files.items():
            (source / path).parent.mkdir(parents=True, exist_ok=True)
            (source / path).write_text(text)
        argv = ([nomac, "build"] if nomac else ["xcodebuild"]) + [
            *selection, "-destination", "generic/platform=iOS", "-derivedDataPath", str(derived),
            "-skipPackagePluginValidation", "CODE_SIGNING_ALLOWED=NO", *extra, "build"]
        completed = subprocess.run(argv, cwd=source, capture_output=True, text=True, env=os.environ)
        log = completed.stdout + completed.stderr
        (work / f"{tool}.log").write_text(log)
        executables = derived / "Build/Products/PluginExecutables"
        state = executables / "GenPlugin-state.json"
        probes = sorted(derived.rglob("probe.json"))
        results[name] = normalize({
            "exitStatus": completed.returncode,
            "pluginLines": [line for line in log.splitlines() if "plug-in" in line or "plugin" in line.lower() and line.startswith("[")],
            "pluginExecutables": sorted(path.name for path in executables.iterdir()) if executables.exists() else None,
            "compileCommand": json.loads(state.read_text()).get("commandLine") if state.exists() else None,
            "pifTasks": plugin_tasks(derived),
            "customTaskBlocks": custom_task_blocks(log),
            "scripts": sorted(path.read_text() for path in (derived / "Build/Intermediates.noindex").glob("*.build/*/*.build/Script-*.sh")),
            "generated": sorted(str(path.relative_to(derived)) for path in (derived / "Build/Intermediates.noindex/BuildToolPluginIntermediates").rglob("*.swift")),
            "probe": json.loads(probes[0].read_text()) if probes else None,
        }, derived, source)
    (out / f"{tool}.json").write_text(json.dumps(results, indent=2, sort_keys=True) + "\n")
    print(json.dumps({name: {key: result[key] for key in ("exitStatus", "generated")} for name, result in results.items()}, indent=2))


if __name__ == "__main__":
    main()
