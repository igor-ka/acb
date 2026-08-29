#!/usr/bin/env bash
# Proves the verify.sh contract holds for every declared component. It tests the script's
# PLUMBING, never its checks — which is what makes it stack-agnostic: dispatch, exit codes and
# error propagation are identical in a Swift repository and a Terraform one, while the checks
# themselves have nothing in common.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

ACB_CONFIG="${ACB_CONFIG:-.acb.json}"
if [[ ! -f "$ACB_CONFIG" ]]; then
  echo "✗ no $ACB_CONFIG — this check needs one." >&2
  exit 1
fi

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s — %s\n' "$1" "$2"; }

# One trap for the whole run. A trap set inside the loop is replaced on every iteration, so all
# but the last patched copy would survive a failure.
trap 'rm -f ./*/.acb-conformance.sh' EXIT

for id in $(jq -r '.components[]?.id' "$ACB_CONFIG"); do
  v="$id/verify.sh"

  # 1. It exists and is executable.
  if [[ -x "$v" ]]; then ok "$id: verify.sh is executable"
  else bad "$id: verify.sh is executable" "missing or not +x"; continue; fi

  # 2. Every declared target dispatches. Exit 64 means "unknown target"; anything else — including
  #    2 for not-implemented and 1 for a genuine failure — means the target was found.
  for t in $(jq -r --arg i "$id" '.components[]|select(.id==$i)|.targets[]' "$ACB_CONFIG"); do
    ( cd "$id" && ./verify.sh "$t" >/dev/null 2>&1 ); rc=$?
    if [[ $rc -ne 64 ]]; then ok "$id: target '$t' dispatches"
    else bad "$id: target '$t' dispatches" "exit 64 — the script does not know this target"; fi
  done

  # 3. An undeclared target is rejected, and rejected distinguishably.
  ( cd "$id" && ./verify.sh __no_such_target__ >/dev/null 2>&1 ); rc=$?
  if [[ $rc -eq 64 ]]; then ok "$id: unknown target exits 64"
  else bad "$id: unknown target exits 64" "got $rc"; fi

  # 4. A failure inside a target propagates to the script's exit status.
  #
  #    Be precise about what this proves, because the tempting overclaim is wrong. It plants a
  #    `false` as the first statement of the target body and requires a non-zero exit. That
  #    catches the two structural ways a target can become unable to fail: a body running without
  #    `errexit`, where an early failure is ignored and a later success sets the status; and a
  #    dispatcher that swallows the target's status (`"target_$1" || true`).
  #
  #    It does NOT prove an individual check can fail. `grep -q x file || true` inside the body
  #    still exits 0 on its own, and this assertion will not see it — detecting that needs
  #    mutation of the checks themselves, which is a different tool. Reviewers catch those; this
  #    catches the plumbing that would silence all of them at once.
  #
  #    The patched copy is written INSIDE the component directory, not in /tmp. The script's own
  #    `cd "$(dirname "$0")"` is what makes its relative paths work, so a copy elsewhere would run
  #    the target against the wrong directory and prove nothing. The original is never written to.
  first="$(jq -r --arg i "$id" '.components[]|select(.id==$i)|.targets[0]' "$ACB_CONFIG")"
  tmp="$id/.acb-conformance.sh"
  awk -v fn="target_${first}() {" 'index($0, fn) == 1 { print; print "  false"; next } { print }' \
      "$v" > "$tmp"
  chmod +x "$tmp"
  ( cd "$id" && "./$(basename "$tmp")" "$first" >/dev/null 2>&1 ); rc=$?
  if [[ $rc -ne 0 ]]; then ok "$id: a failure inside '$first' propagates"
  else bad "$id: a failure inside '$first' propagates" "exit 0 with a planted 'false'"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
