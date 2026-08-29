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
  run shellcheck -x bin/acb lib/*.sh tests/*.test.sh
}

selftest() {
  local t status=0
  for t in tests/*.test.sh; do
    echo "==> $t"
    "$t" || status=1
  done
  return $status
}

render() {
  run ./tests/render.test.sh
}

all() { lint; selftest; }

case "${1:-all}" in
  lint|selftest|render|all) "${1:-all}" ;;
  *) echo "usage: ./verify.sh [lint|selftest|render|all]" >&2; exit 2 ;;
esac
