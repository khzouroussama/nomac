#!/usr/bin/env python3
"""What ProcessXCFramework copies of an xcframework's AppleDouble (`._*`) files, for a self-written app.

Archives made on a Mac carry each file's extended attributes as a `._<name>` file next to it, and
an xcframework downloaded and unpacked elsewhere keeps them as plain files (swiftfin's
`libvlc.xcframework`). envelope_experiments.py's objectVersion-77 app links `Vendor.xcframework`,
a static library whose `Headers` hold:

- `Vendor.h` and `._Vendor.h`, an AppleDouble file with Finder info;
- `._Orphan.h`, an AppleDouble file without its file;
- `junk.h` and `._junk.h`, a file that is not AppleDouble;
- `sub/Sub.h` and `._sub`, an AppleDouble file for a directory.

Usage:
  xcframework_copy_experiments.py <out>                  on a Mac: xcodebuild (DEVELOPER_DIR)
  xcframework_copy_experiments.py <out> --nomac <nomac> [nomac build options...]

<out>/<tool>.log keeps the build's output; <out>/<tool>.json lists its exit status and the files
the build wrote to the products' `include`.
"""

import json
import os
import shutil
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import envelope_experiments as envelope  # noqa: E402

INFO = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>libVendor.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
"""


def apple_double():
    """An AppleDouble version 2 file with one entry, Finder info (ID 9) of type TEXT."""
    finder = b"TEXTttxt" + bytes(24)
    return struct.pack(">IIxxxxxxxxxxxxxxxxH", 0x00051607, 0x00020000, 1) + struct.pack(">III", 9, 38, len(finder)) + finder


SLICE = "Vendor.xcframework/ios-arm64"
TEXTS = {f"{SLICE}/Headers/Vendor.h": "int vendor(void);\n", f"{SLICE}/Headers/junk.h": "\n",
         f"{SLICE}/Headers/._junk.h": "not AppleDouble\n", f"{SLICE}/Headers/sub/Sub.h": "\n",
         f"{SLICE}/libVendor.a": "!<arch>\n", "Vendor.xcframework/Info.plist": INFO}
BINARIES = {f"{SLICE}/Headers/._Vendor.h", f"{SLICE}/Headers/._Orphan.h", f"{SLICE}/Headers/._sub"}


def project():
    def edit(p, files):
        reference = p.add("vendor/xcframework", "PBXFileReference", lastKnownFileType="wrapper.xcframework",
                          path="Vendor.xcframework", sourceTree="<group>")
        envelope.add_to_group(p, "group/frameworks", [reference])
        p.objects[p.ids("app/frameworks")]["files"].append(p.add("vendor/xcframework/build", "PBXBuildFile", fileRef=reference))
        files.update(TEXTS)
        sources = p.objects[p.ids("app/sources")]
        sources["files"] = [build for build in sources["files"] if build != p.ids("app/model/build")]
    return envelope.era_project(77, edit=edit)


def main():
    out = Path(sys.argv[1]).resolve()
    nomac = sys.argv[sys.argv.index("--nomac") + 1] if "--nomac" in sys.argv else None
    extra = sys.argv[sys.argv.index("--nomac") + 2:] if nomac else []
    tool = "nomac" if nomac else "xcode"
    source = out / f"src-{tool}"
    shutil.rmtree(source, ignore_errors=True)
    for path, text in project().items():
        (source / path).parent.mkdir(parents=True, exist_ok=True)
        (source / path).write_text(text)
    for path in BINARIES:
        (source / path).write_bytes(apple_double())
    derived = out / f"dd-{tool}"
    shutil.rmtree(derived, ignore_errors=True)
    command = ([nomac, "build"] if nomac else ["xcodebuild"]) + [
        "-project", "P.xcodeproj", "-scheme", "App", "-configuration", "Debug", "-destination", "generic/platform=iOS",
        "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "ASSETCATALOG_COMPILER_APPICON_NAME=", *extra, "build"]
    completed = subprocess.run(command, cwd=source, capture_output=True, text=True, env=os.environ)
    (out / f"{tool}.log").write_text(completed.stdout + completed.stderr)
    include = derived / "Build/Products/Debug-iphoneos/include"
    results = {
        "exitStatus": completed.returncode,
        "include": sorted(str(path.relative_to(include)) + ("/" if path.is_dir() else "") for path in include.rglob("*")) if include.exists() else None,
    }
    (out / f"{tool}.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
