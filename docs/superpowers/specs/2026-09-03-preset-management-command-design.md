# Preset inspection and management commands — design

**Date:** 2026-09-03  
**Target version:** v0.8.0  
**Project:** P09  
**Status:** approved and implemented  
**CLI standard:** v1.4.14, standard tier for this command group

## Purpose

Make OpenRouter presets inspectable and editable without requiring users to edit
`config/modes.json` by hand or remember that `setup.sh` performs synchronization.
The launcher already knew how to list account presets and create remote presets
from local profiles. This design exposes the complete lifecycle as one discoverable
`preset` command group.

A **profile** is the local launcher configuration selected by `--profile`. A
**preset slug** is the identifier of the corresponding remote OpenRouter preset.

## Command surface

```text
claude-openrouter preset list [flags]
claude-openrouter preset view <profile-name> [flags]
claude-openrouter preset view --slug <preset-slug> [flags]
claude-openrouter preset create [<profile-name>] [flags]
claude-openrouter preset update [<profile-name>] [flags]
claude-openrouter preset apply <profile-name> [flags]
claude-openrouter preset apply --all [flags]
```

| Command | Local effect | Remote effect |
|---|---|---|
| `list` | Reads profile links | Lists account presets |
| `view` | Reads the linked profile | Reads one preset and reports `in-sync`, `drifted`, or `orphan` |
| `create` | Adds one profile | Creates and verifies its preset |
| `update` | Replaces one managed profile definition | Updates and verifies its preset |
| `apply` | Reads one or all managed profiles | Synchronizes and verifies their presets |

`presets [--json]` remains as a compatibility command for the original account
listing. New scripts use `preset list`.

## Create and update behavior

Interactive use prompts for missing fields, shows a plan, and asks for confirmation.
Automation supplies the same fields as flags and uses `--no-input --yes`.

The supported profile shapes are:

- `type: "preset"`: `--model`, one or more `--provider` values, and an optional
  `--fallback`.
- `type: "fusion"`: one or more `--panel-model` values, `--judge-model`, and an
  optional `--fallback`.

`--dry-run` prints the complete local value and remote target without reading a key,
writing a file, or calling a mutation endpoint.

## Configuration safety

The writer validates the candidate JSON before replacement. It then:

1. acquires `<config>.lock` as a directory;
2. writes a temporary file in the configuration directory;
3. copies an existing configuration to `<config>.bak`;
4. atomically renames the temporary file over the target; and
5. removes the lock, including when `INT` or `TERM` interrupts the write.

When the launcher is still reading `config/modes.json.example`, the first mutation
creates `config/modes.json`. An explicit `--config FILE` is always updated in place.

The local configuration is committed before remote synchronization. If the remote
operation fails, the valid local profile remains, no readiness marker is created,
and the error provides the exact recovery command:

```text
claude-openrouter preset apply <profile-name>
```

Until recovery succeeds, launch resolution continues to use the profile's fallback.

## Output and exit contract

Human output defaults to `table`. `-o json` and `--json` emit structured results;
`preset list -o name` emits one sorted slug per line. Machine-readable errors use:

```json
{"error":{"code":"usage","message":"..."}}
```

Errors are written to standard error. Successful machine output is written to
standard output. Exit codes are stable for the new command group:

| Exit | Meaning |
|---:|---|
| `0` | Success, including a declined interactive confirmation |
| `1` | Operational, response, configuration, or synchronization failure |
| `2` | Usage or missing-input error |
| `3` | Requested profile, preset, or configuration not found |
| `4` | Authentication required or rejected |
| `5` | Local lock or create conflict |
| `130` / `143` | Interrupted by `INT` / `TERM` |

The canonical mutation commands accept `--key-file` or `OPENROUTER_API_KEY`; they
do not accept a plaintext key argument. The legacy commands retain their existing
`--key` behavior for compatibility.

## Implementation

- `lib/presets.sh` owns parsing, prompting, validation, views, safe local writes,
  synchronization orchestration, and result formatting.
- `lib/common.sh` retains shared OpenRouter calls and preset/profile comparison.
- `setup.sh` remains the established low-level synchronization implementation.
  `preset apply` and successful create/update flows invoke it with the selected
  config and key through environment variables, so secrets do not appear in argv.
- `bin/claude-openrouter` dispatches the command group and accepts global
  `--config FILE` before a subcommand.
- `completions/_claude-openrouter` completes actions, flags, output formats, and
  existing profile names where applicable.

## Verification

The no-cost smoke suite uses a fake `curl` implementation and covers:

- deterministic list formats and local/remote view status;
- usage, not-found, authentication, conflict, and lock failures;
- provider-pinned and fusion profile creation;
- update with backup, dry-run with no write, and global `--config`;
- recoverable remote failure with no readiness marker; and
- one-profile and all-profile apply, including a single JSON result.

The suite never calls the live OpenRouter API. A live account verification remains a
separate manual release check because it changes remote account state.

