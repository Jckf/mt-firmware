#!/usr/bin/env bash
# Usage: sync.sh <builds.json> <firmware checkout>
#
# Rebases every patch branch in builds.json onto upstream and force-pushes the ones that moved.
# The fork's own develop is never pushed: that would start upstream's full CI matrix in the fork. Writes to $GITHUB_OUTPUT:
#   builds   - matrix entries {branch, suffix, sha, platform, pio_env} for branches to build
#   releases - one entry per branch to build {branch, suffix, description, sha, short, upstream, count}
#   failed - patch branches that no longer rebase cleanly
#
# Env: UPSTREAM_REPO, UPSTREAM_BRANCH, ONLY_BRANCH (optional), FORCE_BUILD (true/false), GH_TOKEN
set -euo pipefail

config=$(realpath "$1")
cd "$2"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git remote add upstream "${UPSTREAM_URL:-https://github.com/${UPSTREAM_REPO}.git}"
git fetch --no-tags upstream "$UPSTREAM_BRANCH"
base=upstream/$UPSTREAM_BRANCH

builds='[]'
releases='[]'
failed='[]'
upstream_sha=$(git rev-parse "$base")

while read -r entry <&3; do
  branch=$(jq -r .branch <<<"$entry")
  [[ -n "${ONLY_BRANCH:-}" && "$branch" != "$ONLY_BRANCH" ]] && continue

  echo "::group::$branch"
  git fetch --no-tags origin "$branch"
  git checkout -q -B work FETCH_HEAD
  before=$(git rev-parse HEAD)
  changed=false
  ok=true

  if git merge-base --is-ancestor "$base" HEAD; then
    echo "$branch is already on top of $base"
  elif git rebase "$base"; then
    git push --force-with-lease="$branch:$before" origin "HEAD:refs/heads/$branch"
    changed=true
  else
    git rebase --abort
    ok=false
    failed=$(jq -c --arg b "$branch" '. + [$b]' <<<"$failed")
    title="$branch no longer rebases onto $UPSTREAM_REPO $UPSTREAM_BRANCH"
    # Issues are off by default on forks; the failed run is the notification then.
    open=$(gh issue list --state open --search "in:title \"$title\"" --json number --jq length 2>/dev/null) || open=skip
    if [[ "$open" == 0 ]]; then
      gh issue create --title "$title" --body "Upstream $(git rev-parse --short "$base") conflicts with $branch. Run: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" ||
        echo "::warning::could not open an issue"
    fi
    echo "::error::$branch does not rebase cleanly onto $base"
  fi
  echo "::endgroup::"

  if [[ "$ok" == true && ("$changed" == true || "${FORCE_BUILD:-false}" == true) ]]; then
    sha=$(git rev-parse HEAD)
    # Same abbreviation as bin/readprops.py, so the release job can find the artifacts by version.
    short=$(git rev-parse --short=7 HEAD)
    builds=$(jq -c --argjson e "$entry" --arg sha "$sha" \
      '. + [$e.targets[] | {branch: $e.branch, suffix: $e.suffix, sha: $sha, platform, pio_env}]' <<<"$builds")
    releases=$(jq -c --argjson e "$entry" --arg sha "$sha" --arg short "$short" --arg up "$upstream_sha" \
      '. + [{branch: $e.branch, suffix: $e.suffix, description: ($e.description // ""), sha: $sha, short: $short, upstream: $up, count: ($e.targets | length)}]' <<<"$releases")
  fi
done 3< <(jq -c '.[]' "$config")

echo "builds=$builds" >>"$GITHUB_OUTPUT"
echo "releases=$releases" >>"$GITHUB_OUTPUT"
echo "failed=$failed" >>"$GITHUB_OUTPUT"
