# Multi-account mechanisms: separate homes, refresh races, and session switching

Background reference for multi-account handling in Claude Code / Codex harnesses.
Paths and behavior are from this machine (macOS, user `stevemorin`).
Code citations are from the `agent-deck` checkout at `v1.16.10`
(`7d2302fb`, PR references as noted).

Contents:

1. [Separate homes versus in-place swap](#1-separate-homes-versus-in-place-swap)
2. [Single-use refresh tokens and competing refresh chains](#2-single-use-refresh-tokens-and-competing-refresh-chains)
3. [What a switch actually moves](#3-what-a-switch-actually-moves)

---

## 1. Separate homes versus in-place swap

### What it is

Two ways to make the same harness binary talk to a different login: point it
at a different directory, or rewrite the one credential inside the directory it
already uses.

### Context

Every harness reads exactly one credential from one home. The home is a
directory chosen by an environment variable. Claude Code adds a twist on
macOS: the Keychain item is named after the home, so a non-default home gets
its own item. Codex and DeepSeek keep the credential as a file inside the
home, so the same rule falls out naturally.

### Example, separate homes

Two Claude Code homes side by side on this Mac:

```text
export CLAUDE_CONFIG_DIR=~/.claude            export CLAUDE_CONFIG_DIR=~/.claude-work
┌────────────────────────────────┐            ┌────────────────────────────────┐
│ ~/.claude/                     │            │ ~/.claude-work/                │
│   .claude.json   oauthAccount: │            │   .claude.json   oauthAccount: │
│                  personal      │            │                  work          │
│   settings.json  (hooks, MCP)  │            │   settings.json  EMPTY         │
│   projects/…/abc123.jsonl      │            │   projects/      EMPTY         │
└───────────────┬────────────────┘            └───────────────┬────────────────┘
                │ Keychain service name                       │
                ▼                                             ▼
   "Claude Code-credentials"                    "Claude Code-credentials-ce60aabc"
   personal access + refresh token              work access + refresh token
```

The workflow to create the second home is three commands. Nothing in the
first home changes:

```bash
CLAUDE_CONFIG_DIR=~/.claude-work claude auth login          # browser OAuth flow
CLAUDE_CONFIG_DIR=~/.claude-work claude auth status --json  # "configDirectory": "/Users/stevemorin/.claude-work"
CLAUDE_CONFIG_DIR=~/.claude-work claude                     # runs as the work account
```

The Keychain on this Mac already shows the pattern working: one unsuffixed
item plus eight suffixed items left behind by past sessions that set
`CLAUDE_CONFIG_DIR`. agent-deck's `accounts` command even prints the login
step for a slot whose directory does not exist yet:

```go
// cmd/agent-deck/accounts_cmd.go:86-92
for _, account := range accounts {
    status := "ok"
    if !account.Exists {
        status = "not created — log in with: CLAUDE_CONFIG_DIR=" + account.ConfigDir + " claude"
    }
    fmt.Printf("%-20s %-40s %s\n", account.Name, account.ConfigDir, status)
}
```

Codex is the same shape with `CODEX_HOME=~/.codex-work codex login`, which
writes `~/.codex-work/auth.json`.

### Example, in-place swap

This is what `claude-swap` or CCSwitcher does. The home stays fixed, the
credential inside the default Keychain item is rewritten, and the tool keeps
its own stash of tokens:

```text
~/.claude-swap-backup/
  personal.json   ← saved token A
  work.json       ← saved token B
        │
        │  "claude-swap use work"
        ▼
 Keychain "Claude Code-credentials"   ◄── overwritten with token B
 ~/.claude.json  oauthAccount         ◄── overwritten with work identity
 ~/.claude/projects/…                 unchanged: personal AND work transcripts mixed
 ~/.claude/settings.json              unchanged: shared by both accounts
```

The workflow, step by step:

1. Quit every running `claude` process, because a live process re-reads the
   Keychain on its next API call and would silently adopt the new account
   mid-conversation.
2. The tool copies the current Keychain item into its backup stash as the
   current account's saved token.
3. The tool writes saved token B into the Keychain item and rewrites
   `oauthAccount`.
4. Relaunch `claude`. It is now the work account, with the personal account
   no longer visible.

### What this gets you

Separate homes give you concurrent sessions on different accounts, with
isolation of history, MCP servers, and trust, at the cost of a new home
starting empty. In-place swap gives you shared settings and history across
accounts, at the cost of one session at a time and a credential rewrite on
every switch.

agent-deck chose the first because of the next section.

---

## 2. Single-use refresh tokens and competing refresh chains

### What it is

An OAuth refresh token can be redeemed once. Redeeming it returns a new
access token and a new refresh token, and the server marks the old refresh
token dead.

### Context

Claude Code and Codex both refresh in the background before the access token
expires. Codex records this in the `last_refresh` field of `auth.json`. The
consequence is that any two live copies of the same refresh token are in a
race, and only one can win.

### Example

The timeline that logged agent-deck users out of their host Claude before
PR #2153. The sandbox start copied the host's Keychain token into the
container:

```text
time   host Keychain          sandbox file           server's view
t0     R1                     R1  (copied)           R1 valid
t1     refreshes with R1      -                      R1 used → dead; issues R2
       now holds R2
t2     -                      refreshes with R1      401 invalid_grant
                              → sandbox logged out
```

or, if the sandbox refreshes first:

```text
t1'    -                      refreshes with R1      R1 dead; issues R2'
t2'    refreshes with R1      -                      401 → HOST logged out
```

The fix is written as a rule in the source:

```go
// internal/docker/sandbox.go:26-31
// Single-owner rule (#2153): an OAuth refresh token is single-use and rotates
// on every refresh, so every copy of it starts a competing refresh chain and
// whichever side refreshes first invalidates the other. The Keychain entry is
// owned by the host's Claude; the sandbox file is owned by the containers and
// is normally created by a /login inside the sandbox. This opt-in path copies
// the Keychain entry exactly once, to seed a sandbox that has no credential of
// its own, and that single copy still forks the host chain once.
```

The same race is why a symlinked Codex `auth.json` fails. Two homes share
one file, and each process caches its token in memory:

```text
~/.codex-work/auth.json ──symlink──► ~/.codex/auth.json   (on disk: R1)

 process A (personal)          process B (work)          file on disk
 holds R1 in memory            holds R1 in memory        R1
 refreshes → gets R2           -                         R2
 -                             refreshes with R1 → 401   R2
 -                             user re-logs in → R3      R3   ← A's R2 now dead
 next refresh with R2 → 401    -                         R3
```

GitHub issue #15410 on the Codex repo, closed as not planned, states it
directly: the first run may work on the cached access token, and later runs
fail with 401 once the other instance refreshed.

### What this gets you

The rule "one credential, one owner" is the whole reason agent-deck never
copies a credential between account slots and never lets two slots resolve
to one directory. The single exception is the opt-in, one-time sandbox
seeding path quoted above, which forks the host chain once by design and is
never repeated. The rule also tells you which community tools are safe to
combine with agent-deck:
none of the in-place swappers, because they rewrite the default home's item
that agent-deck's default slot owns.

---

## 3. What a switch actually moves

### What it is

`agent-deck session switch-account <session> <slot>` copies a session's
transcript from one home to another, leaving the source copy in place. It
does not move an account, because the target account already exists in the
target home from the one-time login in section 1.

### Context

The only session-specific thing that lives in the source home is the
transcript. Everything else is either per-home and stays put, such as
credentials, `settings.json`, MCP config, memory, and hooks, or per-project
and shared, such as `.claude/settings.json` and `.mcp.json` in the repo.
The executor from PR #2237 handles Claude→Claude and Codex→Codex. It writes
a journal at every state boundary so a crash leaves a readable record
instead of a half-moved conversation:

```go
// internal/session/harness_switch.go:53-61
const (
    switchJournalVersion = 3
    switchPrepared       = "prepared"
    switchStaged         = "staged"
    switchInstalled      = "installed"
    switchCommitted      = "committed"
    switchCompleted      = "completed"
    switchFailed         = "failed"
)
```

### Example

A Claude session in `~/c/agent-deck` with session id `abc123`, moving from
the default slot to `work`. Claude encodes the working directory into the
folder name, so the transcript path is
`projects/-Users-stevemorin-c-agent-deck/abc123.jsonl`:

```text
agent-deck session switch-account my-session work
 │
 ├─1  take per-source lock; write runtime/harness-switch/<op>.json as prepared
 ├─2  re-run the preview inside the lock: slot "work" configured? exact session id known?
 │       any refusal → stop here, nothing has been touched
 ├─3  export ~/.claude/projects/-Users-stevemorin-c-agent-deck/abc123.jsonl   sha256 = H1
 │       copy → <stage>/native-XXXX/abc123.jsonl        verify sha256 == H1
 │       copy → <stage>/native-XXXX/abc123/             subagent sidechain, per-file sizes verified
 │                                                      journal = staged
 ├─4  stop the session (KillAndWait); export again; sha256 must still equal H1
 │       mismatch → source restarted, journal = failed
 ├─5  install → ~/.claude-work/projects/-Users-stevemorin-c-agent-deck/abc123.jsonl
 │       destination absent ............ verified copy
 │       destination sha256 == H1 ....... no-op
 │       destination is a byte-prefix ... snapshot to abc123.jsonl.bak-<UnixNano>
 │                                        then temp file + rename + fsync
 │       destination diverged ........... REFUSE, keep both files
 │                                                      journal = installed
 ├─6  pre-accept folder trust for ~/c/agent-deck in ~/.claude-work/.claude.json
 ├─7  Instance.Account = "work" ........................ committed
 ├─8  restart: CLAUDE_CONFIG_DIR=~/.claude-work claude --resume abc123
 │       start fails → account rolled back, source restarted, journal = failed
 └─9  registry compare-and-swap; acknowledge journal; delete <stage>, journal = completed
```

Step 5 is where the safety lives. The refusal and the backup naming are
here:

```go
// internal/session/harness_switch.go:931-933
if !isPrefix {
    return fmt.Errorf("destination contains a divergent or newer conversation; preserving both files and refusing overwrite: %s", destination)
}
```

```go
// internal/session/harness_switch.go:1035-1042
func snapshotConversationArtifact(destination, expectedHash string) (string, error) {
    for n := 0; ; n++ {
        suffix := fmt.Sprintf("%d", time.Now().UnixNano())
        if n > 0 {
            suffix = fmt.Sprintf("%s-%d", suffix, n)
        }
        backup := destination + ".bak-" + suffix
        f, err := os.OpenFile(backup, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
```

After the switch, the two homes look like this. The source transcript is
still there, untouched:

```text
~/.claude/                                     ~/.claude-work/
  Keychain item ............ unchanged           Keychain item ............ unchanged
  .claude.json ............. unchanged           .claude.json ............. trust entry added for ~/c/agent-deck
  settings.json ............ unchanged           settings.json ............ unchanged (still empty)
  projects/…/abc123.jsonl .. still present       projects/…/abc123.jsonl .. NEW, sha256 == H1
  projects/…/abc123/ ....... still present       projects/…/abc123/ ....... NEW, sidechain copy
```

Codex follows the same nine steps with the rollout file under `sessions/`
rooted under the target `CODEX_HOME`, and no trust pre-seed. The older
`session set <session> account work` command skips steps 1, 2, 4, 8, and 9,
checks only byte counts, and only migrates when the tool string is literally
`claude`, so prefer `switch-account`.

### What this gets you

A switch that cannot lose or corrupt a conversation, leaves a journal to
inspect after a crash, and never reads or writes a credential itself. The account
is expressed only as which directory the restarted process is pointed at.
