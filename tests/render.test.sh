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

# --targets is how the conformance check learns what a script knows without running anything.
# Introspection, not execution: asking "does target X dispatch?" by running target X re-runs the
# whole build inside a metadata job for any repository whose targets do something.
#
# ACB_CONFIG and the `api` component come from the fixture this file exports at the top; `api`
# declares ["lint","test"].
t="$(mktemp -d)"
acb_render_verify api > "$t/verify.sh"
chmod +x "$t/verify.sh"
got="$("$t/verify.sh" --targets | tr '\n' ' ')"
if [[ "$got" == "lint test " ]]; then ok "the skeleton lists its targets"
else bad "the skeleton lists its targets" "expected 'lint test ', got '$got'"; fi

# `acb init` writes CLAUDE.md, ci.yml, the ruleset and every component's verify.sh
# unconditionally. Run a second time on a repository that has been adopted and filled in, it
# replaces all of them with skeletons — and the generated apply-ruleset.sh header used to tell
# operators to do exactly that. A recorded template commit is the signal that init has already run.
i="$(mktemp -d)"
( cd "$i" && git init -q -b main )
cat > "$i/.acb.json" <<'JSON'
{ "template": { "repo": "igor-ka/acb", "commit": "deadbeef" },
  "process": { "doc": "docs/sdlc.md", "watched": ["^scripts/"] },
  "components": [ { "id": "app", "checkName": "App checks", "targets": ["lint"] } ] }
JSON
printf 'a real CLAUDE.md a consumer wrote by hand\n' > "$i/CLAUDE.md"
out="$( acb_cmd_init "$i" 2>&1 )"; rc=$?
if [[ $rc -eq 3 && "$out" == *"already initialised"* ]]; then
  ok "init refuses an already-initialised repository"
else bad "init refuses an already-initialised repository" "exit $rc: $out"; fi
if grep -q 'a real CLAUDE.md' "$i/CLAUDE.md"; then ok "init left the consumer's CLAUDE.md alone"
else bad "init left the consumer's CLAUDE.md alone" "it was overwritten with the template"; fi

# A fresh directory still initialises — the guard keys on the recorded commit, not on the file.
f="$(mktemp -d)"
out="$( acb_cmd_init "$f" 2>&1 )"; rc=$?
if [[ $rc -eq 0 && -f "$f/CLAUDE.md" ]]; then ok "a fresh directory still initialises"
else bad "a fresh directory still initialises" "exit $rc: $out"; fi

# The scaffolded watched list is what every new consumer starts from, and nothing tested it: the
# only assertion for the pattern lived in check-sdlc-sync.test.sh's own hand-written fixture, a
# second copy. Drop the pattern from the scaffold and that suite stays green while every repository
# initialised afterwards ships an ungoverned tree. The source here is MANIFEST, not a copy.
w="$(mktemp -d)"
( cd "$w" && acb_scaffold_config >/dev/null 2>&1 )
scaf="$(jq -r '[.process.watched[]] | join("|")' "$w/.acb.json" 2>/dev/null)"
# Without this the block passes vacuously if the scaffold ever fails: grep -qE "" matches anything.
if [[ -z "$scaf" ]]; then bad "the scaffold writes a watched list" "acb_scaffold_config produced none"; fi
# A sed that yields no trees would drop every assertion below and move only the total count — the
# mutant this block survived when it was first written. Counted, so silence is a failure.
trees=0
while read -r d; do
  [[ -n "$d" && -n "$scaf" ]] || continue
  [[ "$d" == */ ]] && probe="${d}probe.md" || probe="$d"
  trees=$((trees + 1))
  if grep -qE "$scaf" <<<"$probe"; then ok "the scaffold watches $d"
  else bad "the scaffold watches $d" "no process.watched pattern matches the carried tree"; fi
done < <(sed -n -e 's|^\(\.claude/[^/]*\)/.*|\1/|p' -e 's|^\(\.claude/[^/]*\)$|\1|p' \
           MANIFEST | LC_ALL=C sort -u)
if [[ "$trees" -gt 0 ]]; then ok "the carried tree enumeration is not empty"
else bad "the carried tree enumeration is not empty" "the sed matched no MANIFEST path — every assertion above was skipped"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
