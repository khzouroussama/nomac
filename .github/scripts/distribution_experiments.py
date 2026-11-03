#!/usr/bin/env python3
"""Observe Xcode 27.0's App Store distribution offline, for `nomac export` and `nomac upload`.

Runs on a macOS machine with Xcode 27.0 (docs/VERIFICATION.md "Without CI"). xcodebuild runs
offline (signing_experiments.OFFLINE): with an Apple account in Xcode, app-store-connect exports
ask Apple's developer services about the team. The archive is signing_experiments.py's `adhoc`
app (an app, a framework and a share extension, bundle IDs `org.nomac.signing` and
`org.nomac.signing.Share`), archived ad hoc. Every identity and profile is made here, in a
throwaway keychain on the search list only while xcodebuild runs; installed profiles are removed
afterwards.

- app-store-self-signed: an app-store-connect export signed by a self-signed identity named
  `Apple Distribution: …` (Apple's iOS distribution extension 1.2.840.113635.100.6.1.4) with an
  App Store profile for each bundle signed by that identity.
- development-self-signed: the same as a debugging export, with `Apple Development: …`
  (1.2.840.113635.100.6.1.2) and development profiles.
- app-store-information: the ad hoc app-store-connect export with `generateAppStoreInformation`.
- export-options: app-store-connect exports with each documented option away from its default
  and an unknown one, and an archive built with STRIP_INSTALLED_PRODUCT=NO exported with and
  without stripSwiftSymbols (app-store-connect, release-testing); `signing_experiments.py
  compare-export <output> <nomac>` compares them with nomac's.
- option-archives: the odr app exported for app-store-connect with an asset pack base URL, and
  provisioningProfiles given to ad hoc exports.
- thinning: debugging exports thinned for all variants, of the adhoc app and of a copy with a
  self-written asset catalog (THINNING_IMAGES), of that copy declaring iOS 12.0 or 18.5 and of one
  with catalogs in its extension and framework too, of two with a 2.3 or 3 MB resource, twice each;
  signing_experiments' watch, App Clip and on-demand resources apps; and the copy thinned for one
  iPhone and one iPad.
- car-thinning: CAR_CATALOGS compiled by actool and thinned by assetutil for each trait set of
  the iOS 18.0 descriptors (`compare-car <output> <nomac>` runs `nomac assetutil` on them).
- option-grid: each documented option alone, away from its default, for each method.
- missing-profile: each method with an identity of its kind and `provisioningProfiles` naming
  profiles that are not installed, by UUID and by name.
- apple-profile (only with `--apple-profile <.mobileprovision> --identity <PEM>`, an
  Apple-issued development profile and its identity): debugging exports with the profile as
  issued, re-signed by a self-signed certificate, signed by a self-made chain with Apple's
  names, with one character of its content changed, and as issued with an identity it does not
  list (apple_profile_variants); the issued, re-signed and other-certificate profiles also for
  a build with manual signing. The outputs hold the profile's team and are written under the
  output folder only; nothing of them is committed.

Usage:
  distribution_experiments.py <output> [case ...] [--apple-profile P --identity I]
  distribution_experiments.py report <output>
  distribution_experiments.py compare <output> <nomac>
  distribution_experiments.py compare-car <output> <nomac>
  distribution_experiments.py compare-thinning <output> <nomac>
"""

import argparse
import datetime
import hashlib
import html
import json
import os
import plistlib
import re
import shutil
import subprocess
import struct
import sys
import tempfile
import uuid
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import signing_experiments as se  # noqa: E402

TEAM = "NOMAC00000"
BUNDLES = ["org.nomac.signing", "org.nomac.signing.Share"]
PROFILE_FOLDER = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
DEVELOPER_DIR = "/Applications/Xcode_27.app/Contents/Developer"
KINDS = {
    "distribution": ("Apple Distribution", "1.2.840.113635.100.6.1.4", "app-store-connect"),
    "development": ("Apple Development", "1.2.840.113635.100.6.1.2", "debugging"),
}


def make_identity(folder, kind):
    """A self-signed RSA identity named as Apple names its certificates, written as the
    `identity.pem` (key, then certificate) signing_experiments.case_keychain reads."""
    name, marker, _ = KINDS[kind]
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "leaf.cnf").write_text(
        "[req]\ndistinguished_name=dn\nprompt=no\n"
        f"[dn]\nUID={TEAM}\nCN={name}: nomac Test ({TEAM})\nOU={TEAM}\nO=nomac Test\nC=US\n"
        "[ext]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n"
        f"extendedKeyUsage=critical,codeSigning\n{marker}=critical,DER:0500\n")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(folder / "key.pem"),
                    "-out", str(folder / "cert.pem"), "-days", "365", "-config", str(folder / "leaf.cnf"), "-extensions", "ext"],
                   check=True, capture_output=True)
    (folder / "identity.pem").write_text((folder / "key.pem").read_text() + (folder / "cert.pem").read_text())


def sign_profile(content, folder, name):
    """`content` (a property list) as a profile: CMS SignedData signed by the folder's identity."""
    plist = folder / f"{name}.plist"
    plist.write_bytes(content)
    target = folder / f"{name}.mobileprovision"
    subprocess.run(["openssl", "cms", "-sign", "-binary", "-nodetach", "-outform", "DER", "-signer", str(folder / "cert.pem"),
                    "-inkey", str(folder / "key.pem"), "-in", str(plist), "-out", str(target)], check=True)
    return target


