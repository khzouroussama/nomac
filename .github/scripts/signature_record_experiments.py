#!/usr/bin/env python3
"""The signature records `xcodebuild archive` writes for xcframeworks, and where they end up.

An archive build sets ENABLE_SIGNATURE_AGGREGATION=YES, and Swift Build then runs
`builtin-collectSignature` on each xcframework a target uses. envelope_experiments.py's
objectVersion-77 app links one self-written or third-party xcframework, in one of these ways:

- `direct-*`: a `PBXFileReference` in the app's Frameworks phase;
- `package-*`: a local package's `binaryTarget`, the package's product in the app's Frameworks phase;
- `build-*`: the same with `build` instead of `archive`, which has no signature aggregation;
- `collect-*`: `direct-adhoc` with a script phase that writes other files named `*.signature` in and
  around the products folder, for which of them the archive takes.

The xcframework is one of:

- `unsigned`: a static library, as `xcodebuild -create-xcframework` leaves it;
- `adhoc`: the same, after `codesign -s -`;
- `dynamic`: a dynamic framework after `codesign -s -`, embedded in the app;
- `identity`: the same as `adhoc` under a throwaway self-signed certificate from a keychain of its
  own, never on the search list (no Apple team in the signature);
- `vendor`: a public third-party release signed by its vendor's Apple Distribution certificate
  (`--vendor <xcframework>`, by default SentryObjC-Static 9.32.0);
- `tampered`: `adhoc` with a file added after signing; `modified`: with a signed file changed;
  `removed`: with a signed file removed;
- `digests`: `adhoc` with SHA-1 and SHA-256 code directories (`--digest-algorithm=sha1,sha256`,
  which codesign refuses for SHA-1 alone); `identity-digests`: `identity` with both;
- `partial`: `adhoc` without `_CodeSignature/CodeDirectory`; `norequirements`: without
  `CodeRequirements`; `nosignature`: without `CodeSignature`; `corrupt`: its `CodeDirectory` cut short;
  `badcms`: `identity` with its `CodeSignature` cut short;
- `fixture-unsigned`, `fixture-adhoc`: the empty static library `SignatureRecordTests` writes, whose
  records' digests that test holds;
- `expected-match`, `expected-other`, `expected-unsigned`: `vendor` or `unsigned`, with
  `expectedSignature` in the file reference, as Xcode records an accepted identity.

Usage:
  signature_record_experiments.py prepare <out> --vendor <xcframework>   on a Mac: <out>/xcf
  signature_record_experiments.py run <out> [case ...]                   on a Mac: xcodebuild (DEVELOPER_DIR)
  signature_record_experiments.py run <out> --nomac <nomac> [case ...] [--options ...]
  signature_record_experiments.py compare <out>                          each case: xcode.json with nomac.json

<out>/<case>/<tool>.json lists each run's exit statuses, its diagnostics about signatures, the
`.signature` files (paths relative to the derived data, the archive or the export, with digests),
the archive's and the export's top level and the IPA's entries outside the app. <tool>.log keeps the
output. xcodebuild runs without network access, the export with the `debugging` method only: an
app-store-connect export can call Apple's services once an account is in Xcode.
"""

import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import envelope_experiments as envelope  # noqa: E402

OFFLINE = ["sandbox-exec", "-p", '(version 1)(allow default)(deny network-outbound (remote ip))'
           '(deny network-outbound (remote unix-socket (path-literal "/private/var/run/mDNSResponder")))']

EXPORT_OPTIONS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>debugging</string>
	<key>signingCertificate</key>
	<string>-</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>teamID</key>
	<string>NOMAC00000</string>
</dict>
</plist>
"""

# Which `.signature` files the archive takes: in the products folder, below it and beside it.
COLLECT_SCRIPTS = {
    "collect": """cd "$BUILT_PRODUCTS_DIR"
mkdir -p sub Sub.signature Signatures ../Other-iphoneos
echo top > top.signature
echo below > sub/below.signature
echo folder > Sub.signature/inside.signature
echo signatures > Signatures/named.signature
echo other > ../Other-iphoneos/other.signature
echo beside > ../beside.signature
echo plain > plain.txt
ln -sf top.signature link.signature
mkdir -p ../../elsewhere
echo linked > ../../elsewhere/linked.signature
ln -sfn "$(cd ../../elsewhere && pwd)" linkdir
""",
    "collect-root": """cd "$BUILT_PRODUCTS_DIR"
