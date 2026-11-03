#!/usr/bin/env python3
"""Swift macro plugins that are not Apple's: a project's own SwiftPM macro targets and prebuilt
plugin executables named in its flags, as test cases for `nomac build` and `nomac check` off macOS.

Three self-written apps, each a git repository at a fixed date:

  macro-package         an iOS app that uses `#stringify` and `@Greeting` from a local Swift
                        package, whose `.macro` target depends on swift-syntax 604.0.0: Xcode
                        builds the macro target for the build machine from its sources.
  macro-prebuilt        the same macros declared in the app itself and implemented by a plugin
                        executable its OTHER_SWIFT_FLAGS names with `-load-plugin-executable`, a
                        universal macOS binary built by this script from the SwiftPM package
                        beside it (`Plugin/apple`, expo-modules-macros' layout: a `.macro` target
                        and no product).
  macro-prebuilt-alone  macro-prebuilt with the binary and no package.

`generate` writes the apps (on a Mac: it builds the plugin binary with Xcode's SwiftPM, and
resolves macro-package's packages with xcodebuild); `capture` and `verify` are
expo_experiments.py's, for macro-package and macro-prebuilt: Xcode's Debug build as the
reference, and `nomac verify --build` against it (with the network allowed, for swift-syntax).
`order` records which of two `-load-plugin-executable` flags for one module the compiler uses;
`expansions` dumps macro-prebuilt's expansions with a given compiler and plugin.

Usage (DEVELOPER_DIR selects the Xcode; root defaults to ~/nomac-out/wt-scratch/macros/plugins):
  macro_plugin_experiments.py generate [--root R] [app ...]
  macro_plugin_experiments.py capture [--root R] [app ...]
  macro_plugin_experiments.py verify --nomac <nomac> [--root R] [app ...]
  macro_plugin_experiments.py order [--root R] [--swiftc <swiftc>]
  macro_plugin_experiments.py expansions --plugin <executable> --sdk <iPhoneOS.sdk> --label L [--root R] [--swiftc <swiftc>]
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import expo_experiments as expo  # noqa: E402
import loader_experiments as loader  # noqa: E402

SWIFT_SYNTAX = ".package(url: \"https://github.com/swiftlang/swift-syntax.git\", exact: \"604.0.0\")"
MACRO_DEPENDENCIES = ('[.product(name: "SwiftSyntaxMacros", package: "swift-syntax"), '
                      '.product(name: "SwiftCompilerPlugin", package: "swift-syntax")]')

PLUGIN = """import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct StringifyMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            fatalError("the macro has no argument")
        }
        return "(\\(argument), \\(literal: argument.description))"
    }
}

public struct GreetingMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let name = declaration.as(StructDeclSyntax.self)?.name.text ?? "it"
        return ["static let greeting = \\(literal: "Hello from " + name)"]
    }
}

@main
struct GreetPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [StringifyMacro.self, GreetingMacro.self]
}
"""

DECLARATIONS = """@freestanding(expression) {access}macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "GreetMacros", type: "StringifyMacro")
@attached(member, names: named(greeting)) {access}macro Greeting() = #externalMacro(module: "GreetMacros", type: "GreetingMacro")
"""

APP = """import SwiftUI
{imports}
@Greeting struct Model {{}}

