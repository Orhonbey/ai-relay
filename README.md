# ai-relay

Plan-driven task delegation across AI CLIs, for Claude Code.

You plan the work with Claude. Claude writes the plan to a file, hands it to
another AI CLI (CommandCode, Opencode, Kimi, Codex, Aider) running in an
isolated git worktree, then **runs your quality gates itself** and reads the
output rather than trusting the model's report. On failure it feeds a specific
correction back; when retries run out it escalates to the next target.

## How It Works

```
/relay "<task>"
  │
  ├─ 1 · PLAN        explore the repo → ask you about every real
  │                  technical choice → write <plan.dir>/YYYY-MM-DD-<slug>.md
  │                  ↳ GATE: you approve the plan and the target
  │
  ├─ 2 · DISPATCH    git worktree add → minimal prompt (the plan's *path*,
  │                  not its contents) → run the CLI in the background
  │
  ├─ 3 · GATE        Claude runs every `gates` command in the worktree and
  │                  reads the real output, then checks each acceptance
  │                  criterion against `git diff`
  │
  ├─ 4 · FEEDBACK    on FAIL: a specific correction (gate output, file:line,
  │                  expected behaviour) → same session via --continue
  │                  ↳ up to `max_retries` rounds
  │
  ├─ 5 · ESCALATE    retries exhausted → reset the worktree to its base commit
  │                  → next target in `escalation` → you are told, and may stop
  │
  └─ 6 · ACCEPT      report → GATE: you approve the merge → merge + cleanup
```

`/relay --quick "<task>"` skips phase 1 and gives you the old one-shot
behaviour. For one-liners, writing a plan is waste.

## Install

```bash
git clone https://github.com/Orhonbey/ai-relay.git
cd ai-relay

# Install and seed this project's config from a preset
./install.sh commandcode

# Or install with the full example config
./install.sh
```

This installs:

| Destination | What |
|---|---|
| `~/.ai-relay/relay-run.sh` | The runner — one copy, shared by every project |
| `~/.ai-relay/presets/*.json` | CLI flag maps |
| `~/.claude/skills/ai-relay/` | The skill (`SKILL.md`, `relay.md`, `templates/`) |
| `~/.claude/commands/relay.md` | The `/relay` slash command |
| `./.ai-relay.json` | This project's config — **committed, not ignored** |

Re-running `install.sh` refreshes the runner and presets in place.

## Usage

```
/relay "implement the token bucket limiter described in docs/rate-limit.md"
```

Claude explores the repo, asks you about each real technical decision, writes
the plan, and asks you to approve the plan and the target together. That is the
only approval before work starts; the next one is the merge.

### Parallel relays

Each task gets its own worktree and branch, so several relays can run at once.
If two in-flight relays name overlapping files, Claude warns you — it does not
block.

## Config

`.ai-relay.json` is a tracked project file: it carries the target roster and the
quality gates, which are facts about the project.

| Field | Description | Example |
|---|---|---|
| `version` | `3` enables the plan-driven loop. Omit for v2 behaviour. | `3` |
| `plan.dir` | Where plan files are written | `"docs/relay-plans"` |
| `targets` | Named CLI × model combinations | see below |
| `default_target` | Target used when none is given | `"cc"` |
| `escalation` | Handover order; already-tried targets are skipped | `["cc", "oc"]` |
| `max_retries` | Correction rounds before escalating | `3` |
| `gates` | Commands Claude runs to decide PASS/FAIL | `[{"name":"test","cmd":"npm test"}]` |
| `worktree.enabled` | Isolate each task in a git worktree | `true` |
| `worktree.base_dir` | Where worktrees are created | `".worktrees"` |
| `status_file` | Status file path (relative, no symlinks) | `".relay_status"` |
| `cli` | *v2 legacy* — single CLI binary | `"kimi"` |
| `flags` | *v2 legacy* — flag map for that CLI | `{"prompt": "-p"}` |

### Targets

