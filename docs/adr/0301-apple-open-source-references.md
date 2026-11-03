# ADR 0301: Apple's open-source releases as references for signing formats

- Status: accepted
- Date: 2026-10-21

## Context

Signing reproduces formats codesign writes: code directories, requirements, CMS signatures,
`codesign_allocate`'s layout. CLAUDE.md allows reimplementation from observed outputs and public
documentation only, never from decompiling Apple's tools. Apple publishes the source of the
Security project (`libsecurity_codesigning`, `libsecurity_smime`, `libsecurity_utilities`),
ld64 and cctools under the Apple Public Source License (APSL 2.0) at
github.com/apple-oss-distributions. The integrator confirmed (2026-10-21) that these releases
count as public documentation.

## Decision

The packaging and signing workstream reads these releases to settle formats and edge cases:
opcodes and layouts (`requirement.h`), which CMS attributes codesign asks for and the size it
reserves (`signer.cpp`, `CodeSigner.cpp`, `superblob.h`), how the CMS encoder orders sets
(`cmssigdata.c`, `cmsutil.c`), when the default identifier gets a suffix. nomac's code is
written in Swift from those facts; no Apple source is copied. Each rule taken from them is
named in the code comment or docs/formats/ with the file it comes from, and is checked against
codesign's output (`signing_experiments.py`, NomacSigningTests). Should code ever be ported,
it carries the APSL notice and a new ADR records it.

Decompiling or disassembling Apple's closed binaries (codesign itself, IDEDistribution) stays
forbidden.

## Consequences

- Formats are settled faster and edge cases (indefinite lengths, set ordering, size
  estimates) are explained rather than guessed.
- Observation stays the proof: a rule read in the sources but not yet seen in codesign's
  output is recorded as such and not relied on.
