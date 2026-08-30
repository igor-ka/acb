#!/usr/bin/env bash
# Sync is the half of this toolkit that touches other repositories, so every case here runs
# against a THROWAWAY toolkit fixture, never the real checkout. ACB_ROOT is what pull and propose
# read and write — propose branches, commits and pushes — so pointing it at the developer's own
# clone would have this suite open pull requests as a side effect of running the tests.
# `gh` is stubbed on PATH for the same reason.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REAL_ROOT="$PWD"

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s — %s\n' "$1" "$2"; }

# A fake toolkit: a git repo with a carried/ tree and a MANIFEST, and a stub gh ahead of the real
# one on PATH.
STUB="$(mktemp -d)"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
echo "gh $*" >> "${GH_LOG:-/dev/null}"
case "$1" in
  repo) exit 1 ;;      # "not a GitHub repo" — keeps status's ecosystem probe quiet
  variable) exit 1 ;;
  pr) echo "https://example.invalid/pr/1" ;;
esac
exit 0
STUBEOF
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

make_toolkit() {
  local t; t="$(mktemp -d)"
  # A faithful miniature: ACB_ROOT means "the toolkit checkout", one meaning, so the fixture
  # carries the same lib/ the real one does rather than the code being loaded from elsewhere.
  cp -R "$REAL_ROOT/lib" "$t/lib"
  mkdir -p "$t/carried/skills"
  printf 'original\n' > "$t/carried/skills/a.md"
  printf 'skills/a.md\n' > "$t/MANIFEST"
  git -C "$t" init -q -b main
  git -C "$t" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "base"
  git -C "$t" add -A
  git -C "$t" -c user.email=t@t -c user.name=t commit -q -m "carried"
  git -C "$t" remote add origin "$t/../fake-remote" 2>/dev/null || true
  printf '%s' "$t"
}

make_consumer() {
  local toolkit="$1" commit="$2" c; c="$(mktemp -d)"
  mkdir -p "$c/skills"
  # The file AS OF the recorded commit, not as of the toolkit's HEAD. A consumer that has not
  # pulled holds the old content; copying the new content while recording the old commit would
  # fabricate a repository that never existed.
  git -C "$toolkit" show "$commit:carried/skills/a.md" > "$c/skills/a.md"
  cat > "$c/.acb.json" <<JSON
{ "template": { "repo": "example/acb", "commit": "$commit" },
  "process": { "doc": "docs/sdlc.md", "watched": ["^scripts/"], "dependabotEcosystems": [] },
  "components": [] }
JSON
  git -C "$c" init -q -b main
  git -C "$c" add -A
  git -C "$c" -c user.email=t@t -c user.name=t commit -q -m "init"
  printf '%s' "$c"
}

run_acb() { ( cd "$1" && shift && ACB_ROOT="$TOOLKIT" "$REAL_ROOT/bin/acb" "$@" 2>&1 ); }

TOOLKIT="$(make_toolkit)"
HEAD_SHA="$(git -C "$TOOLKIT" rev-parse HEAD)"

# --- status: up to date ---
C="$(make_consumer "$TOOLKIT" "$HEAD_SHA")"
out="$(run_acb "$C" status)"
if grep -q 'behind: 0' <<<"$out" && grep -q 'ahead: 0' <<<"$out"; then ok "status reports clean"
else bad "status reports clean" "$out"; fi

# --- status: behind ---
printf 'upstream change\n' > "$TOOLKIT/carried/skills/a.md"
git -C "$TOOLKIT" add -A
git -C "$TOOLKIT" -c user.email=t@t -c user.name=t commit -q -m "upstream"
NEW_SHA="$(git -C "$TOOLKIT" rev-parse HEAD)"
out="$(run_acb "$C" status)"
if grep -q 'behind: 1 commit' <<<"$out"; then ok "status reports behind"
else bad "status reports behind" "$out"; fi

# --- pull: refuses a dirty tree, exit 3 ---
printf 'local edit\n' >> "$C/skills/a.md"
out="$(run_acb "$C" pull)"; rc=$?
if [[ $rc -eq 3 ]] && grep -q 'not clean' <<<"$out"; then ok "pull refuses a dirty tree with exit 3"
else bad "pull refuses a dirty tree with exit 3" "exit $rc: $out"; fi

# --- pull: applies, updates the commit, and commits nothing ---
git -C "$C" checkout -q -- .
out="$(run_acb "$C" pull)"; rc=$?
got="$(cat "$C/skills/a.md")"
recorded="$(jq -r .template.commit "$C/.acb.json")"
dirty="$(git -C "$C" status --porcelain)"
if [[ $rc -eq 0 && "$got" == "upstream change" && "$recorded" == "$NEW_SHA" && -n "$dirty" ]]; then
  ok "pull applies, records the commit, and leaves the change uncommitted"
else
  bad "pull applies, records the commit, and leaves the change uncommitted" \
      "exit $rc, content '$got', recorded ${recorded:0:8} vs ${NEW_SHA:0:8}, dirty='${dirty:0:40}'"
fi

# --- pull: idempotent. A second pull with no upstream change produces an empty diff. This is
#     the empty-diff test in miniature, and the property the whole two-bucket design rests on.
git -C "$C" add -A && git -C "$C" -c user.email=t@t -c user.name=t commit -q -m "pulled"
run_acb "$C" pull >/dev/null
if [[ -z "$(git -C "$C" status --porcelain)" ]]; then ok "a second pull is a no-op"
else bad "a second pull is a no-op" "$(git -C "$C" status --porcelain)"; fi