def make_profiles(folder, kind):
    """One profile per bundle for the folder's identity: App Store (`beta-reports-active`, no
    devices) or development (`get-task-allow`, one device). Returns {bundle ID: UUID}."""
    certificate = subprocess.run(["openssl", "x509", "-in", str(folder / "cert.pem"), "-outform", "DER"],
                                 capture_output=True, check=True).stdout
    created = datetime.datetime(2026, 11, 3)
    uuids = {}
    for bundle in BUNDLES:
        entitlements = {"application-identifier": f"{TEAM}.{bundle}", "com.apple.developer.team-identifier": TEAM,
                        "keychain-access-groups": [f"{TEAM}.*"]}
        profile = {"AppIDName": bundle, "ApplicationIdentifierPrefix": [TEAM], "CreationDate": created, "Platform": ["iOS"],
                   "IsXcodeManaged": False, "DeveloperCertificates": [certificate], "Entitlements": entitlements,
                   "ExpirationDate": created + datetime.timedelta(days=365), "Name": f"nomac {kind} {bundle}",
                   "TeamIdentifier": [TEAM], "TeamName": "nomac Test", "TimeToLive": 365,
                   "UUID": str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{kind}.{bundle}")).upper(), "Version": 1}
        if kind == "distribution":
            entitlements.update({"beta-reports-active": True, "get-task-allow": False})
        else:
            entitlements["get-task-allow"] = True
            profile["ProvisionedDevices"] = ["00008110-000000000000001E"]
        sign_profile(plistlib.dumps(profile), folder, bundle)
        uuids[bundle] = profile["UUID"]
    return uuids


def profile_content(path):
    return subprocess.run(["openssl", "cms", "-verify", "-noverify", "-nosigs", "-inform", "DER", "-in", str(path)],
                          capture_output=True, check=True).stdout


def options(method, team, profiles=None, certificate="-", extra=None):
    entries = {"method": method, "signingStyle": "manual", "signingCertificate": certificate, "teamID": team}
    if profiles:
        entries["provisioningProfiles"] = profiles
    entries.update(extra or {})
    return plistlib.dumps(entries)


def export(case, archive, options_data, identity_folder=None):
    """xcodebuild -exportArchive, offline, with the folder's identity in a throwaway keychain and
    its profiles installed in Xcode's profile folder while it runs. Records status and output."""
    case.mkdir(parents=True, exist_ok=True)
    (case / "options.plist").write_bytes(options_data)
    xcodebuild(case, ["-exportArchive", "-archivePath", str(archive), "-exportPath", str(case / "export"),
                      "-exportOptionsPlist", str(case / "options.plist")], identity_folder)


def xcodebuild(case, arguments, identity_folder, directory=None):
    installed = []
    try:
        for profile in sorted(identity_folder.glob("*.mobileprovision")) if identity_folder else []:
            target = PROFILE_FOLDER / f"{plistlib.loads(profile_content(profile))['UUID']}.mobileprovision"
            if target.exists():
                sys.exit(f"{target} is installed already; not replacing it")
            PROFILE_FOLDER.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(profile, target)
            installed.append(target)
        with se.case_keychain(identity_folder):
            result = subprocess.run([*se.OFFLINE, "xcodebuild", *arguments], capture_output=True, text=True, cwd=directory,
                                    env=dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR))
    finally:
        for target in installed:
            target.unlink()
    (case / "xcodebuild.log").write_text(result.stdout + result.stderr)
    errors = [line for line in (result.stdout + result.stderr).splitlines() if line.startswith("error: ")]
    (case / "result.json").write_text(json.dumps({"status": result.returncode, "errors": errors}, indent=1) + "\n")


def adhoc_archive(output, name="adhoc"):
    """One of signing_experiments' apps (`adhoc` by default), archived ad hoc (no exports)."""
    experiment = output / name
    archive = experiment / "adhoc.xcarchive"
    if not archive.is_dir():
        files, _ = se.EXPERIMENTS[name]
        source = experiment / "source"
        for path, text in files().items():
            (source / path).parent.mkdir(parents=True, exist_ok=True)
            (source / path).write_text(text)
        se.observe_adhoc(source, experiment, methods=())
    return archive


def self_signed(output, archive, kind):
    case = output / f"{'app-store' if kind == 'distribution' else 'development'}-self-signed"
    shutil.rmtree(case, ignore_errors=True)
    identity = case / "identity"
    make_identity(identity, kind)
    name, _, method = KINDS[kind]
    export(case, archive, options(method, TEAM, make_profiles(identity, kind), name), identity)


def app_store_information(output, archive):
    case = output / "app-store-information"
    shutil.rmtree(case, ignore_errors=True)
    export(case, archive, options("app-store-connect", TEAM, extra={"generateAppStoreInformation": True}))


APPLE_NAMES = {
    "root": "/C=US/O=Apple Inc./OU=Apple Certification Authority/CN=Apple Root CA",
    "intermediate": "/C=US/O=Apple Inc./OU=Certification Authority/CN=Apple iPhone Certification Authority",
    "leaf": "/C=US/O=Apple Inc./CN=Apple iPhone OS Provisioning Profile Signing",
}


def fake_apple_chain(folder):
    """Self-made certificates with the names of the chain that signs Apple's profiles (root,
    intermediate, signer); returns the signer's certificate, key and the other two."""
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "ca.cnf").write_text("[ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n"
                                   "[leaf]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n")
    issuer = None
    for name in ("root", "intermediate", "leaf"):
        key, certificate = folder / f"{name}.key", folder / f"{name}.pem"
        request = ["openssl", "req", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key), "-subj", APPLE_NAMES[name]]
        extensions = ["-extfile", str(folder / "ca.cnf"), "-extensions", "leaf" if name == "leaf" else "ca"]
        if issuer is None:
            subprocess.run([*request, "-x509", "-days", "30", "-out", str(certificate), "-config", "/dev/null",
                            "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign"],
                           check=True, capture_output=True)
        else:
            csr = folder / f"{name}.csr"
            subprocess.run([*request, "-out", str(csr)], check=True, capture_output=True)
            subprocess.run(["openssl", "x509", "-req", "-in", str(csr), "-CA", str(issuer[1]), "-CAkey", str(issuer[0]),
                            "-CAcreateserial", "-days", "30", "-out", str(certificate), *extensions], check=True, capture_output=True)
        issuer = (key, certificate)
    (folder / "chain.pem").write_text((folder / "intermediate.pem").read_text() + (folder / "root.pem").read_text())
    return folder / "leaf.pem", folder / "leaf.key", folder / "chain.pem"


