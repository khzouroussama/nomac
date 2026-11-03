#!/usr/bin/env python3
"""Writes NOTICE, the list of open-source components nomac's tree and its release downloads contain
or depend on, from Package.resolved, the vendored directories' UPSTREAM.md files, the patch
directories in .github and the revisions the build scripts pin. Fails when a component has no
entry here, or a vendored file lost its copyright header.

Usage: third_party_notices.py [--check] [repository]   (default: the repository holding this script)
  --check  compare with the committed NOTICE instead of writing it
"""
import json
import pathlib
import re
import sys

SWIFT = "Apache-2.0 WITH Swift-exception (Apache License 2.0 with Runtime Library Exception)"
APACHE = "Apache-2.0"
LLVM = "Apache-2.0 WITH LLVM-exception (Apache License 2.0 with LLVM Exceptions)"
APSL = "APSL-2.0 (Apple Public Source License 2.0)"

PACKAGES = {
    "aexml": ("AEXML", "MIT"),
    "pathkit": ("PathKit", "BSD-2-Clause"),
    "spectre": ("Spectre", "BSD-2-Clause"),
    "swift-argument-parser": ("Swift Argument Parser", SWIFT),
    "swift-asn1": ("SwiftASN1", APACHE),
    "swift-atomics": ("Swift Atomics", SWIFT),
    "swift-build": ("Swift Build, through the fork carrying the patches in .github/upstream/swift-build", SWIFT),
    "swift-certificates": ("Swift Certificates", APACHE),
    "swift-collections": ("Swift Collections", SWIFT),
    "swift-crypto": ("Swift Crypto, which contains BoringSSL (ISC and OpenSSL licenses)", APACHE),
    "swift-driver": ("Swift Driver, through the fork carrying the patch in .github/upstream/swift-driver", SWIFT),
    "swift-llbuild": ("llbuild", SWIFT),
    "swift-nio": ("SwiftNIO", APACHE),
    "swift-nio-ssl": ("SwiftNIO SSL, which contains BoringSSL (ISC and OpenSSL licenses)", APACHE),
    "swift-package-manager": ("Swift Package Manager", SWIFT),
    "swift-system": ("Swift System", SWIFT),
    "swift-toolchain-sqlite": ("SQLite as the Swift toolchain packages it (SQLite itself is in the public domain)", SWIFT),
    "swift-tools-protocols": ("Swift Tools Protocols", SWIFT),
    "swift-tools-support-core": ("Swift Tools Support Core", SWIFT),
    "xcode-project-format": ("Xcode project format", APACHE),
    "xcodeproj": ("XcodeProj", "MIT"),
}

# Directories of this repository holding copies or ports of open-source code. `copied` names the
# files that came from upstream when UPSTREAM.md's table does not list them.
VENDORED = [
    ("Sources/NomacLZFSE", "Encoder of the reference LZFSE implementation, ported to Swift",
     "https://github.com/lzfse/lzfse", "e634ca58b4821d9f3d560cdc6df5dec02ffc93fd", "BSD-3-Clause", "LICENSE.txt", None),
    ("Sources/NomacPluginAPI/PluginAPI/PackagePlugin", "SwiftPM's PackagePlugin runtime",
     "https://github.com/swiftlang/swift-package-manager", "8054c59f07a9c8cc8e67b3ec57870710c7154854", SWIFT, "LICENSE.txt", "*"),
    ("Sources/VendoredPackagePIFBuilder", "SwiftPM's package PIF builder",
     "https://github.com/swiftlang/swift-package-manager", "f0065c5a061542acce0f3aa6394cc77c726c6577", SWIFT, "LICENSE.txt", None),
    ("Sources/NomacMacros/Plugins/FoundationMacros", "swift-foundation's macros",
     "https://github.com/swiftlang/swift-foundation", "3b9d8f42b7923a7c1ae9ce20f3b05d1facac334e", APACHE, "LICENSE.md", None),
    ("Sources/NomacMacros/Plugins/TipKitMacros", "swift-foundation's predicate macro",
     "https://github.com/swiftlang/swift-foundation", "60bd7a1d8a730ebdeab2cb037b0519ef3b010ed3", APACHE, "LICENSE.md", ["PredicateMacro.swift"]),
]

# Patch directories: (directory, upstream, license, script and variable pinning the revision).
PATCHES = [
    (".github/lld", "lld of swiftlang/llvm-project", "https://github.com/swiftlang/llvm-project", LLVM, ("build-llvm-tools.sh", "LLVM_TAG")),
    (".github/clang", "clang of swiftlang/llvm-project", "https://github.com/swiftlang/llvm-project", LLVM, ("build-llvm-tools.sh", "LLVM_TAG")),
    (".github/swift", "the Swift compiler (swiftlang/swift)", "https://github.com/swiftlang/swift", SWIFT, ("build-swift-frontend.sh", "SWIFT_TAG")),
    (".github/cctools", "Apple's cctools and ld64 as cctools-port ports them to Linux", "https://github.com/tpoechtrager/cctools-port", APSL, ("build-cctools.sh", "CCTOOLS_COMMIT")),
    (".github/upstream/swift-build", "Swift Build", "https://github.com/swiftlang/swift-build", SWIFT, None),
    (".github/upstream/swift-driver", "Swift Driver", "https://github.com/swiftlang/swift-driver", SWIFT, None),
    (".github/upstream/swift-llbuild", "llbuild (not applied, BACKLOG B-137)", "https://github.com/swiftlang/swift-llbuild", SWIFT, None),
    (".github/upstream/swift-package-manager", "Swift Package Manager", "https://github.com/swiftlang/swift-package-manager", SWIFT, None),
]