```json
"targets": {
  "cc": { "preset": "commandcode", "model": "" },
  "oc": { "preset": "opencode", "model": "" }
}
```

A target names a preset and, optionally, a model.

**Leaving `model` empty is the default and usually what you want** — the runner
then omits the model flag entirely and the CLI uses whichever model you have
selected in it. Set `model` only when you want to pin one target to a specific
model regardless of the CLI's own selection:

```json
"oc-kimi": { "preset": "opencode", "model": "opencode-go/kimi-k2.7-code" }
```

A target can also override individual preset flags:

```json
"cc-careful": {
  "preset": "commandcode",
  "flags": { "prompt": "--skip-onboarding --permission-mode auto-accept -p" }
}
```

## Quality gates

```json
"gates": [
  { "name": "lint",      "cmd": "npm run lint" },
  { "name": "typecheck", "cmd": "npm run typecheck" },
  { "name": "test",      "cmd": "npm test" }
]
```

**Claude runs these commands itself, in the worktree, and reads the output.** A
model claiming its work passes is not evidence. All gates run even after one
fails, so a single round collects every finding.

A gate that is not configured is reported as `NOT RUN` — never silently counted
as passed. If `gates` is empty, every gate reports `NOT RUN` and the summary
says so. The result is PASS only when every gate passes **and** every acceptance
criterion in the plan is met.

## Presets

| Preset | CLI | Notes |
|---|---|---|
| `commandcode` | CommandCode | Model flag, session, turn cap; permission prompts bypassed |
| `opencode` | Opencode | `run` subcommand, model flag, `--dir`; permission prompts bypassed |
| `kimi` | Kimi | Full support (continue, session, workdir) |
| `codex` | OpenAI Codex CLI | Quiet mode, prompt only |
| `minimax` | MiniMax CLI | Prompt + workdir |
| `aider` | Aider | Message-based prompting |

The runner is invoked in the background with no TTY, so a CLI that stops to ask
for permission would hang rather than fail. Presets therefore pass the flag that
skips those prompts. Isolation comes from the git worktree, the gates, and the
merge approval — not from the CLI's own prompts.

## Adding a New AI CLI

1. Create `presets/your-cli.json` with all six `flags` keys
2. Run `./test/run-tests.sh` — the schema test guards the contract
3. Verify every flag appears in `your-cli --help`
4. Submit a PR

See [docs/adding-a-preset.md](docs/adding-a-preset.md) for details.

## Upgrading from v2

```bash
cd ai-relay && git pull && ./install.sh
```

Then, in each project that used v2:

- Delete the project-local `./relay-run.sh` — the runner is global now
- Remove `.ai-relay.json` from `.gitignore` and commit it (the installer removes
  that line for you)
- Migrate the config: replace the top-level `cli` and `flags` with a `targets`
  roster and add `"version": 3`, plus `gates` and `escalation`

Nothing breaks if you skip the migration. A config with no `version` key is read
as a single implicit target and builds a byte-identical command line; the plan
phase and the gates simply stay off until you opt in.

## Testing

```bash
./test/run-tests.sh
```

Dependency-free: bash + jq. Tests assert the exact command line the runner
builds by running it against a stub CLI that records its argv. No real model is
called and no network is used. See [test/README.md](test/README.md).

## Requirements

- [jq](https://jqlang.github.io/jq/) — `brew install jq`
- git (worktree support)
- bash 3.2 or newer — macOS's default bash works
- The target AI CLI, installed and on `PATH`
- Claude Code

No Node.js, Python, or test framework required.

## Documentation

- [docs/2026-08-06-ai-relay-v3-design.md](docs/2026-08-06-ai-relay-v3-design.md) — v3 design and decisions
- [docs/adding-a-preset.md](docs/adding-a-preset.md) — preset contract
- [test/README.md](test/README.md) — test suite

## Author

[Sunal Orhon](https://www.linkedin.com/in/sunalorhon/)

## License

MIT