mkdir -p ../Signatures
echo root > ../Signatures/root.signature
echo plain > ../Signatures/plain.txt
""",
    "collect-same": """cd "$BUILT_PRODUCTS_DIR"
mkdir -p sub
echo first > same.signature
echo second > sub/same.signature
""",
    "collect-support": """cd "$BUILT_PRODUCTS_DIR"
mkdir -p ../SwiftSupport
echo support > ../SwiftSupport/support.signature
""",
}

FIXTURE_INFO = """<?xml version="1.0" encoding="UTF-8"?>
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

# The differences this suite expects, docs/formats/code-signature.md "Signature records": off macOS
# nothing verifies a signature's seals (B-198), Packaging.log is not written (docs/formats/ipa.md).
NOT_VERIFIED = {"direct-tampered", "direct-modified", "direct-removed", "direct-norequirements"}
NOT_VERIFIED_WARNING = "was read but not verified"
# Both refuse, but nomac's build stops at its first failed task, SignatureCollection, which gives the
# reason where Xcode's says only `Error error 0` beside ProcessXCFramework's.
SAME_REASON = {"direct-corrupt", "direct-badcms"}

VENDOR_NAME = "SentryObjC-Static.xcframework"
VENDOR_TEAM = "97JCY7859U"

# Case: (how the app uses it, folder under <out>/xcf, the xcframework's name, expected signature).
CASES = {
    "direct-unsigned": ("direct", "unsigned", "Vendor.xcframework", None),
    "direct-adhoc": ("direct", "adhoc", "Vendor.xcframework", None),
    "direct-dynamic": ("embed", "dynamic", "VendorKit.xcframework", None),
    "direct-identity": ("direct", "identity", "Vendor.xcframework", None),
    "direct-vendor": ("direct", "vendor", VENDOR_NAME, None),
    "fixture-unsigned": ("direct", "fixture-unsigned", "Vendor.xcframework", None),
    "fixture-adhoc": ("direct", "fixture-adhoc", "Vendor.xcframework", None),
    "direct-tampered": ("direct", "tampered", "Vendor.xcframework", None),
    "direct-modified": ("direct", "modified", "Vendor.xcframework", None),
    "direct-removed": ("direct", "removed", "Vendor.xcframework", None),
    "direct-digests": ("direct", "digests", "Vendor.xcframework", None),
    "direct-identity-digests": ("direct", "identity-digests", "Vendor.xcframework", None),
    "direct-partial": ("direct", "partial", "Vendor.xcframework", None),
    "direct-norequirements": ("direct", "norequirements", "Vendor.xcframework", None),
    "direct-nosignature": ("direct", "nosignature", "Vendor.xcframework", None),
    "direct-corrupt": ("direct", "corrupt", "Vendor.xcframework", None),
    "direct-badcms": ("direct", "badcms", "Vendor.xcframework", None),
    "collect": ("collect", "adhoc", "Vendor.xcframework", None),
    "collect-root": ("collect-root", "adhoc", "Vendor.xcframework", None),
    "collect-same": ("collect-same", "adhoc", "Vendor.xcframework", None),
    "collect-support": ("collect-support", "adhoc", "Vendor.xcframework", None),
    "expected-match": ("direct", "vendor", VENDOR_NAME, f"AppleDeveloperProgram:{VENDOR_TEAM}:GetSentry LLC"),
    "expected-other": ("direct", "vendor", VENDOR_NAME, "AppleDeveloperProgram:NOMAC00000:Someone Else"),
    "expected-unsigned": ("direct", "unsigned", "Vendor.xcframework", f"AppleDeveloperProgram:{VENDOR_TEAM}:GetSentry LLC"),
    "package-unsigned": ("package", "unsigned", "Vendor.xcframework", None),
    "package-adhoc": ("package", "adhoc", "Vendor.xcframework", None),
    "package-vendor": ("package", "vendor", VENDOR_NAME, None),
    "build-direct-adhoc": ("direct", "adhoc", "Vendor.xcframework", None),
    "build-package-adhoc": ("package", "adhoc", "Vendor.xcframework", None),
    "build-expected-match": ("direct", "vendor", VENDOR_NAME, f"AppleDeveloperProgram:{VENDOR_TEAM}:GetSentry LLC"),
    "build-expected-other": ("direct", "vendor", VENDOR_NAME, "AppleDeveloperProgram:NOMAC00000:Someone Else"),
    "build-corrupt": ("direct", "corrupt", "Vendor.xcframework", None),
}


