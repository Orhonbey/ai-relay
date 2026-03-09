# ai-relay

AI-agnostic task delegation for Claude Code. Delegate coding tasks to any AI CLI (Kimi, Codex, Aider, MiniMax) with automated review and quality gates.

## How It Works

```
You (Claude Code)          ai-relay            Target AI CLI
    |                         |                      |
    |-- /relay "add X" ------>|                      |
    |                         |-- prepare prompt     |
    |                         |-- relay-run.sh ----->|
    |                         |   (status: RUNNING)  |
    |                         |                      |-- writes code
    |                         |                      |-- git commit
    |                         |   (status: DONE) <---|
    |                         |-- git diff review    |
    |<-- report --------------|                      |
```

## Install

```bash
git clone https://github.com/SunalSpaciel/ai-relay.git
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
1. Analyze the task and read relevant code
2. Prepare a detailed prompt
3. Run the configured AI CLI via `relay-run.sh`
4. Poll `.relay_status` until completion
5. Review changes with `git diff`
6. Report results (and optionally run quality gates)

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

## License

MIT
