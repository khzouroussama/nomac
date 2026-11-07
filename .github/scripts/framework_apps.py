#!/usr/bin/env python3
"""Each cross-platform framework's fresh default app through nomac on Linux (docs/PROJECT-COMPATIBILITY.md).

For Flutter, Capacitor, Cordova, Kotlin Multiplatform, NativeScript and Tauri mobile: create the app
the way the framework's documentation says, generate what its tools can generate off macOS, then try
`nomac check`, `nomac archive` and `nomac export` with ad hoc signing and no change to the app.

Runs on the Linux build machine, or in a Linux container, with nomac (NOMAC_DEVELOPER_DIR names its
developer directory) and the framework's own tools on PATH. Every step's command, status, seconds and last error line go to
--output as JSON and its whole output to <work>/<framework>/logs. A step marked `refusal` shows what
the framework's own tool does off macOS, so its failure does not stop the framework's run. A
framework counts as reaching an IPA only when `nomac export` wrote one.

    framework_apps.py --work /work/fw --output /work/fw/results.json [--configuration Release] [framework ...]

--flutter-root names the Flutter SDK, whose `gen_snapshot_arm64` is only read to record its format. Run
one framework at a time on a loaded machine: each `nomac archive` is a whole build.
"""
import argparse
import hashlib
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import time

ADHOC = ["CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "AD_HOC_CODE_SIGNING_ALLOWED=YES",
         "PROVISIONING_PROFILE_REQUIRED=NO", "DEVELOPMENT_TEAM=", "PROVISIONING_PROFILE_SPECIFIER="]