def xcrun(*arguments, directory=None):
    subprocess.run(["xcrun", *arguments], check=True, cwd=directory, capture_output=True)


def sign(xcframework, *options):
    subprocess.run(["codesign", "-s", *options, str(xcframework)], check=True, capture_output=True, timeout=120)


def self_signed(work):
    """A throwaway self-signed code signing identity in a keychain of its own. Returns (name, keychain)."""
    name = "Nomac Experiment Signing"
    key, certificate, bundle = work / "key.pem", work / "certificate.pem", work / "identity.p12"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key), "-out", str(certificate), "-days", "3650",
                    "-subj", f"/CN={name}", "-addext", "keyUsage=critical,digitalSignature", "-addext", "extendedKeyUsage=critical,codeSigning"],
                   check=True, capture_output=True)
    export = ["openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(certificate), "-out", str(bundle), "-passout", "pass:nomac"]
    if subprocess.run([*export, "-legacy"], capture_output=True).returncode != 0:
        subprocess.run(export, check=True, capture_output=True)
    keychain = work / "experiment.keychain-db"
    subprocess.run(["security", "create-keychain", "-p", "nomac", str(keychain)], check=True, capture_output=True)
    subprocess.run(["security", "unlock-keychain", "-p", "nomac", str(keychain)], check=True, capture_output=True)
    subprocess.run(["security", "import", str(bundle), "-k", str(keychain), "-P", "nomac", "-T", "/usr/bin/codesign"], check=True, capture_output=True)
    subprocess.run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", "nomac", str(keychain)], check=True, capture_output=True)
    return name, keychain


def prepare(out, vendor):
    """<out>/xcf/<kind>/<name>.xcframework: the xcframeworks each case copies."""
    xcf = out / "xcf"
    shutil.rmtree(xcf, ignore_errors=True)
    with tempfile.TemporaryDirectory(prefix="nomac-signature-") as work:
        work = Path(work)
        (work / "Headers").mkdir()
        (work / "Headers/Vendor.h").write_text("int vendor_answer(void);\n")
        (work / "vendor.c").write_text('#include "Headers/Vendor.h"\nint vendor_answer(void) { return 42; }\n')
        target = ["--sdk", "iphoneos", "clang", "-target", "arm64-apple-ios17.0"]
        xcrun(*target, "-c", "vendor.c", "-o", "vendor.o", directory=work)
        xcrun("--sdk", "iphoneos", "libtool", "-static", "-o", "libVendor.a", "vendor.o", directory=work)
        unsigned = xcf / "unsigned/Vendor.xcframework"
        unsigned.parent.mkdir(parents=True)
        subprocess.run(["xcodebuild", "-create-xcframework", "-library", str(work / "libVendor.a"), "-headers", str(work / "Headers"),
                        "-output", str(unsigned)], check=True, capture_output=True)

        framework = work / "VendorKit.framework"
        framework.mkdir()
        xcrun(*target, "-dynamiclib", "vendor.c", "-install_name", "@rpath/VendorKit.framework/VendorKit", "-o", str(framework / "VendorKit"),
              directory=work)
        with open(framework / "Info.plist", "wb") as plist:
            plistlib.dump({"CFBundleExecutable": "VendorKit", "CFBundleIdentifier": "org.nomac.vendorkit", "CFBundlePackageType": "FMWK",
                           "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "MinimumOSVersion": "17.0",
                           "CFBundleSupportedPlatforms": ["iPhoneOS"]}, plist)
        dynamic = xcf / "dynamic/VendorKit.xcframework"
        dynamic.parent.mkdir(parents=True)
        sign(framework, "-")
        subprocess.run(["xcodebuild", "-create-xcframework", "-framework", str(framework), "-output", str(dynamic)], check=True, capture_output=True)
        sign(dynamic, "-")

        kinds = ("adhoc", "tampered", "modified", "removed", "digests", "identity", "identity-digests", "partial", "norequirements", "nosignature", "corrupt", "badcms")
        copies = {kind: xcf / kind / "Vendor.xcframework" for kind in kinds}
        for copy in copies.values():
            copy.parent.mkdir()
            shutil.copytree(unsigned, copy, symlinks=True)
        for kind in ("adhoc", "tampered", "modified", "removed", "partial", "norequirements", "nosignature", "corrupt"):
            sign(copies[kind], "-")
        (copies["tampered"] / "added.txt").write_text("added after signing\n")
        with open(copies["modified"] / "ios-arm64/Headers/Vendor.h", "a") as header:
            header.write("// changed after signing\n")
        (copies["removed"] / "ios-arm64/Headers/Vendor.h").unlink()
        (copies["partial"] / "_CodeSignature/CodeDirectory").unlink()
        (copies["norequirements"] / "_CodeSignature/CodeRequirements").unlink()
        (copies["nosignature"] / "_CodeSignature/CodeSignature").unlink()
        directory = copies["corrupt"] / "_CodeSignature/CodeDirectory"
        directory.write_bytes(directory.read_bytes()[:20])
        sign(copies["digests"], "-", "--digest-algorithm=sha1,sha256")

        name, keychain = self_signed(work)
        try:
            sign(copies["identity"], name, "--keychain", str(keychain))
            sign(copies["identity-digests"], name, "--keychain", str(keychain), "--digest-algorithm=sha1,sha256")
            sign(copies["badcms"], name, "--keychain", str(keychain))
            cms = copies["badcms"] / "_CodeSignature/CodeSignature"
            cms.write_bytes(cms.read_bytes()[:100])
        finally:
            subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True)

    for kind in ("fixture-unsigned", "fixture-adhoc"):
        fixture = xcf / kind / "Vendor.xcframework"
        (fixture / "ios-arm64/Headers").mkdir(parents=True)
        (fixture / "Info.plist").write_text(FIXTURE_INFO)
        (fixture / "ios-arm64/libVendor.a").write_text("!<arch>\n")
        (fixture / "ios-arm64/Headers/Vendor.h").write_text("int vendor(void);\n")
    sign(xcf / "fixture-adhoc/Vendor.xcframework", "-")

    (xcf / "vendor").mkdir()
    subprocess.run(["ditto", "--noextattr", "--noqtn", str(vendor), str(xcf / "vendor" / vendor.name)], check=True)


