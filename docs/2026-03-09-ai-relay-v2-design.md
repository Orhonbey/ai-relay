# ai-relay v2 — Redesign

**Date:** 2026-03-09
**Status:** Approved
**Repo:** https://github.com/Orhonbey/ai-relay

## Problem

ai-relay v1 works but wastes Claude tokens in three ways:

1. **Prompt bloat** — Claude reads all relevant files and pastes their contents into the prompt text (~2000-5000 tokens per relay call)
2. **Polling loop** — Claude checks `.relay_status` every 10 seconds. A 2-minute task costs ~12 message turns (~1200 tokens doing nothing)
3. **No isolation** — Target CLI writes to the same working directory, blocking parallel work

## Design Goals (Priority Order)

1. **Token savings** — Minimize Claude's token usage per relay call (~75% reduction target)
2. **Quality** — Fewer retries through better context transfer
3. **Parallelism** — Support multiple concurrent relay tasks

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Context transfer | Minimal prompt (task + file paths only) | Kimi and Codex can both read the repo themselves — no need to paste file contents |
| CLAUDE.md awareness | One-line instruction: "Read CLAUDE.md files first" | Project rules live in the repo, target CLI will see them |
| Polling | `run_in_background: true` | Zero polling cost — Claude gets notified on completion |
| Isolation | Git worktree per task | Enables parallel relay, prevents conflicts with active work |
| Review depth | Full git diff review | Acceptable cost (~800-1500 tokens), catches errors before merge |

## Architecture

### Flow

```
/relay "task description"
    │
    ├─ 1. Prepare minimal prompt
    │     - Task description (from user)
    │     - File paths to modify (Claude identifies)
    │     - "Read CLAUDE.md hierarchy before starting"
    │     - "Git commit when done"
    │
    ├─ 2. Create git worktree
    │     - Branch: relay/<task-slug>
    │     - Directory: .worktrees/relay-<task-slug>
    │
    ├─ 3. Run relay-run.sh in background
    │     - run_in_background: true
    │     - Workdir pointed at worktree
    │     - Claude is FREE to do other work
    │
    │     ... notification arrives when done ...
    │
    ├─ 4. Review changes
    │     - git diff in worktree
    │     - Full review (style, security, tests, breaking changes)
    │
    ├─ 5. Report to user
    │     - File list + summary
    │     - Issues found (if any)
    │     - Retry if needed (max_retries from config)
    │
    └─ 6. On approval
          - Merge worktree branch into current branch
          - Delete worktree + branch
```

### Parallel Relay

```
/relay "task A"  ──→  worktree-A  ──→  Kimi instance 1
/relay "task B"  ──→  worktree-B  ──→  Kimi instance 2
                                        │
Claude is free to work on other things  │
                                        │
        ←── notification A done ────────┘
        ←── notification B done ────────┘
        review A, review B, merge both
```

Each worktree is fully isolated — different branch, different directory, no conflicts.

### Token Cost Comparison

| Phase | v1 Cost | v2 Cost | Savings |
|-------|---------|---------|---------|
| Prompt preparation (file reading + pasting) | ~2000-5000 tokens | ~200-400 tokens | ~90% |
| Polling (2min task, 10s interval) | ~1200 tokens | 0 tokens | 100% |
| Review (git diff) | ~800-1500 tokens | ~800-1500 tokens | 0% |
| **Total per relay call** | **~4000-7700** | **~1000-1900** | **~75%** |

## Files to Change

### 1. `relay.md` (skill — `~/.claude/commands/relay.md`)

Major rewrite:

**Step 1 (Prompt):**
- Remove the "read files and paste contents" instructions
- New prompt template:

```
## Task
[One-sentence task description]

## Setup
- Read all CLAUDE.md files in the repo before starting (root + subdirectories)
- Follow the project's conventions and rules

## Files to Modify
1. `path/to/file` — [what to change]
2. `path/to/other` — [what to change]

## Rules
- Only touch the specified files
- Git add + git commit when done
- Commit message format: type: description

## Do NOT
- Create unrelated files
- Break existing tests
- Add unnecessary dependencies
```

**Step 2 (Execute):**
- Create worktree before running
- Use `run_in_background: true` for the bash command
- Remove entire polling section (Step 3 in v1)

**Step 4 (Review):**
- Review diff from worktree, not main working dir
- Same review depth as v1

**New Step (Merge):**
- On user approval: merge worktree branch, cleanup
- On rejection: delete worktree + branch

### 2. `relay-run.sh`

Add worktree management:

```bash
# New flags
# --worktree <path>  : run in specified worktree directory

# Before execution:
# - cd to worktree path if provided

# After execution:
# - Status file written to worktree directory
```

The worktree creation/deletion is handled by the skill (relay.md), not by relay-run.sh. The runner just receives the workdir path.

### 3. `.ai-relay.json`

Add worktree config:

```json
{
  "cli": "kimi",
  "flags": {
    "prompt": "--print --final-message-only -p",
    "continue": "-C",
    "session": "-S",
    "workdir": "-w"
  },
  "max_retries": 3,
  "status_file": ".relay_status",
  "worktree": {
    "enabled": true,
    "base_dir": ".worktrees"
  },
  "hooks": {
    "post_review": ""
  }
}
```

## CLI Compatibility

| Feature | Kimi | Codex CLI | Aider | MiniMax |
|---------|------|-----------|-------|---------|
| Reads repo files | Yes (`-w`) | Yes (sandbox) | Yes | Yes (`-w`) |
| Sees CLAUDE.md | Yes | Yes | Yes | Yes |
| Worktree support | Yes (just change `-w` path) | Yes (pass worktree as cwd) | Yes | Yes |
| Minimal prompt works | Yes | Yes | Yes | Yes |

All four supported CLIs can read project files independently. The minimal prompt approach is CLI-agnostic.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Worktree branch already exists | Append timestamp suffix |
| Relay fails mid-task | Status = FAILED, worktree preserved for inspection |
| Merge conflict | Report to user, don't auto-resolve |
| Multiple relays to same files | User's responsibility — warn if detected |
| Target CLI ignores CLAUDE.md | Acceptable — review step catches violations |

## Not In Scope (YAGNI)

- Context caching between relay calls
- Automatic test execution post-relay
- Webhook/signal-based completion notification
- Smart file detection (let Claude identify files)
- Persistent relay sessions across Claude conversations
