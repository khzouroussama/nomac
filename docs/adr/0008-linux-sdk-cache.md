# ADR 0008: Linux CI verifies with an encrypted, cached copy of the runner's Xcode subset

- Status: withdrawn on 2026-11-03 (was accepted, resolving BACKLOG B-003 and extending ADR 0004)
- Date: 2026-10-21

## Withdrawn

On 2026-11-03 the project owner decided that Apple's SDK runs only on Apple hardware, as
Apple's Xcode and Apple SDKs Agreement authorizes it (docs/LEGAL.md). The `reference`
workflow's Linux jobs that unpacked the encrypted subset (`sdk`, `sdk-capture`,
`build-nomac-linux`, `verify-linux`), `.github/scripts/sdk-cache.sh` and the `NOMAC_SDK_KEY`
secret's use are removed. `verify-linux` never ran: it was added at 09:39 UTC on 2026-10-21 and
was skipped in each of the workflow's runs since, and no SDK cache entry exists. Linux builds
that use the SDK run in Docker, a Linux virtual machine, on a Mac (docs/VERIFICATION.md
"Without CI"). The rest of this record is the decision as it was taken.

## Context

nomac's claim is about Linux, but every comparison with Xcode so far ran on the macOS runner:
Swift Build cannot resolve an iOS setting without the SDK and the platform files of an Xcode
installation, and Linux CI had none. Linux CI could only run unit tests against a
self-authored synthetic developer directory. Engine differences that exist only off Darwin
(BACKLOG B-005) were therefore never measured.

The GitHub macOS runner already has the reference Xcode, and `nomac sdk install` reduces it to
a 450 MB subset that reproduces every settings capture (ADR 0003, `reference` runs 4 and 5). The
project owner decided on 2026-10-21 to keep that subset in the GitHub Actions cache for Linux
jobs.

The cache is private to the repository, but not to its pull requests: a workflow run for a pull
request, including one from a fork, can restore caches created on the base branch, and it runs
the workflow files of the pull request. Once the repository is public, anyone could open a pull
request that restores the subset and uploads it as a public artifact, which the legal line
forbids. Secrets are not given to workflow runs for pull requests from forks.

## Decision

- The `reference` workflow's `sdk` job names a cache entry
  `nomac-sdk-<Xcode build>-<hash of XcodeSubset.swift and the pack script>-<key fingerprint>`
  and looks it up. On a miss, `sdk-capture` (macOS) runs `nomac sdk install` on the runner's
  Xcode and packs the result with `.github/scripts/sdk-cache.sh`: tar and gzip, encrypted with
  AES-256-CBC under a PBKDF2-SHA256 key (200,000 iterations) derived from the `NOMAC_SDK_KEY`
  repository secret. The script decrypts and lists the archive before it is cached.
- `build-nomac-linux` builds nomac in the `swift:6.4.1-noble` container, and `verify-linux`
  restores the entry, unpacks the subset at the reference's own Xcode path, recreates the
  checkout at the reference's own path, runs `nomac verify` and uploads `linux-verify-<app>`.
  Using the reference's paths keeps values that hash a path comparable (ADR 0006).
- Without the secret, these jobs are skipped with a notice. The subset is never uploaded as an
  artifact and never committed; only its encrypted archive is stored, and only in the cache.

## Consequences

- macOS minutes are spent on the SDK only on a cache miss: a new Xcode build or subset
  definition, a new key, or seven days without any run reading the entry.
- `linux-verify-<app>` reports show nomac's real status on Linux, including the values that
  differed while Swift Build hashed with SHA-256 off Darwin (B-005, fixed by the owner's fork of
  Swift Build, ADR 0005). Until Linux matches, the corpus percentages still come from the macOS
  `verify` reports.
- Rotating `NOMAC_SDK_KEY` changes the fingerprint, so the next run captures a new entry; the
  old one expires unused.
- Pull requests from forks cannot run Linux verification, because they get no secret.