def project(way, name, expected):
    """The envelope app using xcframework `name`, whose folder sits at the source root or in the local package."""
    def edit(p, files):
        sources = p.objects[p.ids("app/sources")]
        sources["files"] = [build for build in sources["files"] if build != p.ids("app/model/build")]
        if way == "package":
            package = p.add("package/local", "XCLocalSwiftPackageReference", relativePath="Local")
            p.objects[p.ids("project")]["packageReferences"] = [package]
            product = p.add("package/local/vendor", "XCSwiftPackageProductDependency", package=package, productName="VendorProduct")
            p.objects[p.ids("target/app")]["packageProductDependencies"] = [product]
            p.objects[p.ids("app/frameworks")]["files"].append(p.add("package/local/vendor/build", "PBXBuildFile", productRef=product))
            files["Local/Package.swift"] = ("// swift-tools-version: 5.9\nimport PackageDescription\n\nlet package = Package(\n"
                                            '    name: "Local",\n    platforms: [.iOS(.v17)],\n'
                                            '    products: [.library(name: "VendorProduct", targets: ["VendorBinary"])],\n'
                                            f'    targets: [.binaryTarget(name: "VendorBinary", path: "{name}")]\n)\n')
            return
        values = {"lastKnownFileType": "wrapper.xcframework", "path": name, "sourceTree": "<group>"}
        if expected:
            values["expectedSignature"] = expected
        reference = p.add("vendor/xcframework", "PBXFileReference", **values)
        envelope.add_to_group(p, "group/frameworks", [reference])
        p.objects[p.ids("app/frameworks")]["files"].append(p.add("vendor/xcframework/build", "PBXBuildFile", fileRef=reference))
        if way in COLLECT_SCRIPTS:
            script = p.add("vendor/script", "PBXShellScriptBuildPhase", buildActionMask=2147483647, files=[], inputPaths=[], outputPaths=[],
                           runOnlyForDeploymentPostprocessing=0, shellPath="/bin/sh", shellScript=COLLECT_SCRIPTS[way])
            p.objects[p.ids("target/app")]["buildPhases"].append(script)
        if way == "embed":
            embed = p.objects[p.ids("app/embed")]
            embed["files"].append(p.add("vendor/xcframework/embed", "PBXBuildFile", fileRef=reference,
                                        settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]}))
    return envelope.era_project(77, edit=edit)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signature_files(root):
    """{path relative to root: the digest and the property list}, with certificates as digests."""
    results = {}
    for path in sorted(root.rglob("*.signature")) if root.is_dir() else []:
        if path.is_dir():
            results[str(path.relative_to(root))] = "folder"
            continue
        try:
            record = plistlib.loads(path.read_bytes())
        except plistlib.InvalidFileException:
            results[str(path.relative_to(root))] = {"sha256": digest(path), "text": path.read_text()}
            continue
        if "certificates" in record:
            record["certificates"] = [hashlib.sha256(certificate).hexdigest() for certificate in record["certificates"]]
        if "cdhashes" in record:
            record["cdhashes"] = [cdhash.hex() for cdhash in record["cdhashes"]]
        results[str(path.relative_to(root))] = {"sha256": digest(path), "record": record}
    return results


