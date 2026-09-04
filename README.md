# Claude OpenRouter Launcher

[![CI](https://github.com/smorinlabs/claude-openrouter-launcher/actions/workflows/ci.yml/badge.svg)](https://github.com/smorinlabs/claude-openrouter-launcher/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Claude Code, with the backend you choose.**

Claude OpenRouter Launcher connects Claude Code to OpenRouter, so you can use a
single model, pin a model to a specific provider, or ask a multi-model
[Fusion panel](https://openrouter.ai/docs/guides/routing/routers/fusion-router)
to deliberate before answering. You keep the Claude Code workflow while gaining
explicit control over which backend handles each kind of work.

- **Choose the right model for the task.** Launch a named profile or any raw
  OpenRouter model slug.
- **Control where it runs.** Use the selected backend for the main conversation,
  subagents, or every Claude Code model slot.
- **Manage presets from the terminal.** List, inspect, create, update, preview,
  and synchronize OpenRouter presets without editing generated settings.
- **See what will happen.** Preview resolved settings, check account and preset
  health, and report the cost of a session.

[Quick start](#quick-start) · [Examples](#examples) ·
[How routing works](#how-routing-works) · [Complete guide](docs/guide.md)

## Quick start

### 1. Install

Prerequisites: [Claude Code](https://code.claude.com/docs/en/getting-started),
an [OpenRouter API key](https://openrouter.ai/settings/keys), Bash, `git`,
`make`, `curl`, and `jq`.

```bash
git clone https://github.com/smorinlabs/claude-openrouter-launcher.git
cd claude-openrouter-launcher
make install
```

`make install` links `claude-openrouter` into `~/.local/bin` and installs zsh
completion into `~/.zfunc`. If the command is not found, add the install
directory to your shell path:

```zsh
export PATH="$HOME/.local/bin:$PATH"
```

### 2. Authenticate and prepare the bundled presets

```bash
export OPENROUTER_API_KEY="replace-with-your-openrouter-key"
claude-openrouter preset apply --all
```

`preset apply --all` creates or updates the remote OpenRouter presets described
by the local configuration. It changes presets in the OpenRouter account that
owns the resolved API key. Model-only profiles do not require this step.

### 3. Launch Claude Code

```bash
claude-openrouter -g
```

The bundled defaults select the `fusion` profile in `extreme` mode. That means
the configured Fusion panel is used for every Claude Code model slot. Arguments
that the launcher does not consume are passed through to `claude`.

## Examples

Start an interactive session with the configured defaults:

```bash
claude-openrouter -g
```

Run a one-shot prompt on the bundled DeepSeek profile:

```bash
claude-openrouter --profile deepseek -p "Review this repository for race conditions"
```

Use a raw OpenRouter model slug without creating a profile:

```bash
claude-openrouter --backend "qwen/qwen3-coder-plus" -p "Explain the build failure"
```

Keep the configured Claude models for the main conversation and use Fusion only
when Claude Code creates a subagent:

```bash
claude-openrouter --profile fusion --mode subagent -g
```

Preview the exact settings file without launching Claude Code or requiring an
API key:

```bash
claude-openrouter --profile glm-fireworks --mode main --show-settings
```

## How routing works

The launcher separates two decisions that are easy to conflate:

| Decision | Configuration term | Question it answers | Example |
|---|---|---|---|
| Backend selection | **Profile** | What model or preset should handle the request? | `fusion`, `deepseek`, `glm-fireworks` |
| Slot placement | **Mode** | Where should that backend be used inside Claude Code? | `subagent`, `main`, `extreme` |

A **preset slug** is different from both. It is the remote identifier stored in
an OpenRouter account, such as `cc-fusion`. A local profile such as `fusion`
can reference that remote preset slug.

### Profiles: choose the backend

| Profile type | What it selects | Remote setup required? |
|---|---|:---:|
| `model` | One OpenRouter model slug, optionally with a routing variant | No |
| `preset` | One model constrained to one or more provider tags | Yes |
| `fusion` | Multiple panel models plus a judge model | Yes |
| Direct `--backend` | One raw model slug with no named profile | No |

List the profiles in the active configuration:

```bash
claude-openrouter profiles
```

### Modes: choose where it runs

| Bundled mode | Main conversation | Subagents | Relative use of the selected backend |
|---|---|---|---|
| `subagent` | Configured Claude model aliases | Selected backend | Lowest |
| `main` | Selected backend for the default/Opus slot; configured Claude aliases for Sonnet and Haiku | Selected backend | Medium |
| `extreme` *(default)* | Selected backend in every slot | Selected backend | Highest |

The relative-use column describes how often the selected backend can be called,
not a guaranteed price. Actual cost depends on the model, provider, tokens, and
whether a Fusion panel is involved.

```bash
claude-openrouter modes
```

## Find models and providers

Search OpenRouter's public catalog for a model slug:

```bash
claude-openrouter models glm
claude-openrouter models glm --json
```

Compare the providers currently serving one model. The results include the
provider tag needed for a provider-pinned preset:

```bash
claude-openrouter providers z-ai/glm-5.2 --sort reliable
claude-openrouter providers z-ai/glm-5.2 --sort cheapest --json
```

Catalog availability, context limits, prices, and uptime are live OpenRouter
data. Treat output captured in documentation or scripts as a snapshot.

## Inspect and manage presets

The `preset` command group manages both sides of a preset-backed profile:

- the **local profile** saved in the launcher configuration; and
- the **remote preset** saved in the OpenRouter account for the resolved key.

```bash
claude-openrouter preset list
claude-openrouter preset view fusion
claude-openrouter preset create team-glm
claude-openrouter preset update team-glm
claude-openrouter preset apply team-glm
```

`preset create` and `preset update` are interactive in a terminal. They display
the proposed local and remote values before requesting confirmation. Use
`--dry-run` for a preview that writes neither side.

An unlinked remote preset is not an error. It means the preset exists in the
OpenRouter account, but no profile in the active local configuration references
its slug. Inspect it directly with:

```bash
claude-openrouter preset view --slug <remote-preset-slug>
```

The [complete guide](docs/guide.md#manage-openrouter-presets) explains the list
columns, synchronization states, non-interactive automation, panel replacement
versus additive edits, Fusion tuning knobs, backups, and recovery.

## Configuration

The bundled [`config/modes.json.example`](config/modes.json.example) works
without a setup copy. To customize it manually:

```bash
cp config/modes.json.example config/modes.json
```

The launcher resolves configuration in this order:

1. `--config FILE`
2. `CLAUDE_OPENROUTER_CONFIG`
3. `config/modes.json` in this repository
4. bundled `config/modes.json.example`

The first successful `preset create` or `preset update` based on the bundled
example creates `config/modes.json` automatically. See the
[configuration reference](docs/guide.md#configure-the-launcher) for the schema,
custom modes, routing variants, and explicit config files.

## Authentication, safety, and cost

For launcher and legacy commands, key precedence is
`--key` → `--key-file` → `OPENROUTER_API_KEY`. Canonical `preset` commands use
`--key-file` or `OPENROUTER_API_KEY`; they intentionally do not accept a
plaintext `--key` flag.

Prefer `--key-file` or `OPENROUTER_API_KEY` when using the launcher or legacy
commands. A key supplied with `--key` can remain in shell history and may be
visible to other local processes through the process list.

The launcher passes the resolved key to the child `claude` process as
`ANTHROPIC_AUTH_TOKEN` inside a subshell. It does not write the key to the
launcher configuration or export it into the parent shell. Key files are parsed
as data rather than sourced as shell code.

Fusion can call several panel models and a judge for one request, so it normally
costs more and takes longer than a single-model request. Measure a session
against OpenRouter's usage data with:

```bash
claude-openrouter --cost --profile fusion --mode main -p "Design a migration plan"
```

See [authentication and key handling](docs/guide.md#authenticate) and
[cost reporting](docs/guide.md#cost-reporting) for details and limitations.

## Command map

| Command | Purpose |
|---|---|
| `claude-openrouter -g` | Launch the configured default profile and mode |
| `claude-openrouter --profile NAME [claude args...]` | Launch a named backend profile |
| `claude-openrouter --backend SLUG [claude args...]` | Launch a raw OpenRouter model slug |
| `claude-openrouter profiles [--json]` | List local profiles and resolved targets |
| `claude-openrouter modes [--json]` | List modes and per-slot routing |
| `claude-openrouter models [QUERY] [--json]` | Search the public model catalog |
| `claude-openrouter providers SLUG [--sort ...] [--json]` | Compare serving providers |
| `claude-openrouter preset <command>` | List, view, create, update, or apply presets |
| `claude-openrouter doctor` | Diagnose dependencies, authentication, credits, presets, and environment conflicts |
| `claude-openrouter --show-settings` | Print resolved settings without launching |
| `claude-openrouter --cost [claude args...]` | Launch and report the observed usage change |

For complete flags, output formats, exit behavior, and examples, read the
**[Claude OpenRouter Launcher guide](docs/guide.md)** or run:

```bash
claude-openrouter --help
claude-openrouter preset --help
claude-openrouter preset <command> --help
```

## Development

```bash
make check     # verify Claude Code, curl, and jq
just all       # run shellcheck and no-cost smoke tests
```

GitHub Actions also runs shellcheck, actionlint, and the smoke tests. Enable the
repository's gitleaks pre-commit hook with `make hooks`.

## License

MIT — see [LICENSE](LICENSE).
