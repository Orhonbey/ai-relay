# /relay — Plan-driven task delegation across AI CLIs

Plan the work with the user, delegate it to a target AI CLI, verify the result
against objective gates, feed corrections back, and escalate to another model if
the gates cannot be met.

## Input
$ARGUMENTS — the task description. If it starts with `--quick`, skip Phase 1.

## Configuration

Read `.ai-relay.json` from the project root. If it is missing, tell the user to
run `install.sh` and stop.

- `version: 3` — full plan-driven loop (below).
- No `version` key — legacy config. Run the v2 flow: skip Phase 1, use the single
  implicit target, review the diff, no gates.

Resolve the runner once: use `./relay-run.sh` if it exists (legacy install),
otherwise `${AI_RELAY_HOME:-$HOME/.ai-relay}/relay-run.sh`. If neither exists,
tell the user to run `install.sh` and stop.

## Phase 1 — Plan

Skip this phase entirely when the user passed `--quick`.

1. Explore the repo: which files does this touch, what conventions apply, what
   already exists that this must fit.
2. **Ask the user about every real technical choice**, one question at a time,
   as multiple choice with your recommendation first and each option's cost
   stated. Real choices are things like: data access model, test runner, lint
   chain, a new dependency, CI scope, module boundaries, error-handling
   strategy. Not real choices: variable names, ordering, formatting — decide
   those yourself.
3. Write the plan to `<plan.dir>/YYYY-MM-DD-<slug>.md` using
   `templates/plan.md`. Every acceptance criterion must be verifiable either by
   a gate command's output or by a single look at the diff. "The code should be
   clean" is not a criterion; "`src/db.ts` throws `ConfigError` when `DB_URL` is
   unset" is.
4. Propose a target from `targets` based on the task, and ask the user to
   approve **the plan and the target together**. This is the only approval gate
   before work starts.

## Phase 2 — Dispatch

1. Create the worktree (when `worktree.enabled`):

   ```bash
   git worktree add <base_dir>/relay-<slug> -b relay/<slug>
   ```

   If the branch exists, append a timestamp to the slug. Record the base commit
   (`git rev-parse HEAD` before branching) — Phase 5 resets to it.

2. Build a **minimal** prompt. Do not paste the plan's contents; the model reads
   the file itself.

   ```
   ## Task
   <one sentence>

   ## Plan
   `<absolute path to the plan file>` — read this file and follow it exactly.
   The task is not done until every acceptance criterion in it is met.

   ## Setup
   - Read every AGENTS.md / CLAUDE.md in the repo first
   - Follow the project's conventions

   ## Rules
   - Only touch files named in the plan
   - git add + git commit when done
   - Commit message: type(scope): summary
   ```

3. Run it in the background:

   ```bash
   <runner> --target <name> --worktree <base_dir>/relay-<slug> "<PROMPT>"
   ```

   Use `run_in_background: true`. Do not poll `.relay_status` — you are notified
   on completion. You are free to do other work meanwhile.

## Phase 3 — Gate

Run every command in `gates` yourself, in the worktree, in order. Run all of
them even after one fails, so a single round collects every finding. Read the
actual output — never accept the model's claim that something passed.

Then read `git diff <base>..HEAD` and check each acceptance criterion in the
plan one by one.

Report in this shape:

```
GATES
  lint       PASS
  typecheck  FAIL  src/db.ts:42  TS2345: ...
  test       FAIL  2 failing (db.test.ts: "throws on missing URL")
  build      NOT RUN  (not configured)

ACCEPTANCE
  PASS  1. ...
  FAIL  3. ...  — no corresponding change in the diff
```

A gate that is not configured is reported as NOT RUN — never counted as passed.
The result is PASS only when every gate passes **and** every criterion is met.

## Phase 4 — Feedback

On FAIL, write a specific correction prompt: which gate or criterion, the actual
command output, `file:line`, and what is expected instead. Never write "fix the
code".

```bash
<runner> --target <name> --worktree <path> "<FEEDBACK>" --continue
```

`--continue` keeps the model's session, so it still has its own context. Go back
to Phase 3. Repeat at most `max_retries` times (default 3).

## Phase 5 — Escalate

When retries are exhausted:

1. Reset the worktree to the base commit recorded in Phase 2 — not to `main`,
   which may have moved. The next model must not inherit half-finished work.
2. Pick the next entry in `escalation`, skipping targets already tried.
3. Dispatch as in Phase 2, adding a handover note: which gates broke, with what
   output, and what the previous model attempted.
4. Tell the user that the task was handed over and to which target. They may
   stop the loop here.

If `escalation` is exhausted, stop and report everything that was tried.

## Phase 6 — Accept

On PASS, report: files changed, each gate's output, how many rounds it took,
which target finished it. Ask the user to approve the merge.

**On approval:**

```bash
git merge relay/<slug>
git worktree remove <base_dir>/relay-<slug>
git branch -d relay/<slug>
```

**On rejection:**

```bash
git worktree remove <base_dir>/relay-<slug> --force
git branch -D relay/<slug>
```

**On merge conflict:** do not resolve it. Report it and let the user decide.

## Parallel relays

Each task gets its own worktree and branch, so several relays can run at once.
If two in-flight relays name overlapping files in their plans, warn the user —
do not block.

## Failure handling

| Situation | What to do |
|---|---|
| Runner exits non-zero | Keep the worktree for inspection; report the output |
| Branch already exists | Append a timestamp to the slug |
| Target not in roster | Stop; list the available targets |
| Plan file unreadable by the model | Pass the plan path as an absolute path |
| `gates` empty | Report every gate as NOT RUN and say so in the summary |