def tree_top(root):
    return sorted(path.name for path in root.iterdir()) if root.is_dir() else None


def modes_and_times(archive, derived):
    """Each record's mode in the archive, and whether its time and mode are those of the build's file."""
    results = {}
    for path in sorted(archive.rglob("*.signature")) if archive.is_dir() else []:
        built = [candidate for candidate in derived.rglob(path.name) if candidate.is_file()]
        results[str(path.relative_to(archive))] = {"mode": oct(path.stat().st_mode & 0o7777), "builtMode": oct(built[0].stat().st_mode & 0o7777) if built else None,
                                                   "sameTime": bool(built) and int(built[0].stat().st_mtime) == int(path.stat().st_mtime)}
    return results


def ipa_entries(export):
    ipas = list(export.glob("*.ipa")) if export.is_dir() else []
    if not ipas:
        return None
    with zipfile.ZipFile(ipas[0]) as archive:
        names = archive.namelist()
    return {"topLevel": sorted({name.split("/")[0] for name in names}),
            "signatures": sorted(name for name in names if name.endswith(".signature") or "Signatures" in name)}


def diagnostics(text):
    keep = re.compile(r"signature|identity of|not recorded|compromised|xcframework", re.IGNORECASE)
    kinds = re.compile(r"(^|\W)(error|warning|note):")
    shown = {re.sub(r"/\S*/(\S+)", r"\1", line.strip()).removeprefix("xcodebuild: ").replace("could not", "couldn’t") for line in text.splitlines()
             if keep.search(line) and kinds.search(line) and "detected encoding" not in line}
    return sorted(shown)


