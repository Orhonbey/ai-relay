# ai-relay

AI-agnostic task delegation for Claude Code. Delegate coding tasks to any AI CLI (Kimi, Codex, Aider, MiniMax) with automated review and quality gates.

## How It Works

```
You (Claude Code)          ai-relay            Target AI CLI
    |                         |                      |
    |-- /relay "add X" ------>|                      |
    |                         |-- minimal prompt     |
    |                         |-- create worktree    |
    |                         |-- relay-run.sh ----->|  (background)
    |                         |                      |
    |   (free to do other work)                      |-- reads repo
    |                         |                      |-- writes code
    |                         |                      |-- git commit
    |                         |<-- notification -----|
    |                         |-- git diff review    |
    |<-- report + merge ------|                      |
```

## Install

```bash
git clone https://github.com/Orhonbey/ai-relay.git
cd ai-relay

# Install with a preset (e.g., kimi)
./install.sh kimi

# Or install with blank config
./install.sh
```

This does three things:
1. Copies `relay.md` skill to `~/.claude/commands/`
2. Copies `relay-run.sh` to your project root
3. Creates `.ai-relay.json` from preset or blank template

## Usage

In Claude Code:

```
/relay "implement feature X based on the spec in docs/feature-x.md"
```

Claude will:
1. Prepare a minimal prompt (task + file paths only — no file content pasting)
2. Create an isolated git worktree for the task
3. Run the AI CLI in the background (Claude is free to do other work)
4. Review changes with `git diff` when notified
5. Report results and ask for merge approval
6. Merge worktree branch on approval, cleanup on rejection

### Parallel Relay

Each task runs in its own worktree, so you can run multiple relays concurrently:

```
/relay "task A"  →  worktree-A  →  CLI instance 1
/relay "task B"  →  worktree-B  →  CLI instance 2
```

Claude reviews and merges each independently when they complete.

## Config

`.ai-relay.json` fields:

| Field | Description | Example |
|-------|-------------|---------|
| `cli` | AI CLI binary name | `"kimi"`, `"codex"`, `"aider"` |
| `flags.prompt` | Flags before the prompt text | `"--print --final-message-only -p"` |
| `flags.continue` | Flag to continue a session | `"-C"` |
| `flags.session` | Flag to specify session ID | `"-S"` |
| `flags.workdir` | Flag to set working directory | `"-w"` |
| `max_retries` | Max fix attempts per task | `3` |
| `status_file` | Status file path | `".relay_status"` |
| `worktree.enabled` | Enable git worktree isolation | `true` |
| `worktree.base_dir` | Directory for worktrees | `".worktrees"` |
| `hooks.post_review` | Post-review command (optional) | `"/simplify"` |

## Presets

| Preset | CLI | Notes |
|--------|-----|-------|
| `kimi` | Kimi 2.5 | Full feature support (continue, session, workdir) |
| `codex` | OpenAI Codex CLI | Quiet mode, prompt only |
| `minimax` | MiniMax CLI | Prompt + workdir |
| `aider` | Aider | Message-based prompting |

Use a preset: `./install.sh kimi`

## Adding a New AI CLI

1. Create `presets/your-cli.json` with the correct flags
2. Test: `./install.sh your-cli` then `/relay "hello world test"`
3. Submit a PR

See [docs/adding-a-preset.md](docs/adding-a-preset.md) for details.

## Requirements

- [jq](https://jqlang.github.io/jq/) — JSON parser (`brew install jq`)
- Target AI CLI installed and accessible in PATH
- Claude Code with slash command support

## Author

[Sunal Orhon](https://www.linkedin.com/in/sunalorhon/)

## License

MIT
