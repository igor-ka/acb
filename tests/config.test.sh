#!/usr/bin/env bash
# Unit tests for lib/config.sh. The config is the contract every later command reads, so a
# malformed one must fail loudly here rather than produce an empty component list three commands
# later — which would render an empty CI workflow and look like success.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=lib/config.sh
source lib/config.sh

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s — %s\n' "$1" "$2"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
write_cfg() { printf '%s' "$1" > "$TMP/.acb.json"; }

# asserts_validate <name> <expected-exit> <json>
asserts_validate() {
  local name="$1" want="$2" json="$3" got out
  write_cfg "$json"
  out="$(ACB_CONFIG="$TMP/.acb.json" acb_config_validate 2>&1)"; got=$?
  if [[ "$got" -eq "$want" ]]; then ok "$name"
  else bad "$name" "expected exit ${want}, got ${got}: ${out}"; fi
}

VALID='{"template":{"repo":"igor-ka/acb","commit":"abc"},
        "process":{"doc":"docs/sdlc.md","watched":["^scripts/"],
                   "prShapeHatch":"[multi-child]","sdlcSyncHatch":"[skip-sdlc-sync]",
                   "dependabotEcosystems":["npm_and_yarn"]},
        "components":[{"id":"backend","checkName":"Backend checks",
                       "runner":"ubuntu-latest","targets":["lint","test"]}]}'

asserts_validate "accepts a complete config"           0 "$VALID"
asserts_validate "accepts zero components"             0 "$(jq -c '.components=[]' <<<"$VALID")"
asserts_validate "rejects invalid JSON"                1 '{ not json'
asserts_validate "rejects a missing process block"     1 "$(jq -c 'del(.process)' <<<"$VALID")"
asserts_validate "rejects a duplicate component id"    1 "$(jq -c '.components += .components' <<<"$VALID")"
asserts_validate "rejects an empty checkName"          1 "$(jq -c '.components[0].checkName=""' <<<"$VALID")"
asserts_validate "rejects a component with no targets" 1 "$(jq -c '.components[0].targets=[]' <<<"$VALID")"
# A missing file is its own case: point ACB_CONFIG somewhere that does not exist.
out="$(ACB_CONFIG="$TMP/nope.json" acb_config_validate 2>&1)"; got=$?
if [[ "$got" -eq 1 && "$out" == *"no "* ]]; then ok "rejects a missing config file"
else bad "rejects a missing config file" "expected exit 1, got ${got}: ${out}"; fi

# Accessors. An `asserts_eq` helper rather than `[[ … ]] && ok || bad`: that idiom is not
# if-then-else — if `ok` ever fails, `bad` runs too and the case reports both ways.
# asserts_eq <name> <expected> <actual>
asserts_eq() {
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

write_cfg "$VALID"
export ACB_CONFIG="$TMP/.acb.json"
asserts_eq "acb_components lists ids"      "backend"           "$(acb_components)"
asserts_eq "acb_targets lists targets"     "lint test "        "$(acb_targets backend | tr '\n' ' ')"
asserts_eq "acb_check_name reads checkName" "Backend checks"   "$(acb_check_name backend)"
asserts_eq "acb_runner defaults sensibly"  "ubuntu-latest"     "$(acb_runner backend)"
asserts_eq "acb_process reads a scalar"    "docs/sdlc.md"      "$(acb_process doc)"
asserts_eq "acb_process_arr reads an array" "npm_and_yarn"     "$(acb_process_arr dependabotEcosystems)"
asserts_eq "acb_template reads the repo"   "igor-ka/acb"       "$(acb_template repo)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