def run_case(out, case, nomac, options):
    way, kind, name, expected = CASES[case]
    tool = "nomac" if nomac else "xcode"
    root = out / case
    source = root / f"src-{tool}"
    derived, archive, export = root / f"dd-{tool}", root / f"{tool}.xcarchive", root / f"export-{tool}"
    for path in (source, derived, archive, export):
        shutil.rmtree(path, ignore_errors=True)
    source.mkdir(parents=True)
    for path, text in project(way, name, expected).items():
        (source / path).parent.mkdir(parents=True, exist_ok=True)
        (source / path).write_text(text)
    destination = source / "Local" if way == "package" else source
    shutil.copytree(out / "xcf" / kind / name, destination / name, symlinks=True)
    settings = ["CODE_SIGN_IDENTITY=-", "AD_HOC_CODE_SIGNING_ALLOWED=YES", "PROVISIONING_PROFILE_REQUIRED=NO", "CODE_SIGN_STYLE=Manual",
                "CODE_SIGN_ENTITLEMENTS=", "ASSETCATALOG_COMPILER_APPICON_NAME="]
    plain_build = case.startswith("build-")
    common = ["-project", "P.xcodeproj", "-scheme", "App", "-configuration", "Release", "-destination", "generic/platform=iOS",
              "-derivedDataPath", str(derived), *([] if plain_build else ["-archivePath", str(archive)]), *settings]

    def execute(argv):
        if nomac:
            return subprocess.run(argv, cwd=source, capture_output=True, text=True)
        extra = ["-IDEPackageSupportDisableManifestSandbox=YES"] if way == "package" and "-exportArchive" not in argv else []
        return subprocess.run([*OFFLINE, *argv, *extra], cwd=source, capture_output=True, text=True)

    action = "build" if plain_build else "archive"
    built = execute([nomac, action, *common, *options] if nomac else ["xcodebuild", *common, action])
    plist = root / "export.plist"
    plist.write_text(EXPORT_OPTIONS)
    exported = None
    if built.returncode == 0 and not plain_build:
        exported = execute([nomac, "export", "-archivePath", str(archive), "-exportPath", str(export), "-exportOptionsPlist", str(plist)] if nomac
                           else ["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(export), "-exportOptionsPlist", str(plist)])
    log = built.stdout + built.stderr + (exported.stdout + exported.stderr if exported else "")
    (root / f"{tool}.log").write_text(log)
    results = {
        "archiveExit": built.returncode,
        "exportExit": exported.returncode if exported else None,
        "diagnostics": diagnostics(log),
        "derived": signature_files(derived),
        "archive": signature_files(archive),
        "archiveFiles": modes_and_times(archive, derived),
        "archiveTop": tree_top(archive),
        "exportTop": tree_top(export),
        "export": signature_files(export),
        "ipa": ipa_entries(export),
    }
    (root / f"{tool}.json").write_text(json.dumps(results, indent=1, sort_keys=True, default=str) + "\n")
    print(f"{case} {tool}: archive {results['archiveExit']} export {results['exportExit']} "
          f"signatures {len(results['derived'])}/{len(results['archive'])}/{len(results['export'])}")
    # What the suite needs is in the JSON; the build trees are large.
    shutil.rmtree(derived, ignore_errors=True)
    shutil.rmtree(source, ignore_errors=True)


def compare(out):
    """Each case's records and folders in xcode.json against nomac.json, but for NOT_VERIFIED's cases."""
    def shown(results):
        results = dict(results)
        results["exportTop"] = [name for name in results["exportTop"] or [] if name != "Packaging.log"]
        results["diagnostics"] = [line.replace(":1:1:", ":") for line in results["diagnostics"] if NOT_VERIFIED_WARNING not in line]
        return results

    different = 0
    for case in CASES:
        xcode_path, nomac_path = out / case / "xcode.json", out / case / "nomac.json"
        if not xcode_path.exists() or not nomac_path.exists():
            print(f"{case}: not run")
            continue
        xcode, nomac = shown(json.loads(xcode_path.read_text())), shown(json.loads(nomac_path.read_text()))
        differences = [key for key in ("archiveExit", "exportExit", "archive", "archiveFiles", "archiveTop", "exportTop", "export", "ipa", "diagnostics")
                       if xcode[key] != nomac[key]]
        if case in NOT_VERIFIED:
            print(f"{case}: {'Xcode refuses, nomac accepts with a warning (B-198)' if xcode['archiveExit'] and not nomac['archiveExit'] else 'UNEXPECTED'}")
            continue
        if case in SAME_REASON and differences == ["diagnostics"]:
            reason = next(line.split("note: ")[1] for line in xcode["diagnostics"] if "note: " in line)
            differences = [] if any(reason in line for line in nomac["diagnostics"]) else differences
        different += bool(differences)
        print(f"{case}: {'identical' if not differences else 'differs in ' + ', '.join(differences)}")
    sys.exit(1 if different else 0)


def main():
    command, out = sys.argv[1], Path(sys.argv[2]).resolve()
    arguments = sys.argv[3:]
    if command == "prepare":
        prepare(out, Path(arguments[arguments.index("--vendor") + 1]).resolve())
    elif command == "compare":
        compare(out)
    else:
        options = []
        if "--options" in arguments:
            index = arguments.index("--options")
            arguments, options = arguments[:index], arguments[index + 1:]
        nomac = None
        if "--nomac" in arguments:
            index = arguments.index("--nomac")
            nomac = arguments[index + 1]
            del arguments[index:index + 2]
        if not nomac:
            os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")
        for case in arguments or CASES:
            run_case(out, case, nomac, options)


if __name__ == "__main__":
    main()