def apple_profile_variants(output, archive, apple_profile, identity_pem):
    """Debugging exports with an Apple-issued profile: as issued; its content (same bytes)
    signed by a self-signed certificate; signed by a self-made chain with Apple's names (SHA-1,
    as Apple signs); the issued file with one character of its `Name` changed (the signature no
    longer matches); and as issued with a self-signed `Apple Development` identity the profile
    does not list."""
    content = profile_content(apple_profile)
    profile = plistlib.loads(content)
    profiles = {bundle: profile["UUID"] for bundle in BUNDLES}
    for label in ("issued", "resigned", "fake-apple-chain", "tampered", "other-certificate"):
        case = output / f"apple-profile/{label}"
        shutil.rmtree(case, ignore_errors=True)
        identity = case / "identity"
        identity.mkdir(parents=True)
        if label == "other-certificate":
            make_identity(identity, "development")
            for name in ("leaf.cnf", "key.pem", "cert.pem"):
                (identity / name).unlink()
        else:
            shutil.copyfile(identity_pem, identity / "identity.pem")
        target = identity / "profile.mobileprovision"
        signed = ["openssl", "cms", "-sign", "-binary", "-nodetach", "-outform", "DER", "-in", str(case / "content.plist"), "-out", str(target)]
        if label in ("issued", "other-certificate"):
            shutil.copyfile(apple_profile, target)
        elif label == "tampered":
            data = apple_profile.read_bytes()
            name = f"<string>{profile['Name']}</string>".encode()
            assert data.count(name) == 1
            changed = name[:-10] + (b"X" if name[-10:-9] != b"X" else b"Y") + name[-9:]
            target.write_bytes(data.replace(name, changed))
        else:
            (case / "content.plist").write_bytes(content)
            if label == "resigned":
                subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(case / "signer.key"),
                                "-out", str(case / "signer.pem"), "-days", "30", "-subj", "/CN=nomac profile signer"],
                               check=True, capture_output=True)
                subprocess.run([*signed, "-signer", str(case / "signer.pem"), "-inkey", str(case / "signer.key")], check=True)
            else:
                leaf, key, chain = fake_apple_chain(case / "chain")
                subprocess.run([*signed, "-md", "sha1", "-signer", str(leaf), "-inkey", str(key), "-certfile", str(chain)], check=True)
            (case / "content.plist").unlink()
        certificate = "Apple Development"
        if label == "other-certificate":
            # By its SHA-1, so that no other Apple Development identity of the keychains is taken.
            der = subprocess.run(["openssl", "x509", "-outform", "DER"], input=(identity / "identity.pem").read_bytes(),
                                 capture_output=True, check=True).stdout
            certificate = hashlib.sha1(der).hexdigest().upper()
        export(case, archive, options("debugging", profile["TeamIdentifier"][0], profiles, certificate), identity)
        if label in ("issued", "resigned", "other-certificate"):
            # The same profile for a build with manual signing (every target; the framework
            # takes none).
            build = case / "build"
            build.mkdir()
            xcodebuild(build, ["-project", "Signing.xcodeproj", "-scheme", "App", "-destination", "generic/platform=iOS",
                               "-derivedDataPath", str(build / "dd"), "build", "CODE_SIGN_STYLE=Manual",
                               f"CODE_SIGN_IDENTITY={certificate}", f"PROVISIONING_PROFILE_SPECIFIER={profile['UUID']}",
                               f"DEVELOPMENT_TEAM={profile['TeamIdentifier'][0]}"], identity, archive.parent / "source")
            shutil.rmtree(build / "dd", ignore_errors=True)


def missing_profile(output, archive):
    """Each method with an identity of its kind and profiles that are not installed, one named by
    UUID and one by name."""
    for method, kind in (("app-store-connect", "distribution"), ("release-testing", "distribution"),
                         ("enterprise", "distribution"), ("debugging", "development")):
        case = output / f"missing-profile/{method}"
        shutil.rmtree(case, ignore_errors=True)
        identity = case / "identity"
        make_identity(identity, kind)
        profiles = {BUNDLES[0]: "00000000-0000-4000-8000-000000000001", BUNDLES[1]: "nomac Missing Profile"}
        export(case, archive, options(method, TEAM, profiles, KINDS[kind][0]), identity)


def report(output):
    for result in sorted(output.glob("**/result.json")):
        data = json.loads(result.read_text())
        print(f"{result.parent.relative_to(output)}: status {data['status']}")
        for line in sorted(set(data["errors"])):
            print(f"  {line}")


def flag(key, value):
    """An export option as signing_experiments.export's `extra` takes it."""
    text = f"<{'true' if value else 'false'}/>" if isinstance(value, bool) else f"<string>{html.escape(value)}</string>"
    return f"\t<key>{key}</key>\n\t{text}\n"


