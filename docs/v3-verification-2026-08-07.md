# ai-relay v3 — live verification

**Date:** 2026-08-07
**Branch:** `feat/v3-plan-driven-multi-model`
**Scope:** the four proofs required by §8 of the v3 design.

Every round ran in a throwaway sandbox repo, never in a real project. The
sandbox is a git repo with `src/index.js`, a `node:test` suite, and
`gates: [{ "name": "test", "cmd": "npm test" }]`. Its baseline is green.

Both targets leave `model` empty, so the runner omits the model flag and each
CLI runs whichever model the user has selected in it:

```json
"targets": {
  "cc": { "preset": "commandcode", "model": "" },
  "oc": { "preset": "opencode",    "model": "" }
}
```

---

## Proof 1 — live relay round (commandcode)

**Command**

```bash
~/.ai-relay/relay-run.sh --target cc --worktree <sandbox>/.worktrees/relay-sum "<minimal prompt>"
```

Run in the background. Exit code 0, `.relay_status` = `DONE`.

**Observed**

| Check | Result |
|---|---|
| Worktree created | PASS — `relay/sum` branched from `cfcbb35` |
| CLI ran without hanging | PASS — no permission or trust prompt blocked the run |
| Model committed | PASS — `c491e3e feat(sum): export sum(a, b) and add unit test` |
| Phase 3 gate run by the reviewer | PASS — `npm test`: `# pass 4`, `# fail 0`, exit 0 |
| Acceptance criteria checked against the diff | PASS — 4/4 |
| `Do NOT` respected | PASS — `test/smoke.test.js` untouched |
| Phase 6 merge + cleanup | PASS — fast-forward, worktree removed, branch deleted, `npm test` still exits 0 on the merged branch |

**Diff produced by the model**

```diff
-module.exports = {};
+module.exports = { sum: (a, b) => a + b };
```

```js
// test/sum.test.js (new)
test('sum(2, 3) === 5',  () => { assert.strictEqual(sum(2, 3), 5); });
test('sum(-1, 1) === 0', () => { assert.strictEqual(sum(-1, 1), 0); });
test('sum(0, 0) === 0',  () => { assert.strictEqual(sum(0, 0), 0); });
```

