#!/usr/bin/env python3
"""The merge gate's check of what reaches the public main: the tree of a ref, with NOTICE written
again, checked for anything that must not be published, as a one-commit repository that is never
pushed (the public repository began as such a snapshot, on 2026-11-03).

Usage: public_snapshot.py <output-dir> [--ref main] [--leak-scan <leak_scan.py>]
                          [--message <title>] [--co-author <name and address>]
  <output-dir>  a new or empty directory; the snapshot repository is made there
  --ref         the commit whose tree is published (default main)
  --message     the commit's title (default "nomac early preview"); the body names the commit of
                this repository the tree comes from
  --co-author   the Co-Authored-By trailer (default Claude Opus 5.5 <noreply@anthropic.com>)
  --leak-scan   the owner's scan for signing identifiers (default $NOMAC_LEAK_SCAN), which reads
                identifiers kept outside the repository and prints where they occur, never them;
                the snapshot is refused without it

The snapshot changes one file besides NOTICE: `.github/tags` keeps its comments but no tag line,
since the commits they name are not in the snapshot's history (the tags workflow would fail).
Checks of the snapshot's tree: no file but the logos is binary, no executable format, Apple
archive or signing file by content or extension, no path under this machine's home folder or its
user name, no Claude session line or link. The commit is authored by this repository's git user.
"""
import argparse
import io
import os
import pathlib
import pwd
import re
import subprocess
import sys
import tarfile

ALLOWED_BINARY = {"docs/assets/logo-dark.png", "docs/assets/logo-light.png"}
FORBIDDEN_EXTENSIONS = {".car", ".nib", ".mom", ".omo", ".tbd", ".dylib", ".a", ".o", ".ipa", ".xip", ".dmg", ".zip",
                        ".mobileprovision", ".provisionprofile", ".p12", ".cer", ".der", ".pem", ".key", ".xcarchive"}
MAGIC = {b"\xcf\xfa\xed\xfe": "Mach-O", b"\xce\xfa\xed\xfe": "Mach-O", b"\xca\xfe\xba\xbe": "universal Mach-O",
         b"\x7fELF": "ELF", b"!<arch>\n": "ar archive", b"xar!": "xar archive", b"bplist00": "binary property list",
         b"PK\x03\x04": "zip archive", b"BOMStore": "BOM (asset catalog)", b"\x30\x80\x06\x09": "CMS signature"}
SESSION = re.compile(r"Claude-[S]ession|claude\.ai/(code|chat)/")


def git(repo, *args, **kwargs):
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, **kwargs).stdout


def findings(root):
    home = os.path.expanduser("~")
    user = pwd.getpwuid(os.getuid()).pw_name
    private = re.compile("|".join(re.escape(p) for p in {home, f"/Users/{user}", f"/home/{user}"}))
    found = []
    for path in sorted(p for p in root.rglob("*") if p.is_file() and ".git" not in p.relative_to(root).parts):
        name = path.relative_to(root).as_posix()
        data = path.read_bytes()
        if path.suffix.lower() in FORBIDDEN_EXTENSIONS:
            found.append(f"{name}: a {path.suffix} file")
        kind = next((kind for magic, kind in MAGIC.items() if data.startswith(magic)), None)
        if kind:
            found.append(f"{name}: {kind}")
        if name in ALLOWED_BINARY:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            found.append(f"{name}: not UTF-8 text")
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if private.search(line):
                found.append(f"{name}:{number}: a path in this machine's home folder")
            if SESSION.search(line) and name != "CLAUDE.md":
                found.append(f"{name}:{number}: a Claude session line or link")
    return found


def stage(repo, commit, out):
    """Puts the tree of `commit`, with the snapshot's changes, in the work tree of `out`, and
    stops when the result has something that must not be published."""
    if (out / ".git").exists():
        git(out, "rm", "-r", "-q", "--ignore-unmatch", ".")
    with tarfile.open(fileobj=io.BytesIO(git(repo, "archive", "--format=tar", commit))) as archive:
        archive.extractall(out, filter="tar")
    tags = out / ".github/tags"
    tags.write_text("".join(line for line in tags.read_text().splitlines(True) if line.startswith("#") or not line.strip()))
    subprocess.run([sys.executable, str(out / ".github/scripts/third_party_notices.py"), str(out)], check=True, capture_output=True)
    problems = findings(out)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(f"error: {len(problems)} findings in the tree of {commit[:12]}; nothing was committed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    parser.add_argument("--ref", default="main")
    parser.add_argument("--leak-scan", default=os.environ.get("NOMAC_LEAK_SCAN"))
    parser.add_argument("--message", default="nomac early preview")
    parser.add_argument("--co-author", default="Claude Opus 5.5 <noreply@anthropic.com>")
    args = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parents[2]
    out = pathlib.Path(args.output).resolve()
    commit = git(repo, "rev-parse", "--verify", f"{args.ref}^{{commit}}", text=True).strip()
    if not args.leak_scan or not pathlib.Path(args.leak_scan).is_file():
        sys.exit("error: no leak scan (--leak-scan or NOMAC_LEAK_SCAN); the snapshot is not made without it")
    if out.exists() and any(out.iterdir()):
        sys.exit(f"error: {out} is not empty")
    name = git(repo, "config", "user.name", text=True).strip()
    email = git(repo, "config", "user.email", text=True).strip()

    out.mkdir(parents=True, exist_ok=True)
    stage(repo, commit, out)

    environment = {**os.environ, "GIT_AUTHOR_NAME": name, "GIT_AUTHOR_EMAIL": email,
                   "GIT_COMMITTER_NAME": name, "GIT_COMMITTER_EMAIL": email}
    subprocess.run(["git", "init", "-q", "-b", "main", str(out)], check=True)
    git(out, "add", "-A")
    message = f"{args.message}\n\nThe tree of the development repository at {commit[:12]}.\n\nCo-Authored-By: {args.co_author}\n"
    subprocess.run(["git", "-C", str(out), "commit", "-q", "-m", message], check=True, env=environment)
    scan = subprocess.run([sys.executable, args.leak_scan, str(out)], capture_output=True, text=True, check=False)
    print(scan.stdout.strip().splitlines()[-1] if scan.stdout.strip() else scan.stderr.strip())
    if scan.returncode != 0:
        sys.exit(f"error: the leak scan found identifiers in {out}; do not publish it")
    files = len(git(out, "ls-files", text=True).splitlines())
    commits = git(out, "rev-list", "--count", "HEAD", text=True).strip()
    print(f"snapshot of {commit[:12]} ({args.ref}): {files} files, commit {git(out, 'rev-parse', '--short=12', 'HEAD', text=True).strip()} ({commits} in main), in {out}")
    print("Not pushed.")


main()
