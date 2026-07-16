# `models` discovery command — design

**Date:** 2026-07-15
**Target version:** v0.5.0
**Project:** P05
**Status:** approved (design), pending implementation plan

## Summary

Add a `models` subcommand that lets you find an OpenRouter **model slug** to paste
into a `model`-type profile or `--backend`. Today the launcher can target any slug
but gives you no way to discover one — you have to leave the tool and browse
openrouter.ai. This closes that loop.

Primary job is **discovery** (find a slug), not evaluation or validation.

## Background

- `GET /api/v1/models` returns **342 models** (verified 2026-07-15), each with
  `id`, `canonical_slug`, `name`, `context_length`, `pricing`, `top_provider`,
  `architecture`, `supported_parameters`, `description`, …
- Scale is the core design problem: a bare dump is 342 lines. Filtering is the feature.
- The endpoint is **public** — no API key — so this command works before `./setup.sh`
  (unlike `doctor`). `lib/check-openrouter.sh` already hits it keyless for its
  reachability probe.
- Existing sibling subcommands (`modes`, `profiles`) set the house style: a header
  line naming the source, indented rows, trailing hint line(s).
- 23 of the 342 models are free (`pricing.prompt == "0"`), so that case is real.

## Decisions (from brainstorming)

| # | Decision |
|---|----------|
| Primary job | **Find a slug to use** (discovery). Slug is the product. |
| Name | **`models`** — matches the `modes`/`profiles` noun style. Accepted risk: one letter from `modes`; mitigated by a cross-reference hint line in the output. |
| Line format | **slug + name + context + price**, aligned — enough to choose between near-duplicates (glm-4.5 / 4.6 / 5.2) without a second command. |
| No query | **List all** (342). Unix-y; pipe to `grep`/`less`/`fzf`. Consistent with `modes`/`profiles`. |
| `--json` | **Yes** — emit the filtered raw model objects for scripting. |
| No match | **grep-style: exit 1** (message on stderr; `--json` prints `[]`). |

## Command surface

```bash
claude-openrouter models [QUERY] [--json]
```

- **QUERY** — optional, case-insensitive **substring**, matched against both `id`
  and `name`. `glm` matches `z-ai/glm-5.2` (id) and `Z.ai: GLM 5.2` (name);
  `anthropic` matches by vendor prefix. Omitted → all models.
- **`--json`** — emit the filtered model objects as a JSON array instead of the table.
- **No API key required.** Works before setup.
- Requires `curl` + `jq` (already `col_require`d elsewhere).

## Output (human) — verified rendering against live data

```
Models (OpenRouter — 12 of 342 matching "glm"):
  z-ai/glm-4.5       Z.ai: GLM 4.5       131K ctx   $0.60/$2.20 per 1M
  z-ai/glm-4.5-air   Z.ai: GLM 4.5 Air   131K ctx   $0.13/$0.85 per 1M
  z-ai/glm-4.6       Z.ai: GLM 4.6       203K ctx   $0.50/$2.00 per 1M
  z-ai/glm-5.2       Z.ai: GLM 5.2       1.0M ctx   $0.95/$3.00 per 1M
  (use a slug as a profile's "model", or with --backend)
  (looking for launch modes? see 'claude-openrouter modes')
```

Rules:
- **Sorted by `id`** so families group (`glm-4.5 → 4.6 → 5.2` adjacent) — required by
  the "choose between near-duplicates" job.
- **Pricing** converted from the API's per-token strings to **$ per 1M tokens**,
  input/output, 2 decimals. `pricing.prompt == "0"` → render `free`.
- **Context** compacted: `1048576 → 1.0M`, `131072 → 131K`, `<1000 → as-is`.
- Columns aligned; header names the source and the match count (`N of 342 matching "q"`,
  or `342 total` with no query).
- Trailing hints: how to use the slug, plus the **`modes` cross-reference** that
  mitigates the one-letter typo trap.

## Behavior details

| Case | Result |
|---|---|
| Matches found | table (or JSON array) on stdout, **exit 0** |
| No match | `no models match 'zzz'` + hint on **stderr**, **exit 1** (grep-style) |
| No match, `--json` | `[]` on stdout, **exit 1** |
| Network/HTTP failure | `col_die` with a clear message + `claude-openrouter doctor` hint, non-zero |

Rationale for stderr on no-match: keeps stdout clean so `models foo | …` pipes
correctly while the message is still visible interactively.

## Implementation

- New **`col_list_models <query> <json>`** in `lib/common.sh`, alongside
  `col_list_modes` / `col_list_profiles` (same file, same shape — no new file).
- **Fetch:** a keyless `curl -fsS --connect-timeout 5 --max-time 15 "$OR_API/models"`.
  (`col_or_get` is not reused: it injects an `Authorization` header and requires a key;
  `/models` is public.)
- **Filter + sort + format in one `jq` program** — bash stays thin. `--json` skips the
  formatter and emits the filtered array.
- New `models)` case in `bin/claude-openrouter`'s subcommand block (next to `modes)` /
  `profiles)`), parsing an optional positional QUERY and `--json`; calls
  `col_require curl jq` then `col_list_models`.
- `usage()` gains a `models` line.

## Testing (NO-COST smoke)

Stub `curl` with a small fixed payload (a normal model, a free model, a 1M-context
model) and assert:
- substring match on **id** and on **name**; case-insensitive
- no query → lists all payload models
- `--json` → valid JSON array of exactly the filtered set
- pricing rendered `$X.XX/$Y.YY per 1M`; free model renders `free`
- context rendered `1.0M` / `131K`
- **no match → stderr message + exit 1**; `--json` no match → `[]` + exit 1
- works with **no key** in the environment
- header + both hint lines present
- shellcheck clean

## Automated verification

- `make check`, then `just all` (shellcheck + smoke) pass.

## Manual verification

- `bin/claude-openrouter models glm` lists the GLM family, slug-first, sorted.
- `bin/claude-openrouter models` lists all 342.
- `bin/claude-openrouter models zzz; echo $?` → message on stderr, `1`.
- `bin/claude-openrouter models glm --json | jq -r '.[].id'` → the GLM slugs.
- Works with `OPENROUTER_API_KEY` unset and before `./setup.sh`.

## Docs & tracking

- README: a "Discovering models" subsection under Profiles — find a slug → paste it
  into a `model` profile or `--backend`.
- `PROJECTS.md`: **Project P05: models discovery command (v0.5.0)**.

## Out of scope

Deliberately excluded to keep this one command focused (YAGNI):

- **Per-model provider/endpoint listing** (`/models/:id/endpoints`) — the input to
  `preset` provider pinning, and what reveals per-provider context/price/throughput
  traps (e.g. one provider serving GLM 5.2 at 65K context vs 1M elsewhere).
  Proposed follow-up: **P06 — `providers <slug>`**.
- **Account preset listing** (`GET /api/v1/presets`, verified to exist and return 3
  presets today, including the orphan `cc-fusion-probe`). Would flag presets on the
  account that no profile references, and profiles whose preset is missing — invisible
  to both `profiles` (config-side) and `doctor` (only checks referenced presets).
  Proposed follow-up: **P07 — `presets`**.
- Caching, pagination, `--free` / `--provider` filters, fuzzy matching, sort flags.
