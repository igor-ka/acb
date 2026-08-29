#!/usr/bin/env bash
# Reader and validator for .acb.json. Sourced by bin/acb and by the carried gate scripts.
#
# Every accessor reads the file rather than caching into globals: the gate scripts are one-shot
# CI invocations where a cache buys nothing, and a stale cache in a long-running command is a
# class of bug this does not need to have.

# The canonical target vocabulary. Reserved names; extras are allowed, so this list is not used to
# reject unknown targets — only to document what the names mean and to let `acb init` order the
# generated CI steps sensibly.
# shellcheck disable=SC2034  # consumed by lib/render.sh from PR 4 onward
ACB_CANONICAL_TARGETS="install audit lint format typecheck test test:integration build package migrate publish eval selftest"

acb_config_path() { printf '%s' "${ACB_CONFIG:-.acb.json}"; }

acb_config_validate() {
  local f; f="$(acb_config_path)"
  if [[ ! -f "$f" ]]; then
    echo "✗ no $f here — run 'acb init' first, or cd to a repository that has one." >&2
    return 1
  fi
  if ! jq -e . "$f" >/dev/null 2>&1; then
    echo "✗ $f is not valid JSON." >&2
    return 1
  fi
  local problem
  # One jq expression, so every problem is reported in one pass rather than one per run.
  problem="$(jq -r '
    [ (if (.template.repo   | type) != "string" then "template.repo must be a string"   else empty end),
      (if (.process.doc     | type) != "string" then "process.doc must be a string"     else empty end),
      (if (.process.watched | type) != "array"  then "process.watched must be an array" else empty end),
      (if (.components | type) != "array" then "components must be an array (use [] for none)" else empty end),
      (([.components[]?.id] | length) as $n
        | ([.components[]?.id] | unique | length) as $u
        | if $n != $u then "component ids must be unique" else empty end),
      (.components[]? | select((.checkName // "") == "") | "component \(.id // "?") has no checkName"),
      (.components[]? | select(((.targets // []) | length) == 0) | "component \(.id // "?") declares no targets")
    ] | join("\n")' "$f" 2>/dev/null)"
  if [[ -n "$problem" ]]; then
    printf '✗ %s is invalid:\n' "$f" >&2
    printf '%s\n' "$problem" | sed 's/^/    /' >&2
    return 1
  fi
  return 0
}

acb_components()  { jq -r '.components[]?.id' "$(acb_config_path)"; }
acb_targets()     { jq -r --arg id "$1" '.components[] | select(.id == $id) | .targets[]' "$(acb_config_path)"; }
acb_check_name()  { jq -r --arg id "$1" '.components[] | select(.id == $id) | .checkName' "$(acb_config_path)"; }
acb_runner()      { jq -r --arg id "$1" '.components[] | select(.id == $id) | .runner // "ubuntu-latest"' "$(acb_config_path)"; }
acb_process()     { jq -r --arg k "$1" '.process[$k] // ""' "$(acb_config_path)"; }
acb_process_arr() { jq -r --arg k "$1" '.process[$k][]?' "$(acb_config_path)"; }
acb_template()    { jq -r --arg k "$1" '.template[$k] // ""' "$(acb_config_path)"; }
