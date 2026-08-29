#!/usr/bin/env bash
# Generation is where one declaration becomes a workflow, a ruleset and a set of skeletons. If
# those three stop agreeing, a required check names a job that does not exist — a failure that
# surfaces at merge time, which is the wrong time.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export ACB_ROOT="$PWD"
# shellcheck source=lib/config.sh
source lib/config.sh
# shellcheck source=lib/render.sh
source lib/render.sh

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s — %s\n' "$1" "$2"; }
asserts_has()  { if grep -q "$2" <<<"$3"; then ok "$1"; else bad "$1" "missing: $2"; fi; }
asserts_lacks(){ if grep -q "$2" <<<"$3"; then bad "$1" "unexpectedly present: $2"; else ok "$1"; fi; }

TMP="$(mktemp -d)"
cat > "$TMP/.acb.json" <<'JSON'
{"template":{"repo":"igor-ka/acb","commit":"abc"},
 "process":{"doc":"docs/sdlc.md","watched":["^scripts/"],
            "prShapeHatch":"[multi-child]","sdlcSyncHatch":"[skip-sdlc-sync]",
            "dependabotEcosystems":["npm_and_yarn"]},
 "components":[{"id":"api","checkName":"API checks","runner":"ubuntu-latest",
                "targets":["lint","test"]},
               {"id":"mobile","checkName":"Mobile checks","runner":"macos-14",
                "targets":["build"]}]}
JSON
export ACB_CONFIG="$TMP/.acb.json"

ci="$(acb_render_ci)"
asserts_has   "renders the first checkName"        'name: API checks'    "$ci"
asserts_has   "renders the second checkName"       'name: Mobile checks' "$ci"
asserts_has   "honours a per-component runner"     'runs-on: macos-14'   "$ci"
asserts_has   "renders a step per target"          'run: ./verify.sh test' "$ci"
asserts_lacks "leaves no unreplaced marker"        '@@'                  "$ci"
# The job name comes from checkName, never the directory — those disagree in real repositories,
# and deriving one from the other silently renames a required check.
asserts_lacks "does not use the directory as a job name" 'name: api$'    "$ci"

rules="$(acb_render_ruleset)"
asserts_lacks "ruleset leaves no marker"           '@@'                  "$rules"
asserts_has   "ruleset enables Copilot review"     'copilot_code_review' "$rules"
if jq -e . <<<"$rules" >/dev/null 2>&1; then ok "ruleset is valid JSON"
else bad "ruleset is valid JSON" "jq rejected it"; fi

# The required checks and the workflow's job names come from one declaration, and this is the
# assertion that keeps them that way.
req="$(jq -r '.rules[]|select(.type=="required_status_checks")|.parameters.required_status_checks[].context' <<<"$rules" | LC_ALL=C sort)"
jobs="$( { grep -oE '^ {4}name: .*' <<<"$ci" | sed 's/.*name: //'; echo "SDLC docs"; echo "PR shape"; } | LC_ALL=C sort)"
if [[ "$req" == "$jobs" ]]; then ok "required checks match the job names"
else bad "required checks match the job names" "$(diff <(echo "$req") <(echo "$jobs") | tr '\n' ' ')"; fi

vs="$(acb_render_verify api)"
asserts_has  "skeleton fails closed"    'exit 2'   "$vs"
asserts_has  "unknown target exits 64"  'exit 64'  "$vs"
# Multi-line bodies are load-bearing: the conformance check plants a statement after the opening
# brace, and against a one-liner that lands after the closing brace where it proves nothing.
if grep -A1 '^target_lint() {$' <<<"$vs" | grep -q 'not_implemented lint'; then
  ok "target bodies are multi-line"
else bad "target bodies are multi-line" "one-liner body would make conformance vacuous"; fi

# Zero components is a supported shape. The right output is NO output: a `jobs:` key with nothing
# under it is a file GitHub rejects, and asserting it renders would lock that in.
jq -c '.components=[]' "$TMP/.acb.json" > "$TMP/empty.json"
empty="$(ACB_CONFIG="$TMP/empty.json" acb_render_ci)"; rc=$?
if [[ $rc -eq 1 && -z "$empty" ]]; then ok "zero components writes no workflow"
else bad "zero components writes no workflow" "exit $rc, output '${empty:0:40}'"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