# --- status: ahead ---
printf 'downstream improvement\n' > "$C/skills/a.md"
out="$(run_acb "$C" status)"
if grep -q 'ahead: 1 carried file' <<<"$out" && grep -q 'skills/a.md' <<<"$out"; then
  ok "status reports ahead and names the file"
else bad "status reports ahead and names the file" "$out"; fi

# --- behind does not masquerade as ahead ---
# A file the consumer never touched must not be reported as ahead just because upstream moved.
# Following that advice would propose a stale copy and revert the upstream change.
C2="$(make_consumer "$TOOLKIT" "$HEAD_SHA")"     # recorded at the OLD commit, file untouched
out="$(run_acb "$C2" status)"
if grep -q 'behind: 1 commit' <<<"$out" && grep -q 'ahead: 0' <<<"$out"; then
  ok "a behind-but-unedited file is not reported as ahead"
else bad "a behind-but-unedited file is not reported as ahead" "$out"; fi

# --- propose: refuses a file that is not carried ---
printf 'x\n' > "$C/generated.md"
out="$(run_acb "$C" propose generated.md)"; rc=$?
if [[ $rc -eq 3 ]] && grep -q 'not a carried file' <<<"$out"; then ok "propose refuses a generated file"
else bad "propose refuses a generated file" "exit $rc: $out"; fi

# --- propose: refuses a file identical upstream ---
git -C "$C" checkout -q -- skills/a.md
out="$(run_acb "$C" propose skills/a.md)"; rc=$?
if [[ $rc -eq 3 ]] && grep -q 'identical upstream' <<<"$out"; then ok "propose refuses an identical file"
else bad "propose refuses an identical file" "exit $rc: $out"; fi

# --- propose: copies upstream and restores the toolkit's branch ---
printf 'downstream improvement\n' > "$C/skills/a.md"
before_branch="$(git -C "$TOOLKIT" rev-parse --abbrev-ref HEAD)"
out="$(run_acb "$C" propose skills/a.md)"; rc=$?
after_branch="$(git -C "$TOOLKIT" rev-parse --abbrev-ref HEAD)"
if [[ "$before_branch" == "$after_branch" ]]; then ok "propose restores the toolkit's branch"
else bad "propose restores the toolkit's branch" "was $before_branch, now $after_branch"; fi

# --- propose: refuses when the toolkit checkout is dirty ---
printf 'stray\n' > "$TOOLKIT/untracked.txt"
printf 'another improvement\n' > "$C/skills/a.md"
out="$(run_acb "$C" propose skills/a.md)"; rc=$?
if [[ $rc -eq 3 ]] && grep -q 'uncommitted changes' <<<"$out"; then
  ok "propose refuses a dirty toolkit checkout"
else bad "propose refuses a dirty toolkit checkout" "exit $rc: $out"; fi

# --- drift: a component's job need not live in ci.yml -------------------------------------------
#
# acb_check_drift reads only the working directory, so it is exercised directly rather than
# through `acb status`, which would need a whole consumer fixture. lib/sync.sh is pure function
# definitions, so sourcing it has no side effect.
drift_in() {   # <dir> -> sets $out and $rc
  out="$( cd "$1" && ACB_ROOT="$REAL_ROOT" bash -c \
            'source "$ACB_ROOT/lib/sync.sh"; acb_check_drift' 2>&1 )"; rc=$?
}

# Terraform gets its own workflow so its toolchain setup is not in the middle of the Node
# pipeline; a deployment-script suite gets one so it can be required without lodging in another
# job. Reading ci.yml alone reports both as "required, no job" and makes status permanently red
# for a repository that did nothing wrong.
d="$(mktemp -d)"; mkdir -p "$d/.github/workflows"
cat > "$d/.acb.json" <<'JSON'
{ "template": { "repo": "example/repo", "commit": "0" },
  "process": { "doc": "docs/sdlc.md", "watched": ["^scripts/"] },
  "components": [ { "id": "app", "checkName": "App checks", "targets": ["lint"] } ] }
JSON
printf 'jobs:\n  app:\n    name: App checks\n' > "$d/.github/workflows/ci.yml"
printf 'jobs:\n  tf:\n    name: Terraform checks\n' > "$d/.github/workflows/terraform.yml"
# A workflow that gates nothing, which is normal and must not be an error.
printf 'jobs:\n  am:\n    name: Dependabot auto-merge\n' > "$d/.github/workflows/auto-merge.yml"
cat > "$d/.github/ruleset.json" <<'JSON'
{ "rules": [ { "type": "required_status_checks", "parameters": { "required_status_checks":
  [ {"context":"App checks"}, {"context":"Terraform checks"},
    {"context":"SDLC docs"}, {"context":"PR shape"} ] } } ] }
JSON

drift_in "$d"
if [[ $rc -eq 0 && "$out" == *"drift: none"* ]]; then
  ok "a job in another workflow is not drift"
else bad "a job in another workflow is not drift" "exit $rc: $out"; fi

# The direction that still matters: a required check no job anywhere produces hangs every merge.
rm "$d/.github/workflows/terraform.yml"
drift_in "$d"
if [[ $rc -eq 1 && "$out" == *"Terraform checks"* ]]; then
  ok "a required check with no job is still drift, and is named"
else bad "a required check with no job is still drift, and is named" "exit $rc: $out"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
