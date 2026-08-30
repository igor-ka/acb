#!/usr/bin/env bash
# The conformance check's fourth assertion — that a failure inside a target reaches the script's
# exit status — is the one that earns the script. An assertion that cannot fail is exactly what it
# exists to catch, so it is itself checked here against fixtures built to defeat it.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/check-conformance.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s — %s\n' "$1" "$2"; }

# The fixture is parameterised through these globals rather than positional arguments: a case sets
# only what it is about, and reads as a sentence.
FX_SET='set -euo pipefail'                    # the errexit line
FX_DISPATCH='"target_${1}"'                   # how the dispatcher calls the function
FX_FNDEF='target_lint() {
  true
}'                                            # the function definition, verbatim
FX_TARGETS='lint'                             # what the script's TARGETS holds
FX_DECLARED='["lint"]'                        # what .acb.json declares
FX_TARGETS_ARM='echo "$TARGETS" | tr " " "\n"; exit 0'   # the --targets implementation

fx_reset() {
  FX_SET='set -euo pipefail'
  FX_DISPATCH='"target_${1}"'
  FX_FNDEF='target_lint() {
  true
}'
  FX_TARGETS='lint'
  FX_DECLARED='["lint"]'
  FX_TARGETS_ARM='echo "$TARGETS" | tr " " "\n"; exit 0'
}

build_fixture() {
  local d="$1"
  mkdir -p "$d/app" "$d/scripts"
  cat > "$d/.acb.json" <<JSON
{ "template": { "repo": "example/repo", "commit": "0" },
  "process": { "doc": "docs/sdlc.md", "watched": ["^scripts/"] },
  "components": [ { "id": "app", "checkName": "App checks", "targets": $FX_DECLARED } ] }
JSON
  # An UNQUOTED heredoc, so the FX_* values are substituted — but only once. A '$TARGETS' inside
  # one of those values is written to the file literally, which is what the fixture wants.
  cat > "$d/app/verify.sh" <<EOS
#!/usr/bin/env bash
${FX_SET}
cd "\$(dirname "\$0")"
TARGETS="${FX_TARGETS}"
if [[ "\${1:-}" == "--targets" ]]; then ${FX_TARGETS_ARM}; fi
${FX_FNDEF}
case "\${1:-all}" in
  *) if [[ " \$TARGETS " == *" \${1:-} "* ]]; then ${FX_DISPATCH}; else exit 64; fi ;;
esac
EOS
  chmod +x "$d/app/verify.sh"
  cp "$SCRIPT" "$d/scripts/"
}

run_fixture() {
  local d; d="$(mktemp -d)"
  build_fixture "$d"
  out="$( cd "$d" && ./scripts/check-conformance.sh 2>&1 )"; rc=$?
}

# 1. Wired correctly: errexit on, dispatcher passes the status through.
fx_reset
run_fixture
if [[ $rc -eq 0 ]]; then ok "a correctly wired verify.sh conforms"
else bad "a correctly wired verify.sh conforms" "exit $rc: $out"; fi

# 2. No errexit. The planted `false` is followed by `true`, so without errexit the body's status
#    is the LAST command's and the failure vanishes. This is how a target with several checks
#    silently reports green after the first one fails.
fx_reset; FX_SET='set -uo pipefail'
run_fixture
if [[ $rc -ne 0 && "$out" == *"propagates"* ]]; then ok "a body running without errexit is caught"
else bad "a body running without errexit is caught" "expected non-zero naming 'propagates', got $rc: $out"; fi

# 3. A dispatcher that swallows the target's status. errexit is on and the body is fine; the
#    silencing happens one level up, which is the harder of the two to notice by reading.
# shellcheck disable=SC2016  # the ${…} is fixture content written into a generated script
fx_reset; FX_DISPATCH='"target_${1}" || true'
run_fixture
if [[ $rc -ne 0 && "$out" == *"propagates"* ]]; then ok "a dispatcher swallowing the status is caught"
else bad "a dispatcher swallowing the status is caught" "expected non-zero naming 'propagates', got $rc: $out"; fi

# 4. The bare `<name>()` convention. A script that never adopted the target_ prefix is still
#    conformant; the check discovers the name rather than dictating it.
# shellcheck disable=SC2016  # fixture content
fx_reset
FX_FNDEF='lint() {
  true
}'
FX_DISPATCH='"${1}"'
run_fixture
if [[ $rc -eq 0 ]]; then ok "a bare <name>() function is discovered"
else bad "a bare <name>() function is discovered" "exit $rc: $out"; fi

# 5. The trailing-underscore convention, which a script adopts to dodge the `test` builtin.
# shellcheck disable=SC2016  # fixture content
fx_reset
FX_FNDEF='lint_() {
  true
}'
FX_DISPATCH='"${1}_"'
run_fixture
if [[ $rc -eq 0 ]]; then ok "a <name>_() function is discovered"
else bad "a <name>_() function is discovered" "exit $rc: $out"; fi

# 6. A ONE-LINE function body. The plant must land inside the braces: printed on the following
#    line it sits at file scope, runs at definition time, and aborts the script before dispatch —
#    a non-zero exit for entirely the wrong reason, which is a pass this check must not award.
#    The fixture proves the right one by making the body succeed and the plant the only failure.
# shellcheck disable=SC2016  # fixture content
fx_reset
FX_FNDEF='lint() { true; }'
FX_DISPATCH='"${1}"'
run_fixture
if [[ $rc -eq 0 ]]; then ok "a one-line function body is patched inside the braces"
else bad "a one-line function body is patched inside the braces" "exit $rc: $out"; fi

# 7. No function matches any convention. This must FAIL LOUDLY. The old plant inserted nothing
#    here and the assertion passed on an unrelated exit status — the vacuous pass this check
#    exists to catch, exhibited by the check itself.
# shellcheck disable=SC2016  # fixture content
fx_reset
FX_FNDEF='do_the_lint() {
  true
}'
FX_DISPATCH='do_the_lint'
run_fixture
if [[ $rc -ne 0 && "$out" == *"no function implements"* ]]; then
  ok "an undiscoverable function fails loudly"
else bad "an undiscoverable function fails loudly" "expected non-zero naming 'no function implements', got $rc: $out"; fi

# 8. The script knows a target the declaration does not. A check nobody calls is as much a defect
#    as a step that cannot run, and the old per-target probe could not see this direction at all.
fx_reset; FX_TARGETS='lint format'
FX_FNDEF='target_lint() {
  true
}
target_format() {
  true
}'
run_fixture
# Assert on the FAILURE message, not on "--targets" — that substring is in assertion 2's own
# passing label (`✓ app: --targets agrees with the declaration`), so matching it would reduce this
# case to `rc -ne 0` and let any other assertion's failure satisfy it.
if [[ $rc -ne 0 && "$out" == *"] vs --targets ["* ]]; then ok "an undeclared target the script knows is caught"
else bad "an undeclared target the script knows is caught" "expected non-zero naming '] vs --targets [', got $rc: $out"; fi

# 9. No --targets arm at all: the script predates the contract. Silence must not read as
#    agreement — an empty list would otherwise compare equal to an empty declaration.
fx_reset; FX_TARGETS_ARM='exit 64'
run_fixture
if [[ $rc -ne 0 && "$out" == *"does not implement"* ]]; then ok "a script without --targets is caught"
else bad "a script without --targets is caught" "expected non-zero naming 'does not implement', got $rc: $out"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
