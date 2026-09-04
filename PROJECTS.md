## [x] Project P01: claude-openrouter-launcher (v0.1.0)
**Goal/Requirement**: A team-usable, standalone toolkit to run Claude Code through OpenRouter's
Fusion multi-model panel, with a one-time per-user preset setup and a single configurable launcher.

- Setup script creates each user's own `cc-fusion` OpenRouter preset (custom 5-model panel), with a
  fallback to `openrouter/fusion` if not run.
- One launcher (`bin/claude-openrouter`) with config-driven `--mode` (subagent / main / extreme + custom),
  working in interactive and `claude -p` modes.
- Three key-input methods: `--key`, `--key-file`, `$OPENROUTER_API_KEY` (in that precedence).

**Out of Scope**
- Native-Anthropic advisor (server-side tool; does not work through OpenRouter — disabled).
- Committing secrets (public repo).

### Tests & Tasks
- [x] [P01-T01] `lib/common.sh`: key resolution (3 methods), config load, fusion-ref, settings render
- [x] [P01-T02] `setup.sh`: create + verify the `cc-fusion` preset; write PRESET_READY marker
- [x] [P01-T03] `bin/claude-openrouter`: `--mode`, key methods, subshell-scoped secret, arg passthrough
- [x] [P01-T04] `config/modes.json.example`: subagent / main / extreme with per-slot models
- [x] [P01-TS01] `tests/smoke.sh`: shellcheck, mode render, fusion-keyword resolution, key precedence
- [x] [P01-T05] Scaffolding: README, justfile, Makefile, CI (shellcheck/actionlint/smoke), LICENSE
- [ ] [P01-TS02] Live verification: setup creates preset; each mode routes correctly via `claude -p`

### Automated Verification
- `make check` (deps), `just lint` (shellcheck), `just test` (`tests/smoke.sh`) all pass.

### Manual Verification
- `./setup.sh --key-file ~/.config/smorin/.env` creates the preset.
- `bin/claude-openrouter --mode main -p "say hi" --output-format json` → `modelUsage` shows `@preset/cc-fusion`.
- `bin/claude-openrouter --mode subagent -p "<spawns a subagent>"` → main Opus + subagent fusion.

---

## [x] Project P02: doctor preset transparency (v0.2.0)
**Goal/Requirement**: `doctor` should show the live preset's full configuration (panel models,
judge, tool_choice) and flag drift from the config it was built from, plus confirm which key it
actually resolved.

- Display live `analysis_models`, judge, and `tool_choice` from the preset (reuse the response
  doctor already fetches — no extra API call).
- Compare panel + judge against config `.panel_models` / `.judge_model`; on mismatch emit a
  non-fatal `⚠ differs — re-run ./setup.sh` (doctor still exits 0).
- Print the resolved key's last-4 (locally derived) to confirm which key/env was picked up.

