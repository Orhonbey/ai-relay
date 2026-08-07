# ai-relay v3 — Plan-driven multi-model task loop

**Date:** 2026-08-06
**Status:** Approved (design)
**Repo:** https://github.com/Orhonbey/ai-relay
**Predecessor:** `docs/2026-03-09-ai-relay-v2-design.md`

---

## 1. Problem

ai-relay v2 works: it delegates a task to an AI CLI in an isolated worktree,
runs it in the background, reviews the diff, and gates the merge. But measured
against how the tool is actually used, it has four gaps:

1. **No planning phase.** The input is a one-line task description, from which
   Claude produces a prompt directly. What is wanted instead: the user and
   Claude plan first, every technical choice in the plan is put to the user, the
   plan is written to a file, and the implementer is handed **that file**.
2. **One CLI.** `.ai-relay.json` carries a single `cli` field. The user wants to
   use both CommandCode and Opencode, **with different models**.
3. **No model selection.** The preset schema has no slot for a model flag, yet
   both CLIs take model selection as a flag (`-m`). Multi-model is impossible
   without that slot.
4. **Subjective review.** In v2 the quality gate amounts to "Claude looks at the
   diff and judges style, tests and security". Code that does not compile or
   breaks the tests can slip through; the "done, flawless" verdict has no
   objective basis.

## 2. Goals

1. **The plan is the contract.** The implementing model must be able to finish
   the work by reading the plan, with no prior knowledge of the repo. Acceptance
   criteria must be machine-verifiable.
2. **Multi-target.** Several CLI × model combinations defined as named targets,
   selectable per task.
3. **Objective gate.** The done/not-done verdict rests on the output of commands
   Claude runs itself, and on checking each criterion in the plan one by one.
4. **Automatic recovery.** If the gate cannot be met: first corrections on the
   same model, then handover to another — the user should not have to intervene
   at every stall.
5. **Few but meaningful approvals.** The user steps in only where decisions
   change.

## 3. Decisions

Every choice in this design was put to the user as a multiple-choice question
and answered:

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Who dispatches | **Claude runs it automatically** | Background execution plus worktree isolation makes this safe; a manual step every round kills the loop |
| 2 | Where it lives | **ai-relay v3** (not a new repo) | Runner, worktree, merge gate and preset infrastructure already exist and are tested; a second tool creates confusion |
| 3 | Model roles | **Single target + Claude as referee** | Most predictable and cheapest; multi-model exists as "pick from the roster", with no concurrent race |
| 4 | Plan generation | **Own template + flexible location** | ai-relay is a public repo; depending on the superpowers plugin would be a heavy prerequisite |
| 5 | Quality gate | **Command chain + acceptance criteria** | A model's "it passed" is not trustworthy; Claude must see the output |
| 6 | Failure path | **N correction rounds → hand over to another model** | The user should not have to intervene at every stall, but is told at handover and can stop |

### Out of scope (deliberately)

- Sending the same task to several models in parallel and racing them
  (eliminated in decision 3; could return later as a `--race` flag).
- A different model performing an independent code review (eliminated in
  decision 3).
- Claude taking over a stalled task and finishing it itself (eliminated in
  decision 6).
- Embedding a GitHub issue/PR protocol into the skill (left as a separate layer,
  see §9).
- Already eliminated in v2: context caching, persistent sessions, smart file
  detection.

## 4. Flow

