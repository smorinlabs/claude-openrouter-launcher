# Claude OpenRouter Launcher guide

This guide is the operational reference for Claude OpenRouter Launcher. Start
with the [README quick start](../README.md#quick-start) if you only need to
install and launch the bundled defaults.

## Contents

- [Understand the three names](#understand-the-three-names)
- [Install](#install)
- [Authenticate](#authenticate)
- [Launch Claude Code](#launch-claude-code)
- [Choose a profile](#choose-a-profile)
- [Choose a mode](#choose-a-mode)
- [Discover models and providers](#discover-models-and-providers)
- [Manage OpenRouter presets](#manage-openrouter-presets)
- [Configure the launcher](#configure-the-launcher)
- [Automate commands](#automate-commands)
- [Enable zsh completion](#enable-zsh-completion)
- [Run diagnostics](#run-diagnostics)
- [Cost reporting](#cost-reporting)
- [How the integration works](#how-the-integration-works)
- [Upgrade from an earlier release](#upgrade-from-an-earlier-release)
- [Troubleshoot](#troubleshoot)

## Understand the three names

Three identifiers participate in routing. They describe different things:

| Identifier | Where it exists | What it means | Example |
|---|---|---|---|
| **Local profile name** | Launcher configuration | A reusable name for one backend definition | `fusion` |
| **Remote preset slug** | One OpenRouter account | A user-chosen identifier stored with a preset | `cc-fusion` |
| **Mode name** | Launcher configuration | A mapping that decides which Claude Code slots use the selected backend | `subagent` |

For example, the local profile `fusion` can reference the remote preset slug
`cc-fusion`. Selecting mode `subagent` then places `@preset/cc-fusion` only in
Claude Code's subagent slot.

The full request path is:

```text
launcher arguments
    → local profile (what backend)
    → local mode (which Claude Code slots)
    → generated Claude Code settings
    → OpenRouter model or remote preset
```

## Install

### Requirements

The launcher requires:

- [Claude Code](https://code.claude.com/docs/en/getting-started)
- an [OpenRouter API key](https://openrouter.ai/settings/keys)
- Bash, `curl`, and `jq` at runtime
- `git` and `make` for the installation sequence below

Run `make check` from the repository to verify Claude Code, `curl`, and `jq`.
Run `bash --version` to verify Bash separately.

### Standard installation

```bash
git clone https://github.com/smorinlabs/claude-openrouter-launcher.git
cd claude-openrouter-launcher
make install
```

The default installation creates these symbolic links:

| Installed path | Target | Purpose |
|---|---|---|
| `~/.local/bin/claude-openrouter` | `bin/claude-openrouter` in the clone | Launcher command |
| `~/.zfunc/_claude-openrouter` | `completions/_claude-openrouter` in the clone | zsh completion |

Because the links point into the clone, keep the repository at that path. To
use different destinations:

```bash
make install PREFIX=/your/bin/directory COMPLETION_PREFIX=/your/zsh/functions
```

`make install` does not edit shell startup files. Add the binary directory to
`PATH` yourself if it is not already present:

```zsh
export PATH="$HOME/.local/bin:$PATH"
```

### Flox environment

The repository includes a [Flox](https://flox.dev) environment that provides
Claude Code, `curl`, `jq`, `shellcheck`, `just`, and `gitleaks` at pinned
versions:

```bash
flox activate
```

Activation adds the repository's `bin` directory to `PATH`. It does not create
or update remote OpenRouter presets; run `claude-openrouter preset apply --all`
after authentication when you want to use the preset-backed profiles.

## Authenticate

### Environment variable

Set the key for the current shell:

```bash
export OPENROUTER_API_KEY="replace-with-your-openrouter-key"
```

Do not commit an API key to this repository or place it in the launcher JSON
configuration.

### Key file

A key file keeps the secret out of command history. Its content may use either
of these forms:

```dotenv
OPENROUTER_API_KEY=replace-with-your-openrouter-key
```

```dotenv
export OPENROUTER_API_KEY=replace-with-your-openrouter-key
```

Pass the path explicitly:

```bash
claude-openrouter --key-file ~/.config/openrouter.env -g
claude-openrouter preset list --key-file ~/.config/openrouter.env
```

The parser reads the first `OPENROUTER_API_KEY` assignment as data. It does not
source or execute the file.

### Key precedence

The launcher and legacy commands resolve a key in this order:

1. `--key KEY`
2. `--key-file FILE`
3. `OPENROUTER_API_KEY`

Prefer `--key-file` or `OPENROUTER_API_KEY`. A key supplied with `--key` can
remain in shell history and may be visible to other local processes through
the process list.

The canonical `preset list`, `preset view`, `preset create`, `preset update`,
and `preset apply` commands intentionally omit `--key`. They accept
`--key-file` or the environment variable so the secret is not exposed as a
process argument.

The resolved key is assigned to `ANTHROPIC_AUTH_TOKEN` only inside the child
process that runs Claude Code. The launcher clears `ANTHROPIC_API_KEY` for that
child and does not export either change into the parent shell.

## Launch Claude Code

### Default interactive session

```bash
claude-openrouter -g
```

`-g` and `--go` mean “launch with the configured defaults.” With no actionable
arguments, the command prints help and offers to launch only when both input and
output are interactive terminals.

### Pass arguments to Claude Code

Arguments not recognized by the launcher are forwarded to `claude`:

```bash
claude-openrouter --profile deepseek -p "Find the bug in this function"
claude-openrouter --mode main -- --permission-mode plan
```

Use `--` when a Claude Code flag could be confused with a future launcher flag.

### Launcher options

| Option | Effect |
|---|---|
| `-g`, `--go` | Launch with no additional Claude Code arguments |
| `--profile NAME` | Select a local profile |
| `--backend SLUG` | Use a raw OpenRouter model slug without a profile |
| `--mode NAME` | Select where the backend is placed |
| `--key KEY` | Supply the key as an argument; it can appear in shell history and process listings. Prefer `--key-file` or `OPENROUTER_API_KEY` |
| `--key-file FILE` | Read the key from a file |
| `--config FILE` | Use one explicit launcher configuration |
| `--show-settings`, `--dry-run` | Render and print settings without launching |
| `--cost` | Measure the account usage change around the session |

`--profile` and `--backend` are mutually exclusive because one selects a named
local definition while the other bypasses local profiles.

### Preview resolved settings

`--show-settings` is the safest way to verify a profile and mode combination:

```bash
claude-openrouter --profile fusion --mode main --show-settings
```

The command reports the selected mode, profile, configuration path, resolved
backend, generated settings path, and formatted JSON. It does not require an
OpenRouter key or the `claude` executable.

## Choose a profile

A profile defines the backend that replaces each `backend` placeholder in a
mode. List the active definitions and their resolved targets:

```bash
claude-openrouter profiles
claude-openrouter profiles --json
```

### Model profile

A `model` profile gives a reusable name to one OpenRouter model slug:

```json
"deepseek": {
  "type": "model",
  "model": "deepseek/deepseek-v3.2"
}
```

It needs no remote preset:

```bash
claude-openrouter --profile deepseek -g
```

The bundled configuration documents these OpenRouter routing variants and
includes profiles that use `:nitro` and `:exacto`:

| Suffix | Routing intent documented by the bundled configuration |
|---|---|
| no suffix | Balanced provider routing |
| `:nitro` | Prefer throughput |
| `:floor` | Prefer price |
| `:exacto` | Prefer providers with stronger quality signals |

These suffixes ask OpenRouter to choose a provider. They do not pin one named
provider.

### Provider-pinned preset profile

A `preset` profile stores a model and provider constraint in OpenRouter:

```json
"glm-fireworks": {
  "type": "preset",
  "preset_slug": "cc-glm-fireworks",
  "model": "z-ai/glm-5.2",
  "provider": { "only": ["fireworks"] },
  "fallback": "z-ai/glm-5.2"
}
```

After `preset apply`, the profile resolves to `@preset/cc-glm-fireworks`. Before
the preset has been verified, it resolves to the unpinned fallback model.

### Fusion profile

A `fusion` profile defines models that deliberate in parallel and a judge that
synthesizes their analysis:

```json
"fusion": {
  "type": "fusion",
  "preset_slug": "cc-fusion",
  "panel_models": [
    "~anthropic/claude-opus-latest",
    "~openai/gpt-latest",
    "~google/gemini-pro-latest"
  ],
  "judge_model": "~anthropic/claude-opus-latest",
  "fallback": "openrouter/fusion"
}
```

The custom panel must be stored as a remote preset before Claude Code can name
it as `@preset/<slug>`. Run:

```bash
claude-openrouter preset apply fusion
```

### Direct backend

Use `--backend` for a one-off slug that does not need a local name:

```bash
claude-openrouter --backend "qwen/qwen3-coder-plus" --mode main -g
```

Direct backends cannot carry a launcher-managed provider constraint. Create a
`preset` profile when you must pin a provider.

## Choose a mode

A mode maps Claude Code's model slots. The literal value `backend` resolves to
the active profile or direct backend.

```bash
claude-openrouter modes
claude-openrouter modes --json
```

The bundled modes are:

| Mode | `default` | `opus` | `sonnet` | `haiku` | `subagent` |
|---|---|---|---|---|---|
| `subagent` | `opus` | Claude Opus alias | Claude Sonnet alias | Claude Haiku alias | `backend` |
| `main` | `opus` | `backend` | Claude Sonnet alias | Claude Haiku alias | `backend` |
| `extreme` | `backend` | `backend` | `backend` | `backend` | `backend` |

Use `subagent` when the selected backend should act as an on-demand second
opinion. Use `main` when it should handle the default/Opus path and subagents.
Use `extreme` when every slot should resolve to it.

The names “lowest,” “medium,” and “highest” describe relative backend use only.
They are not price guarantees.

## Discover models and providers

### Search models

`models` searches model IDs and display names case-insensitively:

```bash
claude-openrouter models
claude-openrouter models glm
claude-openrouter models glm --json
```

The endpoint is public, so the command does not need a key or launcher
configuration. Human output shows the slug, display name, context limit, and
input/output prices per one million tokens. Results are sorted by slug.

A query with no matches prints a diagnostic and exits `1`. In JSON mode it
prints `[]` and still exits `1`, which makes the command usable as a grep-style
probe.

### Compare providers

`providers` lists the OpenRouter endpoints currently serving one model:

```bash
claude-openrouter providers z-ai/glm-5.2
claude-openrouter providers z-ai/glm-5.2 --sort cheapest
claude-openrouter providers z-ai/glm-5.2 --sort expensive
claude-openrouter providers z-ai/glm-5.2 --sort reliable
claude-openrouter providers z-ai/glm-5.2 --json
```

The human table shows each provider `tag`, context limit, input/output price,
and reported 30-day uptime. The `tag` is the exact value accepted by repeatable
`--provider TAG` flags and the `provider.only` configuration array.

This endpoint is also public. Model availability, endpoint data, and pricing
can change independently of this repository.

## Manage OpenRouter presets

The `preset` command group joins two sources:

- **Remote source:** presets in the OpenRouter account for the resolved API key.
- **Local source:** `fusion` and `preset` profiles in the active launcher JSON.

### List the combined inventory

```bash
claude-openrouter preset list
```

Example shape:

```text
Presets

Remote source: OpenRouter account for the resolved API key
Local source:  /path/to/claude-openrouter-launcher/config/modes.json

PRESET SLUG       OPENROUTER  LOCAL PROFILE  LINK STATE
cc-fusion         present     fusion         linked
cc-experiment     present     (none)         not linked to this config
cc-team-model     missing     team-model     missing from OpenRouter
```

Read each column independently:

| Column | Source | Meaning |
|---|---|---|
| `PRESET SLUG` | Both | The identifier used to join a local profile to a remote preset |
| `OPENROUTER` | Remote account | `present` when that account contains the slug; otherwise `missing` |
| `LOCAL PROFILE` | Active config file | The profile that references the slug; `(none)` means no profile in this config references it |
| `LINK STATE` | Derived relationship | Whether both sides are linked, remote-only, or local-only |

“Not linked to this config” is harmless. It does not mean the remote preset is
broken or unused by every application. It means only that the active launcher
configuration does not reference it. The launcher deliberately has no delete
command; delete unwanted remote presets at
<https://openrouter.ai/settings/presets>.

On a narrow terminal, the same fields render as stacked records. Redirected
output remains a deterministic table.

### Understand list output modes

```bash
claude-openrouter preset list -o table
claude-openrouter preset list -o json
claude-openrouter preset list -o name
```

`table` is the combined remote/local inventory. For backward compatibility,
`json` returns OpenRouter's remote preset array and `name` returns only sorted
remote slugs. A script that needs the relationship can combine
`preset list --json` with `profiles --json`, or inspect a known profile with
`preset view --json`.

The plural command remains as a compatibility alias:

```bash
claude-openrouter presets
claude-openrouter presets --json
```

New scripts should use `preset list`.

### Inspect one preset

Use a local profile name when the preset is linked:

```bash
claude-openrouter preset view fusion
```

Use the remote slug when no local profile is linked:

```bash
claude-openrouter preset view --slug cc-experiment
```

`preset view` shows the resolved remote configuration and one of these
synchronization states:

| Status | Meaning | Next action |
|---|---|---|
| `in-sync` | Managed local fields match the remote preset | None |
| `drifted` | The local profile and remote preset differ | Review, then run `preset apply <profile>` if local should win |
| `orphan` | The remote slug has no linked profile in this config | Keep it, link it manually, or delete it in OpenRouter |

For Fusion, drift comparison includes the panel, judge, required tool choice,
and managed tuning knobs. For a provider-pinned preset, it includes the model
and every provider constraint set by the local profile. Extra remote fields
that the launcher does not manage are ignored.

### Create a preset interactively

```bash
claude-openrouter preset create
```

The command asks for a local profile name, profile type, remote slug, and the
fields required by that type. It then displays a plan and asks for confirmation.
Choosing no exits successfully without changing either source.

You may supply the profile name and let the remaining prompts continue:

```bash
claude-openrouter preset create team-glm
```

### Create a preset non-interactively

Provider-pinned example:

```bash
claude-openrouter preset create team-glm \
  --type preset \
  --preset-slug cc-team-glm \
  --model z-ai/glm-5.2 \
  --provider fireworks \
  --fallback z-ai/glm-5.2 \
  --no-input --yes
```

Repeat `--provider` to allow more than one provider.

Fusion example:

```bash
claude-openrouter preset create team-fusion \
  --type fusion \
  --preset-slug cc-team-fusion \
  --panel-model '~anthropic/claude-opus-latest' \
  --panel-model '~openai/gpt-latest' \
  --judge-model '~anthropic/claude-opus-latest' \
  --fallback openrouter/fusion \
  --no-input --yes
```

`--no-input` prevents prompts. `--yes` supplies the required confirmation.
Automation should normally use both.

### Update a preset

Interactive update starts from the current local values:

```bash
claude-openrouter preset update fusion
```

Non-interactive flags change only the supplied scalar fields, with one important
exception: repeatable `--provider` and `--panel-model` values represent complete
arrays.

#### Replace or edit a Fusion panel

`--panel-model` replaces the entire panel. Re-specify every model to keep:

```bash
claude-openrouter preset update fusion \
  --panel-model '~anthropic/claude-opus-latest' \
  --panel-model deepseek/deepseek-v3.2 \
  --judge-model '~anthropic/claude-opus-latest' \
  --no-input --yes
```

Use additive flags to change individual entries while preserving the rest:

```bash
claude-openrouter preset update fusion \
  --add-panel-model deepseek/deepseek-v3.2 \
  --remove-panel-model qwen/qwen3-coder-plus \
  --no-input --yes
```

Additions are idempotent: adding an existing model changes nothing. Removing a
model that is not present exits with `not_found` and leaves the panel unchanged.
Replacement and additive flags cannot be combined in one invocation.

#### Tune Fusion

Fusion profiles accept these optional settings:

| Flag | Stored field | Validation | Meaning |
|---|---|---|---|
| `--max-tool-calls N` | `max_tool_calls` | Integer from 1 through 16 | Maximum web-search steps for an inner call |
| `--temperature T` | `temperature` | Number from 0 through 2 | Panel temperature; the analyst remains at 0 |
| `--max-completion-tokens N` | `max_completion_tokens` | Positive integer | Maximum output tokens for each inner panel or analyst call |
| `--reasoning-effort E` | `reasoning.effort` | String passed through to OpenRouter | Reasoning effort sent to panel and analyst calls |
| `--reasoning-max-tokens N` | `reasoning.max_tokens` | Positive integer | Reasoning token budget sent to panel and analyst calls |

Example:

```bash
claude-openrouter preset update fusion \
  --max-tool-calls 2 \
  --temperature 0.7 \
  --max-completion-tokens 8000 \
  --reasoning-effort medium \
  --reasoning-max-tokens 2000 \
  --no-input --yes
```

On create, omitted knobs use OpenRouter defaults. On update, omitted knobs keep
their current local values. Tuning flags are rejected for a non-Fusion `preset`
profile. The CLI can set or replace a knob but has no dedicated unset flag. To
remove one, delete that field from the local JSON and run
`preset apply <profile>` after reviewing the change.

### Preview changes

`--dry-run` prints the merged local profile and target paths without reading a
key, writing a file, or calling OpenRouter:

```bash
claude-openrouter preset update fusion \
  --add-panel-model deepseek/deepseek-v3.2 \
  --dry-run
```

Preview synchronization separately:

```bash
claude-openrouter preset apply --all --dry-run
```

### Synchronize local definitions

Apply one profile:

```bash
claude-openrouter preset apply fusion
```

Apply every local `fusion` and `preset` profile:

```bash
claude-openrouter preset apply --all
```

`apply` treats the local configuration as the desired state and creates or
updates the corresponding remote presets. Model-only profiles are excluded.

`setup.sh` remains available as the original lower-level workflow:

```bash
./setup.sh --profile fusion --key-file ~/.config/openrouter.env
```

Prefer `preset apply` in new instructions and scripts.

### Understand write safety and recovery

`preset create` and `preset update` acquire `<config>.lock` before reading and
hold it through the write. A concurrent mutation exits with a conflict rather
than overwriting a stale copy.

The write sequence is:

1. Validate the proposed profile.
2. Write a temporary JSON file beside the target.
3. Copy an existing target to `<config>.bak`.
4. Atomically replace the target.
5. Synchronize the remote preset.
6. Write a per-slug readiness marker after the remote response is verified.

The local configuration is intentionally saved before the remote call. If the
remote call fails, the local change and backup remain, while the readiness
marker remains absent. The launcher then uses the profile's `fallback` instead
of claiming the preset is ready. Retry safely with:

```bash
claude-openrouter preset apply <local-profile>
```

## Configure the launcher

### Configuration resolution

The launcher resolves one JSON file in this order:

1. The path passed with `--config FILE`.
2. The path in `CLAUDE_OPENROUTER_CONFIG`.
3. `config/modes.json` beside the repository launcher.
4. The bundled `config/modes.json.example`.

For consistent placement with every subcommand, put an explicit config before
the command name:

```bash
claude-openrouter --config /path/to/team-modes.json profiles
claude-openrouter --config /path/to/team-modes.json preset view fusion
```

The bundled example is a valid runtime configuration. You do not need to copy
it unless you want local edits:

```bash
cp config/modes.json.example config/modes.json
```

If a mutation starts from the bundled example, the first successful
`preset create` or `preset update` writes `config/modes.json`. If an explicit or
environment-selected file is active, the mutation updates that file in place.

### Top-level fields

```json
{
  "default_profile": "fusion",
  "default_mode": "extreme",
  "profiles": {},
  "modes": {}
}
```

| Field | Purpose |
|---|---|
| `default_profile` | Profile selected when neither `--profile` nor `--backend` is present |
| `default_mode` | Mode selected when `--mode` is absent; falls back to `extreme` when omitted |
| `profiles` | Map of profile names to backend definitions |
| `modes` | Map of mode names to Claude Code slot mappings |

Profile names used by preset mutation commands may contain lowercase letters,
digits, dots, underscores, and hyphens. They cannot start with a hyphen, dot, or
underscore.

### Custom mode

Each mode may set `default`, `opus`, `sonnet`, `haiku`, and `subagent`. A value
may be a literal model slug or the special value `backend`:

```json
"review": {
  "default": "opus",
  "opus": "backend",
  "sonnet": "~anthropic/claude-sonnet-latest",
  "haiku": "~anthropic/claude-haiku-latest",
  "subagent": "backend"
}
```

Launch it with:

```bash
claude-openrouter --profile glm --mode review -g
```

### Runtime state

Generated state lives under:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/claude-openrouter/
```

It contains generated Claude Code settings and verified preset markers under
`presets/<slug>.json`. Do not treat generated settings as durable
configuration; change profiles and modes in the selected JSON file instead.

The settings filename includes the profile or sanitized direct backend plus the
mode. This prevents simultaneous sessions using different routes from sharing
one partially overwritten file. Each generated file is published atomically.

## Automate commands

### JSON output

Use JSON when a script needs structured output:

```bash
claude-openrouter profiles --json
claude-openrouter modes --json
claude-openrouter models glm --json
claude-openrouter providers z-ai/glm-5.2 --json
claude-openrouter preset view fusion --json
claude-openrouter preset update fusion --temperature 0.4 --no-input --yes --json
```

After `jq` is available, application-level preset errors in JSON mode are
written to standard error as one object:

```json
{
  "error": {
    "code": "not_found",
    "message": "profile 'missing' not found"
  }
}
```

### Preset exit statuses

Canonical preset commands use these status categories:

| Exit status | Category | Typical cause |
|---:|---|---|
| `0` | Success | Operation completed, dry-run completed, or interactive confirmation was declined |
| `1` | Operational failure | Invalid JSON config, network failure, unreadable response, write failure, or apply failure |
| `2` | Usage or validation failure | Unknown flag, missing required field, incompatible flags, or missing confirmation |
| `3` | Not found | Missing profile, remote preset, or requested panel member |
| `4` | Authentication failure | Missing, invalid, or rejected key |
| `5` | Conflict | Existing profile or slug, duplicate local link, or active config lock |
| `130` | Interrupted | Interactive operation received `SIGINT` |
| `143` | Terminated | Mutation received `SIGTERM` |

Other command families use conventional success/failure behavior rather than
this complete taxonomy. In particular, a `models` query with no matches exits
`1` even though the public API request succeeded.

## Enable zsh completion

`make install` puts `_claude-openrouter` in `~/.zfunc`. Add that directory to
`fpath` before zsh initializes completion:

```zsh
fpath=(~/.zfunc $fpath)
autoload -Uz compinit && compinit
```

Completion covers subcommands and flags. Profile and mode values are read from
the active launcher configuration at completion time, so a newly added value is
available on the next tab completion without regenerating the file.

Only zsh completion is included. Bash and fish completion files are not shipped.
Raw model slug completion is intentionally omitted because it would require an
OpenRouter catalog request while typing.

## Run diagnostics

Run the doctor before debugging individual requests:

```bash
claude-openrouter doctor
claude-openrouter doctor --key-file ~/.config/openrouter.env
```

It checks:

- the `claude`, `curl`, and `jq` executables;
- the selected configuration and available modes;
- the resolved API-key source and OpenRouter authentication;
- account credits when a key is available;
- remote existence and drift for preset-backed profiles;
- readiness markers; and
- conflicting Claude Code environment variables.

Critical failures produce a nonzero exit. Warnings identify conditions that do
not prevent every launch, such as a missing readiness marker that activates a
fallback.

### Startup preflight

Before launching Claude Code, the launcher performs two bounded checks:

1. It tests OpenRouter connectivity and key acceptance. Failure produces a
   warning and a `doctor` hint.
2. When the backend resolves to `@preset/<slug>`, it verifies that the preset
   still exists for the account. A confirmed missing preset stops the launch;
   a transient network or server failure warns and allows the launch.

Set `COL_SKIP_PRECHECK=1` to bypass both checks:

```bash
COL_SKIP_PRECHECK=1 claude-openrouter -g
```

This is a diagnostic escape hatch. It can move a clear startup failure into a
harder-to-understand mid-session failure.

## Cost reporting

`--cost` reads cumulative OpenRouter usage before and after the Claude Code
process, then reports the observed difference:

```bash
claude-openrouter --cost --profile fusion --mode main -p "Review this design"
```

OpenRouter usage can settle asynchronously, so the launcher polls for up to
approximately 30 seconds after Claude Code exits. If no change appears, it
prints a link to OpenRouter activity instead of claiming the session was free.

The calculation assumes no other workload changes the same OpenRouter account's
cumulative usage during the measurement window. Concurrent sessions or other
applications can make the reported difference include unrelated spend.

Fusion normally has higher cost and latency than a single model because panel
models and a judge can participate in one request. Use a less expansive mode or
a model-only profile when the extra deliberation is unnecessary.

## How the integration works

The launcher routes Anthropic-compatible requests through OpenRouter using a
combination of generated Claude Code settings and the child-process
environment:

```text
Generated settings:
ANTHROPIC_BASE_URL=https://openrouter.ai/api
ANTHROPIC_API_KEY=

Child-process environment:
ANTHROPIC_AUTH_TOKEN=[redacted]
```

The mode populates Claude Code model settings such as
`ANTHROPIC_DEFAULT_OPUS_MODEL` and `CLAUDE_CODE_SUBAGENT_MODEL`. Each `backend`
placeholder becomes a raw model slug or `@preset/<remote-slug>`.

### Why custom Fusion needs a preset

Claude Code settings can select model names per slot, but they cannot attach an
OpenRouter Fusion panel definition to every request. A remote preset stores the
panel and judge under one slug that Claude Code can select as if it were a
model.

The launcher writes this shape through OpenRouter's preset chat-completions
endpoint:

```json
{
  "model": "openrouter/fusion",
  "tools": [
    {
      "type": "openrouter:fusion",
      "parameters": {
        "analysis_models": ["~anthropic/claude-opus-latest", "..."],
        "model": "~anthropic/claude-opus-latest"
      }
    }
  ],
  "tool_choice": "required"
}
```

OpenRouter's general Fusion documentation may show a `plugins` request form.
Live validation performed for this repository on 2026-09-04 found that the
`plugins` field was dropped when stored inside a preset, while the `tools` form
round-tripped the panel, judge, tool choice, and supported knobs. The launcher
therefore uses the verified `tools` form. Re-test that decision against the live
API before changing the stored shape.

### Claude Code advisor limitation

The Claude Code advisor is an Anthropic server-side tool and does not operate
through this OpenRouter route. Generated settings set
`CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`. Use the selected backend in the main slot
or subagent slot instead.

### Why the warning is a preflight

A Claude Code `SessionStart` hook executes too late for a reliable visible
connectivity warning because Claude Code currently discards that hook's output
on new sessions ([anthropics/claude-code#10373](https://github.com/anthropics/claude-code/issues/10373)).
The launcher runs the check before starting Claude Code so the operator sees it.

## Upgrade from an earlier release

### From version 0.2.x preset state

Preset readiness is stored per remote slug. Run this once after upgrading:

```bash
claude-openrouter preset apply --all
```

Until a preset is verified and its new marker exists, a preset-backed profile
uses its configured fallback and prints a warning.

### From the `claude-fusion` name

Version 0.4.0 renamed the project to Claude OpenRouter Launcher without command
aliases:

| Earlier name | Current name |
|---|---|
| `claude-fusion` | `claude-openrouter` |
| `CLAUDE_FUSION_CONFIG` | `CLAUDE_OPENROUTER_CONFIG` |
| `~/.config/claude-fusion` | `~/.config/claude-openrouter` |

Remote OpenRouter preset slugs such as `cc-fusion` did not change. Re-run
`make install` to refresh the binary link, then run `preset apply --all` to
write readiness markers under the current state directory.

## Troubleshoot

| Symptom | Meaning | Action |
|---|---|---|
| `preset not set up ... using fallback` | No verified readiness marker exists for that slug | Run `claude-openrouter preset apply <profile>` |
| `missing from OpenRouter` in `preset list` | A local profile references a slug absent from this account | Apply that local profile, or correct its `preset_slug` |
| `not linked to this config` in `preset list` | A remote preset has no profile in the active config | Keep it, inspect with `preset view --slug`, link it, or delete it in OpenRouter |
| `drifted` in `preset view` or `doctor` | Managed local fields differ from the remote preset | Review both sides; run `preset apply <profile>` only when local should win |
| OpenRouter rejects the key | The resolved key is missing, expired, invalid, or belongs to a different account | Verify the key source with `doctor` and replace it if needed |
| Requests report insufficient credits | The account cannot fund the request | Add credits in OpenRouter and rerun `doctor` |
| Model not found | A configured model slug is unavailable or misspelled | Search with `claude-openrouter models <query>` and update the profile |
| Claude Code appears to ignore the route | Existing Anthropic authentication or `ANTHROPIC_API_KEY` may interfere | Run `doctor`, unset `ANTHROPIC_API_KEY`, and use `/logout` in Claude Code if cached login state persists |
| `--cost` reports no usage change | Usage did not settle within the polling window | Check <https://openrouter.ai/activity> |
| Advisor never runs | The Anthropic server-side advisor is disabled for OpenRouter routing | Use `main`, `extreme`, or a backend-enabled subagent instead |
| Configuration is locked | Another preset mutation owns `<config>.lock`, or a stale lock remains after an abnormal termination | Confirm no mutation is running before removing only that specific lock directory |

Start every investigation with:

```bash
claude-openrouter doctor
```

Then preview the exact route without launching:

```bash
claude-openrouter --profile <local-profile> --mode <mode> --show-settings
```