@main struct GreetApp: App {{
    var body: some Scene {{
        WindowGroup {{
            Text(Model.greeting + " " + #stringify(1 + 2).1)
        }}
    }}
}}
"""

PLUGIN_FLAG = '"$(inherited) -load-plugin-executable \\"$(SRCROOT)/Plugin/apple/GreetMacros#GreetMacros\\""'


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def app_project(package):
    """An app target with App.swift (and Macros.swift unless the macros come from `package`)."""
    sources = [("A00000000000000000000003", "A00000000000000000000004", "App.swift")]
    if not package:
        sources.append(("A00000000000000000000005", "A00000000000000000000006", "Macros.swift"))
    objects = "".join(f'\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n'
                      f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n'
                      for build, ref, name in sources)
    children = "".join(f"\t\t\t\t{ref} /* {name} */,\n" for _, ref, name in sources)
    files = "".join(f"\t\t\t\t{build} /* {name} in Sources */,\n" for build, _, name in sources)
    objects += f"""		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{children}				P00000000000000000000001,
			);
			sourceTree = "<group>";
		}};
		F00000000000000000000004 /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{files}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
    settings = dict(loader.APP_SETTINGS, SWIFT_VERSION="6.0")
    extra = ""
    references = ""
    phases = ["F00000000000000000000004 /* Sources */"]
    if package:
        objects += ('\t\tD00000000000000000000001 /* XCLocalSwiftPackageReference "Deps/Greet" */ = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Greet; };\n'
                    "\t\tE00000000000000000000001 /* Greet */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = Greet; };\n")
        extra = "\t\t\tpackageProductDependencies = (\n\t\t\t\tE00000000000000000000001 /* Greet */,\n\t\t\t);\n"
        objects += """		A00000000000000000000007 /* Greet in Frameworks */ = {isa = PBXBuildFile; productRef = E00000000000000000000001 /* Greet */; };
		F00000000000000000000005 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000007 /* Greet in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
        phases.append("F00000000000000000000005 /* Frameworks */")
        references = "\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001,\n\t\t\t);\n"
    else:
        settings["OTHER_SWIFT_FLAGS"] = PLUGIN_FLAG
    objects += loader.product_file("P00000000000000000000001", "App", loader.APPLICATION)
    objects += loader.app_target("C00000000000000000000001", "App", phases,
                                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], settings,
                                 extra=extra, product_reference="P00000000000000000000001")
    return loader.project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001 /* App */"], objects,
                          package_references=references)


def plugin_manifest(products):
    return ("// swift-tools-version: 6.0\nimport CompilerPluginSupport\nimport PackageDescription\n\nlet package = Package(\n"
            '    name: "Greet",\n    platforms: [.iOS(.v18), .macOS(.v14)],\n'
            + (f"    products: {products},\n" if products else "")
            + f"    dependencies: [{SWIFT_SYNTAX}],\n    targets: [\n"
            f'        .macro(name: "GreetMacros", dependencies: {MACRO_DEPENDENCIES}),\n'
            + ('        .target(name: "Greet", dependencies: ["GreetMacros"]),\n' if products else "")
            + "    ]\n)\n")


def files(app_id):
    if app_id == "macro-package":
        return {
            "P.xcodeproj/project.pbxproj": app_project(package=True),
            "App.swift": APP.format(imports="import Greet\n"),
            "Deps/Greet/Package.swift": plugin_manifest('[.library(name: "Greet", targets: ["Greet"])]'),
            "Deps/Greet/Sources/GreetMacros/Plugin.swift": PLUGIN,
            "Deps/Greet/Sources/Greet/Greet.swift": DECLARATIONS.format(access="public "),
        }
    text = {
        "P.xcodeproj/project.pbxproj": app_project(package=False),
        "App.swift": APP.format(imports=""),
        "Macros.swift": DECLARATIONS.format(access=""),
    }
    if app_id == "macro-prebuilt":
        text["Plugin/apple/Package.swift"] = plugin_manifest(None)
        text["Plugin/apple/Sources/GreetMacros/Plugin.swift"] = PLUGIN
    return text


APPS = ["macro-package", "macro-prebuilt", "macro-prebuilt-alone"]


def build_plugin(root, env):
    """The plugin as a universal macOS binary (of the Mac's architecture: SwiftPM builds macro
    targets for the build machine only) and the package's Package.resolved, built once from the
    package macro-prebuilt ships. SwiftPM's native build system names a macro target's executable
    `<target>-tool`; its default one builds no macro target that no product names ("Could not
    find target named 'GreetMacros-product'")."""
    work = root / "plugin-build"
    binary = work / "GreetMacros"
    if not binary.exists():
        package = work / "package"
        shutil.rmtree(package, ignore_errors=True)
        for path, content in files("macro-prebuilt").items():
            if path.startswith("Plugin/apple/"):
                write(package / path.removeprefix("Plugin/apple/"), content)
        command = ["xcrun", "swift", "build", "-c", "release", "--build-system", "native"]
        expo.run(command + ["--product", "GreetMacros"], package, env)
        built = subprocess.run(command + ["--show-bin-path"], cwd=package, env=env, check=True, capture_output=True, text=True).stdout.strip()
        expo.run(["xcrun", "lipo", "-create", Path(built) / "GreetMacros-tool", "-output", binary], work, env)
        shutil.copy(package / "Package.resolved", work / "Package.resolved")
    return binary, work / "Package.resolved"


def generate(root, app_id, env):
    src = root / "apps" / app_id
    shutil.rmtree(src, ignore_errors=True)
    for path, content in files(app_id).items():
        write(src / path, content)
    if app_id == "macro-package":
        derived = root / "resolve-DerivedData"
        expo.run(["xcodebuild", "-resolvePackageDependencies", "-project", "P.xcodeproj", "-scheme", "App", "-derivedDataPath", derived], src, env)
        shutil.rmtree(derived, ignore_errors=True)
    else:
        binary, resolved = build_plugin(root, env)
        (src / "Plugin/apple").mkdir(parents=True, exist_ok=True)
        shutil.copy(binary, src / "Plugin/apple/GreetMacros")
        if app_id == "macro-prebuilt":
            shutil.copy(resolved, src / "Plugin/apple/Package.resolved")
    commit = expo.commit_everything(src)
    record = {"id": app_id, "path": str(src), "commit": commit, "container": "P.xcodeproj", "scheme": "App"}
    (root / "apps" / f"{app_id}.json").write_text(json.dumps(record, indent=2) + "\n")
    expo.log(f"{app_id}: {commit}")


def order(root, swiftc):
    """Which of two `-load-plugin-executable` flags for the module GreetMacros the compiler uses:
    the plugin, or an executable that answers nothing, first."""
    out = root / "order"
    out.mkdir(parents=True, exist_ok=True)
    plugin = root / "apps" / "macro-prebuilt" / "Plugin/apple/GreetMacros"
    silent = out / "silent"
    silent.write_text("#!/bin/sh\nexit 1\n")
    silent.chmod(0o755)
    (out / "Use.swift").write_text(DECLARATIONS.format(access="") + "let text = #stringify(1 + 2).1\n")
    results = {}
    for label, first, second in (("plugin-first", plugin, silent), ("silent-first", silent, plugin)):
        proc = subprocess.run(swiftc + ["-typecheck", "Use.swift", "-load-plugin-executable", f"{first}#GreetMacros",
                                        "-load-plugin-executable", f"{second}#GreetMacros"], cwd=out, capture_output=True, text=True)
        errors = [line for line in proc.stderr.splitlines() if ": error: " in line]
        results[label] = {"exitStatus": proc.returncode, "firstError": errors[0].split(": error: ", 1)[1] if errors else None}
    (out / "order.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


def expansions(root, swiftc, plugin, sdk, label):
    """macro-prebuilt's sources type-checked for iOS with `-dump-macro-expansions` and `plugin`:
    Xcode's compiler with the binary the app ships, and swift.org's with nomac's build of its
    package, write <root>/expansions/<label>.txt for a byte comparison."""
    src = root / "apps" / "macro-prebuilt"
    out = root / "expansions"
    out.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(swiftc + ["-typecheck", "-target", "arm64-apple-ios18.0", "-sdk", sdk, "-swift-version", "6", "App.swift", "Macros.swift",
                                    "-Xfrontend", "-dump-macro-expansions", "-load-plugin-executable", f"{plugin}#GreetMacros"],
                          cwd=src, capture_output=True, text=True)
    (out / f"{label}.txt").write_text(proc.stderr)
    print(f"{label}: exit {proc.returncode}, {proc.stderr.count('@__swiftmacro_')} expansions")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["generate", "capture", "verify", "order", "expansions"])
    parser.add_argument("apps", nargs="*")
    parser.add_argument("--root", type=Path, default=Path.home() / "nomac-out/wt-scratch/macros/plugins")
    parser.add_argument("--nomac")
    parser.add_argument("--swiftc", default="xcrun swiftc")
    parser.add_argument("--plugin", help="expansions: the plugin executable")
    parser.add_argument("--sdk", help="expansions: the iPhoneOS SDK")
    parser.add_argument("--label", default="xcode", help="expansions: the output's name")
    args = parser.parse_intermixed_args()
    root = args.root.resolve()
    (root / "apps").mkdir(parents=True, exist_ok=True)
    expo.NESTED_SWIFTPM.update(APPS)
    if args.command == "order":
        return order(root, args.swiftc.split())
    if args.command == "expansions":
        return expansions(root, args.swiftc.split(), args.plugin, args.sdk, args.label)
    developer_dir = os.environ.get("DEVELOPER_DIR") or sys.exit("error: set DEVELOPER_DIR to the reference Xcode")
    env = expo.capture.reference_environment(developer_dir)
    for app_id in args.apps or (APPS if args.command == "generate" else APPS[:2]):
        if args.command == "generate":
            generate(root, app_id, env)
        elif args.command == "capture":
            expo.capture_app(root, app_id, ["Debug"])
        else:
            expo.verify_app(root, app_id, ["Debug"], args.nomac or sys.exit("error: verify needs --nomac"))


if __name__ == "__main__":
    main()
