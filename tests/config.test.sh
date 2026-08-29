#!/usr/bin/env bash
# Unit tests for lib/config.sh. The config is the contract every later command reads, so a
# malformed one must fail loudly here rather than produce an empty component list three commands
# later — which would render an empty CI workflow and look like success.
set -uo pipefail
cd "$(dirname "$0")/.."
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

# Accessors
write_cfg "$VALID"
export ACB_CONFIG="$TMP/.acb.json"
[[ "$(acb_components)" == "backend" ]] \
  && ok "acb_components lists ids" || bad "acb_components lists ids" "got '$(acb_components)'"
[[ "$(acb_targets backend | tr '\n' ' ')" == "lint test " ]] \
  && ok "acb_targets lists targets" || bad "acb_targets lists targets" "got '$(acb_targets backend)'"
[[ "$(acb_check_name backend)" == "Backend checks" ]] \
  && ok "acb_check_name reads checkName" || bad "acb_check_name reads checkName" "got '$(acb_check_name backend)'"
[[ "$(acb_runner backend)" == "ubuntu-latest" ]] \
  && ok "acb_runner defaults sensibly" || bad "acb_runner defaults sensibly" "got '$(acb_runner backend)'"
[[ "$(acb_process doc)" == "docs/sdlc.md" ]] \
  && ok "acb_process reads a scalar" || bad "acb_process reads a scalar" "got '$(acb_process doc)'"
[[ "$(acb_process_arr dependabotEcosystems)" == "npm_and_yarn" ]] \
  && ok "acb_process_arr reads an array" || bad "acb_process_arr reads an array" "got '$(acb_process_arr dependabotEcosystems)'"
[[ "$(acb_template repo)" == "igor-ka/acb" ]] \
  && ok "acb_template reads the repo" || bad "acb_template reads the repo" "got '$(acb_template repo)'"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
