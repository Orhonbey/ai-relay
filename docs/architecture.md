# ai-relay Architecture

## Overview

ai-relay is a Claude Code skill that delegates coding tasks to external AI CLIs. Claude acts as the **planner and reviewer**, while the target AI CLI acts as the **code writer**.

The two systems communicate through Git and a status file — no direct API calls or shared memory.

## Components

```
project-root/
├── .relay_status          # Signal file (gitignored)
├── .ai-relay.json         # Config (gitignored, from preset)
├── relay-run.sh           # Generic wrapper script
└── ~/.claude/commands/
    └── relay.md           # Claude Code skill definition
```

### relay.md (Skill)

The Claude Code slash command definition. When the user types `/relay "task"`, Claude loads this file and follows its 6-step workflow:

1. **Analyze** — Read relevant code, understand the task
2. **Execute** — Run `relay-run.sh` with prepared prompt
3. **Poll** — Watch `.relay_status` for completion
4. **Review** — `git diff` the changes
5. **Report** — Summarize results to user
6. **Quality Gate** — Optional post-review hook

### relay-run.sh (Wrapper)

A POSIX shell script that:
1. Reads `.ai-relay.json` with `jq`
2. Builds the CLI command from config flags
3. Manages status file lifecycle: `RUNNING` -> `DONE`/`FAILED`
4. Handles session continuation (`--continue` flag)

### .ai-relay.json (Config)

Project-local configuration that defines:
- Which AI CLI to use
- CLI-specific flags for prompt, session, and workdir
- Max retry count
- Optional post-review hook

Created from presets during installation.

## Execution Flow

```
/relay "add logging to auth module"
         |
         v
   [Step 1: Claude reads auth module code,
    prepares detailed prompt with context]
         |
         v
   [Step 2: ./relay-run.sh "prompt"]
         |
         v
   relay-run.sh:
     1. echo RUNNING > .relay_status
     2. jq reads .ai-relay.json
     3. builds: kimi --print --final-message-only -p "prompt" -w /path
     4. executes command
     5. echo DONE > .relay_status (or FAILED)
         |
         v
   [Step 3: Claude polls .relay_status]
         |
         v
   [Step 4: DONE -> git log + git diff review]
         |
         v
   [Step 5: Report to user]
         |
         v
   [Step 6: hooks.post_review? -> run hook -> fix if needed]
```

## Session Strategy

The wrapper supports three modes:

| Mode | Command | Use Case |
|------|---------|----------|
| New | `./relay-run.sh "prompt"` | Fresh task |
| Continue | `./relay-run.sh "fix" --continue` | Fix in same session |
| Resume | `./relay-run.sh "prompt" --continue id` | Specific session |

Session support depends on the target CLI. If `flags.continue` or `flags.session` are empty in config, those features are unavailable for that CLI.

## Error Handling

- **CLI not found**: `relay-run.sh` fails, status = FAILED
- **Config missing**: `relay-run.sh` exits with error before execution
- **jq missing**: `relay-run.sh` exits with dependency error
- **Task fails**: Status = FAILED, Claude reports to user
- **Review finds issues**: Claude prepares fix prompt, retries up to `max_retries`
- **Max retries exceeded**: Claude reports status, asks for manual intervention

## Design Decisions

- **Config over code**: CLI differences handled via JSON config, not code branches
- **POSIX shell**: Maximum portability (sh, not bash-specific)
- **Status file**: Simple, reliable IPC — no sockets, no APIs
- **Git as review channel**: Changes reviewed via `git diff`, not CLI output parsing
- **Optional quality gate**: `hooks.post_review` only runs if configured
