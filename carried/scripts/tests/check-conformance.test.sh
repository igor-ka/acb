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

# build_fixture <dir> <set-line> <dispatch-line>
build_fixture() {
  local d="$1" setline="$2" dispatch="$3"
  mkdir -p "$d/app" "$d/scripts"
  cat > "$d/.acb.json" <<'JSON'
{ "template": { "repo": "example/repo", "commit": "0" },
  "process": { "doc": "docs/sdlc.md", "watched": ["^scripts/"] },
  "components": [ { "id": "app", "checkName": "App checks", "targets": ["lint"] } ] }
JSON
  cat > "$d/app/verify.sh" <<EOS
#!/usr/bin/env bash
${setline}
cd "\$(dirname "\$0")"
TARGETS="lint"
target_lint() {
  true
}
case "\${1:-all}" in
  *) if [[ " \$TARGETS " == *" \${1:-lint} "* ]]; then ${dispatch}; else exit 64; fi ;;
esac
EOS
  chmod +x "$d/app/verify.sh"
  cp "$SCRIPT" "$d/scripts/"
}

# run_fixture <set-line> <dispatch-line> -> sets $rc and $out
run_fixture() {
  local d; d="$(mktemp -d)"
  build_fixture "$d" "$1" "$2"
  out="$( cd "$d" && ./scripts/check-conformance.sh 2>&1 )"; rc=$?
}

# 1. Wired correctly: errexit on, dispatcher passes the status through.
run_fixture 'set -euo pipefail' '"target_${1:-lint}"'
if [[ $rc -eq 0 ]]; then ok "a correctly wired verify.sh conforms"
else bad "a correctly wired verify.sh conforms" "exit $rc: $out"; fi

# 2. No errexit. The planted `false` is followed by `true`, so without errexit the body's status
#    is the LAST command's and the failure vanishes. This is how a target with several checks
#    silently reports green after the first one fails.
run_fixture 'set -uo pipefail' '"target_${1:-lint}"'
if [[ $rc -ne 0 && "$out" == *"propagates"* ]]; then ok "a body running without errexit is caught"
else bad "a body running without errexit is caught" "expected non-zero naming 'propagates', got $rc: $out"; fi

# 3. A dispatcher that swallows the target's status. errexit is on and the body is fine; the
#    silencing happens one level up, which is the harder of the two to notice by reading.
run_fixture 'set -euo pipefail' '"target_${1:-lint}" || true'
if [[ $rc -ne 0 && "$out" == *"propagates"* ]]; then ok "a dispatcher swallowing the status is caught"
else bad "a dispatcher swallowing the status is caught" "expected non-zero naming 'propagates', got $rc: $out"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
