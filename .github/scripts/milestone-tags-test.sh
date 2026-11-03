#!/usr/bin/env bash
# Tests milestone-tags.sh against a scratch repository with a bare origin. A stand-in `gh` on
# PATH answers the Actions API query from canned responses with the script's own jq filter.
set -euo pipefail

script=$(cd "$(dirname "$0")" && pwd)/milestone-tags.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/ci"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# gh api <path> --jq <filter>: serves $FAKE_CI/<sha>.json, or <sha>.<n>.json on the n-th call.
path=$2 filter=$4
sha=${path##*head_sha=}; sha=${sha%%&*}
count_file="$FAKE_CI/$sha.calls"
calls=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 )); echo "$calls" >"$count_file"
response="$FAKE_CI/$sha.$calls.json"
[[ -f $response ]] || response="$FAKE_CI/$sha.json"
[[ -f $response ]] || response="$FAKE_CI/none.json"
jq -r "$filter" "$response"
EOF
chmod +x "$work/bin/gh"
echo '{"workflow_runs": []}' >"$work/ci/none.json"

runs() { # runs <sha> <status>/<conclusion>...
  local sha=$1; shift
  local items=() entry
  for entry in "$@"; do
    items+=("{\"status\": \"${entry%%/*}\", \"conclusion\": $( [[ ${entry#*/} == null ]] && echo null || echo "\"${entry#*/}\"" ), \"html_url\": \"https://example.invalid/runs/$sha/${#items[@]}\"}")
  done
  local IFS=,
  echo "{\"workflow_runs\": [${items[*]}]}"
}

git init -q --bare "$work/origin.git"
git init -q "$work/repo"
cd "$work/repo"
git config user.name test; git config user.email test@example.invalid
git remote add origin "$work/origin.git"
commit() { git commit -q --allow-empty -m "$1"; git rev-parse HEAD; }
green=$(commit green)
red=$(commit red)
slow=$(commit slow)
never=$(commit never)
head=$(commit head)
git checkout -q -b side "$green"
side=$(commit side)
git checkout -q -
git push -q origin HEAD:refs/heads/main

runs "$green" completed/success completed/cancelled >"$work/ci/$green.json"
runs "$red" completed/cancelled completed/failure >"$work/ci/$red.json"
runs "$slow" in_progress/null >"$work/ci/$slow.1.json"
runs "$slow" completed/success >"$work/ci/$slow.json"
runs "$side" completed/success >"$work/ci/$side.json"

export PATH="$work/bin:$PATH" FAKE_CI="$work/ci" GITHUB_REPOSITORY=owner/repo GITHUB_SHA=$head
export CI_POLL_SECONDS=0 CI_MISSING_SECONDS=0

failures=0
check() { # check <name> <expected exit> <expected output fragment> <tag file contents>
  local name=$1 expected=$2 fragment=$3 status=0
  printf '%s\n' "$4" >"$work/tags"
  output=$("$script" "$work/tags" 2>&1) || status=$?
  if [[ $status != "$expected" || $output != *"$fragment"* ]]; then
    echo "FAIL $name (exit $status, expected $expected)"; echo "$output" | sed 's/^/    /'; failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

check "creates a tag on a green commit" 0 "created v0.1.0-loader at $green" \
  "# comment

v0.1.0-loader $green Loader milestone"
[[ $(git --git-dir="$work/origin.git" rev-parse "refs/tags/v0.1.0-loader^{commit}") == "$green" ]] \
  && echo "ok   origin has the tag" || { echo "FAIL origin has the tag"; failures=$((failures + 1)); }
[[ $(git --git-dir="$work/origin.git" cat-file -p v0.1.0-loader) == *"ci: https://example.invalid/runs/$green/0"* ]] \
  && echo "ok   the tag message links the green ci run" || { echo "FAIL the tag message links the green ci run"; failures=$((failures + 1)); }
check "leaves an existing tag on the same commit" 0 "v0.1.0-loader already points at $green" "v0.1.0-loader $green Loader milestone"
check "never moves a tag" 1 "tags are never moved" "v0.1.0-loader $head Loader milestone"
check "waits for a ci run in progress" 0 "created v0.2.0 at $slow" "v0.2.0 $slow Second"
check "refuses a commit whose ci failed" 1 "did not succeed on $red" "v0.3.0 $red Third"
check "refuses a commit ci never ran on" 1 "never ran on $never" "v0.4.0 $never Fourth"
check "refuses a commit outside the branch" 1 "not in the history of $head" "v0.5.0 $side Fifth"
check "refuses a tag that is not a version" 1 "is not a version tag" "loader $green Bad"
check "refuses an abbreviated SHA" 1 "is not a full commit SHA" "v0.6.0 ${green:0:7} Short"
check "refuses a tag without a message" 1 "has no message" "v0.7.0 $green"
check "keeps going after a bad line" 1 "created v0.8.0 at $green" "v0.8.0-bad x
v0.8.0 $green Eighth"

if (( failures )); then echo "$failures failed"; exit 1; fi
echo "all passed"