**Independent criterion check** (not the model's word):

```
typeof sum = function
sum(2,3) = 5
sum(-1,1) = 0
sum(0,0) = 0
```

The model reported that all four criteria passed. Verified independently — the
report was accurate. The point of Phase 3 is that this is checked, not assumed.

**Note on non-interactive execution.** The runner is invoked with no TTY. The
`commandcode` preset passes `--yolo`, which also covers the initial project
trust prompt: a fresh worktree directory did not stall the run. No extra
`--trust` flag was needed.

**Result: PASS**

---

## Proof 2 — unmet acceptance criterion caught and corrected

**Setup note — the first attempt did not fail.** The plan for this round carried
an acceptance criterion (`product(a, b)`) that appeared only under *Acceptance
criteria*, never under *Steps*. The model implemented it anyway, and Phase 3
reported PASS on all five criteria:

```
# tests 10   # pass 10   # fail 0        (npm test exit 0)
typeof max = function    max(2,3) = 3
typeof product = function                ← not in Steps, only in the criteria
test/max.test.js = present   test/product.test.js = present
```

That is a finding worth keeping: the plan really does behave as a contract — the
prompt's "not done until every acceptance criterion is met" was honoured. But it
did not exercise the FAIL path, so the criterion was made genuinely unmet
instead: a sixth criterion (`divide` throwing `RangeError`) was appended to the
plan **after** the round had finished, so the model had never seen it. This is
the real-world case the mechanism exists for — a model that skips part of the
plan.

**Phase 3 report**

```
GATES
  test       PASS  (npm test, exit 0)
  lint       NOT RUN  (not configured)
  typecheck  NOT RUN  (not configured)

ACCEPTANCE
  PASS  1. npm test exits 0
  PASS  2. max is a function
  PASS  3. max(2,3) === 3
  PASS  4. test/max.test.js exists
  PASS  5. product is a function
  FAIL  6. divide throws RangeError("division by zero") on b=0
           — actual: missing; test/divide.test.js MISSING
```

Unconfigured gates are reported `NOT RUN`, not silently passed — as specified.

**Phase 4 correction prompt** (abridged) — names the criterion, the observed
state, and the expected behaviour; no "fix the code":

```
FAILED — acceptance criterion 6 in <plan path>
Observed:
  src/index.js — `typeof require("./src/index.js").divide` is "undefined"
  test/divide.test.js — file does not exist
Expected:
  1. src/index.js exports `divide(a, b)`:
     - throws `new RangeError("division by zero")` when `b === 0`
     - otherwise returns `a / b`
     - keep the existing sum, max and product exports intact
  2. test/divide.test.js asserts: divide(6,3)===2, divide(-6,3)===-2,
     divide(1,0) throws RangeError("division by zero")
PASSING, do not change: criteria 1-5.
```

Sent with `--continue`, so the model kept its own session.

**Phase 3 re-run — all green**

```
GATES
  test       PASS  (npm test, exit 0)   # tests 13  # pass 13  # fail 0

ACCEPTANCE
  PASS  1-6   (divide → RangeError: division by zero; divide(6,3)=2; divide(-6,3)=-2)
```

Two commits, one per round:

```
4c5fdaf feat(math): export max(a, b) and product(a, b) with tests
47e194b feat(math): export divide(a, b) with zero guard and test
```

The correction round touched only what the feedback named: `test/smoke.test.js`
and `test/sum.test.js` are unchanged across both rounds.

**Result: PASS**

---

## Proof 3 — escalation

**Setup.** `max_retries: 1`, `escalation: ["cc-tight", "oc"]`. The first target
is stalled realistically rather than artificially: `cc-tight` overrides the
preset's turn cap at the target level, which also exercises per-target flag
overrides.

```json
"cc-tight": {
  "preset": "commandcode",
  "model": "",
  "flags": { "prompt": "--skip-onboarding --max-turns 1 --yolo -p" }
}
```

The override took effect — the preset's `--max-turns 100` was replaced:

```
Warning: Reached maximum conversation turns (1). The response may be incomplete.
.relay_status = FAILED
```

**Round 1 (cc-tight) — Phase 3**

```
GATES
  test       PASS  (npm test, exit 0)

ACCEPTANCE
  FAIL  2. clamp is a function — actual: undefined
  FAIL  7. test/clamp.test.js exists — MISSING

git log d9a931d..HEAD → empty (no commit)
git status           → clean
```

**Round 2 (cc-tight, `--continue`)** — same turn cap, same result. `max_retries`
exhausted.

**Phase 5.1 — worktree reset.** The reset ran against the base commit recorded
at Phase 2 (`d9a931d`), not against `main`. Because the capped model never
committed, the reset had nothing to discard in this round, so the command was
also verified mechanically: a throwaway `wip:` commit was made in the worktree,
`git reset --hard d9a931d && git clean -fd` was run, and the commit and its
working-tree changes were gone (`git status` reported 0 changes).

**Phase 5.2 — target selection.**

```
escalation: cc-tight → oc
tried:      cc-tight
next:       oc          (already-tried targets skipped)
```

**Phase 5.3 — dispatch to `oc` with a handover note** stating which criteria
failed, with what observed values, what the previous model attempted, and that
the tree was reset so there is no half-finished work to inherit.

**Phase 5.4** — the user was told the task had been handed over and to which
target, and that they could stop the loop.

**Phase 3 after escalation — all green**

```
GATES
  test       PASS  (npm test, exit 0)   # tests 17  # pass 17  # fail 0

ACCEPTANCE
  PASS  1. npm test exits 0
  PASS  2. clamp is a function
  PASS  3. clamp(5,1,10) === 5
  PASS  4. clamp(-3,1,10) === 1
  PASS  5. clamp(42,1,10) === 10
  PASS  6. clamp(5,10,1) throws RangeError("lo must not exceed hi")
  PASS  7. test/clamp.test.js exists

previous exports preserved: sum:function max:function product:function divide:function
commit: cd9a0d6 feat(clamp): export clamp function with tests
```

This round is also the live `opencode` round required by §8 proof 1, so both
presets have now driven a real model end to end.

**Result: PASS**

---

## Proof 4 — v2 backward compatibility

**Setup.** The sandbox config was downgraded to the v2 shape — no `version`, no
`targets`, a single top-level `cli` and `flags`:

```json
{
  "cli": "commandcode",
  "flags": {
    "prompt": "--skip-onboarding --max-turns 100 --yolo -p",
    "continue": "-c",
    "session": "--session",
    "workdir": ""
  },
  "max_retries": 3,
  "status_file": ".relay_status",
  "worktree": { "enabled": true, "base_dir": ".worktrees" }
}
```

**Command line.** The same config was pointed at `test/fixtures/fake-cli` and
run with no `--target`, so the argv could be read exactly:

```
--skip-onboarding
--max-turns
100
--yolo
-p
legacy task
cwd=<worktree>
```

No `-m` was injected, and the run succeeded without `--target` — the config was
read as a single implicit target, as v2 did.

**Live round.** `relay-run.sh --worktree <wt> "<task>"`, no `--target`, no plan
file, no gates. `.relay_status` = `DONE`.

```diff
+// math helpers
 module.exports = {
   sum: (a, b) => a + b,
```

```
commit: 1d60a29 docs(index): add module comment
npm test exit = 0
exports: sum, max, product, divide, clamp   (behaviour unchanged)
```

The plan phase did not open, no gates ran, and the round ended at diff review
and the merge gate — the v2 flow. Merge and cleanup then behaved as before.

**Result: PASS**

---

## Summary

| # | Proof | Result |
|---|---|---|
| 1 | Live relay round, commandcode | PASS |
| 1 | Live relay round, opencode | PASS (inside proof 3) |
| 2 | Unmet criterion caught by Phase 3, fixed by Phase 4 | PASS |
| 3 | Escalation to the next target after retries | PASS |
| 4 | v2 config backward compatibility | PASS |

Rounds run: 7 model invocations across 4 branches, all in a throwaway sandbox.

### What the rounds changed about the design

- **`--yolo` also covers the initial project trust prompt.** A fresh worktree
  directory did not stall commandcode, so no separate `--trust` flag was added
  to the preset. This was the main open risk before the live rounds.
- **The plan really does act as a contract.** In proof 2 the model implemented an
  acceptance criterion that appeared nowhere in the plan's *Steps* — the
  "not done until every criterion is met" instruction was enough. Forcing a FAIL
  required a criterion the model had never seen.
- **Per-target flag overrides work and are useful.** Proof 3 stalled its first
  target with a target-level `--max-turns 1`, overriding the preset's `100`.

### Not covered by these rounds

- Merge conflicts (Phase 6 reports rather than resolves them) — not exercised;
  all four merges were fast-forward.
- Exhausting the whole `escalation` list — proof 3 succeeded on the second
  target, so the "list exhausted, stop and report" path was not reached.
- Parallel relays over overlapping files — the warning path was not exercised.
- `lint` and `typecheck` gates — the sandbox configured only `test`. They were
  reported `NOT RUN`, which is itself the specified behaviour for an
  unconfigured gate.
