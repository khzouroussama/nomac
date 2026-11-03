#!/usr/bin/env python3
"""The executable of a sticker pack, for a self-written project.

envelope_experiments.py's objectVersion-77 project with a sticker pack target added
(`com.apple.product-type.app-extension.messages-sticker-pack`, no sources, an empty resources
phase), built alone (`-target Stickers`) for `iphoneos` with code signing off. A sticker pack has
no code: Swift Build copies the platform's `Library/Application Support/MessagesApplicationExtensionStub`
in as its executable (CopyAndPreserveArchs), as wikipedia's `Wikipedia Stickers.appex`.

Usage:
  sticker_stub_experiments.py <out>                  on a Mac: xcodebuild (DEVELOPER_DIR)
  sticker_stub_experiments.py <out> --nomac <nomac> [nomac build options...]

<out>/<tool>.log keeps the build's output; <out>/<tool>.json lists its exit status, the appex's
files and the SHA-256 of its executable and of the developer directory's stub.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import envelope_experiments as envelope  # noqa: E402

STUB = "Platforms/iPhoneOS.platform/Library/Application Support/MessagesApplicationExtensionStub/MessagesApplicationExtensionStub"
INFO = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.message-payload-provider</string>
		<key>NSExtensionPrincipalClass</key>
		<string>StickerBrowserViewController</string>
	</dict>
</dict>
</plist>
"""


def project():
    def edit(p, files):
        product = p.add("stickers/product", "PBXFileReference", explicitFileType="wrapper.app-extension", includeInIndex=0,
                        path="Stickers.appex", sourceTree="BUILT_PRODUCTS_DIR")
        envelope.add_to_group(p, "group/products", [product])
        settings = {"INFOPLIST_FILE": "Stickers/Info.plist", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.App.Stickers",
                    "PRODUCT_NAME": "$(TARGET_NAME)", "SKIP_INSTALL": "YES", "TARGETED_DEVICE_FAMILY": "1,2"}
        entries = [p.add(f"stickers/list/{name}", "XCBuildConfiguration", buildSettings=settings, name=name) for name in ("Debug", "Release")]
        listing = p.add("stickers/list", "XCConfigurationList", buildConfigurations=entries, defaultConfigurationIsVisible=0,
                        defaultConfigurationName="Release")
        resources = p.add("stickers/resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[],
                          runOnlyForDeploymentPostprocessing=0)
        target = p.add("target/stickers", "PBXNativeTarget", buildConfigurationList=listing, buildPhases=[resources], buildRules=[],
                       dependencies=[], name="Stickers", productName="Stickers", productReference=product,
                       productType="com.apple.product-type.app-extension.messages-sticker-pack")
        p.objects[p.ids("project")]["targets"].append(target)
        files["Stickers/Info.plist"] = INFO
    return envelope.era_project(77, edit=edit)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def main():
    out = Path(sys.argv[1]).resolve()
    nomac = sys.argv[sys.argv.index("--nomac") + 1] if "--nomac" in sys.argv else None
    extra = sys.argv[sys.argv.index("--nomac") + 2:] if nomac else []
    developer = Path(extra[extra.index("--developer-dir") + 1] if "--developer-dir" in extra
                     else os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer"))
    tool = "nomac" if nomac else "xcode"
    source = out / f"src-{tool}"
    shutil.rmtree(source, ignore_errors=True)
    for path, text in project().items():
        (source / path).parent.mkdir(parents=True, exist_ok=True)
        (source / path).write_text(text)
    derived = out / f"build-{tool}"
    shutil.rmtree(derived, ignore_errors=True)
    command = ([nomac, "build"] if nomac else ["xcodebuild"]) + [
        "-project", "P.xcodeproj", "-target", "Stickers", "-configuration", "Debug", "-sdk", "iphoneos",
        f"SYMROOT={derived}", "CODE_SIGNING_ALLOWED=NO", *extra, "build"]
    completed = subprocess.run(command, cwd=source, capture_output=True, text=True, env=os.environ)
    (out / f"{tool}.log").write_text(completed.stdout + completed.stderr)
    appex = derived / "Debug-iphoneos/Stickers.appex"
    results = {
        "exitStatus": completed.returncode,
        "appex": sorted(str(path.relative_to(appex)) for path in appex.rglob("*")) if appex.exists() else None,
        "executable": sha256(appex / "Stickers"),
        "stub": sha256(developer / STUB),
    }
    (out / f"{tool}.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
