#!/usr/bin/env bash
# Carried files must be byte-identical in every consumer. Three ways that breaks, one case each.
# Without this the two-bucket design is a discipline; with it, it is a check.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s\n%s\n' "$1" "$(sed 's/^/      /' <<<"$2")"; }

# asserts_empty <name> <output>
asserts_empty() { if [[ -z "$2" ]]; then ok "$1"; else bad "$1" "$2"; fi; }

# 1. No repository, owner, or project identifier may appear in a carried file.
#    -i, because the fixtures deliberately include a mixed-case spelling to prove the matching is
#    case-insensitive, and a case-sensitive check would sail straight past it.
asserts_empty "no repository identifiers in carried/" \
  "$(grep -rInEi 'igor-ka|llm-code-execution|llm-sandbox' carried/ || true)"

# 2. No render-time marker may appear. A carried file with a marker in it is a template that
#    escaped into the wrong bucket, and `acb pull` would overwrite a consumer's substituted value
#    with the marker itself.
asserts_empty "no @@MARKER@@ substitutions in carried/" \
  "$(grep -rIn '@@[A-Z_]\+@@' carried/ || true)"

# 3. MANIFEST and the tree must agree in BOTH directions. A file in carried/ but not in MANIFEST
#    is never copied to a consumer and looks like it was; a MANIFEST line with no file makes
#    `acb pull` fail halfway, having already written some of the set.
actual="$( ( cd carried && find . -type f | sed 's|^\./||' ) | LC_ALL=C sort )"
listed="$(LC_ALL=C sort MANIFEST)"
asserts_empty "MANIFEST matches carried/" \
  "$(diff <(printf '%s\n' "$listed") <(printf '%s\n' "$actual") || true)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
