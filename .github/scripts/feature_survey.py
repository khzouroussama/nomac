#!/usr/bin/env python3
"""Survey how many open-source iOS apps lie entirely inside nomac's envelope.

The app list is github.com/dkhamsing/open-source-ios-apps (its contents.json). Each GitHub
repository is sparse-cloned at its default branch's head with only the files that describe a
project (ADR 0011):

    git clone --depth 1 --filter=blob:none --sparse <url>
    git sparse-checkout set --no-cone <PATTERNS>

`nomac check --json --description-only` then reads each repository's entry container, and the
results are aggregated: how often each feature is used, the share of apps with no feature of a
domain outside the envelope, for each domain and for all of them (with its 95% Wilson interval),
and the features that would raise the loader's share, the headline (ADR 0011), most if verified
next.

Usage:
  feature_survey.py [all|fetch|check|report] [--out DIR] [--nomac PATH] [--jobs N] [--limit N]
                    [--list FILE]

`all` runs the three steps. Every step reuses what an earlier run left in the output folder:
fetched repositories are not cloned again, checked ones not checked again. Output goes to
~/nomac-out/survey by default, never into the repository.
"""

import argparse
import collections
import concurrent.futures
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

LIST_URL = "https://raw.githubusercontent.com/dkhamsing/open-source-ios-apps/master/contents.json"
DEFAULT_OUT = Path.home() / "nomac-out" / "survey"
DEFAULT_NOMAC = Path(__file__).resolve().parents[2] / ".build" / "debug" / "nomac"
# The project-description files. SwiftPM reads a `Package@swift-<version>.swift` in place of
# `Package.swift` when the toolchain matches, so those are manifests too.
PATTERNS = ["*.xcodeproj/", "*.xcworkspace/", "*.xcconfig", "Package.swift", "Package@swift-*.swift",
            "Package.resolved", "*.xctestplan"]
CLONE_TIMEOUT = 300
CHECK_TIMEOUT = 300
MAX_CLONES = 8
ATTEMPTS = 2
# Folders whose projects are not the app's own: dependency managers' checkouts and build output.
EXCLUDED_DIRECTORIES = {"Pods", "Carthage", "node_modules", "build", "DerivedData", ".build", "vendor", "Vendor",
                        "third_party", "ThirdParty", "external", "External", "submodules", "Submodules"}
GIT_ENVIRONMENT = {"GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "/usr/bin/true", "SSH_ASKPASS": "/usr/bin/true",
                   "GIT_LFS_SKIP_SMUDGE": "1"}

print_lock = threading.Lock()


def log(message):
    with print_lock:
        print(message, flush=True)


# ---------------------------------------------------------------------------------------------
# The app list


def load_list(out, list_file):
    path = Path(list_file) if list_file else out / "contents.json"
    if not path.exists():
        with urllib.request.urlopen(LIST_URL, timeout=120) as response:
            path.write_bytes(response.read())
    return json.loads(path.read_text())


def github_repository(source):
    """`owner/name` of a GitHub source URL, or None for any other host."""
    match = re.match(r"https?://(?:www\.)?github\.com/([^/\s#?]+)/([^/\s#?]+)", source or "")
    if not match:
        return None
    owner, name = match.group(1), match.group(2)
    if name.endswith(".git"):
        name = name[:-4]
    return f"{owner}/{name}"


def repositories(contents):
    seen = {}
    for project in contents["projects"]:
        repository = github_repository(project.get("source"))
        if repository and repository.lower() not in seen:
            seen[repository.lower()] = {"repository": repository, "title": project.get("title", ""),
                                        "source": project.get("source"), "categories": project.get("category-ids", [])}
    return list(seen.values())


def folder_name(repository):
    return repository.replace("/", "__")


# ---------------------------------------------------------------------------------------------
# Fetch


def git(arguments, cwd=None, timeout=CLONE_TIMEOUT):
    environment = dict(os.environ, **GIT_ENVIRONMENT)
    return subprocess.run(["git", "-c", "credential.helper=", "-c", "core.askPass=/usr/bin/true", *arguments], cwd=cwd,
                          env=environment, capture_output=True, text=True, timeout=timeout)


