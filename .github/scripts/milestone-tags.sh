#!/usr/bin/env bash
# Creates the milestone tags listed in a tag file (default .github/tags), as described in
# docs/adr/0007-milestone-tags.md. Each non-comment line is
#
#   <tag> <full commit SHA> <message>
#
# A tag is created only when the commit is in the history of the checked-out commit and the
# `ci` workflow succeeded on it. A tag that already exists on the same commit is left alone; one
# that exists on another commit is an error, because tags are never moved.
#
# Environment: GITHUB_REPOSITORY, GITHUB_SHA and GH_TOKEN as set by GitHub Actions.
# CI_WAIT_SECONDS (default 2700) bounds how long to wait for a `ci` run that is still going;
# a commit with no `ci` run at all is waited for at most CI_MISSING_SECONDS (default 120).
set -euo pipefail

file=${1:-.github/tags}
wait_seconds=${CI_WAIT_SECONDS:-2700}
missing_seconds=${CI_MISSING_SECONDS:-120}
poll_seconds=${CI_POLL_SECONDS:-30}
tag_pattern='^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'

# Prints "success <run URL>", "pending", "missing" or "failure" for the `ci` runs of a commit.
ci_status() {
  gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$1&per_page=100" --jq '
    [.workflow_runs[]] as $runs
    | ([$runs[] | select(.conclusion == "success")] | first) as $green
    | if $green != null then "success \($green.html_url)"
      elif any($runs[]; .status != "completed") then "pending"
      elif ($runs | length) == 0 then "missing"
      else "failure" end'
}

# Waits for `ci` on a commit to finish and prints the URL of its successful run.
await_ci() {
  local sha=$1 waited=0 status
  while true; do
    status=$(ci_status "$sha")
    case $status in
      success\ *) echo "${status#success }"; return 0 ;;
      failure) echo "the ci workflow did not succeed on $sha" >&2; return 1 ;;
      missing) if (( waited >= missing_seconds )); then echo "the ci workflow never ran on $sha" >&2; return 1; fi ;;
      pending) if (( waited >= wait_seconds )); then echo "the ci workflow on $sha did not finish within ${wait_seconds}s" >&2; return 1; fi ;;
      *) echo "unexpected ci status for $sha: $status" >&2; return 1 ;;
    esac
    sleep "$poll_seconds"
    waited=$((waited + poll_seconds))
  done
}

failed=0
line_number=0
while IFS= read -r line || [[ -n $line ]]; do
  line_number=$((line_number + 1))
  [[ -z ${line//[[:space:]]/} || $line =~ ^[[:space:]]*# ]] && continue
  read -r tag sha message <<<"$line"
  where="$file:$line_number"
  if [[ ! $tag =~ $tag_pattern ]]; then
    echo "$where: error: '$tag' is not a version tag (vMAJOR.MINOR.PATCH[-label])" >&2; failed=1; continue
  fi
  if [[ ! ${sha:-} =~ ^[0-9a-f]{40}$ ]]; then
    echo "$where: error: '${sha:-}' is not a full commit SHA" >&2; failed=1; continue
  fi
  if [[ -z ${message:-} ]]; then
    echo "$where: error: $tag has no message" >&2; failed=1; continue
  fi
  if ! git cat-file -e "$sha^{commit}" 2>/dev/null || ! git merge-base --is-ancestor "$sha" "$GITHUB_SHA"; then
    echo "$where: error: $sha is not in the history of $GITHUB_SHA" >&2; failed=1; continue
  fi
  if existing=$(git rev-parse -q --verify "refs/tags/$tag^{commit}"); then
    if [[ $existing == "$sha" ]]; then
      echo "$tag already points at $sha"
    else
      echo "$where: error: $tag already points at $existing; tags are never moved" >&2; failed=1
    fi
    continue
  fi
  if ! run_url=$(await_ci "$sha"); then
    echo "$where: error: not tagging $tag" >&2; failed=1; continue
  fi
  git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    tag -a "$tag" "$sha" -m "$message" -m "ci: $run_url"
  git push origin "refs/tags/$tag"
  echo "created $tag at $sha (ci: $run_url)"
done <"$file"

exit "$failed"