```
/relay "<task>"
  │
  ├─ Phase 1 · PLAN (Claude ↔ user)
  │    explore the repo → ask about every technical choice as multiple choice
  │    → plan file: <plan.dir>/YYYY-MM-DD-<slug>.md
  │    → GATE 1: plan approval + target approval
  │
  ├─ Phase 2 · DISPATCH
  │    git worktree add <base_dir>/relay-<slug> -b relay/<slug>
  │    relay-run.sh --target <name> --worktree <path> "<minimal prompt>"
  │    run_in_background: true → wait for the notification
  │
  ├─ Phase 3 · GATE (objective)
  │    the gate commands are run in order in the worktree, output is read
  │    git diff → each acceptance criterion in the plan marked ✓/✗
  │
  ├─ Phase 4 · FEEDBACK (on FAIL)
  │    structured report → relay-run.sh ... --continue
  │    → back to Phase 3 · at most max_retries rounds
  │
  ├─ Phase 5 · ESCALATE (retries exhausted)
  │    worktree is reset → next target in the escalation list
  │    the new model gets the plan + the previous attempt's report
  │    the user is told (and may stop) · if the list runs out, stop and report
  │
  └─ Phase 6 · ACCEPT (on PASS)
       report → GATE 2: merge approval → merge + cleanup
```

### Phase 1 — Plan

Claude explores the repo (which files are affected, which conventions apply),
then puts **every real technical choice** in the plan to the user as a
multiple-choice question: the recommended option first, each option's cost
stated explicitly. No item is written into the plan before it is answered.

Examples of a "real technical choice": database access model, test runner, lint
chain, a new dependency, CI scope, file/module boundaries, error-handling
strategy. Not examples: variable names, ordering, formatting.

The plan is written to `<plan.dir>` as `YYYY-MM-DD-<slug>.md`, using
`templates/plan.md`:

```markdown
# <id/title>

## Task
<one sentence>

## Read first
- `path/a` — why
- `path/b` — why

## Steps
### 1. <step name>
- File: `path/to/file`
- Signature: `function foo(a: A, b: B): C`
- Behaviour: <what it does; what it returns in each case>
- Test vectors:
  | input | expected |
  |---|---|
  | ... | ... |

## Acceptance criteria
- [ ] <machine-verifiable statement>
- [ ] <machine-verifiable statement>

## Quality gates
<comes from the config; referenced in the plan>

## Do NOT
- Touch files not listed above
- Add dependencies
- Modify existing tests
```

**Acceptance-criterion rule:** every item must be verifiable either by a
command's output or by a single look at the diff. "The code should be clean" is
not a criterion; "`server/src/db/mongo.ts` throws `ConfigError` when
`MONGODB_URI` is unset" is.

### Phase 2 — Dispatch

The worktree is created as in v2. The prompt sent to the implementer is
**minimal** — the plan's contents are not pasted, only its path is given (v2's
token-saving decision is preserved):

```
## Task
<one sentence>

## Plan
`<path to the plan file>` — read this file and follow it exactly. The task is
not done until every acceptance criterion in it is met.

## Setup
- Read every AGENTS.md / CLAUDE.md in the repo first
- Follow the project's conventions

## Rules
- Only touch files named in the plan
- git add + git commit when done
- Commit message: type(scope): summary
```

Execution uses `run_in_background: true`; Claude can do other work until the
notification arrives. There is no polling.

### Phase 3 — Gate

Claude enters the worktree and **runs the commands in the `gates` array itself**,
in order, and reads the output. If one gate breaks, the rest still run (so a
single round collects every finding).

Then `git diff main..HEAD` is read and the acceptance criteria in the plan are
checked one by one. Result:

```
GATE REPORT
  lint       ✓
  typecheck  ✗  server/src/db/mongo.ts:42  TS2345: ...
  test       ✗  2 failing (mongo.test.ts: "throws on missing URI")
  build      — not run (not configured)

ACCEPTANCE CRITERIA
  ✓ 1. ...
  ✗ 3. ...  — no corresponding change in the diff
```

**An unconfigured gate does not count as skipped**, it is reported as "not run".
Unless every gate is ✓ **and** every criterion is ✓, the result is FAIL.

### Phase 4 — Feedback

A structured correction prompt is produced from the FAIL report: which
criterion/gate, which command output, which `file:line`, what is expected. No
generic phrasing ("fix the code").