def clone_once(repository, directory):
    if directory.exists():
        shutil.rmtree(directory)
    url = f"https://github.com/{repository}.git"
    steps = [(["clone", "--quiet", "--depth", "1", "--filter=blob:none", "--sparse", "--no-tags", url, str(directory)], None),
             (["sparse-checkout", "set", "--no-cone", *PATTERNS], directory)]
    for arguments, cwd in steps:
        try:
            result = git(arguments, cwd=cwd)
        except subprocess.TimeoutExpired:
            return f"git {arguments[0]} timed out after {CLONE_TIMEOUT} s"
        if result.returncode != 0:
            return f"git {arguments[0]} failed ({result.returncode}): {result.stderr.strip()[-400:]}"
    return None


def fetch_one(entry, repos):
    repository = entry["repository"]
    directory = repos / folder_name(repository)
    record_path = repos / (folder_name(repository) + ".fetch.json")
    if record_path.exists():
        record = json.loads(record_path.read_text())
        if record["status"] == "fetched" and directory.exists():
            return record
    errors = []
    for attempt in range(ATTEMPTS):
        if attempt:
            time.sleep(10)
        error = clone_once(repository, directory)
        if error is None:
            break
        errors.append(error)
    if len(errors) == ATTEMPTS:
        if directory.exists():
            shutil.rmtree(directory)
        record = {"repository": repository, "status": "failed", "errors": errors}
    else:
        head = git(["rev-parse", "HEAD"], cwd=directory).stdout.strip()
        branch = git(["rev-parse", "--abbrev-ref", "HEAD"], cwd=directory).stdout.strip()
        record = {"repository": repository, "status": "fetched", "commit": head, "branch": branch, "retried": bool(errors)}
    record_path.write_text(json.dumps(record, indent=1) + "\n")
    log(f"{record['status']:8} {repository}" + (f" {record.get('commit', '')[:12]}" if record["status"] == "fetched" else f": {errors[-1]}"))
    return record


def fetch(out, entries, jobs):
    repos = out / "repos"
    repos.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(jobs, MAX_CLONES)) as pool:
        records = list(pool.map(lambda entry: fetch_one(entry, repos), entries))
    counts = collections.Counter(record["status"] for record in records)
    log(f"fetched {counts['fetched']}, failed twice {counts['failed']}")
    return records


# ---------------------------------------------------------------------------------------------
# Check


def excluded(relative):
    parts = Path(relative).parts
    return any(part in EXCLUDED_DIRECTORIES for part in parts[:-1]) or any(part.endswith((".xcodeproj", ".xcworkspace")) for part in parts[:-1])


def entry_container(directory):
    """The container a developer opens: the shallowest workspace, else the shallowest project,
    outside dependency managers' folders; ties go to the first path in byte order."""
    candidates = {".xcworkspace": [], ".xcodeproj": []}
    for root, folders, _ in os.walk(directory):
        if ".git" in folders:
            folders.remove(".git")
        for folder in list(folders):
            suffix = Path(folder).suffix
            if suffix in candidates:
                relative = os.path.relpath(os.path.join(root, folder), directory)
                if not excluded(relative):
                    candidates[suffix].append(relative)
                folders.remove(folder)
    for suffix in (".xcworkspace", ".xcodeproj"):
        if candidates[suffix]:
            return sorted(candidates[suffix], key=lambda path: (len(Path(path).parts), path))[0], len(candidates[".xcworkspace"]) + len(candidates[".xcodeproj"])
    return None, 0


def check_one(record, repos, checks, nomac):
    repository = record["repository"]
    result_path = checks / (folder_name(repository) + ".json")
    if result_path.exists():
        cached = json.loads(result_path.read_text())
        if cached["status"] != "checked" or "domains" in cached:
            return cached
    directory = repos / folder_name(repository)
    container, candidates = entry_container(directory)
    result = {"repository": repository, "commit": record["commit"], "container": container, "candidates": candidates}
    if container is None:
        result["status"] = "no-project"
    else:
        try:
            run = subprocess.run([nomac, "check", "--json", "--description-only", str(directory / container)], capture_output=True, text=True,
                                 timeout=CHECK_TIMEOUT)
            if run.returncode in (0, 1) and run.stdout:
                report = json.loads(run.stdout)
                result["status"] = "checked"
                result["inside"] = report["inside"]
                result["features"] = {feature["id"]: feature["status"] for feature in report["features"]}
                result["domains"] = {feature["id"]: feature["domain"] for feature in report["features"]}
                result["unchecked"] = sorted({part["what"] for part in report["unchecked"]})
            else:
                result["status"] = "failed"
                result["error"] = (run.stderr or run.stdout).strip()[-600:]
        except subprocess.TimeoutExpired:
            result["status"] = "failed"
            result["error"] = f"timed out after {CHECK_TIMEOUT} s"
    result_path.write_text(json.dumps(result, indent=1, sort_keys=True) + "\n")
    log(f"{result['status']:10} {repository} {container or ''}" + (" inside" if result.get("inside") else ""))
    return result