**Out of Scope**
- Changing doctor's exit-code semantics for existing checks; comparing against a hardcoded
  baseline (we diff against the user's own config).

### Tests & Tasks
- [x] [P02-TS01] `tests/smoke.sh` #20: in-sync stub asserts panel/judge lines + "in sync";
      drifted stub asserts "differs" and exit 0; assert key last-4 + source lines present
- [x] [P02-T01] `col_doctor`: print resolved-key last-4 + source (file path / env var / --key flag)
- [x] [P02-T02] `col_doctor`: display live panel/judge/tool_choice from existing `pinfo`
- [x] [P02-T03] `col_doctor`: diff panel+judge vs config, warn (non-fatal) on drift

### Automated Verification
- `make check`, then `just all` (shellcheck + smoke) pass.

### Manual Verification
- `bin/claude-openrouter doctor --key-file ~/.config/smorin/.env` shows panel/judge/tool_choice,
  a "matches config" line, and the key last-4.

---

## [x] Project P03: profiles + multi-model backends (v0.3.0)
**Goal/Requirement**: Add named **profiles** so the launcher can target any OpenRouter
backend — a fusion preset, a model-slug alias, or a raw `--backend` slug — composed with
the existing modes. Clean-break config schema; default mode becomes `extreme`.

**Out of Scope**
- Back-compat shim for the old top-level preset keys, or a `"fusion"` slot-keyword alias.
- Per-profile `default_mode`.

### Tests & Tasks
- [x] [P03-T01] Config schema (`profiles` catalog, `default_profile`/`default_mode`) + `lib/common.sh` resolvers (`col_resolve_profile/_mode`, `col_profile_type`, `col_backend_ref`, per-slug `col_preset_ready`, `col_render_settings` with `"backend"` keyword)
- [x] [P03-T02] `setup.sh`: per-fusion-profile preset creation (all by default, `--profile` for one), per-slug markers, model-profile skip
- [x] [P03-T03] `bin/claude-openrouter`: `--profile`/`--backend`, `profiles` subcommand, `extreme` default, mutual exclusion, profile-aware preset warning, richer `--show-settings`; `just run` default → extreme
- [x] [P03-T04] `col_doctor`: per-fusion-profile preset + drift, profiles summary
- [x] [P03-T05] README Profiles section + upgrade note; PROJECTS.md
- [x] [P03-TS01] `tests/smoke.sh`: profile/backend resolution (all 3 flavors), mode×profile render, default precedence, `--profile`/`--backend` mutual exclusion, multi-profile setup + markers, profile-aware doctor
- [x] [P03-TS02] Live verification: `--profile deepseek -p "..." --output-format json` shows the deepseek slug; `./setup.sh` creates all fusion presets

### Automated Verification
- `make check`, then `just all` (shellcheck + smoke) pass.

### Manual Verification
- `bin/claude-openrouter profiles` lists `fusion` (fusion), `deepseek`/`qwen` (model).
- `bin/claude-openrouter --profile fusion --mode main --show-settings` → opus + subagent = `@preset/cc-fusion`.
- `bin/claude-openrouter --profile deepseek --show-settings` → all slots = `deepseek/deepseek-v3.2`.
- `bin/claude-openrouter --backend "qwen/qwen3-coder-plus" --show-settings` → all slots = `qwen/qwen3-coder-plus`.
- `bin/claude-openrouter --profile deepseek --backend foo` → error.
- `./setup.sh --key-file ~/.config/smorin/.env` writes markers under `$COL_STATE_DIR/presets/`.

---

## [x] Project P04: rename to "Claude OpenRouter Launcher" (v0.4.0)
**Goal/Requirement**: Rebrand the product/tooling from "fusion" to OpenRouter (the tool is
no longer Fusion-specific), while keeping the OpenRouter **Fusion router** references
(the `fusion` profile, `cc-fusion` preset, `openrouter/fusion`, `openrouter:fusion`) intact.
Full, clean-break rename (no aliases). Breaking change.

- Binary `claude-fusion` → `claude-openrouter`; repo → `claude-openrouter-launcher`.
- Internal prefix `cfl_`/`CFL_` → `col_`/`COL_`; `CLAUDE_FUSION_CONFIG` → `CLAUDE_OPENROUTER_CONFIG`.
- State dir `~/.config/claude-fusion` → `~/.config/claude-openrouter` (re-run `./setup.sh` once after upgrade).

**Out of Scope**
- Renaming the OpenRouter Fusion-router tokens (profile/preset/slugs) — those are a real external feature.
- Back-compat aliases for the old binary/env names.
- Rewriting the dated P03 spec/plan docs (historical; addenda only).

### Tests & Tasks
- [x] [P04-T01] `git mv bin/claude-fusion bin/claude-openrouter`; ordered sed across 13 token-bearing files (protected tokens excluded)
- [x] [P04-T02] State dir + `CLAUDE_OPENROUTER_CONFIG` env + `col_`/`COL_` identifiers; README/PROJECTS/.flox/.claude announcement
- [x] [P04-TS01] `tests/smoke.sh` renamed in lockstep; shellcheck clean; `just all` → `smoke: ALL PASS`
- [x] [P04-T03] Tag v0.3.0 (pre-rename); GitHub repo rename + remote update
- [x] [P04-T04] Merge PR; tag v0.4.0

### Automated Verification
- `make check`, then `just all` (shellcheck + smoke) pass.
- `grep -rIE 'claude-fusion|cfl_|CFL_|CLAUDE_FUSION_CONFIG'` returns only historical `docs/superpowers` hits.

### Manual Verification
- `bin/claude-openrouter -g` launches; `profiles`/`modes`/`doctor` work.
- After upgrade, first launch warns "run ./setup.sh" (new state dir); re-running setup restores readiness.

---

## [x] Project P05: models discovery command (v0.5.0)
**Goal/Requirement**: Add a `models` subcommand so you can find an OpenRouter **model
slug** for a `model` profile or `--backend` without leaving the tool. Discovery-first:
the slug is the product. Public endpoint — no key, works before `./setup.sh`.
See `docs/superpowers/specs/2026-07-15-models-discovery-command-design.md`.

**Out of Scope**
- Per-model provider/endpoint listing → P06.
- Caching, pagination, `--free`/`--provider` filters, fuzzy matching, sort flags.

### Tests & Tasks
- [x] [P05-T01] `col_list_models <query> <json>` in `lib/common.sh`: keyless fetch, case-insensitive substring on id+name, sort by id, aligned table, `$/1M` + `K`/`M` formatting, `free`
- [x] [P05-T02] `models)` subcommand in `bin/claude-openrouter` (optional QUERY, `--json`); `usage()` + README "Discovering models"
- [x] [P05-TS01] `tests/smoke.sh`: id/name match, case-insensitivity, no-query lists all, `--json` filtered array, free + K/M formatting, hints, works with no key
- [x] [P05-TS02] No match is grep-style: stderr message + exit 1; `--json` → `[]` + exit 1

### Automated Verification
- `make check`, then `just all` (shellcheck + smoke) pass.

### Manual Verification
- `bin/claude-openrouter models glm` → GLM family, slug-first, sorted, aligned.
- `bin/claude-openrouter models zzz; echo $?` → stderr message, `1`.
- `bin/claude-openrouter models glm --json | jq -r '.[].id'` → the GLM slugs.
- Works with `OPENROUTER_API_KEY` unset.

---

## [x] Project P07: account presets command (v0.5.0)
**Goal/Requirement**: Add a `presets` subcommand that compares the OpenRouter presets on
the account (`GET /api/v1/presets`) with locally configured profiles. Human output is a
unified inventory with explicit remote and local sources. Each slug reports `linked`,
`not linked to this config`, or `missing from OpenRouter`.

**Out of Scope**
- Deleting/creating presets (setup.sh creates; deletion stays on the OpenRouter dashboard).
- Changing the remote-account-only data returned by `--json` and `-o name`.

### Tests & Tasks
- [x] [P07-T01] `col_list_presets <key> <format>` in `lib/common.sh`: account fetch,
      remote/local union, explicit columns and link states, adaptive table/stacked layout
- [x] [P07-T02] `presets)` subcommand (`--key`/`--key-file`/`--json`); `usage()` + README section
- [x] [P07-TS01] `tests/smoke.sh`: source labels, all link states, sorted union,
      summary, conditional hints, narrow layout, and unchanged `--json` array

### Automated Verification
- `make check`, then `just all` (shellcheck + smoke) pass.

### Manual Verification
- `bin/claude-openrouter presets --key-file ~/.config/smorin/.env` labels the remote
  OpenRouter source and local config path, then shows each preset slug beside its local
  profile and literal link state.

---

## [x] Project P06: providers command (v0.6.0)
**Goal/Requirement**: Add `providers <slug>` — list who serves a model and at what
context/price/uptime. Supplies the `tag` you pin in a `preset` profile's
`provider.only`, and exposes the per-provider spread the model summary hides (the same
slug can be served at 10× different context and 3× different price). Public endpoint —
no key. Sorts: `alpha` (default), `cheapest`, `expensive`, `reliable`.

**Out of Scope**
- Throughput/latency columns and a `fastest` sort: OpenRouter returns
  `throughput_last_30m` / `latency_last_30m` as **null** on this endpoint (verified live
  across GLM 5.2, GPT-4o-mini, Llama 3.3, DeepSeek v3.2 — 0 non-null of 57 endpoints).
  `uptime_last_30m` IS populated and is used instead. Revisit if OpenRouter populates them.
- Writing/creating presets from this command (that stays in `setup.sh`).

### Tests & Tasks
- [x] [P06-T01] `col_list_providers <slug> <sort> <json>` in `lib/common.sh`; shared
      `COL_JQ_FMT` jq helpers factored out of `col_list_models` (pad/ctx/money — DRY)
- [x] [P06-T02] `providers)` subcommand: required slug, `--sort` validation, `--json`;
      `usage()` + README "Choosing a provider to pin"
- [x] [P06-TS01] `tests/smoke.sh`: default alpha, ctx/price/uptime rendering, no dead
      speed column, pin hint, each sort's ordering, `--json`, missing-slug / bad-sort / 404

### Automated Verification
- `make check`, then `just all` (shellcheck + smoke) pass.

### Manual Verification
- `bin/claude-openrouter providers z-ai/glm-5.2` → 28 providers, alphabetical, no key needed.
- `--sort cheapest` → `deepinfra/fp4 $0.93`; `--sort expensive` → `wafer/fast $3.00`;
  `--sort reliable` → `wafer/fast 100% up` (orders diverge from row 3).
- `providers` with no slug / `--sort fastest` / an unknown slug → clear errors, non-zero.

---

## [x] Project P08: shell completion (v0.7.0)
**Goal/Requirement**: Ship a zsh completion function so the launcher is discoverable
from the shell. Complete subcommands, global flags, and — crucially — the *values*
that are specific to this user's config: `--profile` from their profiles and `--mode`
from their modes. Wire it into `make install` / `just install` so putting the launcher
on PATH also makes it complete.
- Completion values come from the launcher itself, never a hardcoded list, so a
  profile added to `config/modes.json` completes with no regeneration step.
- `profiles` and `modes` gain `--json` (matching `models` / `providers` / `presets`,
  which already have it) so completion parses structured output instead of the
  human-readable table.

**Out of Scope**
- bash/fish completion. zsh only: it is the shell this repo targets (`setup.sh`,
  the README, and the developer's environment are all zsh). Revisit on request.
- Completing OpenRouter model slugs for `--backend` / `providers`. That needs a
  network call per TAB against `/models` (417 entries); a cache with an invalidation
  policy is a separate project.
- Auto-registering the completion in the user's `.zshrc`. The install target places
  the file and prints the one line to add; editing a user's shell config is theirs.

### Tests & Tasks
- [x] [P08-T01] `--json` on `profiles` and `modes`: `col_list_profiles` /
      `col_list_modes` take a `json` argument and emit the config objects; the
      subcommands parse `--json`. Today both silently ignore the flag.
- [x] [P08-T02] `completions/_claude-openrouter` — zsh compdef: subcommands with
      descriptions, global flags, `--profile`/`--mode` value completion from the
      launcher, `--sort` values for `providers`, file completion for `--key-file`
- [x] [P08-T03] Install wiring (`Makefile`, `justfile`) + README "Shell completion"
      + `usage()` unchanged (completion is not a subcommand)
- [x] [P08-TS01] `tests/smoke.sh`: `--json` output shape for both commands; the
      completion file is syntactically valid zsh; the helper that extracts names
      returns the expected set from the example config
- [x] Regression Test Status — `just all` green (shellcheck + 32 smoke sections)

### Deliverable
```bash
$ claude-openrouter --profile <TAB>
deepseek  fusion  glm  glm-exacto  glm-fireworks  glm-nitro  qwen
$ claude-openrouter --mode <TAB>
extreme  main  subagent
$ claude-openrouter pro<TAB>
profiles  providers
```

### Automated Verification
- `make check`, then `just all` (shellcheck + smoke) pass.
- `zsh -n completions/_claude-openrouter` exits 0.

### Manual Verification
- `make install && exec zsh` → `claude-openrouter --profile <TAB>` lists profiles
  from the user's own `config/modes.json` (including locally-added ones).
- Adding a profile to `config/modes.json` makes it complete with no other step.

---

## [x] Project P09: preset inspection and management commands (v0.8.0)
**Goal/Requirement**: Expose the complete preset lifecycle through a canonical
`preset` command group. Users can list account presets, inspect one local/remote
definition, interactively create or update a profile, and synchronize one or all
preset-backed profiles without editing JSON by hand.

### Contract

- `preset list`, `preset view`, `preset create`, `preset update`, and `preset apply`.
- Interactive prompting by default; flags plus `--no-input --yes` for automation.
- `table`, `json`, and list-only `name` output formats; structured machine errors.
- Atomic local writes with backup, lock, signal cleanup, and an exact recovery command
  when remote synchronization fails after the local save.
- `presets` remains as the legacy account-listing command.

### Tests & Tasks

- [x] [P09-T01] `lib/presets.sh`: parsers, help, inspection, prompting, validation,
      safe config writes, create/update, and apply orchestration
- [x] [P09-T02] `bin/claude-openrouter`: canonical group dispatch and global
      `--config FILE`
- [x] [P09-T03] `lib/common.sh`: sorted preset formats, unified human inventory,
      adaptive table/stacked rendering, and canonical recovery hints
- [x] [P09-T04] zsh action/flag/profile completion; README lifecycle documentation;
      approved design record
- [x] [P09-TS01] no-cost smoke coverage for list/view/create/update/apply, adaptive
      inventory rendering, dry-run, conflicts, locking, JSON errors, remote failure
      recovery, and readiness markers
- [x] [P09-TS02] Live verification (2026-09-04): `cc-live-probe` created,
      `preset view` `in-sync`, updated, `preset apply` recreated readiness
      (plus P10/P11 live steps on the same preset)

### Automated Verification

- `make check`, then `just all` (shellcheck + no-cost smoke suite) pass.
- Interactive `preset create interactive-probe --dry-run` prints the plan and leaves
  both the config and lock state unchanged.

### Manual Verification

- Create a disposable profile with `preset create`, confirm `preset view` reports
  `in-sync`, update it, and confirm `preset apply` recreates its readiness marker.
- Remove the disposable remote preset from the OpenRouter dashboard after testing.

---

## [~] Project P11: fusion tuning knobs (v0.9.0)
**Goal/Requirement**: Expose OpenRouter's Fusion run parameters as optional
fusion-profile fields, persisted through the `tools[].parameters` object the
launcher already stores (live-verified 2026-09-04 to round-trip, unlike the
`plugins` form, which presets silently drop). Knobs: `max_tool_calls` (1–16),
`temperature` (0–2, panel only), `max_completion_tokens` (positive int),
`reasoning` (`effort` string + `max_tokens` positive int). Absent knobs mean
OpenRouter defaults; update inherits unspecified knobs; drift detection covers
them.

**Out of Scope**
- The curated `preset` base slug (redundant when an explicit panel is set).
- Unsetting a knob back to default (no `--no-*` flags; recreate the profile).
- `plugins`-form migration (rejected by live probe — see P10 notes).

### Tests & Tasks
- [x] [P11-T01] `lib/presets.sh`: knob flags, range validation, update inherit,
      plan/view display, knob-aware sync status; `setup.sh`: knobs in remote
      body + verification; `lib/common.sh` doctor knobs drift detail;
      completions + README + usage
- [x] [P11-TS01] `tests/smoke.sh` 29d3: create with all knobs (config + remote
      body), update inherits/changes one, range rejections, panel untouched
- [x] [P11-TS02] Live verification (2026-09-04): `cc-live-probe` created with
      `--max-tool-calls 2`; `preset view` reported `in-sync` with knobs shown

### Automated Verification
- `make check`, then `just all` (shellcheck + no-cost smoke suite) pass.

### Manual Verification
- `preset update fusion --max-tool-calls 2 --dry-run` shows the knob in the
  plan and leaves the config unchanged.

---

## [~] Project P10: additive fusion panel editing (v0.9.0)
**Goal/Requirement**: Change single entries on a fusion preset's panel without
retyping the whole list. `preset update` gains repeatable `--add-panel-model`
and `--remove-panel-model` flags (update only); `--panel-model` keeps its
replace-the-whole-panel semantics and is now documented as such in `--help`,
the zsh completion, and the README.

**Out of Scope**
- Additive provider editing for `type: "preset"` profiles.
- Fusion form migration — step A probe (2026-09-04, live account) resolved it:
  the `plugins` form is accepted but silently dropped from stored preset config
  (bare alias + `tool_choice` persisted; custom panel lost), while the `tools`
  form round-trips fully, including new knobs (`max_tool_calls`, `temperature`
  verified persisted). Decision: keep the `tools` form; new-knob exposure is
  viable via `tools[].parameters` (step C pending approval).

### Tests & Tasks
- [x] [P10-T01] `lib/presets.sh`: `--add/--remove-panel-model` parsing (repeatable
      and `=` forms), `col_preset_apply_panel_edits` merge (removals first,
      idempotent adds, `not_found` on unknown removal), update-only / fusion-only /
      no-mix-with-`--panel-model` validation, merged panel in dry-run plan and
      interactive default
- [x] [P10-T02] `--help` documents replace vs additive semantics; zsh completion
      offers the new flags on `update`; README documents both forms with an example
- [x] [P10-TS01] `tests/smoke.sh` 29d2: add keeps panel + syncs remote body,
      idempotent add, combined add+remove, misuse matrix (unknown member → 1,
      empty panel / mixed flags / create / preset-type → 2, panel untouched),
      additive dry-run previews without writing, completion offers new flags
- [x] [P10-TS02] Live verification (2026-09-04): added `z-ai/glm-5.2` to
      `cc-live-probe`, `in-sync` with 3-model panel; removed it, `in-sync`
      with 2-model panel

### Automated Verification
- `make check`, then `just all` (shellcheck + no-cost smoke suite) pass.

### Manual Verification
- `preset update fusion --add-panel-model <slug> --dry-run` shows the merged panel
  and leaves the config unchanged; without `--dry-run`, `preset view fusion`
  reports `in-sync` with the new member.
