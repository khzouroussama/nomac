# ADR 0007: Milestone tags are created by a workflow from `.github/tags`

- Status: accepted
- Date: 2026-10-21

## Context

Milestones are tagged (`v0.1.0-loader`, …) only when CI is green. The agent's session may push
only its working branch: pushing `v0.1.0-loader` from the session was refused with HTTP 403. If
every milestone tag waited for the owner to push it by hand, tags would lag behind the work and
a tag could be pushed on a commit CI never verified.

## Decision

- Milestone tags are listed in `.github/tags`, one per line: `<tag> <full commit SHA> <message>`.
  Adding a line and pushing the branch is how a milestone is tagged.
- The `tags` workflow (`.github/workflows/tags.yml`) runs when that file changes. It creates an
  annotated tag with the repository's `GITHUB_TOKEN` only when:
  - the tag is a version tag (`vMAJOR.MINOR.PATCH[-label]`) and the SHA is a full commit SHA;
  - the commit is in the history of the pushed commit;
  - the `ci` workflow has a successful run on that exact commit (the workflow waits up to 45
    minutes for a run still in progress). The tag message ends with that run's URL.
- An existing tag on the same commit is skipped. An existing tag on another commit is an
  error: the workflow never moves or deletes tags.
- The logic lives in `.github/scripts/milestone-tags.sh`. The workflow runs
  `.github/scripts/milestone-tags-test.sh` first, which exercises it against a scratch
  repository and canned Actions API responses.

## Consequences

- Tags are authored by `github-actions[bot]`. Tags pushed with `GITHUB_TOKEN` do not trigger
  other workflows, which is what we want: nothing runs on tag pushes.
- "CI is green" is checked by the workflow, not asserted by whoever adds the line.
- Retracting or moving a tag remains a manual decision for the owner.