EXPORT_OPTIONS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>method</key>
\t<string>debugging</string>
\t<key>signingCertificate</key>
\t<string>-</string>
\t<key>signingStyle</key>
\t<string>manual</string>
\t<key>teamID</key>
\t<string>NOMAC00000</string>
</dict>
</plist>
"""


class Run:
    def __init__(self, name, work, environment, configuration, timeout):
        self.name = name
        self.root = pathlib.Path(work) / name
        self.logs = self.root / "logs"
        self.environment = environment
        self.configuration = configuration
        self.timeout = timeout
        self.result = {"framework": name, "configuration": configuration, "steps": [], "ipa": None, "stopped_at": None}
        shutil.rmtree(self.root, ignore_errors=True)
        self.logs.mkdir(parents=True)

    def step(self, name, command, cwd=None, refusal=False):
        """Runs one step and returns whether it succeeded; a failed step that is not a refusal ends the run."""
        started = time.time()
        log = self.logs / f"{len(self.result['steps']):02}-{name}.log"
        with open(log, "w") as output:
            try:
                status = subprocess.run([str(word) for word in command], cwd=cwd or self.root, env=self.environment, stdout=output,
                                        stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, timeout=self.timeout).returncode
            except subprocess.TimeoutExpired:
                status = "timeout"
            except FileNotFoundError as error:
                output.write(str(error))
                status = "not found"
        ok = status == 0
        self.result["steps"].append({"step": name, "command": shlex.join(str(word) for word in command), "ok": ok, "status": status,
                                     "seconds": round(time.time() - started), "refusal": refusal,
                                     "last_error": None if ok else last_error(log)})
        print(f"{'PASS' if ok else 'REFUSED' if refusal else 'FAIL'} {self.name} {name}" + ("" if ok else f": {self.result['steps'][-1]['last_error']}"), flush=True)
        if not ok and not refusal:
            self.result["stopped_at"] = name
        return ok

    def native(self, container, scheme, cwd):
        """`nomac check`, `nomac archive` and `nomac export` of a project or workspace, ad hoc."""
        flag = "-workspace" if container.endswith(".xcworkspace") else "-project"
        self.step("check", ["nomac", "check", container], cwd=cwd, refusal=True)
        archive = self.root / f"{scheme}.xcarchive"
        if not self.step("archive", ["nomac", "archive", flag, container, "-scheme", scheme, "-configuration", self.configuration,
                                     "-destination", "generic/platform=iOS", "-archivePath", archive, "-derivedDataPath", self.root / "dd", *ADHOC], cwd=cwd):
            return False
        options = self.root / "ExportOptions.plist"
        options.write_text(EXPORT_OPTIONS)
        if not self.step("export", ["nomac", "export", "-archivePath", archive, "-exportPath", self.root / "export",
                                    "-exportOptionsPlist", options], cwd=cwd):
            return False
        ipas = sorted((self.root / "export").glob("*.ipa"))
        if ipas:
            self.result["ipa"] = {"name": ipas[0].name, "bytes": ipas[0].stat().st_size,
                                  "sha256": hashlib.sha256(ipas[0].read_bytes()).hexdigest()}
        return bool(ipas)


def last_error(log):
    lines = [line.strip() for line in log.read_text(errors="replace").splitlines() if line.strip()]
    errors = [line for line in lines if "error" in line.lower() or "exception" in line.lower() or "not supported" in line.lower()]
    return ((errors or lines or [""])[-1])[:300]


def executable_format(path):
    if not path.exists():
        return "missing"
    magic = path.read_bytes()[:4]
    if magic == b"\x7fELF":
        return "ELF"
    return "Mach-O" if magic in (b"\xca\xfe\xba\xbe", b"\xcf\xfa\xed\xfe") else magic.hex()


def flutter(run, arguments):
    app = run.root / "flutter_demo"
    offline = ["--offline"] if arguments.offline else []
    sdk = pathlib.Path(arguments.flutter_root)
    if not run.step("create", ["flutter", "create", *offline, "--org", "dev.nomac", "--platforms=ios", "flutter_demo"]):
        return
    run.step("build-ios-config-only", ["flutter", "build", "ios", "--config-only"], cwd=app, refusal=True)
    run.step("precache", ["flutter", "precache", "--ios"], cwd=app, refusal=True)
    if not (sdk / "bin/cache/artifacts/engine/ios-release/Flutter.xcframework").exists():
        run.step("precache-all-platforms", ["flutter", "precache", "--ios", "--all-platforms"], cwd=app, refusal=True)
    if not run.step("pub-get", ["flutter", "pub", "get", *offline], cwd=app):
        return
    run.result["gen_snapshot_format"] = executable_format(sdk / "bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64")
    run.native("Runner.xcworkspace", "Runner", app / "ios")


def capacitor(run, arguments):
    app = run.root / "capapp"
    if not run.step("create", ["npm", "init", "-y", "@capacitor/app@latest", "capapp", "--", "--name", "capapp", "--app-id", "dev.nomac.capapp"]):
        return
    if not run.step("npm-install", ["npm", "install"], cwd=app):
        return
    if not run.step("web-build", ["npm", "run", "build"], cwd=app):
        return
    if not run.step("install-ios", ["npm", "install", "@capacitor/ios"], cwd=app):
        return
    if not run.step("cap-add-ios", ["npx", "cap", "add", "ios"], cwd=app):
        return
    run.step("cap-sync-ios", ["npx", "cap", "sync", "ios"], cwd=app, refusal=True)
    run.native("App.xcodeproj", "App", app / "ios/App")


def cordova(run, arguments):
    app = run.root / "hello"
    if not run.step("create", ["npx", "--yes", "cordova", "create", "hello", "dev.nomac.hello", "HelloCordova"]):
        return
    if not run.step("platform-add-ios", ["npx", "--yes", "cordova", "platform", "add", "ios"], cwd=app):
        return
    run.step("prepare-ios", ["npx", "--yes", "cordova", "prepare", "ios"], cwd=app, refusal=True)
    run.step("build-ios", ["npx", "--yes", "cordova", "build", "ios"], cwd=app, refusal=True)
    run.native("App.xcworkspace", "App", app / "platforms/ios")


def kotlin(run, arguments):
    app = run.root / "kmp"
    if not run.step("create", ["git", "clone", "--depth", "1", "https://github.com/Kotlin/KMP-App-Template.git", "kmp"]):
        return
    run.step("framework", ["./gradlew", "--no-daemon", ":composeApp:linkDebugFrameworkIosArm64"], cwd=app, refusal=True)
    run.native("iosApp.xcodeproj", "iosApp", app / "iosApp")


def nativescript(run, arguments):
    app = run.root / "nsapp"
    if not run.step("create", ["npx", "--yes", "nativescript", "create", "nsapp", "--template", "@nativescript/template-hello-world-ts", "--appid", "dev.nomac.nsapp"]):
        return
    if not run.step("prepare-ios", ["npx", "--yes", "nativescript", "prepare", "ios"], cwd=app, refusal=True):
        return
    run.native("platforms/ios/nsapp.xcworkspace", "nsapp", app)


def tauri(run, arguments):
    app = run.root / "tauriapp"
    if not run.step("create", ["npx", "--yes", "create-tauri-app@latest", "tauriapp", "--template", "vanilla", "--manager", "npm", "--identifier", "dev.nomac.tauriapp", "--yes"]):
        return
    if not run.step("npm-install", ["npm", "install"], cwd=app):
        return
    if not run.step("ios-init", ["npx", "tauri", "ios", "init"], cwd=app, refusal=True):
        return
    run.native("src-tauri/gen/apple/tauriapp.xcodeproj", "tauriapp_iOS", app)


FRAMEWORKS = {"flutter": flutter, "capacitor": capacitor, "cordova": cordova, "kotlin": kotlin, "nativescript": nativescript, "tauri": tauri}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("frameworks", nargs="*", choices=[[], *FRAMEWORKS], default=[])
    parser.add_argument("--work", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--flutter-root", default=os.environ.get("FLUTTER_ROOT", ""))
    parser.add_argument("--offline", action="store_true", help="pub without the network, from PUB_CACHE")
    parser.add_argument("--timeout", type=int, default=3600)
    arguments = parser.parse_args()
    results = []
    for name in arguments.frameworks or FRAMEWORKS:
        run = Run(name, arguments.work, dict(os.environ), arguments.configuration, arguments.timeout)
        FRAMEWORKS[name](run, arguments)
        shutil.rmtree(run.root / "dd", ignore_errors=True)
        results.append(run.result)
        print(f"{name}: " + (f"IPA {run.result['ipa']['name']}, {run.result['ipa']['bytes']} bytes" if run.result["ipa"] else "no IPA"), flush=True)
    pathlib.Path(arguments.output).write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