def export_options(output, archive):
    """app-store-connect exports of the adhoc archive with each option xcodebuild documents for
    them (`xcodebuild -help`) set away from its default, and an option it does not know; then an
    archive built with STRIP_INSTALLED_PRODUCT=NO (Swift symbols left in) exported with and
    without stripSwiftSymbols, for app-store-connect and release-testing. Compared with
    `signing_experiments.py compare-export`."""
    experiment = archive.parent
    for label, extra in (("asc-testflight-internal", flag("testFlightInternalTestingOnly", True)),
                         ("asc-no-version-management", flag("manageAppVersionAndBuildNumber", False)),
                         ("asc-no-strip", flag("stripSwiftSymbols", False)),
                         ("asc-destination-export", flag("destination", "export")),
                         ("asc-unknown-option", flag("nomacUnknownOption", "value")),
                         ("asc-testflight-internal-false", flag("testFlightInternalTestingOnly", False))):
        se.export(experiment, archive.name, "app-store-connect", label=label, extra=extra)
    for method, label, extra in (("debugging", "debugging-no-strip", flag("stripSwiftSymbols", False)),
                                 ("enterprise", "enterprise-no-strip", flag("stripSwiftSymbols", False)),
                                 ("release-testing", "release-testing-testflight-internal", flag("testFlightInternalTestingOnly", True)),
                                 ("debugging", "debugging-unknown-option", flag("nomacUnknownOption", "value"))):
        se.export(experiment, archive.name, method, label=label, extra=extra)
    unstripped = output / "unstripped"
    if not (unstripped / "adhoc.xcarchive").is_dir():
        files, _ = se.EXPERIMENTS["adhoc"]
        for path, text in files().items():
            (unstripped / "source" / path).parent.mkdir(parents=True, exist_ok=True)
            (unstripped / "source" / path).write_text(text)
        se.observe_adhoc(unstripped / "source", unstripped, methods=(), settings=["STRIP_INSTALLED_PRODUCT=NO"])
    for method in ("app-store-connect", "release-testing"):
        se.export(unstripped, "adhoc.xcarchive", method)
        se.export(unstripped, "adhoc.xcarchive", method, label=f"{method}-no-strip", extra=flag("stripSwiftSymbols", False))


# A value away from the default for each documented option nomac's other cases leave alone
# (`xcodebuild -help`, "Available keys for -exportOptionsPlist"); generateAppStoreInformation
# is not exported for app-store-connect, whose helper does not start offline.
OPTION_VALUES = {
    "distributionBundleIdentifier": "org.nomac.signing", "embedOnDemandResourcesAssetPacksInBundle": False,
    "generateAppStoreInformation": True, "iCloudContainerEnvironment": "Production",
    "installerSigningCertificate": "Developer ID Installer", "manageAppVersionAndBuildNumber": False,
    "onDemandResourcesAssetPacksBaseURL": "https://example.com/odr", "testFlightInternalTestingOnly": True,
    "thinning": "<thin-for-all-variants>", "uploadSymbols": False,
}


def option_grid(output, archive):
    """Each of OPTION_VALUES alone, for each method: which options a method keeps in
    ExportOptions.plist."""
    for method in ("app-store-connect", "release-testing", "enterprise", "debugging"):
        for key, value in OPTION_VALUES.items():
            if not (method == "app-store-connect" and key == "generateAppStoreInformation"):
                se.export(archive.parent, archive.name, method, label=f"grid-{method}-{key}", extra=flag(key, value))


def option_archives(output, archive):
    """The options of B-466 with archives that use them: the odr app's packs exported for
    app-store-connect with `onDemandResourcesAssetPacksBaseURL`, and `provisioningProfiles` given
    to ad hoc exports (app-store-connect and debugging)."""
    odr = adhoc_archive(output, "odr")
    se.export(odr.parent, odr.name, "app-store-connect", label="asc-base-url",
              extra=flag("onDemandResourcesAssetPacksBaseURL", "https://example.com/odr"))
    profiles = "\t<key>provisioningProfiles</key>\n\t<dict>\n" + "".join(
        f"\t\t<key>{bundle}</key>\n\t\t<string>00000000-0000-4000-8000-000000000001</string>\n" for bundle in BUNDLES) + "\t</dict>\n"
    for method in ("app-store-connect", "debugging"):
        se.export(archive.parent, archive.name, method, label=f"{method}-adhoc-profiles", extra=profiles)


