# /relay — AI CLI Task Delegation

Analyze the user's task and delegate it to the configured AI CLI.

## Input
$ARGUMENTS — task description from the user

## Configuration

Read `.ai-relay.json` in the project root for CLI name, flags, and settings.
If the file doesn't exist, tell the user to run install.sh first.

## Workflow

### Step 1: Analyze and Prepare Prompt
1. Analyze the task — which files are affected, what kind of change
2. Identify the file paths to modify (do NOT read and paste file contents — the target CLI reads the repo itself)
3. Prepare a minimal prompt for the target AI CLI

Use this prompt template:

```
## Task
[Clear, one-sentence task description]

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

### Step 2: Create Worktree (if enabled)

Read `worktree.enabled` from `.ai-relay.json`. If `true` (or if the `worktree` key exists and is enabled):

1. Generate a short slug from the task description (lowercase, hyphens, max 30 chars)
2. Create the worktree:
   ```bash
   git worktree add .worktrees/relay-<slug> -b relay/<slug>
   ```
3. If the branch already exists, append a timestamp:
   ```bash
   git worktree add .worktrees/relay-<slug>-<timestamp> -b relay/<slug>-<timestamp>
   ```

If `worktree` config is missing or `enabled: false`, skip this step and run in the current directory (v1 behavior).

### Step 3: Execute AI CLI

Run in the background:
```bash
# With worktree:
./relay-run.sh --worktree .worktrees/relay-<slug> "PREPARED_PROMPT"

# Without worktree (fallback):
./relay-run.sh "PREPARED_PROMPT"
```
Use `run_in_background: true` for this Bash call. Claude is free to do other work while the task runs.

When the background task completes, you will receive a notification automatically. Do NOT poll or check `.relay_status` — just wait for the notification.

- If the task succeeded (exit 0) — proceed to Step 4
- If the task failed (non-zero exit) — inform the user and check the output for errors. If worktree was used, keep it for inspection.

### Step 4: Review

If worktree was used, review from the worktree:
```bash
cd .worktrees/relay-<slug>
git log --oneline -3
git diff main..HEAD
git diff --name-only main..HEAD
```

If no worktree (v1 fallback):
```bash
git log --oneline -3
git diff HEAD~1 HEAD
git diff --name-only HEAD~1 HEAD
```

Review the changes:
- Is the code style correct?
- Are tests present and sensible?
- Any security issues?
- Any unnecessary file changes?

### Step 5: Report
Inform the user:
- What changed (file list + summary)
- Any issues found
- Ask for approval to merge (if worktree) or confirm completion (if no worktree)

### Error Correction (Max retries from config, default 3)
If issues are found during review:
1. Clearly describe the problem
2. Prepare a fix prompt (only the problematic part)
3. Run with `run_in_background: true`:
   ```bash
   # With worktree:
   ./relay-run.sh --worktree .worktrees/relay-<slug> "fix prompt" --continue

   # Without worktree:
   ./relay-run.sh "fix prompt" --continue
   ```
4. Wait for notification, then review again

If not fixed after max retries, give the user a status report.

### Step 6: Merge or Reject (worktree only)

**On user approval:**
```bash
git merge relay/<slug>
git worktree remove .worktrees/relay-<slug>
git branch -d relay/<slug>
```

**On user rejection:**
```bash
git worktree remove .worktrees/relay-<slug> --force
git branch -D relay/<slug>
```

**On merge conflict:**
Do NOT auto-resolve. Report the conflict to the user with details and let them decide how to proceed.

If no worktree was used, skip this step entirely.

### Step 7: Quality Gate (After All Tasks Complete)

Read `hooks.post_review` from `.ai-relay.json`. If it is set (non-empty):

1. Run the configured post-review hook (e.g., `/simplify`, security review)
2. Collect findings and prioritize (critical > high > medium)
3. If critical/high findings exist, delegate fixes:
   ```bash
   ./relay-run.sh "FIX_PROMPT" --continue
   ```
   Use `run_in_background: true`. Include findings list and which files need fixing.
   Wait for notification, then review again (max 2 rounds)
4. If clean — inform user: "Quality gate passed, ready to push"

If `hooks.post_review` is empty or not set, skip this step.

## Session Strategy

| Scenario | Command | Description |
|----------|---------|-------------|
| New task | `./relay-run.sh "prompt"` | Start fresh session |
| New task (worktree) | `./relay-run.sh --worktree <path> "prompt"` | Isolated session |
| Fix (same task) | `./relay-run.sh "fix" --continue` | Continue last session |
| Fix (worktree) | `./relay-run.sh --worktree <path> "fix" --continue` | Continue in worktree |
| Specific session | `./relay-run.sh "prompt" --continue session_id` | Resume by session ID |