def check(out, records, nomac, jobs):
    checks = out / "checks"
    checks.mkdir(parents=True, exist_ok=True)
    fetched = [record for record in records if record["status"] == "fetched"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        return list(pool.map(lambda record: check_one(record, out / "repos", checks, nomac), fetched))


# ---------------------------------------------------------------------------------------------
# Report


def wilson(successes, total, z=1.959964):
    if total == 0:
        return (0.0, 0.0)
    share = successes / total
    denominator = 1 + z * z / total
    centre = (share + z * z / (2 * total)) / denominator
    margin = z * math.sqrt(share * (1 - share) / total + z * z / (4 * total * total)) / denominator
    return (centre - margin, centre + margin)


def greedy(blockers, limit):
    """Features to verify in order: each step the one that brings the most projects entirely inside
    the envelope, ties going to the one that blocks the most projects."""
    remaining = {project: set(features) for project, features in blockers.items() if features}
    verified = set()
    steps = []
    while remaining and len(steps) < limit:
        counts = collections.Counter(feature for features in remaining.values() for feature in features)
        unblocked = collections.Counter(next(iter(features)) for features in remaining.values() if len(features) == 1)
        feature = max(counts, key=lambda candidate: (unblocked[candidate], counts[candidate], candidate))
        verified.add(feature)
        newly = 0
        for project in list(remaining):
            remaining[project].discard(feature)
            if not remaining[project]:
                del remaining[project]
                newly += 1
        steps.append({"feature": feature, "unblocks": newly, "blocks": counts[feature]})
    return steps


HEADLINE = "loader"


def outside(result, domain=None):
    """The features of a checked project outside the envelope, of `domain` or of every domain."""
    return {feature for feature, feature_status in result["features"].items()
            if feature_status != "verified" and domain in (None, result["domains"][feature])}


def coverage(checked, domain=None):
    inside = sum(not outside(result, domain) for result in checked)
    low, high = wilson(inside, len(checked))
    return {"inside": inside, "coverage": inside / len(checked) if checked else 0, "coverage95": [low, high]}


def report(out, records, results, contents_path):
    checked = [result for result in results if result["status"] == "checked"]
    total = len(checked)
    domains = sorted({domain for result in checked for domain in result["domains"].values()} | {HEADLINE}, key=lambda name: (name != HEADLINE, name))
    by_domain = {domain: coverage(checked, domain) for domain in domains}
    headline = by_domain[HEADLINE]
    low, high = headline["coverage95"]
    usage = collections.Counter()
    status = {}
    domain_of = {}
    for result in checked:
        for feature, feature_status in result["features"].items():
            usage[feature] += 1
            status[feature] = feature_status
            domain_of[feature] = result["domains"][feature]
    blockers = {result["repository"]: outside(result, HEADLINE) for result in checked}
    blocked = collections.Counter(feature for features in blockers.values() for feature in features)
    sole = collections.Counter(next(iter(features)) for features in blockers.values() if len(features) == 1)
    others = {domain: collections.Counter(feature for result in checked for feature in outside(result, domain)) for domain in domains if domain != HEADLINE}
    steps = greedy(blockers, 30)
    cumulative = headline["inside"]
    for step in steps:
        cumulative += step["unblocks"]
        step["coverage"] = cumulative / total if total else 0
    unchecked = collections.Counter(what for result in checked for what in result["unchecked"])
    summary = {
        "list": {"source": LIST_URL, "sha256": hashlib.sha256(contents_path.read_bytes()).hexdigest()},
        "repositories": len(records),
        "fetched": sum(record["status"] == "fetched" for record in records),
        "failedTwice": sum(record["status"] == "failed" for record in records),
        "withoutProject": sum(result["status"] == "no-project" for result in results),
        "checkFailed": sum(result["status"] == "failed" for result in results),
        "projects": total,
        "headlineDomain": HEADLINE,
        "inside": headline["inside"],
        "coverage": headline["coverage"],
        "coverage95": headline["coverage95"],
        "domains": by_domain,
        "allDomains": coverage(checked),
        "next": steps,
        "blocking": [{"feature": feature, "blocks": count, "soleBlocker": sole[feature], "status": status[feature]} for feature, count in blocked.most_common()],
        "blockingByDomain": {domain: [{"feature": feature, "blocks": count, "status": status[feature]} for feature, count in counter.most_common()]
                             for domain, counter in others.items()},
        "usage": [{"feature": feature, "domain": domain_of[feature], "projects": count, "status": status[feature]} for feature, count in usage.most_common()],
        "unchecked": dict(unchecked.most_common()),
        "commits": {result["repository"]: result["commit"] for result in results},
        "containers": {result["repository"]: result["container"] for result in checked},
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=1) + "\n")
    lines = [
        f"Repositories {summary['repositories']}, fetched {summary['fetched']}, failed twice {summary['failedTwice']}, "
        f"without an Xcode project {summary['withoutProject']}, check failed {summary['checkFailed']}.",
        f"Projects checked: {total}. Entirely inside the {HEADLINE}'s envelope: {headline['inside']} ({100 * headline['coverage']:.1f}%, "
        f"95% CI {100 * low:.1f}-{100 * high:.1f}%).",
        "",
        "Projects with no feature of the domain outside its envelope:",
        "",
        "| | " + " | ".join(domains) + " |",
        "|---|" + "---|" * len(domains),
        "| projects | " + " | ".join(str(by_domain[domain]["inside"]) for domain in domains) + " |",
        "| share | " + " | ".join(f"{100 * by_domain[domain]['coverage']:.1f}%" for domain in domains) + " |",
        "| 95% CI | " + " | ".join("{:.1f}-{:.1f}%".format(*(100 * bound for bound in by_domain[domain]["coverage95"])) for domain in domains) + " |",
        "",
        "All domains: {} ({:.1f}%, 95% CI {:.1f}-{:.1f}%).".format(summary["allDomains"]["inside"], 100 * summary["allDomains"]["coverage"],
                                                                  *(100 * bound for bound in summary["allDomains"]["coverage95"])),
        "",
        f"Verify next for the {HEADLINE} (greedy: projects each brings inside, projects it blocks, coverage after):",
    ]
    lines += [f"{index:3}. {step['feature']}: +{step['unblocks']} ({step['blocks']} blocked) -> {100 * step['coverage']:.1f}%"
              for index, step in enumerate(steps, 1)]
    lines += ["", f"Most blocking features of the {HEADLINE} (projects blocked, as the only blocker):"]
    lines += [f"  {item['blocks']:5} {item['soleBlocker']:5}  {item['status']:10} {item['feature']}" for item in summary["blocking"][:40]]
    for domain, items in summary["blockingByDomain"].items():
        lines += ["", f"Most blocking features of {domain} (projects blocked):"]
        lines += [f"  {item['blocks']:5}  {item['status']:10} {item['feature']}" for item in items[:10]]
    lines += ["", "Parts not checked in sparse checkouts (projects):"]
    lines += [f"  {count:5}  {what}" for what, count in unchecked.most_common()]
    (out / "SUMMARY.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


# ---------------------------------------------------------------------------------------------
# Main


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("step", nargs="?", default="all", choices=["all", "fetch", "check", "report"])
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--nomac", default=str(DEFAULT_NOMAC))
    parser.add_argument("--jobs", type=int, default=MAX_CLONES)
    parser.add_argument("--limit", type=int, default=0, help="survey only the first N repositories of the list")
    parser.add_argument("--list", help="a contents.json to use instead of downloading it")
    arguments = parser.parse_args()
    out = Path(arguments.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    entries = repositories(load_list(out, arguments.list))
    if arguments.limit:
        entries = entries[:arguments.limit]
    repos = out / "repos"
    if arguments.step in ("all", "fetch"):
        fetch(out, entries, arguments.jobs)
    records = [json.loads((repos / (folder_name(entry["repository"]) + ".fetch.json")).read_text()) for entry in entries
               if (repos / (folder_name(entry["repository"]) + ".fetch.json")).exists()]
    if arguments.step in ("all", "check"):
        check(out, records, arguments.nomac, arguments.jobs)
    if arguments.step in ("all", "check", "report"):
        checks = out / "checks"
        results = [json.loads((checks / (folder_name(record["repository"]) + ".json")).read_text()) for record in records
                   if record["status"] == "fetched" and (checks / (folder_name(record["repository"]) + ".json")).exists()]
        report(out, records, results, Path(arguments.list) if arguments.list else out / "contents.json")


if __name__ == "__main__":
    sys.exit(main())
