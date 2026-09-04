# claude-openrouter-launcher

**Run Claude Code on any OpenRouter backend — a fusion panel, a model alias, or a raw slug.**

This launcher points Claude Code at [OpenRouter](https://openrouter.ai) via **profiles**: use [OpenRouter Fusion](https://openrouter.ai/docs/guides/routing/routers/fusion-router) (several frontier models answering in parallel, merged by a judge), a named model alias, or any raw model slug. Same Claude Code you already use — sharper answers by routing through the backend that fits the job.

- **Drop-in.** One command launches Claude Code with your chosen backend wired in. No code changes.
- **Dial the power.** Any backend as your main model, as subagents only (a cheaper "second opinion"), or everywhere (`extreme` default).
- **Yours to configure.** Your OpenRouter key, your profiles, your modes.
- **Interactive or headless.** Works in normal sessions and in `claude -p` one-shots.

---

## Quick start

You need: **Claude Code** (`claude`), an **[OpenRouter](https://openrouter.ai) API key** (`sk-or-v1-…`), and **`curl`** + **`jq`**.

```bash
# 1. Get it
git clone https://github.com/smorinlabs/claude-openrouter-launcher
cd claude-openrouter-launcher

# 2. One-time setup — creates your fusion preset on your own OpenRouter account
./setup.sh --key-file ~/.config/openrouter.env     # or:  --key sk-or-v1-…   |   export OPENROUTER_API_KEY=…

# 3. Launch Claude Code with fusion
bin/claude-openrouter -g                                # "just go" — default mode, interactive
bin/claude-openrouter -p "design a rate limiter"        # headless one-shot
```

That's it. The default mode (`extreme`) runs the active profile's backend in every tier — main, Sonnet, Haiku, and subagents.

**Helpful extras:**
- `make install` — put `claude-openrouter` on your PATH (then drop the `bin/`).
- `claude-openrouter` with no arguments — prints help (and, in a terminal, offers to just go).
- `claude-openrouter doctor` — checks your key, credits, preset, and environment if anything's off.

### Or use Flox (reproducible, zero manual installs)

[Flox](https://flox.dev) gives you Claude Code **and** every dependency — pinned — in one step, so there's nothing to install by hand:

```bash
flox activate          # first run fetches claude, curl, jq, shellcheck, just, gitleaks (pinned)
./setup.sh --key-file ~/.config/openrouter.env
claude-openrouter -g       # already on your PATH inside the env
```

The environment is defined in `.flox/env/manifest.toml` — edit it and re-`flox activate` to change tools or versions.

---

## Modes

A **mode** decides where the active profile's backend is used. Pick one with `--mode`; the default is `extreme`.

| Mode | Main model | Subagents | Best for | Relative cost |
|------|-----------|-----------|----------|:---:|
| `main` | **backend** | **backend** | backend as your main model and in subagents | $$ |
| `subagent` | Opus | **backend** | cheaper day-to-day; backend only when Claude spawns a subagent | $ |
| `extreme` *(default)* | **backend** | **backend** | every tier (Opus/Sonnet/Haiku) + subagents on backend | $$$ |

```bash
bin/claude-openrouter --mode subagent -p "explain this stack trace"
claude-openrouter modes        # list modes and their exact per-slot models
```

### Customizing modes and the panel

Defaults ship in `config/modes.json.example` and work out of the box — **nothing to create**. To customize, copy it once (the copy wins everywhere) and edit:

```bash
cp config/modes.json.example config/modes.json
```

- **Add your own mode.** Each slot is a model slug, or the keyword `"backend"` (which resolves to the active profile's backend):
  ```jsonc
  "modes": {
    "myteam": { "default": "opus", "opus": "backend", "sonnet": "deepseek/deepseek-v3.2", "haiku": "~anthropic/claude-haiku-latest", "subagent": "backend" }
  }
  ```
  ```bash
  bin/claude-openrouter --mode myteam -p "..."
  ```
- **Change the fusion panel itself** (which models deliberate + the judge), then re-run `./setup.sh`:
  ```jsonc
  "profiles": {
    "fusion": {
      "type": "fusion",
      "preset_slug": "cc-fusion",
      "panel_models": ["~anthropic/claude-opus-latest","~openai/gpt-latest","~google/gemini-pro-latest","deepseek/deepseek-v3.2","qwen/qwen3-coder-plus"],
      "judge_model": "~anthropic/claude-opus-latest",
      "fallback": "openrouter/fusion"
    }
  }
  ```

Preset-backed profiles can also be created or updated with the interactive
`claude-openrouter preset create` and `claude-openrouter preset update`
commands described below. Those commands save `config/modes.json` atomically
and synchronize the remote OpenRouter preset.

---

## Profiles

A **profile** decides *what* backend powers Claude Code. A **mode** decides *where* that backend is used (see Modes). Pick both: `--profile NAME --mode NAME`. With no `--mode`, the default is `extreme` (the backend in every slot).

Four flavors:

| Flavor | Config | Needs `./setup.sh`? |
|--------|--------|:---:|
| **Fusion preset** — a panel + judge | `"type": "fusion"` (with `preset_slug`, `panel_models`, `judge_model`, `fallback`) | yes |
| **Model alias** — a named OpenRouter slug | `"type": "model"` (with `model`) | no |
| **Provider-pinned preset** — one model forced to one provider | `"type": "preset"` (with `preset_slug`, `model`, `provider`, `fallback`) | yes |
| **Direct slug** — a raw slug, no profile | `--backend "vendor/model"` | no |

```bash
claude-openrouter --profile fusion --mode main          # fusion as main + subagents
claude-openrouter --profile deepseek                     # deepseek in every slot (extreme default)
claude-openrouter --profile glm-fireworks                # GLM 5.2 pinned to the Fireworks provider
claude-openrouter --backend "qwen/qwen3-coder-plus"      # raw slug, every slot
claude-openrouter profiles                               # list profiles and their targets
```

`--profile` and `--backend` are mutually exclusive. Define profiles in `config/modes.json` (copy `config/modes.json.example`); `default_profile` and `default_mode` set the no-flag behavior.

**Routing variants & provider pinning.** A `model`-type slug can carry an OpenRouter routing variant — `:nitro` (fastest), `:floor` (cheapest), `:exacto` (quality-first provider) — but a slug *cannot* pin one named provider. To force a single provider (e.g. Fireworks) use a `preset` profile: it bakes `provider: { "only": ["fireworks"] }` into a server-side preset (created by `./setup.sh`) and resolves to `@preset/<slug>`. Before setup runs it falls back to the bare `model` (unpinned).

### Discovering models

Need a slug for a `model` profile or `--backend`? `models` searches OpenRouter's catalog (342 models). It hits a **public** endpoint, so it needs no key and works before `./setup.sh`:

```bash
claude-openrouter models glm            # search id + name (case-insensitive)
claude-openrouter models                # list everything (pipe to grep/less/fzf)
claude-openrouter models glm --json     # raw model objects for scripting
```
```
Models (OpenRouter — 12 of 342 matching "glm"):
  z-ai/glm-4.6   Z.ai: GLM 4.6   203K ctx  $0.50/$2.00 per 1M
  z-ai/glm-5.2   Z.ai: GLM 5.2   1.0M ctx  $0.95/$3.00 per 1M
```
Results are sorted by slug so families group together, pricing is shown per 1M tokens in/out (free models say `free`), and a search with no matches exits `1` (grep-style). Copy a slug straight into a profile's `"model"` or `--backend`.

### Choosing a provider to pin

A slug like `z-ai/glm-5.2` is served by **many** providers, and they are not equivalent — `providers` shows the spread the model summary hides, and gives you the `tag` you put in a `preset` profile's `provider.only`:

```bash
claude-openrouter providers z-ai/glm-5.2                     # alphabetical (default)
claude-openrouter providers z-ai/glm-5.2 --sort cheapest     # also: expensive, reliable, alpha
claude-openrouter providers z-ai/glm-5.2 --json
```
```
Providers for z-ai/glm-5.2 (28 serving):
  deepinfra/fp4    1.0M ctx  $0.93/$3.00 per 1M   98.9% up
  akashml/fp8      131K ctx  $1.30/$4.40 per 1M   93.1% up
  fireworks/fast   1.0M ctx  $2.10/$6.60 per 1M   99.9% up
  (pin one with a preset profile: "provider": { "only": ["<tag>"] } — see README)
```
**Why this matters:** the same slug can be served at **10× different context** (101K vs 1.0M above) and **3× different price** — so default routing or the wrong pin can silently hand you a fraction of the context you expected. Sort by `cheapest` to see what default routing leans toward, or `reliable` (uptime) to pick a provider worth pinning.

> OpenRouter returns `throughput`/`latency` as `null` on this endpoint, so there's no speed column — `uptime` is the perf signal that's actually populated. (Use `:nitro` on a model slug if you want throughput-sorted routing.)

### Listing your account's presets

`preset list` lists the OpenRouter presets on your **account** and cross-references them against your config — surfacing what `profiles` (config-side) and `doctor` (only checks *referenced* presets) can't:

```bash
claude-openrouter preset list --key-file ~/.config/openrouter.env
```
```
Presets (OpenRouter account — 3 total):
  cc-fusion         ← profile: fusion
  cc-glm-fireworks  ← profile: glm-fireworks
  cc-fusion-probe   ⚠ orphan — no profile references it
```
**orphan** = on your account but no profile points at it (harmless leftovers, e.g. after a slug rename). **missing** = a profile references it but it isn't on the account → run `claude-openrouter preset apply <name>`.

> **Upgrading from v0.2.x:** preset readiness moved to per-slug markers. Re-run `./setup.sh` once after upgrading; until then fusion profiles use their `fallback` (with a warning).
>
> **Upgrading to v0.4.0 (rename):** the project was renamed to **Claude OpenRouter Launcher** (clean break, no aliases). The binary is now **`claude-openrouter`** (was `claude-fusion`), the config env var is **`CLAUDE_OPENROUTER_CONFIG`** (was `CLAUDE_FUSION_CONFIG`), and state lives in **`~/.config/claude-openrouter`** (was `~/.config/claude-fusion`). Re-run `./setup.sh` once so preset markers land in the new state dir; your OpenRouter presets (`cc-fusion`, etc.) are unchanged. If you symlinked the old binary, re-run `make install` / `just install`.

### Inspecting and managing presets

`preset` is the canonical command group for the complete preset lifecycle. A
**profile** is the local name selected with `--profile`; its `preset_slug`
identifies the remote OpenRouter preset.

```bash
claude-openrouter preset list                         # account presets + local links
claude-openrouter preset list -o name                 # slugs only, sorted
claude-openrouter preset view fusion                  # local + remote config and drift
claude-openrouter preset view --slug cc-orphan --json # inspect an unlinked preset
claude-openrouter preset create team-glm              # interactive create + save + sync
claude-openrouter preset update team-glm              # interactive edit + save + sync
claude-openrouter preset apply team-glm               # re-sync one existing profile
claude-openrouter preset apply --all                  # re-sync every preset-backed profile
```

The interactive create/update flow supports the two preset shapes the launcher
already understands: `preset` for one model pinned to one or more providers,
and `fusion` for a panel plus judge. It displays the local and remote changes
before asking for confirmation.

Automation uses the same implementation without prompts. Repeat `--provider`
or `--panel-model` for multiple values:

```bash
claude-openrouter preset create team-glm \
  --type preset \
  --preset-slug cc-team-glm \
  --model z-ai/glm-5.2 \
  --provider fireworks \
  --fallback z-ai/glm-5.2 \
  --key-file ~/.config/openrouter.env \
  --no-input --yes
```

Editing a fusion panel is additive or replacement — pick one per invocation.
`--panel-model` **replaces** the whole panel, so re-specify every model you want
to keep. `--add-panel-model` / `--remove-panel-model` (repeatable, `update`
only) change single entries and leave the rest alone:

```bash
claude-openrouter preset update fusion \
  --add-panel-model deepseek/deepseek-v3.2 \
  --remove-panel-model qwen/qwen3-coder-plus \
  --no-input --yes
```

Adding a model that is already on the panel is a no-op; removing one that isn't
fails (`not_found`) and leaves the panel untouched. `--dry-run` previews the
merged panel without writing.

Fusion profiles also accept optional tuning knobs, stored in the preset and
compared for drift like the panel and judge. Absent knobs stay at OpenRouter
defaults:

```bash
claude-openrouter preset update fusion \
  --max-tool-calls 2 \
  --temperature 0.7 \
  --max-completion-tokens 8000 \
  --reasoning-effort medium \
  --reasoning-max-tokens 2000 \
  --no-input --yes
```

`--max-tool-calls` takes 1–16, `--temperature` 0–2 (panel only; the analyst
always runs at 0). `preset view` and `doctor` surface knob drift the same way
they surface panel/judge drift.

Use `--dry-run` to print the plan without writing local or remote state. An
existing configuration file is backed up as `<config>.bak`, then replaced
atomically under a short-lived `<config>.lock` directory. If the remote update
fails after the local file is saved, the readiness marker stays absent and the
launcher uses the configured fallback. Retry safely with
`claude-openrouter preset apply <profile-name>`.

`presets [--json]` remains available for compatibility with the original list
command. New scripts should use `preset list` and the canonical
`-o table|json|name` output selector.

---

## Providing your key

Three ways, in precedence order **`--key` > `--key-file` > `$OPENROUTER_API_KEY`**:

```bash
bin/claude-openrouter --key sk-or-v1-...             # 1. on the command line
bin/claude-openrouter --key-file ~/.config/or.env    # 2. a file containing OPENROUTER_API_KEY=...
export OPENROUTER_API_KEY=sk-or-v1-... && bin/claude-openrouter   # 3. environment variable
```

Your key is injected only as `ANTHROPIC_AUTH_TOKEN` into the `claude` process (in a subshell) — **never written to disk, never exported into your shell.** Key files are parsed with `sed`, not sourced.

---

## Commands

```bash
claude-openrouter -g                              # launch the default mode (no other args needed)
claude-openrouter --profile NAME [args…]          # use a named profile (fusion preset or model alias)
claude-openrouter --backend "vendor/model" [args…]  # use a raw OpenRouter slug directly
claude-openrouter --mode MODE [args…]             # launch a mode; extra args pass through to claude (e.g. -p "…")
claude-openrouter modes [--json]                  # list modes and their per-slot models
claude-openrouter profiles [--json]               # list profiles and their targets
claude-openrouter models [QUERY] [--json]         # find a model slug (public API — no key needed)
claude-openrouter providers SLUG [--sort …]       # who serves a model, at what ctx/price/uptime
claude-openrouter preset <command>                # list/view/create/update/apply presets
claude-openrouter presets [--json]                # legacy alias for preset listing
claude-openrouter doctor                          # health check: deps, key, credits, preset, env conflicts
claude-openrouter --show-settings                 # print the resolved settings JSON, no launch (alias: --dry-run)
claude-openrouter --cost --mode … -p …            # run, then report what that session cost on OpenRouter
claude-openrouter --config FILE preset view NAME  # use one explicit config file
claude-openrouter --help                          # usage
```

Repo tasks (run as `make <t>` or `just <t>`): `check` (verify deps) · `lint` (shellcheck) · `test` (no-cost smoke tests) · `setup` · `install` (symlink onto PATH and fpath; `PREFIX` / `COMPLETION_PREFIX` overridable) · `hooks` (enable the gitleaks pre-commit hook). `just all` runs lint + tests.

### Shell completion

`make install` places a zsh completion at `~/.zfunc/_claude-openrouter` alongside the launcher symlink. Add that directory to your `fpath` **before** `compinit` runs:

```zsh
fpath=(~/.zfunc $fpath)
autoload -Uz compinit && compinit
```

Then subcommands, flags, and — the useful part — your own config values complete:

```
$ claude-openrouter --profile <TAB>
deepseek  fusion  glm  glm-exacto  glm-fireworks  glm-nitro  qwen
$ claude-openrouter --mode <TAB>
extreme  main  subagent
```

Those values are read from the launcher at completion time via `profiles --json` and `modes --json`, not from a list baked into the completion file. Add a profile to `config/modes.json` and it completes on the next TAB — no regeneration, no reload. Override the destination with `make install COMPLETION_PREFIX=~/.zsh/completions`.

Only zsh is supported today. bash and fish completions are not shipped; `--backend` and `providers` complete no model slugs, since that would mean a network call to `/models` on every keystroke.

### Startup connectivity check

Before launching Claude, the launcher runs a fast pre-flight: if OpenRouter is unreachable or your key is rejected, it prints a one-line hint to run `claude-openrouter doctor` — so you aren't surprised by cryptic mid-session errors. Silent on success. Disable with `COL_SKIP_PRECHECK=1`.

It also **verifies preset-backed profiles**: when the active profile resolves to an `@preset/<slug>` (any `fusion` or `preset` profile whose preset has been set up), the launcher confirms that preset still exists on your account with a free, no-inference `GET /presets/<slug>`. If it's missing or deleted, the launcher aborts before starting Claude with a fix hint (`claude-openrouter preset apply <name>`) instead of failing mid-session. Also skipped by `COL_SKIP_PRECHECK=1`.

---

## Cost & latency

A fusion turn runs several models plus a judge, so it costs and takes more than a single model — observed roughly **$0.15–0.35 per fusion turn** vs ~$0.01 for one Opus turn. By mode: `subagent` is cheapest (backend only on subagent spawns), `main` routes every main turn through the backend, `extreme` is the most expensive. Keep prompts focused, and use `--cost` to see a session's actual spend (it waits briefly, with a countdown, for OpenRouter billing to settle).

---

## Troubleshooting

Run **`claude-openrouter doctor`** first — it checks most of these and prints a fix for each.

| Symptom | Likely cause / fix |
|---|---|
| `preset not set up — using fallback` | The preset has not been synchronized for this OpenRouter key/account. Run `claude-openrouter preset apply <name>`; `doctor` verifies the result. |
| `OpenRouter rejected the key` | Key wrong/expired, or wrong `--key`/`--key-file`/`OPENROUTER_API_KEY`. |
| `insufficient credits` / requests fail | Add credits at <https://openrouter.ai/settings/credits>; `doctor` shows your balance. |
| `model not found` errors | A panel slug in `config/modes.json` is invalid — check it against <https://openrouter.ai/api/v1/models>. |
| Claude Code ignores the base URL / "model not found" | A cached Anthropic login or a real `ANTHROPIC_API_KEY` in your shell can interfere. The launcher unsets it per-run; if it persists, `/logout` in Claude Code and unset the key (`doctor` warns if it's set). |
| `--cost` says "no usage change detected" | OpenRouter billing lagged past the ~30s wait; check <https://openrouter.ai/activity>. |
| The advisor never fires | Expected — Claude Code's advisor is a server-side Anthropic tool that doesn't work through OpenRouter (it's disabled here). Use `main`/`extreme` (backend as main) or `subagent` (backend in subagents) instead. |

---

## How it works

Claude Code is pointed at OpenRouter via `ANTHROPIC_BASE_URL=https://openrouter.ai/api`, `ANTHROPIC_AUTH_TOKEN=<key>`, `ANTHROPIC_API_KEY=""`. Fusion is reached through model slugs:

- **Fusion is a server tool, not a model.** `openrouter/fusion` runs a *default* 3-model panel. To run a *custom* panel you need an OpenRouter **preset** whose `config.model` is `openrouter/fusion` plus a `tools:[{type:"openrouter:fusion",parameters:{analysis_models:[…],model:<judge>}}]` block with `tool_choice:"required"`. `setup.sh` creates exactly that and the launcher references it as `@preset/<slug>`.
- **`@preset/` works on the Anthropic `/messages` endpoint** Claude Code uses, and **`CLAUDE_CODE_SUBAGENT_MODEL`** routes subagents to it — that's how `subagent` mode gives you fusion as an on-demand second opinion.
- **The Claude Code advisor doesn't work through OpenRouter** (server-side Anthropic tool); it's disabled via `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`. Fusion reaches you through the main tier and/or subagents instead.
- **Presets are created only via** `POST /api/v1/presets/{slug}/chat/completions` (the direct `POST /api/v1/presets` returns 404).

The connectivity warning is a launcher pre-flight, not a SessionStart hook: such a hook *does* execute, but Claude Code currently **discards SessionStart hook output** on new sessions ([anthropics/claude-code#10373](https://github.com/anthropics/claude-code/issues/10373)), so it can't show you the warning. A pre-flight prints reliably.

### Fusion presets and Claude Code

**Why presets matter.** Claude Code's `settings.json` can only route model *names* per slot (via env vars like `ANTHROPIC_DEFAULT_OPUS_MODEL`) — it cannot inject per-request body fields such as a `plugins` array or a `tools` array. So there is no way to tell Claude Code "fuse with this custom panel" inline. An OpenRouter **preset** solves that: the panel + judge config lives server-side under a slug, and the slot just names `@preset/<slug>` as if it were a model.

**How presets and Fusion work together.** `setup.sh` (or `preset create`/`apply`) stores this config on your OpenRouter account via `POST /api/v1/presets/{slug}/chat/completions`:

```json
{
  "model": "openrouter/fusion",
  "tools": [{ "type": "openrouter:fusion",
               "parameters": { "analysis_models": ["~anthropic/claude-opus-latest", "…"],
                               "model": "~anthropic/claude-opus-latest" } }],
  "tool_choice": "required"
}
```

Every request naming `@preset/<slug>` then runs the full pipeline: the panel answers in parallel, the judge compares them into structured analysis (consensus, contradictions, blind spots), and the serving model writes the final answer from it. `preset view <name>` shows the stored panel/judge and whether local config still matches (`in-sync`/`drifted`).

**Why the `tools` form, not the newer `plugins` form.** OpenRouter's docs now recommend configuring Fusion per-request with `plugins: [{id: "fusion", …}]`. We tested that form against the live API (2026-09-04) and it **does not work inside presets**: the create call succeeds, but the stored `designated_version.config` silently drops the `plugins` entry, keeping only the bare alias — and inference through such a preset deliberates with the *default* 3-model panel, not the configured one. The `tools` form above round-trips verbatim (panel, judge, `tool_choice`), including newer knobs such as `max_tool_calls` and `temperature` (both verified persisted live). Since presets are our only vehicle into Claude Code, the launcher stays on the `tools` form. If OpenRouter ever persists `plugins` in presets, that decision should be re-tested, not assumed.

---

## Development

```bash
make check     # verify deps (claude, curl, jq)
just all       # shellcheck + no-cost smoke tests  (or: just lint / just test)
```

CI (GitHub Actions) runs shellcheck, actionlint, and the no-cost smoke tests on every push. A gitleaks pre-commit hook is available via `make hooks`.

## License

MIT — see [LICENSE](LICENSE).
