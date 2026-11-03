#!/usr/bin/env python3
"""Which products xcodebuild signs for the identity a build resolves, on self-written projects (B-186).

Swift Build signs a product with the identity hash its client answers for the target's
`CODE_SIGN_IDENTITY`, and signs nothing when that answer is empty. These builds show what Xcode
27.0 answers for an empty identity and for `-`, without any identity from a keychain:

- package: a Swift package with a dynamic library product, built by its scheme with no signing
  options (Xcode's package projects set `CODE_SIGN_IDENTITY = ""`), with ad-hoc signing allowed,
  and with `-` too.
- app: an app project with `CODE_SIGN_IDENTITY=` on the command line, with ad-hoc signing allowed,
  and with `-` instead.

Usage: signing_identity_experiments.py <output-dir>    (on a Mac; DEVELOPER_DIR selects the Xcode)

<output-dir>/<variant>.log keeps each build's log; summary.json lists each build's exit status,
its CodeSign tasks and the products with a `_CodeSignature`.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loader_experiments as loader  # noqa: E402


def package():
    return loader.package_files("src", "Kit", ['.library(name: "Kit", type: .dynamic, targets: ["Kit"])'],
                                {"Kit": ("library", [])})


def app():
    return {"src/P.xcodeproj/project.pbxproj": loader.simple_project("App"),
            "src/App.swift": "@main struct App { static func main() {} }\n"}


# What `nomac build` synthesizes off macOS to sign ad hoc, without the identity (LinuxSigning).
AD_HOC = ["AD_HOC_CODE_SIGNING_ALLOWED=YES", "PROVISIONING_PROFILE_REQUIRED=NO"]
APP = ["-project", "P.xcodeproj", "-scheme", "App"]
VARIANTS = {
    "package": (package, ["-scheme", "Kit"], []),
    "package-adhoc-allowed": (package, ["-scheme", "Kit"], AD_HOC),
    "package-adhoc": (package, ["-scheme", "Kit"], AD_HOC + ["CODE_SIGN_IDENTITY=-"]),
    "app-empty-identity": (app, APP, ["SWIFT_VERSION=5.0", "CODE_SIGN_IDENTITY="]),
    "app-empty-identity-adhoc-allowed": (app, APP, ["SWIFT_VERSION=5.0", "CODE_SIGN_IDENTITY="] + AD_HOC),
    "app-adhoc": (app, APP, ["SWIFT_VERSION=5.0", "CODE_SIGN_IDENTITY=-"] + AD_HOC),
}


def main():
    out = Path(sys.argv[1]).resolve()
    developer = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")
    environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"], "LANG": "en_US.UTF-8",
                   "DEVELOPER_DIR": developer, "TMPDIR": os.environ.get("TMPDIR", "/tmp/")}
    summary = {}
    for name, (files, container, settings) in VARIANTS.items():
        work = out / name
        shutil.rmtree(work, ignore_errors=True)
        for path, text in files().items():
            (work / path).parent.mkdir(parents=True, exist_ok=True)
            (work / path).write_text(text)
        derived = work / "dd"
        completed = subprocess.run(["xcodebuild", *container, "-destination", "generic/platform=iOS", "-configuration", "Debug",
                                    "-derivedDataPath", str(derived), *settings, "build"],
                                   cwd=work / "src", env=environment, capture_output=True, text=True)
        log = completed.stdout + completed.stderr
        (out / f"{name}.log").write_text(log)
        products = derived / "Build/Products"
        summary[name] = {
            "settings": settings,
            "exitStatus": completed.returncode,
            "codeSignTasks": sorted({line.split(" (in target")[0] for line in log.splitlines() if line.startswith("CodeSign ")}),
            "signedProducts": sorted(str(path.parent.relative_to(products)) for path in products.rglob("_CodeSignature")),
        }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
