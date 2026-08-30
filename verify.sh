#!/usr/bin/env bash
# The single entry point CI and a developer both run. Same script, same targets, so the two
# cannot drift — the property this toolkit exists to propagate.
set -euo pipefail
cd "$(dirname "$0")"

run() { echo "==> $*"; "$@"; }

lint() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "✗ shellcheck is not installed. brew install shellcheck" >&2
    echo "  Not skipped: a check that quietly does nothing is worse than no check." >&2
    return 1
  fi
  # -x follows `source` so lib/*.sh is analysed in the context that sources it.
  run shellcheck -x bin/acb lib/*.sh tests/*.test.sh \
    carried/scripts/*.sh carried/scripts/tests/*.test.sh
}

selftest() {
  local t status=0
  # The carried suites run here too. They are the only thing standing between a de-hardcoding
  # mistake and every consumer inheriting it.
  for t in tests/*.test.sh carried/scripts/tests/*.test.sh; do
    echo "==> $t"
    "$t" || status=1
  done
  return $status
}

render() {
  run ./tests/render.test.sh
}

all() { lint; selftest; }

# The contract this toolkit ships, honoured by the toolkit itself. Nothing checks it here — acb is
# not a declared component of anything — which is why writing it by hand is the honest test of
# whether the four lines in docs/sdlc.md are actually enough.
TARGETS="lint selftest render"

case "${1:-all}" in
  all) all ;;
  --targets) printf '%s\n' "$TARGETS" | tr ' ' '\n'; exit 0 ;;
  lint|selftest|render) "$1" ;;
  # 64, not 2: "no such target", distinguishable from "declared but not implemented".
  *) echo "usage: ./verify.sh [$TARGETS|all|--targets]" >&2; exit 64 ;;
esac