def png(width, height, rgb):
    """A solid RGB PNG."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


# An image set's renditions as (idiom, scale), for the thinning case's catalog.
THINNING_IMAGES = {
    "shared": [("universal", 1), ("iphone", 2), ("iphone", 3), ("ipad", 2)],
    "pad-only": [("ipad", 2)],
    "phone-low": [("iphone", 1)],
}


def thinning(output, archive):
    """Debugging exports with `thinning` `<thin-for-all-variants>`: the adhoc archive, and a copy
    whose app gets an asset catalog of THINNING_IMAGES compiled by actool (iPhone and iPad) and
    is signed again ad hoc; twice each, for what changes from run to run."""
    case = output / "thinning"
    shutil.rmtree(case, ignore_errors=True)
    catalog = case / "Assets.xcassets"
    for name, renditions in THINNING_IMAGES.items():
        folder = catalog / f"{name}.imageset"
        folder.mkdir(parents=True)
        images = []
        for idiom, scale in renditions:
            filename = f"{idiom}@{scale}x.png"
            (folder / filename).write_bytes(png(8 * scale, 8 * scale, (40 * scale, 120, 200)))
            images.append({"idiom": idiom, "scale": f"{scale}x", "filename": filename})
        (folder / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}))
    (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
    environment = dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR)
    copy = case / "catalog" / archive.name
    copy.parent.mkdir(parents=True)
    subprocess.run(["cp", "-cR", str(archive), str(copy)], check=True)
    app = next((copy / "Products/Applications").glob("*.app"))
    # Values of every property list type, for how the variants write the Info.plist again.
    info = plistlib.loads((app / "Info.plist").read_bytes())
    info.update({"NomacNested": {"Zeta": "z", "Alpha": [1, 2.5, False], "Empty": {}}, "NomacEmptyArray": [], "NomacFalse": False,
                 "NomacReal": 0.25, "NomacData": b"\x00\x01nomac", "NomacDate": datetime.datetime(2026, 11, 3, 12, 0, 0),
                 "NomacEscaped": "a & b < c > d \" ' é", "NomacNegative": -7})
    (app / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY, sort_keys=True))
    subprocess.run(["xcrun", "actool", str(catalog), "--compile", str(app), "--platform", "iphoneos", "--minimum-deployment-target",
                    "18.0", "--target-device", "iphone", "--target-device", "ipad", "--output-partial-info-plist",
                    str(case / "partial.plist")], check=True, capture_output=True, env=environment)
    subprocess.run(["codesign", "-f", "-s", "-", "--preserve-metadata=identifier,entitlements,flags", str(app)],
                   check=True, capture_output=True, env=environment)
    def variant(name, minimum=None, nested=False, large=0):
        """A copy of the catalog archive: its app declaring `minimum`, or with catalogs in its
        share extension (CAR_CATALOGS' idioms) and framework (scales) as well."""
        target = case / name / archive.name
        target.parent.mkdir(parents=True)
        subprocess.run(["cp", "-cR", str(copy), str(target)], check=True)
        target_app = next((target / "Products/Applications").glob("*.app"))
        bundles = []
        if nested:
            for bundle, images in (("Frameworks/Kit.framework", CAR_CATALOGS["scales"]), ("PlugIns/Share.appex", CAR_CATALOGS["idioms"])):
                compile_catalog(images, case / name / bundle.split("/")[1], target_app / bundle)
                bundles.append(target_app / bundle)
        if minimum:
            subprocess.run(["plutil", "-replace", "MinimumOSVersion", "-string", minimum, str(target_app / "Info.plist")], check=True)
        if large:
            # Bytes that do not compress, for how the report writes megabytes.
            (target_app / "large.bin").write_bytes(hashlib.shake_256(b"nomac").digest(large))
        for bundle in bundles + [target_app]:
            subprocess.run(["codesign", "-f", "-s", "-", "--preserve-metadata=identifier,entitlements,flags", str(bundle)],
                           check=True, capture_output=True, env=environment)
        return target

    # Declaring iOS 12.0, whose first iPad-group product (a Mac) starts at 14.0, and 18.5, which
    # device_traits.db does not list: which descriptors, and what deployment target the variants
    # are thinned for; catalogs in an extension and a framework too.
    shapes = [variant("catalog-12", minimum="12.0"), variant("catalog-185", minimum="18.5"), variant("nested", nested=True),
              variant("large", large=2_345_678), variant("large-3", large=2_975_000)]
    for experiment in (archive.parent, copy.parent, *(shape.parent for shape in shapes)):
        for run in (1, 2):
            se.export(experiment, archive.name, "debugging", label=f"thinning-{run}", extra=flag("thinning", "<thin-for-all-variants>"))
    # signing_experiments' apps with a watch app, an App Clip (signed by a script phase) and
    # on-demand resources; the watch app's copies: another BuildMachineOSBuild in its
    # Info.plist, an asset catalog (images by scale, a watchOS app icon), and watchOS 9.0.
    for name in ("watch", "appclip-script", "odr"):
        shaped = adhoc_archive(output, name)
        for run in (1, 2):
            se.export(shaped.parent, shaped.name, "debugging", label=f"thinning-{run}", extra=flag("thinning", "<thin-for-all-variants>"))
    watch = adhoc_archive(output, "watch")
    for label in ("watch-build", "watch-catalog", "watch-9"):
        target = case / label / watch.name
        target.parent.mkdir(parents=True)
        subprocess.run(["cp", "-cR", str(watch), str(target)], check=True)
        app = next((target / "Products/Applications").glob("*.app"))
        watch_app = app / "Watch/Watch.app"
        if label == "watch-build":
            subprocess.run(["plutil", "-replace", "BuildMachineOSBuild", "-string", "99Z999", str(watch_app / "Info.plist")], check=True)
        elif label == "watch-9":
            # Declaring watchOS 9.0, as two corpus apps' watch apps do, below its slices' minimums.
            subprocess.run(["plutil", "-replace", "MinimumOSVersion", "-string", "9.0", str(watch_app / "Info.plist")], check=True)
        else:
            compile_catalog(WATCH_IMAGES, case / label, watch_app, platform="watchos", devices=["watch"], minimum="11.0", icon=True)
        for bundle in (watch_app, app):
            subprocess.run(["codesign", "-f", "-s", "-", "--preserve-metadata=identifier,entitlements,flags", str(bundle)],
                           check=True, capture_output=True, env=environment)
        for run in (1, 2):
            se.export(target.parent, watch.name, "debugging", label=f"thinning-{run}", extra=flag("thinning", "<thin-for-all-variants>"))
    # Thinning for one device, by its product type.
    for device in ("iPhone12,3", "iPad13,1"):
        se.export(copy.parent, archive.name, "debugging", label=f"thinning-{device}", extra=flag("thinning", device))


# A watch app's image sets as (idiom, scale) renditions, for the thinning case's watch catalog.
WATCH_IMAGES = {"shared": [("universal", 1), ("watch", 2)], "watch-only": [("watch", 2)], "universal-two": [("universal", 2)]}


def compile_catalog(images, folder, destination, platform="iphoneos", devices=("iphone", "ipad"), minimum="18.0", icon=False):
    """Image sets as CAR_CATALOGS describes them, compiled by actool into `destination` (iOS 18.0,
    iPhone and iPad by default); `icon` adds a single-size app icon for the platform."""
    catalog = folder / "Assets.xcassets"
    for set_name, renditions in images.items():
        imageset = catalog / f"{set_name}.imageset"
        imageset.mkdir(parents=True)
        entries = []
        for index, (idiom, scale) in enumerate(renditions):
            filename = f"{idiom}@{scale}x.png"
            (imageset / filename).write_bytes(png(8 * scale + index, 8 * scale, (40 * scale, 30 * index, 200)))
            entries.append({"idiom": idiom, "scale": f"{scale}x", "filename": filename})
        (imageset / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}))
    catalog.mkdir(parents=True, exist_ok=True)
    (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
    arguments = []
    if icon:
        (catalog / "AppIcon.appiconset").mkdir()
        (catalog / "AppIcon.appiconset/icon.png").write_bytes(png(1024, 1024, (20, 120, 220)))
        (catalog / "AppIcon.appiconset/Contents.json").write_text(json.dumps({"images": [
            {"filename": "icon.png", "idiom": "universal", "platform": "ios" if platform == "iphoneos" else platform,
             "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}))
        arguments = ["--app-icon", "AppIcon", "--compress-pngs"]
    subprocess.run(["xcrun", "actool", str(catalog), "--compile", str(destination), "--platform", platform, "--minimum-deployment-target",
                    minimum, *[f for device in devices for f in ("--target-device", device)], *arguments,
                    "--output-partial-info-plist", str(folder / "partial.plist")],
                   check=True, capture_output=True, env=dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR))


# Catalogs of image sets nomac's actool compiles too (idioms and scales), for car-thinning: each
# image set as its (idiom, scale) renditions; `app` holds a color set with a dark appearance and
# a single-size app icon (color_and_icon_assets).
CAR_CATALOGS = {
    "thinning": THINNING_IMAGES,
    "scales": {"all": [("universal", 1), ("universal", 2), ("universal", 3)], "one-three": [("universal", 1), ("universal", 3)],
               "two": [("universal", 2)], "three": [("universal", 3)]},
    "idioms": {"universal-phone": [("universal", 1), ("iphone", 1)], "universal3-phone2": [("universal", 3), ("iphone", 2)],
               "pad1-universal2": [("ipad", 1), ("universal", 2)], "phone": [("iphone", 2), ("iphone", 3)],
               "pad": [("ipad", 1), ("ipad", 2)], "universal2-pad2": [("universal", 2), ("ipad", 2)]},
    "app": {},
}
CAR_CATALOGS["scales"]["one-two"] = [("universal", 1), ("universal", 2)]
TRAITS_DB = "Platforms/iPhoneOS.platform/usr/standalone/device_traits.db"


def color_and_icon_assets(catalog):
    """A color set with any and dark appearances, and AppIcon as one 1024-point iOS icon with
    its dark variant (Xcode's default app icon set), into `catalog`."""
    colors = catalog / "Accent.colorset"
    colors.mkdir(parents=True)
    def color(red):
        return {"color": {"color-space": "srgb", "components": {"red": red, "green": "0.200", "blue": "0.400", "alpha": "1.000"}}, "idiom": "universal"}
    dark = dict(color("0.900"), appearances=[{"appearance": "luminosity", "value": "dark"}])
    (colors / "Contents.json").write_text(json.dumps({"colors": [color("0.100"), dark], "info": {"author": "xcode", "version": 1}}))
    icon = catalog / "AppIcon.appiconset"
    icon.mkdir(parents=True)
    (icon / "icon.png").write_bytes(png(1024, 1024, (20, 120, 220)))
    (icon / "dark.png").write_bytes(png(1024, 1024, (10, 10, 40)))
    images = [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
              {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "dark.png", "idiom": "universal",
               "platform": "ios", "size": "1024x1024"}]
    (icon / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}))


def trait_sets(minimum="18.0"):
    """The trait sets of the descriptors from `minimum` on, by ID, as assetutil arguments in the
    database's own spellings."""
    import sqlite3
    database = sqlite3.connect(f"file:{DEVELOPER_DIR}/{TRAITS_DB}?mode=ro", uri=True)
    versions = [row[0] for row in database.execute("select TargetVersion from DeploymentTarget order by DeploymentTarget")]
    wanted = versions[versions.index(minimum):]
    rows = database.execute(
        "select distinct t.DeviceTraitSetID, t.ArtworkDeviceIdiom, t.ArtworkScaleFactor, t.ArtworkDeviceSubtype, t.ArtworkDeviceSubtypeFallbacks, "
        "t.ArtworkDisplayGamut, t.ArtworkHostedIdioms, t.GraphicsFeatureSetClass, t.GraphicsFeatureSetFallbacks, t.DevicePerformanceMemoryClass "
        "from DeploymentVariant v join DeviceTraits t on t.DeviceTraitSetID = v.DeviceTraitSet "
        f"where v.DeploymentTarget in ({','.join('?' * len(wanted))}) order by t.DeviceTraitSetID", wanted)
    sets = {}
    for identifier, idiom, scale, subtype, fallbacks, gamut, hosted, graphics, graphics_fallbacks, memory in rows:
        arguments = ["-i", idiom, "-s", str(scale)]
        arguments += ["-t", str(subtype)] if subtype else []
        arguments += ["-u", fallbacks] if fallbacks else []
        arguments += ["-p", gamut] if gamut else []
        arguments += ["-h", hosted] if hosted else []
        arguments += ["-g", graphics, "-k", graphics_fallbacks or "", "-M", str(memory), "-r", minimum]
        sets[identifier] = arguments
    return sets


def car_thinning(output, archive):
    """Each of CAR_CATALOGS compiled by actool for iPhone and iPad (iOS 18.0), then thinned by
    assetutil (the tool the export runs) for every trait set of the iOS 18.0 descriptors:
    `<case>/<catalog>/<trait set>.car`, with the arguments in `thinning.json`."""
    case = output / "car-thinning"
    shutil.rmtree(case, ignore_errors=True)
    environment = dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR)
    sets = trait_sets()
    for name, images in CAR_CATALOGS.items():
        folder = case / name
        catalog = folder / "Assets.xcassets"
        for set_name, renditions in images.items():
            imageset = catalog / f"{set_name}.imageset"
            imageset.mkdir(parents=True)
            entries = []
            for index, (idiom, scale) in enumerate(renditions):
                filename = f"{idiom}@{scale}x.png"
                (imageset / filename).write_bytes(png(8 * scale + index, 8 * scale, (40 * scale, 30 * index, 200)))
                entries.append({"idiom": idiom, "scale": f"{scale}x", "filename": filename})
            (imageset / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}))
        catalog.mkdir(parents=True, exist_ok=True)
        (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
        icon = []
        if name == "app":
            color_and_icon_assets(catalog)
            icon = ["--app-icon", "AppIcon", "--compress-pngs"]
        subprocess.run(["xcrun", "actool", str(catalog), "--compile", str(folder), "--platform", "iphoneos", "--minimum-deployment-target",
                        "18.0", "--target-device", "iphone", "--target-device", "ipad", *icon, "--output-partial-info-plist",
                        str(folder / "partial.plist")], check=True, capture_output=True, env=environment)
        for identifier, arguments in sets.items():
            subprocess.run(["assetutil", *arguments, "-o", str(folder / f"{identifier}.car"), str(folder / "Assets.car")],
                           check=True, capture_output=True)
    (case / "thinning.json").write_text(json.dumps({str(k): v for k, v in sets.items()}, indent=1) + "\n")


def compare_car_thinning(output, nomac):
    """`nomac assetutil` with each recorded trait set on each recorded catalog, byte for byte."""
    case = output / "car-thinning"
    sets = json.loads((case / "thinning.json").read_text())
    failures = 0
    for folder in sorted(p for p in case.iterdir() if p.is_dir()):
        different = []
        with tempfile.TemporaryDirectory(prefix="nomac-car-") as work:
            for identifier, arguments in sets.items():
                ours = Path(work) / f"{identifier}.car"
                completed = subprocess.run([nomac, "assetutil", *arguments, "-o", str(ours), str(folder / "Assets.car")],
                                           capture_output=True, text=True)
                if completed.returncode != 0 or ours.read_bytes() != (folder / f"{identifier}.car").read_bytes():
                    different.append(f"{identifier}: {completed.stderr.strip()[:120] or 'bytes differ'}")
        print(f"{'identical' if not different else 'DIFFERENT'}: {folder.name} {len(sets) - len(different)} of {len(sets)}")
        for line in different[:5]:
            print(f"    {line}")
        failures += bool(different)
    return failures


def thinned_export(folder):
    """A thinned export's variants by their descriptor sets: file, its app-thinning.plist entry,
    and its report block with the descriptors sorted; the IPA's own (universal) under None."""
    variants = plistlib.loads((folder / "app-thinning.plist").read_bytes())["variants"]
    report = (folder / "App Thinning Size Report.txt").read_text()
    first, rest = report.split("Variant: ", 1)
    blocks = {block.split("\n", 1)[0]: "Variant: " + block for block in ("Variant: " + rest).removeprefix("Variant: ").split("\n\n\nVariant: ")}
    result = {}
    for key, entry in variants.items():
        descriptors = entry.pop("variantDescriptors", None)
        identity = None if descriptors is None else frozenset((d["device"], d["os-version"]) for d in descriptors)
        name = key.removeprefix("Apps/")
        block = blocks[name].replace(name, "<variant>")
        listed = re.search(r"Supported variant descriptors: (.*)", block).group(1)
        block = block.replace(listed, ", ".join(sorted(re.findall(r"\[[^\]]*\]", listed))) or listed)
        result[identity] = (folder / key, entry, block.strip("\n"))
    return first, result


def compare_thinning(output, nomac):
    """`nomac export` of every thinned export of the thinning case, with Xcode 27.0's developer
    directory: the same files, variants matched by their descriptors (xcodebuild names them
    with a random UUID and lists their descriptors in an order that changes per run)."""
    failures = 0
    records = [*output.glob("*/export-thinning-*.json"), *(output / "thinning").glob("*/export-thinning-*.json")]
    for record in sorted(r for r in records if r.stem != "export-thinning-2"):
        experiment = record.parent
        xcode = experiment / record.stem
        with tempfile.TemporaryDirectory(prefix="nomac-thinning-") as work:
            ours = Path(work) / "export"
            completed = subprocess.run([nomac, "export", "-archivePath", str(experiment / "adhoc.xcarchive"), "-exportPath", str(ours),
                                        "-exportOptionsPlist", str(experiment / f"{record.stem}.plist"), "--developer-dir", DEVELOPER_DIR],
                                       capture_output=True, text=True)
            differences = [] if completed.returncode == 0 else [f"exit status {completed.returncode}: {completed.stderr.strip()[:200]}"]
            if not differences:
                if (xcode / "ExportOptions.plist").read_bytes() != (ours / "ExportOptions.plist").read_bytes():
                    differences.append("ExportOptions.plist: contents differ")
                # With a watch app xcodebuild writes, from one run to the next, the summary of the
                # export without thinning (nomac's), the same without the watch app, or one entry
                # for the watch app alone (`watch`, `watch-build`, `watch-catalog`: all three in six
                # runs).
                expected = plistlib.loads((xcode / "DistributionSummary.plist").read_bytes())
                actual = plistlib.loads((ours / "DistributionSummary.plist").read_bytes())
                app = next(iter(actual.values()))[0]
                without = dict(app, embeddedBinaries=[b for b in app.get("embeddedBinaries", []) if not b["name"].endswith(".app")])
                watches = [b for b in app.get("embeddedBinaries", []) if b["name"].endswith(".app")]
                first = next(iter(expected.values()))[0]
                watch_only = bool(watches) and first.get("name") == watches[0]["name"] and "embeddedBinaries" not in first
                if expected != actual and next(iter(expected.values()))[0] != without and not watch_only:
                    differences.append("DistributionSummary.plist: contents differ")
                expected_head, expected = thinned_export(xcode)
                actual_head, actual = thinned_export(ours)
                if expected_head != actual_head:
                    differences.append("report title differs")
                if set(expected) != set(actual):
                    differences.append(f"variants differ: {len(expected)} != {len(actual)}")
                for identity in set(expected) & set(actual):
                    (left, left_entry, left_block), (right, right_entry, right_block) = expected[identity], actual[identity]
                    label = "universal" if identity is None else f"{len(identity)} descriptors"
                    if left_entry != right_entry:
                        differences.append(f"{label}: app-thinning.plist entry differs")
                    if left_block != right_block:
                        differences.append(f"{label}: report differs")
                    differences += [f"{label}: {d}" for d in se.zip_differences(left.read_bytes(), right.read_bytes())]
        if completed.returncode == 70 and "(BACKLOG B-465)" in completed.stderr:
            print(f"refused (B-465): {experiment.name} {record.stem}")
            continue
        print(f"{'identical' if not differences else 'DIFFERENT'}: {experiment.name} {record.stem}")
        for difference in differences[:8]:
            print(f"    {difference}")
        failures += bool(differences)
    return failures


def compare(output, nomac):
    """`nomac export` on every recorded export with the case's identity and profiles: the same
    status and the same error and note lines, as sets (xcodebuild's order varies from run to
    run). app-store-information is left out: xcodebuild failed in its helper, not on a rule."""
    failures = 0
    for result in sorted(output.glob("**/result.json")):
        case = result.parent
        if case.name == "build" or case.name == "app-store-information":
            continue
        identity = case / "identity"
        arguments = ["--keychain", str(identity / "identity.pem"), "--provisioning-profiles", str(identity)] if identity.is_dir() else []
        with tempfile.TemporaryDirectory(prefix="nomac-dist-export-") as work:
            completed = subprocess.run([nomac, "export", "-archivePath", str(output / "adhoc/adhoc.xcarchive"), "-exportPath",
                                        str(Path(work) / "export"), "-exportOptionsPlist", str(case / "options.plist"), *arguments],
                                       capture_output=True, text=True)
        recorded = json.loads(result.read_text())
        expected = sorted(se.refusal_lines((case / "xcodebuild.log").read_text(), "  "))
        actual = sorted(se.refusal_lines(completed.stderr, "note: "))
        differences = [] if completed.returncode == recorded["status"] else [f"exit status {completed.returncode}, not {recorded['status']}"]
        if expected != actual:
            differences.append(f"messages {actual} != {expected}")
        print(f"{'identical' if not differences else 'DIFFERENT'}: {case.relative_to(output)}")
        for difference in differences:
            print(f"    {difference}")
        failures += bool(differences)
    return failures


CASES = ["app-store-self-signed", "development-self-signed", "app-store-information", "missing-profile", "export-options", "option-grid", "option-archives", "thinning", "car-thinning"]


def main():
    if sys.argv[1:2] == ["report"]:
        return report(Path(sys.argv[2]).resolve())
    if sys.argv[1:2] == ["compare-thinning"]:
        sys.exit(1 if compare_thinning(Path(sys.argv[2]).resolve(), str(Path(sys.argv[3]).resolve())) else 0)
    if sys.argv[1:2] == ["compare-car"]:
        sys.exit(1 if compare_car_thinning(Path(sys.argv[2]).resolve(), str(Path(sys.argv[3]).resolve())) else 0)
    if sys.argv[1:2] == ["compare"]:
        sys.exit(1 if compare(Path(sys.argv[2]).resolve(), str(Path(sys.argv[3]).resolve())) else 0)
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("cases", nargs="*")
    parser.add_argument("--apple-profile", type=Path)
    parser.add_argument("--identity", type=Path)
    arguments = parser.parse_args()
    output = arguments.output.resolve()
    archive = adhoc_archive(output)
    for name in arguments.cases or CASES + (["apple-profile"] if arguments.apple_profile else []):
        if name == "app-store-self-signed":
            self_signed(output, archive, "distribution")
        elif name == "development-self-signed":
            self_signed(output, archive, "development")
        elif name == "app-store-information":
            app_store_information(output, archive)
        elif name == "car-thinning":
            car_thinning(output, archive)
        elif name == "thinning":
            thinning(output, archive)
        elif name == "option-archives":
            option_archives(output, archive)
        elif name == "option-grid":
            option_grid(output, archive)
        elif name == "export-options":
            export_options(output, archive)
        elif name == "missing-profile":
            missing_profile(output, archive)
        elif name == "apple-profile":
            apple_profile_variants(output, archive, arguments.apple_profile.resolve(), arguments.identity.resolve())
        else:
            sys.exit(f"unknown case {name}")


if __name__ == "__main__":
    main()
