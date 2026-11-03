#!/usr/bin/env python3
"""Makes a commit of the public repository: the tree of a ref of this repository (the development
repository, which keeps the history), with NOTICE written again, checked for anything that must
not be published, and stops before any push (the owner decided on 2026-11-02 that the public
repository starts from a one-commit snapshot of the tree, without this repository's history).
The first snapshot is a repository of one commit; with --onto, a later one is a new commit on
top of the public repository's main, so it is pushed as a fast-forward.

Usage: public_snapshot.py <output-dir> [--ref main] [--onto <public repository>] [--leak-scan <leak_scan.py>]
                          [--message <title>] [--co-author <name and address>]
  <output-dir>  a new or empty directory; the snapshot repository is made there
  --ref         the commit whose tree is published (default main)
  --onto        the public repository's URL or path, whose main the snapshot commit goes on top of
  --message     the commit's title (default "nomac early preview"); the body names the commit of
                this repository the tree comes from
  --co-author   the Co-Authored-By trailer (default Claude Opus 5.5 <noreply@anthropic.com>)
  --repo        the development repository to read (default: the one holding this script)
  --follow      <output-dir> is an existing clone of the public repository: the tree of --ref
                becomes its next commit, with --ref's message, author, committer and dates, or
                nothing happens when the public tree would not change (continuous publishing,
                docs/state/release.md); no leak scan runs, the caller runs it before pushing
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


def follow(repo, commit, out):
    """The tree of `commit` as the next commit of the public clone `out`, with its metadata."""
    if git(out, "status", "--porcelain", text=True).strip():
        sys.exit(f"error: {out} has uncommitted changes")
    stage(repo, commit, out)
    git(out, "add", "-A")
    if not git(out, "status", "--porcelain", text=True).strip():
        print(f"{commit[:12]}: no change to the public tree")
        return
    fields = git(repo, "show", "-s", "--format=%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%B", commit, text=True).split("\0", 6)
    names = ["GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_AUTHOR_DATE", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL", "GIT_COMMITTER_DATE"]
    environment = {**os.environ, **dict(zip(names, fields[:6]))}
    subprocess.run(["git", "-C", str(out), "commit", "-q", "--cleanup=verbatim", "-F", "-"], input=fields[6].encode(), check=True, env=environment)
    print(f"{commit[:12]} -> {git(out, 'rev-parse', '--short=12', 'HEAD', text=True).strip()}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    parser.add_argument("--ref", default="main")
    parser.add_argument("--leak-scan", default=os.environ.get("NOMAC_LEAK_SCAN"))
    parser.add_argument("--onto")
    parser.add_argument("--message", default="nomac early preview")
    parser.add_argument("--co-author", default="Claude Opus 5.5 <noreply@anthropic.com>")
    parser.add_argument("--follow", action="store_true")
    parser.add_argument("--repo", help="the development repository (default: the one holding this script)")
    args = parser.parse_args()
    repo = pathlib.Path(args.repo).resolve() if args.repo else pathlib.Path(__file__).resolve().parents[2]
    out = pathlib.Path(args.output).resolve()
    commit = git(repo, "rev-parse", "--verify", f"{args.ref}^{{commit}}", text=True).strip()
    if args.follow:
        follow(repo, commit, out)
        return
    if not args.leak_scan or not pathlib.Path(args.leak_scan).is_file():
        sys.exit("error: no leak scan (--leak-scan or NOMAC_LEAK_SCAN); the snapshot is not made without it")
    if out.exists() and any(out.iterdir()):
        sys.exit(f"error: {out} is not empty")
    name = git(repo, "config", "user.name", text=True).strip()
    email = git(repo, "config", "user.email", text=True).strip()

    out.mkdir(parents=True, exist_ok=True)
    if args.onto:
        subprocess.run(["git", "clone", "-q", "--branch", "main", args.onto, str(out)], check=True)
    stage(repo, commit, out)

    environment = {**os.environ, "GIT_AUTHOR_NAME": name, "GIT_AUTHOR_EMAIL": email,
                   "GIT_COMMITTER_NAME": name, "GIT_COMMITTER_EMAIL": email}
    if not args.onto:
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
    print("Not pushed: push main from that directory (a fast-forward; never force). A push runs the ci and tags workflows.")


main()