HEADER = """nomac
Copyright the nomac contributors. Licensed under the Apache License 2.0 (LICENSE).

nomac is not affiliated with Apple. Xcode, iOS and TestFlight are trademarks of Apple Inc. This
repository contains no Apple software: no binaries, SDK files, .xip contents or files Xcode wrote.
Everything below is open-source code published by its authors under the license named.

This file is generated by .github/scripts/third_party_notices.py; do not edit it by hand.
"""


def pinned(repo, script, variable):
    text = (repo / ".github/scripts" / script).read_text()
    match = re.search(r"\$\{" + variable + r":-([^}]+)\}", text)
    if not match:
        sys.exit(f"error: no default for {variable} in {script}")
    return match.group(1)


def copied_files(directory, copied):
    if copied == "*":
        return sorted(p.name for p in directory.glob("*.swift"))
    if copied:
        return copied
    rows = re.findall(r"^\| `([^`]+\.swift)` \|", (directory / "UPSTREAM.md").read_text(), re.MULTILINE)
    if not rows:
        sys.exit(f"error: {directory}/UPSTREAM.md lists no copied file")
    return rows


def notices(repo):
    errors = []
    lines = [HEADER, "", "## Swift packages nomac depends on", "",
             "SwiftPM downloads them when nomac is built (Package.resolved); they are linked into the nomac executable.", ""]
    pins = json.loads((repo / "Package.resolved").read_text())["pins"]
    for pin in sorted(pins, key=lambda p: p["identity"]):
        entry = PACKAGES.get(pin["identity"])
        if not entry:
            errors.append(f"Package.resolved pins {pin['identity']}, which has no entry in PACKAGES")
            continue
        state = pin["state"]
        version = state.get("version") or state.get("branch")
        revision = state["revision"][:12] + (f" ({version})" if version else "")
        lines.append(f"- {entry[0]}: {pin['location']} at {revision}. License: {entry[1]}.")
    for identity in sorted(set(PACKAGES) - {p["identity"] for p in pins}):
        errors.append(f"PACKAGES lists {identity}, which Package.resolved does not pin")

    lines += ["", "The nomac executable of a release download also links, statically, the Swift standard library, Foundation and",
              f"libdispatch of the swift.org Swift 6.4.1 toolchain (https://github.com/swiftlang). License: {SWIFT}."]
    lines += ["", "## Open-source code copied into this repository", "",
              "Each directory keeps the upstream license file and an UPSTREAM.md naming the files copied and every change; each copied file keeps its original header.", ""]
    for path, what, url, revision, license, license_file, copied in VENDORED:
        directory = repo / path
        upstream = directory / "UPSTREAM.md"
        if not upstream.exists() or not (directory / license_file).exists():
            errors.append(f"{path} lacks UPSTREAM.md or {license_file}")
            continue
        if revision not in upstream.read_text():
            errors.append(f"{path}/UPSTREAM.md does not name revision {revision}")
        for name in copied_files(directory, copied):
            head = "\n".join((directory / name).read_text().splitlines()[:15]) if (directory / name).exists() else ""
            if "Copyright" not in head:
                errors.append(f"{path}/{name} has no copyright header")
        lines.append(f"- `{path}`: {what}, {url} at {revision[:12]}. License: {license} (`{path}/{license_file}`).")

    patched = ("Each patch changes the upstream project named and is licensed under that project's license. The release downloads "
               "(docs/RELEASES.md) are these projects built for Linux with these patches, with the license texts beside the binaries.")
    lines += ["", "## Patches to open-source projects", "", patched, ""]
    for path, what, url, license, pin in PATCHES:
        count = len(list((repo / path).glob("*.patch")))
        if not count:
            errors.append(f"{path} has no patch")
            continue
        at = f" at {pinned(repo, *pin)}" if pin else ""
        noun = "patch" if count == 1 else "patches"
        lines.append(f"- `{path}` ({count} {noun}): {what}, {url}{at}. License: {license}.")
    return "\n".join(lines) + "\n", errors


def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    repo = pathlib.Path(args[0] if args else pathlib.Path(__file__).resolve().parents[2]).resolve()
    text, errors = notices(repo)
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if errors:
        sys.exit(1)
    target = repo / "NOTICE"
    if "--check" in sys.argv:
        if not target.exists() or target.read_text() != text:
            sys.exit("error: NOTICE is not the one third_party_notices.py writes; run it and commit NOTICE")
        print("NOTICE is up to date")
    else:
        target.write_text(text)
        print(f"wrote {target}")


main()
