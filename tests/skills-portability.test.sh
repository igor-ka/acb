#!/usr/bin/env bash
# A carried document that tells the reader to run one ecosystem's command is broken for every
# project that does not use it. This is the check behind that sentence.
#
# It is deliberately NOT a blanket ban on the word "npm". references/security-checklist.md
# enumerates npm, pnpm and Yarn side by side, and security-and-hardening says "do not assume npm" —
# that is multi-ecosystem reference content, and removing it would make the skills worse, not more
# portable. The rule is narrower: name a tool freely when you are comparing ecosystems; never tell
# the reader to run one as though it were this project's command.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

TREES="carried/.claude/commands carried/.claude/skills carried/docs"

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s\n%s\n' "$1" "$2"; }
asserts_empty() { if [[ -z "$2" ]]; then ok "$1"; else bad "$1" "$2"; fi; }

# A line naming a peer ecosystem is a comparison, not an instruction.
PEERS='pnpm|yarn|Yarn|pip|pip-audit|cargo|Cargo|gradle|Gradle|pytest|go test|go\.mod|Gemfile|pyproject|pom\.xml|composer|shrinkwrap'
# Command forms that mean "run this".
CMDS='npm (test|ci|install|run )|npx |vitest run'

# Blocks between <!-- portability-exempt: reason --> and <!-- /portability-exempt --> are skipped.
# A visible, greppable exemption carrying its own justification, rather than a regex quietly
# widened until it stops catching anything.
scan() {
  local tree
  for tree in $TREES; do
    while IFS= read -r f; do
      awk -v F="$f" '
        /<!-- portability-exempt:/ { skip = 1; next }
        /<!-- \/portability-exempt -->/ { skip = 0; next }
        !skip { print F ":" FNR ":" $0 }' "$f"
    done < <(find "$tree" -type f -name '*.md')
  done
}

asserts_empty "no single-ecosystem run instructions" \
  "$(scan | grep -E "$CMDS" | grep -vE "$PEERS" || true)"

# Tool names used as though they were the tool, rather than as one example among peers.
TOOLS='\b(Vitest|vitest|ESLint|eslint|Prettier|prettier|tsc)\b'
asserts_empty "no bare tool names outside a comparison" \
  "$(scan | grep -E "$TOOLS" | grep -vE "$PEERS|Jest|jest" || true)"

# Application nouns. No exceptions — these name one program, never a category.
NOUNS='backend/src|frontend/src|HistoryStore|SandboxBackend|sandbox-image|Auth0|Cloud Run|Valkey|llm-code-exec'
asserts_empty "no application nouns" \
  "$(scan | grep -E "$NOUNS" || true)"

# Postgres survives only under attribution: the example teaches, the unlabelled mention couples.
pg="$(scan | grep -E '\bPostgres\b' | grep -viE 'drawn from|generalises|for example' || true)"
asserts_empty "Postgres mentions carry their attribution" "$pg"

# The canonical vocabulary must not regress to a tool name.
asserts_empty "no docker/fmt targets (package/format are canonical)" \
  "$(scan | grep -E 'verify\.sh (docker|fmt)\b|SKIP_DOCKER' || true)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