It is sent to the same session with
`relay-run.sh --target <name> --worktree <path> "<feedback>" --continue`; the
model keeps its own context. Back to Phase 3. At most `max_retries` (default 3)
rounds.

### Phase 5 — Escalate

When retries are exhausted the worktree is reset — the new model must not
inherit the old one's half-finished work. The reset target is the base commit
the worktree was created from (recorded when the branch was created), not
`main`: the user may have moved `main` in the meantime and the handover must not
pull that in.

The next target in the `escalation` list is then given the plan **and** the
previous attempt's report ("these gates broke with this output, these approaches
were tried").

**Relationship between `default_target` and `escalation`:** the first attempt is
always `default_target` (or the target the user approved in Phase 1).
`escalation` gives the handover order; **targets already tried are skipped**. So
with `default_target: "cc"` and `escalation: ["cc", "oc"]` the order is
cc → oc, and cc is not tried twice.

The user is informed at handover and may stop. If the list runs out, the loop
stops and a full report is presented.

### Phase 6 — Accept

On PASS the report covers: files changed, each gate's output, how many rounds it
took, which target finished it. With the user's approval: merge plus worktree
and branch cleanup. Merge conflicts are not resolved automatically; they are
reported to the user.

### Escape hatch

`/relay --quick "<task>"` skips the plan phase and gives v2 behaviour. Writing a
plan for a one-liner is waste.

## 5. Config v3

```json
{
  "version": 3,
  "plan":   { "dir": "docs/relay-plans" },
  "targets": {
    "cc": { "preset": "commandcode", "model": "" },
    "oc": { "preset": "opencode",    "model": "" }
  },
  "default_target": "cc",
  "escalation": ["cc", "oc"],
  "max_retries": 3,
  "gates": [
    { "name": "lint",      "cmd": "npm run lint" },
    { "name": "typecheck", "cmd": "npm run typecheck" },
    { "name": "test",      "cmd": "npm test" }
  ],
  "worktree": { "enabled": true, "base_dir": ".worktrees" },
  "status_file": ".relay_status"
}
```

A **`flags.model`** slot is added to the preset schema — it did not exist in
v1/v2, and multi-model is impossible without it.

**Model selection stays with the user.** A target's `model` is empty by default:
the runner then omits the model flag entirely and the CLI runs whichever model
the user has selected in it. Pinning a model per target remains possible
(`"model": "opencode-go/kimi-k2.7-code"`) but is never the default, so ai-relay
does not silently override a choice made in the CLI. Escalation therefore
operates at the CLI level (commandcode → opencode) rather than the model level.

A **`flags.pre`** slot is also added, because the position of the model flag
differs per CLI. In CommandCode `-p` must be immediately followed by the prompt
(`-p, --print [query]`); in Opencode `run` is a **subcommand** and must come
first. A single `flags.prompt` slot cannot build both. Build order:

```
cli + pre + [model_flag model] + prompt_flags + PROMPT + [workdir_flag dir] + [continue] + [session id]
```

### Preset flags

Verified from `--help` output (2026-08-06; commandcode 1.13.0, opencode
current):

| | commandcode | opencode |
|---|---|---|
| pre | *(none)* | `run` |
| prompt | `-p` | *(positional)* |
| model | `-m` | `-m` |
| continue | `-c` | `-c` |
| session | `--session` | `-s` |
| permission | `--yolo` | `--auto` |
| directory | *(cwd — the runner already `cd`s)* | `--dir` |
| extra | `--skip-onboarding --max-turns 100` | *(none)* |

`presets/commandcode.json`:

```json
{
  "cli": "commandcode",
  "flags": {
    "pre": "",
    "model": "-m",
    "prompt": "--skip-onboarding --max-turns 100 --yolo -p",
    "continue": "-c",
    "session": "--session",
    "workdir": ""
  }
}
```

`presets/opencode.json`:

```json
{
  "cli": "opencode",
  "flags": {
    "pre": "run",
    "model": "-m",
    "prompt": "--auto",
    "continue": "-c",
    "session": "-s",
    "workdir": "--dir"
  }
}
```

The permission flags are not a convenience. The runner is invoked in the
background with no TTY attached: a CLI that stops to ask for permission hangs
forever rather than failing. Opencode has no narrower setting than `--auto`, and
CommandCode's `--permission-mode auto-accept` still prompts for non-edit
actions, which reproduces the hang. Isolation is provided by the worktree, the
gates Claude runs itself, and the merge approval.

The existing `kimi` / `codex` / `minimax` / `aider` presets are preserved; empty
`"pre": ""` and `"model": ""` fields are added to them so every preset carries
the full schema. Their command lines are unchanged.

## 6. Repo changes

| File | Status | Work |
|---|---|---|
| `SKILL.md` | new | Makes ai-relay a real Skill (previously only `~/.claude/commands/relay.md`) |
| `relay.md` | heavy revision | Phase 1 (plan) and Phase 3 (gate) added, handover logic written |
| `templates/plan.md` | new | The plan template from §4 |
| `relay-run.sh` | medium | `--target <name>` resolution, `flags.model` and `flags.pre` support, v3 config reading |
| `presets/commandcode.json` | new | §5 |
| `presets/opencode.json` | new | §5 |
| `.ai-relay.json.example` | changed | v3 schema |
| `install.sh` | medium | Global runner home, skill installation, gitignore fix |
| `test/run-tests.sh` | new | Dependency-free test runner |
| `test/fixtures/fake-cli` | new | Stub CLI that records its argv |
| `docs/2026-08-06-ai-relay-v3-design.md` | new | This document |
| `README.md` | changed | New flow |

### Backward compatibility

If the `version` field is absent, the config is treated as v2 and converted into
a single-element roster (`cli` + `flags` → one implicit target). The plan phase
engages only for `version: 3` configs; existing `/relay` users are not broken.
A test asserts that a v2 config still produces a byte-identical command line.

## 7. Edge cases

| Situation | Behaviour |
|---|---|
| Branch already exists | Timestamp appended to the slug |
| Relay crashed (non-zero exit) | Status FAILED, worktree preserved for inspection |
| Merge conflict | Not resolved automatically, reported to the user |
| Parallel relays over the same files | Warning if detected; no blocking (user's responsibility) |
| Worktree during handover | `git reset --hard` to the base commit the worktree was created from — no half-finished work is inherited |
| `escalation` contains `default_target` | Tried targets are skipped, no model is tried twice |
| Target not in the roster | Error, available targets are listed |
| `gates` empty/undefined | Gates are reported as "not run", never silently counted as passed |
| Model ignores the plan | Caught by the acceptance criteria in Phase 3 → Phase 4 |
| Plan file unreadable | The implementer errors; Claude passes the path as an absolute path |

## 8. Verification

Implementing this design in the ai-relay repo will produce the following
evidence:

1. One live relay round each with the `commandcode` and `opencode` presets (a
   small, real change) — showing the command was built and the model committed.
2. One round with a deliberately broken acceptance criterion — showing Phase 3
   reports FAIL and Phase 4 corrects it.
3. One round with `max_retries: 1` — showing the handover mechanism moves to the
   second target.
4. One round with a v2 config — showing backward compatibility is intact.

## 9. Relationship to host projects

This skill does **not replace** a project's GitHub issue/PR protocol, it
**operates underneath it**: the issue is claimed according to the project's
rules, `/relay` writes the plan for that work and drives it to a model, and the
PR is opened as the project requires. Embedding that protocol into the skill is
out of scope for v3.

The skill also fits a division of labour where Claude writes and reviews the
plan while the target model writes the code — that is exactly v3's default flow.
Because Claude taking over a stalled task was eliminated in decision 6, the
skill cannot violate that boundary.
