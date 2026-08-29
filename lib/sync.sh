#!/usr/bin/env bash
# Bidirectional sync. Carried files are byte-identical in every consumer, which is what makes
# `pull` a copy, `git diff` the review, and `propose` a copy in the other direction. No merge
# engine, because byte-identical files never need one.

# --- status ----------------------------------------------------------------------------------

acb_cmd_status() {
  acb_config_validate || return 1
  local recorded head p behind status=0
  local -a ahead=()
  recorded="$(acb_template commit)"
  head="$(git -C "$ACB_ROOT" rev-parse HEAD)"

  if [[ -z "$recorded" ]]; then
    echo "behind: unknown — .acb.json records no template commit (an interrupted init?)"
    status=1
  elif [[ "$recorded" != "$head" ]]; then
    behind="$(git -C "$ACB_ROOT" rev-list --count "$recorded..$head" 2>/dev/null || echo '?')"
    echo "behind: $behind commit(s) — run 'acb pull'"
  else
    echo "behind: 0"
  fi

  # Ahead is per-file, not per-commit: the question a consumer asks is "what have I changed that
  # the toolkit does not have", and the answer is the argument list `acb propose` takes.
  #
  # Compare against the RECORDED commit, not the toolkit's HEAD. Against HEAD, a file the
  # consumer never touched shows as ahead the moment upstream changes it — the consumer is
  # merely behind — and following that advice would propose a stale copy and revert the upstream
  # change. The two states are independent and must be computed independently.
  while read -r p; do
    [[ -f "$p" ]] || continue
    if [[ -n "$recorded" ]] && git -C "$ACB_ROOT" cat-file -e "$recorded:carried/$p" 2>/dev/null; then
      cmp -s "$p" <(git -C "$ACB_ROOT" show "$recorded:carried/$p" 2>/dev/null) || ahead+=("$p")
    else
      # No recorded commit, or the file did not exist at it: fall back to HEAD, which is the
      # best available answer rather than a wrong one.
      cmp -s "$p" "$ACB_ROOT/carried/$p" || ahead+=("$p")
    fi
  done < "$ACB_ROOT/MANIFEST"
  if ((${#ahead[@]})); then
    echo "ahead: ${#ahead[@]} carried file(s) differ — 'acb propose <path>' to send upstream"
    printf '  %s\n' "${ahead[@]}"
  else
    echo "ahead: 0"
  fi

  acb_check_drift || status=1
  acb_check_ecosystems
  return $status
}

# The ruleset and the workflow are generated from one declaration but owned by the consumer
# afterwards, so a hand-edit to either can leave a job nothing requires, or a required check that
# no job produces. Both are silent until merge time, which is the wrong time.
acb_check_drift() {
  local jobs required missing
  if [[ ! -f .github/ruleset.json ]]; then
    echo "drift: no ruleset document — nothing to reconcile"
    return 0
  fi
  # ci.yml is absent in a zero-component repository, and that is correct rather than an error.
  # The two process checks come from the CARRIED workflows, not from ci.yml, so reading ci.yml
  # alone would report them missing on every run and make status permanently red.
  jobs="$( { if [[ -f .github/workflows/ci.yml ]]; then
               grep -oE '^ {4}name: .*' .github/workflows/ci.yml | sed 's/.*name: //'
             fi
             echo "SDLC docs"; echo "PR shape"; } | LC_ALL=C sort -u )"
  required="$(jq -r '.rules[]?|select(.type=="required_status_checks")
                     |.parameters.required_status_checks[].context' .github/ruleset.json \
              | LC_ALL=C sort -u)"
  # LC_ALL=C on both: comm compares byte-wise, and these names contain spaces.
  missing="$(comm -3 <(printf '%s\n' "$jobs") <(printf '%s\n' "$required"))"
  if [[ -n "$missing" ]]; then
    echo "✗ drift between the workflow's job names and the ruleset's required checks:" >&2
    printf '%s\n' "$missing" | sed 's/^/    /' >&2
    echo "  Left column: a job nothing requires. Right column: a required check no job produces." >&2
    return 1
  fi
  echo "drift: none"
  return 0
}

# The auto-merge allow-list lives in a repository variable, because that workflow has no checkout
# by design. Two homes means they can disagree, so status reconciles them. Best-effort: no remote,
# no gh, or no permission is not a failure of the repository.
acb_check_ecosystems() {
  local declared actual repo
  declared="$(acb_process_arr dependabotEcosystems | LC_ALL=C sort | tr '\n' ' ')"
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || return 0
  actual="$(gh variable get ACB_DEPENDABOT_ECOSYSTEMS --repo "$repo" 2>/dev/null || true)"
  actual="$(printf '%s' "$actual" | tr ' ' '\n' | grep -v '^$' | LC_ALL=C sort | tr '\n' ' ')"
  if [[ "${declared% }" != "${actual% }" ]]; then
    echo "ecosystems: .acb.json says '${declared% }', ACB_DEPENDABOT_ECOSYSTEMS says '${actual% }'"
    echo "  gh variable set ACB_DEPENDABOT_ECOSYSTEMS --repo $repo --body '${declared% }'"
  else
    echo "ecosystems: in sync"
  fi
}

# --- pull ------------------------------------------------------------------------------------

acb_cmd_pull() {
  acb_config_validate || return 1
  # Overwrite is correct for byte-identical files, which makes `git diff` the review and
  # `git checkout .` the undo — but only if the tree was clean first. Refusing here is what turns
  # "read the diff" from an instruction into a guarantee.
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ working tree is not clean. Commit or stash first — pull overwrites carried files, and" >&2
    echo "  a dirty tree makes the resulting diff unreadable, which is the only review there is." >&2
    return 3
  fi
  local p n=0 commit tmp
  while read -r p; do
    mkdir -p "$(dirname "$p")" || return 1
    cp "$ACB_ROOT/carried/$p" "$p" || return 1
    n=$((n + 1))
  done < "$ACB_ROOT/MANIFEST"
  commit="$(git -C "$ACB_ROOT" rev-parse HEAD)"
  tmp="$(mktemp)"
  jq --arg c "$commit" '.template.commit = $c' .acb.json > "$tmp" && mv "$tmp" .acb.json
  echo "✓ pulled $n carried file(s) at ${commit:0:8}. Nothing committed — review with 'git diff'."
}

# --- propose ---------------------------------------------------------------------------------

acb_cmd_propose() {
  acb_config_validate || return 1
  if [[ $# -eq 0 ]]; then
    echo "usage: acb propose <path>..." >&2
    return 2
  fi
  local p
  for p in "$@"; do
    # Generated files are the consumer's, by construction. Sending one upstream is the failure
    # mode that makes a template unmaintainable, so it is prevented rather than discouraged.
    if ! grep -qxF "$p" "$ACB_ROOT/MANIFEST"; then
      echo "✗ '$p' is not a carried file — it is generated, and generated files belong to this" >&2
      echo "  repository alone. 'acb status' lists what can be proposed." >&2
      return 3
    fi
    if cmp -s "$p" "$ACB_ROOT/carried/$p"; then
      echo "✗ '$p' is identical upstream — nothing to propose." >&2
      return 3
    fi
  done

  if [[ -n "$(git -C "$ACB_ROOT" status --porcelain)" ]]; then
    echo "✗ the toolkit checkout at $ACB_ROOT has uncommitted changes. Proposing would sweep them" >&2
    echo "  into the proposal commit. Commit or stash them there first." >&2
    return 3
  fi

  # Restore the toolkit's branch afterwards. Leaving it on propose/… would make the very next
  # `acb status` or `pull` — in any consumer — compare against that branch instead of main.
  local orig branch from
  orig="$(git -C "$ACB_ROOT" rev-parse --abbrev-ref HEAD)"
  branch="propose/$(date +%Y%m%d-%H%M%S)"
  from="$(basename "$PWD")"
  git -C "$ACB_ROOT" checkout -q -b "$branch" || return 1
  for p in "$@"; do
    cp "$p" "$ACB_ROOT/carried/$p" || return 1
  done
  git -C "$ACB_ROOT" add -A
  git -C "$ACB_ROOT" commit -qm "propose: $* from $from"
  git -C "$ACB_ROOT" push -q -u origin "$branch" || { git -C "$ACB_ROOT" checkout -q "$orig"; return 1; }
  ( cd "$ACB_ROOT" && gh pr create \
      --title "propose: $* from $from" \
      --body "Carried file(s) changed downstream and offered upstream by 'acb propose'." ) || true
  git -C "$ACB_ROOT" checkout -q "$orig"
  echo "✓ proposed $# file(s) from $from on branch $branch"
}
