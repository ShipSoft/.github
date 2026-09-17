#!/usr/bin/env bash
#
# Bring ShipSoft repository settings in line with the canonical config in this
# directory: merge-method toggles, and the "main-1"/"main-2" branch rulesets
# that give every repo a merge queue, a review requirement and a linear
# history.
#
# Dry-run by default; --apply writes. Re-running is safe and is also the drift
# check. Needs `gh` authenticated as a user with admin on the target repos, and
# `jq`. GITHUB_TOKEN inside Actions cannot write another repo's rulesets, so
# this is meant to be run by hand.
#
# SPDX-FileCopyrightText: CERN for the benefit of the SHiP Collaboration
# SPDX-License-Identifier: LGPL-3.0-or-later
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config=$here/repos.json
org=$(jq -r .org "$config")

apply=false
only=()

usage() {
  cat >&2 <<EOF
usage: ${0##*/} [--apply] [--repo NAME]...

  --apply       write changes (default is a dry run that only prints the diff)
  --repo NAME   limit to one repository; repeatable
EOF
  exit "${1:-2}"
}

while [ $# -gt 0 ]; do
  case $1 in
    --apply) apply=true ;;
    --repo) shift; [ $# -gt 0 ] || usage; only+=("$1") ;;
    -h|--help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
  shift
done

# Strip the fields GitHub adds on read (ids, timestamps, links) and impose a
# stable ordering, so a desired ruleset and a live one can be compared directly.
normalise_ruleset() {
  jq -S '{
    name,
    target,
    enforcement,
    bypass_actors: ((.bypass_actors // [])
      | map({actor_id, actor_type, bypass_mode})
      | sort_by(.actor_type, (.actor_id // -1))),
    conditions: {ref_name: {
      include: (.conditions.ref_name.include // [] | sort),
      exclude: (.conditions.ref_name.exclude // [] | sort)}},
    rules: (.rules | map({type, parameters: (.parameters // null)}) | sort_by(.type))
  }'
}

# The review ruleset is the only per-repo variation: which checks are required,
# and whether a code-owner review is needed.
render_review() {
  local tier=$1 codeowners=$2
  jq --arg tier "$tier" --argjson codeowners "$codeowners" '
    .rules |= map(
      if .type == "pull_request"
      then .parameters.require_code_owner_review = $codeowners
      else . end)
    | if $tier == "none" then
        .rules |= map(select(.type != "required_status_checks"))
      elif $tier == "single" then
        .rules |= map(if .type == "required_status_checks" then
          .parameters.required_status_checks |=
            map(select(.context == "All checks passed"))
        else . end)
      else . end
  ' "$here/ruleset-review.json"
}

required_contexts() {
  jq -r '(.rules[] | select(.type == "required_status_checks")
          | .parameters.required_status_checks[].context) // empty'
}

# Resolve the workflow file that produced a check run on the default branch, by
# way of its check suite. Only a workflow living in the repository itself can be
# read back, and a run is reported as "owner/repo/.github/workflows/x.yml@ref"
# when it belongs elsewhere, so the ref and our own prefix are trimmed off and
# anything still pointing at another repository is dropped rather than resolved
# against a same-named file here. Prints nothing when nothing is resolvable,
# which the caller treats as a failure.
workflow_for_context() {
  local repo=$1 ctx=$2 runs_json=$3 suite
  suite=$(jq -r --arg c "$ctx" \
    'first(.check_runs[] | select(.name == $c) | .check_suite.id) // empty' <<<"$runs_json")
  [ -n "$suite" ] || return 0
  gh api "repos/$org/$repo/actions/runs?check_suite_id=$suite" 2>/dev/null |
    jq -r --arg prefix "$org/$repo/" '
      .workflow_runs[].path
      | sub("@[^@]*$"; "")
      | if startswith(".github/") then .
        elif startswith($prefix) then ltrimstr($prefix)
        else empty end' 2>/dev/null || true
}

# A workflow that does not trigger on merge_group never reports inside the
# queue, so a pull request sits there until check_response_timeout_minutes.
# Matched by grep rather than parsed: this script depends on gh and jq alone,
# and no YAML parser is available. Both the block form and the flow form
# (on: [push, pull_request, merge_group]) match. A merge_group mentioned only
# in a comment would pass, which is the accepted limit of the check.
workflow_has_merge_group() {
  local repo=$1 path=$2 branch=$3
  gh api -H "Accept: application/vnd.github.raw" \
    "repos/$org/$repo/contents/$path?ref=$branch" 2>/dev/null |
    grep -qE '^[[:space:]]+merge_group:|^.?on.?:.*\[.*merge_group'
}

changed=0
blocked=0

for repo in $(jq -r '.repos | keys[]' "$config"); do
  if [ ${#only[@]} -gt 0 ] && ! printf '%s\n' "${only[@]}" | grep -Fxq "$repo"; then
    continue
  fi

  tier=$(jq -r --arg r "$repo" '.repos[$r].tier' "$config")
  codeowners=$(jq -r --arg r "$repo" '.repos[$r].codeowners' "$config")
  echo "=== $org/$repo (tier: $tier, codeowners: $codeowners)"

  repo_json=$(gh api "repos/$org/$repo")
  default_branch=$(jq -r .default_branch <<<"$repo_json")

  # 1. Merge-method toggles.
  settings_diff=$(jq -n --argjson live "$repo_json" --slurpfile want "$here/repo-settings.json" '
    $want[0] | to_entries
    | map(select($live[.key] != .value) | "\(.key): \($live[.key]) -> \(.value)")
    | .[]' -r)
  if [ -n "$settings_diff" ]; then
    changed=1
    echo "$settings_diff" | sed 's/^/  settings  /'
    if $apply; then
      gh api --method PATCH "repos/$org/$repo" --input "$here/repo-settings.json" >/dev/null
      echo "  settings  applied"
    fi
  fi

  # 2. Gate. Work out the review ruleset first: if a required check cannot
  #    actually gate the queue, no protection may be touched below, because
  #    removing the superseded rules would leave the branch unprotected with
  #    no replacement to create.
  want_review=$(render_review "$tier" "$codeowners")
  missing=()
  unqueued=()
  if [ "$tier" != none ]; then
    check_runs=$(gh api "repos/$org/$repo/commits/$default_branch/check-runs?per_page=100" \
                   2>/dev/null || echo '{"check_runs":[]}')
    seen=$(jq -r '.check_runs[].name' <<<"$check_runs")
    while IFS= read -r ctx; do
      [ -n "$ctx" ] || continue
      if ! grep -Fxq "$ctx" <<<"$seen"; then
        missing+=("$ctx")
        continue
      fi
      found=false
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        found=true
        workflow_has_merge_group "$repo" "$path" "$default_branch" ||
          unqueued+=("$ctx ($path)")
      done < <(workflow_for_context "$repo" "$ctx" "$check_runs")
      # No workflow resolved is not a pass. The trigger cannot be confirmed, and
      # a required context that never reports inside the queue is exactly what
      # this gate exists to catch.
      $found || unqueued+=("$ctx (no workflow found)")
    done < <(required_contexts <<<"$want_review")
  fi
  if [ ${#missing[@]} -gt 0 ] || [ ${#unqueued[@]} -gt 0 ]; then
    blocked=1
    [ ${#missing[@]} -eq 0 ] ||
      echo "  BLOCKED   never reported on $default_branch: ${missing[*]}"
    [ ${#unqueued[@]} -eq 0 ] ||
      echo "  BLOCKED   reported but no confirmed merge_group trigger: ${unqueued[*]}"
    echo "            add the aggregator job and a merge_group: trigger first;"
    echo "            leaving this repo's rulesets untouched"
    continue
  fi

  # 3. Rulesets. Only branch rulesets scoped to the default branch are ours to
  #    replace. Tag, push and release rulesets, anything targeting a wider set
  #    of branches, and rulesets inherited from the organisation belong to
  #    whoever created them, so they are reported and left alone.
  live_rulesets=$(gh api "repos/$org/$repo/rulesets?includes_parents=false")
  for unmanaged in $(jq -r --arg d "refs/heads/$default_branch" '
      .[] | select(.name != "main-1" and .name != "main-2")
          | select(.target != "branch" or
              (((.conditions.ref_name.include // []) - ["~DEFAULT_BRANCH", $d]) | length) > 0)
          | "\(.id):\(.name)"' <<<"$live_rulesets"); do
    echo "  ruleset   ${unmanaged#*:} (${unmanaged%%:*}) -> unmanaged, left in place"
  done
  # An empty include list matches nothing, which is how Geometry's legacy
  # ruleset ended up inert; it is still ours to clear.
  stale_ids=()
  for stale in $(jq -r --arg d "refs/heads/$default_branch" '
      .[] | select(.name != "main-1" and .name != "main-2")
          | select(.target == "branch")
          | select((((.conditions.ref_name.include // []) - ["~DEFAULT_BRANCH", $d]) | length) == 0)
          | "\(.id):\(.name)"' <<<"$live_rulesets"); do
    changed=1
    echo "  ruleset   ${stale#*:} (${stale%%:*}) -> delete (superseded)"
    stale_ids+=("${stale%%:*}")
  done

  for name in main-1 main-2; do
    if [ "$name" = main-1 ]; then
      want=$(cat "$here/ruleset-protect.json")
    else
      want=$want_review
    fi

    id=$(jq -r --arg n "$name" '.[] | select(.name == $n) | .id' <<<"$live_rulesets")
    if [ -n "$id" ]; then
      live=$(gh api "repos/$org/$repo/rulesets/$id" | normalise_ruleset)
      if [ "$live" = "$(normalise_ruleset <<<"$want")" ]; then
        echo "  ruleset   $name up to date"
        continue
      fi
      changed=1
      diff -u --label "live/$name" --label "want/$name" \
        <(echo "$live") <(normalise_ruleset <<<"$want") | sed 's/^/  /' || true
      if $apply; then
        gh api --method PUT "repos/$org/$repo/rulesets/$id" --input - <<<"$want" >/dev/null
        echo "  ruleset   $name updated"
      fi
    else
      changed=1
      echo "  ruleset   $name -> create"
      if $apply; then
        gh api --method POST "repos/$org/$repo/rulesets" --input - <<<"$want" >/dev/null
        echo "  ruleset   $name created"
      fi
    fi
  done

  # The superseded rulesets go now rather than before the loop above, for the
  # same reason classic protection goes last: set -e aborts on a failed create
  # or update, and an obsolete ruleset left standing beats no protection at all.
  if $apply && [ ${#stale_ids[@]} -gt 0 ]; then
    for stale_id in "${stale_ids[@]}"; do
      gh api --method DELETE "repos/$org/$repo/rulesets/$stale_id"
    done
  fi

  # 4. Classic branch protection stacks on top of rulesets and the union is
  #    enforced, so leaving it in place hides rules we are not managing. It is
  #    removed last: set -e aborts above on a failed create or update, so a
  #    failure leaves the old protection standing rather than stripping it with
  #    nothing to replace it.
  if gh api "repos/$org/$repo/branches/$default_branch/protection" >/dev/null 2>&1; then
    changed=1
    echo "  classic   branch protection on $default_branch -> delete"
    if $apply; then
      gh api --method DELETE "repos/$org/$repo/branches/$default_branch/protection"
      echo "  classic   deleted"
    fi
  fi
done

if [ $blocked -ne 0 ]; then
  echo
  echo "Some repositories are missing their required checks; see BLOCKED above." >&2
  exit 1
fi
if ! $apply && [ $changed -ne 0 ]; then
  echo
  echo "Dry run: nothing written. Re-run with --apply."
fi
