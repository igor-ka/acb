#!/usr/bin/env bash
# Proves the verify.sh contract holds for every declared component. It tests the script's
# PLUMBING, never its checks — which is what makes it stack-agnostic: dispatch, exit codes and
# error propagation are identical in a Swift repository and a Terraform one, while the checks
# themselves have nothing in common.
#
# It runs each verify.sh three times — `--targets`, an unknown target, and one real target with a
# `false` planted as its first statement — and every one of the three exits immediately. Asking
# "does target X dispatch?" by RUNNING target X was the first design and it is wrong for any
# repository whose targets do something: it re-runs the install, the build and the image push
# inside a metadata job on every pull request. The known-target set is read through `--targets`
# instead, which is also stronger — it sees a target the script has and the declaration does not.
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

# The function implementing a target, by the three conventions a real script uses, in this fixed
# and documented order: the skeleton's own prefix; the trailing underscore a script adopts to
# dodge a shell builtin (`test`); the plain name.
#
# It returns the exact string the plant below searches for, not just the name — so discovery and
# patching cannot disagree about what they matched, which is how the plant came to insert nothing
# while the assertion still reported a pass.
target_fn_prefix() {
  local script="$1" name="$2" cand
  for cand in "target_$name" "${name}_" "$name"; do
    if awk -v fn="$cand() {" 'index($0, fn) == 1 { found = 1 } END { exit !found }' "$script"; then
      printf '%s() {\n' "$cand"
      return 0
    fi
  done
  return 1
}

for id in $(jq -r '.components[]?.id' "$ACB_CONFIG"); do
  v="$id/verify.sh"

  # 1. It exists and is executable.
  if [[ -x "$v" ]]; then ok "$id: verify.sh is executable"
  else bad "$id: verify.sh is executable" "missing or not +x"; continue; fi

  # 2. The script's own target list and the declaration agree, in BOTH directions. A declared
  #    target the script does not know is a CI step that cannot run; a target the script knows and
  #    nothing declares is a check nobody calls. Read, never executed.
  declared="$(jq -r --arg i "$id" '.components[]|select(.id==$i)|.targets[]' \
              "$ACB_CONFIG" | LC_ALL=C sort)"
  actual="$( ( cd "$id" && ./verify.sh --targets ) 2>/dev/null | LC_ALL=C sort )"
  if [[ -z "$actual" ]]; then
    bad "$id: --targets agrees with the declaration" \
        "./verify.sh --targets printed nothing — the script does not implement it"
  elif [[ "$declared" == "$actual" ]]; then
    ok "$id: --targets agrees with the declaration"
  else
    bad "$id: --targets agrees with the declaration" \
        "declared [$(echo "$declared" | tr '\n' ' ')] vs --targets [$(echo "$actual" | tr '\n' ' ')]"
  fi

  # 3. An undeclared target is rejected, and rejected distinguishably. Exit 64 means "unknown
  #    target"; 2 is "declared but not implemented yet", and one shared code makes this vacuous.
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
  #    The FIRST declared target is used, and being first is what keeps this cheap: `false` fires
  #    before the body's real work starts, so the run costs nothing however heavy the target is.
  #
  #    The patched copy is written INSIDE the component directory, not in /tmp. The script's own
  #    `cd "$(dirname "$0")"` is what makes its relative paths work, so a copy elsewhere would run
  #    the target against the wrong directory and prove nothing. The original is never written to.
  first="$(jq -r --arg i "$id" '.components[]|select(.id==$i)|.targets[0]' "$ACB_CONFIG")"
  if ! prefix="$(target_fn_prefix "$v" "$first")"; then
    bad "$id: a failure inside '$first' propagates" \
        "no function implements it — tried target_${first}(), ${first}_() and ${first}(). Name it one of those."
    continue
  fi
  tmp="$id/.acb-conformance.sh"
  # Injected INSIDE the opening brace, not printed on the following line. `install() { run npm ci; }`
  # is a complete definition on one line, and a `false` printed after it lands at file scope: it
  # runs at definition time and aborts the script before dispatch — a non-zero exit for entirely
  # the wrong reason. Rewriting the brace is correct for both shapes and needs no special case.
  awk -v fn="$prefix" '
    !done && index($0, fn) == 1 { sub(/\{/, "{ false;"); done = 1 }
    { print }
  ' "$v" > "$tmp"
  # The plant must have changed something. This is the guard that holds however the naming
  # conventions evolve: a patch that silently inserts nothing produces an assertion that passes
  # vacuously, which is the exact defect this check exists to catch and has exhibited once.
  if cmp -s "$v" "$tmp"; then
    bad "$id: a failure inside '$first' propagates" "the planted 'false' changed nothing"
    continue
  fi
  chmod +x "$tmp"
  ( cd "$id" && "./$(basename "$tmp")" "$first" >/dev/null 2>&1 ); rc=$?
  if [[ $rc -ne 0 ]]; then ok "$id: a failure inside '$first' propagates"
  else bad "$id: a failure inside '$first' propagates" "exit 0 with a planted 'false'"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
