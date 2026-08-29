# acb — agentic coding baseline

Installs a development process into a repository, and carries improvements between repositories.

    acb init <dir>      scaffold a repository from this toolkit
    acb status          what this repo is behind or ahead on
    acb pull            bring carried files up to the toolkit's HEAD
    acb propose <path>  open a PR upstream with a carried file you changed

Two buckets and nothing between them. **Carried** files are byte-identical in every consumer, so
syncing is `cp` and reviewing is `git diff`. **Generated** files are written once at `acb init`
and belong to the consumer thereafter. Variation lives in `.acb.json`, read at run time.

Requires `bash`, `jq`, `gh`. `shellcheck` for `./verify.sh lint`.

Design and rationale: `docs/specs/2026-08-26-sdlc-template.md` in `igor-ka/llm-code-execution`.
