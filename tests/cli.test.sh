#!/usr/bin/env bash
# Exit codes are part of the contract: 0 success, 1 operational failure, 2 usage error, 3 refusal
# by design. A caller — often an agent following CLAUDE.md rather than a human reading stderr —
# distinguishes "you typed it wrong" from "I declined" on the code alone.
set -uo pipefail
cd "$(dirname "$0")/.."

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s — %s\n' "$1" "$2"; }

# asserts <name> <expected-exit> <needle> <args...>
asserts() {
  local name="$1" want="$2" needle="$3"; shift 3
  local out got
  out="$(./bin/acb "$@" 2>&1)"; got=$?
  if [[ "$got" -eq "$want" && "$out" == *"$needle"* ]]; then ok "$name"
  else bad "$name" "expected exit ${want} containing '${needle}', got ${got}: ${out}"; fi
}

asserts "no arguments prints usage"      2 "usage: acb"
asserts "unknown subcommand exits 2"     2 "unknown command 'frobnicate'" frobnicate
asserts "--help exits 0"                 0 "usage: acb" --help
asserts "status outside an acb repo"     1 "run 'acb init' first" status
asserts "init is not implemented yet"    1 "not implemented until ACB-4" init /tmp/nowhere
asserts "pull is not implemented yet"    1 "not implemented until ACB-5" pull

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
